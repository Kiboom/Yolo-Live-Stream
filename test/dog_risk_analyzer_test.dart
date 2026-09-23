import "dart:typed_data";
import "dart:ui";

import "package:flutter_test/flutter_test.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";
import "package:yolo_live_stream/src/dog_risk_analyzer.dart";
import "package:yolo_live_stream/src/rule_based_dog_risk_analyzer.dart";
import "package:yolo_live_stream/src/sound_scores.dart";

// 강아지 박스 긴 변은 200px. 머리는 오른쪽(x 증가 방향)을 향한다.
const Rect dogBox = Rect.fromLTRB(100, 100, 300, 260);
const Rect nearPersonBox = Rect.fromLTRB(320, 100, 420, 300);
const Rect farPersonBox = Rect.fromLTRB(600, 100, 700, 300);

const Map<int, Offset> standingPoints = {
  0: Offset(242, 255),
  1: Offset(240, 210),
  2: Offset(238, 180),
  3: Offset(138, 255),
  4: Offset(140, 210),
  6: Offset(252, 255),
  7: Offset(250, 210),
  8: Offset(248, 180),
  9: Offset(148, 255),
  10: Offset(150, 210),
  12: Offset(130, 150),
  13: Offset(100, 190),
  14: Offset(265, 120),
  15: Offset(270, 122),
  16: Offset(295, 135),
  20: Offset(280, 125),
  21: Offset(282, 126),
  22: Offset(230, 140),
};

YOLOResult detection(String className, Rect box) => YOLOResult(
  classIndex: 0,
  className: className,
  confidence: 0.9,
  boundingBox: box,
  normalizedBox: box,
);

YOLOResult dogPose(
  Map<int, Offset> points, {
  Rect box = dogBox,
  double confidence = 0.9,
}) => YOLOResult(
  classIndex: 0,
  className: "dog",
  confidence: 0.9,
  boundingBox: box,
  normalizedBox: box,
  keypoints: [for (var i = 0; i < 24; i++) Keypoint(points[i]?.dx ?? 0, points[i]?.dy ?? 0)],
  keypointConfidences: [for (var i = 0; i < 24; i++) points.containsKey(i) ? confidence : 0],
);

DogRiskReport analyze({
  Rect? personBox = nearPersonBox,
  Map<int, Offset>? points,
  Map<String, double>? sound,
  DogRiskThresholds thresholds = const DogRiskThresholds(),
}) {
  final scores = Float32List(SoundScores.labels.length);
  for (final MapEntry(key: label, value: score) in {...?sound}.entries) {
    scores[SoundScores.labels.indexOf(label)] = score;
  }
  return RuleBasedDogRiskAnalyzer(thresholds: thresholds).analyze(
    DogRiskSignals(
      detections: [
        detection("dog", dogBox),
        if (personBox != null) detection("person", personBox),
      ],
      dogPoses: points == null ? null : [dogPose(points)],
      sound: sound == null ? null : SoundScores(scores),
    ),
  );
}

void main() {
  group("거리", () {
    test("박스가 겹치면 0", () {
      expect(analyze(personBox: const Rect.fromLTRB(250, 100, 350, 300)).distance, 0);
    });

    test("떨어져 있으면 간격 ÷ 강아지 박스 긴 변", () {
      expect(analyze().distance, closeTo(20 / 200, 1e-9));
      expect(analyze(personBox: const Rect.fromLTRB(330, 300, 400, 400)).distance, closeTo(50 / 200, 1e-9));
    });

    test("사람이 없으면 null", () {
      expect(analyze(personBox: null).distance, isNull);
    });

    test("강아지가 없으면 null", () {
      final report = const RuleBasedDogRiskAnalyzer().analyze(
        DogRiskSignals(detections: [detection("person", nearPersonBox)]),
      );
      expect(report.distance, isNull);
      expect(report.level, DogRiskLevel.low);
    });

    test("강아지가 여러 마리면 사람에게 가장 가까운 강아지 기준으로 포즈를 고른다", () {
      const otherDogBox = Rect.fromLTRB(900, 100, 1100, 260);
      final lyingElsewhere = {
        for (final entry in standingPoints.entries) entry.key: entry.value.translate(800, 0),
        22: const Offset(1030, 240),
      };
      final report = const RuleBasedDogRiskAnalyzer().analyze(
        DogRiskSignals(
          detections: [
            detection("dog", otherDogBox),
            detection("dog", dogBox),
            detection("person", nearPersonBox),
          ],
          dogPoses: [
            dogPose(
              lyingElsewhere,
              box: otherDogBox,
            ),
            dogPose(standingPoints),
          ],
        ),
      );
      expect(report.distance, closeTo(0.1, 1e-9));
      expect(report.posture, DogPosture.standing);
    });
  });

  group("자세", () {
    test("서 있음", () {
      expect(analyze(points: standingPoints).posture, DogPosture.standing);
    });

    test("앉음", () {
      final sittingPoints = {
        ...standingPoints,
        3: const Offset(150, 255),
        4: const Offset(190, 230),
        9: const Offset(160, 255),
        10: const Offset(200, 230),
        12: const Offset(160, 245),
        22: const Offset(220, 130),
      };
      expect(analyze(points: sittingPoints).posture, DogPosture.sitting);
    });

    test("엎드림", () {
      final lyingPoints = {
        ...standingPoints,
        0: const Offset(270, 250),
        1: const Offset(245, 248),
        2: const Offset(220, 245),
        3: const Offset(150, 250),
        4: const Offset(170, 240),
        6: const Offset(275, 250),
        7: const Offset(250, 248),
        8: const Offset(225, 245),
        9: const Offset(155, 250),
        10: const Offset(175, 240),
        12: const Offset(120, 215),
        22: const Offset(200, 210),
      };
      expect(analyze(points: lyingPoints).posture, DogPosture.lying);
    });

    test("키포인트 신뢰도가 기준 미만이면 unknown", () {
      final report = const RuleBasedDogRiskAnalyzer().analyze(
        DogRiskSignals(
          detections: [detection("dog", dogBox)],
          dogPoses: [
            dogPose(
              standingPoints,
              confidence: 0.3,
            ),
          ],
        ),
      );
      expect(report.posture, DogPosture.unknown);
      expect(report.isTailRaised, isNull);
    });

    test("판정에 필요한 키포인트가 없으면 unknown", () {
      expect(analyze(points: {16: const Offset(295, 135)}).posture, DogPosture.unknown);
    });

    test("강아지 박스와 겹치는 포즈가 없으면 unknown이고 나머지는 null", () {
      final report = const RuleBasedDogRiskAnalyzer().analyze(
        DogRiskSignals(
          detections: [detection("dog", dogBox), detection("person", nearPersonBox)],
          dogPoses: [
            dogPose(
              standingPoints,
              box: const Rect.fromLTRB(900, 100, 1100, 260),
            ),
          ],
        ),
      );
      expect(report.posture, DogPosture.unknown);
      expect(report.isFacingPerson, isNull);
      expect(report.isTailRaised, isNull);
      expect(report.isHeadLoweredForward, isNull);
    });
  });

  group("시선", () {
    test("옆모습에서 사람 쪽을 보면 true", () {
      expect(analyze(points: standingPoints).isFacingPerson, isTrue);
    });

    test("옆모습에서 사람 반대쪽을 보면 false", () {
      expect(
        analyze(
          personBox: const Rect.fromLTRB(-150, 100, -50, 300),
          points: standingPoints,
        ).isFacingPerson,
        isFalse,
      );
    });

    test("귀 뿌리가 없으면 두 눈 가운데를 기준으로 한다", () {
      final points = Map.of(standingPoints)
        ..remove(14)
        ..remove(15);
      expect(analyze(points: points).isFacingPerson, isTrue);
    });

    test("옆모습에서 귀 뿌리와 눈이 한쪽씩만 보여도 판정한다", () {
      final points = Map.of(standingPoints)
        ..remove(15)
        ..remove(21);
      expect(analyze(points: points).isFacingPerson, isTrue);
      points.remove(14);
      expect(analyze(points: points).isFacingPerson, isTrue);
    });

    test("정면 얼굴에서 한쪽 눈만 보이면 null", () {
      final points = Map.of(standingPoints)
        ..removeWhere((index, _) => index == 14 || index == 15 || index == 21)
        ..[20] = const Offset(188, 125)
        ..[16] = const Offset(200, 130);
      expect(analyze(points: points).isFacingPerson, isNull);
    });

    test("정면 얼굴에서 귀 뿌리 하나만 보이면 null", () {
      final points = Map.of(standingPoints)
        ..removeWhere((index, _) => index == 15 || index == 20 || index == 21)
        ..[14] = const Offset(175, 120)
        ..[16] = const Offset(200, 125);
      expect(analyze(points: points).isFacingPerson, isNull);
    });

    test("정면을 봐서 머리 방향이 너무 짧으면 null", () {
      final frontalPoints = {
        ...standingPoints,
        14: const Offset(190, 120),
        15: const Offset(210, 120),
        16: const Offset(200, 122),
      };
      expect(analyze(points: frontalPoints).isFacingPerson, isNull);
    });

    test("사람이 없으면 null", () {
      expect(
        analyze(
          personBox: null,
          points: standingPoints,
        ).isFacingPerson,
        isNull,
      );
    });
  });

  group("긴장 신호", () {
    test("꼬리가 내려가 있고 머리가 withers보다 높으면 둘 다 false", () {
      final report = analyze(points: standingPoints);
      expect(report.isTailRaised, isFalse);
      expect(report.isHeadLoweredForward, isFalse);
    });

    test("tail_end가 tail_start보다 위면 꼬리 올림", () {
      expect(analyze(points: {...standingPoints, 13: const Offset(110, 110)}).isTailRaised, isTrue);
    });

    test("tail_end가 여유값 이내로만 높으면 수평 꼬리로 보고 false", () {
      expect(analyze(points: {...standingPoints, 13: const Offset(100, 145)}).isTailRaised, isFalse);
    });

    test("코가 withers보다 낮고 앞발이 몸 중심보다 머리 쪽이면 머리를 낮추고 앞으로 향함", () {
      expect(analyze(points: {...standingPoints, 16: const Offset(295, 200)}).isHeadLoweredForward, isTrue);
    });

    test("코가 낮아도 앞발이 몸 중심보다 뒤쪽이면 false", () {
      final points = {
        ...standingPoints,
        0: const Offset(160, 255),
        6: const Offset(170, 255),
        16: const Offset(295, 200),
      };
      expect(analyze(points: points).isHeadLoweredForward, isFalse);
    });
  });

  group("위험도", () {
    final tensePoints = {...standingPoints, 13: const Offset(110, 110)};

    test("가까움과 으르렁이면 high", () {
      expect(analyze(sound: {"Growling": 0.8}).level, DogRiskLevel.high);
    });

    test("가까움, 사람 쪽을 봄, 긴장 신호면 high", () {
      expect(analyze(points: tensePoints).level, DogRiskLevel.high);
    });

    test("가까움과 사람 쪽을 봄만 있고 긴장 신호가 없으면 caution", () {
      expect(analyze(points: standingPoints).level, DogRiskLevel.caution);
    });

    test("가까움과 긴장 신호만 있고 사람 반대쪽을 보면 caution", () {
      final report = analyze(
        personBox: const Rect.fromLTRB(-150, 100, 90, 300),
        points: tensePoints,
      );
      expect(report.isFacingPerson, isFalse);
      expect(report.level, DogRiskLevel.caution);
    });

    test("가까움만 있으면 caution", () {
      expect(analyze().level, DogRiskLevel.caution);
    });

    test("멀리서 으르렁만 있으면 caution, 기준값과 같으면 으르렁으로 본다", () {
      final report = analyze(
        personBox: farPersonBox,
        sound: {"Growling": 0.5},
      );
      expect(report.level, DogRiskLevel.caution);
    });

    test("멀리서 사람 쪽을 보며 긴장해도 low", () {
      final report = analyze(
        personBox: farPersonBox,
        points: tensePoints,
        sound: {"Growling": 0.2},
      );
      expect(report.isFacingPerson, isTrue);
      expect(report.isTailRaised, isTrue);
      expect(report.level, DogRiskLevel.low);
    });

    test("사람이 없으면 으르렁이어도 caution", () {
      final report = analyze(
        personBox: null,
        sound: {"Growling": 0.9},
      );
      expect(report.level, DogRiskLevel.caution);
    });

    test("아무 신호가 없으면 low", () {
      expect(analyze(personBox: farPersonBox).level, DogRiskLevel.low);
    });
  });

  group("소리 점수", () {
    test("소리 점수가 없으면 으르렁 점수는 null이고 으르렁으로 보지 않는다", () {
      final report = analyze(personBox: farPersonBox);
      expect(report.growlScore, isNull);
      expect(report.level, DogRiskLevel.low);
    });

    test("Growling이 아닌 소리는 점수가 높아도 으르렁으로 보지 않는다", () {
      final report = analyze(
        personBox: farPersonBox,
        sound: {"Bark": 0.9},
      );
      expect(report.growlScore, 0);
      expect(report.level, DogRiskLevel.low);
    });

    test("기준값이 float32로 정확히 표현되지 않아도 기준값과 같은 점수는 으르렁으로 본다", () {
      final report = analyze(
        personBox: farPersonBox,
        sound: {"Growling": 0.7},
        thresholds: const DogRiskThresholds(growlScore: 0.7),
      );
      expect(report.level, DogRiskLevel.caution);
    });
  });

  test("포즈 모델이 없으면 자세, 시선, 긴장 신호는 null이고 으르렁 점수는 그대로 담는다", () {
    final report = analyze(sound: {"Growling": 0.3});
    expect(report.posture, isNull);
    expect(report.isFacingPerson, isNull);
    expect(report.isTailRaised, isNull);
    expect(report.isHeadLoweredForward, isNull);
    // 점수는 Float32List에 담기므로 float32 정밀도로 반올림된다.
    expect(report.growlScore, closeTo(0.3, 1e-6));
  });
}
