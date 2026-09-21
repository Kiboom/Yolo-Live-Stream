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
}

class FakeVideoTrack implements MediaStreamTrack {
  FakeVideoTrack(this.frame);

  final Future<ByteBuffer> frame;

  @override
  Future<ByteBuffer> captureFrame() => frame;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
