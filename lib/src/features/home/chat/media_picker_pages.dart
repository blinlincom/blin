part of 'package:bim/src/features/home/home_page.dart';

const _mediaMaxImageSelection = 20;

class _InAppMediaPickerPage extends StatefulWidget {
  const _InAppMediaPickerPage({required this.contentType});

  final String contentType;

  @override
  State<_InAppMediaPickerPage> createState() => _InAppMediaPickerPageState();
}

class _InAppMediaPickerPageState extends State<_InAppMediaPickerPage> {
  static const _pageSize = 120;
  static const _maxImageSelection = _mediaMaxImageSelection;

  final ScrollController _gridController = ScrollController();
  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _selectedAssets = const [];
  bool _loading = true;
  bool _loadingAssets = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String _error = '';
  String _selectingAssetId = '';

  bool get _videoOnly => widget.contentType == ChatContentTypes.video;
  AssetEntity? get _selectedAsset =>
      _selectedAssets.isEmpty ? null : _selectedAssets.last;
  int get _selectedCount => _selectedAssets.length;
  int get _maxSelection => _selectedMaxSelectionForAssets(_selectedAssets);

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
      _selectedAssets = const [];
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = '需要授权访问相册后才能选择图片或视频';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: _mediaRequestType,
        filterOption: _mediaFilterOption,
        hasAll: true,
      );
      if (!mounted) {
        return;
      }
      if (albums.isEmpty) {
        AppLogger.warn(
          'chat',
          'media picker albums empty',
          data: {'content_type': widget.contentType},
        );
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
        _selectedAssets = const [];
      });
    }
    try {
      final assets = await album.getAssetListPaged(page: 0, size: _pageSize);
      assets.sort(_mediaAssetRecentCompare);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAlbum = album;
        _assets = assets;
        _selectedAssets = const [];
        _page = 0;
        _hasMore = assets.length >= _pageSize;
        _loading = false;
        _loadingAssets = false;
        _loadingMore = false;
      });
      AppLogger.info(
        'chat',
        'media picker assets loaded',
        data: {
          'content_type': widget.contentType,
          'album_id': album.id,
          'album_name': album.name,
          'asset_count': assets.length,
          'has_more': _hasMore,
        },
      );
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
      assets.sort(_mediaAssetRecentCompare);
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
      setState(() => _addSelectedAsset(selected));
    }
  }

  Future<void> _sendSelectedAsset() async {
    final selected = List<AssetEntity>.from(_selectedAssets);
    if (selected.isEmpty || _selectingAssetId.isNotEmpty) {
      return;
    }
    setState(
      () => _selectingAssetId = selected.length == 1
          ? selected.first.id
          : 'batch',
    );
    try {
      final payloads = <Map<String, String>>[];
      for (final asset in selected) {
        payloads.add(_mediaAssetSelectionPayload(asset));
      }
      if (!mounted) {
        return;
      }
      AppLogger.info(
        'chat',
        'media assets selected for send',
        data: {
          'content_type': widget.contentType,
          'media_mode': _mediaModeLogName,
          'count': payloads.length,
          'asset_ids': selected.map((item) => item.id).take(30).toList(),
        },
      );
      Navigator.of(context).pop(
        payloads.length == 1
            ? payloads.first
            : <String, String>{'batch_json': jsonEncode(payloads)},
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'select media asset failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'content_type': widget.contentType,
          'asset_ids': selected.map((item) => item.id).take(30).toList(),
        },
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
    final current = _selectedAssets.indexWhere((item) => item.id == asset.id);
    if (current >= 0) {
      setState(() {
        final next = List<AssetEntity>.from(_selectedAssets)..removeAt(current);
        _selectedAssets = next;
      });
      return;
    }
    if (_assetIsVideo(asset)) {
      setState(() => _selectedAssets = [asset]);
      return;
    }
    if (_selectedAssets.any(_assetIsVideo)) {
      setState(() => _selectedAssets = [asset]);
      return;
    }
    if (_selectedAssets.length >= _maxImageSelection) {
      _showChatSnack(context, '一次最多选择 $_maxImageSelection 张图片', error: true);
      return;
    }
    setState(() => _selectedAssets = [..._selectedAssets, asset]);
  }

  void _addSelectedAsset(AssetEntity asset) {
    final existing = _selectedAssets.indexWhere((item) => item.id == asset.id);
    if (existing >= 0) {
      return;
    }
    if (_assetIsVideo(asset)) {
      _selectedAssets = [asset];
      return;
    }
    if (_selectedAssets.any(_assetIsVideo)) {
      _selectedAssets = [asset];
      return;
    }
    if (_selectedAssets.length >= _maxImageSelection) {
      _showChatSnack(context, '一次最多选择 $_maxImageSelection 张图片', error: true);
      return;
    }
    _selectedAssets = [..._selectedAssets, asset];
  }

  void _clearSelection() {
    if (_selectingAssetId.isNotEmpty || _selectedAssets.isEmpty) {
      return;
    }
    setState(() => _selectedAssets = const []);
  }

  int _selectionIndex(AssetEntity asset) {
    final index = _selectedAssets.indexWhere((item) => item.id == asset.id);
    return index < 0 ? 0 : index + 1;
  }

  @override
  Widget build(BuildContext context) {
    final title = _videoOnly ? '选择视频' : '最近项目';
    return BimScaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: BimColors.background,
      topBar: _PickerAppBar(title: title),
      body: Column(
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
            selectedCount: _selectedCount,
            maxSelection: _maxSelection,
            videoSelected: _selectedAssets.any(_assetIsVideo),
            sending: _selectingAssetId.isNotEmpty,
            onClear: _selectedCount == 0 ? null : _clearSelection,
            onPreview: _selectedAsset == null ? null : _openPreview,
            onSend: _selectedCount == 0 ? null : _sendSelectedAsset,
          ),
        ],
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
      return _EmptyState(text: _videoOnly ? '暂无可发送视频' : '暂无可发送图片或视频');
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
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
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
                    final selectionIndex = _selectionIndex(asset);
                    return _MediaAssetTile(
                      asset: asset,
                      selected: selectionIndex > 0,
                      selectionIndex: selectionIndex,
                      sending:
                          _selectingAssetId == asset.id ||
                          (_selectingAssetId == 'batch' && selectionIndex > 0),
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

  RequestType get _mediaRequestType =>
      _videoOnly ? RequestType.video : RequestType.common;

  FilterOptionGroup get _mediaFilterOption => FilterOptionGroup(
    orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
  );

  String get _mediaModeLogName => _videoOnly ? 'video' : 'recent_common';
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
      AppLogger.info(
        'chat',
        'in-app files loaded',
        data: {'directory_count': dirs.length, 'file_count': files.length},
      );
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
    final selected = _selectedFile?.path == file.path;
    setState(() => _selectedFile = selected ? null : file);
  }

  void _clearSelectedFile() {
    if (_selectingPath.isNotEmpty || _selectedFile == null) {
      return;
    }
    setState(() => _selectedFile = null);
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
    return BimScaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: BimColors.background,
      topBar: _PickerAppBar(
        title: '选择文件',
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _loadFiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
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
            onClear: _selectedFile == null ? null : _clearSelectedFile,
            onSend: _selectedFile == null ? null : _sendSelectedFile,
          ),
        ],
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
              padding: const EdgeInsets.only(bottom: 12),
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
