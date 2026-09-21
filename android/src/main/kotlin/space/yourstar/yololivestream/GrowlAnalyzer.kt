package space.yourstar.yololivestream

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cloudwebrtc.webrtc.FlutterWebRTCPlugin
import com.cloudwebrtc.webrtc.audio.AudioProcessingAdapter
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import com.google.ai.edge.litert.TensorBuffer
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal const val YAMNET_SAMPLE_RATE = 16000
internal const val YAMNET_WINDOW_SAMPLES = 15600
internal const val YAMNET_HOP_SAMPLES = 8000
internal const val YAMNET_GROWLING_INDEX = 74

/** Converts one 10 ms WebRTC frame (FloatS16 range) to 16 kHz mono floats in -1..1. Returns the number written to [out]. */
internal fun resampleTo16k(src: FloatArray, count: Int, out: FloatArray): Int {
    val outCount = YAMNET_SAMPLE_RATE / 100
    if (count <= 0) return 0
    if (count % outCount == 0) {
        val ratio = count / outCount
        for (i in 0 until outCount) {
            var sum = 0f
            for (j in 0 until ratio) sum += src[i * ratio + j]
            out[i] = (sum / ratio / 32768f).coerceIn(-1f, 1f)
        }
    } else {
        val step = count.toFloat() / outCount
        for (i in 0 until outCount) {
            val pos = i * step
            val left = pos.toInt().coerceAtMost(count - 1)
            val right = (left + 1).coerceAtMost(count - 1)
            val frac = pos - left
            out[i] = ((src[left] * (1 - frac) + src[right] * frac) / 32768f).coerceIn(-1f, 1f)
        }
    }
    return outCount
}

internal class GrowlSampleWindow {
    private val ring = FloatArray(YAMNET_WINDOW_SAMPLES)
    private var writeIndex = 0
    private var filled = 0
    private var sinceLastHop = 0

    /** Returns true when the window is full and at least one hop of new samples has arrived since the last true. */
    fun append(samples: FloatArray, count: Int): Boolean {
        for (i in 0 until count) {
            ring[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % YAMNET_WINDOW_SAMPLES
        }
        filled = (filled + count).coerceAtMost(YAMNET_WINDOW_SAMPLES)
        sinceLastHop += count
        if (filled < YAMNET_WINDOW_SAMPLES || sinceLastHop < YAMNET_HOP_SAMPLES) return false
        sinceLastHop = 0
        return true
    }

    fun snapshot(): FloatArray {
        val out = FloatArray(YAMNET_WINDOW_SAMPLES)
        val tail = YAMNET_WINDOW_SAMPLES - writeIndex
        System.arraycopy(ring, writeIndex, out, 0, tail)
        System.arraycopy(ring, 0, out, tail, writeIndex)
        return out
    }

    fun clear() {
        writeIndex = 0
        filled = 0
        sinceLastHop = 0
    }
}

class GrowlAnalyzer(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    AudioProcessingAdapter.ExternalAudioFrameProcessing {

    private val methodChannel = MethodChannel(messenger, "yolo_live_stream/growl_analyzer")
    private val eventChannel = EventChannel(messenger, "yolo_live_stream/growl_analyzer/scores")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val inferenceExecutor = Executors.newSingleThreadExecutor()
    private val inferenceBusy = AtomicBoolean(false)

    private var eventSink: EventChannel.EventSink? = null
    private var attachedAdapter: AudioProcessingAdapter? = null

    @Volatile private var outputMuted = false
    @Volatile private var running = false

    // Touched only on the WebRTC audio thread.
    private val window = GrowlSampleWindow()
    private var frameScratch = FloatArray(480)
    private val resampled = FloatArray(YAMNET_SAMPLE_RATE / 100)

    // Touched only on the inference thread.
    private var model: CompiledModel? = null
    private var inputBuffers: List<TensorBuffer>? = null
    private var outputBuffers: List<TensorBuffer>? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val adapter = FlutterWebRTCPlugin.sharedSingleton?.audioProcessingController?.renderPreProcessing
                if (adapter == null) {
                    result.error("UNAVAILABLE", "flutter_webrtc peer connection factory is not initialized", null)
                    return
                }
                outputMuted = call.argument<Boolean>("muteOutput") ?: false
                if (attachedAdapter == null) {
                    running = true
                    adapter.addProcessor(this)
                    attachedAdapter = adapter
                }
                result.success(null)
            }
            "setOutputMuted" -> {
                outputMuted = call.argument<Boolean>("muted") ?: false
                result.success(null)
            }
            "stop" -> {
                detach()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun initialize(sampleRateHz: Int, numChannels: Int) {}

    override fun reset(newRate: Int) {}

    // libwebrtc passes channel 0 of the full-band render AudioBuffer: numFrames native-order floats in FloatS16 range.
    override fun process(numBands: Int, numFrames: Int, buffer: ByteBuffer) {
        if (!running) return
        val floats = buffer.order(ByteOrder.nativeOrder()).asFloatBuffer()
        val count = minOf(numFrames, floats.remaining())
        if (frameScratch.size < count) frameScratch = FloatArray(count)
        floats.get(frameScratch, 0, count)
        if (outputMuted) {
            floats.rewind()
            for (i in 0 until count) floats.put(i, 0f)
        }
        val written = resampleTo16k(frameScratch, count, resampled)
        if (window.append(resampled, written) && inferenceBusy.compareAndSet(false, true)) {
            val input = window.snapshot()
            inferenceExecutor.execute { runInference(input) }
        }
    }

    private fun runInference(input: FloatArray) {
        try {
            val compiled = model ?: loadModel()
            val inputs = inputBuffers!!
            val outputs = outputBuffers!!
            inputs[0].writeFloat(input)
            compiled.run(inputs, outputs)
            val score = outputs[0].readFloat()[YAMNET_GROWLING_INDEX].toDouble()
            mainHandler.post { if (running) eventSink?.success(score) }
        } catch (e: Throwable) {
            Log.w(TAG, "YAMNet inference failed: ${e.message}")
        } finally {
            inferenceBusy.set(false)
        }
    }

    private fun loadModel(): CompiledModel {
        val assetPath = FlutterInjector.instance().flutterLoader()
            .getLookupKeyForAsset("assets/yamnet.tflite", "yolo_live_stream")
        val compiled = CompiledModel.create(context.assets, assetPath, CompiledModel.Options(Accelerator.CPU))
        inputBuffers = compiled.createInputBuffers()
        outputBuffers = compiled.createOutputBuffers()
        model = compiled
        return compiled
    }

    private fun detach() {
        running = false
        outputMuted = false
        attachedAdapter?.removeProcessor(this)
        attachedAdapter = null
        window.clear()
    }

    fun dispose() {
        detach()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        inferenceExecutor.execute {
            inputBuffers?.forEach { runCatching { it.close() } }
            outputBuffers?.forEach { runCatching { it.close() } }
            runCatching { model?.close() }
            model = null
        }
        inferenceExecutor.shutdown()
    }

    private companion object {
        const val TAG = "GrowlAnalyzer"
    }
}
