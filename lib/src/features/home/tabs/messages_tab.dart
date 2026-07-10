part of 'package:bim/src/features/home/home_page.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesHeader extends StatelessWidget {
  const _MessagesHeader({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BimColors.surface,
      padding: const EdgeInsets.fromLTRB(
        BimSpacing.x4,
        BimSpacing.x2,
        BimSpacing.x4,
        BimSpacing.x3,
      ),
      child: Row(
        children: [
          Expanded(
            child: BimPressable(
              onTap: () => _push(context, SearchPage(controller: controller)),
              semanticLabel: '搜索消息和联系人',
              child: Container(
                height: BimDimensions.touchTarget,
                padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x3),
                decoration: BoxDecoration(
                  color: BimColors.fill,
                  borderRadius: BorderRadius.circular(BimRadius.sm),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search, color: BimColors.mutedText, size: 19),
                    SizedBox(width: BimSpacing.x2),
                    Text(
                      '搜索消息和联系人',
                      style: TextStyle(
                        color: BimColors.mutedText,
                        fontSize: BimTypography.meta,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: BimSpacing.x2),
          BimPressable(
            onTap: () =>
                _push(context, FriendQrScannerPage(controller: controller)),
            semanticLabel: '扫一扫',
            child: Container(
              width: BimDimensions.touchTarget,
              height: BimDimensions.touchTarget,
              alignment: Alignment.center,
              color: BimColors.fill,
              child: const Icon(
                Icons.qr_code_scanner,
                color: BimColors.text,
                size: 21,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesTabState extends State<MessagesTab> {
  late int _conversationRevision;
  List<Map<String, Object?>> _conversations = const [];
  bool _loading = true;
  String? _error;
  int _loadToken = 0;
  StreamSubscription<BusinessImMessageEvent>? _messageSub;

  @override
  void initState() {
    super.initState();
    _conversationRevision = widget.controller.conversationVersion;
    _conversations = widget.controller.cachedConversations();
    _precacheConversationAvatars(context, _conversations);
    _loading =
        _conversations.isEmpty || widget.controller.initialHistorySyncing;
    widget.controller.addListener(_onControllerChanged);
    _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
    _loadConversations(showLoading: _conversations.isEmpty);
  }

  @override
  void didUpdateWidget(MessagesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _messageSub?.cancel();
      _conversations = widget.controller.cachedConversations();
      _loading =
          _conversations.isEmpty || widget.controller.initialHistorySyncing;
      _error = null;
      widget.controller.addListener(_onControllerChanged);
      _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
      _loadConversations(showLoading: _conversations.isEmpty);
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final next = widget.controller.conversationVersion;
    if (widget.controller.initialHistorySyncing && !_loading) {
      setState(() => _loading = true);
    }
    if (!widget.controller.initialHistorySyncing &&
        _loading &&
        next == _conversationRevision) {
      setState(() => _loading = false);
    }
    if (next != _conversationRevision) {
      _conversationRevision = next;
      _applyCachedConversations();
    }
  }

  void _applyCachedConversations() {
    final list = widget.controller.cachedConversations();
    _precacheConversationAvatars(context, list);
    setState(() {
      _conversations = list;
      _loading = widget.controller.initialHistorySyncing && list.isEmpty;
      _error = null;
    });
  }

  Future<void> _loadConversations({required bool showLoading}) async {
    final token = ++_loadToken;
    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await widget.controller.loadConversations();
      if (!mounted || token != _loadToken) {
        return;
      }
      _precacheConversationAvatars(context, list);
      setState(() {
        _conversations = list;
        _loading = widget.controller.initialHistorySyncing;
        _error = null;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) {
        return;
      }
      final cached = widget.controller.cachedConversations();
      if (cached.isNotEmpty) {
        _precacheConversationAvatars(context, cached);
        AppLogger.warn(
          'ui',
          'conversation load failed, keep visible cache',
          data: {'count': cached.length, 'error': error.toString()},
        );
        setState(() {
          _conversations = cached;
          _loading = false;
          _error = null;
        });
        return;
      }
      final isLoginRace = error.toString().contains('请先登录');
      if (isLoginRace && widget.controller.isSessionRestoring) {
        AppLogger.info(
          'ui',
          'conversation load waits restored session',
          data: {'booting': widget.controller.booting},
        );
        setState(() {
          _loading = true;
          _error = null;
        });
        return;
      }
      AppLogger.warn(
        'ui',
        'conversation load failed without local cache',
        data: {'login_race': isLoginRace, 'error': error.toString()},
      );
      setState(() {
        _loading = false;
        _error = isLoginRace ? null : error.toString();
      });
    }
  }

  void _onMessageEvent(BusinessImMessageEvent event) {
    if (!mounted || event.conversation.isEmpty) {
      return;
    }
    final next = _upsertConversation(_conversations, event.conversation);
    _precacheConversationAvatars(context, next);
    setState(() {
      _conversations = next;
      _loading = false;
      _error = null;
      _conversationRevision = widget.controller.conversationVersion;
    });
  }

  Future<void> _refreshReadStateAfterChatPop(
    String channelId,
    int channelType,
  ) async {
    try {
      await widget.controller.markConversationRead(
        channelId: channelId,
        channelType: channelType,
      );
      if (!mounted) {
        return;
      }
      _applyCachedConversations();
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'refresh read state after chat pop failed',
        error: error,
        stackTrace: stackTrace,
        data: {'channel_id': channelId, 'channel_type': channelType},
      );
    }
  }

  Future<void> _setConversationPinned(
    Map<String, Object?> item, {
    required bool pinned,
  }) async {
    final channelType = _channelTypeFromConversation(item);
    final channelId = _conversationChannelId(item, channelType);
    if (channelId.isEmpty) {
      return;
    }
    await widget.controller.setConversationPinned(
      channelId: channelId,
      channelType: channelType,
      pinned: pinned,
    );
    if (mounted) {
      _applyCachedConversations();
    }
  }

  Future<void> _deleteConversation(Map<String, Object?> item) async {
    final confirmed = await _confirmDanger(
      context,
      title: '删除会话',
      content: '将清空你自己看到的这个会话和聊天记录，不影响对方。',
      confirmText: '删除',
    );
    if (!confirmed) {
      return;
    }
    await widget.controller.deleteConversation(conversation: item);
    if (mounted) {
      _applyCachedConversations();
    }
  }

  Future<void> _showConversationActions(Map<String, Object?> item) async {
    final pinned = _conversationPinned(item);
    final action = await BimActionSheet.show<String>(
      context: context,
      children: [
        BimActionSheetItem(
          icon: pinned ? Icons.push_pin_outlined : Icons.push_pin,
          label: pinned ? '取消置顶' : '置顶',
          onTap: () => Navigator.of(context).pop('pin'),
        ),
        BimActionSheetItem(
          icon: Icons.delete_outline,
          label: '删除会话',
          danger: true,
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    );
    if (!mounted) {
      return;
    }
    if (action == 'pin') {
      await _setConversationPinned(item, pinned: !pinned);
      return;
    }
    if (action == 'delete') {
      await _deleteConversation(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = _MessagesHeader(controller: widget.controller);
    return ColoredBox(
      color: BimColors.surface,
      child: ListView.builder(
        physics: const ClampingScrollPhysics(),
        itemCount: _conversations.isEmpty ? 2 : _conversations.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return header;
          }
          if (_conversations.isEmpty) {
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: _emptyBody(),
            );
          }
          return _conversationTile(context, _conversations[index - 1]);
        },
      ),
    );
  }

  Widget _emptyBody() {
    if (_loading) {
      return const BimLoadingState(label: '正在同步会话');
    }
    if (_error != null) {
      return _ErrorState(
        text: _error!,
        onRetry: () => _loadConversations(showLoading: true),
      );
    }
    return _ChatEmptyState(
      scene: _ChatEmptyScene.conversations,
      onAction: () => _push(context, SearchPage(controller: widget.controller)),
    );
  }

  Widget _conversationTile(BuildContext context, Map<String, Object?> item) {
    final title = _conversationTitle(item);
    final content = _conversationSubtitle(item);
    final time = _conversationTimeText(item);
    final unread = _intValue(item, ['unread_quantity']);
    final channelType = _channelTypeFromConversation(item);
    final channelId = _conversationChannelId(item, channelType);
    final contentType = _value(item, [
      'content_type',
    ], fallback: _value(_asObjectMap(item['payload']), ['content_type']));
    final paymentService =
        channelType == _privateChannelType &&
        (contentType == ChatContentTypes.walletNotice || title == '支付通知');
    final pinned = _conversationPinned(item);
    return Dismissible(
      key: ValueKey('conversation-$channelType-$channelId'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _showConversationActions(item);
        return false;
      },
      background: _ConversationSwipeActions(pinned: pinned),
      child: _ConversationTile(
        title: title,
        subtitle: content.isEmpty ? '暂无最新消息' : content,
        time: time,
        unread: unread,
        isGroup: channelType == _groupChannelType,
        isPinned: pinned,
        avatarUrl: _conversationAvatarUrl(item),
        onLongPress: () => _showConversationActions(item),
        onTap: () {
          if (channelId.isEmpty) {
            return;
          }
          unawaited(
            Navigator.of(context)
                .push(
                  _chatPageRoute(
                    paymentService
                        ? PaymentServicePage(
                            controller: widget.controller,
                            title: title.isEmpty ? '支付通知' : title,
                            channelId: channelId,
                            channelType: channelType,
                          )
                        : ChatPage(
                            controller: widget.controller,
                            title: title,
                            channelId: channelId,
                            groupId: _value(item, [
                              'group_id',
                              'id',
                            ], fallback: channelId),
                            channelType: channelType,
                          ),
                  ),
                )
                .then(
                  (_) => _refreshReadStateAfterChatPop(channelId, channelType),
                ),
          );
        },
      ),
    );
  }

  bool _conversationPinned(Map<String, Object?> item) {
    for (final key in const ['is_pinned', 'pinned', 'is_top', 'top']) {
      final value = item[key];
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

  Future<bool> _confirmDanger(
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
            child: Text(
              confirmText,
              style: const TextStyle(color: BimColors.danger),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  List<Map<String, Object?>> _sortConversationsForUi(
    List<Map<String, Object?>> conversations,
  ) {
    final next = conversations
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
    next.sort((a, b) {
      final pinnedCompare =
          (_conversationPinned(b) ? 1 : 0) - (_conversationPinned(a) ? 1 : 0);
      if (pinnedCompare != 0) {
        return pinnedCompare;
      }
      return _value(b, [
        'msg_time',
        'create_time',
        'timestamp',
      ]).compareTo(_value(a, ['msg_time', 'create_time', 'timestamp']));
    });
    return next;
  }

  List<Map<String, Object?>> _upsertConversation(
    List<Map<String, Object?>> current,
    Map<String, Object?> conversation,
  ) {
    final next = current
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final channelId = _value(conversation, ['channel_id']);
    final channelType = _channelTypeFromConversation(conversation);
    final index = next.indexWhere(
      (item) =>
          _value(item, ['channel_id']) == channelId &&
          _channelTypeFromConversation(item) == channelType,
    );
    if (index >= 0) {
      next[index] = {...next[index], ...conversation};
    } else {
      next.insert(0, Map<String, Object?>.from(conversation));
    }
    return _sortConversationsForUi(next);
  }
}
