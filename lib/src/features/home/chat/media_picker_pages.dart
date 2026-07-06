part of 'package:bim/src/features/home/home_page.dart';

class _InAppMediaPickerPage extends StatefulWidget {
  const _InAppMediaPickerPage({required this.contentType});

  final String contentType;

  @override
  State<_InAppMediaPickerPage> createState() => _InAppMediaPickerPageState();
}

class _InAppMediaPickerPageState extends State<_InAppMediaPickerPage> {
  static const _pageSize = 120;

  final ScrollController _gridController = ScrollController();
  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  AssetPathEntity? _selectedAlbum;
  AssetEntity? _selectedAsset;
  bool _loading = true;
  bool _loadingAssets = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String _error = '';
  String _selectingAssetId = '';

  bool get _isVideo => widget.contentType == ChatContentTypes.video;

  @override
  void initState() {
    super.initState();
    _gridController.addListener(_onGridScroll);
    unawaited(_loadAlbums());
  }

  @override
  void dispose() {
    _gridController
      ..removeListener(_onGridScroll)
      ..dispose();
    super.dispose();
  }

  void _onGridScroll() {
    if (!_hasMore ||
        _loading ||
        _loadingAssets ||
        _loadingMore ||
        _selectedAlbum == null) {
      return;
    }
    if (_gridController.position.extentAfter < 520) {
      unawaited(_loadMoreAssets());
    }
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _loading = true;
      _error = '';
      _selectedAsset = null;
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = '需要授权访问相册后才能选择${_isVideo ? '视频' : '图片'}';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: _isVideo ? RequestType.video : RequestType.image,
        hasAll: true,
      );
      if (!mounted) {
        return;
      }
      if (albums.isEmpty) {
        setState(() {
          _loading = false;
          _albums = const [];
          _assets = const [];
          _selectedAlbum = null;
          _error = '';
        });
        return;
      }
      final selected = albums.firstWhere(
        (item) => item.isAll,
        orElse: () => albums.first,
      );
      setState(() {
        _albums = albums;
        _selectedAlbum = selected;
      });
      await _loadAssets(selected, showPageLoading: false);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load media picker failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '相册读取失败';
      });
    }
  }

  Future<void> _loadAssets(
    AssetPathEntity album, {
    bool showPageLoading = true,
  }) async {
    if (showPageLoading) {
      setState(() {
        _loadingAssets = true;
        _error = '';
        _selectedAsset = null;
      });
    }
    try {
      final assets = await album.getAssetListPaged(page: 0, size: _pageSize);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAlbum = album;
        _assets = assets;
        _selectedAsset = null;
        _page = 0;
        _hasMore = assets.length >= _pageSize;
        _loading = false;
        _loadingAssets = false;
        _loadingMore = false;
      });
      if (_gridController.hasClients) {
        _gridController.jumpTo(0);
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load media assets failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadingAssets = false;
        _loadingMore = false;
        _error = '媒体列表读取失败';
      });
    }
  }

  Future<void> _loadMoreAssets() async {
    final album = _selectedAlbum;
    if (album == null) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final assets = await album.getAssetListPaged(
        page: nextPage,
        size: _pageSize,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _assets = [..._assets, ...assets];
        _page = nextPage;
        _hasMore = assets.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'chat',
        'load more media assets failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _openPreview([AssetEntity? seed]) async {
    final asset = seed ?? _selectedAsset;
    if (asset == null || _assets.isEmpty) {
      return;
    }
    final index = max(0, _assets.indexWhere((item) => item.id == asset.id));
    final selected = await Navigator.of(context).push<AssetEntity>(
      MaterialPageRoute(
        builder: (_) =>
            _MediaAssetPreviewPage(assets: _assets, initialIndex: index),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedAsset = selected);
    }
  }

  Future<void> _sendSelectedAsset() async {
    final asset = _selectedAsset;
    if (asset == null || _selectingAssetId.isNotEmpty) {
      return;
    }
    setState(() => _selectingAssetId = asset.id);
    try {
      final payload = await _mediaAssetPayload(asset, widget.contentType);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(payload);
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'select media asset failed',
        error: error,
        stackTrace: stackTrace,
        data: {'asset_id': asset.id},
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectingAssetId = '');
      _showChatSnack(context, '文件读取失败', error: true);
    }
  }

  void _toggleAsset(AssetEntity asset) {
    if (_selectingAssetId.isNotEmpty) {
      return;
    }
    final selected = _selectedAsset?.id == asset.id;
    if (selected) {
      unawaited(_openPreview(asset));
      return;
    }
    setState(() => _selectedAsset = asset);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isVideo ? '选择视频' : '选择图片';
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _pageColor,
      appBar: _PickerAppBar(title: title),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            if (!_loading && _error.isEmpty && _albums.isNotEmpty)
              _MediaAlbumStrip(
                albums: _albums,
                selected: _selectedAlbum,
                loading: _loadingAssets,
                onChanged: (album) => _loadAssets(album),
              ),
            Expanded(child: _buildBody()),
            _MediaPickerFooter(
              selected: _selectedAsset,
              sending: _selectingAssetId.isNotEmpty,
              onPreview: _selectedAsset == null ? null : _openPreview,
              onSend: _selectedAsset == null ? null : _sendSelectedAsset,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _MediaGridSkeleton();
    }
    if (_error.isNotEmpty) {
      return _ErrorState(
        text: _error,
        onRetry: _error.contains('授权')
            ? () async {
                await PhotoManager.openSetting();
                if (mounted) {
                  await _loadAlbums();
                }
              }
            : _loadAlbums,
      );
    }
    if (_assets.isEmpty && !_loadingAssets) {
      return _EmptyState(text: _isVideo ? '暂无可发送视频' : '暂无可发送图片');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _mediaGridColumns(context, constraints.maxWidth);
        final contentWidth = min(constraints.maxWidth, 980.0);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: contentWidth,
            child: Stack(
              children: [
                GridView.builder(
                  controller: _gridController,
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 86),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                  ),
                  itemCount: _assets.length + (_loadingMore ? columns : 0),
                  itemBuilder: (context, index) {
                    if (index >= _assets.length) {
                      return const _MediaSkeletonTile();
                    }
                    final asset = _assets[index];
                    return _MediaAssetTile(
                      asset: asset,
                      selected: _selectedAsset?.id == asset.id,
                      sending: _selectingAssetId == asset.id,
                      onTap: () => _toggleAsset(asset),
                      onLongPress: () => _openPreview(asset),
                    );
                  },
                ),
                if (_loadingAssets)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InAppFilePickerPage extends StatefulWidget {
  const _InAppFilePickerPage();

  @override
  State<_InAppFilePickerPage> createState() => _InAppFilePickerPageState();
}

class _InAppFilePickerPageState extends State<_InAppFilePickerPage> {
  static const _maxFiles = 300;

  final TextEditingController _searchController = TextEditingController();
  List<_LocalFileItem> _files = const [];
  _FileTypeFilter _filter = _FileTypeFilter.all;
  _LocalFileItem? _selectedFile;
  bool _loading = true;
  String _error = '';
  String _selectingPath = '';

  List<_LocalFileItem> get _visibleFiles {
    return _files.where(_fileVisible).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadFiles());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = '';
      _selectedFile = null;
      _selectingPath = '';
    });
    try {
      final dirs = await _candidateFileDirectories();
      final files = <_LocalFileItem>[];
      final seen = <String>{};
      for (final dir in dirs) {
        if (files.length >= _maxFiles) {
          break;
        }
        await _scanDirectory(dir, files, seen, depth: 2);
      }
      files.sort((a, b) => b.modified.compareTo(a.modified));
      if (!mounted) {
        return;
      }
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'load in-app files failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '文件列表读取失败';
      });
    }
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<_LocalFileItem> files,
    Set<String> seen, {
    required int depth,
  }) async {
    if (files.length >= _maxFiles || !await dir.exists()) {
      return;
    }
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (files.length >= _maxFiles) {
          return;
        }
        final name = _fileName(entity.path);
        if (name.startsWith('.')) {
          continue;
        }
        if (entity is File) {
          if (!seen.add(entity.path)) {
            continue;
          }
          final stat = await entity.stat();
          if (stat.size <= 0) {
            continue;
          }
          files.add(
            _LocalFileItem(
              path: entity.path,
              name: name,
              size: stat.size,
              modified: stat.modified.millisecondsSinceEpoch,
            ),
          );
        } else if (entity is Directory && depth > 0) {
          await _scanDirectory(entity, files, seen, depth: depth - 1);
        }
      }
    } on FileSystemException {
      return;
    }
  }

  Future<void> _sendSelectedFile() async {
    final file = _selectedFile;
    if (file == null || _selectingPath.isNotEmpty) {
      return;
    }
    setState(() => _selectingPath = file.path);
    try {
      final current = File(file.path);
      final stat = await current.stat();
      if (stat.size <= 0) {
        throw const FileSystemException('file is empty');
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(<String, String>{
        'file_path': file.path,
        'name': file.name,
        'size': stat.size.toString(),
        'mime': _mimeFromPath(file.path, ChatContentTypes.file),
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'select in-app file failed',
        error: error,
        stackTrace: stackTrace,
        data: {'path': file.path},
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectingPath = '');
      _showChatSnack(context, '文件读取失败', error: true);
    }
  }

  void _selectFile(_LocalFileItem file) {
    if (_selectingPath.isNotEmpty) {
      return;
    }
    setState(() => _selectedFile = file);
  }

  void _onSearchChanged(String value) {
    setState(_clearInvisibleSelection);
  }

  void _changeFilter(_FileTypeFilter value) {
    setState(() {
      _filter = value;
      _clearInvisibleSelection();
    });
  }

  void _clearInvisibleSelection() {
    final selected = _selectedFile;
    if (selected != null && !_fileVisible(selected)) {
      _selectedFile = null;
    }
  }

  bool _fileVisible(_LocalFileItem file) {
    if (!_filter.matches(file)) {
      return false;
    }
    final keyword = _searchController.text.trim().toLowerCase();
    if (keyword.isEmpty) {
      return true;
    }
    return file.name.toLowerCase().contains(keyword) ||
        file.path.toLowerCase().contains(keyword);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _pageColor,
      appBar: _PickerAppBar(
        title: '选择文件',
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _loadFiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _FilePickerToolbar(
              controller: _searchController,
              filter: _filter,
              onSearchChanged: _onSearchChanged,
              onFilterChanged: _changeFilter,
            ),
            Expanded(child: _buildBody()),
            _FilePickerFooter(
              selected: _selectedFile,
              sending: _selectingPath.isNotEmpty,
              onSend: _selectedFile == null ? null : _sendSelectedFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _FileListSkeleton();
    }
    if (_error.isNotEmpty) {
      return _ErrorState(text: _error, onRetry: _loadFiles);
    }
    if (_files.isEmpty) {
      return const _EmptyState(text: '暂无可发送文件');
    }
    final files = _visibleFiles;
    if (files.isEmpty) {
      return const _EmptyState(text: '没有匹配的文件');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(constraints.maxWidth, 860.0);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: ListView.separated(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: 86),
              itemCount: files.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _lightBorderColor),
              itemBuilder: (context, index) {
                final file = files[index];
                return _FilePickerTile(
                  file: file,
                  selected: _selectedFile?.path == file.path,
                  sending: _selectingPath == file.path,
                  onTap: () => _selectFile(file),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

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
                    label: album.isAll ? '全部' : album.name,
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
    required this.sending,
    required this.onTap,
    required this.onLongPress,
  });

  final AssetEntity asset;
  final bool selected;
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
        color: const Color(0xffe8eaed),
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
                  if (bytes == null) {
                    return _MediaAssetPlaceholder(isVideo: isVideo);
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
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
                          ? const Color(0x66000000)
                          : const Color(0x33000000),
                    ),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: _SelectionMark(selected: selected, busy: sending),
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
        if (bytes == null) {
          return const _FullScreenMediaLoading();
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
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

class _FilePickerToolbar extends StatelessWidget {
  const _FilePickerToolbar({
    required this.controller,
    required this.filter,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _FileTypeFilter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<_FileTypeFilter> onFilterChanged;

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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: '搜索文件名',
                hintStyle: const TextStyle(color: _mutedColor, fontSize: 14),
                prefixIcon: const Icon(
                  Icons.search,
                  color: _secondaryTextColor,
                  size: 20,
                ),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空',
                        onPressed: () {
                          controller.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
                filled: true,
                fillColor: _fillColor,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 42,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              scrollDirection: Axis.horizontal,
              itemCount: _FileTypeFilter.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _FileTypeFilter.values[index];
                return Center(
                  child: _PickerFilterButton(
                    label: item.label,
                    selected: filter == item,
                    onTap: filter == item ? null : () => onFilterChanged(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePickerTile extends StatelessWidget {
  const _FilePickerTile({
    required this.file,
    required this.selected,
    required this.sending,
    required this.onTap,
  });

  final _LocalFileItem file;
  final bool selected;
  final bool sending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = _compactFilePath(file.path);
    return Semantics(
      button: true,
      selected: selected,
      label: file.name,
      child: Material(
        color: selected ? const Color(0xffedf5ff) : _surfaceColor,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xffeef4ff),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      _fileIcon(file.name),
                      color: _primaryColor,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_fileSizeLabel(file.size)} · ${_formatTime(file.modified)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      if (path.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _mutedColor,
                            fontSize: 11,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _SelectionMark(selected: selected, busy: sending),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaPickerFooter extends StatelessWidget {
  const _MediaPickerFooter({
    required this.selected,
    required this.sending,
    required this.onPreview,
    required this.onSend,
  });

  final AssetEntity? selected;
  final bool sending;
  final VoidCallback? onPreview;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final enabled = selected != null && !sending;
    return _PickerFooterShell(
      leading: Text(
        selected == null ? '未选择' : '已选择 1 项',
        style: const TextStyle(
          color: _secondaryTextColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        TextButton(
          onPressed: enabled ? onPreview : null,
          child: const Text('预览'),
        ),
        FilledButton(
          onPressed: enabled ? onSend : null,
          child: sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发送'),
        ),
      ],
    );
  }
}

class _FilePickerFooter extends StatelessWidget {
  const _FilePickerFooter({
    required this.selected,
    required this.sending,
    required this.onSend,
  });

  final _LocalFileItem? selected;
  final bool sending;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final enabled = selected != null && !sending;
    return _PickerFooterShell(
      leading: Text(
        selected == null
            ? '请选择一个文件'
            : '${selected!.name} · ${_fileSizeLabel(selected!.size)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _secondaryTextColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: enabled ? onSend : null,
          child: sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发送'),
        ),
      ],
    );
  }
}

class _PickerFooterShell extends StatelessWidget {
  const _PickerFooterShell({required this.leading, required this.actions});

  final Widget leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionMaxWidth = min(
          constraints.maxWidth * (compact ? 0.62 : 0.56),
          compact ? 178.0 : 260.0,
        );
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: _surfaceColor,
            border: Border(top: BorderSide(color: _lightBorderColor)),
          ),
          child: SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 58),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 10 : 14,
                  8,
                  compact ? 10 : 14,
                  8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: leading,
                      ),
                    ),
                    SizedBox(width: compact ? 8 : 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: compact ? 84 : 96,
                        maxWidth: actionMaxWidth,
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        physics: const ClampingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (
                              var index = 0;
                              index < actions.length;
                              index++
                            ) ...[
                              if (index > 0) SizedBox(width: compact ? 6 : 8),
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                child: actions[index],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PickerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PickerAppBar({required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(51);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      centerTitle: true,
      toolbarHeight: 50,
      backgroundColor: _surfaceColor,
      foregroundColor: _textColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      actions: actions,
      titleTextStyle: const TextStyle(
        color: _textColor,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: _lightBorderColor),
      ),
    );
  }
}

class _PickerFilterButton extends StatelessWidget {
  const _PickerFilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _textColor : _fillColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32, minWidth: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? Colors.white : _textColor,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected, required this.busy});

  final bool selected;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? _primaryColor : const Color(0x66000000),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.4),
      ),
      child: selected
          ? const Icon(Icons.check, color: Colors.white, size: 16)
          : const SizedBox.shrink(),
    );
  }
}

class _MediaAssetPlaceholder extends StatelessWidget {
  const _MediaAssetPlaceholder({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xffe8eaed),
      child: Center(
        child: Icon(
          isVideo ? Icons.videocam_outlined : Icons.image_outlined,
          color: _mutedColor,
          size: 28,
        ),
      ),
    );
  }
}

class _VideoDurationBadge extends StatelessWidget {
  const _VideoDurationBadge({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x99000000)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(Icons.play_arrow, color: Colors.white, size: 13),
            const SizedBox(width: 2),
            Text(
              _secondsLabel(seconds),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTopBar extends StatelessWidget {
  const _PreviewTopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x66000000)),
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
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 50),
          ],
        ),
      ),
    );
  }
}

class _PreviewBottomBar extends StatelessWidget {
  const _PreviewBottomBar({required this.asset, required this.onSelect});

  final AssetEntity asset;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;
    final label = isVideo ? '选择此视频' : '选择此图片';
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0x99000000)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isVideo ? _secondsLabel(asset.duration) : '图片预览',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton(onPressed: onSelect, child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaGridSkeleton extends StatelessWidget {
  const _MediaGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _mediaGridColumns(context, constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemCount: columns * 5,
          itemBuilder: (_, __) => const _MediaSkeletonTile(),
        );
      },
    );
  }
}

class _MediaSkeletonTile extends StatelessWidget {
  const _MediaSkeletonTile();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Color(0xffe8eaed)),
    );
  }
}

class _FileListSkeleton extends StatelessWidget {
  const _FileListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 86),
      itemCount: 10,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: _lightBorderColor),
      itemBuilder: (_, __) => const _FileSkeletonRow(),
    );
  }
}

class _FileSkeletonRow extends StatelessWidget {
  const _FileSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          const SizedBox(
            width: 42,
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xffe8eaed)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SizedBox(
                  width: double.infinity,
                  height: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xffe8eaed)),
                  ),
                ),
                SizedBox(height: 9),
                SizedBox(
                  width: 180,
                  height: 11,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0xffeef0f3)),
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

class _LocalFileItem {
  const _LocalFileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final int modified;
}

enum _FileTypeFilter {
  all('全部'),
  document('文档'),
  image('图片'),
  video('视频'),
  archive('压缩包'),
  other('其他');

  const _FileTypeFilter(this.label);

  final String label;

  bool matches(_LocalFileItem file) {
    return switch (this) {
      _FileTypeFilter.all => true,
      _FileTypeFilter.document =>
        _fileKind(file.name) == _FileTypeKind.document,
      _FileTypeFilter.image => _fileKind(file.name) == _FileTypeKind.image,
      _FileTypeFilter.video => _fileKind(file.name) == _FileTypeKind.video,
      _FileTypeFilter.archive => _fileKind(file.name) == _FileTypeKind.archive,
      _FileTypeFilter.other => _fileKind(file.name) == _FileTypeKind.other,
    };
  }
}

enum _FileTypeKind { document, image, video, archive, other }

Future<Map<String, String>> _mediaAssetPayload(
  AssetEntity asset,
  String contentType,
) async {
  final file = await asset.originFile ?? await asset.file;
  if (file == null || file.path.isEmpty) {
    throw const FileSystemException('asset file is unavailable');
  }
  final stat = await file.stat();
  if (stat.size <= 0) {
    throw const FileSystemException('asset file is empty');
  }
  final name = await asset.titleAsync;
  return <String, String>{
    'file_path': file.path,
    'name': name.isNotEmpty ? name : _fileName(file.path),
    'size': stat.size.toString(),
    'mime': asset.mimeType ?? _mimeFromPath(file.path, contentType),
    if (asset.width > 0) 'width': asset.width.toString(),
    if (asset.height > 0) 'height': asset.height.toString(),
    if (contentType == ChatContentTypes.video)
      'duration': asset.duration.toString(),
  };
}

int _mediaGridColumns(BuildContext context, double width) {
  final orientation = MediaQuery.orientationOf(context);
  if (width >= 1100) {
    return 9;
  }
  if (width >= 900) {
    return 8;
  }
  if (width >= 700) {
    return 6;
  }
  if (width >= 520 || orientation == Orientation.landscape) {
    return 5;
  }
  return 4;
}

_FileTypeKind _fileKind(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' ||
    'jpeg' ||
    'png' ||
    'gif' ||
    'webp' ||
    'bmp' ||
    'heic' => _FileTypeKind.image,
    'mp4' || 'mov' || 'm4v' || 'webm' || 'avi' || 'mkv' => _FileTypeKind.video,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => _FileTypeKind.archive,
    'pdf' ||
    'txt' ||
    'md' ||
    'doc' ||
    'docx' ||
    'xls' ||
    'xlsx' ||
    'ppt' ||
    'pptx' => _FileTypeKind.document,
    _ => _FileTypeKind.other,
  };
}

String _compactFilePath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((item) => item.isNotEmpty).toList();
  if (parts.length <= 2) {
    return '';
  }
  final parent = parts[parts.length - 2];
  if (parent.isEmpty) {
    return '';
  }
  return parent;
}
