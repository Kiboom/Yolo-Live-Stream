import "dart:async";
import "dart:typed_data";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";
import "package:yolo_live_stream/src/sound_scores.dart";

/// 수신 음성을 네이티브에서 가로채 YAMNet으로 분석하고, 521종 소리 점수를 받는다.
///
/// 채널 규약 (Android `GrowlAnalyzer.kt`, iOS `GrowlAnalyzer.swift`와 공유)
///  - MethodChannel "yolo_live_stream/growl_analyzer"
///    - "start" {"muteOutput": bool}: 가로채기와 분석 시작. muteOutput이면 분석한 뒤 버퍼를 0으로 지워 스피커로 내보내지 않는다.
///    - "setOutputMuted" {"muted": bool}: 분석 중 스피커 출력만 켜고 끈다.
///    - "stop": 가로채기와 분석을 멈추고 출력 음소거도 푼다.
///  - EventChannel "yolo_live_stream/growl_analyzer/scores": 약 0.5초마다 YAMNet 521종 점수(Float32List, 0~1, 순서는 [SoundScores.labels])를 보낸다.
class GrowlAnalyzer {
  GrowlAnalyzer({
    required this.onUpdate,
    this.onSoundScores,
  });

  static const MethodChannel _methodChannel = MethodChannel("yolo_live_stream/growl_analyzer");

  final void Function() onUpdate;

  /// 새 점수가 들어올 때마다 호출된다.
  final void Function(SoundScores scores)? onSoundScores;
  StreamSubscription<dynamic>? _subscription;

  /// 최신 소리 점수. 분석 전이거나 멈췄으면 null.
  SoundScores? soundScores;

  bool _hasLoggedInvalidScores = false;

  Future<void> start({required bool muteOutput}) async {
    _subscription ??= const EventChannel("yolo_live_stream/growl_analyzer/scores").receiveBroadcastStream().listen(_handleScores);
    await _methodChannel.invokeMethod<void>("start", {"muteOutput": muteOutput});
  }

  Future<void> setOutputMuted(bool muted) => _methodChannel.invokeMethod<void>("setOutputMuted", {"muted": muted});

  Future<void> stop() async {
    // 구독을 먼저 풀면 네이티브가 멈추기 전에 보낸 점수가 채널 버퍼에 남아 다음 start에 전달되므로, 네이티브가 멈출 때까지 구독을 둔 채 점수를 버린다.
    final StreamSubscription<dynamic>? subscription = _subscription;
    _subscription = null;
    soundScores = null;
    subscription?.onData(null);
    try {
      await _methodChannel.invokeMethod<void>("stop");
    } finally {
      await subscription?.cancel();
    }
    onUpdate();
  }

  void _handleScores(dynamic event) {
    final SoundScores? latest = _parseSoundScores(event);
    if (latest == null) {
      if (!_hasLoggedInvalidScores) debugPrint("GrowlAnalyzer: 숫자 ${SoundScores.labels.length}개가 아닌 소리 점수를 무시했습니다 (${event.runtimeType})");
      _hasLoggedInvalidScores = true;
      return;
    }
    soundScores = latest;
    onSoundScores?.call(latest);
    onUpdate();
  }

  /// 플랫폼에 따라 Float64List나 숫자 리스트로 올 수 있다. 레이블 수와 길이가 다르면 null.
  static SoundScores? _parseSoundScores(Object? event) {
    if (event is! List<Object?> || event.length != SoundScores.labels.length) return null;
    if (event is Float32List) return SoundScores(event);
    final List<double> scores = [
      for (final Object? score in event)
        if (score is num) score.toDouble(),
    ];
    return scores.length == event.length ? SoundScores(Float32List.fromList(scores)) : null;
  }
}
