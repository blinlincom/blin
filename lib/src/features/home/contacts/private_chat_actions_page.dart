part of 'package:bim/src/features/home/home_page.dart';

class PrivateChatActionsPage extends StatefulWidget {
  const PrivateChatActionsPage({
    required this.controller,
    required this.title,
    required this.receiverId,
    required this.channelId,
    this.avatarUrl = '',
    this.online = false,
    this.burnAfterRead = false,
    this.peerBurnAfterRead = false,
    this.burnSeconds = 0,
    this.peerBurnSeconds = 0,
    this.onBurnChanged,
    this.onStartVoiceCall,
    this.onStartVideoCall,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String receiverId;
  final String channelId;
  final String avatarUrl;
  final bool online;
  final bool burnAfterRead;
  final bool peerBurnAfterRead;
  final int burnSeconds;
  final int peerBurnSeconds;
  final Future<void> Function(bool enabled, int seconds)? onBurnChanged;
  final VoidCallback? onStartVoiceCall;
  final VoidCallback? onStartVideoCall;

  @override
  State<PrivateChatActionsPage> createState() => _PrivateChatActionsPageState();
}

class _PrivateChatActionsPageState extends State<PrivateChatActionsPage> {
  String _message = '';
  String _error = '';
  late bool _burnAfterRead;
  late int _burnSeconds;
  late bool _pinned;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _burnAfterRead = widget.burnAfterRead;
    _burnSeconds = widget.burnSeconds;
    _pinned = _initialPinned();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: const BimTopBar(title: '聊天信息'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            _ChatInfoMemberStrip(
              title: widget.title,
              avatarUrl: widget.avatarUrl,
              online: widget.online,
              onOpenProfile: _openProfile,
            ),
            const _GroupGap(),
            _SettingsNavTile(title: '查找聊天记录', onTap: _openMessageSearch),
            const _GroupGap(),
            _SettingsSwitchTile(
              title: '置顶聊天',
              subtitle: '',
              value: _pinned,
              onChanged: _busy ? null : _changePinned,
            ),
            _SettingsSwitchTile(
              title: '阅后即焚',
              subtitle: _burnSubtitle,
              value: _burnAfterRead,
              onChanged: _busy || widget.onBurnChanged == null
                  ? null
                  : _changeBurnAfterRead,
            ),
            _SettingsValueNavTile(
              title: '阅后即焚倒计时',
              value: _burnAfterRead ? '$_burnSeconds 秒' : '开启后可设置',
              onTap: _burnAfterRead ? _editBurnSeconds : null,
            ),
            const _GroupGap(),
            _SettingsNavTile(title: '查看好友资料', onTap: _openProfile),
            _SettingsNavTile(title: '好友状态', onTap: _friendStatus),
            const _GroupGap(),
            _SettingsNavTile(title: '消息提醒设置', onTap: _openNotificationSettings),
            _SettingsDangerTile(title: '清空聊天记录', onTap: _deleteConversation),
            _SettingsDangerTile(title: '删除好友', onTap: _deleteFriend),
            if (_busy) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  String get _burnSubtitle {
    final parts = <String>[];
    if (_burnAfterRead) {
      parts.add(_burnSeconds > 0 ? '我已开启，$_burnSeconds 秒后焚毁' : '我已开启');
    } else {
      parts.add('关闭');
    }
    if (widget.peerBurnAfterRead) {
      parts.add(
        widget.peerBurnSeconds > 0
            ? '对方已开启 ${widget.peerBurnSeconds} 秒'
            : '对方已开启',
      );
    }
    return parts.join(' · ');
  }

  bool _initialPinned() {
    final conversation = _currentConversation();
    if (conversation.isEmpty) {
      return false;
    }
    for (final key in const ['is_pinned', 'pinned', 'is_top', 'top']) {
      final value = conversation[key];
      if (value != null) {
        return _boolValue(value);
      }
    }
    return false;
  }

  Map<String, Object?> _currentConversation() {
    for (final item in widget.controller.cachedConversations()) {
      final channelType = _intValue(item, [
        'channel_type',
        'channelType',
        'type',
      ]);
      final channelId = _value(item, [
        'channel_id',
        'channelID',
        'channel',
        'uid',
      ]);
      if (channelType == _privateChannelType && channelId == widget.channelId) {
        return item;
      }
    }
    return const {};
  }

  Future<void> _changePinned(bool value) async {
    final previous = _pinned;
    setState(() {
      _pinned = value;
      _busy = true;
      _message = '';
      _error = '';
    });
    try {
      await widget.controller.setConversationPinned(
        channelId: widget.channelId,
        channelType: _privateChannelType,
        pinned: value,
      );
    } catch (error) {
      setState(() {
        _pinned = previous;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openMessageSearch() {
    _push(
      context,
      ChatMessageSearchPage(
        controller: widget.controller,
        title: widget.title,
        channelId: widget.channelId,
        channelType: _privateChannelType,
      ),
    );
  }

  void _openNotificationSettings() {
    _push(
      context,
      BackgroundReceiveProtectionPage(controller: widget.controller),
    );
  }

  Future<void> _changeBurnAfterRead(bool value) async {
    final previousEnabled = _burnAfterRead;
    final previousSeconds = _burnSeconds;
    setState(() {
      _busy = true;
      _burnAfterRead = value;
      if (!value) {
        _burnSeconds = 0;
      }
      _message = '';
      _error = '';
    });
    try {
      await widget.onBurnChanged?.call(_burnAfterRead, _burnSeconds);
    } catch (error) {
      setState(() {
        _burnAfterRead = previousEnabled;
        _burnSeconds = previousSeconds;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editBurnSeconds() async {
    final data = await _openInput(
      context,
      title: '阅后即焚倒计时',
      fields: [
        ActionInputField(
          id: 'seconds',
          label: '秒数',
          keyboardType: TextInputType.number,
          initial: _burnSeconds > 0 ? _burnSeconds.toString() : '',
        ),
      ],
    );
    if (data == null) {
      return;
    }
    final seconds = int.tryParse(data['seconds'] ?? '') ?? 0;
    final old = _burnSeconds;
    setState(() {
      _busy = true;
      _burnSeconds = seconds;
      _message = '';
      _error = '';
    });
    try {
      await widget.onBurnChanged?.call(true, _burnSeconds);
    } catch (error) {
      setState(() {
        _burnSeconds = old;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openProfile() async {
    await _push(
      context,
      FriendProfilePage(
        controller: widget.controller,
        title: widget.title,
        receiverId: widget.receiverId,
        channelId: widget.channelId,
        avatarUrl: widget.avatarUrl,
        online: widget.online,
        onOpenChat: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  Future<void> _friendStatus() async {
    try {
      final result = await widget.controller.friendStatus(widget.receiverId);
      setState(() {
        _message = _friendStatusText(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteFriend() async {
    await _run(() => widget.controller.deleteFriend(widget.receiverId));
  }

  Future<void> _deleteConversation() async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空聊天记录',
      content: '将清空你自己看到的这个单聊记录和会话，不影响对方。',
      confirmText: '清空',
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => widget.controller.deletePrivateConversation(
        receiverId: widget.receiverId,
        channelId: widget.channelId,
      ),
    );
  }

  Future<void> _run(Future<Map<String, Object?>> Function() task) async {
    try {
      final result = await task();
      setState(() {
        _message = _friendlyResult(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class ChatMessageSearchPage extends StatefulWidget {
  const ChatMessageSearchPage({
    required this.controller,
    required this.title,
    required this.channelId,
    required this.channelType,
    this.groupId = '',
    super.key,
  });

  final SessionController controller;
  final String title;
  final String channelId;
  final int channelType;
  final String groupId;

  @override
  State<ChatMessageSearchPage> createState() => _ChatMessageSearchPageState();
}

class _ChatMessageSearchPageState extends State<ChatMessageSearchPage> {
  final TextEditingController _queryController = TextEditingController();
  Future<List<Map<String, Object?>>>? _messagesFuture;

  @override
  void initState() {
    super.initState();
    _messagesFuture = widget.controller.loadLocalMessages(
      channelId: widget.channelId,
      channelType: widget.channelType,
      groupId: widget.groupId,
    );
    _queryController.addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _queryController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: const BimTopBar(title: '查找聊天记录'),
      body: SafeArea(
        child: Column(
          children: [
            ColoredBox(
              color: _surfaceColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: TextField(
                  controller: _queryController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText:
                        '搜索 ${widget.title.isEmpty ? '聊天记录' : widget.title}',
                    prefixIcon: const Icon(Icons.search, size: 21),
                    isDense: true,
                    filled: true,
                    fillColor: _fillColor,
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(BimRadius.md),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<Map<String, Object?>>>(
                future: _messagesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const BimLoadingState(label: '正在查找聊天记录');
                  }
                  if (snapshot.hasError) {
                    return _EmptyState(text: snapshot.error.toString());
                  }
                  final messages = _filteredSearchMessages(
                    snapshot.data ?? const [],
                    _queryController.text,
                  );
                  if (messages.isEmpty) {
                    return _EmptyState(
                      text: _queryController.text.trim().isEmpty
                          ? '输入关键词搜索聊天记录'
                          : '没有找到相关聊天记录',
                    );
                  }
                  return ListView.separated(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: messages.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _lightBorderColor),
                    itemBuilder: (context, index) {
                      final item = messages[index];
                      final payload = _asObjectMap(item['payload']);
                      final content = _messageSearchText(item, payload);
                      return BimListTile(
                        title: content,
                        titleMaxLines: 2,
                        subtitle: _messageTimeLabel(item),
                        showDivider: false,
                        minHeight: 62,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: const BimTopBar(title: '个人名片'),
      body: SafeArea(
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
    super.key,
  });

  final SessionController controller;
  final String title;
  final int userId;

  @override
  State<FriendMomentsPage> createState() => _FriendMomentsPageState();
}

class _FriendMomentsPageState extends State<FriendMomentsPage> {
  late Future<Map<String, Object?>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.loadUserMoments(
      userId: widget.userId,
      limit: 30,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: const BimTopBar(title: '朋友圈'),
      body: SafeArea(
        child: FutureBuilder<Map<String, Object?>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const BimLoadingState(label: '正在加载动态');
            }
            if (snapshot.hasError) {
              return _EmptyState(text: snapshot.error.toString());
            }
            final posts = _listFromResult(snapshot.data ?? const {});
            if (posts.isEmpty) {
              return const _EmptyState(text: '暂无动态');
            }
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const _GroupGap(),
              itemBuilder: (context, index) {
                return _FriendMomentTile(
                  title: widget.title,
                  post: posts[index],
                );
              },
            );
          },
        ),
      ),
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

class _ChatInfoMemberStrip extends StatelessWidget {
  const _ChatInfoMemberStrip({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.onOpenProfile,
  });

  final String title;
  final String avatarUrl;
  final bool online;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChatInfoMemberItem(
              title: title.isEmpty ? '好友' : title,
              avatarUrl: avatarUrl,
              online: online,
              onTap: onOpenProfile,
            ),
            const SizedBox(width: 28),
            const _ChatInfoAddMemberItem(),
          ],
        ),
      ),
    );
  }
}

class _ChatInfoMemberItem extends StatelessWidget {
  const _ChatInfoMemberItem({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.onTap,
  });

  final String title;
  final String avatarUrl;
  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 58,
              color: const Color(0xff8e99a8),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            _PresencePill(online: online),
          ],
        ),
      ),
    );
  }
}

class _ChatInfoAddMemberItem extends StatelessWidget {
  const _ChatInfoAddMemberItem();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _surfaceColor,
              border: Border.all(color: _borderColor),
              borderRadius: BorderRadius.circular(_avatarRadius(58)),
            ),
            child: const Icon(Icons.add, color: _mutedColor, size: 30),
          ),
          const SizedBox(height: 8),
          const Text(
            '添加',
            style: TextStyle(
              color: _mutedColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(title: title, onTap: onTap);
  }
}

class _SettingsValueNavTile extends StatelessWidget {
  const _SettingsValueNavTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(title: title, value: value, onTap: onTap);
  }
}

class _SettingsDangerTile extends StatelessWidget {
  const _SettingsDangerTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      onTap: onTap,
      tone: BimSettingsTileTone.danger,
      showChevron: false,
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  const _SettingsInfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      value: value,
      showChevron: false,
      valueMaxLines: 4,
    );
  }
}

class _FriendProfileHero extends StatelessWidget {
  const _FriendProfileHero({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.username,
    required this.signature,
  });

  final String title;
  final String avatarUrl;
  final bool online;
  final String username;
  final String signature;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 72,
              color: const Color(0xff8e99a8),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title.isEmpty ? '好友' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PresencePill(online: online),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (username.isNotEmpty)
                    Text(
                      '账号：${_atName(username)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  if (signature.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      signature,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendMomentsPreview extends StatelessWidget {
  const _FriendMomentsPreview({required this.future, required this.onTap});

  final Future<Map<String, Object?>>? future;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _lightBorderColor)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 90,
                child: Text(
                  '朋友圈',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: _MomentPreviewImages(future: future)),
              const Icon(Icons.chevron_right, color: _mutedColor, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _MomentPreviewImages extends StatelessWidget {
  const _MomentPreviewImages({required this.future});

  final Future<Map<String, Object?>>? future;

  @override
  Widget build(BuildContext context) {
    if (future == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Map<String, Object?>>(
      future: future,
      builder: (context, snapshot) {
        final urls = snapshot.connectionState == ConnectionState.done
            ? _momentPreviewUrls(snapshot.data ?? const {})
            : const <String>[];
        if (urls.isEmpty) {
          return const Align(
            alignment: Alignment.centerRight,
            child: Text(
              '暂无动态',
              style: TextStyle(color: _mutedColor, fontSize: 14),
            ),
          );
        }
        return Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 6,
            children: [
              for (final url in urls.take(4))
                _MomentPreviewThumb(imageUrl: url),
            ],
          ),
        );
      },
    );
  }
}

class _MomentPreviewThumb extends StatelessWidget {
  const _MomentPreviewThumb({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _fillColor,
        borderRadius: BorderRadius.circular(BimRadius.xs),
      ),
      child: Image.network(
        _normalizeAvatarUrl(imageUrl),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const ColoredBox(color: _fillColor),
      ),
    );
  }
}

class _FriendMomentTile extends StatelessWidget {
  const _FriendMomentTile({required this.title, required this.post});

  final String title;
  final Map<String, Object?> post;

  @override
  Widget build(BuildContext context) {
    final content = _momentContent(post);
    final media = _momentMediaFromPost(post);
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? '好友动态' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                content,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
            ],
            if (media.isNotEmpty) ...[
              const SizedBox(height: 10),
              _FriendMomentMediaGrid(media: media),
            ],
            const SizedBox(height: 10),
            Text(
              _momentTimeText(post),
              style: const TextStyle(color: _mutedColor, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _FriendMomentMediaGrid extends StatelessWidget {
  const _FriendMomentMediaGrid({required this.media});

  final List<Map<String, Object?>> media;

  @override
  Widget build(BuildContext context) {
    final count = min(media.length, 9);
    final columns = count == 1 ? 1 : 3;
    final width = MediaQuery.sizeOf(context).width;
    final tileSize = columns == 1 ? min(width - 72, 220.0) : 92.0;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final item in media.take(9))
          _FriendMomentMediaThumb(item: item, size: tileSize),
      ],
    );
  }
}

class _FriendMomentMediaThumb extends StatelessWidget {
  const _FriendMomentMediaThumb({required this.item, required this.size});

  final Map<String, Object?> item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = _momentMediaUrl(item);
    final type = _value(item, ['type', 'media_type', 'content_type']);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _fillColor,
        borderRadius: BorderRadius.circular(BimRadius.xs),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isNotEmpty)
            Image.network(
              _normalizeAvatarUrl(url),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const ColoredBox(color: _fillColor),
            )
          else
            const ColoredBox(color: _fillColor),
          if (type.toLowerCase().contains('video'))
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 34,
              ),
            ),
        ],
      ),
    );
  }
}

List<String> _momentPreviewUrls(Map<String, Object?> data) {
  final urls = <String>[];
  for (final post in _listFromResult(data)) {
    final media = _momentMediaFromPost(post);
    for (final item in media) {
      final url = _value(item, [
        'thumb_url',
        'cover_url',
        'thumbnail_url',
        'poster_url',
        'preview_url',
        'image_url',
        'url',
        'file_url',
        'media_url',
        'path',
      ]);
      if (url.isNotEmpty) {
        urls.add(url);
      }
      if (urls.length >= 4) {
        return urls;
      }
    }
  }
  return urls;
}

String _momentContent(Map<String, Object?> post) {
  return _value(post, ['content', 'text', 'body', 'desc', 'description']);
}

String _momentTimeText(Map<String, Object?> post) {
  final time = _parseUiTime(
    _value(post, ['created_at', 'create_time', 'publish_time', 'timestamp']),
  );
  if (time == null) {
    return '';
  }
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  if (time.year == now.year && time.month == now.month && time.day == now.day) {
    return '${two(time.hour)}:${two(time.minute)}';
  }
  if (time.year == now.year) {
    return '${time.month}月${time.day}日';
  }
  return '${time.year}年${time.month}月${time.day}日';
}

String _momentMediaUrl(Map<String, Object?> item) {
  return _value(item, [
    'thumb_url',
    'cover_url',
    'thumbnail_url',
    'poster_url',
    'preview_url',
    'image_url',
    'url',
    'file_url',
    'media_url',
    'path',
  ]);
}

List<Map<String, Object?>> _momentMediaFromPost(Map<String, Object?> post) {
  final media = post['media'];
  if (media is List) {
    return media
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }
  if (media is String && media.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(media);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (item) =>
                  item.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList(growable: false);
      }
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return BimSettingsSwitchTile(
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: _mutedColor, fontSize: 14),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresencePill extends StatelessWidget {
  const _PresencePill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          color: online ? _chatOnlineColor : _mutedColor,
          size: 8,
        ),
        const SizedBox(width: 6),
        Text(
          online ? '在线' : '离线',
          style: const TextStyle(color: _mutedColor, fontSize: 12),
        ),
      ],
    );
  }
}
