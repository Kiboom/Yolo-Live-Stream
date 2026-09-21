import "dart:async";

import "package:flutter/services.dart";

/// 수신 음성을 네이티브에서 가로채 YAMNet으로 분석하고, 으르렁(Growling) 점수를 받는다.
///
/// 채널 규약 (Android `GrowlAnalyzer.kt`, iOS `GrowlAnalyzer.swift`와 공유)
///  - MethodChannel "yolo_live_stream/growl_analyzer"
///    - "start" {"muteOutput": bool}: 가로채기와 분석 시작. muteOutput이면 분석한 뒤 버퍼를 0으로 지워 스피커로 내보내지 않는다.
///    - "setOutputMuted" {"muted": bool}: 분석 중 스피커 출력만 켜고 끈다.
///    - "stop": 가로채기와 분석을 멈추고 출력 음소거도 푼다.
///  - EventChannel "yolo_live_stream/growl_analyzer/scores": 약 0.5초마다 Growling 점수(double, 0~1)를 보낸다.
class GrowlAnalyzer {
  GrowlAnalyzer({required this.onUpdate});

  static const MethodChannel _methodChannel = MethodChannel("yolo_live_stream/growl_analyzer");

  final void Function() onUpdate;
  StreamSubscription<dynamic>? _subscription;

  /// 최신 Growling 점수. 분석 전이거나 멈췄으면 null.
  double? growlScore;

  Future<void> start({required bool muteOutput}) async {
    _subscription ??= const EventChannel("yolo_live_stream/growl_analyzer/scores").receiveBroadcastStream().listen((dynamic score) {
      growlScore = (score as num).toDouble();
      onUpdate();
    });
    await _methodChannel.invokeMethod<void>("start", {"muteOutput": muteOutput});
  }

  Future<void> setOutputMuted(bool muted) => _methodChannel.invokeMethod<void>("setOutputMuted", {"muted": muted});

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    growlScore = null;
    await _methodChannel.invokeMethod<void>("stop");
    onUpdate();
  }
}
