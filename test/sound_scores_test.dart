import "dart:typed_data";

import "package:flutter_test/flutter_test.dart";
import "package:yolo_live_stream/src/sound_scores.dart";

void main() {
  test("레이블은 521개이고 YAMNet 클래스 순서를 따른다", () {
    expect(SoundScores.labels, hasLength(521));
    expect(SoundScores.labels.indexOf("Growling"), 74);
    expect(SoundScores.labels.indexOf("Bark"), 70);
    expect(SoundScores.labels.indexOf("Baby cry, infant cry"), 20);
  });

  test("레이블로 같은 순서의 점수를 조회한다", () {
    final Float32List scores = Float32List(521)
      ..[74] = 0.75
      ..[70] = 0.5
      ..[20] = 0.25;
    final SoundScores soundScores = SoundScores(scores);
    expect(soundScores["Growling"], 0.75);
    expect(soundScores["Bark"], 0.5);
    expect(soundScores["Baby cry, infant cry"], 0.25);
    expect(soundScores["Speech"], 0);
  });

  test("YAMNet 레이블이 아니면 ArgumentError", () {
    final SoundScores soundScores = SoundScores(Float32List(521));
    expect(() => soundScores["Meow meow"], throwsArgumentError);
    expect(() => soundScores["growling"], throwsArgumentError);
  });

  test("점수 개수가 레이블 수와 다르면 디버그 모드에서 AssertionError", () {
    expect(() => SoundScores(Float32List(520)), throwsAssertionError);
  });
}
