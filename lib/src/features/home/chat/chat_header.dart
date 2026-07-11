part of 'package:bim/src/features/home/home_page.dart';

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.avatarUrl,
    this.avatarMembers = const [],
    required this.isGroup,
    required this.statusText,
    required this.online,
    required this.groupPresenceLoading,
    required this.onBack,
    required this.onDetail,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  final String title;
  final String avatarUrl;
  final List<Map<String, Object?>> avatarMembers;
  final bool isGroup;
  final String statusText;
  final bool online;
  final bool groupPresenceLoading;
  final VoidCallback onBack;
  final VoidCallback? onDetail;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: BimDimensions.chatHeader,
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border(bottom: BorderSide(color: BimColors.borderLight)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x1),
      child: Row(
        children: [
          _HeaderIconButton(
            tooltip: '返回',
            icon: Icons.chevron_left,
            iconSize: 31,
            onPressed: onBack,
          ),
          if (!isGroup) ...[
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 34,
              color: BimColors.primary,
            ),
            const SizedBox(width: BimSpacing.x2),
          ] else ...[
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              compositeMembers: avatarMembers,
              size: 34,
              color: BimColors.success,
              icon: avatarMembers.isEmpty ? Icons.groups : null,
            ),
            const SizedBox(width: BimSpacing.x2),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? (isGroup ? '群聊' : '聊天') : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BimColors.textDark,
                    fontSize: BimTypography.title,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: BimSpacing.x1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (groupPresenceLoading) ...[
                      const SizedBox(
                        width: 8,
                        height: 8,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.3,
                          color: BimColors.secondaryText,
                        ),
                      ),
                      const SizedBox(width: BimSpacing.x1),
                    ] else ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: online || isGroup
                              ? BimColors.online
                              : BimColors.mutedText,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: BimSpacing.x1),
                    ],
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: BimColors.secondaryText,
                        fontSize: BimTypography.caption,
                        fontWeight: FontWeight.w500,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isGroup) ...[
            _HeaderIconButton(
              tooltip: '语音通话',
              icon: Icons.call_outlined,
              onPressed: onVoiceCall,
            ),
            _HeaderIconButton(
              tooltip: '视频通话',
              icon: Icons.videocam_outlined,
              onPressed: onVideoCall,
            ),
          ],
          _HeaderIconButton(
            tooltip: isGroup ? '群设置' : '聊天设置',
            icon: Icons.more_horiz,
            onPressed: onDetail,
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconSize = 24,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: BimDimensions.touchTarget,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: onPressed == null ? BimColors.mutedText : BimColors.textDark,
          size: iconSize,
        ),
      ),
    );
  }
}
