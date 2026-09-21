import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:yolo_live_stream/yolo_live_stream.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel growlChannel = MethodChannel("yolo_live_stream/growl_analyzer");
  const MethodChannel webRtcChannel = MethodChannel("FlutterWebRTC.Method");
  final List<MethodCall> growlCalls = [];
  setUp(() {
    growlCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(webRtcChannel, (MethodCall call) async => {"textureId": 1});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(growlChannel, (MethodCall call) async {
      growlCalls.add(call);
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
}
