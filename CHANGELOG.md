## 0.4.0

- `LiveStreamingView`에 내장 컨트롤 UI를 끄는 `showControlPanel` 추가(끄면 영상+탐지 오버레이만 남는다).
- 코드에서 시작/종료/카메라 전환을 제어하는 `LiveStreamingController` 추가.
- 위젯이 뜨면 자동 연결하는 `autoStart`와 수신자용 `senderIp` 추가.
- 탐지 결과를 외부로 받는 `onDetected` 콜백과 송신자 자기 IP를 받는 `onLocalIpReady` 콜백 추가.
- 수신 음성 출력을 켜고 끄는 `enableSpeaker` 필드와 `LiveStreamingController.setSpeakerEnabled` 추가.
- Dart 3.9.x에서 컴파일되도록 dot-shorthand 표기를 명시적 enum으로 전환.

## 0.3.0

- Dart SDK 하한을 3.9.2로 낮춤.

## 0.2.0

- 커스텀 모델 경로(`customModelPath`) 지원. 지정 시 `model` enum 대신 그 경로의 모델을 사용.
- 공개 API 도큐먼트 주석(`///`) 정리.

## 0.1.0

- 첫 릴리스.
- 같은 Wi-Fi에서 WebRTC P2P 영상 송수신 (`LiveStreamingView`, `LiveStreamingConnector`).
- 수신 영상에 YOLO 객체 탐지 오버레이 (`YoloAnalyzer`, `DetectionOverlay`).
- 외부 제어용 역할 스위처 위젯 (`LiveStreamRoleSwitcher`).
- 설정 필드: 해상도(`VideoQuality`), 프레임률, 모델(`YoloModel`), 분석 주기.
