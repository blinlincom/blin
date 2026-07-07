part of 'package:bim/src/features/home/home_page.dart';

const _friendQrScheme = 'bim';
const _friendQrHost = 'friend';
const _friendQrPath = '/app/friend';

class FriendQrTarget {
  const FriendQrTarget({required this.username, required this.raw});

  final String username;
  final String raw;
}

Uri _friendQrUri(UserSession session) {
  final username = session.username.trim();
  return Uri(
    scheme: _friendQrScheme,
    host: _friendQrHost,
    path: '/add',
    queryParameters: {'username': username},
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

class MyFriendQrPage extends StatelessWidget {
  const MyFriendQrPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    if (session == null) {
      return const Scaffold(
        backgroundColor: _pageColor,
        body: SafeArea(child: Center(child: Text('请先登录'))),
      );
    }
    final qrUri = _friendQrUri(session);
    final displayName = _sessionDisplayName(session);
    final username = session.username.trim();
    final qrSize = min(MediaQuery.sizeOf(context).width - 96, 280.0);
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('我的二维码')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
          children: [
            ColoredBox(
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
                                '用户名：$username',
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
                          semanticsLabel: 'BIM 好友二维码',
                          errorStateBuilder: (_, __) =>
                              const Center(child: Text('二维码生成失败')),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Center(
                      child: Text(
                        '扫一扫上面的二维码，加我为好友',
                        style: TextStyle(color: _mutedColor, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _PlainInfoBlock(
              text: '二维码只用于跳转到好友查询，不展示用户 IMUID。外部扫码会尝试打开 BIM 并进入添加好友流程。',
            ),
          ],
        ),
      ),
    );
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
  final _manual = TextEditingController();
  bool _handled = false;
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
    _manual.dispose();
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
    final target = _parseFriendQrTarget(raw);
    if (target == null) {
      setState(() => _error = '不是有效的 BIM 好友二维码');
      return;
    }
    _handled = true;
    await _scanner.stop();
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) =>
            FriendQrResultPage(controller: widget.controller, target: target),
      ),
    );
  }

  Future<void> _openManual() async {
    final value = _manual.text.trim();
    if (value.isEmpty) {
      setState(() => _error = '请输入二维码内容或用户名');
      return;
    }
    await _openRaw(value);
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
                        '相机启动失败：${error.errorCode.name}',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: scanSize,
                      height: scanSize,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 28,
                    child: Text(
                      _error.isEmpty ? '将好友二维码放入框内' : _error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _error.isEmpty ? Colors.white : _dangerColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ColoredBox(
              color: _surfaceColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _openManual(),
                        decoration: const InputDecoration(
                          hintText: '粘贴二维码内容或输入用户名',
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: BimDimensions.touchTarget,
                      child: FilledButton(
                        onPressed: _openManual,
                        child: const Text('查询'),
                      ),
                    ),
                  ],
                ),
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

class _PlainInfoBlock extends StatelessWidget {
  const _PlainInfoBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Text(
          text,
          style: const TextStyle(
            color: _mutedColor,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
