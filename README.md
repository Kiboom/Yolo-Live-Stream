# yolo_live_stream

같은 Wi-Fi에 연결된 두 모바일 기기가 **클라우드 없이** 카메라 영상을 실시간으로 주고받고,
수신 영상에 **YOLO 객체 탐지** 결과를 표시하는 Flutter 플러그인입니다.

- 영상: WebRTC P2P 직접 전송 (`flutter_webrtc`)
- 시그널링: 한 기기가 WebSocket 서버를 열고, 다른 기기가 해당 IP로 접속해 offer/answer 교환
- 객체 탐지: 수신 영상 프레임을 주기적으로 분석 (`ultralytics_yolo`, 기본 모델 `yolo26m`)

## 설치

`pubspec.yaml`에 추가합니다.

```yaml
dependencies:
  yolo_live_stream: ^0.13.0
```

## 사용법

### 1) 올인원 위젯

영상 송수신과 YOLO 오버레이를 위젯 하나로 구성합니다. 송신자·수신자 역할은 외부에서 정해 넘기며,
역할 선택 UI가 필요하면 `LiveStreamRoleSwitcher`를 사용합니다.

```dart
import "package:yolo_live_stream/yolo_live_stream.dart";

class _HomeState extends State<Home> {
  Role role = Role.sender;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            LiveStreamRoleSwitcher(
              role: role,
              onChanged: (nextRole) => setState(() => role = nextRole),
            ),
            Expanded(child: LiveStreamingView(role: role)), // 객체 탐지 기본값: 켬
          ],
        ),
      ),
    );
  }
}
```

실행 중 `role`이 바뀌면 기존 연결을 종료하고 새 역할의 대기 상태로 전환합니다.

주요 옵션은 다음과 같습니다.

```dart
LiveStreamingView(
  role: role,                                // 필수
  quality: VideoQuality.hd720,               // sd480 / hd720 / fullHd1080
  frameRate: 30,                             // 초당 프레임 수
  enableSpeaker: true,                       // false면 수신 음성을 재생하지 않음
  enableDetection: true,                     // false면 YOLO 탐지 없이 영상만 표시
  model: YoloModel.medium,                   // nano < small < medium < large < extraLarge
  customModelPath: null,                     // 지정하면 model 옵션을 무시
  detectionInterval: Duration(milliseconds: 400),
  showControlPanel: true,                    // false면 내장 UI를 숨김
  autoStart: false,                          // true면 위젯을 표시할 때 자동 연결
  senderIp: null,                            // 자동 연결할 송신자 IP
  onDetected: null,                          // (List<YOLOResult> results) { ... } 탐지 결과 콜백
  onLocalIpReady: null,                      // (String ip) { ... } 송신자 IP 콜백
  dogPoseModelPath: null,                    // 직접 학습한 dog-pose 모델 경로
  enableGrowlDetection: false,               // true면 수신 음성의 으르렁 소리를 감지
  dogRiskAnalyzer: RuleBasedDogRiskAnalyzer(), // 강아지 위험도 판정 로직
  onDogRiskAnalyzed: null,                   // (DogRiskReport report) { ... } 강아지 위험도 콜백
);
```

### 내장 UI 없이 사용하기

앱에 별도의 IP 입력이나 시작·종료 UI가 있다면 `showControlPanel: false`로 내장 UI를 숨길 수 있습니다.
이 경우 영상과 탐지 오버레이만 표시되며, 연결은 다음 두 방식으로 제어합니다.

**자동 시작 (`autoStart`)**: 위젯이 나타나면 자동으로 연결하고, 사라지면 종료합니다. 수신자는 `senderIp`를 지정해야 합니다.

```dart
LiveStreamingView(
  role: Role.receiver,
  showControlPanel: false,
  autoStart: true,
  senderIp: "192.168.0.12",
  onDetected: (results) {
    // TTS, 진동 등 앱 기능과 연동
  },
);
```

**컨트롤러 (`LiveStreamingController`)**: 코드에서 연결 시작·종료와 카메라 전환을 직접 제어합니다.

```dart
final controller = LiveStreamingController();

LiveStreamingView(
  role: Role.receiver,
  controller: controller,
  showControlPanel: false,
  onDetected: (results) { /* ... */ },
);

// 필요한 곳에서 직접 제어
await controller.startAsReceiver("192.168.0.12"); // 송신자면 controller.startAsSender()
await controller.switchCamera();
controller.setSpeakerEnabled(false); // 수신 음성 재생 끄기
await controller.stop();
// localIp, isConnected, isStarted, isSpeakerEnabled로 상태를 확인합니다.
// addListener(...)로 상태 변경을 구독할 수 있습니다.
```

송신자로 시작하면 `onLocalIpReady` 콜백이나 `controller.localIp`로 IP를 확인해 수신자에게 전달할 수 있습니다.

### 구성 요소 직접 조합하기

필요한 구성 요소를 직접 조합할 수도 있습니다.

- `LiveStreamingConnector`: WebRTC 연결, 카메라, 시그널링 처리
- `YoloAnalyzer`: 수신 영상 프레임을 주기적으로 분석
- `DetectionOverlay`: 수신 영상과 탐지 박스 표시

```dart
final connection = LiveStreamingConnector(
  onUpdate: () => setState(() {}),
  onError: print,
);
await connection.initRenderers();
await connection.startAsSender(); // 또는 startAsReceiver("192.168.0.12")

final analyzer = YoloAnalyzer(
  onUpdate: () => setState(() {}),
  getRemoteTrack: () => connection.remoteVideoTrack,
);
await analyzer.start();

// build 메서드에서 사용
DetectionOverlay(renderer: connection.remoteRenderer, detections: analyzer.detections);
```

## 권한 설정

### Android

`INTERNET`, `CAMERA`, `RECORD_AUDIO` 권한과 카메라 기능, `usesCleartextTraffic` 설정은 앱 빌드 시
자동으로 병합됩니다. 단, 앱에서 `networkSecurityConfig`를 별도로 사용하면 네트워크 설정을 확인해야 합니다.

#### compileSdk 설정

`flutter_webrtc` 0.12.x와 AndroidX의 compileSdk 요구 버전이 달라 빌드가 실패할 수 있습니다.
앱의 `android/build.gradle.kts`에서 `flutter_webrtc`의 compileSdk를 36으로 지정하세요. 아래 코드는
`project.evaluationDependsOn(":app")`이 있는 `subprojects` 블록보다 앞에 두어야 합니다.

```kotlin
// flutter_webrtc와 AndroidX의 compileSdk 요구 버전을 맞춥니다.
subprojects {
    if (name == "flutter_webrtc") {
        afterEvaluate {
            extensions.configure<com.android.build.api.dsl.LibraryExtension> { compileSdk = 36 }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}
```

### iOS

플러그인을 사용하는 앱의 `ios/Runner/Info.plist`에 다음 항목을 직접 추가하세요.

```xml
<key>NSCameraUsageDescription</key>
<string>카메라 영상 전송을 위해 필요합니다.</string>
<key>NSMicrophoneUsageDescription</key>
<string>영상 통화 기능을 위해 필요합니다.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>같은 Wi-Fi의 기기와 영상을 주고받기 위해 필요합니다.</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

#### CocoaPods 사용

`TensorFlowLiteSwift`와 `flutter_webrtc`가 SwiftPM을 지원하지 않으므로 iOS에서는 CocoaPods를 사용해야 합니다.
앱의 `pubspec.yaml`에서 SwiftPM을 비활성화하세요.

```yaml
flutter:
  config:
    enable-swift-package-manager: false
```

## 동작 방법

두 기기를 **같은 Wi-Fi**에 연결합니다. 카메라는 실제 기기에서만 동작합니다.

1. A 기기에서 `송신자`를 선택하고 `송신 시작`을 누릅니다.
2. B 기기에서 `수신자`를 선택한 뒤, 화면에 표시된 A의 IP를 입력하고 `수신 시작`을 누릅니다.
3. 연결되면 두 기기에 영상이 표시되고, 수신 영상에는 YOLO 탐지 박스가 나타납니다.

> 송신자(A)를 먼저 시작해야 합니다. 서버가 열려 있어야 수신자가 접속할 수 있습니다.

## YOLO 모델

- `model`에 `YoloModel` 값을 지정하면 처음 실행할 때 공식 모델을 내려받아 앱 문서 디렉터리에 저장합니다.
  (iOS `<Documents>/yolo26m.mlpackage`, Android `<app_flutter>/yolo26m_int8.tflite`)
- 기본 모델은 COCO 80개 클래스만 지원하므로, 그 밖의 물체는 비슷한 클래스로 잘못 분류될 수 있습니다.

### 커스텀 모델 (`customModelPath`)

직접 학습한 모델은 `customModelPath`에 지정합니다. 이 값이 있으면 `model`은 사용하지 않습니다.

지원하는 경로는 다음과 같습니다.

1. **에셋 경로(권장)**: `assets/`로 시작하는 경로
2. **URL**: 실행 중 내려받아 앱 문서 디렉터리에 저장
3. **절대 경로**: 기기에 저장된 모델 파일 경로

두 플랫폼을 모두 지원하려면 형식에 맞는 파일을 각각 준비해야 합니다.

- Android: `.tflite` (동적 int8 양자화)
- iOS: `.mlpackage.zip` (CoreML, int8 양자화)

제공된 스크립트를 사용하면 학습한 가중치(`.pt`)를 두 형식으로 내보낼 수 있습니다.

```bash
pip install -r tool/requirements.txt
python3 tool/export_custom_model.py --weights best.pt --export both
```

`--export`에는 `tflite`, `coreml`, `both`(기본값) 중 하나를 지정하고, 입력 크기는 `--imgsz`(기본값 640)로 바꿀 수 있습니다.
스크립트는 내보낸 파일을 플러그인이 읽을 수 있는지 검사하고, 읽을 수 없으면 실패합니다.

```dart
import "dart:io";

LiveStreamingView(
  role: role,
  customModelPath: Platform.isIOS
      ? "assets/models/my_yolo.mlpackage.zip"
      : "assets/models/my_yolo.tflite",
);
```

에셋을 사용한다면 앱의 `pubspec.yaml`에도 등록합니다.

```yaml
flutter:
  assets:
    - assets/models/
```

> **detection(`task=detect`)** 모델만 지원합니다.
> 플러그인이 읽는 입력 레이아웃과 텐서 이름이 정해져 있으므로 Ultralytics의 `export()`를 직접 호출하지 말고 제공된 스크립트를 사용하세요.
> 두 플랫폼용 모델을 함께 만들려면 Linux 환경이나 Python 3.12가 설치된 macOS를 권장합니다.

## 강아지 위험도

수신 영상과 음성을 분석해 강아지의 위험도를 `low`, `caution`, `high`로 판정합니다.
결과는 `onDogRiskAnalyzed`에서 `DogRiskReport`로 받을 수 있습니다.

### 사용법

```dart
import "dart:io";

LiveStreamingView(
  role: Role.receiver,
  enableGrowlDetection: true,
  dogPoseModelPath: Platform.isIOS
      ? "assets/models/dog_pose.mlpackage.zip"
      : "assets/models/dog_pose.tflite",
  onDogRiskAnalyzed: (DogRiskReport report) {
    if (report.level == DogRiskLevel.high) {
      // 보호자에게 알림
    }
  },
);
```

내장 위험도 배지는 `enableDetection: true`일 때만 표시됩니다. 탐지를 끈 경우 결과는
`onDogRiskAnalyzed` 콜백으로만 받을 수 있습니다.

기본 판정은 사람과 강아지의 거리, 강아지의 시선·자세, 으르렁 점수를 조합합니다.

| 조건 | 위험도 |
| --- | --- |
| 가까이 있으면서, 으르렁거리거나 사람을 향해 긴장 자세를 보임 | `high` |
| 가까이 있거나 으르렁거림 | `caution` |
| 그 밖의 상황 | `low` |

`dogPoseModelPath`를 생략하면 자세·시선·긴장 신호는 판정에서 제외됩니다. 임계값은 `DogRiskThresholds`로
조정할 수 있습니다. 으르렁 점수와 임계값은 모두 `float32` 정밀도로 비교하므로 `0.7` 같은 임계값도 정확히 동작합니다.

### 판정 방식 바꾸기

`DogRiskAnalyzer`를 구현해 `dogRiskAnalyzer`에 전달하면 기본 판정 방식을 바꿀 수 있습니다.
`LiveStreamingView`는 처음 전달받은 인스턴스를 세션 내내 사용합니다. 따라서 `build()` 안에서 새로 만들지 말고,
`State` 필드에 한 번만 생성해 전달하세요.

```dart
class _HomeState extends State<Home> {
  final MyDogRiskAnalyzer _dogRiskAnalyzer = MyDogRiskAnalyzer();

  @override
  Widget build(BuildContext context) {
    return LiveStreamingView(
      role: Role.receiver,
      dogRiskAnalyzer: _dogRiskAnalyzer,
      onDogRiskAnalyzed: (report) {
        // 판정 결과 처리
      },
    );
  }
}
```

`analyze()`와 `reset()`에서 발생한 예외는 같은 방식으로 처리합니다. 예외가 연속해서 발생하면 첫 번째만
`onError`로 알리고, 판정에 성공하거나 연결을 새로 시작한 뒤 발생한 예외는 다시 알립니다.

### 포즈 모델 준비

포즈 분석에는 직접 학습한 모델이 필요합니다. 제공된 스크립트는
[dog-pose 데이터셋](https://docs.ultralytics.com/datasets/pose/dog-pose)으로 모델을 학습하고 Android·iOS용 파일을 만듭니다.

```bash
pip install -r tool/requirements.txt
python3 tool/train_dog_pose.py --epochs 100 --imgsz 640 --model yolo26n-pose.pt --export both
```

생성된 `.tflite`와 `.mlpackage.zip` 파일을 앱의 `assets/models/`에 넣고, 플랫폼에 맞는 경로를
`dogPoseModelPath`로 전달합니다. 이미 학습한 모델은 `--weights best.pt` 옵션으로 변환만 할 수 있습니다.
0.12.0 스크립트로 만든 `.tflite`는 Android에서 불러오지 못하므로, 이 옵션으로 다시 내보내세요.

> 모델 형식과 출력 구조가 정해져 있으므로 Ultralytics의 `export()`를 직접 호출하지 말고 제공된 스크립트를 사용하세요.
> 두 플랫폼용 모델을 함께 만들려면 Linux 환경이나 Python 3.12가 설치된 macOS를 권장합니다.

포즈 모델을 불러오지 못해도 사람과 강아지 탐지는 계속합니다.
이때 `onError`로 `포즈 모델 로드 실패: ...`를 한 번 알리고, 위험도는 거리와 으르렁 점수만으로 판정합니다.

으르렁 소리는 내장된 YAMNet 모델로 분석하며, 스피커를 꺼도 감지는 계속됩니다. YAMNet 모델의 출력이
521종이 아니면 모델을 불러올 때 으르렁 감지를 시작하지 못합니다. 이때 `onError`로
`으르렁 감지 시작 실패: ...`를 알리며, 영상 분석은 계속합니다.

> 영상과 음성만으로 실제 거리나 의도를 정확히 판단할 수는 없습니다. 보호자의 확인을 돕는 보조 수단으로만 사용하세요.

## 예제

`example/`에서 플러그인의 전체 동작을 확인할 수 있습니다.

```bash
cd example
flutter run
```
