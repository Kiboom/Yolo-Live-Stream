## 0.9.0

- 0.8.0의 facing 기반 자동 미러를 제거하고, 수동 좌우반전으로 대체. iOS·Android 모두에서 연결마다 영상 미러가 들쭉날쭉하던 문제를 사용자 토글로 해결한다.
- `LiveStreamingController.mirror`·`setMirror`·`toggleMirror` 추가. 한쪽이 토글하면 상대에게 신호로 전달돼 양쪽 표시(영상·탐지 박스)가 함께 뒤집힌다.
- `LiveStreamingView.showMirrorButton`(기본 false) 추가. 켜면 좌우반전 토글 버튼이 보인다.
- `LiveStreamingView.showPip`(기본 true) 추가. false면 우상단 보조 영상(PiP)을 숨긴다.

## 0.8.0

- 송신자가 현재 카메라 방향(전/후면)을 수신자에게 신호로 보내고, 수신자는 송신 카메라가 전면일 때만 받은 영상과 YOLO 탐지 박스를 좌우반전해 표시한다. 전면 카메라 영상이 수신 측에서 거울처럼 뒤집혀 보이던 문제를 바로잡는다.
- `LiveStreamingController.remoteIsFrontCamera` getter와 `DetectionOverlay.mirror` 옵션 추가.

## 0.7.0

- `LiveStreamingController`가 영상 세션(WebRTC 연결·렌더러·YOLO 분석기)을 직접 소유하도록 변경. 같은 controller를 여러 `LiveStreamingView`에 넘기면 화면이 바뀌어도 같은 연결을 끊김 없이 이어서 그린다(예: 작은 카드에서 전체화면으로 전환).
- `LiveStreamingView`는 controller가 있으면 그 세션을 그리기만 한다. controller를 넘기지 않으면 위젯이 내부 세션을 만들어 단독으로 동작하므로 기존 사용 방식은 그대로 호환된다.
- 세션 설정(quality·enableSpeaker·enableDetection·model·customModelPath·detectionInterval·onDetected·onLocalIpReady·onError)을 `LiveStreamingController` 생성자로도 받는다.
- `LiveStreamingController`에 `detections`·`isConnected`·`isStarted` 등 세션 상태 getter와 `prepare`·`start` 추가. 위젯 연결 여부에 의존하던 `isAttached`와 시작 보류(pending start) 동작은 제거.

## 0.6.0

- `LiveStreamingController`가 위젯에 연결되기 전 호출된 `startAsReceiver`/`startAsSender`를 연결 직후 자동 실행하도록 수정.

## 0.5.0

- 수신 음성 출력을 켜고 끄는 `enableSpeaker` 필드와 `LiveStreamingController.setSpeakerEnabled` 추가.

## 0.4.0

- `LiveStreamingView`에 내장 컨트롤 UI를 끄는 `showControlPanel` 추가(끄면 영상+탐지 오버레이만 남는다).
- 코드에서 시작/종료/카메라 전환을 제어하는 `LiveStreamingController` 추가.
- 위젯이 뜨면 자동 연결하는 `autoStart`와 수신자용 `senderIp` 추가.
- 탐지 결과를 외부로 받는 `onDetected` 콜백과 송신자 자기 IP를 받는 `onLocalIpReady` 콜백 추가.
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
