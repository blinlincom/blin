part of 'package:bim/src/features/home/home_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.controller,
    required this.title,
    required this.channelId,
    required this.groupId,
    required this.channelType,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String channelId;
  final String groupId;
  final int channelType;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const int _messageUiLimit = 1000;

  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  bool _toolsOpen = false;
  bool _burnAfterRead = false;
  bool _mentionAll = false;
  int _burnSeconds = 0;
  List<String> _mentionUserIds = const [];
  String _replyClientMsgNo = '';
  String _selectedClientMsgNo = '';
  int _selectedMessageSeq = 0;
  Map<String, Object?> _selectedPayload = const {};
  Map<String, Object?> _groupMuteState = const {};
  String? _error;
  String _message = '';
  List<Map<String, Object?>> _messages = const [];
  bool _messagesLoading = true;
  int _messageLoadToken = 0;
  late int _conversationRevision;
  late int _messageRevision;
  StreamSubscription<BusinessImMessageEvent>? _messageSub;
  StreamSubscription<BusinessImPresenceEvent>? _presenceSub;
  bool _didInitialScroll = false;
  bool _peerOnline = false;
  bool _onlineStatusLoading = false;
  bool _channelInvalid = false;
  int _onlineStatusToken = 0;
  String _lastImStatusText = '';
  int? _groupMemberCount;
  int? _groupOnlineCount;
  bool _groupPresenceLoading = false;
  int _groupPresenceToken = 0;
  final Set<String> _burnTriggeredClientMsgNos = <String>{};
  final Set<String> _receivingRedPacketIds = <String>{};
  final Set<String> _receivingTransferIds = <String>{};

  bool get _isGroup => widget.channelType == _groupChannelType;
  String get _groupId =>
      widget.groupId.isEmpty ? widget.channelId : widget.groupId;
  String get _receiverId => _privateReceiverIdFromChannel(widget.channelId);
  bool get _composerEnabled =>
      !_channelInvalid &&
      (!_isGroup || _groupMuteText(_groupMuteState).isEmpty);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _conversationRevision = widget.controller.conversationVersion;
    _messageRevision = _currentMessageRevision();
    _lastImStatusText = widget.controller.imStatusText;
    _channelInvalid = widget.controller.isChannelInvalid(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    widget.controller.addListener(_onControllerChanged);
    _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
    _presenceSub = widget.controller.presenceEvents.listen(_onPresenceEvent);
    _inputFocusNode.addListener(_onInputFocusChanged);
    unawaited(
      widget.controller.openConversation(
        channelId: widget.channelId,
        channelType: widget.channelType,
      ),
    );
    _loadMessagesIntoState(showLoading: true);
    _refreshGroupMuteState();
    _refreshPeerOnlineStatus();
    if (_isGroup && !_channelInvalid) {
      unawaited(_loadGroupMuteStatus());
      unawaited(_refreshGroupPresence());
    }
    _textController.text = widget.controller.readDraft(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    _textController.addListener(() {
      widget.controller.writeDraft(
        channelId: widget.channelId,
        channelType: widget.channelType,
        text: _textController.text,
      );
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (_inputFocusNode.hasFocus && _isNearBottom()) {
      _stickToBottomDuringKeyboard();
    }
  }

  void _onInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) {
      return;
    }
    if (_toolsOpen) {
      setState(() => _toolsOpen = false);
    }
    if (_isNearBottom()) {
      _stickToBottomDuringKeyboard();
    }
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _messageSub?.cancel();
      _presenceSub?.cancel();
      _conversationRevision = widget.controller.conversationVersion;
      _messageRevision = _currentMessageRevision();
      _lastImStatusText = widget.controller.imStatusText;
      widget.controller.addListener(_onControllerChanged);
      _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
      _presenceSub = widget.controller.presenceEvents.listen(_onPresenceEvent);
    } else if (oldWidget.channelId != widget.channelId ||
        oldWidget.channelType != widget.channelType) {
      _conversationRevision = widget.controller.conversationVersion;
      _messageRevision = _currentMessageRevision();
      _lastImStatusText = widget.controller.imStatusText;
      _messages = const [];
      _didInitialScroll = false;
      _burnTriggeredClientMsgNos.clear();
      _receivingRedPacketIds.clear();
      _receivingTransferIds.clear();
      _groupMuteState = const {};
      _peerOnline = false;
      _onlineStatusLoading = false;
      _channelInvalid = widget.controller.isChannelInvalid(
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _groupMemberCount = null;
      _groupOnlineCount = null;
      _groupPresenceLoading = false;
      unawaited(
        widget.controller.openConversation(
          channelId: widget.channelId,
          channelType: widget.channelType,
        ),
      );
      _loadMessagesIntoState(showLoading: true);
      _refreshGroupMuteState();
      _refreshPeerOnlineStatus();
      if (_isGroup && !_channelInvalid) {
        unawaited(_loadGroupMuteStatus());
        unawaited(_refreshGroupPresence());
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final nextConversation = widget.controller.conversationVersion;
    final nextMessage = _currentMessageRevision();
    final status = widget.controller.imStatusText;
    final becameConnected = status == '已连接' && _lastImStatusText != status;
    _lastImStatusText = status;
    final invalid = widget.controller.isChannelInvalid(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    if (invalid && !_channelInvalid) {
      setState(() {
        _channelInvalid = true;
        _messages = const [];
        _messagesLoading = false;
        _groupPresenceLoading = false;
        _groupMuteState = const {};
      });
    }
    if (becameConnected && !_channelInvalid) {
      if (_isGroup) {
        unawaited(_refreshGroupPresence());
      } else {
        _refreshPeerOnlineStatus();
      }
    }
    final muteChanged = _refreshGroupMuteState();
    final messageChanged = nextMessage != _messageRevision;
    if (nextConversation == _conversationRevision &&
        !messageChanged &&
        !muteChanged) {
      return;
    }
    _conversationRevision = nextConversation;
    _messageRevision = nextMessage;
    if (messageChanged) {
      _loadMessagesIntoState(showLoading: false);
    }
  }

  bool _refreshGroupMuteState() {
    if (!_isGroup) {
      if (_groupMuteState.isEmpty) {
        return false;
      }
      setState(() => _groupMuteState = const {});
      return true;
    }
    final state = widget.controller.groupMuteState(
      channelId: widget.channelId,
      groupId: _groupId,
    );
    if (_sameStringMap(_groupMuteState, state)) {
      return false;
    }
    if (mounted) {
      setState(() => _groupMuteState = state);
    } else {
      _groupMuteState = state;
    }
    return true;
  }

  Future<void> _loadGroupMuteStatus() async {
    if (_channelInvalid) {
      return;
    }
    try {
      await widget.controller.loadGroupMuteStatus(
        groupId: _groupId,
        channelId: widget.channelId,
      );
      if (mounted) {
        _refreshGroupMuteState();
      }
    } catch (error) {
      if (_isMissingGroupError(error)) {
        _markChannelInvalid();
        return;
      }
      AppLogger.warn(
        'ui',
        'load group mute status failed',
        data: {'group_id': _groupId, 'error': error.toString()},
      );
    }
  }

  String _chatHeaderStatusText() {
    if (_isGroup) {
      if (_channelInvalid) {
        return '群聊已失效';
      }
      if (_groupOnlineCount == null) {
        if (!_groupPresenceLoading) {
          return '在线人数获取失败';
        }
        return '在线人数同步中';
      }
      return '$_groupOnlineCount人在线';
    }
    if (_onlineStatusLoading) {
      return '检测中';
    }
    return _peerOnline ? '在线' : '离线';
  }

  String _chatHeaderTitle() {
    final title = widget.title.isEmpty ? '群聊' : widget.title;
    if (!_isGroup) {
      return widget.title;
    }
    final count = _groupMemberCount;
    return count == null ? title : '$title（$count）';
  }

  Future<void> _refreshGroupPresence() async {
    if (!_isGroup || _channelInvalid) {
      return;
    }
    final token = ++_groupPresenceToken;
    if (mounted) {
      setState(() => _groupPresenceLoading = true);
    }
    try {
      final groupMembersResult = await widget.controller.groupMembers(_groupId);
      if (!mounted || token != _groupPresenceToken) {
        return;
      }
      final members = _listFromResult(groupMembersResult);
      final onlineCount = await _loadGroupOnlineCount(members);
      if (!mounted || token != _groupPresenceToken) {
        return;
      }
      setState(() {
        _groupMemberCount = members.length;
        _groupOnlineCount = onlineCount;
        _groupPresenceLoading = false;
      });
    } catch (error, stackTrace) {
      if (_isMissingGroupError(error)) {
        _markChannelInvalid();
        return;
      }
      AppLogger.warn(
        'ui',
        'load group presence failed',
        data: {
          'group_id': _groupId,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      if (!mounted || token != _groupPresenceToken) {
        return;
      }
      setState(() => _groupPresenceLoading = false);
    }
  }

  Future<int> _loadGroupOnlineCount(List<Map<String, Object?>> members) async {
    if (members.isEmpty) {
      return 0;
    }
    const limit = 500;
    var page = 1;
    final counted = <String>{};
    while (mounted) {
      final result = await widget.controller.onlineUsers(
        page: page,
        limit: limit,
      );
      final onlineUsers = _listFromResult(result);
      for (final member in members) {
        final key = _memberPresenceKey(member);
        if (counted.contains(key)) {
          continue;
        }
        if (onlineUsers.any((user) => _memberMatchesOnlineUser(member, user))) {
          counted.add(key);
        }
      }
      if (counted.length >= members.length || onlineUsers.length < limit) {
        break;
      }
      page += 1;
    }
    return counted.length;
  }

  Future<void> _refreshPeerOnlineStatus() async {
    if (_isGroup) {
      if (mounted) {
        setState(() {
          _peerOnline = false;
          _onlineStatusLoading = false;
        });
      }
      return;
    }
    final receiverId = _receiverId;
    if (receiverId.isEmpty) {
      return;
    }
    final token = ++_onlineStatusToken;
    if (mounted) {
      setState(() => _onlineStatusLoading = true);
    }
    try {
      final result = await widget.controller.friendStatus(receiverId);
      final online = _onlineFromFriendStatus(result);
      if (!mounted || token != _onlineStatusToken) {
        return;
      }
      setState(() {
        _peerOnline = online;
        _onlineStatusLoading = false;
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'load peer online status failed',
        data: {
          'receiver_id': receiverId,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      if (!mounted || token != _onlineStatusToken) {
        return;
      }
      setState(() {
        _peerOnline = false;
        _onlineStatusLoading = false;
      });
    }
  }

  bool _onlineFromFriendStatus(Map<String, Object?> result) {
    for (final source in [
      result,
      _asObjectMap(result['friend']),
      _asObjectMap(result['user']),
    ]) {
      for (final key in ['online', 'is_online', 'connected']) {
        final value = source[key];
        if (value != null) {
          return _boolValue(value);
        }
      }
      final status = _value(source, [
        'online_status',
        'status',
        'state',
      ]).toLowerCase();
      if (status == 'online' || status == 'connected' || status == '1') {
        return true;
      }
      if (status == 'offline' || status == '0' || status == '离线') {
        return false;
      }
    }
    return false;
  }

  void _onMessageEvent(BusinessImMessageEvent event) {
    if (!mounted ||
        event.channelId != widget.channelId ||
        event.channelType != widget.channelType) {
      return;
    }
    final shouldStickToBottom = _shouldAutoScrollForMessage(event);
    setState(() {
      if (_isChannelInvalidEvent(event.source)) {
        _channelInvalid = true;
        _messages = const [];
        _messagesLoading = false;
        _groupPresenceLoading = false;
        _groupMuteState = const {};
      } else if (_isMessageDeleteEvent(event.source)) {
        final target = _value(event.message, ['client_msg_no']);
        _messages = _messages
            .where((item) => _value(item, ['client_msg_no']) != target)
            .toList(growable: false);
      } else {
        _messages = _mergeMessageList(
          _messages,
          event.message,
          limit: _messageUiLimit,
        );
      }
      _messagesLoading = false;
      _messageRevision = _currentMessageRevision();
      _conversationRevision = widget.controller.conversationVersion;
    });
    if (shouldStickToBottom) {
      _scrollToBottom(animated: event.source != 'send_local');
    }
    _scheduleBurnAfterReadForMessages(_messages);
    if (!_channelInvalid) {
      unawaited(
        widget.controller.openConversation(
          channelId: widget.channelId,
          channelType: widget.channelType,
        ),
      );
    }
  }

  void _onPresenceEvent(BusinessImPresenceEvent event) {
    if (!mounted || _isGroup) {
      return;
    }
    final receiverId = _receiverId;
    final receiverUserId = _privateReceiverIdFromChannel(receiverId);
    final eventUserId = event.userId.isNotEmpty
        ? event.userId
        : _privateReceiverIdFromChannel(event.uid);
    final eventUid = event.uid.isNotEmpty
        ? event.uid
        : _uidFromUserId(eventUserId);
    if (receiverId.isEmpty ||
        eventUserId.isEmpty ||
        (eventUserId != receiverUserId && eventUid != receiverId)) {
      return;
    }
    if (_peerOnline == event.online && !_onlineStatusLoading) {
      return;
    }
    AppLogger.info(
      'ui',
      'peer presence updated',
      data: {
        'receiver_id': receiverId,
        'uid': event.uid,
        'user_id': event.userId,
        'online': event.online,
      },
    );
    setState(() {
      _peerOnline = event.online;
      _onlineStatusLoading = false;
    });
  }

  int _currentMessageRevision() {
    return widget.controller.messageVersion(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
  }

  Future<List<Map<String, Object?>>> _loadMessages() {
    return AppLogger.measure(
      'ui',
      'load chat messages',
      () => widget.controller.loadLocalMessages(
        channelId: widget.channelId,
        channelType: widget.channelType,
        groupId: widget.groupId,
      ),
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
      },
    );
  }

  Future<void> _loadMessagesIntoState({required bool showLoading}) async {
    final token = ++_messageLoadToken;
    final wasNearBottom = _isNearBottom();
    if (showLoading && mounted) {
      setState(() {
        _messagesLoading = true;
        _error = null;
      });
    }
    try {
      final messages = await _loadMessages();
      if (!mounted || token != _messageLoadToken) {
        return;
      }
      final invalid = widget.controller.isChannelInvalid(
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _precacheMessageAvatars(
        context,
        messages,
        widget.controller.session?.avatar ?? '',
      );
      final nextMessages = _stableLoadedMessages(messages, showLoading);
      setState(() {
        _channelInvalid = invalid;
        _messages = nextMessages;
        _messagesLoading = false;
      });
      _scheduleBurnAfterReadForMessages(nextMessages);
      if (showLoading && !_didInitialScroll) {
        _didInitialScroll = true;
        _scrollToBottom(animated: false);
      } else if (wasNearBottom) {
        _scrollToBottom(animated: false);
      }
    } catch (error) {
      if (!mounted || token != _messageLoadToken) {
        return;
      }
      if (_isMissingGroupError(error)) {
        _markChannelInvalid();
        return;
      }
      setState(() {
        _messagesLoading = false;
        _error = error.toString();
      });
    }
  }

  List<Map<String, Object?>> _stableLoadedMessages(
    List<Map<String, Object?>> loaded,
    bool showLoading,
  ) {
    if (loaded.isEmpty && _messages.isNotEmpty && !showLoading) {
      AppLogger.warn(
        'ui',
        'skip empty chat refresh over visible messages',
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'current_count': _messages.length,
        },
      );
      return _messages;
    }
    if (_messages.isEmpty) {
      return loaded;
    }
    var merged = _messages;
    for (final item in loaded) {
      merged = _mergeMessageList(merged, item, limit: _messageUiLimit);
    }
    return merged;
  }

  void _markChannelInvalid() {
    if (!mounted) {
      _channelInvalid = true;
      return;
    }
    setState(() {
      _channelInvalid = true;
      _messages = const [];
      _messagesLoading = false;
      _groupPresenceLoading = false;
      _groupMuteState = const {};
    });
  }

  bool _isChannelInvalidEvent(String source) {
    return source == 'group_history_not_found' || source == 'channel_invalid';
  }

  bool _isMissingGroupError(Object error) {
    final text = error.toString();
    return text.contains('群聊不存在') ||
        text.contains('群不存在') ||
        text.toLowerCase().contains('group not found') ||
        text.toLowerCase().contains('group does not exist');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSub?.cancel();
    _presenceSub?.cancel();
    _scrollController.dispose();
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _inputFocusNode.dispose();
    widget.controller.closeConversation(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.writeDraft(
      channelId: widget.channelId,
      channelType: widget.channelType,
      text: _textController.text,
    );
    _textController.dispose();
    super.dispose();
  }

  List<Map<String, Object?>> _mergeMessageList(
    List<Map<String, Object?>> current,
    Map<String, Object?> incoming, {
    required int limit,
  }) {
    final next = current
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final clientMsgNo = _value(incoming, ['client_msg_no']);
    final index = clientMsgNo.isEmpty
        ? -1
        : next.indexWhere(
            (item) => _value(item, ['client_msg_no']) == clientMsgNo,
          );
    if (index >= 0) {
      next[index] = _mergeUiMessage(next[index], incoming);
    } else {
      next.add(Map<String, Object?>.from(incoming));
    }
    next.sort((a, b) {
      final seqA = _intValue(a, ['message_seq']);
      final seqB = _intValue(b, ['message_seq']);
      if (seqA > 0 && seqB > 0 && seqA != seqB) {
        return seqA.compareTo(seqB);
      }
      return _value(a, ['timestamp']).compareTo(_value(b, ['timestamp']));
    });
    if (next.length <= limit) {
      return next;
    }
    return next.sublist(next.length - limit);
  }

  String _messageStableKey(Map<String, Object?> item, int index) {
    final clientMsgNo = _value(item, ['client_msg_no']);
    if (clientMsgNo.isNotEmpty) {
      return 'client:$clientMsgNo';
    }
    final messageSeq = _intValue(item, ['message_seq']);
    if (messageSeq > 0) {
      return 'seq:$messageSeq';
    }
    final messageId = _value(item, ['message_id', 'msg_id', 'id']);
    if (messageId.isNotEmpty) {
      return 'id:$messageId';
    }
    final timestamp = _value(item, ['timestamp', 'create_time']);
    final sender = _value(item, ['from_uid', 'sender_uid', 'uid']);
    return 'local:$index:$timestamp:$sender:${_messageContentType(item)}';
  }

  Map<String, Object?> _mergeUiMessage(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final merged = <String, Object?>{...existing, ...incoming};
    final existingPayload = _asObjectMap(existing['payload']);
    final incomingPayload = _asObjectMap(incoming['payload']);
    if (existingPayload.isNotEmpty || incomingPayload.isNotEmpty) {
      final payload = <String, Object?>{...existingPayload, ...incomingPayload};
      for (final key in ['red_packet', 'transfer', 'media', 'receipt']) {
        final existingNested = _asObjectMap(existingPayload[key]);
        final incomingNested = _asObjectMap(incomingPayload[key]);
        if (existingNested.isNotEmpty || incomingNested.isNotEmpty) {
          payload[key] = {...existingNested, ...incomingNested};
        }
      }
      merged['payload'] = payload;
    }
    return merged;
  }

  bool _shouldAutoScrollForMessage(BusinessImMessageEvent event) {
    if (event.message['is_me'] == true || event.source.startsWith('send_')) {
      return true;
    }
    return _isNearBottom();
  }

  bool _isNearBottom({double threshold = 96}) {
    if (!_scrollController.hasClients) {
      return true;
    }
    final position = _scrollController.position;
    return position.pixels - position.minScrollExtent <= threshold;
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final bottom = _scrollController.position.minScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          bottom,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(bottom);
      }
    });
  }

  void _stickToBottomDuringKeyboard() {
    _scrollToBottom(animated: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inputFocusNode.hasFocus) {
        _scrollToBottom(animated: false);
      }
    });
  }

  void _toggleTools() {
    if (!_composerEnabled) {
      return;
    }
    final opening = !_toolsOpen;
    if (opening) {
      FocusScope.of(context).unfocus();
    }
    setState(() => _toolsOpen = opening);
    if (!opening) {
      _scrollToBottom(animated: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muteText = _groupMuteText(_groupMuteState);
    final composerEnabled = _composerEnabled;
    final toastText = _error ?? _message;
    final toastIsError = _error != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _surfaceColor,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: _surfaceColor,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _surfaceColor,
        body: SafeArea(
          child: ColoredBox(
            color: _chatPageColor,
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                return Stack(
                  children: [
                    Column(
                      children: [
                        _ChatHeader(
                          title: _chatHeaderTitle(),
                          avatarUrl: _headerAvatarUrl(),
                          isGroup: _isGroup,
                          statusText: _chatHeaderStatusText(),
                          online: !_isGroup && _peerOnline,
                          groupPresenceLoading: _groupPresenceLoading,
                          onBack: () => Navigator.of(context).maybePop(),
                          onDetail: _openChatDetail,
                          onVoiceCall: () => _showCallPending('语音通话'),
                          onVideoCall: () => _showCallPending('视频通话'),
                        ),
                        if (_replyClientMsgNo.isNotEmpty ||
                            _burnAfterRead ||
                            _mentionAll ||
                            _mentionUserIds.isNotEmpty)
                          _ChatOptionBar(
                            text: _optionText(),
                            onClear: _clearOptions,
                          ),
                        if (_selectedClientMsgNo.isNotEmpty)
                          _SelectedMessageBar(
                            onReply: () => setState(() {
                              _replyClientMsgNo = _selectedClientMsgNo;
                              _selectedClientMsgNo = '';
                            }),
                            onReceipt: _queryReceipt,
                            onRecall: _recallSelected,
                            onDelete: _deleteSelected,
                            onBurn: _burnSelected,
                            onReceiveTransfer: _receiveSelectedTransfer,
                            onClear: () => setState(() {
                              _selectedClientMsgNo = '';
                              _selectedPayload = const {};
                            }),
                          ),
                        Expanded(
                          child: _messagesLoading && _messages.isEmpty
                              ? const Center(child: CircularProgressIndicator())
                              : _messages.isEmpty
                              ? const _EmptyState(text: '暂无消息')
                              : ListView.builder(
                                  controller: _scrollController,
                                  reverse: true,
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    10,
                                    14,
                                    16,
                                  ),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final messageIndex =
                                        _messages.length - 1 - index;
                                    final item = _messages[messageIndex];
                                    final showTime = _shouldShowTimeDivider(
                                      _messages,
                                      messageIndex,
                                    );
                                    final stableKey = _messageStableKey(
                                      item,
                                      messageIndex,
                                    );
                                    return Column(
                                      key: ValueKey(stableKey),
                                      children: [
                                        if (showTime)
                                          _TimeDivider(
                                            text: _messageTimeLabel(item),
                                          ),
                                        _MessageRow(
                                          key: ValueKey('row:$stableKey'),
                                          item: item,
                                          showSenderName: _isGroup,
                                          currentUserAvatarUrl:
                                              widget
                                                  .controller
                                                  .session
                                                  ?.avatar ??
                                              '',
                                          onLongPress: () =>
                                              _selectMessage(item),
                                          onTap:
                                              _messageContentType(item) ==
                                                  ChatContentTypes.redPacket
                                              ? () => _receiveRedPacket(item)
                                              : null,
                                          redPacketReceiving:
                                              _redPacketIsReceiving(item),
                                          onRetry: () => _retryMessage(item),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                        _Composer(
                          controller: _textController,
                          focusNode: _inputFocusNode,
                          enabled: composerEnabled,
                          disabledText: muteText,
                          toolsOpen: _toolsOpen,
                          onVoice: () => _sendMedia(ChatContentTypes.voice),
                          onEmoji: () => _sendMedia(ChatContentTypes.emoji),
                          onTools: _toggleTools,
                          onSend: _sendText,
                        ),
                        if (_toolsOpen)
                          _ChatToolsPanel(
                            isGroup: _isGroup,
                            onTextOption: _openTextOptions,
                            onImage: () => _sendMedia(ChatContentTypes.image),
                            onEmoji: () => _sendMedia(ChatContentTypes.emoji),
                            onGif: () => _sendMedia(ChatContentTypes.gif),
                            onSticker: () =>
                                _sendMedia(ChatContentTypes.sticker),
                            onVoice: () => _sendMedia(ChatContentTypes.voice),
                            onVideo: () => _sendMedia(ChatContentTypes.video),
                            onFile: () => _sendMedia(ChatContentTypes.file),
                            onContactCard: _sendContactCard,
                            onTransfer: _sendTransfer,
                            onRedPacket: _sendRedPacket,
                            onGroupVoiceCall: () => _showCallPending('群语音通话'),
                            onGroupVideoCall: () => _showCallPending('群视频通话'),
                            onGroupMembers: _isGroup ? _openGroupMembers : null,
                          ),
                      ],
                    ),
                    if (toastText.isNotEmpty)
                      Positioned(
                        top: 72,
                        left: 28,
                        right: 28,
                        child: _ChatToast(
                          key: ValueKey('$toastIsError:$toastText'),
                          text: toastText,
                          error: toastIsError,
                          onDismiss: () {
                            if (!mounted) {
                              return;
                            }
                            if (toastIsError && _error == toastText) {
                              setState(() => _error = null);
                            } else if (!toastIsError && _message == toastText) {
                              setState(() => _message = '');
                            }
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _selectMessage(Map<String, Object?> item) {
    setState(() {
      _selectedClientMsgNo = _value(item, ['client_msg_no']);
      _selectedMessageSeq = _intValue(item, ['message_seq']);
      _selectedPayload = _asObjectMap(item['payload']);
      _message = _selectedClientMsgNo.isEmpty ? '当前消息暂不可操作' : '已选中消息';
    });
  }

  void _showCallPending(String name) {
    setState(() {
      _error = null;
      _message = '$name功能开发中';
    });
  }

  Future<void> _sendText() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }
    final mentionUserIds = List<String>.from(_mentionUserIds);
    final mentionAll = _mentionAll;
    final replyClientMsgNo = _replyClientMsgNo;
    final burnAfterRead = _burnAfterRead;
    final burnSeconds = _burnSeconds;
    final hadInputFocus = _inputFocusNode.hasFocus;
    await _runSending(
      () async {
        await widget.controller.sendTextMessage(
          channelId: widget.channelId,
          channelType: widget.channelType,
          groupId: widget.groupId,
          text: text,
          mentionUserIds: mentionUserIds,
          mentionAll: mentionAll,
          replyClientMsgNo: replyClientMsgNo,
          burnAfterRead: burnAfterRead,
          burnAfterReadSeconds: burnSeconds,
        );
      },
      beforeTask: () {
        _textController.clear();
        setState(() {
          _replyClientMsgNo = '';
          _mentionUserIds = const [];
          _mentionAll = false;
        });
        if (hadInputFocus) {
          _inputFocusNode.requestFocus();
        }
      },
      keepKeyboard: hadInputFocus,
    );
  }

  Future<void> _retryMessage(Map<String, Object?> item) async {
    if (_messageStatus(item) != 'failed') {
      return;
    }
    await _runSending(() => widget.controller.retryFailedMessage(item));
  }

  Future<void> _sendMedia(String contentType) async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _selectMediaPayload(contentType);
    if (data == null) {
      return;
    }
    final url = data['url'] ?? '';
    final filePath = data['file_path'] ?? '';
    final params = Map<String, Object?>.from(data)..remove('url');
    if (_burnAfterRead) {
      params['burn_after_read'] = '1';
      if (_burnSeconds > 0) {
        params['burn_after_read_seconds'] = _burnSeconds.toString();
      }
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupMedia(
          groupId: _groupId,
          channelId: widget.channelId,
          contentType: contentType,
          url: url,
          filePath: filePath,
          params: params,
        );
      } else {
        await widget.controller.sendPrivateMedia(
          receiverId: _receiverId,
          contentType: contentType,
          url: url,
          filePath: filePath,
          params: params,
        );
      }
    });
  }

  Future<Map<String, String>?> _selectMediaPayload(String contentType) {
    if (contentType == ChatContentTypes.image ||
        contentType == ChatContentTypes.video) {
      return Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(
          builder: (_) => _InAppMediaPickerPage(contentType: contentType),
        ),
      );
    }
    if (contentType == ChatContentTypes.file) {
      return Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(builder: (_) => const _InAppFilePickerPage()),
      );
    }
    return _openInput(
      context,
      title: _mediaTitle(contentType),
      fields: _mediaFields(contentType),
    );
  }

  Future<void> _sendContactCard() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '发送名片',
      fields: const [ActionInputField(id: 'card_user_id', label: '名片用户')],
    );
    if (data == null) {
      return;
    }
    final cardUserId = data['card_user_id'] ?? '';
    if (cardUserId.isEmpty) {
      setState(() => _error = '名片用户不能为空');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupContactCard(
          groupId: _groupId,
          channelId: widget.channelId,
          cardUserId: cardUserId,
        );
      } else {
        await widget.controller.sendPrivateContactCard(
          receiverId: _receiverId,
          cardUserId: cardUserId,
        );
      }
    });
  }

  Future<void> _sendTransfer() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '发送转账',
      fields: [
        const ActionInputField(
          id: 'money',
          label: '金额',
          keyboardType: TextInputType.number,
        ),
        const ActionInputField(
          id: 'asset_type',
          label: '资产类型',
          hint: 'money 或 integral',
          initial: 'money',
        ),
        const ActionInputField(id: 'remark', label: '备注'),
        if (_isGroup) const ActionInputField(id: 'receiver_id', label: '指定收款人'),
      ],
    );
    if (data == null) {
      return;
    }
    final money = (data['money'] ?? '').trim();
    if (!_isPositiveMoney(money)) {
      setState(() => _error = '金额必须大于 0');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupTransfer(
          groupId: _groupId,
          channelId: widget.channelId,
          receiverId: data['receiver_id'] ?? '',
          money: money,
          assetType: data['asset_type'] ?? 'money',
          remark: data['remark'] ?? '',
        );
      } else {
        await widget.controller.sendPrivateTransfer(
          receiverId: _receiverId,
          money: money,
          assetType: data['asset_type'] ?? 'money',
          remark: data['remark'] ?? '',
        );
      }
    });
  }

  Future<void> _sendRedPacket() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '发送红包',
      fields: [
        const ActionInputField(
          id: 'money',
          label: '金额',
          keyboardType: TextInputType.number,
        ),
        const ActionInputField(
          id: 'asset_type',
          label: '资产类型',
          hint: 'money 或 integral',
          initial: 'money',
        ),
        const ActionInputField(
          id: 'remark',
          label: '祝福语',
          initial: '恭喜发财，大吉大利',
        ),
        if (_isGroup)
          const ActionInputField(
            id: 'packet_type',
            label: '红包类型',
            hint: 'ordinary、luck、specified',
            initial: 'ordinary',
          ),
        if (_isGroup)
          const ActionInputField(
            id: 'quantity',
            label: '份数',
            keyboardType: TextInputType.number,
            initial: '1',
          ),
        if (_isGroup) const ActionInputField(id: 'receiver_id', label: '指定接收人'),
      ],
    );
    if (data == null) {
      return;
    }
    final money = (data['money'] ?? '').trim();
    if (!_isPositiveMoney(money)) {
      setState(() => _error = '金额必须大于 0');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupRedPacket(
          groupId: _groupId,
          channelId: widget.channelId,
          money: money,
          assetType: data['asset_type'] ?? 'money',
          packetType: data['packet_type'] ?? 'ordinary',
          quantity: int.tryParse(data['quantity'] ?? '') ?? 1,
          receiverId: data['receiver_id'] ?? '',
          remark: data['remark'] ?? '',
        );
      } else {
        await widget.controller.sendPrivateRedPacket(
          receiverId: _receiverId,
          money: money,
          assetType: data['asset_type'] ?? 'money',
          remark: data['remark'] ?? '',
        );
      }
    });
  }

  bool _isPositiveMoney(String value) {
    final amount = double.tryParse(value);
    return amount != null && amount > 0;
  }

  Future<void> _openTextOptions() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final data = await _openInput(
      context,
      title: '文本选项',
      fields: [
        if (_isGroup)
          ActionInputField(
            id: 'mention_user_ids',
            label: '@成员',
            hint: '多个成员用逗号分隔',
            initial: _mentionUserIds.join(','),
          ),
        if (_isGroup)
          ActionInputField(
            id: 'mention_all',
            label: '@所有人',
            hint: '填 1 表示开启',
            initial: _mentionAll ? '1' : '',
          ),
        ActionInputField(
          id: 'burn_after_read',
          label: '阅后即焚',
          hint: '填 1 表示开启',
          initial: _burnAfterRead ? '1' : '',
        ),
        ActionInputField(
          id: 'burn_after_read_seconds',
          label: '倒计时秒数',
          keyboardType: TextInputType.number,
          initial: _burnSeconds > 0 ? _burnSeconds.toString() : '',
        ),
      ],
    );
    if (data == null) {
      return;
    }
    setState(() {
      _mentionUserIds = _idsFromText(data['mention_user_ids'] ?? '');
      _mentionAll = (data['mention_all'] ?? '') == '1';
      _burnAfterRead = (data['burn_after_read'] ?? '') == '1';
      _burnSeconds = int.tryParse(data['burn_after_read_seconds'] ?? '') ?? 0;
    });
  }

  Future<void> _queryReceipt() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      await widget.controller.readReceipt(
        targetClientMsgNo: _selectedClientMsgNo,
        messageSeq: _selectedMessageSeq,
      );
      final status = await widget.controller.receiptStatus(
        _selectedClientMsgNo,
      );
      _message = _receiptText(status, isGroup: _isGroup);
    });
  }

  Future<void> _recallSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.recallMessage(
        targetClientMsgNo: _selectedClientMsgNo,
      );
      final target = _selectedClientMsgNo;
      await widget.controller.deleteLocalMessageOnly(
        targetClientMsgNo: target,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _messages = _messages
          .where((item) => _value(item, ['client_msg_no']) != target)
          .toList(growable: false);
      _selectedClientMsgNo = '';
      _selectedMessageSeq = 0;
      _selectedPayload = const {};
      _message = _friendlyResult(result, successText: '消息已撤回');
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    final confirmed = await _confirmDanger(
      context,
      title: '删除消息',
      content: '只删除你自己看到的这条消息，不影响其他人。',
      confirmText: '删除',
    );
    if (!confirmed) {
      return;
    }
    await _runAction(() async {
      final target = _selectedClientMsgNo;
      final result = await widget.controller.deleteMessageForSelf(
        targetClientMsgNo: target,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _messages = _messages
          .where((item) => _value(item, ['client_msg_no']) != target)
          .toList(growable: false);
      _selectedClientMsgNo = '';
      _selectedMessageSeq = 0;
      _selectedPayload = const {};
      _message = _friendlyResult(result, successText: '消息已删除');
    });
  }

  Future<void> _burnSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.burnAfterRead(
        _selectedClientMsgNo,
      );
      final target = _selectedClientMsgNo;
      await widget.controller.deleteLocalMessageOnly(
        targetClientMsgNo: target,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _messages = _messages
          .where((item) => _value(item, ['client_msg_no']) != target)
          .toList(growable: false);
      _selectedClientMsgNo = '';
      _selectedMessageSeq = 0;
      _selectedPayload = const {};
      _message = _friendlyResult(result, successText: '已触发阅后即焚');
    });
  }

  Future<void> _receiveRedPacket(Map<String, Object?> item) async {
    AppLogger.info(
      'ui',
      'red packet receive tapped',
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'client_msg_no': _value(item, ['client_msg_no']),
        'is_me': item['is_me'] == true,
        'payload': _asObjectMap(item['payload']),
      },
    );
    final payload = _asObjectMap(item['payload']);
    if (item['is_me'] == true && !_canReceiveOwnRedPacket(payload, _isGroup)) {
      setState(() {
        _error = null;
        _message = _isGroup ? '指定红包不能由发送者领取' : '不能领取自己发送的红包';
      });
      return;
    }
    final redPacketId = _redPacketReceiveId(payload);
    if (redPacketId.isEmpty) {
      final rawId = _redPacketRawId(payload);
      AppLogger.warn(
        'ui',
        'red packet receive blocked',
        data: {
          'reason': rawId.isEmpty ? 'empty_id' : 'invalid_id',
          'raw_id': rawId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
          'payload': payload,
        },
      );
      setState(() {
        _message = '';
        _error = rawId.isEmpty ? '红包发送确认中，请稍后再试' : '红包数据异常，请重新进入会话';
      });
      return;
    }
    final unavailableText = _redPacketUnavailableText(payload);
    if (unavailableText.isNotEmpty) {
      AppLogger.info(
        'ui',
        'red packet receive blocked',
        data: {
          'reason': unavailableText,
          'red_packet_id': redPacketId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
        },
      );
      setState(() {
        _error = null;
        _message = unavailableText;
      });
      return;
    }
    if (_receivingRedPacketIds.contains(redPacketId)) {
      AppLogger.info(
        'ui',
        'red packet receive duplicate ignored',
        data: {'red_packet_id': redPacketId},
      );
      return;
    }
    setState(() {
      _receivingRedPacketIds.add(redPacketId);
      _error = null;
      _message = '';
    });
    try {
      final result = await widget.controller.receiveRedPacket(
        redPacketId: redPacketId,
        group: _isGroup,
      );
      AppLogger.info(
        'ui',
        'red packet receive api success',
        data: {
          'red_packet_id': redPacketId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
          'result': result,
        },
      );
      final clientMsgNo = _value(item, ['client_msg_no']);
      await widget.controller.markRedPacketReceivedLocal(
        channelId: widget.channelId,
        channelType: widget.channelType,
        clientMsgNo: clientMsgNo,
        redPacketId: redPacketId,
        result: result,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _message = '';
        _conversationRevision = widget.controller.conversationVersion;
        _messageRevision = _currentMessageRevision();
      });
      await _loadMessagesIntoState(showLoading: false);
    } catch (error) {
      AppLogger.error(
        'ui',
        'red packet receive failed',
        error: error,
        data: {
          'red_packet_id': redPacketId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
        },
      );
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _receivingRedPacketIds.remove(redPacketId));
      }
    }
  }

  bool _redPacketIsReceiving(Map<String, Object?> item) {
    final id = _redPacketReceiveId(_asObjectMap(item['payload']));
    return id.isNotEmpty && _receivingRedPacketIds.contains(id);
  }

  Future<void> _receiveSelectedTransfer() async {
    AppLogger.info(
      'ui',
      'transfer receive tapped',
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'client_msg_no': _selectedClientMsgNo,
        'payload': _selectedPayload,
      },
    );
    final id = _transferReceiveId(_selectedPayload);
    if (id.isEmpty) {
      final rawId = _transferRawId(_selectedPayload);
      AppLogger.warn(
        'ui',
        'transfer receive blocked',
        data: {
          'reason': rawId.isEmpty ? 'empty_id' : 'invalid_id',
          'raw_id': rawId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _selectedClientMsgNo,
          'payload': _selectedPayload,
        },
      );
      setState(() {
        _message = '';
        _error = rawId.isEmpty ? '转账发送确认中，请稍后再试' : '转账数据异常，请重新进入会话';
      });
      return;
    }
    final unavailableText = _transferUnavailableText(_selectedPayload);
    if (unavailableText.isNotEmpty) {
      AppLogger.info(
        'ui',
        'transfer receive blocked',
        data: {
          'reason': unavailableText,
          'transfer_id': id,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _selectedClientMsgNo,
        },
      );
      setState(() {
        _error = null;
        _message = unavailableText;
      });
      return;
    }
    if (_receivingTransferIds.contains(id)) {
      AppLogger.info(
        'ui',
        'transfer receive duplicate ignored',
        data: {'transfer_id': id},
      );
      return;
    }
    setState(() {
      _receivingTransferIds.add(id);
      _error = null;
      _message = '';
    });
    try {
      final result = await widget.controller.receiveTransfer(id);
      AppLogger.info(
        'ui',
        'transfer receive api success',
        data: {
          'transfer_id': id,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _selectedClientMsgNo,
          'result': result,
        },
      );
      await widget.controller.markTransferReceivedLocal(
        channelId: widget.channelId,
        channelType: widget.channelType,
        clientMsgNo: _selectedClientMsgNo,
        transferId: id,
        result: result,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _message = _friendlyResult(result, successText: '转账已收款');
        _conversationRevision = widget.controller.conversationVersion;
        _messageRevision = _currentMessageRevision();
      });
      await _loadMessagesIntoState(showLoading: false);
    } catch (error) {
      AppLogger.error(
        'ui',
        'transfer receive failed',
        error: error,
        data: {
          'transfer_id': id,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _selectedClientMsgNo,
        },
      );
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _receivingTransferIds.remove(id));
      }
    }
  }

  Future<void> _openGroupMembers() async {
    await _push(
      context,
      GroupDetailPage(
        controller: widget.controller,
        title: widget.title,
        groupId: _groupId,
        channelId: widget.channelId,
      ),
    );
    if (mounted && _isGroup) {
      unawaited(_refreshGroupPresence());
    }
  }

  Future<void> _openChatDetail() async {
    await _push(
      context,
      _isGroup
          ? GroupDetailPage(
              controller: widget.controller,
              title: widget.title,
              groupId: _groupId,
              channelId: widget.channelId,
            )
          : PrivateChatActionsPage(
              controller: widget.controller,
              title: widget.title,
              receiverId: _receiverId,
              channelId: widget.channelId,
            ),
    );
    if (mounted && _isGroup) {
      unawaited(_refreshGroupPresence());
    }
  }

  Future<void> _runSending(
    Future<void> Function() task, {
    VoidCallback? beforeTask,
    bool keepKeyboard = false,
  }) async {
    setState(() {
      _error = null;
      _message = '';
    });
    try {
      beforeTask?.call();
      await task();
      if (mounted) {
        setState(() {
          _conversationRevision = widget.controller.conversationVersion;
          _messageRevision = _currentMessageRevision();
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        if (keepKeyboard) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _inputFocusNode.requestFocus();
            }
          });
        }
      }
    }
  }

  Future<void> _runAction(Future<void> Function() task) async {
    setState(() {
      _error = null;
      _message = '';
    });
    try {
      await task();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _clearOptions() {
    setState(() {
      _replyClientMsgNo = '';
      _mentionUserIds = const [];
      _mentionAll = false;
      _burnAfterRead = false;
      _burnSeconds = 0;
    });
  }

  bool _isMessageDeleteEvent(String source) {
    return source == 'burn_after_read_cmd' || source == 'recall_cmd';
  }

  void _scheduleBurnAfterReadForMessages(List<Map<String, Object?>> messages) {
    for (final item in messages) {
      if (_isSelfMessage(item)) {
        continue;
      }
      final clientMsgNo = _value(item, ['client_msg_no']);
      if (clientMsgNo.isEmpty ||
          _burnTriggeredClientMsgNos.contains(clientMsgNo)) {
        continue;
      }
      final burn = _asObjectMap(
        _asObjectMap(item['payload'])['burn_after_read'],
      );
      if (!_boolValue(burn['enabled'])) {
        continue;
      }
      _burnTriggeredClientMsgNos.add(clientMsgNo);
      final seconds = _intValue(burn, ['seconds']);
      Future<void>.delayed(Duration(seconds: seconds > 0 ? seconds : 1), () {
        return _triggerBurnAfterRead(clientMsgNo);
      });
    }
  }

  Future<void> _triggerBurnAfterRead(String clientMsgNo) async {
    if (!mounted ||
        !_messages.any(
          (item) => _value(item, ['client_msg_no']) == clientMsgNo,
        )) {
      return;
    }
    try {
      await widget.controller.burnAfterRead(clientMsgNo);
      await widget.controller.deleteLocalMessageOnly(
        targetClientMsgNo: clientMsgNo,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      if (mounted) {
        setState(() {
          _messages = _messages
              .where((item) => _value(item, ['client_msg_no']) != clientMsgNo)
              .toList(growable: false);
        });
      }
    } catch (error, stackTrace) {
      _burnTriggeredClientMsgNos.remove(clientMsgNo);
      AppLogger.warn(
        'ui',
        'burn after read trigger failed',
        data: {
          'client_msg_no': clientMsgNo,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    }
  }

  bool _isSelfMessage(Map<String, Object?> item) {
    final value = item['is_me'];
    return value == true ||
        value?.toString() == '1' ||
        value?.toString() == 'true';
  }

  String _headerAvatarUrl() {
    for (final item in widget.controller.cachedConversations()) {
      if (_value(item, ['channel_id']) == widget.channelId &&
          _intValue(item, ['channel_type']) == widget.channelType) {
        final avatar = _conversationAvatarUrl(item);
        if (avatar.isNotEmpty) {
          return avatar;
        }
      }
    }
    if (!_isGroup) {
      for (final item in widget.controller.cachedFriends()) {
        final channelId = _friendChannelId(item);
        final userId = _friendUserId(item);
        if (channelId == widget.channelId || userId == _receiverId) {
          final avatar = _friendAvatarUrl(item);
          if (avatar.isNotEmpty) {
            return avatar;
          }
        }
      }
    }
    for (final item in _messages) {
      if (!_isSelfMessage(item)) {
        final avatar = _messageSenderAvatarUrl(item);
        if (avatar.isNotEmpty) {
          return avatar;
        }
      }
    }
    return '';
  }

  String _optionText() {
    final parts = <String>[];
    if (_replyClientMsgNo.isNotEmpty) {
      parts.add('引用 ${_shortNo(_replyClientMsgNo)}');
    }
    if (_mentionAll) {
      parts.add('@所有人');
    }
    if (_mentionUserIds.isNotEmpty) {
      parts.add('@${_mentionUserIds.join(',')}');
    }
    if (_burnAfterRead) {
      parts.add(_burnSeconds > 0 ? '阅后即焚 ${_burnSeconds}s' : '阅后即焚');
    }
    return parts.join(' · ');
  }
}

class _ChatToast extends StatefulWidget {
  const _ChatToast({
    required this.text,
    required this.error,
    required this.onDismiss,
    super.key,
  });

  final String text;
  final bool error;
  final VoidCallback onDismiss;

  @override
  State<_ChatToast> createState() => _ChatToastState();
}

class _ChatToastState extends State<_ChatToast> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(_ChatToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.error != widget.error) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    final seconds = widget.text.length > 32 ? 4 : 2;
    _timer = Timer(Duration(seconds: seconds), widget.onDismiss);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: widget.onDismiss,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: widget.error
                  ? const Color(0xffd93025)
                  : const Color(0xe61f2329),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.error ? Icons.error_outline : Icons.check_circle,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
