import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_webrtc/flutter_webrtc.dart";

/// 카메라 해상도 프리셋(가로 x 세로).
enum VideoQuality {
  sd480(640, 480),
  hd720(1280, 720),
  fullHd1080(1920, 1080);

  const VideoQuality(this.width, this.height);

  final int width;
  final int height;
}

/// 같은 Wi-Fi의 두 기기를 WebRTC로 직접 연결해 영상을 주고받는다.
/// 송신자가 작은 서버를 열고, 수신자가 그 서버에 접속해 연결 정보(offer/answer)를 교환한다.
class LiveStreamingConnector {
  LiveStreamingConnector({
    required this.onUpdate,
    required this.onError,
    this.quality = VideoQuality.hd720,
    this.frameRate = 30,
    this.isRemoteAudioEnabled = true,
  });

  /// 카메라 해상도.
  final VideoQuality quality;

  /// 초당 프레임 수.
  final int frameRate;

  static const int _port = 8888; // 연결 정보를 주고받는 포트
  static const Map<String, dynamic> _rtcConfig = {"iceServers": []};

  /// 상태가 바뀌면 화면을 다시 그리도록 알린다.
  final void Function() onUpdate;

  /// 에러를 화면에 보여준다.
  final void Function(String message) onError;

  /// 내 카메라 화면.
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();

  /// 상대 카메라 화면.
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  /// WebRTC 연결 본체.
  RTCPeerConnection? peerConnection;

  /// 내 카메라 영상.
  MediaStream? localStream;

  /// 송신자가 여는 서버.
  HttpServer? server;

  /// 연결 정보를 주고받는 통로.
  WebSocket? socket;

  /// 송신자가 보여줄 내 IP.
  String localIp = "";

  /// 실제로 연결됐는지.
  bool isConnected = false;

  /// 지금 전면 카메라를 쓰는지.
  bool isFrontCamera = true;

  /// 영상을 좌우반전해 보여줄지(수동 토글). 송신 측 버튼으로 정하고 상대에게 신호로 전달한다.
  bool mirror = false;

  /// 수신한 상대 음성을 출력할지. false면 받은 오디오를 무음 처리한다.
  bool isRemoteAudioEnabled;

  /// 분석에 쓰는 상대 영상 트랙(onTrack에서 받음).
  MediaStreamTrack? remoteVideoTrack;

  bool get hasLocalVideo => localRenderer.srcObject != null;
  bool get hasRemoteVideo => remoteRenderer.srcObject != null;

  // 영상을 그릴 화면(렌더러)을 준비한다. 위젯을 그리기 전에 한 번 호출한다.
  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    onUpdate();
  }

  // 송신자로 시작: 카메라를 켜고, 내 IP를 구한 뒤, 서버를 연다.
  Future<bool> startAsSender() async {
    try {
      await close(); // 이전에 열려 있던 연결/서버가 있으면 먼저 정리한다
      await _openCamera();
      localIp = await _getLocalIp();
      onUpdate();
      await _startServer();
      return true;
    } catch (error) {
      onError("시작 실패: $error");
      await close();
      return false;
    }
  }

  // 수신자로 시작: 카메라를 켜고, 송신자 서버(IP)에 접속한다.
  Future<bool> startAsReceiver(String ip) async {
    try {
      await close(); // 이전에 열려 있던 연결/서버가 있으면 먼저 정리한다
      await _openCamera();
      socket = await WebSocket.connect("ws://$ip:$_port");
      socket?.listen(_handleMessage);
      return true;
    } catch (error) {
      onError("연결 실패 ($ip:$_port): $error");
      await close();
      return false;
    }
  }

  // 카메라를 켜고 WebRTC 연결을 만든다. 내 영상을 연결에 싣고, 상대 영상이 도착하면 화면에 표시한다.
  Future<void> _openCamera() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      "video": {
        "facingMode": "user",
        "width": quality.width,
        "height": quality.height,
        "frameRate": frameRate,
      },
      "audio": true,
    });
    localRenderer.srcObject = localStream;
    peerConnection = await createPeerConnection(_rtcConfig);
    for (final MediaStreamTrack track in localStream!.getTracks()) {
      await peerConnection?.addTrack(track, localStream!);
    }
    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first; // 상대 영상이 도착하면 화면에 연결
      }
      if (event.track.kind == "video") {
        remoteVideoTrack = event.track; // 분석용 트랙은 onTrack에서 직접 받는다(원격 스트림은 getVideoTracks가 비어 있을 수 있음)
      } else if (event.track.kind == "audio") {
        event.track.enabled = isRemoteAudioEnabled; // 수신 음성 출력 설정을 새 오디오 트랙에 적용
      }
      onUpdate();
    };
    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      isConnected = state == RTCPeerConnectionState.RTCPeerConnectionStateConnected; // 연결 상태가 바뀔 때마다 갱신
      onUpdate();
    };
    onUpdate();
  }

  // 송신자가 포트를 열고 수신자의 접속을 기다린다. 접속이 오면 offer를 보낸다.
  Future<void> _startServer() async {
    server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    server?.listen((HttpRequest request) async {
      socket = await WebSocketTransformer.upgrade(request);
      socket!.listen(_handleMessage);
      await _sendOffer();
      _sendMirror();
    });
  }

  // 연결 요청(offer)을 만들어 상대에게 보낸다.
  Future<void> _sendOffer() async {
    final RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    await _sendLocalDescription();
  }

  // 상대 메시지를 처리한다. 카메라 방향 신호면 기록하고, SDP면 연결 정보로 등록한다(offer면 answer로 응답).
  Future<void> _handleMessage(dynamic raw) async {
    final Map<String, dynamic> message = jsonDecode(raw as String) as Map<String, dynamic>;
    final String? type = message["type"] as String?;
    if (type == "mirror") {
      mirror = (message["on"] as bool?) ?? mirror;
      onUpdate();
      return;
    }
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(message["sdp"] as String, type),
    );
    if (type == "offer") {
      await _sendAnswer();
      _sendMirror();
    }
  }

  // 받은 offer에 대한 응답(answer)을 만들어 보낸다.
  Future<void> _sendAnswer() async {
    final RTCSessionDescription answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);
    await _sendLocalDescription();
  }

  // 내 연결 정보(SDP)를 상대에게 보낸다. 네트워크 주소가 다 담길 때까지 잠깐 기다린 뒤 전송한다.
  Future<void> _sendLocalDescription() async {
    await _waitForNetworkInfo();
    final RTCSessionDescription localDescription = (await peerConnection!.getLocalDescription())!;
    _sendMessage({"type": localDescription.type, "sdp": localDescription.sdp});
  }

  // 내 네트워크 주소가 연결 정보에 담길 시간을 잠깐 준다. 같은 Wi-Fi면 금방 끝난다.
  Future<void> _waitForNetworkInfo() async {
    await Future.delayed(const Duration(seconds: 1));
  }

  // 전면/후면 카메라를 전환한다.
  Future<void> switchCamera() async {
    final List<MediaStreamTrack> videoTracks = localStream?.getVideoTracks() ?? [];
    if (videoTracks.isEmpty) return;
    await Helper.switchCamera(videoTracks.first);
    isFrontCamera = !isFrontCamera;
    onUpdate();
  }

  // 수신한 상대 음성의 출력을 켜고 끈다.
  void setRemoteAudioEnabled(bool enabled) {
    isRemoteAudioEnabled = enabled;
    for (final MediaStreamTrack track in remoteRenderer.srcObject?.getAudioTracks() ?? []) {
      track.enabled = enabled;
    }
    onUpdate();
  }

  // 통로(WebSocket)로 메시지를 JSON 형태로 보낸다.
  void _sendMessage(Map<String, dynamic> message) {
    socket?.add(jsonEncode(message));
  }

  // 수동 미러 상태를 상대에게 알린다. 받은 쪽은 표시 영상을 같은 방향으로 뒤집는다.
  void _sendMirror() {
    _sendMessage({"type": "mirror", "on": mirror});
  }

  // 미러를 켜고 끄고 상대에게 알린다.
  void setMirror(bool on) {
    mirror = on;
    _sendMirror();
    onUpdate();
  }

  // 같은 Wi-Fi에서 접속할 수 있는 내 IP(예: 192.168.x.x)를 찾는다.
  Future<String> _getLocalIp() async {
    final List<NetworkInterface> interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    String localIp = "0.0.0.0";
    for (final NetworkInterface interface in interfaces) {
      for (final InternetAddress address in interface.addresses) {
        if (address.isLoopback) continue;
        if (address.address.startsWith("192.168.") ||
            address.address.startsWith("10.") ||
            address.address.startsWith("172.")) {
          return address.address;
        }
        localIp = address.address;
      }
    }
    return localIp;
  }

  // 연결과 카메라를 모두 정리하고 끊는다.
  Future<void> close() async {
    await socket?.close();
    socket = null;
    await server?.close(force: true); // 포트(8888)를 즉시 반납하도록 강제로 닫는다
    server = null;
    await peerConnection?.close();
    peerConnection = null;
    await localStream?.dispose();
    localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    remoteVideoTrack = null;
    isConnected = false;
    mirror = false;
    onUpdate();
  }

  // 화면이 사라질 때 렌더러까지 완전히 정리한다.
  Future<void> dispose() async {
    await close();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
