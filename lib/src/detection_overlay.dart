import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";

import "package:yolo_live_stream/src/dog_risk_analyzer.dart";

/// 수신 영상을 보여주고 그 위에 YOLO 탐지 박스를 겹쳐 그린다.
/// 영상을 종횡비에 맞춰 표시하고, 같은 박스 안에 오버레이를 얹어 좌표가 어긋나지 않게 한다.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.renderer,
    required this.detections,
    this.mirror = false,
    this.dogPoses = const [],
    this.dogRiskReport,
  });

  final RTCVideoRenderer renderer;
  final List<YOLOResult> detections;

  /// 영상을 좌우반전해 그릴지. 박스 x좌표도 같이 뒤집어 정렬을 맞춘다.
  final bool mirror;

  /// dog-pose 모델 결과. 키포인트를 점으로 그린다.
  final List<YOLOResult> dogPoses;

  /// 있으면 영상 왼쪽 위에 위험도 배지를 그린다.
  final DogRiskReport? dogRiskReport;

  @override
  Widget build(BuildContext context) {
    final double aspectRatio = renderer.value.aspectRatio;
    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      color: const Color(0xFF0E0E12),
      child: AspectRatio(
        aspectRatio: aspectRatio <= 0 ? 16 / 9 : aspectRatio,
        child: Stack(
          children: [
            RTCVideoView(renderer, mirror: mirror, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
            Positioned.fill(
              child: CustomPaint(painter: _DetectionPainter(detections, mirror, dogPoses, dogRiskReport)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter(this.detections, this.mirror, this.dogPoses, this.dogRiskReport);

  final List<YOLOResult> detections;
  final bool mirror;
  final List<YOLOResult> dogPoses;
  final DogRiskReport? dogRiskReport;

  static const double minKeypointConfidence = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint = Paint()
      ..color = const Color(0xFF30D158)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final YOLOResult detection in detections) {
      // 영상을 좌우반전하면 박스 x도 뒤집어야 맞다(라벨 텍스트는 반전하지 않는다).
      final double left = mirror
          ? 1 - detection.normalizedBox.right
          : detection.normalizedBox.left;
      final double right = mirror
          ? 1 - detection.normalizedBox.left
          : detection.normalizedBox.right;
      final Rect box = Rect.fromLTRB(
        left * size.width,
        detection.normalizedBox.top * size.height,
        right * size.width,
        detection.normalizedBox.bottom * size.height,
      );
      canvas.drawRect(box, boxPaint);
      _paintLabel(canvas, box, detection);
    }
    _paintKeypoints(canvas, size);
    final DogRiskReport? report = dogRiskReport;
    if (report != null) _paintRiskBadge(canvas, report.level);
  }

  void _paintKeypoints(Canvas canvas, Size size) {
    final Paint pointPaint = Paint()..color = const Color(0xFFFFD60A);
    for (final YOLOResult pose in dogPoses) {
      final List<Keypoint>? keypoints = pose.keypoints;
      final List<double>? confidences = pose.keypointConfidences;
      if (keypoints == null || confidences == null) continue;
      final Rect pixelBox = pose.boundingBox;
      final Rect normalizedBox = pose.normalizedBox;
      if (pixelBox.width <= 0 || pixelBox.height <= 0) continue;
      for (int i = 0; i < keypoints.length && i < confidences.length; i++) {
        if (confidences[i] < minKeypointConfidence) continue;
        // 키포인트는 원본 이미지 픽셀 좌표라서, 픽셀 박스와 정규화 박스의 비율로 0~1 좌표로 바꾼다.
        final double normalizedX = normalizedBox.left +
            (keypoints[i].x - pixelBox.left) / pixelBox.width * normalizedBox.width;
        final double normalizedY = normalizedBox.top +
            (keypoints[i].y - pixelBox.top) / pixelBox.height * normalizedBox.height;
        final double x = mirror ? 1 - normalizedX : normalizedX;
        canvas.drawCircle(Offset(x * size.width, normalizedY * size.height), 3, pointPaint);
      }
    }
  }

  void _paintRiskBadge(Canvas canvas, DogRiskLevel level) {
    final (String text, Color color) = switch (level) {
      DogRiskLevel.low => ("낮음", const Color(0xFF30D158)),
      DogRiskLevel.caution => ("주의", const Color(0xFFFF9F0A)),
      DogRiskLevel.high => ("높음", const Color(0xFFFF453A)),
    };
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: "위험도 $text",
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const Offset origin = Offset(8, 8);
    final RRect badge = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx, origin.dy, textPainter.width + 16, textPainter.height + 8),
      const Radius.circular(1000),
    );
    canvas.drawRRect(badge, Paint()..color = color.withValues(alpha: 0.85));
    textPainter.paint(canvas, origin.translate(8, 4));
  }

  void _paintLabel(Canvas canvas, Rect box, YOLOResult detection) {
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: " ${detection.className} ${(detection.confidence * 100).toStringAsFixed(0)}% ",
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect labelBox = Rect.fromLTWH(
      box.left,
      box.top - textPainter.height,
      textPainter.width,
      textPainter.height,
    );
    canvas.drawRect(labelBox, Paint()..color = const Color(0xFF30D158));
    textPainter.paint(canvas, labelBox.topLeft);
  }

  @override
  bool shouldRepaint(_DetectionPainter oldDelegate) =>
      oldDelegate.detections != detections ||
      oldDelegate.mirror != mirror ||
      oldDelegate.dogPoses != dogPoses ||
      oldDelegate.dogRiskReport != dogRiskReport;
}
