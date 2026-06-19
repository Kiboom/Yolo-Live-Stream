import "package:flutter/material.dart";
import "package:yolo_live_stream/src/role.dart";

/// 송신자/수신자를 고르는 iOS 스타일 스위처. 인디케이터가 살짝 튕기며(easeOutBack) 이동한다.
/// LiveStreamingView 바깥에서 역할을 제어할 때 갖다 쓴다.
class LiveStreamRoleSwitcher extends StatelessWidget {
  const LiveStreamRoleSwitcher({
    super.key,
    required this.role,
    required this.onChanged,
    this.enabled = true,
  });

  final Role role;
  final ValueChanged<Role> onChanged;
  /// 연결 중엔 false로 잠글 수 있다.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFF26262F),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // 선택된 칸을 표시하는 흰 박스. 역할을 바꾸면 좌우로 살짝 튕기며 이동한다.
          AnimatedAlign(
            alignment: role == Role.sender ? Alignment.centerLeft : Alignment.centerRight,
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
              Expanded(child: _buildTab(Role.sender, "송신자", Icons.videocam_rounded)),
              Expanded(child: _buildTab(Role.receiver, "수신자", Icons.tv_rounded)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTab(Role value, String label, IconData icon) {
    final bool isSelected = role == value;
    final Color color = isSelected ? const Color(0xFF17171E) : Colors.white60;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => onChanged(value) : null,
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
}
