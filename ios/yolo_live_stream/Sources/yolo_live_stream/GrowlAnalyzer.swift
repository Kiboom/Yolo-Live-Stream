import Flutter
import TensorFlowLite
import WebRTC
import flutter_webrtc
import os

final class GrowlAnalyzer: NSObject, FlutterStreamHandler, ExternalAudioProcessingDelegate {
  private static let modelSampleRate = 16000.0
  private static let windowLength = 15600
  private static let hopLength = 8000
  private static let growlingIndex = 74

  private let modelPath: String?
  private let inferenceQueue = DispatchQueue(label: "yolo_live_stream.growl_analyzer", qos: .userInitiated)
  private var interpreter: Interpreter?
  private var eventSink: FlutterEventSink?
  private var isAttached = false

  // Shared between the WebRTC audio thread and the inference queue.
  private let lock: UnsafeMutablePointer<os_unfair_lock> = {
    let pointer = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    pointer.initialize(to: os_unfair_lock())
    return pointer
  }()
  private var isOutputMuted = false
  private var isInferring = false
  // Bumped by every start and stop so late model loads and inference results from an old session are dropped.
  private var session = 0

  // Audio thread only, except `window` which the inference queue reads while `isInferring` is true.
  private var inputSampleRate = 48000.0
  private var ring = [Float](repeating: 0, count: GrowlAnalyzer.windowLength)
  private var ringIndex = 0
  private var filledCount = 0
  private var samplesSinceInference = 0
  private var resampleSum: Float = 0
  private var resampleCount = 0
  private var resamplePhase = 0.0
  private var window = [Float](repeating: 0, count: GrowlAnalyzer.windowLength)

  init(registrar: FlutterPluginRegistrar) {
    let key = registrar.lookupKey(forAsset: "assets/yamnet.tflite", fromPackage: "yolo_live_stream")
    modelPath = Bundle.main.path(forResource: key, ofType: nil)
    super.init()
    let methodChannel = FlutterMethodChannel(name: "yolo_live_stream/growl_analyzer", binaryMessenger: registrar.messenger())
    methodChannel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    FlutterEventChannel(name: "yolo_live_stream/growl_analyzer/scores", binaryMessenger: registrar.messenger()).setStreamHandler(self)
  }

  deinit {
    lock.deallocate()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "start":
      start(muteOutput: arguments?["muteOutput"] as? Bool ?? false, result: result)
    case "setOutputMuted":
      setOutputMuted(arguments?["muted"] as? Bool ?? false)
      result(nil)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(muteOutput: Bool, result: @escaping FlutterResult) {
    guard let modelPath else {
      result(FlutterError(code: "MODEL_NOT_FOUND", message: "assets/yamnet.tflite is missing", details: nil))
      return
    }
    let token = nextSession()
    inferenceQueue.async { [weak self] in
      guard let self else { return }
      do {
        if self.interpreter == nil {
          let interpreter = try Interpreter(modelPath: modelPath)
          try interpreter.resizeInput(at: 0, to: [GrowlAnalyzer.windowLength])
          try interpreter.allocateTensors()
          self.interpreter = interpreter
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "MODEL_LOAD_FAILED", message: error.localizedDescription, details: nil))
        }
        return
      }
      DispatchQueue.main.async {
        guard token == self.currentSession() else {
          result(nil)
          return
        }
        self.setOutputMuted(muteOutput)
        if !self.isAttached {
          AudioManager.sharedInstance().renderPreProcessingAdapter.addProcessing(self)
          self.isAttached = true
        }
        result(nil)
      }
    }
  }

  private func setOutputMuted(_ muted: Bool) {
    os_unfair_lock_lock(lock)
    isOutputMuted = muted
    os_unfair_lock_unlock(lock)
  }

  private func stop() {
    _ = nextSession()
    if isAttached {
      // removeProcessing waits for the adapter lock, so no audio callback is running when the state below is cleared.
      AudioManager.sharedInstance().renderPreProcessingAdapter.removeProcessing(self)
      isAttached = false
    }
    setOutputMuted(false)
    ringIndex = 0
    filledCount = 0
    samplesSinceInference = 0
    resampleSum = 0
    resampleCount = 0
    resamplePhase = 0
  }

  private func nextSession() -> Int {
    os_unfair_lock_lock(lock)
    session += 1
    let value = session
    os_unfair_lock_unlock(lock)
    return value
  }

  private func currentSession() -> Int {
    os_unfair_lock_lock(lock)
    let value = session
    os_unfair_lock_unlock(lock)
    return value
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func audioProcessingInitialize(withSampleRate sampleRateHz: Int, channels: Int) {
    inputSampleRate = Double(sampleRateHz)
    resampleSum = 0
    resampleCount = 0
    resamplePhase = 0
  }

  func audioProcessingProcess(_ audioBuffer: RTCAudioBuffer) {
    let frames = audioBuffer.frames
    let channels = audioBuffer.channels
    guard frames > 0, channels > 0 else { return }
    let step = inputSampleRate / GrowlAnalyzer.modelSampleRate
    let source = audioBuffer.rawBuffer(forChannel: 0)
    for frame in 0..<frames {
      // WebRTC keeps samples as floats in the int16 range.
      resampleSum += source[frame] / 32768
      resampleCount += 1
      resamplePhase += 1
      if resamplePhase >= step {
        let sample = max(-1, min(1, resampleSum / Float(resampleCount)))
        while resamplePhase >= step {
          appendSample(sample)
          resamplePhase -= step
        }
        resampleSum = 0
        resampleCount = 0
      }
    }

    let isWindowReady = filledCount == GrowlAnalyzer.windowLength && samplesSinceInference >= GrowlAnalyzer.hopLength
    os_unfair_lock_lock(lock)
    let muted = isOutputMuted
    let shouldInfer = isWindowReady && !isInferring
    if shouldInfer { isInferring = true }
    let token = session
    os_unfair_lock_unlock(lock)
    if shouldInfer {
      samplesSinceInference = 0
      copyWindow()
      inferenceQueue.async { [weak self] in self?.runInference(session: token) }
    }
    if muted {
      for channel in 0..<channels {
        audioBuffer.rawBuffer(forChannel: channel).update(repeating: 0, count: frames)
      }
    }
  }

  func audioProcessingRelease() {}

  private func appendSample(_ sample: Float) {
    ring[ringIndex] = sample
    ringIndex = (ringIndex + 1) % GrowlAnalyzer.windowLength
    filledCount = min(filledCount + 1, GrowlAnalyzer.windowLength)
    samplesSinceInference += 1
  }

  private func copyWindow() {
    let tail = GrowlAnalyzer.windowLength - ringIndex
    window.withUnsafeMutableBufferPointer { destination in
      ring.withUnsafeBufferPointer { source in
        destination.baseAddress!.update(from: source.baseAddress! + ringIndex, count: tail)
        (destination.baseAddress! + tail).update(from: source.baseAddress!, count: ringIndex)
      }
    }
  }

  private func runInference(session token: Int) {
    defer {
      os_unfair_lock_lock(lock)
      isInferring = false
      os_unfair_lock_unlock(lock)
    }
    guard let interpreter else { return }
    do {
      let input = window.withUnsafeBufferPointer { Data(buffer: $0) }
      try interpreter.copy(input, toInputAt: 0)
      try interpreter.invoke()
      let output = try interpreter.output(at: 0)
      let score = output.data.withUnsafeBytes { Double($0.bindMemory(to: Float32.self)[GrowlAnalyzer.growlingIndex]) }
      DispatchQueue.main.async { [weak self] in
        guard let self, token == self.currentSession() else { return }
        self.eventSink?(score)
      }
    } catch {
      NSLog("GrowlAnalyzer inference failed: \(error)")
    }
  }
}
