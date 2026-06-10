/// 같은 Wi-Fi에서 WebRTC 영상 송수신 + YOLO 객체 탐지 플러그인.
///
/// 올인원: [LiveStreamingView] 한 줄로 송/수신 화면을 띄운다.
/// 조립형: [LiveStreamingConnector] + [YoloAnalyzer] + [DetectionOverlay]를 직접 조합한다.
library;

export "src/detection_overlay.dart";
export "src/live_streaming_connector.dart";
export "src/live_streaming_view.dart";
export "src/role.dart";
export "src/role_switcher.dart";
export "src/yolo_analyzer.dart";
