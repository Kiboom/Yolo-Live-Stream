import "dart:typed_data";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:yolo_live_stream/src/growl_analyzer.dart";
import "package:yolo_live_stream/src/sound_scores.dart";

const MethodChannel growlChannel = MethodChannel("yolo_live_stream/growl_analyzer");
const EventChannel scoresChannel = EventChannel("yolo_live_stream/growl_analyzer/scores");
const int growlingIndex = 74;

Float32List createGrowlingScores(double growlScore) => Float32List(SoundScores.labels.length)..[growlingIndex] = growlScore;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final List<MethodCall> growlCalls = [];
  final List<SoundScores> receivedScores = [];
  MockStreamHandlerEventSink? scoresSink;
  int updateCount = 0;
  setUp(() {
    growlCalls.clear();
    receivedScores.clear();
    scoresSink = null;
    updateCount = 0;
    messenger.setMockMethodCallHandler(growlChannel, (MethodCall call) async {
      growlCalls.add(call);
      return null;
    });
    messenger.setMockStreamHandler(
      scoresChannel,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          scoresSink = events;
        },
      ),
    );
  });

  Future<GrowlAnalyzer> startAnalyzer() async {
    final GrowlAnalyzer analyzer = GrowlAnalyzer(
      onUpdate: () => updateCount++,
      onSoundScores: receivedScores.add,
    );
    await analyzer.start(muteOutput: true);
    return analyzer;
  }

  Future<void> sendScores(Object? event) async {
    scoresSink?.success(event);
    await pumpEventQueue();
  }

  test("start는 스트림을 구독하고 muteOutput을 네이티브에 넘긴다", () async {
    await startAnalyzer();
    expect(scoresSink, isNotNull);
    expect(growlCalls.single.method, "start");
    expect(growlCalls.single.arguments, {"muteOutput": true});
  });

  test("Float32List 점수가 오면 soundScores를 바꾸고 onSoundScores와 onUpdate를 부른다", () async {
    final GrowlAnalyzer analyzer = await startAnalyzer();
    expect(analyzer.soundScores, isNull);
    await sendScores(createGrowlingScores(0.75));
    expect(analyzer.soundScores?["Growling"], 0.75);
    expect(receivedScores, hasLength(1));
    expect(receivedScores.single, same(analyzer.soundScores));
    expect(updateCount, 1);
    await sendScores(createGrowlingScores(0.25));
    expect(analyzer.soundScores?["Growling"], 0.25);
    expect(receivedScores, hasLength(2));
    expect(updateCount, 2);
  });

  test("Float64List나 숫자 리스트로 와도 Float32List로 바꿔 반영한다", () async {
    final GrowlAnalyzer analyzer = await startAnalyzer();
    await sendScores(Float64List(SoundScores.labels.length)..[growlingIndex] = 0.5);
    expect(analyzer.soundScores?.scores, isA<Float32List>());
    expect(analyzer.soundScores?["Growling"], 0.5);
    await sendScores([for (int index = 0; index < SoundScores.labels.length; index++) index == growlingIndex ? 0.25 : 0]);
    expect(analyzer.soundScores?.scores, isA<Float32List>());
    expect(analyzer.soundScores?["Growling"], 0.25);
    expect(receivedScores, hasLength(2));
  });

  test("길이가 521이 아니거나 숫자가 아닌 값이 섞인 이벤트는 무시하고 다음 이벤트는 계속 받는다", () async {
    final GrowlAnalyzer analyzer = await startAnalyzer();
    await sendScores(Float32List(SoundScores.labels.length - 1));
    await sendScores(Float32List(SoundScores.labels.length + 1));
    await sendScores([for (int index = 0; index < SoundScores.labels.length; index++) index == 0 ? "loud" : 0.0]);
    await sendScores(0.9);
    await sendScores(null);
    expect(analyzer.soundScores, isNull);
    expect(receivedScores, isEmpty);
    expect(updateCount, 0);
    await sendScores(createGrowlingScores(0.75));
    expect(analyzer.soundScores?["Growling"], 0.75);
    expect(receivedScores, hasLength(1));
  });

  test("stop하면 soundScores가 null이 되고, 그 뒤에 온 점수는 반영하지 않는다", () async {
    final GrowlAnalyzer analyzer = await startAnalyzer();
    await sendScores(createGrowlingScores(0.75));
    await analyzer.stop();
    expect(analyzer.soundScores, isNull);
    expect(growlCalls.map((MethodCall call) => call.method), ["start", "stop"]);
    final int stoppedUpdateCount = updateCount;
    await sendScores(createGrowlingScores(0.5));
    expect(analyzer.soundScores, isNull);
    expect(receivedScores, hasLength(1));
    expect(updateCount, stoppedUpdateCount);
    // 구독이 없을 때 온 메시지는 채널 버퍼에 남아 다음 테스트의 구독으로 넘어가므로 비운다.
    messenger.setMessageHandler(scoresChannel.name, (ByteData? message) async => null);
    await pumpEventQueue();
    messenger.setMessageHandler(scoresChannel.name, null);
  });

  test("stop 도중 네이티브가 보낸 점수는 다음 start에도 반영하지 않는다", () async {
    final GrowlAnalyzer analyzer = await startAnalyzer();
    messenger.setMockMethodCallHandler(growlChannel, (MethodCall call) async {
      growlCalls.add(call);
      if (call.method == "stop") {
        scoresSink?.success(createGrowlingScores(0.9));
        await pumpEventQueue();
      }
      return null;
    });
    await analyzer.stop();
    await analyzer.start(muteOutput: true);
    await pumpEventQueue();
    expect(analyzer.soundScores, isNull);
    expect(receivedScores, isEmpty);
    await sendScores(createGrowlingScores(0.25));
    expect(analyzer.soundScores?["Growling"], 0.25);
  });

  test("무시한 이벤트는 처음 한 번만 debugPrint로 알린다", () async {
    final List<String?> logs = [];
    final DebugPrintCallback originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message);
    addTearDown(() => debugPrint = originalDebugPrint);
    await startAnalyzer();
    await sendScores(Float32List(3));
    await sendScores(Float32List(4));
    expect(logs, hasLength(1));
  });
}
