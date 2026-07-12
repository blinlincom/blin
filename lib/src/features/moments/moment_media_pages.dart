part of 'moments_page.dart';

class _MomentMediaPickerPage extends StatefulWidget {
  const _MomentMediaPickerPage({required this.mediaType});

  final String mediaType;

  @override
  State<_MomentMediaPickerPage> createState() => _MomentMediaPickerPageState();
}

class _MomentMediaPickerPageState extends State<_MomentMediaPickerPage> {
  static const _pageSize = 120;

  final ScrollController _controller = ScrollController();
  List<AssetEntity> _assets = const [];
  AssetEntity? _selected;
  bool _loading = true;
  bool _selecting = false;
  String _error = '';

  bool get _isVideo => widget.mediaType == 'video';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        setState(() {
          _loading = false;
          _error = '需要授权访问相册';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: _isVideo ? RequestType.video : RequestType.image,
        hasAll: true,
      );
      if (albums.isEmpty) {
        setState(() {
          _loading = false;
          _assets = const [];
        });
        return;
      }
      final album = albums.firstWhere(
        (item) => item.isAll,
        orElse: () => albums.first,
      );
      final assets = await album.getAssetListPaged(page: 0, size: _pageSize);
      if (!mounted) {
        return;
      }
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'load picker failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '媒体读取失败';
        });
      }
    }
  }

  Future<void> _confirm() async {
    final selected = _selected;
    if (selected == null || _selecting) {
      return;
    }
    setState(() => _selecting = true);
    try {
      final file = await selected.originFile ?? await selected.file;
      if (file == null || file.path.isEmpty) {
        throw const FileSystemException('media file unavailable');
      }
      final stat = await file.stat();
      final title = await selected.titleAsync;
      final media = _MomentLocalMedia(
        filePath: file.path,
        mediaType: widget.mediaType,
        name: title.isNotEmpty ? title : _fileName(file.path),
        mime: selected.mimeType ?? '',
        size: stat.size,
        width: selected.width,
        height: selected.height,
        duration: selected.duration,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(media);
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'select media failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _selecting = false);
        _showMomentMessage(context, '媒体读取失败', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = _selected == null
        ? (_isVideo ? '选择一个视频' : '选择一张图片')
        : (_isVideo ? '已选择视频' : '已选择图片');
    return BimScaffold(
      backgroundColor: BimColors.background,
      topBar: BimTopBar(title: _isVideo ? '选择视频' : '选择图片'),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const BimLoadingState(label: '正在加载媒体')
                : _error.isNotEmpty
                ? _MomentErrorState(error: _error, onRetry: _load)
                : _assets.isEmpty
                ? BimEmptyState(
                    title: _isVideo ? '没有可选择的视频' : '没有可选择的图片',
                    message: '新拍摄或保存的内容会显示在这里',
                    icon: _isVideo
                        ? Icons.video_library_outlined
                        : Icons.photo_library_outlined,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1024
                          ? 7
                          : constraints.maxWidth >= 600
                          ? 5
                          : 4;
                      return GridView.builder(
                        controller: _controller,
                        padding: const EdgeInsets.all(BimSpacing.x1),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: BimSpacing.x1,
                          mainAxisSpacing: BimSpacing.x1,
                        ),
                        itemCount: _assets.length,
                        itemBuilder: (context, index) {
                          final asset = _assets[index];
                          final selected = _selected?.id == asset.id;
                          return _PickerAssetTile(
                            asset: asset,
                            selected: selected,
                            isVideo: _isVideo,
                            onTap: () => setState(() => _selected = asset),
                          );
                        },
                      );
                    },
                  ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: BimColors.surface,
              border: Border(top: BorderSide(color: BimColors.borderLight)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  BimSpacing.x4,
                  BimSpacing.x3,
                  BimSpacing.x4,
                  BimSpacing.x3,
                ),
                child: BimContentViewport(
                  maxWidth: 680,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: BimColors.secondaryText,
                            fontSize: BimTypography.meta,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: BimSpacing.x4),
                      SizedBox(
                        width: 128,
                        child: BimButton(
                          label: '使用',
                          busy: _selecting,
                          onPressed: _selected == null ? null : _confirm,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerAssetTile extends StatelessWidget {
  const _PickerAssetTile({
    required this.asset,
    required this.selected,
    required this.isVideo,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selected;
  final bool isVideo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: asset.thumbnailDataWithSize(const ThumbnailSize(300, 300)),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return const ColoredBox(color: Color(0xffdde2e8));
              }
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            },
          ),
          if (isVideo)
            const Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 32,
              ),
            ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _momentsPrimary : const Color(0x66000000),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _MomentAvatar extends StatelessWidget {
  const _MomentAvatar({
    required this.label,
    required this.imageUrl,
    required this.size,
  });

  final String label;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = _avatarUrl(imageUrl);
    final radius = _momentAvatarRadius(size);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xff8e99a8),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        _avatarInitial(label),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.34,
        ),
      ),
    );
    if (url.isEmpty) {
      return fallback;
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius)),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        errorWidget: (_, __, ___) => fallback,
        placeholder: (_, _) => fallback,
      ),
    );
  }
}

class _MomentVideoFramePreview extends StatefulWidget {
  const _MomentVideoFramePreview({
    required this.fallback,
    this.videoUrl = '',
    this.coverUrl = '',
    this.filePath = '',
  });

  final String videoUrl;
  final String coverUrl;
  final String filePath;
  final Widget fallback;

  @override
  State<_MomentVideoFramePreview> createState() =>
      _MomentVideoFramePreviewState();
}

class _MomentVideoFramePreviewState extends State<_MomentVideoFramePreview> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadFirstFrame();
  }

  @override
  void didUpdateWidget(covariant _MomentVideoFramePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.coverUrl != widget.coverUrl ||
        oldWidget.filePath != widget.filePath) {
      _controller?.dispose();
      _controller = null;
      _failed = false;
      _loadFirstFrame();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadFirstFrame() async {
    if (widget.coverUrl.isNotEmpty ||
        (widget.videoUrl.isEmpty && widget.filePath.isEmpty)) {
      return;
    }
    final expectedUrl = widget.videoUrl;
    final expectedFile = widget.filePath;
    try {
      final options = VideoPlayerOptions(mixWithOthers: true);
      final controller = expectedFile.isNotEmpty
          ? VideoPlayerController.file(
              File(expectedFile),
              videoPlayerOptions: options,
            )
          : VideoPlayerController.networkUrl(
              Uri.parse(expectedUrl),
              videoPlayerOptions: options,
            );
      await controller.initialize();
      await controller.seekTo(Duration.zero);
      await controller.pause();
      if (!mounted ||
          expectedUrl != widget.videoUrl ||
          expectedFile != widget.filePath) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'moments',
        'load video first frame failed',
        data: {
          'video_url': expectedUrl,
          'file_path': expectedFile,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.coverUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.coverUrl,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        errorWidget: (_, __, ___) => _firstFrameOrFallback(),
        placeholder: (_, _) => widget.fallback,
      );
    }
    return _firstFrameOrFallback();
  }

  Widget _firstFrameOrFallback() {
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return widget.fallback;
    }
    final size = controller.value.size;
    final width = size.width > 0 ? size.width : 16.0;
    final height = size.height > 0 ? size.height : 9.0;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: width,
        height: height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

double _momentAvatarRadius(double size) {
  return (size * 0.18).clamp(BimRadius.sm, BimRadius.md).toDouble();
}

class _MomentLoadingState extends StatelessWidget {
  const _MomentLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _MomentErrorState extends StatelessWidget {
  const _MomentErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return BimEmptyState(
      title: '加载失败',
      message: error,
      icon: Icons.refresh,
      actionLabel: '重试',
      onAction: onRetry,
    );
  }
}

class _MomentEmptyState extends StatelessWidget {
  const _MomentEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '暂无朋友圈动态',
        style: TextStyle(color: _momentsSecondary, fontSize: 14),
      ),
    );
  }
}

class _MomentLocalMedia {
  const _MomentLocalMedia({
    required this.filePath,
    required this.mediaType,
    required this.name,
    required this.mime,
    required this.size,
    required this.width,
    required this.height,
    required this.duration,
  });

  final String filePath;
  final String mediaType;
  final String name;
  final String mime;
  final int size;
  final int width;
  final int height;
  final int duration;
}

class _MomentVideoViewer extends StatefulWidget {
  const _MomentVideoViewer({required this.url});

  final String url;

  @override
  State<_MomentVideoViewer> createState() => _MomentVideoViewerState();
}

class _MomentVideoViewerState extends State<_MomentVideoViewer> {
  VideoPlayerController? _controller;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.initialize();
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error, stackTrace) {
      AppLogger.error(
        'moments',
        'video viewer init failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = '视频播放失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: _error.isNotEmpty
              ? Text(_error, style: const TextStyle(color: Colors.white70))
              : controller == null
              ? const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final ratio = controller.value.aspectRatio
                        .clamp(0.56, 16 / 9)
                        .toDouble();
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                        maxHeight: constraints.maxHeight,
                      ),
                      child: AspectRatio(
                        aspectRatio: ratio,
                        child: VideoPlayer(controller),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: controller == null
          ? null
          : FloatingActionButton(
              elevation: 0,
              backgroundColor: const Color(0x66000000),
              onPressed: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
              child: Icon(
                controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
            ),
    );
  }
}

Future<String?> _openMomentCommentSheet(
  BuildContext context, {
  String replyName = '',
}) {
  final controller = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _momentsSurface,
    builder: (context) {
      final bottom = MediaQuery.viewInsetsOf(context).bottom;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: replyName.isEmpty ? '评论' : '回复 $replyName',
                      filled: true,
                      fillColor: _momentsFill,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 42,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(controller.text),
                    child: const Text('发送'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

Future<bool> _confirmMomentAction(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result == true;
}

void _openMomentMediaViewer(BuildContext context, Map<String, Object?> media) {
  final url = _momentMediaSourceUrl(media);
  if (url.isEmpty) {
    return;
  }
  if (_isMomentVideo(media)) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _MomentVideoViewer(url: url)),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _MomentMediaViewerScaffold(url: url),
    ),
  );
}

void _showMomentMessage(
  BuildContext context,
  String text, {
  bool error = false,
}) {
  showBimSnackBar(
    context,
    text,
    tone: error ? BimNoticeTone.error : BimNoticeTone.success,
  );
}

List<Map<String, Object?>> _listFromPayload(Map<String, Object?> data) {
  return _listFromValue(
    data['list'] ?? data['items'] ?? data['rows'] ?? data['records'],
  );
}

List<Map<String, Object?>> _listFromValue(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    value = decoded;
  }
  if (value is! List) {
    return const [];
  }
  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

Map<String, Object?> _mapValue(
  Map<String, Object?> source,
  List<String> keys, {
  Map<String, Object?> fallback = const {},
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
  }
  return fallback;
}

String _textValue(Map<String, Object?> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key]?.toString() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _momentProfileBackground(Map<String, Object?> source) {
  final direct = _textValue(source, const [
    'profile_background',
    'profile_background_url',
    'moments_background',
    'moments_cover',
    'cover_url',
    'background_url',
    'user_bg',
    'userbg',
  ]);
  if (direct.isNotEmpty) {
    return direct;
  }
  for (final key in const ['profile', 'user', 'me', 'member', 'owner']) {
    final nested = _mapValue(source, [key]);
    if (nested.isEmpty) {
      continue;
    }
    final value = _momentProfileBackground(nested);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _uploadedProfileBackground(Map<String, Object?> source) {
  final direct = _textValue(source, const [
    'url',
    'userbg',
    'profile_background',
    'profile_background_url',
    'moments_background',
    'moments_cover',
    'cover_url',
    'background_url',
  ]);
  if (direct.isNotEmpty) {
    return direct;
  }
  for (final key in const ['data', 'user', 'profile']) {
    final nested = _mapValue(source, [key]);
    if (nested.isEmpty) {
      continue;
    }
    final value = _uploadedProfileBackground(nested);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

int _intValue(
  Map<String, Object?> source,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is int) {
      return value;
    }
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return fallback;
}

double _doubleValue(
  Map<String, Object?> source,
  List<String> keys, {
  double fallback = 0,
}) {
  for (final key in keys) {
    final value = source[key];
    if (value is num) {
      return value.toDouble();
    }
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return fallback;
}

bool _boolValue(Map<String, Object?> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is bool) {
      return value;
    }
    final text = value?.toString().toLowerCase() ?? '';
    if (text == '1' || text == 'true' || text == 'yes') {
      return true;
    }
    if (text == '0' || text == 'false' || text == 'no') {
      return false;
    }
  }
  return false;
}

String _displayName(Map<String, Object?> user) {
  return _textValue(user, ['nickname', 'username', 'name']);
}

String _sessionName(String nickname, String username) {
  return nickname.trim().isNotEmpty ? nickname.trim() : username.trim();
}

String _avatarInitial(String label) {
  final text = label.trim();
  if (text.isEmpty) {
    return 'B';
  }
  return text.characters.first.toUpperCase();
}

String _avatarUrl(String value) {
  return _absoluteUrl(value);
}

String _mediaUrl(String value) {
  return _absoluteUrl(value);
}

String _momentMediaSourceUrl(Map<String, Object?> media) {
  return _mediaUrl(
    _textValue(media, [
      'url',
      'image_url',
      'video_url',
      'file_url',
      'media_url',
      'path',
      'src',
    ]),
  );
}

String _momentMediaCoverUrl(Map<String, Object?> media) {
  return _mediaUrl(
    _textValue(media, [
      'thumb_url',
      'cover_url',
      'thumbnail_url',
      'poster_url',
      'preview_url',
    ]),
  );
}

String _absoluteUrl(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '';
  }
  if (text.startsWith('http://') || text.startsWith('https://')) {
    return text;
  }
  if (text.startsWith('//')) {
    return 'https:$text';
  }
  final base = Uri.parse(AppConfig.apiBaseUrl);
  final origin =
      '${base.scheme}://${base.host}${base.hasPort ? ':${base.port}' : ''}';
  if (text.startsWith('/')) {
    return '$origin$text';
  }
  return '$origin/$text';
}

String _momentTime(String value) {
  final time = DateTime.tryParse(value.replaceFirst(' ', 'T'));
  if (time == null) {
    return value;
  }
  final now = DateTime.now();
  final local = time.toLocal();
  final sameDay =
      now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  if (sameDay) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  final yesterday = now.subtract(const Duration(days: 1));
  if (yesterday.year == local.year &&
      yesterday.month == local.month &&
      yesterday.day == local.day) {
    return '昨天';
  }
  if (now.year == local.year) {
    return '${local.month}月${local.day}日';
  }
  return '${local.year}年${local.month}月${local.day}日';
}

String _fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  return index >= 0 ? normalized.substring(index + 1) : normalized;
}
