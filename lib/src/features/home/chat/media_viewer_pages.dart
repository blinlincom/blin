part of 'package:bim/src/features/home/home_page.dart';

class _ChatMediaItem {
  const _ChatMediaItem({
    required this.contentType,
    required this.title,
    required this.localPath,
    required this.url,
    required this.mime,
    required this.size,
    required this.durationSeconds,
    required this.clientMsgNo,
  });

  final String contentType;
  final String title;
  final String localPath;
  final String url;
  final String mime;
  final String size;
  final int durationSeconds;
  final String clientMsgNo;

  factory _ChatMediaItem.fromMessage(Map<String, Object?> item) {
    final contentType = _messageContentType(item);
    final payload = _asObjectMap(item['payload']);
    final media = _asObjectMap(payload['media']);
    final content = _messageContentText(item, payload);
    final localPath = _mediaLocalPath(contentType, payload, media);
    final url = _mediaRemoteUrl(contentType, payload, media);
    final title = _mediaDisplayName(contentType, payload, media, content);
    final duration = _intValue(payload, ['duration']);
    return _ChatMediaItem(
      contentType: contentType,
      title: title,
      localPath: localPath,
      url: url,
      mime: _value(payload, [
        'mime',
        'mime_type',
      ], fallback: _value(media, ['mime', 'mime_type'])),
      size: _value(payload, [
        'size',
        'file_size',
      ], fallback: _value(media, ['size', 'file_size'])),
      durationSeconds: duration,
      clientMsgNo: _value(item, ['client_msg_no']),
    );
  }

  bool get isImage => contentType == ChatContentTypes.image;
  bool get isImageLike =>
      contentType == ChatContentTypes.image ||
      contentType == ChatContentTypes.emoji ||
      contentType == ChatContentTypes.gif ||
      contentType == ChatContentTypes.sticker;
  bool get isVideo => contentType == ChatContentTypes.video;
  bool get isFile => contentType == ChatContentTypes.file;
  bool get isAsset => localPath.startsWith('assets/');
  bool get hasRemote => url.isNotEmpty;
  String get existingLocalPath {
    if (localPath.isEmpty || isAsset) {
      return '';
    }
    try {
      return File(localPath).existsSync() ? localPath : '';
    } on Object {
      return '';
    }
  }

  bool get hasSource => isAsset || existingLocalPath.isNotEmpty || hasRemote;

  String get displaySize => _fileSizeLabel(size);
  String get displayDuration =>
      durationSeconds <= 0 ? '' : _secondsLabel(durationSeconds);
}

class _MediaViewerPage extends StatelessWidget {
  const _MediaViewerPage({required this.media});

  final _ChatMediaItem media;

  @override
  Widget build(BuildContext context) {
    if (media.isImageLike) {
      return _ImageMediaViewerPage(media: media);
    }
    if (media.isVideo) {
      return _VideoMediaViewerPage(media: media);
    }
    return _FileMediaViewerPage(media: media);
  }
}

class _ImageMediaViewerPage extends StatefulWidget {
  const _ImageMediaViewerPage({required this.media});

  final _ChatMediaItem media;

  @override
  State<_ImageMediaViewerPage> createState() => _ImageMediaViewerPageState();
}

class _ImageMediaViewerPageState extends State<_ImageMediaViewerPage> {
  final TransformationController _transformController =
      TransformationController();
  TapDownDetails? _lastTapDown;
  bool _zoomed = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_zoomed) {
      _transformController.value = Matrix4.identity();
      _zoomed = false;
      return;
    }
    final position = _lastTapDown?.localPosition ?? Offset.zero;
    const scale = 2.3;
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, -position.dx * (scale - 1))
      ..setEntry(1, 3, -position.dy * (scale - 1));
    _zoomed = true;
  }

  @override
  Widget build(BuildContext context) {
    final localPath = widget.media.existingLocalPath;
    final image = widget.media.isAsset
        ? Image.asset(
            widget.media.localPath,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                const _FullScreenMediaError(text: '图片无法显示'),
          )
        : localPath.isNotEmpty
        ? Image.file(
            File(localPath),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) =>
                const _FullScreenMediaError(text: '图片无法显示'),
          )
        : widget.media.url.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: widget.media.url,
            fit: BoxFit.contain,
            fadeInDuration: Duration.zero,
            progressIndicatorBuilder: (_, __, progress) =>
                _FullScreenMediaLoading(progress: progress.progress),
            errorWidget: (_, __, ___) =>
                const _FullScreenMediaError(text: '图片加载失败'),
          )
        : const _FullScreenMediaError(text: '图片资源不存在');
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onDoubleTapDown: (details) => _lastTapDown = details,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 1,
                  maxScale: 4,
                  child: Center(child: image),
                ),
              ),
            ),
            _MediaViewerTopBar(
              title: '',
              dark: true,
              trailing: _MediaDownloadButton(media: widget.media, dark: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoMediaViewerPage extends StatefulWidget {
  const _VideoMediaViewerPage({required this.media});

  final _ChatMediaItem media;

  @override
  State<_VideoMediaViewerPage> createState() => _VideoMediaViewerPageState();
}

class _VideoMediaViewerPageState extends State<_VideoMediaViewerPage> {
  VideoPlayerController? _controller;
  Future<void>? _loadFuture;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_onVideoChanged);
    controller?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = widget.media.existingLocalPath;
    final options = VideoPlayerOptions(mixWithOthers: true);
    final controller = source.isNotEmpty
        ? VideoPlayerController.file(File(source), videoPlayerOptions: options)
        : widget.media.url.isNotEmpty
        ? VideoPlayerController.networkUrl(
            Uri.parse(widget.media.url),
            videoPlayerOptions: options,
          )
        : null;
    if (controller == null) {
      _error = '视频资源不存在';
      return;
    }
    _controller = controller;
    controller.addListener(_onVideoChanged);
    try {
      await controller.initialize();
      await controller.pause();
    } catch (error, stackTrace) {
      _error = '视频加载失败';
      AppLogger.error(
        'chat',
        'video viewer initialize failed',
        error: error,
        stackTrace: stackTrace,
        data: {'url': widget.media.url, 'path': widget.media.localPath},
      );
    }
  }

  void _onVideoChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _seek(double milliseconds) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    await controller.seekTo(Duration(milliseconds: milliseconds.round()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<void>(
                future: _loadFuture,
                builder: (context, snapshot) {
                  final controller = _controller;
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _FullScreenMediaLoading();
                  }
                  if (_error != null ||
                      controller == null ||
                      !controller.value.isInitialized) {
                    return _FullScreenMediaError(text: _error ?? '视频无法播放');
                  }
                  final size = controller.value.size;
                  return Center(
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.contain,
                            child: SizedBox(
                              width: size.width <= 0 ? 320 : size.width,
                              height: size.height <= 0 ? 180 : size.height,
                              child: VideoPlayer(controller),
                            ),
                          ),
                          if (!controller.value.isPlaying)
                            const _VideoPlayBadge(size: 62),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            _MediaViewerTopBar(
              title: '',
              dark: true,
              trailing: _MediaDownloadButton(media: widget.media, dark: true),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _VideoControls(
                controller: _controller,
                onPlayToggle: _togglePlay,
                onSeek: _seek,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileMediaViewerPage extends StatelessWidget {
  const _FileMediaViewerPage({required this.media});

  final _ChatMediaItem media;

  @override
  Widget build(BuildContext context) {
    final title = media.title.isEmpty ? '文件' : media.title;
    final size = media.displaySize;
    final mime = media.mime;
    return BimScaffold(
      backgroundColor: BimColors.surface,
      topBar: const BimTopBar(title: '文件'),
      body: BimContentViewport(
        maxWidth: 680,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
          children: [
            Icon(_fileIcon(title), size: 58, color: const Color(0xfff05045)),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            _FileInfoLine(label: '大小', value: size.isEmpty ? '未知' : size),
            _FileInfoLine(label: '类型', value: mime.isEmpty ? '未知' : mime),
            _FileInfoLine(
              label: '来源',
              value: media.existingLocalPath.isNotEmpty ? '本地文件' : '远程文件',
            ),
            const SizedBox(height: 26),
            _FileDownloadPanel(media: media),
          ],
        ),
      ),
    );
  }
}

class _MediaViewerTopBar extends StatelessWidget {
  const _MediaViewerTopBar({
    required this.title,
    required this.dark,
    required this.trailing,
  });

  final String title;
  final bool dark;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : _textColor;
    return Positioned(
      left: 0,
      top: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: dark ? const Color(0x66000000) : _surfaceColor,
          border: dark
              ? null
              : const Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 50,
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      color: color,
                      size: 20,
                    ),
                  ),
                ),
                Expanded(
                  child: title.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
                SizedBox(width: 50, height: 50, child: trailing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaDownloadButton extends StatefulWidget {
  const _MediaDownloadButton({required this.media, required this.dark});

  final _ChatMediaItem media;
  final bool dark;

  @override
  State<_MediaDownloadButton> createState() => _MediaDownloadButtonState();
}

class _MediaDownloadButtonState extends State<_MediaDownloadButton> {
  bool _downloading = false;
  double _progress = 0;

  Future<void> _download() async {
    if (_downloading) {
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      final path = await _downloadMediaToDevice(
        widget.media,
        onProgress: (value) {
          if (mounted) {
            setState(() => _progress = value);
          }
        },
      );
      if (!mounted) {
        return;
      }
      showBimSnackBar(context, '已保存到 $path', tone: BimNoticeTone.success);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'media download failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'type': widget.media.contentType,
          'url': widget.media.url,
          'path': widget.media.localPath,
        },
      );
      if (mounted) {
        showBimSnackBar(context, '下载失败：$error', tone: BimNoticeTone.error);
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.dark ? Colors.white : _textColor;
    if (_downloading) {
      final hasProgress = _progress > 0 && _progress < 1;
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            value: hasProgress ? _progress : null,
            strokeWidth: 2.4,
            color: color,
            backgroundColor: widget.dark ? const Color(0x44ffffff) : null,
          ),
        ),
      );
    }
    return IconButton(
      tooltip: '下载',
      onPressed: widget.media.hasSource ? _download : null,
      icon: Icon(Icons.file_download_outlined, color: color),
    );
  }
}

class _FileDownloadPanel extends StatefulWidget {
  const _FileDownloadPanel({required this.media});

  final _ChatMediaItem media;

  @override
  State<_FileDownloadPanel> createState() => _FileDownloadPanelState();
}

class _FileDownloadPanelState extends State<_FileDownloadPanel> {
  bool _downloading = false;
  double _progress = 0;
  String _downloadedPath = '';
  String _error = '';

  Future<void> _download() async {
    if (_downloading || !widget.media.hasSource) {
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = '';
    });
    try {
      final path = await _downloadMediaToDevice(
        widget.media,
        onProgress: (value) {
          if (mounted) {
            setState(() => _progress = value);
          }
        },
      );
      if (!mounted) {
        return;
      }
      setState(() => _downloadedPath = path);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'file download failed',
        error: error,
        stackTrace: stackTrace,
        data: {'url': widget.media.url, 'path': widget.media.localPath},
      );
      if (mounted) {
        setState(() => _error = '下载失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.media.hasSource) {
      return const _InlineMediaError(text: '文件资源不存在');
    }
    final progressText = _progress > 0 && _progress < 1
        ? ' ${(100 * _progress).round()}%'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _downloading ? null : _download,
          icon: _downloading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.file_download_outlined),
          label: Text(_downloading ? '下载中$progressText' : '下载文件'),
        ),
        if (_downloadedPath.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            '已保存到',
            style: TextStyle(
              color: _secondaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _downloadedPath,
            style: const TextStyle(
              color: _textColor,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 12),
          _InlineMediaError(text: _error),
        ],
      ],
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({
    required this.controller,
    required this.onPlayToggle,
    required this.onSeek,
  });

  final VideoPlayerController? controller;
  final VoidCallback onPlayToggle;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final current = controller;
    if (current == null || !current.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final position = current.value.position;
    final duration = current.value.duration;
    final maxMs = max(1, duration.inMilliseconds).toDouble();
    final value = position.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x99000000)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: IconButton(
                  tooltip: current.value.isPlaying ? '暂停' : '播放',
                  onPressed: onPlayToggle,
                  icon: Icon(
                    current.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                ),
              ),
              Text(
                _secondsLabel(position.inSeconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  min: 0,
                  max: maxMs,
                  onChanged: onSeek,
                  activeColor: Colors.white,
                  inactiveColor: const Color(0x55ffffff),
                ),
              ),
              Text(
                _secondsLabel(duration.inSeconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPlayBadge extends StatelessWidget {
  const _VideoPlayBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0x99000000),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow, color: Colors.white, size: size * 0.58),
    );
  }
}

class _FullScreenMediaLoading extends StatelessWidget {
  const _FullScreenMediaLoading({this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 38,
        height: 38,
        child: CircularProgressIndicator(
          value: progress?.clamp(0, 1).toDouble(),
          strokeWidth: 2.6,
          color: Colors.white,
          backgroundColor: const Color(0x44ffffff),
        ),
      ),
    );
  }
}

class _FullScreenMediaError extends StatelessWidget {
  const _FullScreenMediaError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

class _InlineMediaError extends StatelessWidget {
  const _InlineMediaError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: _dangerColor,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
    );
  }
}

class _FileInfoLine extends StatelessWidget {
  const _FileInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              label,
              style: const TextStyle(
                color: _secondaryTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _mediaLocalPath(
  String contentType,
  Map<String, Object?> payload,
  Map<String, Object?> media,
) {
  final keys = switch (contentType) {
    ChatContentTypes.video => ['file_path', 'video_file_path', 'local_path'],
    ChatContentTypes.file => ['file_path', 'local_path', 'path'],
    ChatContentTypes.emoji ||
    ChatContentTypes.gif ||
    ChatContentTypes.sticker => [
      'file_path',
      'image_file_path',
      'local_path',
      'emoji_asset',
      'sticker_asset',
      'asset',
    ],
    _ => ['file_path', 'image_file_path', 'local_path'],
  };
  for (final key in keys) {
    final value = _value(payload, [key], fallback: _value(media, [key]));
    if (value.isEmpty || _isRemoteResource(value)) {
      continue;
    }
    if (value.startsWith('assets/')) {
      return value;
    }
    if (_isLikelyLocalPath(value)) {
      return value;
    }
  }
  return '';
}

String _mediaRemoteUrl(
  String contentType,
  Map<String, Object?> payload,
  Map<String, Object?> media,
) {
  final keys = switch (contentType) {
    ChatContentTypes.video => [
      'video_url',
      'file_url',
      'url',
      'video_path',
      'file_path',
    ],
    ChatContentTypes.file => ['file_url', 'url', 'file_path', 'path'],
    ChatContentTypes.emoji ||
    ChatContentTypes.gif ||
    ChatContentTypes.sticker => [
      'url',
      'file_url',
      'image_url',
      'gif_url',
      'emoji_url',
      'sticker_url',
      'path',
    ],
    _ => ['image_url', 'url', 'image_path', 'file_url', 'file_path'],
  };
  for (final key in keys) {
    final raw = _value(payload, [key], fallback: _value(media, [key]));
    if (raw.isEmpty || _isLikelyLocalPath(raw)) {
      continue;
    }
    final url = _normalizeAvatarUrl(raw);
    if (url.isNotEmpty) {
      return url;
    }
  }
  return '';
}

String _mediaDisplayName(
  String contentType,
  Map<String, Object?> payload,
  Map<String, Object?> media,
  String content,
) {
  final fromPayload = _value(payload, [
    'file_name',
    'name',
    'filename',
    'title',
  ], fallback: _value(media, ['file_name', 'name', 'filename', 'title']));
  if (fromPayload.isNotEmpty) {
    return fromPayload;
  }
  if (content.isNotEmpty && content != '[消息]') {
    return content;
  }
  final source = _value(payload, [
    'file_path',
    'url',
    'file_url',
  ], fallback: _value(media, ['file_path', 'url', 'file_url']));
  if (source.isNotEmpty) {
    return _fileName(source);
  }
  return switch (contentType) {
    ChatContentTypes.image => '图片',
    ChatContentTypes.video => '视频',
    ChatContentTypes.file => '文件',
    _ => '媒体',
  };
}

bool _isRemoteResource(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

bool _isLikelyLocalPath(String value) {
  final text = value.trim();
  if (text.isEmpty || _isRemoteResource(text)) {
    return false;
  }
  if (text.startsWith('/storage/') ||
      text.startsWith('/sdcard/') ||
      text.startsWith('/data/') ||
      text.startsWith('/var/') ||
      text.startsWith('/Users/') ||
      text.startsWith('/home/')) {
    return true;
  }
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(text);
}

Future<String> _downloadMediaToDevice(
  _ChatMediaItem media, {
  required ValueChanged<double> onProgress,
}) async {
  if (!media.hasSource) {
    throw Exception('媒体资源不存在');
  }
  final dirs = await _mediaDownloadDirectories(media.contentType);
  Object? lastError;
  for (final dir in dirs) {
    try {
      await dir.create(recursive: true);
      final target = await _uniqueDownloadTarget(dir, media);
      if (media.existingLocalPath.isNotEmpty) {
        return _copyLocalMedia(
          sourcePath: media.existingLocalPath,
          targetPath: target.path,
          onProgress: onProgress,
        );
      }
      return _downloadRemoteMedia(
        url: media.url,
        targetPath: target.path,
        onProgress: onProgress,
      );
    } catch (error) {
      lastError = error;
    }
  }
  throw Exception(lastError?.toString() ?? '没有可写入的下载目录');
}

Future<List<Directory>> _mediaDownloadDirectories(String contentType) async {
  final dirs = <Directory>[];
  Future<void> add(Directory? dir, String child) async {
    if (dir == null) {
      return;
    }
    dirs.add(Directory('${dir.path}/BIM/$child'));
  }

  final child = switch (contentType) {
    ChatContentTypes.image ||
    ChatContentTypes.emoji ||
    ChatContentTypes.gif ||
    ChatContentTypes.sticker => 'Images',
    ChatContentTypes.video => 'Videos',
    ChatContentTypes.file => 'Files',
    _ => 'Media',
  };
  if (Platform.isAndroid) {
    dirs.add(Directory('/storage/emulated/0/Download/BIM/$child'));
  }
  try {
    await add(await getDownloadsDirectory(), child);
  } on Object {
    // Not every Flutter platform exposes a user Downloads directory.
  }
  await add(await getApplicationDocumentsDirectory(), child);
  await add(await getApplicationSupportDirectory(), child);
  return dirs;
}

Future<File> _uniqueDownloadTarget(Directory dir, _ChatMediaItem media) async {
  final baseName = _safeDownloadFileName(media);
  final target = File('${dir.path}/$baseName');
  if (!await target.exists()) {
    return target;
  }
  final dot = baseName.lastIndexOf('.');
  final stem = dot <= 0 ? baseName : baseName.substring(0, dot);
  final ext = dot <= 0 ? '' : baseName.substring(dot);
  return File('${dir.path}/$stem-${DateTime.now().millisecondsSinceEpoch}$ext');
}

String _safeDownloadFileName(_ChatMediaItem media) {
  final rawName = media.title.isNotEmpty ? media.title : _fileName(media.url);
  var name = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (name.isEmpty || name == '[图片]' || name == '[视频]' || name == '[文件]') {
    name = switch (media.contentType) {
      ChatContentTypes.image => 'image',
      ChatContentTypes.emoji => 'emoji',
      ChatContentTypes.gif => 'gif',
      ChatContentTypes.sticker => 'sticker',
      ChatContentTypes.video => 'video',
      ChatContentTypes.file => 'file',
      _ => 'media',
    };
  }
  final dot = name.lastIndexOf('.');
  final hasExtension = dot > 0 && dot < name.length - 1;
  final stem = hasExtension ? name.substring(0, dot) : name;
  final ext = hasExtension ? name.substring(dot) : _downloadExtension(media);
  final suffix = _downloadFileNameSuffix(media);
  return '$stem$suffix$ext';
}

String _downloadFileNameSuffix(_ChatMediaItem media) {
  final raw = media.clientMsgNo.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
  if (raw.isEmpty) {
    return '';
  }
  final short = raw.length <= 10 ? raw : raw.substring(raw.length - 10);
  return '-$short';
}

String _downloadExtension(_ChatMediaItem media) {
  final source = media.existingLocalPath.isNotEmpty
      ? media.existingLocalPath
      : media.url;
  final clean = source.split('?').first;
  final dot = clean.lastIndexOf('.');
  if (dot >= 0 && dot < clean.length - 1) {
    final ext = clean.substring(dot);
    if (ext.length <= 8) {
      return ext;
    }
  }
  if (media.mime.contains('png')) {
    return '.png';
  }
  if (media.mime.contains('gif')) {
    return '.gif';
  }
  if (media.mime.contains('webp')) {
    return '.webp';
  }
  if (media.mime.contains('video')) {
    return '.mp4';
  }
  if (media.mime.contains('pdf')) {
    return '.pdf';
  }
  return media.isImage ? '.jpg' : '';
}

Future<String> _copyLocalMedia({
  required String sourcePath,
  required String targetPath,
  required ValueChanged<double> onProgress,
}) async {
  if (sourcePath == targetPath) {
    onProgress(1);
    return targetPath;
  }
  final source = File(sourcePath);
  final target = File(targetPath);
  final total = await source.length();
  var written = 0;
  final input = source.openRead();
  final output = target.openWrite();
  try {
    await for (final chunk in input) {
      output.add(chunk);
      written += chunk.length;
      if (total > 0) {
        onProgress((written / total).clamp(0, 1).toDouble());
      }
    }
    await output.flush();
    await output.close();
    onProgress(1);
    return target.path;
  } catch (_) {
    await output.close();
    await target.delete().catchError((Object _) => target);
    rethrow;
  }
}

Future<String> _downloadRemoteMedia({
  required String url,
  required String targetPath,
  required ValueChanged<double> onProgress,
}) async {
  if (url.isEmpty) {
    throw Exception('下载地址为空');
  }
  final target = File(targetPath);
  try {
    await Dio().download(
      url,
      target.path,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress((received / total).clamp(0, 1).toDouble());
        }
      },
    );
    onProgress(1);
    return target.path;
  } catch (_) {
    await target.delete().catchError((Object _) => target);
    rethrow;
  }
}
