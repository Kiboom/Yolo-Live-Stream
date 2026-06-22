import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";

/// 수신 영상을 보여주고 그 위에 YOLO 탐지 박스를 겹쳐 그린다.
/// 영상을 종횡비에 맞춰 표시하고, 같은 박스 안에 오버레이를 얹어 좌표가 어긋나지 않게 한다.
class DetectionOverlay extends StatelessWidget {
  const DetectionOverlay({
    super.key,
    required this.renderer,
    required this.detections,
    this.mirror = false,
  });

  final RTCVideoRenderer renderer;
  final List<YOLOResult> detections;

  /// 영상을 좌우반전해 그릴지. 박스 x좌표도 같이 뒤집어 정렬을 맞춘다.
  final bool mirror;

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
              child: CustomPaint(painter: _DetectionPainter(detections, mirror)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter(this.detections, this.mirror);

  final List<YOLOResult> detections;
  final bool mirror;

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
      oldDelegate.detections != detections || oldDelegate.mirror != mirror;
}
