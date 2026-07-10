part of 'package:bim/src/features/home/home_page.dart';

class _MediaAlbumStrip extends StatelessWidget {
  const _MediaAlbumStrip({
    required this.albums,
    required this.selected,
    required this.loading,
    required this.onChanged,
  });

  final List<AssetPathEntity> albums;
  final AssetPathEntity? selected;
  final bool loading;
  final ValueChanged<AssetPathEntity> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: albums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final album = albums[index];
                final current = selected?.id == album.id;
                return Center(
                  child: _PickerFilterButton(
                    label: album.isAll ? '最近' : album.name,
                    selected: current,
                    onTap: loading || current ? null : () => onChanged(album),
                  ),
                );
              },
            ),
          ),
          if (loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _MediaAssetTile extends StatelessWidget {
  const _MediaAssetTile({
    required this.asset,
    required this.selected,
    required this.selectionIndex,
    required this.sending,
    required this.onTap,
    required this.onLongPress,
  });

  final AssetEntity asset;
  final bool selected;
  final int selectionIndex;
  final bool sending;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;
    return Semantics(
      button: true,
      selected: selected,
      label: isVideo ? '视频 ${_secondsLabel(asset.duration)}' : '图片',
      child: Material(
        color: BimColors.mediaPlaceholder,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List?>(
                future: asset.thumbnailDataWithSize(
                  const ThumbnailSize.square(260),
                  quality: 84,
                ),
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  if (snapshot.hasError || bytes == null || bytes.isEmpty) {
                    return _MediaAssetPlaceholder(isVideo: isVideo);
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        _MediaAssetPlaceholder(isVideo: isVideo),
                  );
                },
              ),
              if (isVideo)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _VideoDurationBadge(seconds: asset.duration),
                ),
              if (selected || sending)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: sending
                          ? BimColors.scrim
                          : const Color(0x33000000),
                    ),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: _SelectionMark(
                  selected: selected,
                  busy: sending,
                  label: selectionIndex > 0 ? selectionIndex.toString() : '',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaAssetPreviewPage extends StatefulWidget {
  const _MediaAssetPreviewPage({
    required this.assets,
    required this.initialIndex,
  });

  final List<AssetEntity> assets;
  final int initialIndex;

  @override
  State<_MediaAssetPreviewPage> createState() => _MediaAssetPreviewPageState();
}

class _MediaAssetPreviewPageState extends State<_MediaAssetPreviewPage> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.assets.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.assets[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.assets.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final asset = widget.assets[index];
                  if (asset.type == AssetType.video) {
                    return _AssetVideoPreview(asset: asset);
                  }
                  return _AssetImagePreview(asset: asset);
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _PreviewTopBar(
                title: '${_index + 1}/${widget.assets.length}',
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PreviewBottomBar(
                asset: current,
                onSelect: () => Navigator.of(context).pop(current),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssetImagePreview extends StatelessWidget {
  const _AssetImagePreview({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(
        const ThumbnailSize.square(1440),
        quality: 94,
      ),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (snapshot.hasError) {
          return const _FullScreenMediaError(text: '图片无法预览');
        }
        if (bytes == null || bytes.isEmpty) {
          if (snapshot.connectionState == ConnectionState.done) {
            return const _FullScreenMediaError(text: '图片无法预览');
          }
          return const _FullScreenMediaLoading();
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const _FullScreenMediaError(text: '图片无法预览'),
            ),
          ),
        );
      },
    );
  }
}

class _AssetVideoPreview extends StatefulWidget {
  const _AssetVideoPreview({required this.asset});

  final AssetEntity asset;

  @override
  State<_AssetVideoPreview> createState() => _AssetVideoPreviewState();
}

class _AssetVideoPreviewState extends State<_AssetVideoPreview> {
  VideoPlayerController? _controller;
  Future<void>? _future;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant _AssetVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) {
      _controller?.removeListener(_onVideoChanged);
      _controller?.dispose();
      _controller = null;
      _error = '';
      _future = _load();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onVideoChanged);
    _controller?.dispose();
    super.dispose();
  }

  void _onVideoChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _load() async {
    try {
      final file = await widget.asset.originFile ?? await widget.asset.file;
      if (file == null || file.path.isEmpty) {
        throw const FileSystemException('video file is unavailable');
      }
      final controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;
      controller.addListener(_onVideoChanged);
      await controller.initialize();
      await controller.pause();
    } catch (error, stackTrace) {
      _error = '视频无法预览';
      AppLogger.warn(
        'chat',
        'preview picked video failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        final controller = _controller;
        if (snapshot.connectionState != ConnectionState.done) {
          return const _FullScreenMediaLoading();
        }
        if (_error.isNotEmpty ||
            controller == null ||
            !controller.value.isInitialized) {
          return _FullScreenMediaError(
            text: _error.isEmpty ? '视频无法预览' : _error,
          );
        }
        final size = controller.value.size;
        return GestureDetector(
          onTap: _toggle,
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
              if (!controller.value.isPlaying) const _VideoPlayBadge(size: 64),
              Positioned(
                left: 16,
                right: 16,
                bottom: 88,
                child: _PreviewVideoProgress(controller: controller),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewVideoProgress extends StatelessWidget {
  const _PreviewVideoProgress({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final duration = max(1, value.duration.inSeconds);
    final current = value.position.inSeconds.clamp(0, duration);
    return Row(
      children: [
        Text(
          _secondsLabel(current),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Slider(
            value: current.toDouble(),
            min: 0,
            max: duration.toDouble(),
            activeColor: Colors.white,
            inactiveColor: const Color(0x55ffffff),
            onChanged: (value) =>
                controller.seekTo(Duration(seconds: value.round())),
          ),
        ),
        Text(
          _secondsLabel(duration),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
