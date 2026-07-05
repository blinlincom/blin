part of 'package:bim/src/features/home/home_page.dart';

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.item,
    required this.showSenderName,
    required this.currentUserAvatarUrl,
    required this.onLongPress,
    required this.onTap,
    required this.redPacketReceiving,
    required this.onRetry,
  });

  final Map<String, Object?> item;
  final bool showSenderName;
  final String currentUserAvatarUrl;
  final VoidCallback onLongPress;
  final VoidCallback? onTap;
  final bool redPacketReceiving;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isMe = item['is_me'] == true;
    final sender = _messageSenderName(item);
    final avatarUrl = isMe
        ? currentUserAvatarUrl
        : _messageSenderAvatarUrl(item);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _Avatar(label: sender, imageUrl: avatarUrl, size: 38, circle: true),
            const SizedBox(width: 8),
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
                      style: const TextStyle(color: _mutedColor, fontSize: 11),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: onTap,
                      onLongPress: onLongPress,
                      child: _MessageBubble(
                        item: item,
                        isMe: isMe,
                        status: _messageStatus(item),
                        redPacketReceiving: redPacketReceiving,
                        onRetry: onRetry,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _Avatar(
              label: '我',
              imageUrl: avatarUrl,
              size: 38,
              color: _primaryColor,
              circle: true,
            ),
          ],
        ],
      ),
    );
  }
}
