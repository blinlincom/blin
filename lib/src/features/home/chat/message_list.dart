part of 'package:bim/src/features/home/home_page.dart';

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.item,
    required this.showSenderName,
    required this.currentUserAvatarUrl,
    required this.highlighted,
    required this.onLongPressStart,
    required this.onTap,
    required this.onQuoteTap,
    required this.redPacketReceiving,
    required this.onRetry,
    super.key,
  });

  final Map<String, Object?> item;
  final bool showSenderName;
  final String currentUserAvatarUrl;
  final bool highlighted;
  final GestureLongPressStartCallback onLongPressStart;
  final VoidCallback? onTap;
  final ValueChanged<Map<String, Object?>> onQuoteTap;
  final bool redPacketReceiving;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (_isSystemNoticeMessage(item)) {
      return _SystemNoticeRow(text: _systemNoticeText(item));
    }
    final isMe = item['is_me'] == true;
    final sender = _messageSenderName(item);
    final avatarUrl = isMe
        ? currentUserAvatarUrl
        : _messageSenderAvatarUrl(item);
    final contentType = _messageContentType(item);
    final payload = _asObjectMap(item['payload']);
    final status = _messageStatus(item);
    final readText = _messageReadStatusText(item);
    final statusInsideContent = _messageRendersAsMedia(contentType, payload);
    final showExternalStatus =
        isMe &&
        !statusInsideContent &&
        (status == 'sending' ||
            status == 'queued' ||
            status == 'sent' ||
            status == 'read' ||
            status == 'failed');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      color: highlighted ? const Color(0x241677ff) : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: isMe
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              _Avatar(label: sender, imageUrl: avatarUrl, size: 36),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isMe && showSenderName && sender.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 3),
                      child: Text(
                        sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _mutedColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showExternalStatus) ...[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 74),
                          child: _MessageSendStatus(
                            status: status,
                            readText: readText,
                            onRetry: onRetry,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      GestureDetector(
                        onTap: onTap,
                        onLongPressStart: onLongPressStart,
                        child: _MessageBubble(
                          item: item,
                          isMe: isMe,
                          status: status,
                          redPacketReceiving: redPacketReceiving,
                          onQuoteTap: onQuoteTap,
                          onRetry: onRetry,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 7),
              _Avatar(
                label: '我',
                imageUrl: avatarUrl,
                size: 36,
                color: _primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SystemNoticeRow extends StatelessWidget {
  const _SystemNoticeRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.74,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xffeceff3),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _secondaryTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
