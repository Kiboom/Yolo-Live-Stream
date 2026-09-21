import "package:ultralytics_yolo/ultralytics_yolo.dart";

/// 강아지 자세. 포즈 모델이 없거나 키포인트가 부족하면 [unknown].
enum DogPosture { standing, sitting, lying, unknown }

/// 사람과 강아지 사이의 위험도.
enum DogRiskLevel { low, caution, high }

/// 위험도 판정 임계값.
class DogRiskThresholds {
  const DogRiskThresholds({
    this.nearDistance = 0.5,
    this.growlScore = 0.5,
    this.facingAngleDegrees = 30,
    this.keypointConfidence = 0.5,
  });

  /// 이 값보다 가까우면 "가까움". 단위는 강아지 박스 긴 변 길이.
  final double nearDistance;

  /// Growling 점수가 이 값 이상이면 "으르렁".
  final double growlScore;

  /// 머리 방향과 사람 방향 사이 각도가 이 값 안쪽이면 "사람 쪽을 봄".
  final double facingAngleDegrees;

  /// 이 값보다 신뢰도가 낮은 키포인트는 판정에 쓰지 않는다.
  final double keypointConfidence;
}

/// 한 번의 분석 결과. 포즈 모델이 없으면 자세, 시선, 긴장 신호는 null이다.
class DogRiskReport {
  const DogRiskReport({
    required this.level,
    this.distance,
    this.posture,
    this.isFacingPerson,
    this.isTailRaised,
    this.isHeadLoweredForward,
    this.growlScore,
  });

  final DogRiskLevel level;

  /// 가장 가까운 사람과 강아지 박스 사이 간격 ÷ 강아지 박스 긴 변. 겹치면 0, 둘 중 하나가 없으면 null.
  final double? distance;

  final DogPosture? posture;

  /// 정면을 봐서 머리 방향을 판정할 수 없으면 null.
  final bool? isFacingPerson;

  final bool? isTailRaised;
  final bool? isHeadLoweredForward;

  /// 으르렁 감지를 껐으면 null.
  final double? growlScore;
}

/// 박스, 강아지 키포인트, 으르렁 점수를 합쳐 [DogRiskReport]를 만든다. 모델은 돌리지 않는다.
class DogRiskAnalyzer {
  const DogRiskAnalyzer({this.thresholds = const DogRiskThresholds()});

  final DogRiskThresholds thresholds;

  /// [detections]는 기본 detect 모델 결과(person, dog), [dogPoses]는 dog-pose 모델 결과(포즈 모델이 없으면 null).
  DogRiskReport analyze({
    required List<YOLOResult> detections,
    List<YOLOResult>? dogPoses,
    double? growlScore,
  }) {
    throw UnimplementedError();
  }
}
