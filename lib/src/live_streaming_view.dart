import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";
import "package:yolo_live_stream/src/detection_overlay.dart";
import "package:yolo_live_stream/src/live_streaming_connector.dart";
import "package:yolo_live_stream/src/role.dart";
import "package:yolo_live_stream/src/yolo_analyzer.dart";

/// [LiveStreamingView]를 코드에서 직접 제어하는 핸들.
/// 위젯에 넘기면 시작/종료/카메라 전환을 명령형으로 호출하고 연결 상태를 읽을 수 있다.
/// [ChangeNotifier]라서 연결 상태가 바뀌면 리스너에게 통지한다.
class LiveStreamingController extends ChangeNotifier {
  _LiveStreamingViewState? _view;
  void Function()? _pendingStart; // 위젯에 연결되기 전 호출된 시작 요청

  /// 위젯에 연결돼 제어할 수 있는 상태인지.
  bool get isAttached => _view != null;

  /// 송신자로 연결을 시작한다. 위젯에 연결되기 전 호출하면 연결 직후 실행한다.
  Future<void> startAsSender() async {
    final _LiveStreamingViewState? view = _view;
    if (view == null) {
      _pendingStart = startAsSender;
      return;
    }
    await view.startAsSender();
  }

  /// 수신자로 [senderIp]에 접속해 연결을 시작한다. 위젯에 연결되기 전 호출하면 연결 직후 실행한다.
  Future<void> startAsReceiver(String senderIp) async {
    final _LiveStreamingViewState? view = _view;
    if (view == null) {
      _pendingStart = () => startAsReceiver(senderIp);
      return;
    }
    await view.startAsReceiver(senderIp);
  }

  /// 연결을 종료한다.
  Future<void> stop() async {
    await _view?.stop();
  }

  /// 전/후면 카메라를 전환한다(송신자).
  Future<void> switchCamera() async {
    await _view?.connection.switchCamera();
  }

  /// 수신한 상대 음성의 출력을 켜고 끈다.
  void setSpeakerEnabled(bool enabled) {
    _view?.connection.setRemoteAudioEnabled(enabled);
  }

  /// 송신자 자신의 IP. 연결 전이면 빈 문자열.
  String get localIp => _view?.connection.localIp ?? "";

  /// 상대와 실제로 연결됐는지.
  bool get isConnected => _view?.connection.isConnected ?? false;

  /// 연결을 시작한 상태인지.
  bool get isStarted => _view?.isStarted ?? false;

  /// 수신 음성을 출력하는 상태인지.
  bool get isSpeakerEnabled => _view?.connection.isRemoteAudioEnabled ?? true;

  void _flushPendingStart() {
    final void Function()? pending = _pendingStart;
    _pendingStart = null;
    pending?.call();
  }

  void _notify() => notifyListeners();
}

/// 주어진 [role]로 영상을 송/수신하고 (켰으면) YOLO 오버레이를 얹는 위젯.
/// 역할 선택 UI는 들어 있지 않다. 바깥에서 [LiveStreamRoleSwitcher] 등으로 role을 정해 넘긴다.
/// role이 런타임에 바뀌면 진행 중이던 연결을 정리하고 새 역할의 대기 상태로 돌아간다.
///
/// 내장 컨트롤 UI 없이 영상+탐지만 쓰려면 [showControlPanel]을 끄고,
/// 시작/종료는 [autoStart](+[senderIp])나 [controller]로 제어한다.
class LiveStreamingView extends StatefulWidget {
  const LiveStreamingView({
    super.key,
    required this.role,
    this.controller,
    this.quality = VideoQuality.hd720,
    this.frameRate = 30,
    this.enableSpeaker = true,
    this.enableDetection = true,
    this.model = YoloModel.medium,
    this.customModelPath,
    this.detectionInterval = const Duration(milliseconds: 400),
    this.showControlPanel = true,
    this.autoStart = false,
    this.senderIp,
    this.onDetected,
    this.onLocalIpReady,
  });

  final Role role;

  /// 코드에서 시작/종료/카메라 전환을 직접 제어할 컨트롤러.
  final LiveStreamingController? controller;

  /// 카메라 해상도.
  final VideoQuality quality;

  /// 초당 프레임 수.
  final int frameRate;

  /// 수신한 상대 음성을 출력할지. false면 받은 음성을 재생하지 않는다.
  final bool enableSpeaker;

  /// 수신 영상에 YOLO 객체 탐지를 켤지. 끄면 영상만 보여준다.
  final bool enableDetection;

  /// 모델 크기.
  final YoloModel model;

  /// 커스텀 모델 경로. 지정하면 model 대신 이 경로의 모델을 쓴다.
  ///
  /// 경로 형태
  ///  - 에셋 (ex. "assets/...")
  ///  - URL (ex. "https://...")
  ///
  /// 모델 형식
  ///  - Android .tflite
  ///  - iOS .mlpackage.zip
  ///
  /// 주의사항: 반드시 detect(task=detect) 계열 모델이어야 함
  final String? customModelPath;

  /// 분석 주기.
  final Duration detectionInterval;

  /// 내장 컨트롤 UI(IP 입력·시작/종료 버튼·상태 배지·PiP·카메라 전환 버튼)를 보일지.
  /// false면 영상과 탐지 오버레이만 남는다. 이땐 [autoStart]나 [controller]로 시작/종료한다.
  final bool showControlPanel;

  /// 위젯이 화면에 올라오면 자동으로 연결을 시작할지. 수신자는 [senderIp]가 있어야 한다.
  final bool autoStart;

  /// [autoStart] 수신자가 접속할 송신자 IP.
  final String? senderIp;

  /// 매 프레임 YOLO 분석 결과로 호출된다(탐지를 켰을 때만).
  final void Function(List<YOLOResult> detections)? onDetected;

  /// 송신자로 시작해 자기 IP가 정해지면 호출된다.
  final void Function(String localIp)? onLocalIpReady;

  @override
  State<LiveStreamingView> createState() => _LiveStreamingViewState();
}

class _LiveStreamingViewState extends State<LiveStreamingView> {
  late final LiveStreamingConnector connection; // 실제 영상 연결을 담당
  YoloAnalyzer? analyzer; // 수신 영상에 YOLO 객체 탐지를 돌린다(켰을 때만)
  final TextEditingController ipEditingController = TextEditingController(); // 수신자가 입력하는 송신자 IP

  bool isStarted = false; // 시작했는지

  @override
  void initState() {
    super.initState();
    widget.controller?._view = this;
    connection = LiveStreamingConnector(
      onUpdate: _handleUpdate,
      onError: _showMessage,
      quality: widget.quality,
      frameRate: widget.frameRate,
      isRemoteAudioEnabled: widget.enableSpeaker,
    );
    if (widget.enableDetection) {
      analyzer = YoloAnalyzer(
        onUpdate: _handleUpdate,
        onDetected: (detections) => widget.onDetected?.call(detections),
        getRemoteTrack: () => connection.remoteVideoTrack,
        model: widget.model,
        customModelPath: widget.customModelPath,
        interval: widget.detectionInterval,
      );
    }
    _initialize();
  }

  Future<void> _initialize() async {
    await connection.initRenderers();
    if (!mounted) return;
    widget.controller?._flushPendingStart();
    if (widget.autoStart) {
      await _autoStart();
    }
  }

  @override
  void didUpdateWidget(LiveStreamingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._view = null;
      widget.controller?._view = this;
    }
    if (oldWidget.enableSpeaker != widget.enableSpeaker) {
      connection.setRemoteAudioEnabled(widget.enableSpeaker);
    }
    // 역할이 바뀌면 진행 중이던 연결을 정리하고, autoStart면 새 역할로 다시 시작한다.
    if (oldWidget.role != widget.role) {
      if (isStarted) {
        stop();
      }
      if (widget.autoStart) {
        _autoStart();
      }
      return;
    }
    // autoStart 수신자는 송신자 IP가 바뀌면 새 IP로 다시 연결한다.
    if (widget.autoStart &&
        widget.role == Role.receiver &&
        widget.senderIp != null &&
        oldWidget.senderIp != widget.senderIp) {
      _restartReceiver();
    }
  }

  void _handleUpdate() {
    if (!mounted) return;
    widget.controller?._notify();
    setState(() {});
  }

  Future<void> _autoStart() async {
    if (widget.role == Role.sender) {
      await startAsSender();
    } else if (widget.senderIp != null) {
      await startAsReceiver(widget.senderIp!);
    }
  }

  Future<void> _restartReceiver() async {
    if (isStarted) {
      await stop();
    }
    await startAsReceiver(widget.senderIp!);
  }

  // 시작 버튼용. 역할에 맞는 시작을 호출한다.
  Future<void> start() async {
    if (widget.role == Role.sender) {
      await startAsSender();
    } else {
      await startAsReceiver(ipEditingController.text);
    }
  }

  // 송신자로 시작한다. 성공하면 자기 IP를 onLocalIpReady로 알린다.
  Future<void> startAsSender() async {
    setState(() {
      isStarted = true;
    });
    final bool ok = await connection.startAsSender();
    if (!ok) {
      setState(() {
        isStarted = false;
      });
      return;
    }
    widget.onLocalIpReady?.call(connection.localIp);
  }

  // 수신자로 송신자 IP에 접속하고, 받은 영상에 객체 탐지를 돌린다.
  Future<void> startAsReceiver(String senderIp) async {
    setState(() {
      isStarted = true;
    });
    final bool ok = await connection.startAsReceiver(senderIp.trim());
    if (!ok) {
      setState(() {
        isStarted = false;
      });
      return;
    }
    if (analyzer != null) {
      try {
        await analyzer!.start();
      } catch (error) {
        _showMessage("YOLO 모델 로드 실패: $error");
      }
    }
  }

  Future<void> stop() async {
    analyzer?.stop();
    await connection.close();
    if (!mounted) return;
    setState(() {
      isStarted = false;
    });
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    widget.controller?._view = null;
    analyzer?.dispose();
    connection.dispose();
    ipEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showControlPanel) {
      return _buildVideoArea();
    }
    return Column(
      children: [
        Expanded(
          child: _buildVideoArea(),
        ),
        _buildControlPanel(),
      ],
    );
  }

  Widget _buildVideoArea() {
    return Stack(
      children: [
        _buildMainVideo(),
        // 컨트롤을 끄면 영상+탐지 오버레이만 남기고 보조 UI는 모두 감춘다.
        if (widget.showControlPanel) ...[
          Positioned(
            top: 16,
            left: 16,
            child: _buildStatusBadge(),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: _buildPipVideo(),
          ),
          // 송신자는 자기 카메라가 큰 화면이므로, 그 위에 전/후면 전환 버튼을 둔다.
          if (widget.role == Role.sender && connection.hasLocalVideo) ...[
            Positioned(
              right: 16,
              bottom: 16,
              child: _buildSwitchCameraButton(),
            ),
          ],
          // 분석 상태/오류를 눈으로 확인하기 위한 디버그 표시.
          if (widget.role == Role.receiver && isStarted && analyzer != null) ...[
            Positioned(
              left: 16,
              bottom: 16,
              child: _buildAnalysisStatus(),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildAnalysisStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        analyzer!.debugStatus,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  // 큰 화면. 수신자는 받은 영상(켰으면 탐지 박스 포함)을, 송신자는 내 카메라를 보여준다.
  Widget _buildMainVideo() {
    if (widget.role == Role.receiver) {
      if (!connection.hasRemoteVideo) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          color: const Color(0xFF0E0E12),
          child: _buildWaitingPlaceholder(),
        );
      }
      if (analyzer != null) {
        return DetectionOverlay(
          renderer: connection.remoteRenderer,
          detections: analyzer!.detections,
        );
      }
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF0E0E12),
        child: RTCVideoView(
          connection.remoteRenderer,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      color: const Color(0xFF0E0E12),
      child: connection.hasLocalVideo
          ? RTCVideoView(
              connection.localRenderer,
              mirror: connection.isFrontCamera,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : _buildWaitingPlaceholder(),
    );
  }

  Widget _buildWaitingPlaceholder() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.videocam_off_rounded,
          size: 64,
          color: Colors.white24,
        ),
        const SizedBox(height: 16),
        Text(
          isStarted ? "상대 영상 대기 중..." : "역할을 고르고 시작을 누르세요",
          style: const TextStyle(color: Colors.white38, fontSize: 15),
        ),
      ],
    );
  }

  // 우상단 작은 화면. 큰 화면과 반대쪽 영상을 보여준다.
  Widget _buildPipVideo() {
    final bool showMyCamera = widget.role == Role.receiver;
    final RTCVideoRenderer renderer = showMyCamera ? connection.localRenderer : connection.remoteRenderer;
    final bool hasVideo = showMyCamera ? connection.hasLocalVideo : connection.hasRemoteVideo;
    if (!hasVideo) return const SizedBox.shrink();
    return Container(
      width: 110,
      height: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: RTCVideoView(
        renderer,
        mirror: showMyCamera && connection.isFrontCamera,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }

  // 전/후면 카메라 전환 버튼.
  Widget _buildSwitchCameraButton() {
    return GestureDetector(
      onTap: connection.switchCamera,
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.cameraswitch_rounded,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connection.isConnected ? const Color(0xFF30D158) : Colors.white38,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            connection.isConnected ? "연결됨" : "대기 중",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 28),
      decoration: const BoxDecoration(
        color: Color(0xFF17171E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 수신자는 시작 전에 송신자 IP를 입력한다.
          if (!isStarted && widget.role == Role.receiver) ...[
            _buildIpField(),
            const SizedBox(height: 16),
          ],
          // 송신자는 시작 후 자기 IP를 보여준다.
          if (isStarted && widget.role == Role.sender) ...[
            _buildIpBanner(),
            const SizedBox(height: 16),
          ],
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildIpField() {
    return TextField(
      controller: ipEditingController,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: "송신자 IP 입력 (예: 192.168.0.12)",
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: const Icon(
          Icons.lan_rounded,
          color: Colors.white38,
        ),
        filled: true,
        fillColor: const Color(0xFF26262F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildIpBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF26262F),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_rounded,
            size: 18,
            color: Colors.white70,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "내 IP: ${connection.localIp}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            "수신자에게 알려주세요",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: isStarted
          ? FilledButton(
              onPressed: stop,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
              child: const Text(
                "연결 종료",
                style: TextStyle(fontSize: 16),
              ),
            )
          : FilledButton(
              onPressed: start,
              child: Text(
                widget.role == Role.sender ? "송신 시작" : "수신 시작",
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ),
    );
  }
}
