part of 'package:bim/src/features/home/home_page.dart';

const _friendQrScheme = 'bim';
const _friendQrHost = 'friend';
const _friendQrPath = '/app/friend';

class FriendQrTarget {
  const FriendQrTarget({required this.username, required this.raw});

  final String username;
  final String raw;
}

Uri _friendQrUriWithNonce(UserSession session, String nonce) {
  final username = session.username.trim();
  return Uri(
    scheme: _friendQrScheme,
    host: _friendQrHost,
    path: '/add',
    queryParameters: {'username': username, if (nonce.isNotEmpty) 'v': nonce},
  );
}

FriendQrTarget? _parseFriendQrTarget(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme) {
    final username = _friendQrUsernameFromUri(uri);
    if (username.isNotEmpty) {
      return FriendQrTarget(username: username, raw: text);
    }
  }
  final username = _normalizeFriendQrUsername(text);
  if (username.isEmpty) {
    return null;
  }
  return FriendQrTarget(username: username, raw: text);
}

FriendQrTarget? parseFriendQrText(String raw) {
  return _parseFriendQrTarget(raw);
}

FriendQrTarget? _parseFriendQrUri(Uri uri) {
  final username = _friendQrUsernameFromUri(uri);
  if (username.isEmpty) {
    return null;
  }
  return FriendQrTarget(username: username, raw: uri.toString());
}

FriendQrTarget? parseFriendQrUri(Uri uri) {
  return _parseFriendQrUri(uri);
}

String _friendQrUsernameFromUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final host = uri.host.toLowerCase();
  final path = uri.path.toLowerCase();
  if (scheme == _friendQrScheme) {
    if (host != _friendQrHost && host != 'user') {
      return '';
    }
    return _normalizeFriendQrUsername(
      uri.queryParameters['username'] ??
          uri.queryParameters['u'] ??
          uri.queryParameters['account'] ??
          (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : ''),
    );
  }
  if (scheme == 'http' || scheme == 'https') {
    if (path != _friendQrPath && path != '/friend' && path != '/u') {
      return '';
    }
    return _normalizeFriendQrUsername(
      uri.queryParameters['username'] ??
          uri.queryParameters['u'] ??
          uri.queryParameters['account'] ??
          (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : ''),
    );
  }
  return '';
}

String _normalizeFriendQrUsername(String value) {
  final username = value.trim();
  if (username.isEmpty || username.length > 64) {
    return '';
  }
  final valid = RegExp(r'^[A-Za-z0-9_.@+-]+$').hasMatch(username);
  return valid ? username : '';
}

class MyFriendQrPage extends StatefulWidget {
  const MyFriendQrPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MyFriendQrPage> createState() => _MyFriendQrPageState();
}

class _MyFriendQrPageState extends State<MyFriendQrPage> {
  final GlobalKey _qrCardKey = GlobalKey();
  late String _nonce;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nonce = _newQrNonce();
  }

  void _refreshQr() {
    setState(() => _nonce = _newQrNonce());
  }

  Future<void> _saveQr() async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final boundary =
          _qrCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('qr card is not ready');
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('qr image is empty');
      }
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.hasAccess) {
        if (!mounted) {
          return;
        }
        _showChatSnack(context, '请允许访问相册后再保存', error: true);
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      final filename =
          'bim_qr_${DateTime.now().millisecondsSinceEpoch.toString()}.png';
      await PhotoManager.editor.saveImage(bytes, filename: filename);
      if (!mounted) {
        return;
      }
      _showChatSnack(context, '已保存到相册');
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'save friend qr failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showChatSnack(context, '保存失败', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.controller.session;
    if (session == null) {
      return const Scaffold(
        backgroundColor: _pageColor,
        body: SafeArea(child: Center(child: Text('请先登录'))),
      );
    }
    final qrUri = _friendQrUriWithNonce(session, _nonce);
    final displayName = _sessionDisplayName(session);
    final username = _atName(session.username);
    final qrSize = min(MediaQuery.sizeOf(context).width - 96, 280.0);
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('我的二维码'),
        actions: [
          IconButton(
            tooltip: '换二维码',
            onPressed: _refreshQr,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            RepaintBoundary(
              key: _qrCardKey,
              child: ColoredBox(
                color: _surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Avatar(
                            label: displayName,
                            imageUrl: session.avatar,
                            size: 58,
                            color: const Color(0xff8e99a8),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  username,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _mutedColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Center(
                        child: Container(
                          width: qrSize + 28,
                          height: qrSize + 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: _lightBorderColor),
                          ),
                          child: QrImageView(
                            data: qrUri.toString(),
                            version: QrVersions.auto,
                            size: qrSize,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: _textColor,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: _textColor,
                            ),
                            semanticsLabel: '我的二维码',
                            errorStateBuilder: (_, __) =>
                                const Center(child: Text('二维码生成失败')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Center(
                        child: Text(
                          '扫一扫，加我为好友',
                          style: TextStyle(color: _mutedColor, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _QrActionTile(
              icon: Icons.refresh_rounded,
              title: '换个二维码',
              onTap: _refreshQr,
            ),
            _QrActionTile(
              icon: Icons.save_alt_rounded,
              title: _saving ? '正在保存' : '保存到相册',
              onTap: _saving ? null : _saveQr,
            ),
          ],
        ),
      ),
    );
  }
}

String _newQrNonce() {
  final random = Random.secure();
  final value =
      DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
      random.nextInt(0x7fffffff).toRadixString(36);
  return value;
}

String _atName(String username) {
  final value = username.trim();
  if (value.isEmpty) {
    return '';
  }
  return value.startsWith('@') ? value : '@$value';
}

Future<void> _openQrScanResult({
  required BuildContext context,
  required SessionController controller,
  required String raw,
  bool replace = false,
}) async {
  final text = raw.trim();
  if (text.isEmpty) {
    throw Exception('二维码内容为空');
  }

  Widget page;
  final walletToken = _walletTokenFromQr(text);
  if (walletToken.isNotEmpty) {
    final order = await controller.scanWalletQr(walletToken);
    page = WalletPayConfirmPage(
      controller: controller,
      order: order,
      qrToken: walletToken,
    );
  } else {
    final friendTarget = _parseFriendQrTarget(text);
    page = friendTarget == null
        ? _UnknownQrResultPage(raw: text)
        : FriendQrResultPage(controller: controller, target: friendTarget);
  }

  if (!context.mounted) {
    return;
  }
  final route = MaterialPageRoute<void>(builder: (_) => page);
  if (replace) {
    await Navigator.of(context).pushReplacement(route);
  } else {
    await Navigator.of(context).push(route);
  }
}

class FriendQrScannerPage extends StatefulWidget {
  const FriendQrScannerPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<FriendQrScannerPage> createState() => _FriendQrScannerPageState();
}

class _FriendQrScannerPageState extends State<FriendQrScannerPage> {
  late final MobileScannerController _scanner;
  bool _handled = false;
  bool _pickingImage = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoZoom: true,
    );
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim() ?? '';
      if (raw.isEmpty) {
        continue;
      }
      await _openRaw(raw);
      return;
    }
  }

  Future<void> _openRaw(String raw) async {
    _handled = true;
    await _scanner.stop();
    if (!mounted) {
      return;
    }
    try {
      await _openQrScanResult(
        context: context,
        controller: widget.controller,
        raw: raw,
        replace: true,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'open qr scan result failed',
        error: error,
        stackTrace: stackTrace,
        data: {'raw_length': raw.length},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _handled = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
      unawaited(_scanner.start());
    }
  }

  Future<void> _pickFromAlbum() async {
    if (_handled || _pickingImage) {
      return;
    }
    setState(() {
      _pickingImage = true;
      _error = '';
    });
    await _scanner.stop();
    try {
      final path = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _QrAlbumPickerPage()),
      );
      if (!mounted || path == null || path.isEmpty) {
        return;
      }
      final capture = await _scanner.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      );
      final raw = _firstBarcodeRawValue(capture);
      if (raw.isEmpty) {
        setState(() => _error = '未识别到二维码');
        return;
      }
      await _openRaw(raw);
    } on UnsupportedError {
      if (mounted) {
        setState(() => _error = '当前平台不支持从相册识别');
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'scan friend qr image failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = '图片识别失败');
      }
    } finally {
      if (mounted && !_handled) {
        setState(() => _pickingImage = false);
        unawaited(_scanner.start());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanSize = min(MediaQuery.sizeOf(context).width - 64, 280.0);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫一扫'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _pickingImage ? null : _pickFromAlbum,
            child: const Text(
              '相册',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scanner,
                    onDetect: _handleCapture,
                    errorBuilder: (context, error) => Center(
                      child: Text(
                        '相机不可用',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _ScannerOverlayPainter()),
                    ),
                  ),
                  Center(
                    child: SizedBox(
                      width: scanSize,
                      height: scanSize,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 1.6),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 28,
                    child: Text(
                      _error.isEmpty ? '将二维码放入框内' : _error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _error.isEmpty ? Colors.white : _dangerColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_pickingImage)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x66000000),
                        child: Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendQrResultPage extends StatefulWidget {
  const FriendQrResultPage({
    required this.controller,
    required this.target,
    super.key,
  });

  final SessionController controller;
  final FriendQrTarget target;

  @override
  State<FriendQrResultPage> createState() => _FriendQrResultPageState();
}

class _FriendQrResultPageState extends State<FriendQrResultPage> {
  late Future<Map<String, Object?>> _future;
  bool _acting = false;
  String _message = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _future = _search();
  }

  Future<Map<String, Object?>> _search() {
    return widget.controller.searchFriends(
      keyword: widget.target.username,
      limit: 1,
    );
  }

  void _reload() {
    setState(() {
      _future = _search();
      _message = '';
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('添加好友')),
      body: SafeArea(
        child: FutureBuilder<Map<String, Object?>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(
                text: snapshot.error.toString(),
                onRetry: _reload,
              );
            }
            final items = _listFromResult(snapshot.data ?? const {});
            final item = _firstExactUsername(items, widget.target.username);
            if (item == null) {
              return _ErrorState(text: '未找到该用户', onRetry: _reload);
            }
            return _buildProfile(item);
          },
        ),
      ),
    );
  }

  Widget _buildProfile(Map<String, Object?> item) {
    final user = _asObjectMap(item['user']);
    final title = _searchFriendTitle(item);
    final subtitle = _searchFriendSubtitle(item);
    final avatar = _avatarUrlFromMap(user, fallback: _avatarUrlFromMap(item));
    final actionText = _searchFriendActionText(item);
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
      children: [
        ColoredBox(
          color: _surfaceColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
            child: Row(
              children: [
                _Avatar(
                  label: title,
                  imageUrl: avatar,
                  size: 64,
                  color: const Color(0xff8e99a8),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textColor,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _mutedColor,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const _GroupGap(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton(
            onPressed: _acting ? null : () => _handleAction(item),
            child: Text(actionText),
          ),
        ),
        if (_acting) const _LinearBusy(),
        _ResultBlock(text: _message),
        _ErrorBlock(text: _error),
      ],
    );
  }

  Future<void> _handleAction(Map<String, Object?> item) async {
    if (_boolValue(item['is_friend'])) {
      _openRemoteFriendChat(item);
      return;
    }
    if (_boolValue(item['pending_in_apply'])) {
      await _push(context, FriendRequestsPage(controller: widget.controller));
      return;
    }
    if (_boolValue(item['pending_out_apply'])) {
      setState(() => _message = '好友申请已发送，等待对方通过。');
      return;
    }
    await _applyFriend(item);
  }

  Future<void> _applyFriend(Map<String, Object?> item) async {
    final friendId = _searchFriendId(item);
    if (friendId.isEmpty) {
      setState(() => _error = '用户信息为空');
      return;
    }
    setState(() {
      _acting = true;
      _message = '';
      _error = '';
    });
    try {
      final result = await widget.controller.applyFriend(
        friendId: friendId,
        remark: '通过二维码添加',
      );
      _message = _friendlyResult(result, successText: '好友申请已发送');
      _future = _search();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  void _openRemoteFriendChat(Map<String, Object?> item) {
    final user = _asObjectMap(item['user']);
    final friendId = _searchFriendId(item);
    final channelId = _value(item, [
      'channel_id',
      'uid',
    ], fallback: _uidFromUserId(friendId));
    if (friendId.isEmpty || channelId.isEmpty) {
      setState(() => _error = '用户 IM 信息为空');
      return;
    }
    _openPrivateChat(context, widget.controller, {
      ...user,
      'friend': user,
      'friend_id': friendId,
      'userid': friendId,
      'channel_id': channelId,
    });
  }
}

class _UnknownQrResultPage extends StatelessWidget {
  const _UnknownQrResultPage({required this.raw});

  final String raw;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: raw));
    if (context.mounted) {
      _showChatSnack(context, '已复制');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('二维码内容')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 32),
          children: [
            const Icon(Icons.qr_code_2, size: 52, color: _mutedColor),
            const SizedBox(height: 16),
            const Text(
              '未识别到可处理的业务二维码',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '可以复制内容后自行确认来源。',
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedColor, fontSize: 13),
            ),
            const SizedBox(height: 22),
            DecoratedBox(
              decoration: BoxDecoration(
                color: _surfaceColor,
                border: Border.all(color: _lightBorderColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  raw,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制内容'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrAlbumPickerPage extends StatefulWidget {
  const _QrAlbumPickerPage();

  @override
  State<_QrAlbumPickerPage> createState() => _QrAlbumPickerPageState();
}

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
        color: const Color(0xffe8eaed),
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
    final overlay = Paint()..color = const Color(0x66000000);
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
