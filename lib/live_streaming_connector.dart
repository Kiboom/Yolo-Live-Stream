import "dart:async";
import "dart:convert";
import "dart:io";

import "package:flutter_webrtc/flutter_webrtc.dart";

class LiveStreamingConnector {
  LiveStreamingConnector({required this.onUpdate, required this.onError});

  static const int _port = 8888;
  static const Map<String, dynamic> _rtcConfig = {
    "iceServers": [
      {"urls": "stun:stun.l.google.com:19302"},
    ],
  };

  final void Function() onUpdate;
  final void Function(String message) onError;
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  HttpServer? server;
  WebSocket? socket;
  String localIp = "";
  bool isConnected = false;

  bool get hasLocalVideo => localRenderer.srcObject != null;
  bool get hasRemoteVideo => remoteRenderer.srcObject != null;

  Future<void> initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    onUpdate();
  }

  Future<bool> startAsSender() async {
    try {
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

  Future<bool> startAsReceiver(String ip) async {
    try {
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

  Future<void> _openCamera() async {
    localStream = await navigator.mediaDevices.getUserMedia({"video": true, "audio": false});
    localRenderer.srcObject = localStream;
    peerConnection = await createPeerConnection(_rtcConfig);
    for (final MediaStreamTrack track in localStream!.getTracks()) {
      await peerConnection?.addTrack(track, localStream!);
    }
    peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams.first;
        onUpdate();
      }
    };
    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      isConnected = state == .RTCPeerConnectionStateConnected;
      onUpdate();
    };
    onUpdate();
  }

  Future<void> _startServer() async {
    server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
    server?.listen((HttpRequest request) async {
      socket = await WebSocketTransformer.upgrade(request);
      socket!.listen(_handleMessage);
      await _sendOffer();
    });
  }

  Future<void> _sendOffer() async {
    if (peerConnection == null) return;
    final RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection?.setLocalDescription(offer);
    await _waitForNetworkInfo();
    final RTCSessionDescription localDescription = (await peerConnection?.getLocalDescription())!;
    _sendMessage({"type": localDescription.type, "sdp": localDescription.sdp});
  }

  Future<void> _handleMessage(dynamic raw) async {
    final Map<String, dynamic> message = jsonDecode(raw as String) as Map<String, dynamic>;
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(message["sdp"] as String, message["type"] as String),
    );
    if (message["type"] == "offer") {
      await _sendAnswer();
    }
  }

  Future<void> _sendAnswer() async {
    final RTCSessionDescription answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);
    await _waitForNetworkInfo();
    final RTCSessionDescription? localDescription = await peerConnection!.getLocalDescription();
    _sendMessage({"type": localDescription?.type, "sdp": localDescription?.sdp});
  }

  Future<void> _waitForNetworkInfo() async {
    if (peerConnection!.iceGatheringState == .RTCIceGatheringStateComplete) {
      return;
    }
    final Completer<void> completer = Completer<void>();
    peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      if (state == .RTCIceGatheringStateComplete && !completer.isCompleted) {
        completer.complete();
      }
    };
    await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  void _sendMessage(Map<String, dynamic> message) {
    socket?.add(jsonEncode(message));
  }

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

  Future<void> close() async {
    await socket?.close();
    socket = null;
    await server?.close();
    server = null;
    await peerConnection?.close();
    peerConnection = null;
    await localStream?.dispose();
    localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    isConnected = false;
    onUpdate();
  }

  Future<void> dispose() async {
    await close();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
