part of 'package:bim/src/features/home/home_page.dart';

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.item,
    required this.isMe,
    required this.status,
    required this.redPacketReceiving,
    required this.onRetry,
  });

  final Map<String, Object?> item;
  final bool isMe;
  final String status;
  final bool redPacketReceiving;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final contentType = _messageContentType(item);
    final payload = _asObjectMap(item['payload']);
    final content = _messageContentText(item, payload);
    final quote = _messageQuote(item);
    final isImageLike =
        contentType == ChatContentTypes.image ||
        contentType == ChatContentTypes.gif ||
        contentType == ChatContentTypes.sticker ||
        contentType == ChatContentTypes.video;
    final bubble = _MessageBubbleContent(
      contentType: contentType,
      content: content,
      payload: payload,
      isMe: isMe,
      status: status,
      redPacketReceiving: redPacketReceiving,
      onRetry: onRetry,
    );
    final child = quote.isEmpty
        ? bubble
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _QuoteMessagePreview(quote: quote, isMe: isMe),
              const SizedBox(height: 5),
              bubble,
            ],
          );
    return Container(
      constraints: BoxConstraints(
        maxWidth: _bubbleMaxWidth(context, contentType),
      ),
      padding: _bubblePadding(contentType),
      decoration: BoxDecoration(
        color: _bubbleColor(contentType),
        borderRadius: BorderRadius.circular(isImageLike ? 8 : 9),
      ),
      child: child,
    );
  }

  Color _bubbleColor(String contentType) {
    if (contentType == ChatContentTypes.redPacket ||
        contentType == ChatContentTypes.video) {
      return Colors.transparent;
    }
    return isMe ? _chatMineBubbleColor : Colors.white;
  }

  EdgeInsets _bubblePadding(String contentType) {
    return switch (contentType) {
      ChatContentTypes.redPacket => EdgeInsets.zero,
      ChatContentTypes.image ||
      ChatContentTypes.gif ||
      ChatContentTypes.sticker ||
      ChatContentTypes.video => const EdgeInsets.all(0),
      ChatContentTypes.file ||
      ChatContentTypes.voice ||
      ChatContentTypes.contactCard ||
      ChatContentTypes.transfer => const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      _ => const EdgeInsets.fromLTRB(12, 8, 9, 7),
    };
  }

  double _bubbleMaxWidth(BuildContext context, String contentType) {
    final width = MediaQuery.sizeOf(context).width;
    return switch (contentType) {
      ChatContentTypes.redPacket =>
        (width * 0.72).clamp(220.0, 240.0).toDouble(),
      ChatContentTypes.file ||
      ChatContentTypes.video ||
      ChatContentTypes.contactCard ||
      ChatContentTypes.transfer => width * 0.62,
      ChatContentTypes.voice => width * 0.46,
      ChatContentTypes.image ||
      ChatContentTypes.gif ||
      ChatContentTypes.sticker => width * 0.62,
      _ => width * 0.58,
    };
  }
}

class _RedPacketPreview extends StatelessWidget {
  const _RedPacketPreview({
    required this.remark,
    required this.statusText,
    required this.receiving,
  });

  final String remark;
  final String statusText;
  final bool receiving;

  @override
  Widget build(BuildContext context) {
    final text = remark.isEmpty ? '恭喜发财，大吉大利' : remark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 226,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
              color: const Color(0xffff9f43),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xffe4422f),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xffffd878)),
                    ),
                    child: receiving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xffffd878),
                            ),
                          )
                        : const Icon(
                            Icons.redeem,
                            color: Color(0xffffd878),
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          statusText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xfffff3dc),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 27,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              color: Colors.white,
              child: const Text(
                'BIM红包',
                style: TextStyle(
                  color: Color(0xff9da5b1),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubbleContent extends StatelessWidget {
  const _MessageBubbleContent({
    required this.contentType,
    required this.content,
    required this.payload,
    required this.isMe,
    required this.status,
    required this.redPacketReceiving,
    required this.onRetry,
  });

  final String contentType;
  final String content;
  final Map<String, Object?> payload;
  final bool isMe;
  final String status;
  final bool redPacketReceiving;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return switch (contentType) {
      ChatContentTypes.image => _ImageMessagePreview(
        key: ValueKey(_mediaPreviewKey(contentType, payload, content)),
        payload: payload,
        status: status,
        onRetry: onRetry,
      ),
      ChatContentTypes.gif => _MediaPreview(
        icon: Icons.gif_box_outlined,
        title: content.isEmpty ? 'GIF' : content,
        subtitle: _value(payload, ['url', 'file_path']),
        isMe: isMe,
      ),
      ChatContentTypes.sticker => _StickerPreview(
        text: _value(payload, ['sticker_id', 'emoji_code'], fallback: content),
      ),
      ChatContentTypes.emoji => Text(
        _value(payload, [
          'emoji_code',
        ], fallback: content.isEmpty ? '[表情]' : content),
        style: const TextStyle(fontSize: 24, height: 1.2),
      ),
      ChatContentTypes.voice => _VoicePreview(
        seconds: _value(payload, ['duration'], fallback: '0'),
        isMe: isMe,
      ),
      ChatContentTypes.video => _VideoMessagePreview(
        key: ValueKey(_mediaPreviewKey(contentType, payload, content)),
        payload: payload,
        status: status,
        onRetry: onRetry,
      ),
      ChatContentTypes.file => _FilePreview(payload: payload, content: content),
      ChatContentTypes.contactCard => _ContactCardPreview(payload: payload),
      ChatContentTypes.transfer => _PaymentPreview(
        icon: Icons.payments_outlined,
        title: '转账',
        amount: _paymentAmount(payload),
        isMe: isMe,
      ),
      ChatContentTypes.redPacket => _RedPacketPreview(
        remark: _redPacketRemark(payload),
        statusText: _redPacketStatusText(
          payload,
          receiving: redPacketReceiving,
        ),
        receiving: redPacketReceiving,
      ),
      _ => Text(
        content.isEmpty ? '[消息]' : content,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    };
  }
}

class _QuoteMessagePreview extends StatelessWidget {
  const _QuoteMessagePreview({required this.quote, required this.isMe});

  final Map<String, Object?> quote;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final sender = _quoteSenderName(quote);
    final preview = _quotePreviewText(quote);
    final text = sender.isEmpty ? preview : '$sender：$preview';
    final borderColor = isMe
        ? const Color(0xff96d58c)
        : const Color(0xffd8dce3);
    final background = isMe ? const Color(0x55ffffff) : const Color(0xfff4f5f7);
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        border: Border(left: BorderSide(color: borderColor, width: 3)),
      ),
      child: Text(
        text.isEmpty ? '原消息不可查看' : text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xff6f7785),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      ),
    );
  }
}

class _StickerPreview extends StatelessWidget {
  const _StickerPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.isEmpty ? '[贴纸]' : text,
      style: const TextStyle(
        color: _textColor,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
    );
  }
}

class _VoicePreview extends StatelessWidget {
  const _VoicePreview({required this.seconds, required this.isMe});

  final String seconds;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final label = seconds == '0' || seconds.isEmpty ? '' : '$seconds"';
    return SizedBox(
      width: 100,
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) const Icon(Icons.graphic_eq, size: 20),
          if (!isMe) const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (isMe) const SizedBox(width: 8),
          if (isMe) const Icon(Icons.graphic_eq, size: 20),
        ],
      ),
    );
  }
}

String _mediaPreviewKey(
  String contentType,
  Map<String, Object?> payload,
  String content,
) {
  final media = _asObjectMap(payload['media']);
  final identity = _value(
    payload,
    [
      'file_id',
      'media_id',
      'attachment_id',
      'url',
      'file_path',
      'cover_url',
      'thumb_url',
      'thumbnail_url',
      'image_path',
      'video_path',
    ],
    fallback: _value(media, [
      'file_id',
      'media_id',
      'attachment_id',
      'url',
      'path',
      'file_path',
      'cover_url',
      'thumb_url',
      'thumbnail_url',
      'image_path',
      'video_path',
    ]),
  );
  if (identity.isNotEmpty) {
    return '$contentType:$identity';
  }
  final descriptor = _value(payload, [
    'file_name',
    'name',
    'duration',
    'size',
  ], fallback: content);
  return '$contentType:$descriptor';
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.payload, required this.content});

  final Map<String, Object?> payload;
  final String content;

  @override
  Widget build(BuildContext context) {
    final media = _asObjectMap(payload['media']);
    final name = _value(payload, [
      'file_name',
      'name',
      'filename',
    ], fallback: _value(media, ['name'], fallback: content));
    final size = _value(payload, [
      'file_size',
      'size',
    ], fallback: _value(media, ['size']));
    return SizedBox(
      width: 218,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xfff05045),
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
            child: const Icon(
              Icons.article_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name.isEmpty ? '文件' : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                if (size.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      _fileSizeLabel(size),
                      style: const TextStyle(color: _mutedColor, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCardPreview extends StatelessWidget {
  const _ContactCardPreview({required this.payload});

  final Map<String, Object?> payload;

  @override
  Widget build(BuildContext context) {
    final name = _value(payload, [
      'card_nickname',
      'nickname',
      'name',
      'card_user_id',
    ]);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Avatar(label: name, size: 32, color: const Color(0xff34c759)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name.isEmpty ? '名片' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentPreview extends StatelessWidget {
  const _PaymentPreview({
    required this.icon,
    required this.title,
    required this.amount,
    required this.isMe,
  });

  final IconData icon;
  final String title;
  final String amount;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xffd46b08), size: 24),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (amount.isNotEmpty)
              Text(
                amount,
                style: TextStyle(
                  color: isMe
                      ? const Color(0xff477a35)
                      : const Color(0xff8b929e),
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MessageSendStatus extends StatelessWidget {
  const _MessageSendStatus({
    required this.status,
    required this.readText,
    required this.onRetry,
  });

  final String status;
  final String readText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == 'read' && readText.isNotEmpty) {
      return Text(
        readText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _chatAckColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      );
    }
    return SizedBox(
      width: 18,
      height: 18,
      child: Center(
        child: switch (status) {
          'sending' => const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Color(0xff9aa0aa),
            ),
          ),
          'failed' => Tooltip(
            message: '重发',
            child: InkResponse(
              onTap: onRetry,
              radius: 18,
              child: const Icon(
                Icons.error_outline,
                size: 17,
                color: _dangerColor,
              ),
            ),
          ),
          'read' => const Icon(Icons.done_all, size: 17, color: _chatAckColor),
          'queued' ||
          'sent' => const Icon(Icons.done, size: 17, color: _chatAckColor),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }
}

class _TimeDivider extends StatelessWidget {
  const _TimeDivider({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xff8f96a3),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MessageActionItem {
  const _MessageActionItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool destructive;
}

class _MessageActionOverlay extends StatelessWidget {
  const _MessageActionOverlay({
    required this.anchor,
    required this.actions,
    required this.onDismiss,
  });

  final Offset anchor;
  final List<_MessageActionItem> actions;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onDismiss,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const actionWidth = 58.0;
            const menuHeight = 64.0;
            final maxWidth = max(120.0, constraints.maxWidth - 24);
            final menuWidth = min(maxWidth, actions.length * actionWidth + 12);
            final left = (anchor.dx - menuWidth / 2)
                .clamp(12.0, max(12.0, constraints.maxWidth - menuWidth - 12))
                .toDouble();
            final showAbove = anchor.dy > menuHeight + 92;
            final rawTop = showAbove
                ? anchor.dy - menuHeight - 14
                : anchor.dy + 14;
            final top = rawTop
                .clamp(8.0, max(8.0, constraints.maxHeight - menuHeight - 14))
                .toDouble();
            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: menuWidth,
                  height: menuHeight,
                  child: _MessageActionMenu(actions: actions),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MessageActionMenu extends StatelessWidget {
  const _MessageActionMenu({required this.actions});

  final List<_MessageActionItem> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xee202124),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in actions)
                _MessageActionButton(action: action),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageActionButton extends StatelessWidget {
  const _MessageActionButton({required this.action});

  final _MessageActionItem action;

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? const Color(0xffffb4ab) : Colors.white;
    return Semantics(
      button: true,
      label: action.label,
      child: SizedBox(
        width: 58,
        height: 64,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: action.onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(action.icon, color: color, size: 20),
                const SizedBox(height: 5),
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatOptionBar extends StatelessWidget {
  const _ChatOptionBar({required this.text, required this.onClear});

  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xffb87f00)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff785800),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              tooltip: '清除选项',
              padding: EdgeInsets.zero,
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
