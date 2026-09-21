import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";
import "package:yolo_live_stream/src/detection_overlay.dart";
import "package:yolo_live_stream/src/dog_risk_analyzer.dart";

void main() {
  Finder overlayPaint() => find.descendant(
        of: find.byType(DetectionOverlay),
        matching: find.byWidgetPredicate((Widget widget) => widget is CustomPaint && widget.painter != null),
      );

  Future<void> pumpOverlay(WidgetTester tester, DetectionOverlay overlay) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: overlay)));

  YOLOResult dogPose() => YOLOResult(
        classIndex: 0,
        className: "dog",
        confidence: 0.9,
        boundingBox: const Rect.fromLTWH(100, 100, 200, 200),
        normalizedBox: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
        keypoints: [Keypoint(150, 150), Keypoint(200, 200)],
        keypointConfidences: [0.9, 0.2],
      );

  testWidgets("기본값이면 박스 외에 아무것도 그리지 않는다", (WidgetTester tester) async {
    await pumpOverlay(tester, DetectionOverlay(renderer: RTCVideoRenderer(), detections: const []));
    expect(overlayPaint(), paintsNothing);
  });

  testWidgets("신뢰도 0.5 이상 키포인트만 점으로 그린다", (WidgetTester tester) async {
    await pumpOverlay(
      tester,
      DetectionOverlay(renderer: RTCVideoRenderer(), detections: const [], dogPoses: [dogPose()]),
    );
    expect(overlayPaint(), paints..circle(radius: 3));
    expect(overlayPaint(), paintsExactlyCountTimes(#drawCircle, 1));
  });

  testWidgets("리포트가 있으면 위험도 배지를 그린다", (WidgetTester tester) async {
    await pumpOverlay(
      tester,
      DetectionOverlay(
        renderer: RTCVideoRenderer(),
        detections: const [],
        dogRiskReport: const DogRiskReport(level: DogRiskLevel.high),
      ),
    );
    expect(overlayPaint(), paints..rrect(color: const Color(0xFFFF453A).withValues(alpha: 0.85)));
  });
}
