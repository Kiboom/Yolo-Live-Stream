import "dart:math" as math;
import "dart:typed_data";
import "dart:ui";

import "package:ultralytics_yolo/ultralytics_yolo.dart";
import "package:yolo_live_stream/src/dog_risk_analyzer.dart";

/// 박스, 강아지 키포인트, 으르렁 점수를 합쳐 [DogRiskReport]를 만드는 플러그인 기본 규칙. 모델은 돌리지 않는다.
class RuleBasedDogRiskAnalyzer extends DogRiskAnalyzer {
  const RuleBasedDogRiskAnalyzer({this.thresholds = const DogRiskThresholds()});

  final DogRiskThresholds thresholds;

  @override
  DogRiskReport analyze(DogRiskSignals signals) {
    final detections = signals.detections;
    final dogPoses = signals.dogPoses;
    final growlScore = signals.sound?["Growling"];
    final persons = detections.where((detection) => detection.className == "person").toList();
    final dogs = detections.where((detection) => detection.className == "dog").toList();

    YOLOResult? person;
    YOLOResult? dog;
    double? distance;
    for (final candidatePerson in persons) {
      for (final candidateDog in dogs) {
        final dogSize = candidateDog.boundingBox.longestSide;
        if (dogSize <= 0) continue;
        final candidateDistance = _boxGap(candidatePerson.boundingBox, candidateDog.boundingBox) / dogSize;
        if (distance == null || candidateDistance < distance) {
          distance = candidateDistance;
          person = candidatePerson;
          dog = candidateDog;
        }
      }
    }
    // 사람이 없으면 거리 기준이 없으니 화면에서 가장 큰 강아지의 자세를 본다.
    dog ??= dogs.isEmpty ? null : dogs.reduce((a, b) => _boxArea(a.boundingBox) >= _boxArea(b.boundingBox) ? a : b);

    final pose = dog == null || dogPoses == null ? null : _matchingPose(dog.boundingBox, dogPoses);
    final posture = dog == null || dogPoses == null ? null : pose?.posture ?? DogPosture.unknown;
    final isFacingPerson = person == null
        ? null
        : pose?.isFacing(person.boundingBox.center, thresholds.facingAngleDegrees);
    final isTailRaised = pose?.isTailRaised;
    final isHeadLoweredForward = pose?.isHeadLoweredForward;

    final isNear = distance != null && distance < thresholds.nearDistance;
    // 점수는 float32라 기준값도 float32로 맞춘다. double로 비교하면 0.7 같은 기준값에서 같은 점수가 기준 미만이 된다.
    final isGrowling = growlScore != null && growlScore >= Float32List.fromList([thresholds.growlScore]).single;
    // 긴장 신호는 오탐이 잦아, 가까이서 사람을 볼 때만 위험도를 올린다.
    final isTense = isTailRaised == true || isHeadLoweredForward == true;
    final level = isNear && (isGrowling || (isFacingPerson == true && isTense))
        ? DogRiskLevel.high
        : isNear || isGrowling
        ? DogRiskLevel.caution
        : DogRiskLevel.low;

    return DogRiskReport(
      level: level,
      distance: distance,
      posture: posture,
      isFacingPerson: isFacingPerson,
      isTailRaised: isTailRaised,
      isHeadLoweredForward: isHeadLoweredForward,
      growlScore: growlScore,
    );
  }

  /// 강아지 박스와 가장 많이 겹치는 포즈 결과. 겹치는 것이 없으면 null.
  _DogPose? _matchingPose(Rect dogBox, List<YOLOResult> poses) {
    YOLOResult? bestPose;
    var bestOverlap = 0.0;
    for (final pose in poses) {
      final intersection = dogBox.intersect(pose.boundingBox);
      if (intersection.width <= 0 || intersection.height <= 0) continue;
      final intersectionArea = _boxArea(intersection);
      final overlap = intersectionArea / (_boxArea(dogBox) + _boxArea(pose.boundingBox) - intersectionArea);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        bestPose = pose;
      }
    }
    return bestPose == null ? null : _DogPose(bestPose, thresholds.keypointConfidence);
  }

  static double _boxGap(Rect a, Rect b) {
    final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
    final dy = math.max(0.0, math.max(a.top - b.bottom, b.top - a.bottom));
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _boxArea(Rect box) => box.width * box.height;
}

// Ultralytics dog-pose.yaml 키포인트 순서.
const int _frontLeftPaw = 0;
const int _frontLeftKnee = 1;
const int _frontLeftElbow = 2;
const int _rearLeftPaw = 3;
const int _rearLeftKnee = 4;
const int _frontRightPaw = 6;
const int _frontRightKnee = 7;
const int _frontRightElbow = 8;
const int _rearRightPaw = 9;
const int _rearRightKnee = 10;
const int _tailStart = 12;
const int _tailEnd = 13;
const int _leftEarBase = 14;
const int _rightEarBase = 15;
const int _nose = 16;
const int _leftEye = 20;
const int _rightEye = 21;
const int _withers = 22;
const int _keypointCount = 24;

const List<(int, int)> _frontLegs = [(_frontLeftKnee, _frontLeftPaw), (_frontRightKnee, _frontRightPaw)];
const List<(int, int)> _rearLegs = [(_rearLeftKnee, _rearLeftPaw), (_rearRightKnee, _rearRightPaw)];
const List<(int, int)> _frontElbows = [(_frontLeftElbow, _frontLeftPaw), (_frontRightElbow, _frontRightPaw)];
const List<int> _frontPaws = [_frontLeftPaw, _frontRightPaw];
const List<int> _rearPaws = [_rearLeftPaw, _rearRightPaw];
const List<int> _allPaws = [_frontLeftPaw, _rearLeftPaw, _frontRightPaw, _rearRightPaw];

// 무릎→발 가로 이동 ÷ 세로 길이가 이 값 이하이면 다리가 수직으로 펴졌다고 본다(약 20도).
const double _straightLegSlope = 0.35;
// 이하 "크기" 비율은 강아지 박스 긴 변 기준이라 카메라 거리와 무관하다.
const double _standingWithersHeightRatio = 0.35;
const double _sittingTailHeightRatio = 0.15;
const double _lyingElbowHeightRatio = 0.08;
// 엎드림: 발에서 withers까지 높이 ÷ withers에서 tail_start까지 몸길이.
const double _lyingBodyHeightRatio = 0.6;
const double _minHeadDirectionRatio = 0.05;
// 코가 박스 가로 중심에서 박스 폭 절반 × 이 값 이상 떨어져 있으면 옆모습으로 본다.
const double _sideViewNoseOffsetRatio = 0.5;
// 수평에 가까운 꼬리에서 값이 흔들리지 않도록 tail_end가 이만큼 더 높아야 꼬리 올림으로 본다.
const double _tailRaisedMarginRatio = 0.05;

/// 신뢰도 기준을 넘은 키포인트만 담은 강아지 포즈. 없는 키포인트는 null.
class _DogPose {
  _DogPose(YOLOResult pose, double minConfidence)
    : _box = pose.boundingBox,
      _points = List.generate(_keypointCount, (index) {
        final keypoints = pose.keypoints;
        final confidences = pose.keypointConfidences;
        if (keypoints == null || confidences == null) return null;
        if (index >= keypoints.length || index >= confidences.length) return null;
        if (confidences[index] < minConfidence) return null;
        return Offset(keypoints[index].x, keypoints[index].y);
      });

  final Rect _box;
  final List<Offset?> _points;

  double get _size => _box.longestSide;

  DogPosture get posture {
    if (_isLying == true) return DogPosture.lying;
    if (_isSitting == true) return DogPosture.sitting;
    if (_isStanding == true) return DogPosture.standing;
    return DogPosture.unknown;
  }

  bool? get _isStanding {
    final isFrontStraight = _areLegsStraight(_frontLegs);
    final isRearStraight = _areLegsStraight(_rearLegs);
    final withers = _points[_withers];
    final pawY = _meanPoint(_allPaws)?.dy;
    if (isFrontStraight == null || isRearStraight == null || withers == null || pawY == null) return null;
    return isFrontStraight && isRearStraight && pawY - withers.dy >= _standingWithersHeightRatio * _size;
  }

  bool? get _isSitting {
    final isFrontStraight = _areLegsStraight(_frontLegs);
    final tailStart = _points[_tailStart];
    final rearPawY = _meanPoint(_rearPaws)?.dy;
    if (isFrontStraight == null || tailStart == null || rearPawY == null) return null;
    return isFrontStraight && rearPawY - tailStart.dy <= _sittingTailHeightRatio * _size;
  }

  bool? get _isLying {
    final withers = _points[_withers];
    final tailStart = _points[_tailStart];
    final pawY = _meanPoint(_allPaws)?.dy;
    final elbowPairs = _visiblePairs(_frontElbows);
    if (withers == null || tailStart == null || pawY == null || elbowPairs.isEmpty) return null;
    final bodyLength = (withers - tailStart).distance;
    if (bodyLength <= 0) return null;
    final isBodyLow = pawY - withers.dy < _lyingBodyHeightRatio * bodyLength;
    final areElbowsDown = elbowPairs.every(
      (pair) => (pair.$1.dy - pair.$2.dy).abs() <= _lyingElbowHeightRatio * _size,
    );
    return isBodyLow && areElbowsDown;
  }

  /// 머리 기준점(두 귀 뿌리, 두 눈, 귀 뿌리 하나, 눈 하나 순)에서 코로 향하는 벡터. 정면을 봐서 너무 짧으면 null.
  Offset? get _headDirection {
    final nose = _points[_nose];
    if (nose == null) return null;
    final pairBase = _midpoint(_leftEarBase, _rightEarBase) ?? _midpoint(_leftEye, _rightEye);
    if (pairBase != null) {
      final direction = nose - pairBase;
      return direction.distance < _minHeadDirectionRatio * _size ? null : direction;
    }
    // 옆모습에서는 반대편 귀와 눈이 가려지므로 보이는 한쪽을 쓴다.
    // 정면에서도 한쪽만 보일 수 있어, 코가 박스 가로 가장자리 쪽에 있는 옆모습일 때만 판정한다.
    final singleBase = _points[_leftEarBase] ?? _points[_rightEarBase] ?? _points[_leftEye] ?? _points[_rightEye];
    final isSideView = (nose.dx - _box.center.dx).abs() >= _sideViewNoseOffsetRatio * _box.width / 2;
    if (singleBase == null || !isSideView) return null;
    final direction = nose - singleBase;
    return direction.distance < _minHeadDirectionRatio * _size ? null : direction;
  }

  bool? isFacing(Offset target, double maxAngleDegrees) {
    final headDirection = _headDirection;
    final nose = _points[_nose];
    if (headDirection == null || nose == null) return null;
    final toTarget = target - nose;
    if (toTarget.distance == 0) return true;
    final cosine = _dot(headDirection, toTarget) / (headDirection.distance * toTarget.distance);
    return math.acos(cosine.clamp(-1.0, 1.0)) * 180 / math.pi <= maxAngleDegrees;
  }

  bool? get isTailRaised {
    final tailStart = _points[_tailStart];
    final tailEnd = _points[_tailEnd];
    if (tailStart == null || tailEnd == null) return null;
    return tailStart.dy - tailEnd.dy > _tailRaisedMarginRatio * _size;
  }

  bool? get isHeadLoweredForward {
    final nose = _points[_nose];
    final withers = _points[_withers];
    final headDirection = _headDirection;
    final frontPaw = _meanPoint(_frontPaws);
    if (nose == null || withers == null || headDirection == null || frontPaw == null) return null;
    // 머리를 숙이면 머리 방향이 아래를 향해 발이 늘 "앞"으로 잡히므로, 가로 성분만 비교한다.
    return nose.dy > withers.dy && (frontPaw.dx - _box.center.dx) * headDirection.dx > 0;
  }

  /// 보이는 다리가 모두 수직으로 펴졌는지. 보이는 다리가 없으면 null.
  bool? _areLegsStraight(List<(int, int)> legs) {
    final visibleLegs = _visiblePairs(legs);
    if (visibleLegs.isEmpty) return null;
    return visibleLegs.every((leg) {
      final (knee, paw) = leg;
      final height = paw.dy - knee.dy;
      return height > 0 && (paw.dx - knee.dx).abs() <= _straightLegSlope * height;
    });
  }

  List<(Offset, Offset)> _visiblePairs(List<(int, int)> indexPairs) => [
    for (final (first, second) in indexPairs)
      if (_points[first] case final firstPoint?)
        if (_points[second] case final secondPoint?) (firstPoint, secondPoint),
  ];

  Offset? _midpoint(int first, int second) {
    final firstPoint = _points[first];
    final secondPoint = _points[second];
    if (firstPoint == null || secondPoint == null) return null;
    return (firstPoint + secondPoint) / 2;
  }

  Offset? _meanPoint(List<int> indices) {
    final visiblePoints = [for (final index in indices) ?_points[index]];
    if (visiblePoints.isEmpty) return null;
    return visiblePoints.reduce((a, b) => a + b) / visiblePoints.length.toDouble();
  }

  static double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;
}
