import "package:ultralytics_yolo/ultralytics_yolo.dart";
import "package:yolo_live_stream/src/sound_scores.dart";

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

/// 플러그인이 영상 프레임이나 소리 점수가 들어올 때마다 모아 [DogRiskAnalyzer]에 넘기는 입력.
class DogRiskSignals {
  const DogRiskSignals({
    required this.detections,
    this.dogPoses,
    this.sound,
  });

  /// detect 모델 결과 전체(COCO 80종). 탐지를 껐거나 아직 프레임이 없으면 빈 리스트.
  final List<YOLOResult> detections;

  /// dog-pose 모델 결과(키포인트 24개). 포즈 모델이 없으면 null.
  final List<YOLOResult>? dogPoses;

  /// 최신 YAMNet 점수. 으르렁 감지를 껐거나 아직 소리가 없으면 null.
  final SoundScores? sound;
}

/// 위험도 판정 로직. 기본값은 [RuleBasedDogRiskAnalyzer]이고, 앱은 이 클래스를 상속해 판정을 바꿔 끼운다.
///
/// 세션 동안 같은 인스턴스를 쓰므로 여러 번의 [analyze] 사이에 기록을 쌓을 수 있다.
abstract class DogRiskAnalyzer {
  const DogRiskAnalyzer();

  DogRiskReport analyze(DogRiskSignals signals);

  /// 연결을 멈추거나 다시 시작할 때 플러그인이 부른다. 쌓아 둔 기록이 있으면 여기서 지운다.
  void reset() {}
}
