import "package:flutter/material.dart";
import "package:flutter_webrtc/flutter_webrtc.dart";
import "package:live_camera_app/live_streaming_connector.dart";

enum Role { sender, receiver }

class LiveStreamingScreen extends StatefulWidget {
  const LiveStreamingScreen({super.key});

  @override
  State<LiveStreamingScreen> createState() => _LiveStreamingScreenState();
}

class _LiveStreamingScreenState extends State<LiveStreamingScreen> {
  late final LiveStreamingConnector connection;
  final TextEditingController ipEditingController = TextEditingController();

  Role role = Role.sender;
  bool isStarted = false;

  @override
  void initState() {
    super.initState();
    connection = LiveStreamingConnector(
      onUpdate: () {
        setState(() {});
      },
      onError: _showMessage,
    );
    connection.initRenderers();
  }

  Future<void> start() async {
    setState(() {
      this.isStarted = true;
    });

    final bool isStarted = role == .sender
        ? await connection.startAsSender()
        : await connection.startAsReceiver(ipEditingController.text.trim());

    if (!isStarted) {
      setState(() {
        this.isStarted = false;
      });
    }
  }

  Future<void> stop() async {
    await connection.close();
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
    connection.dispose();
    ipEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildVideoArea()),
            _buildControlPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    return Stack(
      children: [
        _buildRemoteVideo(),
        Positioned(
          top: 16,
          left: 16,
          child: _buildStatusBadge(),
        ),
        Positioned(
          top: 16,
          right: 16,
          child: _buildLocalPreview(),
        ),
      ],
    );
  }

  Widget _buildRemoteVideo() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      color: const Color(0xFF0E0E12),
      child: connection.hasRemoteVideo
          ? RTCVideoView(
              connection.remoteRenderer,
              objectFit: .RTCVideoViewObjectFitCover,
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

  Widget _buildLocalPreview() {
    if (!connection.hasLocalVideo) return const SizedBox.shrink();
    return Container(
      width: 110,
      height: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: RTCVideoView(
        connection.localRenderer,
        mirror: true,
        objectFit: .RTCVideoViewObjectFitCover,
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
          _buildRoleSwitcher(),
          const SizedBox(height: 16),
          if (!isStarted && role == .receiver) ...[
            _buildIpField(),
            const SizedBox(height: 16),
          ],
          if (isStarted && role == .sender) ...[
            _buildIpBanner(),
            const SizedBox(height: 16),
          ],
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildRoleSwitcher() {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF26262F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: role == .sender ? Alignment.centerLeft : Alignment.centerRight,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildRoleTab(.sender, "송신자", Icons.videocam_rounded),
              ),
              Expanded(
                child: _buildRoleTab(.receiver, "수신자", Icons.tv_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleTab(Role role, String label, IconData icon) {
    final bool isSelected = this.role == role;
    final Color color = isSelected ? const Color(0xFF17171E) : Colors.white60;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isStarted) return;
        setState(() {
          this.role = role;
        });
      },
      child: Container(
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              child: Text(label),
            ),
          ],
        ),
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
                role == .sender ? "송신 시작" : "수신 시작",
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ),
    );
  }
}
