## 0.2.0

- 커스텀 모델 경로(`customModelPath`) 지원. 지정 시 `model` enum 대신 그 경로의 모델을 사용.
- 공개 API 도큐먼트 주석(`///`) 정리.

## 0.1.0

- 첫 릴리스.
- 같은 Wi-Fi에서 WebRTC P2P 영상 송수신 (`LiveStreamingView`, `LiveStreamingConnector`).
- 수신 영상에 YOLO 객체 탐지 오버레이 (`YoloAnalyzer`, `DetectionOverlay`).
- 외부 제어용 역할 스위처 위젯 (`LiveStreamRoleSwitcher`).
- 설정 필드: 해상도(`VideoQuality`), 프레임률, 모델(`YoloModel`), 분석 주기.
