part of 'package:bim/src/features/home/home_page.dart';

class _QrAlbumPickerPageState extends State<_QrAlbumPickerPage>
    with WidgetsBindingObserver {
  static const _pageSize = 120;

  final ScrollController _gridController = ScrollController();
  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  AssetPathEntity? _selectedAlbum;
  bool _loading = true;
  bool _loadingAssets = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 0;
  String _error = '';
  String _selectingAssetId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gridController.addListener(_onGridScroll);
    unawaited(_loadAlbums());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gridController
      ..removeListener(_onGridScroll)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final album = _selectedAlbum;
    if (album == null) {
      unawaited(_loadAlbums());
    } else {
      unawaited(_loadAssets(album, showPageLoading: false));
    }
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
    });
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) {
          return;
        }
        setState(() {
          _loading = false;
          _error = '需要允许访问相册';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: _qrAlbumFilterOption,
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
        'ui',
        'load qr album failed',
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
        'ui',
        'load qr album assets failed',
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
        _error = '图片读取失败';
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
        'ui',
        'load more qr album assets failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _selectAsset(AssetEntity asset) async {
    if (_selectingAssetId.isNotEmpty) {
      return;
    }
    setState(() => _selectingAssetId = asset.id);
    try {
      final file = await asset.originFile ?? await asset.file;
      if (file == null || file.path.isEmpty) {
        throw const FileSystemException('asset file is unavailable');
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(file.path);
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'select qr album image failed',
        error: error,
        stackTrace: stackTrace,
        data: {'asset_id': asset.id},
      );
      if (!mounted) {
        return;
      }
      setState(() => _selectingAssetId = '');
      _showChatSnack(context, '图片读取失败', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: const _PickerAppBar(title: '选择图片'),
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
        onRetry: _error.contains('相册')
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
      return const _EmptyState(text: '暂无图片');
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
                    return _QrAlbumImageTile(
                      asset: asset,
                      busy: _selectingAssetId == asset.id,
                      onTap: () => _selectAsset(asset),
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

class _QrAlbumImageTile extends StatelessWidget {
  const _QrAlbumImageTile({
    required this.asset,
    required this.busy,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '选择图片',
      child: Material(
        color: BimColors.mediaPlaceholder,
        child: InkWell(
          onTap: busy ? null : onTap,
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
                    return const _MediaAssetPlaceholder(isVideo: false);
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        const _MediaAssetPlaceholder(isVideo: false),
                  );
                },
              ),
              if (busy)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrActionTile extends StatelessWidget {
  const _QrActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _lightBorderColor)),
          ),
          child: Row(
            children: [
              Icon(icon, color: _textColor, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: onTap == null ? _mutedColor : _textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: _mutedColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = min(size.width - 64, 280.0);
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: scanSize,
      height: scanSize,
    );
    final overlay = Paint()..color = BimColors.scrim;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(path, overlay);

    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    const length = 26.0;
    final corners = <List<Offset>>[
      [rect.topLeft, rect.topLeft + const Offset(length, 0)],
      [rect.topLeft, rect.topLeft + const Offset(0, length)],
      [rect.topRight, rect.topRight - const Offset(length, 0)],
      [rect.topRight, rect.topRight + const Offset(0, length)],
      [rect.bottomLeft, rect.bottomLeft + const Offset(length, 0)],
      [rect.bottomLeft, rect.bottomLeft - const Offset(0, length)],
      [rect.bottomRight, rect.bottomRight - const Offset(length, 0)],
      [rect.bottomRight, rect.bottomRight - const Offset(0, length)],
    ];
    for (final line in corners) {
      canvas.drawLine(line[0], line[1], cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) => false;
}

String _firstBarcodeRawValue(BarcodeCapture? capture) {
  if (capture == null) {
    return '';
  }
  for (final barcode in capture.barcodes) {
    final raw = barcode.rawValue?.trim() ?? '';
    if (raw.isNotEmpty) {
      return raw;
    }
  }
  return '';
}

FilterOptionGroup get _qrAlbumFilterOption => FilterOptionGroup(
  orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
);

Future<String> _scanQrRawFromImagePath(String path) async {
  if (path.trim().isEmpty) {
    return '';
  }
  final scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  try {
    final capture = await scanner.analyzeImage(
      path,
      formats: const [BarcodeFormat.qrCode],
    );
    return _firstBarcodeRawValue(capture);
  } finally {
    scanner.dispose();
  }
}

Map<String, Object?>? _firstExactUsername(
  List<Map<String, Object?>> items,
  String username,
) {
  final target = username.toLowerCase();
  for (final item in items) {
    final user = _asObjectMap(item['user']);
    final value = _value(user, [
      'username',
    ], fallback: _value(item, ['username'])).toLowerCase();
    if (value == target) {
      return item;
    }
  }
  return null;
}
