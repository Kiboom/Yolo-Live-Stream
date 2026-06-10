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
  enableDetection: true,                     // false면 영상만(YOLO 끔)
  model: YoloModel.medium,                   // nano < small < medium < large < extraLarge
  detectionInterval: Duration(milliseconds: 400),
);
```

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

### Android — 자동

권한(`INTERNET`, `CAMERA`, `RECORD_AUDIO`), 카메라 기능, `usesCleartextTraffic`는 플러그인 매니페스트에
들어 있어 **앱 빌드 시 자동 병합**됩니다. 별도 작업이 필요 없습니다.
(앱에서 별도 `networkSecurityConfig`를 지정하면 `usesCleartextTraffic`가 덮어써질 수 있습니다.)

### iOS — 직접 추가 필요

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

## 동작 방법

두 기기를 **같은 Wi-Fi**에 연결합니다. (카메라는 실제 기기에서만 동작)

1. A 기기: `송신자`를 고르고 `송신 시작` → 화면에 `내 IP` 표시 (예: 192.168.0.12)
2. B 기기: `수신자`를 고르고 A의 IP를 입력한 뒤 `수신 시작`
3. 두 기기에 서로의 영상이 나타나고, 수신 측엔 YOLO 박스가 얹힙니다.

> 송신자(A)를 먼저 시작해야 합니다. 서버가 열려 있어야 수신자가 접속할 수 있습니다.

## YOLO 모델

- 첫 실행 시 모델을 자동 다운로드해 앱 문서 디렉터리에 캐시합니다.
  (iOS `<Documents>/yolo26m.mlpackage`, Android `<app_flutter>/yolo26m_int8.tflite`)
- COCO 80개 클래스 기준이라 그 범위 밖 물체는 비슷한 클래스로 뭉뚱그려질 수 있습니다.

## 예제

`example/`가 플러그인을 그대로 쓰는 동작 데모입니다.

```bash
cd example
flutter run
```
