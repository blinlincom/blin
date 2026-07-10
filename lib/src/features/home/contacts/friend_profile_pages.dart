part of 'package:bim/src/features/home/home_page.dart';

class FriendProfilePage extends StatefulWidget {
  const FriendProfilePage({
    required this.controller,
    required this.title,
    required this.receiverId,
    required this.channelId,
    this.avatarUrl = '',
    this.online = false,
    this.onOpenChat,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String receiverId;
  final String channelId;
  final String avatarUrl;
  final bool online;
  final VoidCallback? onOpenChat;

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage> {
  Future<Map<String, Object?>>? _statusFuture;
  Future<Map<String, Object?>>? _momentsFuture;
  String _message = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _statusFuture = widget.controller.friendStatus(widget.receiverId);
    final userId = int.tryParse(widget.receiverId) ?? 0;
    _momentsFuture = userId > 0
        ? widget.controller.loadUserMoments(userId: userId, limit: 4)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: const BimTopBar(title: '个人名片'),
      body: BimContentViewport(
        maxWidth: 680,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            FutureBuilder<Map<String, Object?>>(
              future: _statusFuture,
              builder: (context, snapshot) {
                final status = snapshot.connectionState == ConnectionState.done
                    ? snapshot.data ?? const <String, Object?>{}
                    : const <String, Object?>{};
                final signature = _friendSignatureFromStatus(status);
                final username = _friendUsernameFromStatus(status);
                final source = _friendSourceFromStatus(status);
                return Column(
                  children: [
                    _FriendProfileHero(
                      title: widget.title,
                      avatarUrl: widget.avatarUrl,
                      online: widget.online,
                      username: username,
                      signature: signature,
                    ),
                    const _GroupGap(),
                    _SettingsInfoTile(
                      title: '来源',
                      value: source.isEmpty ? '通过好友关系添加' : source,
                    ),
                  ],
                );
              },
            ),
            const _GroupGap(),
            _FriendMomentsPreview(future: _momentsFuture, onTap: _openMoments),
            _SettingsNavTile(title: '朋友圈和状态', onTap: _openMoments),
            const _GroupGap(),
            _SettingsNavTile(title: '解除好友关系', onTap: _deleteFriend),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: SizedBox(
                height: 50,
                child: FilledButton(
                  onPressed: _openChat,
                  style: FilledButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(BimRadius.lg),
                    ),
                  ),
                  child: const Text(
                    '发消息',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMoments() {
    final userId = int.tryParse(widget.receiverId) ?? 0;
    if (userId <= 0) {
      return;
    }
    _push(
      context,
      FriendMomentsPage(
        controller: widget.controller,
        title: widget.title,
        userId: userId,
        avatarUrl: widget.avatarUrl,
      ),
    );
  }

  Future<void> _deleteFriend() async {
    try {
      final result = await widget.controller.deleteFriend(widget.receiverId);
      setState(() {
        _message = _friendlyResult(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _openChat() {
    Navigator.of(context).maybePop();
    widget.onOpenChat?.call();
  }
}

class FriendMomentsPage extends StatefulWidget {
  const FriendMomentsPage({
    required this.controller,
    required this.title,
    required this.userId,
    this.avatarUrl = '',
    super.key,
  });

  final SessionController controller;
  final String title;
  final int userId;
  final String avatarUrl;

  @override
  State<FriendMomentsPage> createState() => _FriendMomentsPageState();
}

class _FriendMomentsPageState extends State<FriendMomentsPage> {
  late Future<Map<String, Object?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, Object?>> _load() {
    return widget.controller.loadUserMoments(userId: widget.userId, limit: 30);
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(title: '${widget.title}的朋友圈'),
      body: FutureBuilder<Map<String, Object?>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _FriendMomentsLoading();
          }
          if (snapshot.hasError) {
            return BimEmptyState(
              title: '朋友圈加载失败',
              message: snapshot.error.toString(),
              icon: Icons.error_outline,
              actionLabel: '重新加载',
              onAction: _refresh,
            );
          }
          final posts = _listFromResult(snapshot.data ?? const {});
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                BimBreakpoints.horizontalPadding(context),
                BimSpacing.x3,
                BimBreakpoints.horizontalPadding(context),
                BimSpacing.x8,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FriendMomentsIdentity(
                          title: widget.title,
                          avatarUrl: widget.avatarUrl,
                          count: posts.length,
                        ),
                        const BimSectionHeader(text: '动态'),
                        if (posts.isEmpty)
                          const BimEmptyState(
                            title: '暂无朋友圈动态',
                            message: '对方发布的新动态会显示在这里',
                            icon: Icons.photo_library_outlined,
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: BimColors.surface,
                              border: Border.all(color: BimColors.borderLight),
                              borderRadius: BorderRadius.circular(BimRadius.sm),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (
                                  var index = 0;
                                  index < posts.length;
                                  index++
                                )
                                  _FriendMomentTile(
                                    post: posts[index],
                                    showDivider: index != posts.length - 1,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FriendMomentsIdentity extends StatelessWidget {
  const _FriendMomentsIdentity({
    required this.title,
    required this.avatarUrl,
    required this.count,
  });

  final String title;
  final String avatarUrl;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BimSpacing.x4),
      decoration: BoxDecoration(
        color: BimColors.surface,
        border: Border.all(color: BimColors.borderLight),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Row(
        children: [
          _Avatar(
            label: title,
            imageUrl: avatarUrl,
            size: 58,
            color: BimColors.primary,
            icon: Icons.person_outline,
          ),
          const SizedBox(width: BimSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BimColors.textDark,
                    fontSize: BimTypography.profile,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  count == 0 ? '暂无动态' : '共 $count 条动态',
                  style: const TextStyle(
                    color: BimColors.secondaryText,
                    fontSize: BimTypography.meta,
                    fontWeight: FontWeight.w600,
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

class _FriendMomentsLoading extends StatelessWidget {
  const _FriendMomentsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(BimSpacing.x4),
      children: const [
        SizedBox(height: 120),
        BimLoadingState(label: '正在加载朋友圈'),
      ],
    );
  }
}

List<Map<String, Object?>> _filteredSearchMessages(
  List<Map<String, Object?>> messages,
  String query,
) {
  final keyword = query.trim().toLowerCase();
  if (keyword.isEmpty) {
    return const [];
  }
  return messages
      .where((item) {
        final payload = _asObjectMap(item['payload']);
        final content = _messageSearchText(item, payload).toLowerCase();
        final sender = _messageSenderName(item).toLowerCase();
        return content.contains(keyword) || sender.contains(keyword);
      })
      .toList(growable: false);
}

String _messageSearchText(
  Map<String, Object?> item,
  Map<String, Object?> payload,
) {
  final text = _messageContentText(item, payload).trim();
  if (text.isNotEmpty && text != '[消息]') {
    return text;
  }
  final media = _asObjectMap(payload['media']);
  final name = _value(media, ['name', 'filename', 'file_name', 'display_name']);
  if (name.isNotEmpty) {
    return name;
  }
  return _quoteContentTypeText(_messageContentType(item));
}

String _friendSignatureFromStatus(Map<String, Object?> status) {
  for (final source in [
    status,
    _asObjectMap(status['friend']),
    _asObjectMap(status['user']),
  ]) {
    final value = _value(source, ['signature', 'bio', 'description']);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _friendUsernameFromStatus(Map<String, Object?> status) {
  for (final source in [
    status,
    _asObjectMap(status['friend']),
    _asObjectMap(status['user']),
  ]) {
    final value = _value(source, ['username', 'account']);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _friendSourceFromStatus(Map<String, Object?> status) {
  for (final source in [
    status,
    _asObjectMap(status['friend']),
    _asObjectMap(status['user']),
  ]) {
    final value = _value(source, [
      'source_text',
      'source_name',
      'source',
      'from',
      'add_source',
    ]);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}
