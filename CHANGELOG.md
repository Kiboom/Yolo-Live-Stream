## 0.11.0

- 강아지 위험도 분석 추가. 수신 영상의 강아지와 사람 사이 거리, 자세, 시선, 긴장 신호, 으르렁 소리를 합쳐 위험도(`low`, `caution`, `high`)를 판정한다.
- `LiveStreamingView`와 `LiveStreamingController`에 `dogPoseModelPath`, `enableGrowlDetection`(기본 false), `dogRiskAnalyzer`(기본 `RuleBasedDogRiskAnalyzer()`), `onDogRiskAnalyzed` 추가.
- 판정 로직을 앱이 주입할 수 있다. `DogRiskAnalyzer`를 상속한 클래스를 `dogRiskAnalyzer`로 넘기면 기본 규칙 대신 그 로직으로 판정한다.
- 플러그인은 세션 동안 같은 판정 로직 인스턴스를 쓰므로 판정 사이에 기록을 쌓을 수 있다. 연결을 멈추거나 다시 시작하면 `reset()`을 부른다.
- 영상 프레임을 분석할 때와 소리 점수가 들어올 때 모두 판정한다. 탐지를 껐거나 영상이 없어도 소리가 오면 판정한다.
- 판정 로직이 예외를 던지면 위험도를 비우고 `onError`로 `위험도 판정 실패: ...`를 한 번 알린다. 예외가 이어지면 다시 알리지 않고, 판정이 성공하거나 연결을 새로 시작한 뒤에는 다시 알린다.
- 기본 규칙은 으르렁 점수와 임계값을 같은 float32 정밀도로 비교한다. 임계값 0.7도 정확히 동작한다.
- 내장 화면의 위험도 배지는 탐지를 켰을 때만 그린다. 탐지를 끄면 판정 결과는 `onDogRiskAnalyzed`로만 받는다.
- YAMNet 모델의 출력이 521종이 아니면 모델을 불러올 때 으르렁 감지 시작이 실패하고 `onError`로 `으르렁 감지 시작 실패: ...`를 알린다. 영상 분석은 계속한다.
- 기본 규칙은 `RuleBasedDogRiskAnalyzer`로 공개. 임계값은 `RuleBasedDogRiskAnalyzer(thresholds: DogRiskThresholds(...))`로 넘긴다.
- 판정 입력 `DogRiskSignals` 공개. detect 모델 결과 전체(COCO 80종), dog-pose 모델 결과, 소리 점수를 담는다.
- 소리 점수 `SoundScores` 공개. 으르렁 점수 하나가 아니라 YAMNet 521종 점수를 모두 넘기며, `signals.sound?["Growling"]`처럼 레이블 이름으로 꺼낸다. 전체 레이블은 `SoundScores.labels`에 있다.
- `DogRiskReport`, `DogRiskLevel`, `DogPosture`, `DogRiskThresholds`, `DogRiskAnalyzer` 공개. `DogRiskReport`를 상속하면 앱만의 값을 담아 돌려줄 수 있다.
- 포즈 모델은 사용자가 직접 학습해 넘긴다. 학습 스크립트 `tool/train_dog_pose.py` 추가. 포즈 모델이 없으면 거리와 으르렁만으로 판정한다.
- 학습 스크립트는 Android용 TFLite를 동적 int8, end-to-end 출력, NHWC 입력으로 내보내고, 플러그인이 읽을 수 없는 모양이면 실패한다. 키포인트가 24개라 공식 설정(`end2end=False`)으로 내보내면 Android에서 모델을 불러오지 못한다.
- example 앱에 학습한 dog-pose 모델(`example/assets/models/dog_pose.tflite`, `dog_pose.mlpackage.zip`)을 넣었다.
- 으르렁 감지용 YAMNet 모델을 플러그인에 포함. 수신 기기에서 분석하며 스피커를 꺼도 동작한다.
- README에 Android 빌드 안내 추가. `flutter_webrtc` 0.12.x의 compileSdk 31이 androidx 요구 버전(34 이상)보다 낮아 빌드가 실패하므로, 앱의 `android/build.gradle.kts`에서 compileSdk를 36으로 올리는 설정이 필요하다.
- README에 iOS 빌드 안내 추가. `TensorFlowLiteSwift`와 `flutter_webrtc`가 SwiftPM을 지원하지 않아 iOS는 CocoaPods 전용이며, 앱 `pubspec.yaml`에 `enable-swift-package-manager: false`를 권장한다.

## 0.10.0

- 반복 연결/종료 후 YOLO 탐지가 멈추던 버그 수정. 종료가 분석 도중(captureFrame, predict)에 일어나 트랙이 폐기되면 in-flight 호출이 끝나지 않아 `_isBusy`가 true로 박히고, 재연결해도 매 프레임이 즉시 건너뛰어졌다. `stop`에서 `_isBusy`를 리셋해 재시작이 항상 깨끗하도록 한다.
- `enableSpeaker: false`일 때 앱 전체 소리가 음소거되던 버그 수정. flutter_webrtc 기본값(MODE_IN_COMMUNICATION + 오디오 포커스 점유)이 기기 오디오를 통신 모드로 가져가 앱의 TTS 등 미디어 소리까지 죽였다. 수신 음성을 끈 경우 세션을 미디어 오디오 모드로 시작해 앱 소리를 건드리지 않는다.

## 0.9.0

- 0.8.0의 facing 기반 자동 미러를 제거하고, 수동 좌우반전으로 대체. iOS, Android 모두에서 연결마다 영상 미러가 들쭉날쭉하던 문제를 사용자 토글로 해결한다.
- `LiveStreamingController.mirror`, `setMirror`, `toggleMirror` 추가. 한쪽이 토글하면 상대에게 신호로 전달돼 양쪽 표시(영상, 탐지 박스)가 함께 뒤집힌다.
- `LiveStreamingView.showMirrorButton`(기본 false) 추가. 켜면 좌우반전 토글 버튼이 보인다.
- `LiveStreamingView.showPip`(기본 true) 추가. false면 우상단 보조 영상(PiP)을 숨긴다.

## 0.8.0

- 송신자가 현재 카메라 방향(전/후면)을 수신자에게 신호로 보내고, 수신자는 송신 카메라가 전면일 때만 받은 영상과 YOLO 탐지 박스를 좌우반전해 표시한다. 전면 카메라 영상이 수신 측에서 거울처럼 뒤집혀 보이던 문제를 바로잡는다.
- `LiveStreamingController.remoteIsFrontCamera` getter와 `DetectionOverlay.mirror` 옵션 추가.

## 0.7.0

- `LiveStreamingController`가 영상 세션(WebRTC 연결, 렌더러, YOLO 분석기)을 직접 소유하도록 변경. 같은 controller를 여러 `LiveStreamingView`에 넘기면 화면이 바뀌어도 같은 연결을 끊김 없이 이어서 그린다(예: 작은 카드에서 전체화면으로 전환).
- `LiveStreamingView`는 controller가 있으면 그 세션을 그리기만 한다. controller를 넘기지 않으면 위젯이 내부 세션을 만들어 단독으로 동작하므로 기존 사용 방식은 그대로 호환된다.
- 세션 설정(quality, enableSpeaker, enableDetection, model, customModelPath, detectionInterval, onDetected, onLocalIpReady, onError)을 `LiveStreamingController` 생성자로도 받는다.
- `LiveStreamingController`에 `detections`, `isConnected`, `isStarted` 등 세션 상태 getter와 `prepare`, `start` 추가. 위젯 연결 여부에 의존하던 `isAttached`와 시작 보류(pending start) 동작은 제거.

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
