# yolo_live_stream

같은 Wi-Fi의 두 모바일 기기끼리 **클라우드 없이** 카메라 영상을 실시간으로 주고받고,
수신 영상 위에 **YOLO 객체 탐지** 박스를 얹어주는 Flutter 플러그인입니다.

- 영상: WebRTC P2P 직접 전송 (`flutter_webrtc`)
- 시그널링: 한 기기가 작은 WebSocket 서버를 열고 다른 기기가 그 IP로 접속해 offer/answer 교환 (외부 서버 불필요)
- 객체 탐지: 수신 영상 프레임을 주기적으로 분석 (`ultralytics_yolo`, 기본 `yolo26m`)

## 설치

`pubspec.yaml`에 추가합니다.

```yaml
dependencies:
  yolo_live_stream:
    git:
      url: https://github.com/modoc-ai/yolo_live_stream.git
    # 또는 로컬 경로:
    # path: ../yolo_live_stream
```

## 사용법

### 1) 올인원 위젯 (가장 쉬움)

역할 선택, 영상 송수신, YOLO 오버레이가 모두 들어간 화면을 한 줄로 띄웁니다.

역할(송신/수신)은 위젯 바깥에서 정해 넘깁니다. 역할 선택 UI는 플러그인이 주는 `LiveStreamRoleSwitcher`를 쓰면 됩니다.

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
            LiveStreamRoleSwitcher(role: role, onChanged: (r) => setState(() => role = r)),
            Expanded(child: LiveStreamingView(role: role)),  // 객체 탐지 기본 ON
          ],
        ),
      ),
    );
  }
}
```

`role`이 런타임에 바뀌면 진행 중이던 연결을 정리하고 새 역할의 대기 상태로 돌아갑니다.

옵션:

```dart
LiveStreamingView(
  role: role,                                // 필수
  quality: VideoQuality.hd720,               // sd480 / hd720 / fullHd1080
  frameRate: 30,                             // 초당 프레임 수
  enableSpeaker: true,                       // false면 수신 음성을 출력하지 않음
  enableDetection: true,                     // false면 영상만(YOLO 끔)
  model: YoloModel.medium,                   // nano < small < medium < large < extraLarge
  customModelPath: null,                     // 커스텀 모델 경로(지정 시 model 무시)
  detectionInterval: Duration(milliseconds: 400),
  showControlPanel: true,                    // false면 영상+탐지 오버레이만 (내장 UI 숨김)
  autoStart: false,                          // true면 위젯이 뜨자마자 자동 연결
  senderIp: null,                            // autoStart 수신자가 접속할 송신자 IP
  onDetected: null,                          // (List<YOLOResult> results) { ... } 탐지 결과 콜백
  onLocalIpReady: null,                      // (String ip) { ... } 송신자 자기 IP 콜백
  dogPoseModelPath: null,                    // 직접 학습한 dog-pose 모델 경로(형식은 customModelPath와 같음)
  enableGrowlDetection: false,               // true면 수신 음성에서 으르렁 소리를 감지
  dogRiskAnalyzer: RuleBasedDogRiskAnalyzer(), // 강아지 위험도 판정 로직(직접 만든 DogRiskAnalyzer로 교체 가능)
  onDogRiskAnalyzed: null,                   // (DogRiskReport report) { ... } 강아지 위험도 콜백
);
```

### 1-1) 커스텀 UI로 쓰기 (컨트롤 패널 없이)

앱에 고유한 IP 입력, 시작/종료 UI가 있으면 `showControlPanel: false`로 내장 UI(IP 입력, 버튼, 상태 배지, PiP, 카메라 전환 버튼)를 끄고 영상+탐지 오버레이만 띄울 수 있습니다. 이땐 시작/종료를 아래 두 방법으로 제어합니다.

**자동 시작 (`autoStart`)**: 위젯이 화면에 올라오면 자동으로 연결하고, 사라지면 종료합니다. 수신자는 `senderIp`가 필요합니다.

```dart
LiveStreamingView(
  role: Role.receiver,
  showControlPanel: false,
  autoStart: true,
  senderIp: "192.168.0.12",
  onDetected: (results) {
    // TTS, 진동 등 앱 로직에 연결
  },
);
```

**컨트롤러 (`LiveStreamingController`)**: 코드에서 직접 시작/종료/카메라 전환을 호출합니다. 위젯을 띄운 채 연결만 켜고 끌 수 있습니다.

```dart
final controller = LiveStreamingController();

LiveStreamingView(
  role: Role.receiver,
  controller: controller,
  showControlPanel: false,
  onDetected: (results) { /* ... */ },
);

// 어디서든 명령형으로 제어:
await controller.startAsReceiver("192.168.0.12"); // 송신자면 controller.startAsSender()
await controller.switchCamera();
controller.setSpeakerEnabled(false); // 수신 음성 출력 끄기
await controller.stop();
// controller.localIp / isConnected / isStarted / isSpeakerEnabled 로 상태를 읽는다.
// ChangeNotifier라 controller.addListener(...)로 상태 변화를 구독할 수 있다.
```

송신자로 시작하면 `onLocalIpReady` 콜백(또는 `controller.localIp`)으로 자기 IP를 받아 수신자에게 알려줄 수 있습니다.

### 2) 조립형 (직접 화면을 꾸밀 때)

부품을 따로 가져와 직접 조합합니다.

- `LiveStreamingConnector`: WebRTC 연결/카메라/시그널링 담당
- `YoloAnalyzer`: 수신 트랙 프레임을 주기적으로 YOLO 분석
- `DetectionOverlay`: 수신 영상 + 탐지 박스 렌더링

```dart
final connection = LiveStreamingConnector(onUpdate: () => setState(() {}), onError: print);
await connection.initRenderers();
await connection.startAsSender();            // 또는 startAsReceiver("192.168.0.12")

final analyzer = YoloAnalyzer(
  onUpdate: () => setState(() {}),
  getRemoteTrack: () => connection.remoteVideoTrack,
);
await analyzer.start();

// 빌드에서:
DetectionOverlay(renderer: connection.remoteRenderer, detections: analyzer.detections);
```

## 권한 설정

### Android

권한(`INTERNET`, `CAMERA`, `RECORD_AUDIO`), 카메라 기능, `usesCleartextTraffic`는 플러그인 매니페스트에
들어 있어 **앱 빌드 시 자동 병합**됩니다. 별도 작업이 필요 없습니다.
(앱에서 별도 `networkSecurityConfig`를 지정하면 `usesCleartextTraffic`가 덮어써질 수 있습니다.)

#### compileSdk 설정 (직접 추가 필요)

`flutter_webrtc` 0.12.x는 compileSdk를 31로 고정합니다.
그런데 함께 받는 androidx 라이브러리는 34 이상을 요구해서 빌드가 실패합니다.
앱의 `android/build.gradle.kts`에 아래 블록을 추가해 `flutter_webrtc`의 compileSdk를 36으로 올려 주세요.
이 블록은 `project.evaluationDependsOn(":app")`이 들어 있는 `subprojects` 블록보다 앞에 넣어야 합니다.
(`example/android/build.gradle.kts` 참고)

```kotlin
// flutter_webrtc 0.12.x pins compileSdk 31, but its androidx dependencies need 34+ (checkAarMetadata fails).
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

iOS는 Pod이 앱의 `Info.plist`를 자동으로 수정할 수 없습니다. 플러그인을 쓰는 앱의
`ios/Runner/Info.plist`에 아래 키를 **직접 추가**하세요. (`example/ios/Runner/Info.plist` 참고)

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

#### CocoaPods 사용 (SwiftPM 끄기 권장)

이 플러그인의 iOS 부분은 CocoaPods에서만 동작합니다.
의존하는 `TensorFlowLiteSwift`와 `flutter_webrtc`가 SwiftPM을 지원하지 않기 때문입니다.
앱의 `pubspec.yaml`에서 SwiftPM을 꺼 두는 것을 권장합니다.
(`example/pubspec.yaml` 참고)

```yaml
flutter:
  config:
    enable-swift-package-manager: false
```

## 동작 방법

두 기기를 **같은 Wi-Fi**에 연결합니다. (카메라는 실제 기기에서만 동작)

1. A 기기: `송신자`를 고르고 `송신 시작` → 화면에 `내 IP` 표시 (예: 192.168.0.12)
2. B 기기: `수신자`를 고르고 A의 IP를 입력한 뒤 `수신 시작`
3. 두 기기에 서로의 영상이 나타나고, 수신 측엔 YOLO 박스가 얹힙니다.

> 송신자(A)를 먼저 시작해야 합니다. 서버가 열려 있어야 수신자가 접속할 수 있습니다.

## YOLO 모델

- `model`(`YoloModel` enum)을 쓰면 첫 실행 시 공식 모델을 자동 다운로드해 앱 문서 디렉터리에 캐시합니다.
  (iOS `<Documents>/yolo26m.mlpackage`, Android `<app_flutter>/yolo26m_int8.tflite`)
- COCO 80개 클래스 기준이라 그 범위 밖 물체는 비슷한 클래스로 뭉뚱그려질 수 있습니다.

### 커스텀 모델 (`customModelPath`)

직접 학습한 모델을 쓰려면 `customModelPath`에 경로를 넘깁니다(지정 시 `model` enum은 무시). 세 가지 형태를 받습니다.

1. **assets 번들 (권장)**: 앱의 assets에 모델을 넣고 pubspec에 등록한 뒤 `assets/`로 시작하는 경로 전달. 플러그인이 알아서 기기로 복사/압축 해제 후 로드합니다.
2. **URL**: `https://...` 경로. 런타임에 받아서 문서 디렉터리에 캐시합니다.
3. **기기 파일의 절대 경로**: 앱이 미리 받아둔 파일 경로.

**플랫폼별 모델 형식이 다릅니다.** 같은 모델이라도 둘 다 준비해 플랫폼에 맞는 경로를 넘기세요.
- Android: `.tflite` (예: int8 양자화)
- iOS: `.mlpackage.zip` (CoreML)

```dart
import "dart:io";

LiveStreamingView(
  role: role,
  customModelPath: Platform.isIOS
      ? "assets/models/my_yolo.mlpackage.zip"
      : "assets/models/my_yolo.tflite",
);
```

앱(플러그인을 쓰는 쪽)의 `pubspec.yaml`에 asset 등록:

```yaml
flutter:
  assets:
    - assets/models/
```

> 모델은 **detection(task=detect)** 모델이어야 합니다. ultralytics에서 export 시
> `yolo export format=tflite int8=True`(Android), `yolo export format=coreml`(iOS)로 내보냅니다.

## 강아지 위험도

수신 영상에서 강아지와 사람을 찾고, 강아지가 지금 사람에게 위협이 될 만한 상황인지 판정합니다.
결과는 `onDogRiskAnalyzed` 콜백으로 `DogRiskReport`를 받습니다.
판정은 기본 규칙(`RuleBasedDogRiskAnalyzer`)이 맡습니다.
앱이 직접 만든 판정 로직으로 바꿀 수도 있습니다([판정 로직 바꾸기](#판정-로직-바꾸기)).

### 판정 항목

아래 판정 항목과 위험도 규칙은 기본 규칙(`RuleBasedDogRiskAnalyzer`)의 동작입니다.

| 항목 | 필드 | 판정 방법 |
| --- | --- | --- |
| 거리 | `distance` | 가장 가까운 사람 박스와 강아지 박스 사이 간격을 강아지 박스 긴 변으로 나눈 값입니다. 겹치면 0입니다. |
| 자세 | `posture` | 키포인트 위치로 서 있음(`standing`), 앉음(`sitting`), 엎드림(`lying`)을 가립니다. 판정할 수 없으면 `unknown`입니다. |
| 시선 | `isFacingPerson` | 머리 방향과 사람 방향 사이 각도가 `facingAngleDegrees` 안쪽이면 사람 쪽을 본다고 판정합니다. |
| 긴장 신호 | `isTailRaised`, `isHeadLoweredForward` | 꼬리가 높이 들렸는지, 머리를 낮추고 앞으로 쏠렸는지 봅니다. |
| 으르렁 | `growlScore` | 수신 음성을 YAMNet으로 분석한 Growling 점수입니다. |
| 위험도 | `level` | 위 항목을 합쳐 `low`, `caution`, `high`로 냅니다. |

위험도 규칙은 다음과 같습니다.

| 조건 | 위험도 |
| --- | --- |
| 가까움 + (으르렁 또는 (사람 쪽을 봄 + 긴장 신호)) | `high` |
| 가까움, 또는 거리와 상관없이 으르렁 | `caution` |
| 그 밖 | `low` |

"가까움"은 `distance`가 `nearDistance`보다 작은 경우입니다.
"으르렁"은 `growlScore`가 `growlScore` 임계값 이상인 경우입니다.
"긴장 신호"는 꼬리가 들렸거나 머리를 낮추고 앞으로 쏠린 경우입니다.
긴장 신호는 강아지가 가까이 있으면서 사람 쪽을 볼 때만 위험도를 올립니다.
`nearDistance`, `growlScore`, `facingAngleDegrees`는 `DogRiskThresholds`의 임계값입니다.

### 포즈 모델이 없을 때

`dogPoseModelPath`를 넘기지 않으면 거리와 으르렁만으로 판정합니다.
이때 `posture`, `isFacingPerson`, `isTailRaised`, `isHeadLoweredForward`는 `null`입니다.

### 사용 예

```dart
import "dart:io";

LiveStreamingView(
  role: Role.receiver,
  enableGrowlDetection: true,
  dogPoseModelPath: Platform.isIOS
      ? "assets/models/dog_pose.mlpackage.zip"
      : "assets/models/dog_pose.tflite",
  dogRiskAnalyzer: const RuleBasedDogRiskAnalyzer(
    thresholds: DogRiskThresholds(nearDistance: 0.5, growlScore: 0.5),
  ),
  onDogRiskAnalyzed: (DogRiskReport report) {
    if (report.level == DogRiskLevel.high) {
      // 보호자에게 알림
    }
  },
);
```

### 판정 로직 바꾸기

`DogRiskAnalyzer`를 상속한 클래스를 만들어 `dogRiskAnalyzer`로 넘기면 판정 로직을 바꿀 수 있습니다.
넘기지 않으면 기본 규칙(`RuleBasedDogRiskAnalyzer`)을 씁니다.
`LiveStreamingController`에도 같은 이름의 매개변수가 있습니다.

| 메서드 | 플러그인이 부르는 때 | 할 일 |
| --- | --- | --- |
| `analyze(DogRiskSignals signals)` | 영상 프레임을 분석했을 때(`detectionInterval`, 기본 0.4초마다)와 소리 점수가 들어왔을 때(약 0.5초마다) | `DogRiskReport`를 돌려줍니다. |
| `reset()` | 연결을 멈추거나 다시 시작할 때 | 쌓아 둔 기록을 지웁니다. |

탐지를 껐거나 영상이 없어도 소리 점수가 들어오면 `analyze`를 부릅니다.
플러그인은 세션 내내 같은 인스턴스를 씁니다.
그래서 여러 번의 `analyze` 사이에 기록을 쌓을 수 있습니다.

`analyze`에 들어오는 `DogRiskSignals`의 필드는 다음과 같습니다.

| 필드 | 타입 | 내용 |
| --- | --- | --- |
| `detections` | `List<YOLOResult>` | detect 모델 결과 전체(COCO 80종)입니다. 탐지를 껐거나 아직 프레임이 없으면 빈 리스트입니다. |
| `dogPoses` | `List<YOLOResult>?` | dog-pose 모델 결과(키포인트 24개)입니다. 포즈 모델이 없으면 `null`입니다. |
| `sound` | `SoundScores?` | YAMNet이 낸 521종 소리 점수(0~1)입니다. 으르렁 감지를 껐거나 아직 소리가 없으면 `null`입니다. |

소리 점수는 `signals.sound?["Growling"]`처럼 레이블 이름으로 꺼냅니다.
YAMNet 레이블이 아닌 이름을 넣으면 `ArgumentError`가 납니다.
전체 레이블 목록은 `SoundScores.labels`에 있습니다.
쓸 만한 레이블은 다음과 같습니다.

| 레이블 | 번호 | 소리 |
| --- | --- | --- |
| `Growling` | 74 | 으르렁 |
| `Bark` | 70 | 짖음 |
| `Whimper (dog)` | 75 | 강아지 낑낑거림 |
| `Baby cry, infant cry` | 20 | 아기 울음 |
| `Screaming` | 11 | 비명 |
| `Crying, sobbing` | 19 | 울음 |

아래 예시는 으르렁이 4번 연속(약 2초) 이어질 때만 위험도를 `high`로 판정합니다.
자기만의 값(여기서는 0~100 점수)은 `DogRiskReport`를 상속한 클래스에 담아 돌려줍니다.

```dart
class MyReport extends DogRiskReport {
  const MyReport({required super.level, super.growlScore, required this.score});

  final int score;
}

class MyDogRiskAnalyzer extends DogRiskAnalyzer {
  SoundScores? _lastSound;
  int _growlCount = 0;

  @override
  DogRiskReport analyze(DogRiskSignals signals) {
    final SoundScores? sound = signals.sound;
    // analyze는 영상 프레임이 들어올 때도 불리므로, 새 소리 점수가 왔을 때만 셉니다.
    if (sound != null && !identical(sound, _lastSound)) {
      _lastSound = sound;
      _growlCount = sound["Growling"] >= 0.5 ? _growlCount + 1 : 0;
    }
    final double? growlScore = sound?["Growling"];
    return MyReport(
      // 소리 점수는 약 0.5초마다 들어오므로 4번이면 약 2초입니다.
      level: _growlCount >= 4 ? DogRiskLevel.high : DogRiskLevel.low,
      growlScore: growlScore,
      score: ((growlScore ?? 0) * 100).round(),
    );
  }

  @override
  void reset() {
    _lastSound = null;
    _growlCount = 0;
  }
}

LiveStreamingView(
  role: Role.receiver,
  enableGrowlDetection: true,
  dogRiskAnalyzer: MyDogRiskAnalyzer(),
  onDogRiskAnalyzed: (DogRiskReport report) {
    if (report is MyReport) {
      // report.score를 앱 화면에 보여 줍니다.
    }
  },
);
```

`onDogRiskAnalyzed`는 `DogRiskReport` 타입으로 받습니다.
직접 만든 클래스의 값은 `MyReport`로 형 변환해 꺼냅니다.
예시처럼 `report is MyReport`로 확인하면 그 블록 안에서 자동으로 형 변환됩니다.
오버레이의 위험도 배지는 `level`만 씁니다.

`analyze`가 예외를 던지면 플러그인은 다음과 같이 처리합니다.

| 상황 | 플러그인 동작 |
| --- | --- |
| 예외가 처음 남 | 위험도를 비우고 `onError`로 `위험도 판정 실패: ...`를 알립니다. |
| 예외가 계속 이어짐 | 다시 알리지 않습니다. |
| 판정이 한 번 성공한 뒤 다시 예외가 남 | 다시 알립니다. |

### 포즈 모델 학습

Ultralytics는 학습된 dog-pose 가중치를 공개하지 않습니다.
그래서 포즈 모델은 직접 학습해서 넘겨야 합니다.
학습 스크립트는 `tool/train_dog_pose.py`에 있으며, [dog-pose 데이터셋](https://docs.ultralytics.com/datasets/pose/dog-pose)으로 `yolo26n-pose`를 학습합니다.

```bash
pip install -r tool/requirements.txt
python3 tool/train_dog_pose.py --epochs 100 --imgsz 640 --model yolo26n-pose.pt --export both
```

1. 데이터셋은 첫 실행 때 ultralytics가 자동으로 내려받습니다.
2. 학습이 끝나면 `--export` 값에 따라 모델을 내보냅니다. `tflite`는 Android용 `.tflite`, `coreml`은 iOS용 `.mlpackage.zip`, `both`(기본값)는 둘 다 내보냅니다.
3. 두 파일을 앱의 `assets/models/`에 넣고, 플랫폼에 맞는 경로를 `dogPoseModelPath`로 넘깁니다. example 앱의 `example/assets/models/`에 이렇게 만든 파일이 들어 있습니다.

장치는 CUDA, MPS, CPU 순서로 자동 선택하며, `--device`로 직접 지정할 수 있습니다.
CPU로 학습하면 매우 오래 걸리므로 GPU를 권장합니다.
TFLite 내보내기는 macOS의 Python 3.13 이상에서 막히고, Core ML 내보내기는 Windows에서 되지 않습니다.
그래서 Linux(예: Colab)에서 `--export both`로 두 모델을 한 번에 내보내는 것을 권장합니다.
macOS에서는 Python 3.12를 쓰면 두 모델을 한 번에 내보낼 수 있습니다.

`--weights`에 이미 학습한 `.pt` 파일을 넘기면 학습을 건너뛰고 내보내기만 합니다.
그래서 두 플랫폼 모델을 만들 때 학습은 한 번만 하면 됩니다.

```bash
# Colab: 학습한 best.pt로 두 플랫폼 모델을 한 번에 내보내기
python3 tool/train_dog_pose.py --weights best.pt --export both
```

Android 설정은 `ultralytics_yolo` 공식 모델과 다릅니다.
키포인트가 17개가 아니면 플러그인 Android 코드가 end-to-end 출력만 받기 때문입니다.

| 플랫폼 | 형식 | 설정 |
| --- | --- | --- |
| Android | `.tflite` | `quantize="w8a32"`(동적 int8), `nms=False`(end-to-end), 입력 `[1, 640, 640, 3]` |
| iOS | `.mlpackage.zip` | `quantize=8`, `nms=False`(end-to-end) |

스크립트는 내보낸 TFLite의 입력과 출력 모양을 확인하고, 플러그인이 읽을 수 없는 모양이면 실패합니다.

Ultralytics의 `export()`를 기본값으로 직접 호출해 내보낸 파일은 쓸 수 없습니다.
TFLite는 입력이 `[1, 3, 640, 640]`, 출력이 `[1, 77, 8400]`으로 나와 Android에서 모델을 불러올 때 "Unexpected output feature size" 오류가 납니다.
Core ML은 `.mlpackage` 폴더를 통째로 zip으로 묶어야 합니다. 폴더 안의 `model.mlmodel`과 `weight.bin`만 꺼내 쓰면 모델을 불러오지 못합니다.
Colab에서 학습했다면 `best.pt`를 받아 이 스크립트의 `--weights`로 내보내 주세요.

### 으르렁 감지

으르렁 감지는 수신 기기에서 받은 음성으로 분석합니다.
`enableSpeaker: false`로 스피커를 꺼도 분석은 계속됩니다.
YAMNet 모델은 플러그인에 들어 있어 따로 준비할 필요가 없습니다.

### 한계

| 한계 | 내용 |
| --- | --- |
| 자세와 시선 | 규칙 기반이라 옆모습에서는 괜찮지만, 정면이나 뒷모습에서는 정확도가 떨어집니다. |
| 긴장 신호 | 꼬리가 들리는 모습은 놀 때도 나와 오탐이 많습니다. |
| 거리 | 화면은 평면이라 카메라 기준 앞뒤 거리를 알 수 없습니다. |
| 으르렁 | YAMNet은 놀이 중 으르렁과 공격 전 으르렁을 구분하지 못합니다. |
| 용도 | 이 위험도는 보호자가 한 번 살펴볼 순간을 알려 주는 수준입니다. 안전을 보장하지 않습니다. |

임계값은 `RuleBasedDogRiskAnalyzer(thresholds: DogRiskThresholds(...))`로 조정할 수 있습니다.
판정 방식 자체를 바꾸려면 [판정 로직 바꾸기](#판정-로직-바꾸기)를 참고해 주세요.

## 예제

`example/`가 플러그인을 그대로 쓰는 동작 데모입니다.

```bash
cd example
flutter run
```
