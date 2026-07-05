part of 'package:bim/src/features/home/home_page.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MessagesTab> createState() => _MessagesTabState();
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
      _loadConversations(showLoading: false);
    }
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
      setState(() {
        _loading = false;
        _error = error.toString();
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
      await _loadConversations(showLoading: false);
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

  @override
  Widget build(BuildContext context) {
    final header = _SearchBar(
      hintText: '搜索',
      onTap: () => _push(context, SearchPage(controller: widget.controller)),
    );
    return ColoredBox(
      color: _surfaceColor,
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(
        text: _error!,
        onRetry: () => _loadConversations(showLoading: true),
      );
    }
    return const _EmptyState(text: '暂无会话');
  }

  Widget _conversationTile(BuildContext context, Map<String, Object?> item) {
    final title = _conversationTitle(item);
    final content = _conversationSubtitle(item);
    final time = _conversationTimeText(item);
    final unread = _intValue(item, ['unread_quantity']);
    final channelType = _channelTypeFromConversation(item);
    final channelId = _conversationChannelId(item, channelType);
    return _ConversationTile(
      key: ValueKey('conversation-$channelType-$channelId'),
      title: title,
      subtitle: content.isEmpty ? '暂无最新消息' : content,
      time: time,
      unread: unread,
      isGroup: channelType == _groupChannelType,
      avatarUrl: _conversationAvatarUrl(item),
      onTap: () {
        if (channelId.isEmpty) {
          return;
        }
        unawaited(
          Navigator.of(context)
              .push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPage(
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
    );
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
    next.sort(
      (a, b) => _value(b, ['msg_time']).compareTo(_value(a, ['msg_time'])),
    );
    return next;
  }
}
