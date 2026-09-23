import "dart:async";
import "dart:typed_data";

import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";
import "package:yolo_live_stream/yolo_live_stream.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel growlChannel = MethodChannel("yolo_live_stream/growl_analyzer");
  const MethodChannel webRtcChannel = MethodChannel("FlutterWebRTC.Method");
  final List<MethodCall> growlCalls = [];
  bool isGrowlStartFailing = false;
  setUp(() {
    growlCalls.clear();
    isGrowlStartFailing = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(webRtcChannel, (MethodCall call) async => {"textureId": 1});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(growlChannel, (MethodCall call) async {
      growlCalls.add(call);
      if (call.method == "start" && isGrowlStartFailing) {
        throw PlatformException(code: "start_failed");
      }
      return null;
    });
  });
  test("keeps the remote audio track enabled when growl detection is on and the speaker is off", () async {
    final LiveStreamingController controller = LiveStreamingController(
      enableSpeaker: false,
      enableDetection: false,
      enableGrowlDetection: true,
    );
    await controller.prepare();
    controller.setSpeakerEnabled(false);
    expect(controller.isSpeakerEnabled, false);
    expect(controller.connection.isGrowlDetectionEnabled, true);
    expect(growlCalls.single.method, "setOutputMuted");
    expect(growlCalls.single.arguments, {"muted": true});
  });
  test("mutes by disabling the track when growl detection is off", () async {
    final LiveStreamingController controller = LiveStreamingController(
      enableSpeaker: true,
      enableDetection: false,
    );
    await controller.prepare();
    controller.setSpeakerEnabled(false);
    expect(controller.isSpeakerEnabled, false);
    expect(controller.connection.isGrowlDetectionEnabled, false);
    expect(growlCalls, isEmpty);
  });
  test("calls onDogRiskAnalyzed with a report when a person and a dog are detected", () async {
    final List<DogRiskReport> reports = [];
    final LiveStreamingController controller = LiveStreamingController(
      onDogRiskAnalyzed: reports.add,
    );
    await controller.prepare();
    controller.handleDetected([
      YOLOResult(
        classIndex: 0,
        className: "person",
        confidence: 0.9,
        boundingBox: const Rect.fromLTRB(0, 0, 100, 200),
        normalizedBox: const Rect.fromLTRB(0.1, 0.2, 0.3, 0.8),
      ),
      YOLOResult(
        classIndex: 16,
        className: "dog",
        confidence: 0.9,
        boundingBox: const Rect.fromLTRB(120, 100, 220, 200),
        normalizedBox: const Rect.fromLTRB(0.35, 0.5, 0.55, 0.8),
      ),
    ]);
    expect(reports, hasLength(1));
    expect(controller.dogRiskReport, same(reports.single));
    expect(reports.single.distance, isNotNull);
  });
  test("passes each frame's detections to the injected dog risk analyzer", () async {
    final FakeDogRiskAnalyzer analyzer = FakeDogRiskAnalyzer();
    final List<DogRiskReport> reports = [];
    final LiveStreamingController controller = LiveStreamingController(
      dogRiskAnalyzer: analyzer,
      onDogRiskAnalyzed: reports.add,
    );
    await controller.prepare();
    final List<YOLOResult> frame = [
      YOLOResult(
        classIndex: 16,
        className: "dog",
        confidence: 0.9,
        boundingBox: const Rect.fromLTRB(120, 100, 220, 200),
        normalizedBox: const Rect.fromLTRB(0.35, 0.5, 0.55, 0.8),
      ),
    ];
    controller.handleDetected(frame);
    expect(analyzer.receivedSignals.single.detections, same(frame));
    expect(analyzer.receivedSignals.single.sound, isNull);
    expect(controller.dogRiskReport, same(reports.single));
  });
  test("judges dog risk on sound scores even when detection is off", () async {
    const EventChannel scoresChannel = EventChannel("yolo_live_stream/growl_analyzer/scores");
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      scoresChannel,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) => events.success(Float32List(SoundScores.labels.length)),
      ),
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(scoresChannel, null));
    final FakeDogRiskAnalyzer analyzer = FakeDogRiskAnalyzer();
    final List<DogRiskReport> reports = [];
    final LiveStreamingController controller = LiveStreamingController(
      enableDetection: false,
      enableGrowlDetection: true,
      dogRiskAnalyzer: analyzer,
      onDogRiskAnalyzed: reports.add,
    );
    await controller.prepare();
    await controller.startGrowlDetection();
    for (int i = 0; i < 5 && reports.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(analyzer.receivedSignals.single.detections, isEmpty);
    expect(analyzer.receivedSignals.single.dogPoses, isNull);
    expect(analyzer.receivedSignals.single.sound, isNotNull);
    expect(controller.dogRiskReport, same(reports.single));
  });
  test("clears the report and reports the analyzer error once while it keeps failing", () async {
    final FakeDogRiskAnalyzer analyzer = FakeDogRiskAnalyzer();
    final List<String> errors = [];
    final LiveStreamingController controller = LiveStreamingController(
      dogRiskAnalyzer: analyzer,
      onError: errors.add,
    );
    await controller.prepare();
    int notifyCount = 0;
    controller.addListener(() => notifyCount++);
    controller.handleDetected(const []);
    expect(controller.dogRiskReport, isNotNull);
    analyzer.isFailing = true;
    controller.handleDetected(const []);
    controller.handleDetected(const []);
    expect(controller.dogRiskReport, isNull);
    expect(errors, ["위험도 판정 실패: Bad state: analyze failed"]);
    expect(notifyCount, 3);
  });
  test("reports the analyzer error again when it fails after a success", () async {
    final FakeDogRiskAnalyzer analyzer = FakeDogRiskAnalyzer()..isFailing = true;
    final List<String> errors = [];
    final LiveStreamingController controller = LiveStreamingController(
      dogRiskAnalyzer: analyzer,
      onError: errors.add,
    );
    await controller.prepare();
    controller.handleDetected(const []);
    analyzer.isFailing = false;
    controller.handleDetected(const []);
    analyzer.isFailing = true;
    controller.handleDetected(const []);
    expect(errors, hasLength(2));
    expect(controller.dogRiskReport, isNull);
  });
  test("reports the analyzer error again when it still fails after a stop and a new receiver start", () async {
    final FakeDogRiskAnalyzer analyzer = FakeDogRiskAnalyzer()..isFailing = true;
    final List<String> errors = [];
    final LiveStreamingController controller = LiveStreamingController(
      enableDetection: false,
      dogRiskAnalyzer: analyzer,
      onError: errors.add,
    );
    await controller.prepare();
    controller.handleDetected(const []);
    controller.handleDetected(const []);
    await controller.stop();
    await controller.startAsReceiver("127.0.0.1");
    controller.handleDetected(const []);
    expect(errors.where((String message) => message.startsWith("위험도 판정 실패")), hasLength(2));
  });
  test("resets the injected analyzer before a receiver starts and on stop", () async {
    final FakeDogRiskAnalyzer analyzer = FakeDogRiskAnalyzer();
    final LiveStreamingController controller = LiveStreamingController(
      enableDetection: false,
      dogRiskAnalyzer: analyzer,
      onError: (String message) {},
    );
    await controller.startAsReceiver("127.0.0.1");
    expect(analyzer.resetCount, 1);
    await controller.stop();
    expect(analyzer.resetCount, 2);
  });
  test("restores the remote audio track to the speaker setting when the native growl start fails", () async {
    isGrowlStartFailing = true;
    final List<String> errors = [];
    final LiveStreamingController controller = LiveStreamingController(
      enableSpeaker: false,
      enableDetection: false,
      enableGrowlDetection: true,
      onError: errors.add,
    );
    await controller.prepare();
    await controller.startGrowlDetection();
    expect(controller.connection.isGrowlDetectionEnabled, false);
    expect(controller.connection.isRemoteAudioEnabled, false);
    expect(errors, hasLength(1));
    controller.setSpeakerEnabled(true);
    expect(growlCalls.map((MethodCall call) => call.method), ["start"]);
  });
  test("drops a frame result that arrives after stop", () async {
    final Completer<ByteBuffer> frameCompleter = Completer<ByteBuffer>();
    final List<List<YOLOResult>> detectedFrames = [];
    final YoloAnalyzer analyzer = YoloAnalyzer(
      onUpdate: () {},
      onDetected: detectedFrames.add,
      getRemoteTrack: () => FakeVideoTrack(frameCompleter.future),
    );
    final Future<void> analysis = analyzer.analyzeFrame();
    analyzer.stop();
    frameCompleter.complete(Uint8List(4).buffer);
    await analysis;
    expect(detectedFrames, isEmpty);
    expect(analyzer.detections, isEmpty);
    expect(analyzer.debugStatus, "대기 중");
  });
  test("does not start the analysis timer when stop is called while the model loads", () async {
    const MethodChannel yoloChannel = MethodChannel("yolo_single_image_channel");
    final Completer<void> loadGate = Completer<void>();
    final Completer<void> loadStarted = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(yoloChannel, (MethodCall call) async {
      if (call.method != "loadModel") return <String, dynamic>{};
      loadStarted.complete();
      await loadGate.future;
      return true;
    });
    int updateCount = 0;
    final YoloAnalyzer analyzer = YoloAnalyzer(
      onUpdate: () => updateCount++,
      getRemoteTrack: () => null,
      customModelPath: "/models/detect.tflite",
      interval: const Duration(milliseconds: 10),
    );
    final Future<void> starting = analyzer.start();
    await loadStarted.future;
    analyzer.stop();
    final int stoppedUpdateCount = updateCount;
    loadGate.complete();
    await starting;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(updateCount, stoppedUpdateCount);
    expect(analyzer.debugStatus, "모델 로딩 중...");
  });
  test("keeps detecting without dog poses and reports the error once when the pose model fails to load", () async {
    const MethodChannel yoloChannel = MethodChannel("yolo_single_image_channel");
    final List<MethodChannel> poseChannels = [];
    int posePredictCount = 0;
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(yoloChannel, null);
      for (final MethodChannel poseChannel in poseChannels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(poseChannel, null);
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(yoloChannel, (MethodCall call) async {
      // 포즈 모델은 useMultiInstance라 createInstance로 받은 instanceId가 붙은 채널을 따로 쓴다.
      if (call.method == "createInstance") {
        final MethodChannel poseChannel = MethodChannel("yolo_single_image_channel_${(call.arguments as Map)["instanceId"]}");
        poseChannels.add(poseChannel);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(poseChannel, (MethodCall call) async {
          if (call.method == "loadModel") throw PlatformException(code: "MODEL_NOT_FOUND");
          if (call.method == "predictSingleImage") posePredictCount++;
          return <String, dynamic>{};
        });
        return null;
      }
      if (call.method == "loadModel") return true;
      if (call.method == "predictSingleImage") {
        return {
          "boxes": [
            {"class": "dog", "confidence": 0.9, "x1": 120, "y1": 100, "x2": 220, "y2": 200},
          ],
        };
      }
      return <String, dynamic>{};
    });
    final List<String> errors = [];
    final List<List<YOLOResult>> detectedFrames = [];
    final YoloAnalyzer analyzer = YoloAnalyzer(
      onUpdate: () {},
      onDetected: detectedFrames.add,
      onError: errors.add,
      getRemoteTrack: () => FakeVideoTrack(Future<ByteBuffer>.value(Uint8List(4).buffer)),
      customModelPath: "/models/detect.tflite",
      dogPoseModelPath: "/models/dog_pose.tflite",
      interval: const Duration(milliseconds: 10),
    );
    await analyzer.start();
    for (int i = 0; i < 50 && detectedFrames.length < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(detectedFrames.length, greaterThanOrEqualTo(3));
    expect(detectedFrames.last.single.className, "dog");
    expect(analyzer.dogPoses, isNull);
    expect(posePredictCount, 0);
    expect(errors, hasLength(1));
    expect(errors.single, startsWith("포즈 모델 로드 실패: "));
    analyzer.stop();
    expect(analyzer.dogPoses, isNull);
  });
  test("still throws when the detect model fails to load", () async {
    const MethodChannel yoloChannel = MethodChannel("yolo_single_image_channel");
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(yoloChannel, null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(yoloChannel, (MethodCall call) async {
      if (call.method == "loadModel") throw PlatformException(code: "MODEL_NOT_FOUND");
      return <String, dynamic>{};
    });
    final List<String> errors = [];
    final YoloAnalyzer analyzer = YoloAnalyzer(
      onUpdate: () {},
      onError: errors.add,
      getRemoteTrack: () => null,
      customModelPath: "/models/detect.tflite",
      dogPoseModelPath: "/models/dog_pose.tflite",
    );
    await expectLater(analyzer.start(), throwsA(isA<ModelLoadingException>()));
    expect(errors, isEmpty);
  });
}

class FakeVideoTrack implements MediaStreamTrack {
  FakeVideoTrack(this.frame);

  final Future<ByteBuffer> frame;

  @override
  Future<ByteBuffer> captureFrame() => frame;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDogRiskAnalyzer extends DogRiskAnalyzer {
  final List<DogRiskSignals> receivedSignals = [];
  bool isFailing = false;
  int resetCount = 0;

  @override
  DogRiskReport analyze(DogRiskSignals signals) {
    receivedSignals.add(signals);
    if (isFailing) throw StateError("analyze failed");
    return const DogRiskReport(level: DogRiskLevel.low);
  }

  @override
  void reset() => resetCount++;
}
