import "dart:typed_data";

import "package:yolo_live_stream/src/yamnet_labels.dart";

/// YAMNet이 소리 약 1초 구간마다 낸 521종 소리 점수(0~1). 순서는 [labels]와 같다.
class SoundScores {
  const SoundScores(this.scores);

  final Float32List scores;

  static const List<String> labels = yamnetLabels;

  /// [label]의 점수. YAMNet 레이블이 아니면 [ArgumentError].
  double operator [](String label) {
    final int index = labels.indexOf(label);
    if (index < 0) throw ArgumentError.value(label, "label", "not a YAMNet label");
    return scores[index];
  }
}
