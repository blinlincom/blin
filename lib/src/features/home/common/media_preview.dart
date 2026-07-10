part of 'package:bim/src/features/home/home_page.dart';

class _EmojiMessagePreview extends StatelessWidget {
  const _EmojiMessagePreview({
    required this.payload,
    required this.content,
    required this.status,
    required this.onRetry,
  });

  final Map<String, Object?> payload;
  final String content;
  final String status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final asset = _emojiAssetForPayload(payload);
    final url = _normalizeAvatarUrl(
      _value(
        payload,
        ['url', 'file_url', 'image_url', 'gif_url'],
        fallback: _value(_asObjectMap(payload['media']), [
          'url',
          'file_url',
          'image_url',
          'gif_url',
        ]),
      ),
    );
    final image = asset.isNotEmpty
        ? Image.asset(
            asset,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => _fallbackText,
          )
        : url.isNotEmpty
        ? Image.network(
            url,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            loadingBuilder: _mediaLoadingBuilder,
            errorBuilder: (_, __, ___) => _fallbackText,
          )
        : _fallbackText;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(color: Color(0xfff4f5f7)),
              child: Center(child: image),
            ),
            _MediaUploadOverlay(
              status: status,
              progress: _uploadProgress(payload),
              onRetry: onRetry,
            ),
          ],
        ),
      ),
    );
  }

  Widget get _fallbackText {
    return const Text('[表情]', style: TextStyle(fontSize: 14, height: 1.2));
  }
}

class _ImageMessagePreview extends StatelessWidget {
  const _ImageMessagePreview({
    required this.payload,
    required this.status,
    required this.readText,
    required this.timeLabel,
    required this.isMe,
    required this.isGroupMessage,
    required this.onRetry,
    super.key,
  });

  final Map<String, Object?> payload;
  final String status;
  final String readText;
  final String timeLabel;
  final bool isMe;
  final bool isGroupMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localPath = _value(payload, ['file_path']);
    final url = _normalizeAvatarUrl(
      _value(payload, [
        'url',
        'image_path',
      ], fallback: _value(_asObjectMap(payload['media']), ['url'])),
    );
    final image = localPath.isNotEmpty && File(localPath).existsSync()
        ? Image.file(
            File(localPath),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const _MediaLoadPlaceholder(
              icon: Icons.broken_image_outlined,
              title: '图片无法显示',
            ),
          )
        : url.isNotEmpty
        ? Image.network(
            url,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: _mediaLoadingBuilder,
            errorBuilder: (_, __, ___) => const _MediaLoadPlaceholder(
              icon: Icons.broken_image_outlined,
              title: '图片加载失败',
            ),
          )
        : const _MediaLoadPlaceholder(
            icon: Icons.image_outlined,
            title: '图片地址为空',
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            _MediaUploadOverlay(
              status: status,
              progress: _uploadProgress(payload),
              onRetry: onRetry,
            ),
            _MediaMessageMetaBar(
              timeLabel: timeLabel,
              status: status,
              readText: readText,
              isMe: isMe,
              isGroupMessage: isGroupMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoMessagePreview extends StatelessWidget {
  const _VideoMessagePreview({
    required this.payload,
    required this.status,
    required this.readText,
    required this.timeLabel,
    required this.isMe,
    required this.isGroupMessage,
    required this.onRetry,
    super.key,
  });

  final Map<String, Object?> payload;
  final String status;
  final String readText;
  final String timeLabel;
  final bool isMe;
  final bool isGroupMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final media = _asObjectMap(payload['media']);
    final rawLocalPath = _value(payload, [
      'cover_file_path',
      'thumb_file_path',
      'thumbnail_file_path',
    ]);
    final rawCoverUrl = _value(
      payload,
      ['cover_url', 'thumb_url', 'thumbnail_url', 'image_path'],
      fallback: _value(media, [
        'cover_url',
        'thumb_url',
        'thumbnail_url',
        'image_path',
      ]),
    );
    final source = _videoPreviewSource(payload, media);
    final localPath = _looksLikeVideoPath(rawLocalPath) ? '' : rawLocalPath;
    final coverUrl = _looksLikeVideoPath(rawCoverUrl)
        ? ''
        : _normalizeAvatarUrl(rawCoverUrl);
    final image = localPath.isNotEmpty && File(localPath).existsSync()
        ? Image.file(
            File(localPath),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const _MediaLoadPlaceholder(
              icon: Icons.videocam_off_outlined,
              title: '封面无法显示',
            ),
          )
        : coverUrl.isNotEmpty
        ? Image.network(
            coverUrl,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            loadingBuilder: _mediaLoadingBuilder,
            errorBuilder: (_, __, ___) => const _MediaLoadPlaceholder(
              icon: Icons.videocam_off_outlined,
              title: '封面加载失败',
            ),
          )
        : null;
    if (image == null) {
      if (source != null) {
        return _VideoFramePreview(
          key: ValueKey(source.key),
          source: source,
          payload: payload,
          status: status,
          readText: readText,
          timeLabel: timeLabel,
          isMe: isMe,
          isGroupMessage: isGroupMessage,
          onRetry: onRetry,
        );
      }
      return _VideoPlaceholderPreview(
        payload: payload,
        status: status,
        readText: readText,
        timeLabel: timeLabel,
        isMe: isMe,
        isGroupMessage: isGroupMessage,
        onRetry: onRetry,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            if (status != 'sending')
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            _MediaUploadOverlay(
              status: status,
              progress: _uploadProgress(payload),
              onRetry: onRetry,
            ),
            _MediaMessageMetaBar(
              timeLabel: timeLabel,
              status: status,
              readText: readText,
              isMe: isMe,
              isGroupMessage: isGroupMessage,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _mediaLoadingBuilder(
  BuildContext context,
  Widget child,
  ImageChunkEvent? loadingProgress,
) {
  if (loadingProgress == null) {
    return child;
  }
  final expected = loadingProgress.expectedTotalBytes;
  final progress = expected == null || expected <= 0
      ? null
      : loadingProgress.cumulativeBytesLoaded / expected;
  return _MediaLoadPlaceholder(
    icon: Icons.image_outlined,
    title: '加载中',
    progress: progress,
  );
}

class _MediaLoadPlaceholder extends StatelessWidget {
  const _MediaLoadPlaceholder({
    required this.icon,
    required this.title,
    this.progress,
  });

  final IconData icon;
  final String title;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xffeef0f3)),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (value == null)
              Icon(icon, color: BimColors.mutedText, size: 28)
            else
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: value.clamp(0, 1).toDouble(),
                  strokeWidth: 2.2,
                  color: BimColors.mutedText,
                  backgroundColor: const Color(0x338e96a3),
                ),
              ),
            const SizedBox(height: 7),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xff737b88),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPreviewSource {
  const _VideoPreviewSource({required this.value, required this.isLocal});

  final String value;
  final bool isLocal;

  String get key => '${isLocal ? 'file' : 'url'}:$value';
}

class _VideoFramePreview extends StatefulWidget {
  const _VideoFramePreview({
    required this.source,
    required this.payload,
    required this.status,
    required this.readText,
    required this.timeLabel,
    required this.isMe,
    required this.isGroupMessage,
    required this.onRetry,
    super.key,
  });

  final _VideoPreviewSource source;
  final Map<String, Object?> payload;
  final String status;
  final String readText;
  final String timeLabel;
  final bool isMe;
  final bool isGroupMessage;
  final VoidCallback onRetry;

  @override
  State<_VideoFramePreview> createState() => _VideoFramePreviewState();
}

class _VideoFramePreviewState extends State<_VideoFramePreview> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _VideoFramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.key != widget.source.key) {
      _load();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final previous = _controller;
    _controller = null;
    _ready = false;
    await previous?.dispose();

    final source = widget.source;
    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller = source.isLocal
        ? VideoPlayerController.file(
            File(source.value),
            videoPlayerOptions: options,
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(source.value),
            videoPlayerOptions: options,
          );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.pause();
      if (!mounted || _controller != controller) {
        return;
      }
      setState(() => _ready = true);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'video preview initialize failed',
        error: error,
        stackTrace: stackTrace,
        data: {'source': source.key},
      );
      await controller.dispose();
      if (!mounted || _controller != controller) {
        return;
      }
      setState(() {
        _controller = null;
        _ready = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return _VideoPlaceholderPreview(
        payload: widget.payload,
        status: widget.status,
        readText: widget.readText,
        timeLabel: widget.timeLabel,
        isMe: widget.isMe,
        isGroupMessage: widget.isGroupMessage,
        onRetry: widget.onRetry,
      );
    }
    final size = controller.value.size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.black,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: size.width <= 0 ? 208 : size.width,
                  height: size.height <= 0 ? 124 : size.height,
                  child: VideoPlayer(controller),
                ),
              ),
            ),
            if (widget.status != 'sending')
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            _MediaUploadOverlay(
              status: widget.status,
              progress: _uploadProgress(widget.payload),
              onRetry: widget.onRetry,
            ),
            _MediaMessageMetaBar(
              timeLabel: widget.timeLabel,
              status: widget.status,
              readText: widget.readText,
              isMe: widget.isMe,
              isGroupMessage: widget.isGroupMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlaceholderPreview extends StatelessWidget {
  const _VideoPlaceholderPreview({
    required this.payload,
    required this.status,
    required this.readText,
    required this.timeLabel,
    required this.isMe,
    required this.isGroupMessage,
    required this.onRetry,
  });

  final Map<String, Object?> payload;
  final String status;
  final String readText;
  final String timeLabel;
  final bool isMe;
  final bool isGroupMessage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 208,
        height: 124,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff222832), Color(0xff101317)],
                ),
              ),
            ),
            const Positioned(
              left: 12,
              bottom: 10,
              child: Icon(
                Icons.videocam_outlined,
                color: Color(0x99ffffff),
                size: 18,
              ),
            ),
            if (status != 'sending')
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    color: Color(0x99000000),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
            _MediaUploadOverlay(
              status: status,
              progress: _uploadProgress(payload),
              onRetry: onRetry,
            ),
            _MediaMessageMetaBar(
              timeLabel: timeLabel,
              status: status,
              readText: readText,
              isMe: isMe,
              isGroupMessage: isGroupMessage,
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaMessageMetaBar extends StatelessWidget {
  const _MediaMessageMetaBar({
    required this.timeLabel,
    required this.status,
    required this.readText,
    required this.isMe,
    required this.isGroupMessage,
  });

  final String timeLabel;
  final String status;
  final String readText;
  final bool isMe;
  final bool isGroupMessage;

  @override
  Widget build(BuildContext context) {
    final statusText = _statusText;
    if (timeLabel.isEmpty && statusText.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x7d000000)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
            child: Row(
              children: [
                if (timeLabel.isNotEmpty)
                  Text(
                    timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _textStyle(BimColors.inverseText),
                  ),
                if (timeLabel.isNotEmpty && statusText.isNotEmpty)
                  const SizedBox(width: 8),
                if (statusText.isNotEmpty)
                  Expanded(
                    child: Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: _textStyle(_statusColor),
                    ),
                  )
                else
                  const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _statusText {
    if (!isMe) {
      return '';
    }
    return switch (status) {
      'sending' => '发送中',
      'queued' => '待发送',
      'failed' => '发送失败',
      'read' when isGroupMessage && readText.isNotEmpty => readText,
      'sent' when isGroupMessage && readText.isNotEmpty => readText,
      '' when isGroupMessage && readText.isNotEmpty => readText,
      'read' when isGroupMessage => '0人已读',
      'sent' when isGroupMessage => '0人已读',
      '' when isGroupMessage => '0人已读',
      'read' => '已读',
      'sent' => '未读',
      '' => '未读',
      _ => '',
    };
  }

  Color get _statusColor {
    return switch (status) {
      'failed' => const Color(0xffffd2d2),
      'read' => const Color(0xffc9f7d5),
      'sent' => BimColors.inverseText,
      _ => const Color(0xe6ffffff),
    };
  }

  TextStyle _textStyle(Color color) {
    return TextStyle(
      color: color,
      fontSize: 10.5,
      fontWeight: FontWeight.w800,
      height: 1,
      shadows: const [
        Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1)),
      ],
    );
  }
}

class _MediaUploadOverlay extends StatelessWidget {
  const _MediaUploadOverlay({
    required this.status,
    required this.progress,
    required this.onRetry,
  });

  final String status;
  final double progress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status != 'sending' && status != 'failed') {
      return const SizedBox.shrink();
    }
    final failed = status == 'failed';
    final hasProgress = progress > 0 && progress < 1;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: failed ? onRetry : null,
      child: ColoredBox(
        color: BimColors.scrim,
        child: Center(
          child: Container(
            width: failed ? 76 : 58,
            height: failed ? 62 : 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xaa000000),
              borderRadius: BorderRadius.circular(failed ? 10 : 999),
            ),
            child: failed
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, color: Colors.white, size: 25),
                      SizedBox(height: 4),
                      Text(
                        '重发',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ],
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          value: hasProgress ? progress : null,
                          strokeWidth: 2.4,
                          color: Colors.white,
                          backgroundColor: const Color(0x55ffffff),
                        ),
                      ),
                      if (hasProgress)
                        Text(
                          '${(progress * 100).clamp(1, 99).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
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
