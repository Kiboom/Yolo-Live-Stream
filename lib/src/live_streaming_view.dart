import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:ultralytics_yolo/ultralytics_yolo.dart";
import "package:yolo_live_stream/src/detection_overlay.dart";
import "package:yolo_live_stream/src/live_streaming_connector.dart";
import "package:yolo_live_stream/src/role.dart";
import "package:yolo_live_stream/src/yolo_analyzer.dart";

/// 영상 세션(WebRTC 연결 + 렌더러 + YOLO 분석기)을 소유하는 핸들.
///
/// 위젯 바깥에서 세션을 들고 있으므로, 같은 controller를 여러 [LiveStreamingView]에 넘기면
/// 화면이 바뀌어도(예: 작은 카드 → 전체화면) 같은 연결을 끊김 없이 이어서 그릴 수 있다.
/// controller를 넘기지 않으면 [LiveStreamingView]가 내부에 자기 세션을 만들어 쓴다(단독 사용).
///
/// [ChangeNotifier]라서 연결/탐지 상태가 바뀌면 리스너에게 통지한다.
class LiveStreamingController extends ChangeNotifier {
  LiveStreamingController({
    this.role = Role.receiver,
    this.quality = VideoQuality.hd720,
    this.frameRate = 30,
    this.enableSpeaker = true,
    this.enableDetection = true,
    this.model = YoloModel.medium,
    this.customModelPath,
    this.detectionInterval = const Duration(milliseconds: 400),
    this.onDetected,
    this.onLocalIpReady,
    this.onError,
  });

  /// 이 세션의 역할(송신/수신). 세션 단위로 고정된다.
  final Role role;

  /// 카메라 해상도.
  final VideoQuality quality;

  /// 초당 프레임 수.
  final int frameRate;

  /// 수신한 상대 음성을 출력할지.
  final bool enableSpeaker;

  /// 수신 영상에 YOLO 객체 탐지를 켤지. 끄면 분석기를 만들지 않고 영상만 보여준다.
  final bool enableDetection;

  /// 모델 크기.
  final YoloModel model;

  /// 커스텀 모델 경로(지정하면 [model] 대신 사용).
  final String? customModelPath;

  /// 분석 주기.
  final Duration detectionInterval;

  /// 매 프레임 YOLO 분석 결과로 호출된다(탐지를 켰을 때만).
  final void Function(List<YOLOResult> detections)? onDetected;

  /// 송신자로 시작해 자기 IP가 정해지면 호출된다.
  final void Function(String localIp)? onLocalIpReady;

  /// 시작 실패·모델 로드 실패 등 오류 메시지를 받는다.
  final void Function(String message)? onError;

  late final LiveStreamingConnector connection = LiveStreamingConnector(
    onUpdate: _notify,
    onError: (String message) => onError?.call(message),
    quality: quality,
    frameRate: frameRate,
    isRemoteAudioEnabled: enableSpeaker,
  );

  YoloAnalyzer? _analyzer;

  bool _ready = false;
  bool _isStarted = false;
  bool _disposed = false;

  /// 탐지를 켰고 분석기가 준비됐는지.
  bool get hasDetection => _analyzer != null;

  /// 최신 탐지 결과(탐지를 껐으면 빈 리스트).
  List<YOLOResult> get detections => _analyzer?.detections ?? const <YOLOResult>[];

  /// 분석 상태/오류 문자열(디버그 표시용).
  String get analyzerStatus => _analyzer?.debugStatus ?? "";

  /// 송신자 자신의 IP. 연결 전이면 빈 문자열.
  String get localIp => connection.localIp;

  /// 상대와 실제로 연결됐는지.
  bool get isConnected => connection.isConnected;

  /// 연결을 시작한 상태인지.
  bool get isStarted => _isStarted;

  /// 수신 음성을 출력하는 상태인지.
  bool get isSpeakerEnabled => connection.isRemoteAudioEnabled;

  /// 렌더러와 분석기를 준비한다. 시작 메서드가 자동으로 호출하므로 보통은 직접 부를 필요가 없다.
  Future<void> prepare() async {
    if (_ready || _disposed) return;
    await connection.initRenderers();
    if (enableDetection) {
      _analyzer = YoloAnalyzer(
        onUpdate: _notify,
        onDetected: (List<YOLOResult> detections) => onDetected?.call(detections),
        getRemoteTrack: () => connection.remoteVideoTrack,
        model: model,
        customModelPath: customModelPath,
        interval: detectionInterval,
      );
    }
    _ready = true;
  }

  /// 송신자로 시작한다. 성공하면 자기 IP를 [onLocalIpReady]로 알린다.
  Future<void> startAsSender() async {
    await prepare();
    _isStarted = true;
    _notify();
    final bool ok = await connection.startAsSender();
    if (!ok) {
      _isStarted = false;
      _notify();
      return;
    }
    onLocalIpReady?.call(connection.localIp);
  }

  /// 수신자로 [senderIp]에 접속하고, 받은 영상에 객체 탐지를 돌린다.
  Future<void> startAsReceiver(String senderIp) async {
    await prepare();
    _isStarted = true;
    _notify();
    final bool ok = await connection.startAsReceiver(senderIp.trim());
    if (!ok) {
      _isStarted = false;
      _notify();
      return;
    }
    if (_analyzer != null) {
      try {
        await _analyzer!.start();
      } catch (error) {
        onError?.call("YOLO 모델 로드 실패: $error");
      }
    }
  }

  /// 역할에 맞는 시작을 호출한다. 수신자는 [senderIp]가 필요하다.
  Future<void> start([String senderIp = ""]) async {
    if (role == Role.sender) {
      await startAsSender();
    } else {
      await startAsReceiver(senderIp);
    }
  }

  /// 연결을 종료한다(세션 자체는 살아 있어 다시 시작할 수 있다).
  Future<void> stop() async {
    _analyzer?.stop();
    await connection.close();
    _isStarted = false;
    _notify();
  }

  /// 전/후면 카메라를 전환한다(송신자).
  Future<void> switchCamera() => connection.switchCamera();

  /// 수신한 상대 음성의 출력을 켜고 끈다.
  void setSpeakerEnabled(bool enabled) => connection.setRemoteAudioEnabled(enabled);

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _analyzer?.dispose();
    connection.dispose();
    super.dispose();
  }
}

/// 주어진 [role]로 영상을 송/수신하고 (켰으면) YOLO 오버레이를 얹는 위젯.
/// 역할 선택 UI는 들어 있지 않다. 바깥에서 [LiveStreamRoleSwitcher] 등으로 role을 정해 넘긴다.
/// role이 런타임에 바뀌면 진행 중이던 연결을 정리하고 새 역할의 대기 상태로 돌아간다.
///
/// 내장 컨트롤 UI 없이 영상+탐지만 쓰려면 [showControlPanel]을 끄고,
/// 시작/종료는 [autoStart](+[senderIp])나 [controller]로 제어한다.
///
/// [controller]를 넘기면 그 세션을 그리기만 한다(연결/렌더러는 controller가 소유).
/// 같은 controller를 여러 화면에 넘기면 끊김 없이 같은 영상을 이어서 보여준다.
/// controller를 넘기지 않으면 위젯이 내부에 세션을 만들어 단독으로 동작한다.
/// controller를 넘긴 경우 세션 설정(quality·enableDetection·customModelPath·콜백 등)은
/// controller 값이 쓰이고, 위젯의 같은 이름 인자는 무시된다.
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

  /// 영상 세션을 소유·공유할 컨트롤러. 없으면 위젯이 내부 세션을 만든다.
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
  // controller를 넘기지 않은 경우 위젯이 직접 만들어 소유하는 세션.
  LiveStreamingController? _internalController;

  LiveStreamingController get _session => widget.controller ?? _internalController!;

  final TextEditingController ipEditingController = TextEditingController(); // 수신자가 입력하는 송신자 IP

  @override
  void initState() {
    super.initState();
    _attachSession();
    _initialize();
  }

  // 외부 controller가 없으면 위젯 설정으로 내부 controller를 만든다(단독 사용 동작 유지).
  void _attachSession() {
    if (widget.controller == null) {
      _internalController = LiveStreamingController(
        role: widget.role,
        quality: widget.quality,
        frameRate: widget.frameRate,
        enableSpeaker: widget.enableSpeaker,
        enableDetection: widget.enableDetection,
        model: widget.model,
        customModelPath: widget.customModelPath,
        detectionInterval: widget.detectionInterval,
        onDetected: widget.onDetected,
        onLocalIpReady: widget.onLocalIpReady,
        onError: _showMessage,
      );
    }
    _session.addListener(_handleUpdate);
  }

  Future<void> _initialize() async {
    await _session.prepare();
    if (!mounted) return;
    setState(() {});
    if (widget.autoStart) {
      await _autoStart();
    }
  }

  @override
  void didUpdateWidget(LiveStreamingView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // controller 교체(내부<->외부 전환 포함).
    if (oldWidget.controller != widget.controller) {
      final LiveStreamingController previous =
          oldWidget.controller ?? _internalController!;
      previous.removeListener(_handleUpdate);
      final LiveStreamingController? oldInternal = _internalController;
      _internalController = null;
      _attachSession();
      oldInternal?.dispose();
      _initialize();
      return;
    }

    // 내부 세션만 쓰는 경우, role이 바뀌면 새 역할로 세션을 다시 만든다(역할 전환 지원).
    if (widget.controller == null && oldWidget.role != widget.role) {
      final LiveStreamingController old = _internalController!;
      old.removeListener(_handleUpdate);
      _internalController = null;
      _attachSession();
      old.dispose();
      _initialize();
      return;
    }

    if (oldWidget.enableSpeaker != widget.enableSpeaker) {
      _session.setSpeakerEnabled(widget.enableSpeaker);
    }

    // autoStart 수신자는 송신자 IP가 바뀌면 새 IP로 다시 연결한다.
    if (widget.autoStart &&
        _session.role == Role.receiver &&
        widget.senderIp != null &&
        oldWidget.senderIp != widget.senderIp) {
      _restartReceiver();
    }
  }

  void _handleUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _autoStart() async {
    if (_session.role == Role.sender) {
      await _session.startAsSender();
    } else if (widget.senderIp != null) {
      await _session.startAsReceiver(widget.senderIp!);
    }
  }

  Future<void> _restartReceiver() async {
    await _session.stop();
    await _session.startAsReceiver(widget.senderIp!);
  }

  // 시작 버튼용. 역할에 맞는 시작을 호출한다.
  Future<void> _start() async {
    await _session.start(ipEditingController.text);
  }

  Future<void> _stop() async {
    await _session.stop();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  @override
  void dispose() {
    _session.removeListener(_handleUpdate);
    _internalController?.dispose();
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
    final LiveStreamingController session = _session;
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
          if (session.role == Role.sender && session.connection.hasLocalVideo) ...[
            Positioned(
              right: 16,
              bottom: 16,
              child: _buildSwitchCameraButton(),
            ),
          ],
          // 분석 상태/오류를 눈으로 확인하기 위한 디버그 표시.
          if (session.role == Role.receiver &&
              session.isStarted &&
              session.hasDetection) ...[
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
        _session.analyzerStatus,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  // 큰 화면. 수신자는 받은 영상(켰으면 탐지 박스 포함)을, 송신자는 내 카메라를 보여준다.
  Widget _buildMainVideo() {
    final LiveStreamingController session = _session;
    final LiveStreamingConnector connection = session.connection;
    if (session.role == Role.receiver) {
      if (!connection.hasRemoteVideo) {
        return Container(
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          color: const Color(0xFF0E0E12),
          child: _buildWaitingPlaceholder(),
        );
      }
      if (session.hasDetection) {
        return DetectionOverlay(
          renderer: connection.remoteRenderer,
          detections: session.detections,
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
          _session.isStarted ? "상대 영상 대기 중..." : "역할을 고르고 시작을 누르세요",
          style: const TextStyle(color: Colors.white38, fontSize: 15),
        ),
      ],
    );
  }

  // 우상단 작은 화면. 큰 화면과 반대쪽 영상을 보여준다.
  Widget _buildPipVideo() {
    final LiveStreamingController session = _session;
    final LiveStreamingConnector connection = session.connection;
    final bool showMyCamera = session.role == Role.receiver;
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
      onTap: _session.switchCamera,
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
    final bool connected = _session.isConnected;
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
              color: connected ? const Color(0xFF30D158) : Colors.white38,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            connected ? "연결됨" : "대기 중",
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
    final LiveStreamingController session = _session;
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
          if (!session.isStarted && session.role == Role.receiver) ...[
            _buildIpField(),
            const SizedBox(height: 16),
          ],
          // 송신자는 시작 후 자기 IP를 보여준다.
          if (session.isStarted && session.role == Role.sender) ...[
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
              "내 IP: ${_session.localIp}",
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
    final LiveStreamingController session = _session;
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: session.isStarted
          ? FilledButton(
              onPressed: _stop,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE5484D)),
              child: const Text(
                "연결 종료",
                style: TextStyle(fontSize: 16),
              ),
            )
          : FilledButton(
              onPressed: _start,
              child: Text(
                session.role == Role.sender ? "송신 시작" : "수신 시작",
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ),
    );
  }
}
