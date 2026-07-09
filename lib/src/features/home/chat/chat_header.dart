part of 'package:bim/src/features/home/home_page.dart';

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.title,
    required this.avatarUrl,
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
    if (isGroup) {
      return Container(
        height: BimDimensions.chatHeader,
        decoration: const BoxDecoration(
          color: _surfaceColor,
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: _HeaderIconButton(
                tooltip: '返回',
                icon: Icons.chevron_left,
                iconSize: 31,
                onPressed: onBack,
              ),
            ),
            Positioned.fill(
              left: 72,
              right: 54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title.isEmpty ? '群聊' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (groupPresenceLoading) ...[
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.4,
                              color: _secondaryTextColor,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            statusText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _secondaryTextColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HeaderIconButton(
                    tooltip: '群设置',
                    icon: Icons.more_horiz,
                    onPressed: onDetail,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: BimDimensions.chatHeader,
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
      child: Row(
        children: [
          _HeaderIconButton(
            tooltip: '返回',
            icon: Icons.chevron_left,
            iconSize: 31,
            onPressed: onBack,
          ),
          const SizedBox(width: 3),
          _Avatar(
            label: title,
            imageUrl: avatarUrl,
            size: 36,
            color: isGroup ? const Color(0xff34c759) : _primaryColor,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? '聊天' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 7,
                      height: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: online || isGroup
                              ? _chatOnlineColor
                              : const Color(0xffb8bec8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      statusText,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            tooltip: '语音通话',
            icon: Icons.call_outlined,
            onPressed: onVoiceCall,
          ),
          const SizedBox(width: 5),
          _HeaderIconButton(
            tooltip: '视频通话',
            icon: Icons.videocam_outlined,
            onPressed: onVideoCall,
          ),
          const SizedBox(width: 5),
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
    this.iconSize = 26,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 20,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: onPressed == null ? _mutedColor : _textColor,
          size: iconSize,
        ),
      ),
    );
  }
}
