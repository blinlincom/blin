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
    return BimScaffold(
      topBar: const BimTopBar(title: '聊天信息'),
      body: BimContentViewport(
        maxWidth: 680,
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
    return BimScaffold(
      topBar: const BimTopBar(title: '查找聊天记录'),
      body: BimContentViewport(
        maxWidth: 760,
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
