part of 'package:bim/src/features/home/home_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.controller,
    required this.title,
    required this.channelId,
    required this.groupId,
    required this.channelType,
    this.initialClientMsgNo = '',
    super.key,
  });

  final SessionController controller;
  final String title;
  final String channelId;
  final String groupId;
  final int channelType;
  final String initialClientMsgNo;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

double _chatPanelHeight(BuildContext context) {
  final media = MediaQuery.of(context);
  final viewportHeight = media.size.height;
  final usableHeight =
      viewportHeight - media.viewPadding.top - media.viewPadding.bottom;
  final preferred = BimDimensions.chatToolsPanel + media.viewPadding.bottom;
  final availableLimit = max(
    220.0,
    usableHeight -
        BimDimensions.chatHeader -
        BimDimensions.composerControl -
        92,
  );
  final upper = min(BimDimensions.chatToolsPanelMax, availableLimit);
  final compactMin = viewportHeight < 560
      ? 268.0
      : BimDimensions.chatToolsPanel;
  final lower = min(compactMin, upper);
  return preferred.clamp(lower, upper).toDouble();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const int _messageUiLimit = 1000;

  final _chatStackKey = GlobalKey();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final Map<String, GlobalKey> _messageRowKeys = <String, GlobalKey>{};
  bool _toolsOpen = false;
  bool _emojiOpen = false;
  int _emojiInitialTab = 0;
  bool _voiceMode = false;
  bool _voiceRecording = false;
  bool _voiceStartPending = false;
  bool _voiceStopAfterStart = false;
  bool _voiceCancelAfterStart = false;
  bool _burnAfterRead = false;
  bool _peerBurnAfterRead = false;
  bool _mentionAll = false;
  int _burnSeconds = 0;
  int _peerBurnSeconds = 0;
  DateTime? _voiceRecordStartedAt;
  String _voiceRecordPath = '';
  List<String> _mentionUserIds = const [];
  String _replyClientMsgNo = '';
  Map<String, Object?> _replyQuote = const {};
  String _selectedClientMsgNo = '';
  Map<String, Object?> _selectedPayload = const {};
  Map<String, Object?> _selectedMessage = const {};
  Offset? _selectedMenuAnchor;
  Map<String, Object?> _groupMuteState = const {};
  String? _error;
  String _message = '';
  List<Map<String, Object?>> _messages = const [];
  bool _messagesLoading = true;
  bool _historyLoadingSlow = false;
  Timer? _historyLoadingTimer;
  int _messageLoadToken = 0;
  Future<List<Map<String, Object?>>>? _runningMessageLoad;
  String _runningMessageLoadKey = '';
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
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  final Set<String> _burnTriggeredClientMsgNos = <String>{};
  final Map<String, int> _burnRetryAttempts = <String, int>{};
  final Set<String> _receivingRedPacketIds = <String>{};
  final Set<String> _receivingTransferIds = <String>{};
  String _highlightedMessageKey = '';
  String _pendingInitialClientMsgNo = '';
  bool _initialClientMsgHandled = false;
  bool _initialClientMsgRevealed = false;
  Timer? _quoteHighlightTimer;

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
    _pendingInitialClientMsgNo = widget.initialClientMsgNo.trim();
    _channelInvalid = widget.controller.isChannelInvalid(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    _hydrateCachedMessagesForFirstFrame();
    widget.controller.addListener(_onControllerChanged);
    _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
    _presenceSub = widget.controller.presenceEvents.listen(_onPresenceEvent);
    _inputFocusNode.addListener(_onInputFocusChanged);
    _scrollController.addListener(_onMessageListScrolled);
    unawaited(
      widget.controller.openConversation(
        channelId: widget.channelId,
        channelType: widget.channelType,
      ),
    );
    _loadMessagesIntoState(showLoading: _messages.isEmpty);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tryRevealInitialMessage(source: 'first_frame');
      }
    });
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed && !_channelInvalid) {
      unawaited(
        widget.controller.openConversation(
          channelId: widget.channelId,
          channelType: widget.channelType,
        ),
      );
      _scheduleVisibleRead(source: 'lifecycle_resumed');
    }
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
    _clearSelectedMessageMenu();
    if (_toolsOpen || _emojiOpen || _voiceMode) {
      setState(() {
        _toolsOpen = false;
        _emojiOpen = false;
        _voiceMode = false;
      });
    }
    if (_isNearBottom()) {
      _stickToBottomDuringKeyboard();
    }
  }

  void _onMessageListScrolled() {
    if (_selectedClientMsgNo.isNotEmpty && mounted) {
      _clearSelectedMessageMenu();
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
      _historyLoadingSlow = false;
      _historyLoadingTimer?.cancel();
      _runningMessageLoad = null;
      _runningMessageLoadKey = '';
      _messageRowKeys.clear();
      _highlightedMessageKey = '';
      _pendingInitialClientMsgNo = widget.initialClientMsgNo.trim();
      _initialClientMsgHandled = false;
      _initialClientMsgRevealed = false;
      _quoteHighlightTimer?.cancel();
      _clearSelectedMessageMenu();
      unawaited(_cancelVoiceRecording(silent: true));
      _voiceMode = false;
      _didInitialScroll = false;
      _burnTriggeredClientMsgNos.clear();
      _burnRetryAttempts.clear();
      _receivingRedPacketIds.clear();
      _receivingTransferIds.clear();
      _groupMuteState = const {};
      _peerBurnAfterRead = false;
      _peerBurnSeconds = 0;
      _peerOnline = false;
      _onlineStatusLoading = false;
      _channelInvalid = widget.controller.isChannelInvalid(
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _groupMemberCount = null;
      _groupOnlineCount = null;
      _groupPresenceLoading = false;
      _hydrateCachedMessagesForFirstFrame();
      unawaited(
        widget.controller.openConversation(
          channelId: widget.channelId,
          channelType: widget.channelType,
        ),
      );
      _loadMessagesIntoState(showLoading: _messages.isEmpty);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _tryRevealInitialMessage(source: 'channel_changed_first_frame');
        }
      });
      _refreshGroupMuteState();
      _refreshPeerOnlineStatus();
      if (_isGroup && !_channelInvalid) {
        unawaited(_loadGroupMuteStatus());
        unawaited(_refreshGroupPresence());
      }
    } else if (oldWidget.initialClientMsgNo != widget.initialClientMsgNo) {
      _pendingInitialClientMsgNo = widget.initialClientMsgNo.trim();
      _initialClientMsgHandled = false;
      _initialClientMsgRevealed = false;
      _tryRevealInitialMessage(source: 'initial_client_msg_changed');
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
        _historyLoadingSlow = false;
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
    if (event.source == 'burn_after_read_state_cmd') {
      _applyPeerBurnAfterReadState(event.message);
      return;
    }
    final shouldStickToBottom = _shouldAutoScrollForMessage(event);
    final revealRequested =
        _pendingInitialClientMsgNo.isNotEmpty && !_initialClientMsgHandled;
    setState(() {
      if (_isChannelInvalidEvent(event.source)) {
        _channelInvalid = true;
        _messages = const [];
        _messagesLoading = false;
        _groupPresenceLoading = false;
        _groupMuteState = const {};
        _messageRowKeys.clear();
        _highlightedMessageKey = '';
      } else if (_isMessageDeleteEvent(event.source)) {
        final target = _value(event.message, ['client_msg_no']);
        _messages = _messages
            .where((item) => _value(item, ['client_msg_no']) != target)
            .toList(growable: false);
        _pruneMessageRowKeys(_messages);
      } else {
        _messages = _mergeMessageList(
          _messages,
          event.message,
          limit: _messageUiLimit,
        );
        _pruneMessageRowKeys(_messages);
      }
      _messagesLoading = false;
      _messageRevision = _currentMessageRevision();
      _conversationRevision = widget.controller.conversationVersion;
    });
    _tryRevealInitialMessage(source: 'message_event');
    if (shouldStickToBottom && !revealRequested && !_initialClientMsgRevealed) {
      _scrollToBottom(animated: event.source != 'send_local');
    }
    _scheduleBurnAfterReadForMessages(_messages);
    if (!_channelInvalid) {
      _scheduleVisibleRead(source: 'message_event');
    }
  }

  void _applyPeerBurnAfterReadState(Map<String, Object?> message) {
    final payload = _asObjectMap(message['payload']);
    final senderId = _value(payload, ['sender_id', 'from_id', 'user_id']);
    final senderUid = _value(payload, ['sender_uid', 'from_uid']);
    final currentUserId = widget.controller.session?.userId.toString() ?? '';
    final currentUid = widget.controller.session?.chat?.uid ?? '';
    if ((senderId.isNotEmpty && senderId == currentUserId) ||
        (senderUid.isNotEmpty && senderUid == currentUid)) {
      return;
    }
    final enabled = _boolValue(payload['enabled']);
    final seconds = _intValue(payload, ['seconds']);
    setState(() {
      _peerBurnAfterRead = enabled;
      _peerBurnSeconds = enabled ? seconds : 0;
      _message = enabled
          ? (seconds > 0 ? '对方已开启阅后即焚 ${seconds}s' : '对方已开启阅后即焚')
          : '对方已关闭阅后即焚';
      _error = null;
    });
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
    final key = '${widget.channelType}:${widget.channelId}:${widget.groupId}';
    final running = _runningMessageLoad;
    if (running != null && _runningMessageLoadKey == key) {
      AppLogger.info(
        'ui',
        'reuse running chat messages load',
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'group_id': widget.groupId,
          'load_key': key,
        },
      );
      return running;
    }
    final future = AppLogger.measure(
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
    _runningMessageLoad = future;
    _runningMessageLoadKey = key;
    return future.whenComplete(() {
      if (identical(_runningMessageLoad, future)) {
        _runningMessageLoad = null;
        _runningMessageLoadKey = '';
      }
    });
  }

  void _hydrateCachedMessagesForFirstFrame() {
    if (_channelInvalid) {
      _messages = const [];
      _messagesLoading = false;
      return;
    }
    final cached = widget.controller.cachedLocalMessages(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    if (cached.isEmpty) {
      _messages = const [];
      _messagesLoading = true;
      _historyLoadingSlow = false;
      AppLogger.info(
        'ui',
        'chat first frame has no cached messages',
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
        },
      );
      return;
    }
    _messages = cached;
    _messagesLoading = false;
    _historyLoadingSlow = false;
    _didInitialScroll = true;
    _pruneMessageRowKeys(cached);
    AppLogger.info(
      'ui',
      'chat first frame hydrated from cache',
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'count': cached.length,
        'last_message': _chatUiMessageSummary(cached.last),
      },
    );
  }

  Future<void> _loadMessagesIntoState({required bool showLoading}) async {
    final token = ++_messageLoadToken;
    final wasNearBottom = _isNearBottom();
    final beforeCount = _messages.length;
    AppLogger.info(
      'ui',
      'chat messages load state start',
      data: {
        'token': token,
        'show_loading': showLoading,
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'group_id': widget.groupId,
        'before_count': beforeCount,
        'was_near_bottom': wasNearBottom,
        'did_initial_scroll': _didInitialScroll,
      },
    );
    if (showLoading && mounted) {
      setState(() {
        _messagesLoading = true;
        _historyLoadingSlow = false;
        _error = null;
      });
      _startHistoryLoadingTimer();
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
      AppLogger.info(
        'ui',
        'chat messages load state apply',
        data: {
          'token': token,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'group_id': widget.groupId,
          'loaded_count': messages.length,
          'before_count': beforeCount,
          'after_count': nextMessages.length,
          'invalid_channel': invalid,
          'show_loading': showLoading,
          'was_near_bottom': wasNearBottom,
          'first_message': _chatUiMessageSummary(
            nextMessages.isEmpty
                ? const <String, Object?>{}
                : nextMessages.first,
          ),
          'last_message': _chatUiMessageSummary(
            nextMessages.isEmpty
                ? const <String, Object?>{}
                : nextMessages.last,
          ),
        },
      );
      setState(() {
        _channelInvalid = invalid;
        _messages = nextMessages;
        _messagesLoading = false;
        _historyLoadingSlow = false;
        _pruneMessageRowKeys(nextMessages);
      });
      _historyLoadingTimer?.cancel();
      _scheduleBurnAfterReadForMessages(nextMessages);
      final revealRequested =
          _pendingInitialClientMsgNo.isNotEmpty && !_initialClientMsgHandled;
      _tryRevealInitialMessage(source: 'messages_loaded');
      final suppressAutoBottom = revealRequested || _initialClientMsgRevealed;
      if (showLoading && !_didInitialScroll) {
        _didInitialScroll = true;
        if (!suppressAutoBottom) {
          _scrollToBottom(animated: false);
        }
      } else if (wasNearBottom) {
        if (!suppressAutoBottom) {
          _scrollToBottom(animated: false);
        }
      }
      if (!invalid) {
        _scheduleVisibleRead(source: 'messages_loaded');
      }
    } catch (error) {
      if (!mounted || token != _messageLoadToken) {
        AppLogger.info(
          'ui',
          'chat messages load error ignored',
          data: {
            'token': token,
            'current_token': _messageLoadToken,
            'mounted': mounted,
            'error': error.toString(),
          },
        );
        return;
      }
      if (_isMissingGroupError(error)) {
        _markChannelInvalid();
        return;
      }
      setState(() {
        _messagesLoading = false;
        _historyLoadingSlow = false;
        _error = error.toString();
      });
      _historyLoadingTimer?.cancel();
    }
  }

  void _startHistoryLoadingTimer() {
    _historyLoadingTimer?.cancel();
    _historyLoadingTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || !_messagesLoading || _messages.isNotEmpty) {
        return;
      }
      setState(() => _historyLoadingSlow = true);
    });
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

  Map<String, Object?> _chatUiMessageSummary(Map<String, Object?> message) {
    if (message.isEmpty) {
      return const {'empty': true};
    }
    final payload = _asObjectMap(message['payload']);
    final content = _value(message, [
      'content',
      'text',
    ], fallback: _value(payload, ['content', 'text']));
    return {
      'client_msg_no': _value(message, [
        'client_msg_no',
      ], fallback: _value(payload, ['client_msg_no'])),
      'message_id': _value(message, ['message_id', 'message_idstr']),
      'message_seq': _intValue(message, ['message_seq']),
      'content_type': _value(message, [
        'content_type',
      ], fallback: _value(payload, ['content_type'])),
      'status': _value(message, ['status']),
      'is_me': message['is_me'] == true,
      'content_len': content.length,
      if (content.isNotEmpty)
        'content_preview': content.substring(0, min(120, content.length)),
      'payload_keys': payload.keys.take(80).toList(growable: false),
    };
  }

  void _markChannelInvalid() {
    _historyLoadingTimer?.cancel();
    if (!mounted) {
      _channelInvalid = true;
      _historyLoadingSlow = false;
      _messageRowKeys.clear();
      _highlightedMessageKey = '';
      return;
    }
    setState(() {
      _channelInvalid = true;
      _messages = const [];
      _messagesLoading = false;
      _historyLoadingSlow = false;
      _groupPresenceLoading = false;
      _groupMuteState = const {};
      _messageRowKeys.clear();
      _highlightedMessageKey = '';
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
    _historyLoadingTimer?.cancel();
    _quoteHighlightTimer?.cancel();
    unawaited(_disposeVoiceRecorderQuietly());
    _scrollController.removeListener(_onMessageListScrolled);
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
    final lookupKey = _messageLookupKey(item);
    if (lookupKey.isNotEmpty) {
      return lookupKey;
    }
    final timestamp = _value(item, ['timestamp', 'create_time']);
    final sender = _value(item, ['from_uid', 'sender_uid', 'uid']);
    return 'local:$index:$timestamp:$sender:${_messageContentType(item)}';
  }

  String _messageLookupKey(Map<String, Object?> item) {
    final payload = _asObjectMap(item['payload']);
    final clientMsgNo = _value(item, [
      'client_msg_no',
    ], fallback: _value(payload, ['client_msg_no']));
    if (clientMsgNo.isNotEmpty) {
      return 'client:$clientMsgNo';
    }
    final messageId = _value(item, [
      'message_id',
      'message_idstr',
      'msg_id',
      'id',
    ], fallback: _value(payload, ['message_id', 'message_idstr', 'msg_id']));
    if (messageId.isNotEmpty) {
      return 'id:$messageId';
    }
    var messageSeq = _intValue(item, ['message_seq']);
    if (messageSeq <= 0) {
      messageSeq = _intValue(payload, ['message_seq']);
    }
    if (messageSeq > 0) {
      return 'seq:$messageSeq';
    }
    return '';
  }

  void _pruneMessageRowKeys(List<Map<String, Object?>> messages) {
    final liveKeys = messages
        .map(_messageLookupKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    _messageRowKeys.removeWhere((key, _) => !liveKeys.contains(key));
    if (_highlightedMessageKey.isNotEmpty &&
        !liveKeys.contains(_highlightedMessageKey)) {
      _highlightedMessageKey = '';
    }
  }

  int _findQuotedMessageIndex(Map<String, Object?> quote) {
    for (var index = _messages.length - 1; index >= 0; index -= 1) {
      final item = _messages[index];
      if (_messageMatchesQuote(item, quote)) {
        return index;
      }
    }
    return -1;
  }

  bool _messageMatchesQuote(
    Map<String, Object?> item,
    Map<String, Object?> quote,
  ) {
    if (!_quoteChannelMatches(item, quote)) {
      return false;
    }
    final itemPayload = _asObjectMap(item['payload']);
    final quotePayload = _asObjectMap(quote['payload']);
    final itemClientMsgNo = _value(item, [
      'client_msg_no',
    ], fallback: _value(itemPayload, ['client_msg_no']));
    final quoteClientMsgNo = _value(
      quote,
      ['client_msg_no', 'quote_client_msg_no', 'reply_client_msg_no'],
      fallback: _value(quotePayload, [
        'client_msg_no',
        'quote_client_msg_no',
        'reply_client_msg_no',
      ]),
    );
    if (itemClientMsgNo.isNotEmpty &&
        quoteClientMsgNo.isNotEmpty &&
        itemClientMsgNo == quoteClientMsgNo) {
      return true;
    }
    final itemMessageId = _value(
      item,
      ['message_id', 'message_idstr', 'msg_id', 'id'],
      fallback: _value(itemPayload, ['message_id', 'message_idstr', 'msg_id']),
    );
    final quoteMessageId = _value(
      quote,
      ['message_id', 'message_idstr', 'root_mid', 'msg_id', 'id'],
      fallback: _value(quotePayload, [
        'message_id',
        'message_idstr',
        'root_mid',
        'msg_id',
      ]),
    );
    if (itemMessageId.isNotEmpty &&
        quoteMessageId.isNotEmpty &&
        itemMessageId == quoteMessageId) {
      return true;
    }
    var itemMessageSeq = _intValue(item, ['message_seq']);
    if (itemMessageSeq <= 0) {
      itemMessageSeq = _intValue(itemPayload, ['message_seq']);
    }
    var quoteMessageSeq = _intValue(quote, ['message_seq']);
    if (quoteMessageSeq <= 0) {
      quoteMessageSeq = _intValue(quotePayload, ['message_seq']);
    }
    return itemMessageSeq > 0 &&
        quoteMessageSeq > 0 &&
        itemMessageSeq == quoteMessageSeq;
  }

  bool _quoteChannelMatches(
    Map<String, Object?> item,
    Map<String, Object?> quote,
  ) {
    final quotePayload = _asObjectMap(quote['payload']);
    final quoteChannelType = _intValue(quote, ['channel_type']);
    final payloadChannelType = _intValue(quotePayload, ['channel_type']);
    final channelType = quoteChannelType > 0
        ? quoteChannelType
        : payloadChannelType;
    if (channelType > 0 && channelType != widget.channelType) {
      return false;
    }
    final itemChannelId = _value(item, [
      'channel_id',
    ], fallback: widget.channelId);
    final quoteChannelId = _value(quote, [
      'channel_id',
    ], fallback: _value(quotePayload, ['channel_id']));
    return quoteChannelId.isEmpty ||
        quoteChannelId == widget.channelId ||
        quoteChannelId == itemChannelId;
  }

  Map<String, Object?> _mergeUiMessage(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final merged = _mergeUiNonEmpty(existing, incoming);
    final existingPayload = _asObjectMap(existing['payload']);
    final incomingPayload = _asObjectMap(incoming['payload']);
    if (existingPayload.isNotEmpty || incomingPayload.isNotEmpty) {
      final payload = _mergeUiNonEmpty(existingPayload, incomingPayload);
      for (final key in [
        'red_packet',
        'transfer',
        'media',
        'receipt',
        'quote',
      ]) {
        final existingNested = _asObjectMap(existingPayload[key]);
        final incomingNested = _asObjectMap(incomingPayload[key]);
        if (existingNested.isNotEmpty || incomingNested.isNotEmpty) {
          payload[key] = _mergeUiNonEmpty(existingNested, incomingNested);
        }
      }
      _preserveUiString(payload, existingPayload, incomingPayload, [
        'client_msg_no',
        'content_type',
        'content',
        'text',
        'file_path',
        'image_path',
        'video_path',
        'url',
        'cover',
        'thumbnail',
        'reply_client_msg_no',
        'quote_client_msg_no',
      ]);
      merged['payload'] = payload;
    }
    _preserveUiPositiveInt(merged, existing, incoming, ['message_seq']);
    _preserveUiString(merged, existing, incoming, [
      'message_id',
      'message_idstr',
      'client_msg_no',
      'content',
      'content_type',
      'timestamp',
      'from_uid',
    ]);
    return merged;
  }

  Map<String, Object?> _mergeUiNonEmpty(
    Map<String, Object?> base,
    Map<String, Object?> overlay,
  ) {
    final merged = Map<String, Object?>.from(base);
    for (final entry in overlay.entries) {
      if (_hasUiValue(entry.value)) {
        merged[entry.key] = entry.value;
      } else {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return merged;
  }

  bool _hasUiValue(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is Map || value is Iterable) {
      return true;
    }
    return value.toString().trim().isNotEmpty;
  }

  void _preserveUiPositiveInt(
    Map<String, Object?> target,
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
    List<String> keys,
  ) {
    for (final key in keys) {
      final existingValue = _intValue(existing, [key]);
      final incomingValue = _intValue(incoming, [key]);
      if (existingValue > 0 && incomingValue <= 0) {
        target[key] = existingValue;
      }
    }
  }

  void _preserveUiString(
    Map<String, Object?> target,
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
    List<String> keys,
  ) {
    for (final key in keys) {
      final existingValue = _value(existing, [key]);
      final incomingValue = _value(incoming, [key]);
      if (existingValue.isNotEmpty && incomingValue.isEmpty) {
        target[key] = existingValue;
      }
    }
  }

  bool _shouldAutoScrollForMessage(BusinessImMessageEvent event) {
    if (event.message['is_me'] == true || event.source.startsWith('send_')) {
      return true;
    }
    return _isNearBottom();
  }

  void _scheduleVisibleRead({required String source}) {
    if (_lifecycleState != AppLifecycleState.resumed ||
        _channelInvalid ||
        _messagesLoading) {
      AppLogger.info(
        'ui',
        'chat visible read deferred',
        data: {
          'source': source,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'lifecycle': _lifecycleState.name,
          'invalid_channel': _channelInvalid,
          'messages_loading': _messagesLoading,
        },
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _lifecycleState != AppLifecycleState.resumed ||
          _channelInvalid ||
          _messagesLoading) {
        return;
      }
      unawaited(
        widget.controller
            .markConversationVisibleRead(
              channelId: widget.channelId,
              channelType: widget.channelType,
            )
            .catchError((Object error, StackTrace stackTrace) {
              AppLogger.warn(
                'ui',
                'mark visible read failed',
                data: {
                  'source': source,
                  'channel_id': widget.channelId,
                  'channel_type': widget.channelType,
                  'error': error.toString(),
                  'stack': stackTrace.toString(),
                },
              );
            }),
      );
    });
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

  int _findMessageIndexByClientMsgNo(String clientMsgNo) {
    if (clientMsgNo.isEmpty) {
      return -1;
    }
    for (var index = _messages.length - 1; index >= 0; index -= 1) {
      final item = _messages[index];
      final payload = _asObjectMap(item['payload']);
      final itemClientMsgNo = _value(item, [
        'client_msg_no',
      ], fallback: _value(payload, ['client_msg_no']));
      if (itemClientMsgNo == clientMsgNo) {
        return index;
      }
    }
    return -1;
  }

  void _tryRevealInitialMessage({required String source}) {
    final clientMsgNo = _pendingInitialClientMsgNo;
    if (_initialClientMsgHandled ||
        clientMsgNo.isEmpty ||
        _messagesLoading ||
        _messages.isEmpty) {
      return;
    }
    final messageIndex = _findMessageIndexByClientMsgNo(clientMsgNo);
    if (messageIndex < 0) {
      _initialClientMsgHandled = true;
      _pendingInitialClientMsgNo = '';
      AppLogger.warn(
        'ui',
        'initial notification message not found in chat',
        data: {
          'source': source,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': clientMsgNo,
          'message_count': _messages.length,
        },
      );
      if (mounted) {
        setState(() {
          _error = null;
          _message = '消息暂时未同步到本地';
        });
      }
      return;
    }
    final target = _messages[messageIndex];
    final targetKey = _messageLookupKey(target);
    if (targetKey.isEmpty) {
      return;
    }
    _initialClientMsgHandled = true;
    _pendingInitialClientMsgNo = '';
    _initialClientMsgRevealed = true;
    AppLogger.info(
      'ui',
      'reveal initial notification message',
      data: {
        'source': source,
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'client_msg_no': clientMsgNo,
        'message_index': messageIndex,
        'target_key': targetKey,
      },
    );
    _highlightMessage(targetKey);
    _scrollQuotedMessageIntoView(targetKey, messageIndex);
  }

  void _jumpToQuotedMessage(Map<String, Object?> quote) {
    final messageIndex = _findQuotedMessageIndex(quote);
    if (messageIndex < 0) {
      AppLogger.warn(
        'ui',
        'quoted message not found in current chat',
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'quote_client_msg_no': _value(quote, [
            'client_msg_no',
            'quote_client_msg_no',
            'reply_client_msg_no',
          ]),
          'quote_message_id': _value(quote, [
            'message_id',
            'message_idstr',
            'root_mid',
            'msg_id',
            'id',
          ]),
          'quote_message_seq': _intValue(quote, ['message_seq']),
          'message_count': _messages.length,
        },
      );
      if (mounted) {
        setState(() {
          _error = null;
          _message = '原消息不在当前聊天记录中';
        });
      }
      return;
    }
    final target = _messages[messageIndex];
    final targetKey = _messageLookupKey(target);
    if (targetKey.isEmpty) {
      AppLogger.warn(
        'ui',
        'quoted message has no stable lookup key',
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'message_index': messageIndex,
          'message': _chatUiMessageSummary(target),
        },
      );
      return;
    }
    AppLogger.info(
      'ui',
      'jump to quoted message',
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'message_index': messageIndex,
        'target_key': targetKey,
      },
    );
    _highlightMessage(targetKey);
    _scrollQuotedMessageIntoView(targetKey, messageIndex);
  }

  void _highlightMessage(String targetKey) {
    _quoteHighlightTimer?.cancel();
    setState(() {
      _highlightedMessageKey = targetKey;
      _error = null;
      _message = '';
    });
    _quoteHighlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (!mounted || _highlightedMessageKey != targetKey) {
        return;
      }
      setState(() => _highlightedMessageKey = '');
    });
  }

  void _scrollQuotedMessageIntoView(String targetKey, int messageIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      if (_ensureMessageVisible(targetKey)) {
        return;
      }
      await _scrollNearMessage(messageIndex);
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_ensureMessageVisible(targetKey)) {
          AppLogger.warn(
            'ui',
            'quoted message visible context unavailable after scroll',
            data: {
              'channel_id': widget.channelId,
              'channel_type': widget.channelType,
              'target_key': targetKey,
              'message_index': messageIndex,
              'message_count': _messages.length,
            },
          );
        }
      });
    });
  }

  bool _ensureMessageVisible(String targetKey) {
    final targetContext = _messageRowKeys[targetKey]?.currentContext;
    if (targetContext == null) {
      return false;
    }
    unawaited(
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.36,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      ),
    );
    return true;
  }

  Future<void> _scrollNearMessage(int messageIndex) async {
    if (!_scrollController.hasClients || _messages.length <= 1) {
      return;
    }
    final position = _scrollController.position;
    final builderIndex = _messages.length - 1 - messageIndex;
    final ratio = builderIndex / max(1, _messages.length - 1);
    final targetOffset =
        (position.minScrollExtent +
                (position.maxScrollExtent - position.minScrollExtent) * ratio)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    if ((position.pixels - targetOffset).abs() < 1) {
      return;
    }
    try {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } on Object catch (error) {
      AppLogger.warn(
        'ui',
        'scroll near quoted message failed',
        data: {'error': error.toString(), 'message_index': messageIndex},
      );
    }
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
    setState(() {
      _toolsOpen = opening;
      if (opening) {
        _emojiOpen = false;
        _voiceMode = false;
      }
    });
    if (!opening) {
      _scrollToBottom(animated: false);
    }
  }

  void _toggleEmojiPanel({int initialTab = 0}) {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final opening = !_emojiOpen || _emojiInitialTab != initialTab;
    if (opening) {
      FocusScope.of(context).unfocus();
    }
    _clearSelectedMessageMenu();
    setState(() {
      _emojiInitialTab = initialTab;
      _emojiOpen = opening;
      if (_emojiOpen) {
        _toolsOpen = false;
        _voiceMode = false;
      }
      _message = '';
      _error = null;
    });
    if (!opening) {
      _scrollToBottom(animated: false);
    }
  }

  void _toggleVoiceMode() {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    FocusScope.of(context).unfocus();
    _clearSelectedMessageMenu();
    setState(() {
      _voiceMode = !_voiceMode;
      _toolsOpen = false;
      _emojiOpen = false;
      _message = '';
      _error = null;
    });
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
                  key: _chatStackKey,
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
                          onVoiceCall: () => _startLiveKitCall('audio'),
                          onVideoCall: () => _startLiveKitCall('video'),
                        ),
                        if (_replyQuote.isNotEmpty ||
                            _burnAfterRead ||
                            _peerBurnAfterRead ||
                            _mentionAll ||
                            _mentionUserIds.isNotEmpty)
                          _ChatOptionBar(
                            text: _optionText(),
                            onClear: _clearOptions,
                          ),
                        Expanded(
                          child: _messagesLoading && _messages.isEmpty
                              ? _ChatHistoryLoadingState(
                                  slow: _historyLoadingSlow,
                                  isGroup: _isGroup,
                                )
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
                                    final lookupKey = _messageLookupKey(item);
                                    final rowKey = lookupKey.isEmpty
                                        ? null
                                        : _messageRowKeys.putIfAbsent(
                                            lookupKey,
                                            () => GlobalKey(),
                                          );
                                    final row = _MessageRow(
                                      key: ValueKey('row:$stableKey'),
                                      item: item,
                                      showSenderName: _isGroup,
                                      currentUserAvatarUrl:
                                          widget.controller.session?.avatar ??
                                          '',
                                      highlighted:
                                          lookupKey.isNotEmpty &&
                                          lookupKey == _highlightedMessageKey,
                                      onLongPressStart: (details) =>
                                          _selectMessage(
                                            item,
                                            details.globalPosition,
                                          ),
                                      onTap: _messageTapHandler(item),
                                      onQuoteTap: _jumpToQuotedMessage,
                                      redPacketReceiving: _redPacketIsReceiving(
                                        item,
                                      ),
                                      onRetry: () => _retryMessage(item),
                                    );
                                    return Column(
                                      key: ValueKey(stableKey),
                                      children: [
                                        if (showTime)
                                          _TimeDivider(
                                            text: _messageTimeLabel(item),
                                          ),
                                        if (rowKey == null)
                                          row
                                        else
                                          KeyedSubtree(key: rowKey, child: row),
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
                          emojiOpen: _emojiOpen,
                          voiceMode: _voiceMode,
                          recording: _voiceRecording,
                          onVoice: _toggleVoiceMode,
                          onVoiceRecordStart: () =>
                              unawaited(_startVoiceRecording()),
                          onVoiceRecordEnd: () =>
                              unawaited(_finishVoiceRecording()),
                          onVoiceRecordCancel: () =>
                              unawaited(_cancelVoiceRecording()),
                          onEmoji: _toggleEmojiPanel,
                          onTools: _toggleTools,
                          onSend: _sendText,
                          onContentInserted: _handleKeyboardInsertedContent,
                        ),
                        if (_emojiOpen || _toolsOpen)
                          Builder(
                            builder: (context) {
                              final panelHeight = _chatPanelHeight(context);
                              if (_emojiOpen) {
                                return _EmojiPanel(
                                  key: ValueKey(_emojiInitialTab),
                                  controller: widget.controller,
                                  height: panelHeight,
                                  initialTab: _emojiInitialTab,
                                  onSelected: (payload) =>
                                      unawaited(_sendEmoji(payload)),
                                );
                              }
                              return _ChatToolsPanel(
                                height: panelHeight,
                                isGroup: _isGroup,
                                onTextOption: _openTextOptions,
                                onVoiceInput: _toggleVoiceMode,
                                onImage: () =>
                                    _sendMedia(ChatContentTypes.image),
                                onEmoji: () => _toggleEmojiPanel(initialTab: 0),
                                onSticker: () =>
                                    _toggleEmojiPanel(initialTab: 1),
                                onVideo: () =>
                                    _sendMedia(ChatContentTypes.video),
                                onFile: () => _sendMedia(ChatContentTypes.file),
                                onContactCard: _sendContactCard,
                                onTransfer: _sendTransfer,
                                onRedPacket: _sendRedPacket,
                                onGroupVoiceCall: () =>
                                    _startLiveKitCall('audio'),
                                onGroupVideoCall: () =>
                                    _startLiveKitCall('video'),
                                onGroupMembers: _isGroup
                                    ? _openGroupMembers
                                    : null,
                              );
                            },
                          ),
                      ],
                    ),
                    if (_selectedClientMsgNo.isNotEmpty &&
                        _selectedMenuAnchor != null)
                      _MessageActionOverlay(
                        anchor: _selectedMenuAnchor!,
                        actions: _selectedMessageActions(),
                        onDismiss: _clearSelectedMessageMenu,
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

  void _selectMessage(Map<String, Object?> item, Offset globalPosition) {
    final clientMsgNo = _value(item, ['client_msg_no']);
    final anchor = _messageMenuAnchor(globalPosition);
    setState(() {
      _selectedClientMsgNo = clientMsgNo;
      _selectedPayload = _asObjectMap(item['payload']);
      _selectedMessage = Map<String, Object?>.from(item);
      _selectedMenuAnchor = anchor;
      _message = '';
      if (clientMsgNo.isEmpty) {
        _selectedMessage = const {};
        _selectedMenuAnchor = null;
      }
    });
  }

  Offset _messageMenuAnchor(Offset globalPosition) {
    final context = _chatStackKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is RenderBox) {
      return renderObject.globalToLocal(globalPosition);
    }
    return globalPosition;
  }

  void _clearSelectedMessageMenu() {
    if (_selectedClientMsgNo.isEmpty &&
        _selectedPayload.isEmpty &&
        _selectedMessage.isEmpty &&
        _selectedMenuAnchor == null) {
      return;
    }
    if (!mounted) {
      _selectedClientMsgNo = '';
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
      return;
    }
    setState(() {
      _selectedClientMsgNo = '';
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
    });
  }

  List<_MessageActionItem> _selectedMessageActions() {
    final item = _selectedMessage;
    if (item.isEmpty) {
      return const [];
    }
    final contentType = _messageContentType(item);
    final paymentLike = _messageActionPaymentLike(contentType);
    final canRecall = item['is_me'] == true && !paymentLike;
    final copyText = _selectedMessageCopyText(item);
    final actions = <_MessageActionItem>[
      if (_canQuoteMessage(item))
        _MessageActionItem(
          label: '引用',
          icon: Icons.reply,
          onTap: _replySelected,
        ),
      if (!paymentLike)
        _MessageActionItem(
          label: '转发',
          icon: Icons.shortcut,
          onTap: _forwardSelected,
        ),
      if (copyText.isNotEmpty)
        _MessageActionItem(label: '复制', icon: Icons.copy, onTap: _copySelected),
      if (_messageCanScanQr(item))
        _MessageActionItem(
          label: '识别二维码',
          icon: Icons.qr_code_scanner,
          onTap: _scanSelectedQr,
        ),
      _MessageActionItem(
        label: '收藏',
        icon: Icons.bookmark_border,
        onTap: _favoriteSelected,
      ),
      if (canRecall)
        _MessageActionItem(
          label: '撤回',
          icon: Icons.undo,
          destructive: true,
          onTap: _recallSelected,
        ),
      _MessageActionItem(
        label: '删除',
        icon: Icons.delete_outline,
        destructive: true,
        onTap: _deleteSelected,
      ),
    ];
    return actions;
  }

  bool _messageActionPaymentLike(String contentType) {
    return contentType == ChatContentTypes.redPacket ||
        contentType == ChatContentTypes.transfer ||
        contentType == ChatContentTypes.redPacketReceived ||
        contentType == ChatContentTypes.transferReceived;
  }

  bool _messageCanScanQr(Map<String, Object?> item) {
    final contentType = _messageContentType(item);
    if (_messageActionPaymentLike(contentType)) {
      return false;
    }
    final media = _ChatMediaItem.fromMessage(item);
    if (media.isImageLike) {
      return media.existingLocalPath.isNotEmpty || media.url.isNotEmpty;
    }
    if (media.isVideo) {
      final payload = _asObjectMap(item['payload']);
      final mediaPayload = _asObjectMap(payload['media']);
      return _qrMediaCoverLocalPath(payload, mediaPayload).isNotEmpty ||
          _qrMediaCoverRemoteUrl(payload, mediaPayload).isNotEmpty;
    }
    if (!media.isFile) {
      return false;
    }
    final mime = media.mime.toLowerCase();
    final imageLike =
        mime.startsWith('image/') ||
        _looksLikeImagePath(media.localPath) ||
        _looksLikeImagePath(media.url);
    return imageLike &&
        (media.existingLocalPath.isNotEmpty || media.url.isNotEmpty);
  }

  Future<void> _scanSelectedQr() async {
    final item = Map<String, Object?>.from(_selectedMessage);
    if (item.isEmpty) {
      return;
    }
    _QrScanImageSource? source;
    setState(() {
      _message = '识别中...';
      _error = null;
      _selectedClientMsgNo = '';
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
    });
    try {
      source = await _qrScanImageSourceFromMessage(item);
      if (source == null || source.path.isEmpty) {
        throw Exception('当前消息没有可识别的二维码图片');
      }
      final raw = await _scanQrRawFromImagePath(source.path);
      if (raw.isEmpty) {
        if (mounted) {
          setState(() {
            _message = '';
            _error = '未识别到二维码';
          });
        }
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _message = '';
        _error = null;
      });
      await _openQrScanResult(
        context: context,
        controller: widget.controller,
        raw: raw,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'chat',
        'scan message qr failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'client_msg_no': _value(item, ['client_msg_no']),
          'content_type': _messageContentType(item),
        },
      );
      if (mounted) {
        setState(() {
          _message = '';
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      final path = source?.path ?? '';
      if (source?.temporary == true && path.isNotEmpty) {
        try {
          await File(path).delete();
        } on Object {
          // 临时识别文件删除失败不影响用户继续操作。
        }
      }
    }
  }

  Future<_QrScanImageSource?> _qrScanImageSourceFromMessage(
    Map<String, Object?> item,
  ) async {
    final payload = _asObjectMap(item['payload']);
    final mediaPayload = _asObjectMap(payload['media']);
    final media = _ChatMediaItem.fromMessage(item);
    if (media.isImageLike ||
        (media.isFile &&
            (media.mime.toLowerCase().startsWith('image/') ||
                _looksLikeImagePath(media.localPath) ||
                _looksLikeImagePath(media.url)))) {
      final local = media.existingLocalPath;
      if (local.isNotEmpty) {
        return _QrScanImageSource(path: local, temporary: false);
      }
      if (media.url.isNotEmpty) {
        return _downloadQrScanImage(media.url);
      }
      return null;
    }
    if (media.isVideo) {
      final coverLocal = _qrMediaCoverLocalPath(payload, mediaPayload);
      if (coverLocal.isNotEmpty) {
        return _QrScanImageSource(path: coverLocal, temporary: false);
      }
      final coverUrl = _qrMediaCoverRemoteUrl(payload, mediaPayload);
      if (coverUrl.isNotEmpty) {
        return _downloadQrScanImage(coverUrl);
      }
    }
    return null;
  }

  String _selectedMessageCopyText(Map<String, Object?> item) {
    final contentType = _messageContentType(item);
    if (contentType != ChatContentTypes.text &&
        contentType != ChatContentTypes.emoji) {
      return '';
    }
    final payload = _asObjectMap(item['payload']);
    return _messageContentText(item, payload).trim();
  }

  void _replySelected() {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    final quote = _quoteSnapshotFromMessage(_selectedMessage);
    if (quote.isEmpty) {
      _clearSelectedMessageMenu();
      return;
    }
    setState(() {
      _replyClientMsgNo = _selectedClientMsgNo;
      _replyQuote = quote;
      _selectedClientMsgNo = '';
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
    });
  }

  Future<void> _copySelected() async {
    final text = _selectedMessageCopyText(_selectedMessage);
    if (text.isEmpty) {
      _clearSelectedMessageMenu();
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    setState(() {
      _message = '已复制';
      _selectedClientMsgNo = '';
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
    });
  }

  void _forwardSelected() {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    setState(() {
      _message = '转发功能待接入';
      _selectedClientMsgNo = '';
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
    });
  }

  void _favoriteSelected() {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    setState(() {
      _message = '收藏功能待接入';
      _selectedClientMsgNo = '';
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
    });
  }

  Future<void> _startLiveKitCall(
    String mediaType, {
    List<String> initialInviteUserIds = const [],
  }) async {
    if (_channelInvalid) {
      setState(() => _message = '当前会话不可用');
      return;
    }
    var inviteUserIds = const <String>[];
    if (_isGroup) {
      final selected = await Navigator.of(context).push<List<String>>(
        MaterialPageRoute<List<String>>(
          builder: (_) => _GroupCallInvitePickerPage(
            controller: widget.controller,
            groupId: _groupId,
            mediaType: mediaType,
            initialSelectedIds: initialInviteUserIds,
          ),
        ),
      );
      if (selected == null) {
        return;
      }
      inviteUserIds = selected;
      if (inviteUserIds.isEmpty) {
        setState(() => _message = '请选择通话成员');
        return;
      }
    }
    final callType = _isGroup ? 'group' : 'private';
    await _push(
      context,
      LiveKitCallPage.create(
        controller: widget.controller,
        callType: callType,
        mediaType: mediaType,
        receiverId: _isGroup ? '' : _receiverId,
        groupId: _isGroup ? _groupId : '',
        title: _isGroup
            ? _chatHeaderTitle()
            : (mediaType == 'video' ? '视频通话' : '语音通话'),
        inviteUserIds: inviteUserIds,
      ),
    );
  }

  Future<void> _redialFromCallMessage(Map<String, Object?> item) async {
    final payload = _asObjectMap(item['payload']);
    final content = _messageContentText(item, payload);
    final meta = _callMessageUi(payload, content: content);
    final currentUserId = widget.controller.session?.userId.toString() ?? '';
    final initialInviteUserIds = _isGroup
        ? _callParticipantUserIds(payload, currentUserId: currentUserId)
        : const <String>[];
    AppLogger.info(
      'ui',
      'call message redial tapped',
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'client_msg_no': _value(item, ['client_msg_no']),
        'media_type': meta.mediaType,
        'call_type': meta.callType,
        'initial_invite_count': initialInviteUserIds.length,
      },
    );
    await _startLiveKitCall(
      meta.mediaType,
      initialInviteUserIds: initialInviteUserIds,
    );
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
    final replyQuote = Map<String, Object?>.from(_replyQuote);
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
          quote: replyQuote,
          burnAfterRead: burnAfterRead,
          burnAfterReadSeconds: burnSeconds,
        );
      },
      beforeTask: () {
        _textController.clear();
        setState(() {
          _replyClientMsgNo = '';
          _replyQuote = const {};
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
    final payloads = _mediaPayloadBatch(data);
    unawaited(_sendMediaPayloads(contentType, payloads));
  }

  Future<void> _sendMediaPayloads(
    String contentType,
    List<Map<String, String>> payloads,
  ) async {
    // Let the picker route finish its pop animation before resolving large
    // photo/video files. This keeps the chat page responsive after tapping send.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    for (final payload in payloads) {
      if (!mounted) {
        return;
      }
      final payloadContentType = _payloadContentType(contentType, payload);
      try {
        await _sendMediaPayload(payloadContentType, payload);
      } catch (error, stackTrace) {
        AppLogger.error(
          'ui',
          'media payload send failed',
          error: error,
          stackTrace: stackTrace,
          data: {
            'content_type': payloadContentType,
            'asset_id': payload['asset_id'] ?? '',
            'file_path': payload['file_path'] ?? '',
          },
        );
      }
    }
  }

  String _payloadContentType(String fallback, Map<String, String> payload) {
    final value = (payload['content_type'] ?? '').trim();
    if (value == ChatContentTypes.image || value == ChatContentTypes.video) {
      return value;
    }
    return fallback;
  }

  Future<void> _handleKeyboardInsertedContent(
    KeyboardInsertedContent content,
  ) async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final mime = content.mimeType.toLowerCase();
    AppLogger.info(
      'ui',
      'keyboard content inserted',
      data: {
        'mime': mime,
        'uri_len': content.uri.length,
        'has_data': content.hasData,
        'data_len': content.data?.length ?? 0,
      },
    );
    var bytes = content.data;
    if ((bytes == null || bytes.isEmpty) && content.uri.isNotEmpty) {
      bytes = await _readKeyboardContentUri(content.uri);
    }
    if (bytes == null || bytes.isEmpty) {
      AppLogger.warn(
        'ui',
        'keyboard content has no readable bytes',
        data: {'mime': mime, 'uri_len': content.uri.length},
      );
      setState(() => _error = '输入法内容无法读取');
      return;
    }
    final normalizedMime = _normalizeKeyboardMime(mime);
    final contentType = ChatContentTypes.image;
    final ext = _keyboardContentExtension(mime);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/bim_keyboard_${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    await file.writeAsBytes(bytes, flush: true);
    final name = file.uri.pathSegments.isEmpty
        ? 'keyboard$ext'
        : file.uri.pathSegments.last;
    await _sendMediaPayload(contentType, <String, String>{
      'file_path': file.path,
      'mime': normalizedMime,
      'name': name,
      'size': bytes.length.toString(),
      'source': 'keyboard',
      'content': '[图片]',
      'media_json': jsonEncode({
        'mime': normalizedMime,
        'name': name,
        'size': bytes.length.toString(),
        'source': 'keyboard',
      }),
    });
  }

  static const MethodChannel _keyboardContentChannel = MethodChannel(
    'bimotc.com/keyboard_content',
  );

  Future<Uint8List?> _readKeyboardContentUri(String uri) async {
    try {
      final bytes = await _keyboardContentChannel.invokeMethod<Uint8List>(
        'readUri',
        {'uri': uri},
      );
      AppLogger.info(
        'ui',
        'keyboard content uri read',
        data: {'uri_len': uri.length, 'data_len': bytes?.length ?? 0},
      );
      return bytes;
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'keyboard content uri read failed',
        data: {
          'uri_len': uri.length,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      return null;
    }
  }

  String _normalizeKeyboardMime(String mime) {
    final normalized = mime.toLowerCase().trim();
    if (normalized.contains('gif')) {
      return 'image/gif';
    }
    if (normalized.contains('webp')) {
      return 'image/webp';
    }
    if (normalized.contains('png')) {
      return 'image/png';
    }
    if (normalized.contains('jpeg') || normalized.contains('jpg')) {
      return 'image/jpeg';
    }
    return 'image/jpeg';
  }

  String _keyboardContentExtension(String mime) {
    if (mime.contains('gif')) {
      return '.gif';
    }
    if (mime.contains('webp')) {
      return '.webp';
    }
    if (mime.contains('png')) {
      return '.png';
    }
    return '.jpg';
  }

  List<Map<String, String>> _mediaPayloadBatch(Map<String, String> data) {
    final batchJson = data['batch_json'];
    if (batchJson == null || batchJson.isEmpty) {
      return [data];
    }
    final decoded = jsonDecode(batchJson);
    if (decoded is! List) {
      return [data];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => item.map(
            (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
          ),
        )
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> _sendMediaPayload(
    String contentType,
    Map<String, String> data,
  ) async {
    final resolvedData = await _resolveMediaPayload(contentType, data);
    final url = resolvedData['url'] ?? '';
    final filePath = resolvedData['file_path'] ?? '';
    final params = Map<String, Object?>.from(resolvedData)
      ..remove('url')
      ..remove('asset_id');
    final mediaJson = resolvedData['media_json'];
    if (mediaJson != null && mediaJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(mediaJson);
        if (decoded is Map) {
          params['media'] = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } on Object catch (error, stackTrace) {
        AppLogger.warn(
          'ui',
          'media json decode failed',
          data: {'error': error.toString(), 'stack': stackTrace.toString()},
        );
      }
      params.remove('media_json');
    }
    if (_replyQuote.isNotEmpty) {
      params['quote'] = Map<String, Object?>.from(_replyQuote);
      params['quote_json'] = jsonEncode(_replyQuote);
      params['quote_client_msg_no'] = _replyClientMsgNo;
      params['reply_client_msg_no'] = _replyClientMsgNo;
    }
    if (_burnAfterRead) {
      params['burn_after_read'] = '1';
      if (_burnSeconds > 0) {
        params['burn_after_read_seconds'] = _burnSeconds.toString();
      }
    }
    await _runSending(
      () async {
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
      },
      beforeTask: () {
        setState(() {
          _replyClientMsgNo = '';
          _replyQuote = const {};
        });
      },
    );
  }

  Future<Map<String, String>> _resolveMediaPayload(
    String contentType,
    Map<String, String> data,
  ) async {
    final assetId = (data['asset_id'] ?? '').trim();
    if (assetId.isEmpty || (data['file_path'] ?? '').isNotEmpty) {
      return data;
    }
    try {
      final asset = await AssetEntity.fromId(assetId);
      if (asset == null) {
        throw const FileSystemException('asset unavailable');
      }
      final resolved = await _mediaAssetPayload(asset, contentType);
      AppLogger.info(
        'ui',
        'media asset resolved for send',
        data: {
          'content_type': contentType,
          'asset_id': assetId,
          'file_path': resolved['file_path'] ?? '',
          'size': resolved['size'] ?? '',
          'mime': resolved['mime'] ?? '',
        },
      );
      return <String, String>{...data, ...resolved, 'asset_id': assetId};
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'media asset resolve failed',
        error: error,
        stackTrace: stackTrace,
        data: {'content_type': contentType, 'asset_id': assetId},
      );
      if (mounted) {
        setState(() => _error = '媒体文件读取失败');
      }
      rethrow;
    }
  }

  Future<void> _sendEmoji(Map<String, String> data) async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    final kind = (data['kind'] ?? ChatContentTypes.emoji).trim();
    if (kind == ChatContentTypes.text) {
      _insertTextAtCursor(data['text'] ?? data['content'] ?? '');
      return;
    }
    final contentType = switch (kind) {
      ChatContentTypes.gif => ChatContentTypes.gif,
      ChatContentTypes.sticker => ChatContentTypes.sticker,
      _ => ChatContentTypes.emoji,
    };
    final emojiId = (data['emoji_id'] ?? '').trim();
    final stickerId = (data['sticker_id'] ?? emojiId).trim();
    final itemId = stickerId.isNotEmpty ? stickerId : emojiId;
    final emojiAsset = (data['emoji_asset'] ?? data['sticker_asset'] ?? '')
        .trim();
    final url = (data['url'] ?? '').trim();
    if (itemId.isEmpty || (emojiAsset.isEmpty && url.isEmpty)) {
      setState(() => _error = '表情数据无效');
      return;
    }
    final packId = (data['pack_id'] ?? 'default').trim();
    final format = (data['format'] ?? '').trim();
    final animated =
        data['animated'] == '1' ||
        data['animated']?.toLowerCase() == 'true' ||
        contentType == ChatContentTypes.gif ||
        format.toLowerCase() == 'gif' ||
        format.toLowerCase() == 'webp';
    final content = switch (contentType) {
      ChatContentTypes.gif => '[GIF]',
      ChatContentTypes.sticker => '[贴纸]',
      _ => '[表情]',
    };
    final params = <String, Object?>{
      'pack_id': packId.isEmpty ? 'default' : packId,
      if (format.isNotEmpty) 'format': format,
      'animated': animated ? '1' : '0',
      if (emojiId.isNotEmpty) 'emoji_id': emojiId,
      'emoji_code': itemId,
      'sticker_id': itemId,
      'emoji_asset': emojiAsset,
      'sticker_asset': emojiAsset,
      if (url.isNotEmpty) 'url': url,
      'content': content,
      'media': {
        'pack_id': packId.isEmpty ? 'default' : packId,
        if (format.isNotEmpty) 'format': format,
        'animated': animated ? 1 : 0,
        if (emojiId.isNotEmpty) 'emoji_id': emojiId,
        'emoji_code': itemId,
        'sticker_id': itemId,
        if (emojiAsset.isNotEmpty) 'emoji_asset': emojiAsset,
        if (emojiAsset.isNotEmpty) 'sticker_asset': emojiAsset,
        if (url.isNotEmpty) 'url': url,
        'asset': emojiAsset,
      },
    };
    if (_replyQuote.isNotEmpty) {
      params['quote'] = Map<String, Object?>.from(_replyQuote);
      params['quote_json'] = jsonEncode(_replyQuote);
      params['quote_client_msg_no'] = _replyClientMsgNo;
      params['reply_client_msg_no'] = _replyClientMsgNo;
    }
    if (_burnAfterRead) {
      params['burn_after_read'] = '1';
      if (_burnSeconds > 0) {
        params['burn_after_read_seconds'] = _burnSeconds.toString();
      }
    }
    AppLogger.info(
      'ui',
      'emoji selected for send',
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'content_type': contentType,
        'emoji_id': emojiId,
        'sticker_id': itemId,
        'animated': animated,
        'emoji_asset': emojiAsset,
        'has_url': url.isNotEmpty,
      },
    );
    await _runSending(
      () async {
        if (_isGroup) {
          await widget.controller.sendGroupMedia(
            groupId: _groupId,
            channelId: widget.channelId,
            contentType: contentType,
            params: params,
          );
        } else {
          await widget.controller.sendPrivateMedia(
            receiverId: _receiverId,
            contentType: contentType,
            params: params,
          );
        }
      },
      beforeTask: () {
        setState(() {
          _replyClientMsgNo = '';
          _replyQuote = const {};
        });
      },
    );
  }

  void _insertTextAtCursor(String text) {
    if (text.isEmpty) {
      return;
    }
    final value = _textController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    final cursor = start + text.length;
    _textController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
    if (!_emojiOpen && !_inputFocusNode.hasFocus) {
      _inputFocusNode.requestFocus();
    }
  }

  Future<void> _startVoiceRecording() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    if (_voiceRecording || _voiceStartPending) {
      return;
    }
    _voiceStartPending = true;
    _voiceStopAfterStart = false;
    _voiceCancelAfterStart = false;
    try {
      final allowed = await _voiceRecorder.hasPermission();
      if (!allowed) {
        _voiceStartPending = false;
        if (mounted) {
          setState(() => _error = '需要麦克风权限');
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/bim_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) {
        await _voiceRecorder.cancel();
        _voiceStartPending = false;
        return;
      }
      if (_voiceCancelAfterStart) {
        await _voiceRecorder.cancel();
        await _deleteTempVoiceFile(path);
        setState(() {
          _voiceStartPending = false;
          _voiceStopAfterStart = false;
          _voiceCancelAfterStart = false;
          _voiceRecording = false;
          _voiceRecordStartedAt = null;
          _voiceRecordPath = '';
          _message = '已取消发送';
        });
        return;
      }
      setState(() {
        _voiceStartPending = false;
        _voiceRecording = true;
        _voiceRecordStartedAt = DateTime.now();
        _voiceRecordPath = path;
        _message = '';
        _error = null;
      });
      if (_voiceStopAfterStart) {
        _voiceStopAfterStart = false;
        unawaited(_finishVoiceRecording());
      }
    } catch (error, stackTrace) {
      _voiceStartPending = false;
      _voiceStopAfterStart = false;
      _voiceCancelAfterStart = false;
      AppLogger.error(
        'ui',
        'voice recording start failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _error = '录音启动失败');
      }
    }
  }

  Future<void> _finishVoiceRecording() async {
    if (_voiceStartPending && !_voiceRecording) {
      _voiceStopAfterStart = true;
      return;
    }
    if (!_voiceRecording) {
      return;
    }
    final startedAt = _voiceRecordStartedAt;
    final fallbackPath = _voiceRecordPath;
    try {
      final path = await _voiceRecorder.stop();
      final elapsedMs = startedAt == null
          ? 0
          : DateTime.now().difference(startedAt).inMilliseconds;
      if (mounted) {
        setState(() {
          _voiceRecording = false;
          _voiceStartPending = false;
          _voiceStopAfterStart = false;
          _voiceCancelAfterStart = false;
          _voiceRecordStartedAt = null;
          _voiceRecordPath = '';
        });
      }
      final filePath = path?.isNotEmpty == true ? path! : fallbackPath;
      if (elapsedMs < 700) {
        await _deleteTempVoiceFile(filePath);
        if (mounted) {
          setState(() => _message = '说话时间太短');
        }
        return;
      }
      await _sendRecordedVoice(filePath, max(1, (elapsedMs / 1000).round()));
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'voice recording finish failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _voiceRecording = false;
          _voiceStartPending = false;
          _voiceStopAfterStart = false;
          _voiceCancelAfterStart = false;
          _voiceRecordStartedAt = null;
          _voiceRecordPath = '';
          _error = '录音发送失败';
        });
      }
    }
  }

  Future<void> _cancelVoiceRecording({bool silent = false}) async {
    if (_voiceStartPending && !_voiceRecording) {
      _voiceCancelAfterStart = true;
      return;
    }
    if (!_voiceRecording && _voiceRecordPath.isEmpty) {
      return;
    }
    final path = _voiceRecordPath;
    try {
      if (_voiceRecording) {
        await _voiceRecorder.cancel();
      }
      await _deleteTempVoiceFile(path);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'voice recording cancel failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
    if (mounted) {
      setState(() {
        _voiceRecording = false;
        _voiceStartPending = false;
        _voiceStopAfterStart = false;
        _voiceCancelAfterStart = false;
        _voiceRecordStartedAt = null;
        _voiceRecordPath = '';
        if (!silent) {
          _message = '已取消发送';
        }
      });
    }
  }

  Future<void> _disposeVoiceRecorderQuietly() async {
    final path = _voiceRecordPath;
    try {
      if (_voiceRecording) {
        await _voiceRecorder.cancel();
      }
      await _deleteTempVoiceFile(path);
      await _voiceRecorder.dispose();
      _voiceRecording = false;
      _voiceStartPending = false;
      _voiceStopAfterStart = false;
      _voiceCancelAfterStart = false;
      _voiceRecordStartedAt = null;
      _voiceRecordPath = '';
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'voice recorder dispose failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  Future<void> _deleteTempVoiceFile(String path) async {
    if (path.isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _sendRecordedVoice(String filePath, int durationSeconds) async {
    if (filePath.isEmpty || !await File(filePath).exists()) {
      if (mounted) {
        setState(() => _error = '语音文件不存在');
      }
      return;
    }
    final file = File(filePath);
    final size = await file.length();
    final params = <String, Object?>{
      'duration': durationSeconds.toString(),
      'name': _fileName(filePath),
      'mime': _voiceMimeFromPath(filePath),
      'size': size.toString(),
      'file_path': filePath,
      'voice_url': filePath,
      'audio_url': filePath,
      'media': {
        'duration': durationSeconds,
        'name': _fileName(filePath),
        'mime': _voiceMimeFromPath(filePath),
        'size': size,
        'file_path': filePath,
        'voice_url': filePath,
        'audio_url': filePath,
      },
    };
    if (_replyQuote.isNotEmpty) {
      params['quote'] = Map<String, Object?>.from(_replyQuote);
      params['quote_json'] = jsonEncode(_replyQuote);
      params['quote_client_msg_no'] = _replyClientMsgNo;
      params['reply_client_msg_no'] = _replyClientMsgNo;
    }
    if (_burnAfterRead) {
      params['burn_after_read'] = '1';
      if (_burnSeconds > 0) {
        params['burn_after_read_seconds'] = _burnSeconds.toString();
      }
    }
    await _runSending(
      () async {
        if (_isGroup) {
          await widget.controller.sendGroupMedia(
            groupId: _groupId,
            channelId: widget.channelId,
            contentType: ChatContentTypes.voice,
            filePath: filePath,
            params: params,
          );
        } else {
          await widget.controller.sendPrivateMedia(
            receiverId: _receiverId,
            contentType: ChatContentTypes.voice,
            filePath: filePath,
            params: params,
          );
        }
      },
      beforeTask: () {
        setState(() {
          _replyClientMsgNo = '';
          _replyQuote = const {};
        });
      },
    );
  }

  String _voiceMimeFromPath(String filePath) {
    final mime = _mimeFromPath(filePath, ChatContentTypes.voice);
    return mime == 'audio/*' ? 'audio/mp4' : mime;
  }

  Future<Map<String, String>?> _selectMediaPayload(String contentType) {
    if (contentType == ChatContentTypes.voice) {
      setState(() => _message = '请长按录音发送语音');
      return Future.value(null);
    }
    if (contentType == ChatContentTypes.emoji) {
      _toggleEmojiPanel(initialTab: 0);
      return Future.value(null);
    }
    if (contentType == ChatContentTypes.sticker ||
        contentType == ChatContentTypes.gif) {
      _toggleEmojiPanel(initialTab: 1);
      return Future.value(null);
    }
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
    final card = await Navigator.of(context).push<Map<String, Object?>>(
      MaterialPageRoute(
        builder: (_) => _ContactCardPickerPage(controller: widget.controller),
      ),
    );
    if (card == null || !mounted) {
      return;
    }
    final cardUserId = _value(card, ['card_user_id']);
    if (cardUserId.isEmpty) {
      setState(() => _error = '名片用户不能为空');
      return;
    }
    if (!_isCurrentFriendCard(cardUserId)) {
      setState(() => _error = '只能发送自己的好友名片');
      return;
    }
    final params = <String, Object?>{...card};
    if (_replyQuote.isNotEmpty) {
      params['quote'] = Map<String, Object?>.from(_replyQuote);
      params['quote_json'] = jsonEncode(_replyQuote);
      params['quote_client_msg_no'] = _replyClientMsgNo;
      params['reply_client_msg_no'] = _replyClientMsgNo;
    }
    await _runSending(
      () async {
        if (_isGroup) {
          await widget.controller.sendGroupContactCard(
            groupId: _groupId,
            channelId: widget.channelId,
            cardUserId: cardUserId,
            params: params,
          );
        } else {
          await widget.controller.sendPrivateContactCard(
            receiverId: _receiverId,
            cardUserId: cardUserId,
            params: params,
          );
        }
      },
      beforeTask: () {
        setState(() {
          _replyClientMsgNo = '';
          _replyQuote = const {};
        });
      },
    );
  }

  bool _isCurrentFriendCard(String cardUserId) {
    if (cardUserId.isEmpty) {
      return false;
    }
    final friends = widget.controller.cachedFriends(allowDisk: true);
    return friends.any((friend) => _friendUserId(friend) == cardUserId);
  }

  VoidCallback? _messageTapHandler(Map<String, Object?> item) {
    final contentType = _messageContentType(item);
    if (contentType == ChatContentTypes.redPacket) {
      return () => _openRedPacketDetail(item);
    }
    if (contentType == ChatContentTypes.transfer) {
      return () => _openTransferDetail(item);
    }
    if (contentType == ChatContentTypes.call) {
      return () => _redialFromCallMessage(item);
    }
    final payload = _asObjectMap(item['payload']);
    if (_messageRendersAsMedia(contentType, payload) ||
        contentType == ChatContentTypes.file) {
      return () => _openMediaMessage(item);
    }
    return null;
  }

  Future<void> _openRedPacketDetail(Map<String, Object?> item) async {
    final payload = _asObjectMap(item['payload']);
    final redPacketId = _redPacketReceiveId(payload);
    if (redPacketId.isEmpty) {
      setState(() => _error = '红包发送确认中，请稍后再试');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _RedPacketDetailPage(
          controller: widget.controller,
          redPacketId: redPacketId,
          group: _isGroup,
          onReceive: () => _receiveRedPacket(
            item,
            showLocalMessage: false,
            ignoreLocalAvailability: true,
          ),
        ),
      ),
    );
  }

  Future<void> _openTransferDetail(Map<String, Object?> item) async {
    final payload = _asObjectMap(item['payload']);
    final transferId = _transferReceiveId(payload);
    if (transferId.isEmpty) {
      setState(() => _error = '转账发送确认中，请稍后再试');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TransferDetailPage(
          controller: widget.controller,
          transferId: transferId,
          onReceive: () => _receiveTransfer(
            item,
            showLocalMessage: false,
            ignoreLocalAvailability: true,
          ),
        ),
      ),
    );
  }

  Future<void> _openMediaMessage(Map<String, Object?> item) async {
    final status = _messageStatus(item);
    if (status == 'sending' || status == 'queued') {
      setState(() => _message = '媒体正在发送中');
      return;
    }
    if (status == 'failed') {
      setState(() => _error = '媒体发送失败，请点击感叹号重发');
      return;
    }
    final media = _ChatMediaItem.fromMessage(item);
    if (!media.hasSource) {
      setState(() => _error = '媒体资源不存在');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _MediaViewerPage(media: media)),
    );
  }

  Future<void> _sendTransfer() async {
    if (!_composerEnabled) {
      setState(() => _message = _groupMuteText(_groupMuteState));
      return;
    }
    if (!await _ensureWalletReadyForPayment()) {
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
        const ActionInputField(
          id: 'pay_password',
          label: '支付密码',
          hint: '6位数字',
          keyboardType: TextInputType.number,
          obscureText: true,
        ),
        const ActionInputField(id: 'remark', label: '备注'),
        if (_isGroup) const ActionInputField(id: 'receiver_id', label: '指定收款人'),
      ],
    );
    if (data == null) {
      return;
    }
    final money = (data['money'] ?? '').trim();
    final assetType = (data['asset_type'] ?? 'money').trim();
    final amountError = _paymentAmountInputError(money, assetType);
    if (amountError.isNotEmpty) {
      setState(() => _error = amountError);
      return;
    }
    final payPassword = (data['pay_password'] ?? '').trim();
    if (!RegExp(r'^\d{6}$').hasMatch(payPassword)) {
      setState(() => _error = '请输入6位支付密码');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupTransfer(
          groupId: _groupId,
          channelId: widget.channelId,
          receiverId: data['receiver_id'] ?? '',
          money: money,
          assetType: assetType.isEmpty ? 'money' : assetType,
          payPassword: payPassword,
          remark: data['remark'] ?? '',
        );
      } else {
        await widget.controller.sendPrivateTransfer(
          receiverId: _receiverId,
          money: money,
          assetType: assetType.isEmpty ? 'money' : assetType,
          payPassword: payPassword,
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
    if (!await _ensureWalletReadyForPayment()) {
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
        const ActionInputField(
          id: 'pay_password',
          label: '支付密码',
          hint: '6位数字',
          keyboardType: TextInputType.number,
          obscureText: true,
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
    final assetType = (data['asset_type'] ?? 'money').trim();
    final amountError = _paymentAmountInputError(money, assetType);
    if (amountError.isNotEmpty) {
      setState(() => _error = amountError);
      return;
    }
    final payPassword = (data['pay_password'] ?? '').trim();
    if (!RegExp(r'^\d{6}$').hasMatch(payPassword)) {
      setState(() => _error = '请输入6位支付密码');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupRedPacket(
          groupId: _groupId,
          channelId: widget.channelId,
          money: money,
          assetType: assetType.isEmpty ? 'money' : assetType,
          payPassword: payPassword,
          packetType: data['packet_type'] ?? 'ordinary',
          quantity: int.tryParse(data['quantity'] ?? '') ?? 1,
          receiverId: data['receiver_id'] ?? '',
          remark: data['remark'] ?? '',
        );
      } else {
        await widget.controller.sendPrivateRedPacket(
          receiverId: _receiverId,
          money: money,
          assetType: assetType.isEmpty ? 'money' : assetType,
          payPassword: payPassword,
          remark: data['remark'] ?? '',
        );
      }
    });
  }

  String _paymentAmountInputError(String value, String assetType) {
    final normalizedAsset = assetType.trim().isEmpty
        ? 'money'
        : assetType.trim().toLowerCase();
    if (normalizedAsset == 'integral') {
      return RegExp(r'^[1-9]\d*$').hasMatch(value) ? '' : '积分数量必须是正整数';
    }
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
      return '金额格式不正确，最多支持小数点后两位';
    }
    final amount = double.tryParse(value);
    return amount != null && amount > 0 ? '' : '金额必须大于 0';
  }

  Future<bool> _ensureWalletReadyForPayment() async {
    WalletBalance balance;
    try {
      balance = await widget.controller.loadWalletBalance(refresh: true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
      return false;
    }
    if (!mounted) {
      return false;
    }
    if (!balance.securityBound) {
      setState(() => _error = '请先绑定手机号、邮箱或安全验证方式');
      return false;
    }
    if (balance.payPasswordLocked) {
      setState(() => _error = '支付密码已锁定，请联系管理员解锁');
      return false;
    }
    if (balance.payPasswordSet) {
      return true;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WalletPayPasswordPage(controller: widget.controller),
      ),
    );
    if (!mounted) {
      return false;
    }
    try {
      balance = await widget.controller.loadWalletBalance(refresh: true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
      return false;
    }
    if (!balance.payPasswordSet) {
      setState(() => _error = '请先设置支付密码');
      return false;
    }
    if (balance.payPasswordLocked) {
      setState(() => _error = '支付密码已锁定，请联系管理员解锁');
      return false;
    }
    return true;
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
    final oldBurnAfterRead = _burnAfterRead;
    final oldBurnSeconds = _burnSeconds;
    final nextBurnAfterRead = (data['burn_after_read'] ?? '') == '1';
    final nextBurnSeconds =
        int.tryParse(data['burn_after_read_seconds'] ?? '') ?? 0;
    setState(() {
      _mentionUserIds = _idsFromText(data['mention_user_ids'] ?? '');
      _mentionAll = (data['mention_all'] ?? '') == '1';
      _burnAfterRead = nextBurnAfterRead;
      _burnSeconds = nextBurnSeconds;
    });
    if (oldBurnAfterRead != nextBurnAfterRead ||
        oldBurnSeconds != nextBurnSeconds) {
      unawaited(_notifyBurnAfterReadState());
    }
  }

  Future<void> _notifyBurnAfterReadState() async {
    try {
      await widget.controller.sendBurnAfterReadState(
        channelId: widget.channelId,
        channelType: widget.channelType,
        groupId: _isGroup ? _groupId : '',
        enabled: _burnAfterRead,
        seconds: _burnSeconds,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'ui',
        'burn after read state notify failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'enabled': _burnAfterRead,
          'seconds': _burnSeconds,
        },
      );
      if (mounted) {
        setState(() => _error = '阅后即焚状态同步失败');
      }
    }
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
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
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
      _selectedPayload = const {};
      _selectedMessage = const {};
      _selectedMenuAnchor = null;
      _message = _friendlyResult(result, successText: '消息已删除');
    });
  }

  Future<void> _receiveRedPacket(
    Map<String, Object?> item, {
    bool showLocalMessage = true,
    bool ignoreLocalAvailability = false,
  }) async {
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
      if (showLocalMessage) {
        setState(() {
          _error = null;
          _message = _isGroup ? '指定红包不能由发送者领取' : '不能领取自己发送的红包';
        });
      }
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
      if (showLocalMessage) {
        setState(() {
          _message = '';
          _error = rawId.isEmpty ? '红包发送确认中，请稍后再试' : '红包数据异常，请重新进入会话';
        });
      }
      return;
    }
    final unavailableText = ignoreLocalAvailability
        ? ''
        : _redPacketUnavailableText(payload);
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
      if (showLocalMessage) {
        setState(() {
          _error = null;
          _message = unavailableText;
        });
      }
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
        if (showLocalMessage) {
          setState(() => _error = error.toString());
        }
      }
      if (!showLocalMessage) {
        rethrow;
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

  Future<void> _receiveTransfer(
    Map<String, Object?> item, {
    bool showLocalMessage = true,
    bool ignoreLocalAvailability = false,
  }) async {
    AppLogger.info(
      'ui',
      'transfer receive tapped',
      data: {
        'channel_id': widget.channelId,
        'channel_type': widget.channelType,
        'client_msg_no': _value(item, ['client_msg_no']),
        'is_me': item['is_me'] == true,
        'payload': _asObjectMap(item['payload']),
      },
    );
    if (item['is_me'] == true) {
      if (showLocalMessage) {
        setState(() {
          _error = null;
          _message = '不能收取自己发出的转账';
        });
      }
      return;
    }
    final payload = _asObjectMap(item['payload']);
    final transferId = _transferReceiveId(payload);
    if (transferId.isEmpty) {
      final rawId = _transferRawId(payload);
      AppLogger.warn(
        'ui',
        'transfer receive blocked',
        data: {
          'reason': rawId.isEmpty ? 'empty_id' : 'invalid_id',
          'raw_id': rawId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
          'payload': payload,
        },
      );
      if (showLocalMessage) {
        setState(() {
          _message = '';
          _error = rawId.isEmpty ? '转账发送确认中，请稍后再试' : '转账数据异常，请重新进入会话';
        });
      }
      return;
    }
    final unavailableText = ignoreLocalAvailability
        ? ''
        : _transferUnavailableText(payload);
    if (unavailableText.isNotEmpty) {
      AppLogger.info(
        'ui',
        'transfer receive blocked',
        data: {
          'reason': unavailableText,
          'transfer_id': transferId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
        },
      );
      if (showLocalMessage) {
        setState(() {
          _error = null;
          _message = unavailableText;
        });
      }
      return;
    }
    if (_receivingTransferIds.contains(transferId)) {
      AppLogger.info(
        'ui',
        'transfer receive duplicate ignored',
        data: {'transfer_id': transferId},
      );
      return;
    }
    setState(() {
      _receivingTransferIds.add(transferId);
      _error = null;
      _message = '';
    });
    try {
      final result = await widget.controller.receiveTransfer(transferId);
      AppLogger.info(
        'ui',
        'transfer receive api success',
        data: {
          'transfer_id': transferId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
          'result': result,
        },
      );
      final clientMsgNo = _value(item, ['client_msg_no']);
      await widget.controller.markTransferReceivedLocal(
        channelId: widget.channelId,
        channelType: widget.channelType,
        clientMsgNo: clientMsgNo,
        transferId: transferId,
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
        'transfer receive failed',
        error: error,
        data: {
          'transfer_id': transferId,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'client_msg_no': _value(item, ['client_msg_no']),
        },
      );
      if (mounted) {
        if (showLocalMessage) {
          setState(() => _error = error.toString());
        }
      }
      if (!showLocalMessage) {
        rethrow;
      }
    } finally {
      if (mounted) {
        setState(() => _receivingTransferIds.remove(transferId));
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
              avatarUrl: _headerAvatarUrl(),
              memberCount: _groupMemberCount,
              onlineCount: _groupOnlineCount,
            )
          : PrivateChatActionsPage(
              controller: widget.controller,
              title: widget.title,
              receiverId: _receiverId,
              channelId: widget.channelId,
              avatarUrl: _headerAvatarUrl(),
              online: _peerOnline,
              burnAfterRead: _burnAfterRead,
              peerBurnAfterRead: _peerBurnAfterRead,
              burnSeconds: _burnSeconds,
              peerBurnSeconds: _peerBurnSeconds,
              onBurnChanged: _setBurnAfterReadFromSettings,
              onStartVoiceCall: () => _startLiveKitCall('audio'),
              onStartVideoCall: () => _startLiveKitCall('video'),
            ),
    );
    if (mounted && _isGroup) {
      unawaited(_refreshGroupPresence());
    }
  }

  Future<void> _setBurnAfterReadFromSettings(bool enabled, int seconds) async {
    setState(() {
      _burnAfterRead = enabled;
      _burnSeconds = enabled ? seconds : 0;
    });
    await _notifyBurnAfterReadState();
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
    final shouldNotifyBurnDisabled = _burnAfterRead || _burnSeconds > 0;
    setState(() {
      _replyClientMsgNo = '';
      _replyQuote = const {};
      _mentionUserIds = const [];
      _mentionAll = false;
      _burnAfterRead = false;
      _burnSeconds = 0;
    });
    if (shouldNotifyBurnDisabled) {
      unawaited(_notifyBurnAfterReadState());
    }
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
      await widget.controller.burnAfterRead(
        targetClientMsgNo: clientMsgNo,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      await widget.controller.deleteLocalMessageOnly(
        targetClientMsgNo: clientMsgNo,
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
      _burnRetryAttempts.remove(clientMsgNo);
      if (mounted) {
        setState(() {
          _messages = _messages
              .where((item) => _value(item, ['client_msg_no']) != clientMsgNo)
              .toList(growable: false);
        });
      }
    } catch (error, stackTrace) {
      final attempt = (_burnRetryAttempts[clientMsgNo] ?? 0) + 1;
      _burnRetryAttempts[clientMsgNo] = attempt;
      final retry =
          attempt <= 6 &&
          mounted &&
          _messages.any(
            (item) => _value(item, ['client_msg_no']) == clientMsgNo,
          );
      if (retry) {
        final delayMs =
            min(30000, 1000 * (1 << min(attempt - 1, 5))) +
            (DateTime.now().millisecond % 500);
        Future<void>.delayed(Duration(milliseconds: delayMs), () {
          return _triggerBurnAfterRead(clientMsgNo);
        });
      } else {
        _burnTriggeredClientMsgNos.remove(clientMsgNo);
        _burnRetryAttempts.remove(clientMsgNo);
      }
      AppLogger.warn(
        'ui',
        'burn after read trigger failed',
        data: {
          'client_msg_no': clientMsgNo,
          'attempt': attempt,
          'retry': retry,
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
    if (_replyQuote.isNotEmpty) {
      final sender = _quoteSenderName(_replyQuote);
      final preview = _quotePreviewText(_replyQuote);
      parts.add(sender.isEmpty ? '引用 $preview' : '引用 $sender：$preview');
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
    if (_peerBurnAfterRead) {
      parts.add(
        _peerBurnSeconds > 0 ? '对方已开启阅后即焚 ${_peerBurnSeconds}s' : '对方已开启阅后即焚',
      );
    }
    return parts.join(' · ');
  }
}

class _ChatHistoryLoadingState extends StatelessWidget {
  const _ChatHistoryLoadingState({required this.slow, required this.isGroup});

  final bool slow;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final title = slow ? '历史消息较多，正在继续同步' : '正在同步聊天记录';
    final subtitle = isGroup ? '正在整理群聊消息' : '正在加载与好友的聊天记录';
    return Semantics(
      liveRegion: true,
      label: title,
      child: ColoredBox(
        color: _chatPageColor,
        child: Column(
          children: [
            const LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Color(0xffeef1f5),
              color: _primaryColor,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = min(constraints.maxWidth, 620.0);
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: width,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _ChatHistoryLoadingHint(
                              title: title,
                              subtitle: subtitle,
                            ),
                            const SizedBox(height: 18),
                            const _ChatHistorySkeletonRow(
                              mine: false,
                              widthFactor: 0.58,
                            ),
                            const _ChatHistorySkeletonRow(
                              mine: true,
                              widthFactor: 0.46,
                            ),
                            const _ChatHistorySkeletonRow(
                              mine: false,
                              widthFactor: 0.72,
                            ),
                            const _ChatHistorySkeletonRow(
                              mine: true,
                              widthFactor: 0.54,
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _ChatHistoryLoadingHint extends StatelessWidget {
  const _ChatHistoryLoadingHint({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _secondaryTextColor,
            fontSize: 12,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _ChatHistorySkeletonRow extends StatelessWidget {
  const _ChatHistorySkeletonRow({
    required this.mine,
    required this.widthFactor,
  });

  final bool mine;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubbleWidth = min(constraints.maxWidth * widthFactor, 280.0);
        final row = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine) ...[
              const _ChatHistorySkeletonAvatar(),
              const SizedBox(width: 7),
            ],
            Container(
              width: bubbleWidth,
              height: 42,
              decoration: BoxDecoration(
                color: mine ? const Color(0xffe4f4dd) : _surfaceColor,
                border: Border.all(color: const Color(0xffedf0f3)),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            if (mine) ...[
              const SizedBox(width: 7),
              const _ChatHistorySkeletonAvatar(),
            ],
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: row,
          ),
        );
      },
    );
  }
}

class _ChatHistorySkeletonAvatar extends StatelessWidget {
  const _ChatHistorySkeletonAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xffeceff3),
        shape: BoxShape.circle,
      ),
    );
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

class _QrScanImageSource {
  const _QrScanImageSource({required this.path, required this.temporary});

  final String path;
  final bool temporary;
}

String _qrMediaCoverLocalPath(
  Map<String, Object?> payload,
  Map<String, Object?> media,
) {
  for (final key in const [
    'cover_file_path',
    'cover_local_path',
    'cover_path',
    'thumb_file_path',
    'thumb_local_path',
    'thumb_path',
    'thumbnail_file_path',
    'thumbnail_path',
    'image_file_path',
  ]) {
    final value = _value(payload, [key], fallback: _value(media, [key]));
    if (value.isEmpty ||
        _isRemoteResource(value) ||
        !_isLikelyLocalPath(value)) {
      continue;
    }
    try {
      if (File(value).existsSync()) {
        return value;
      }
    } on Object {
      continue;
    }
  }
  return '';
}

String _qrMediaCoverRemoteUrl(
  Map<String, Object?> payload,
  Map<String, Object?> media,
) {
  for (final key in const [
    'cover_url',
    'cover_image_url',
    'cover_path',
    'thumb_url',
    'thumbnail_url',
    'thumbnail_path',
    'image_url',
  ]) {
    final raw = _value(payload, [key], fallback: _value(media, [key]));
    if (raw.isEmpty || _isLikelyLocalPath(raw)) {
      continue;
    }
    final url = _normalizeAvatarUrl(raw);
    if (url.isNotEmpty) {
      return url;
    }
  }
  return '';
}

Future<_QrScanImageSource> _downloadQrScanImage(String rawUrl) async {
  final url = _normalizeAvatarUrl(rawUrl);
  if (url.isEmpty) {
    throw Exception('二维码图片地址为空');
  }
  final dir = await getTemporaryDirectory();
  final ext = _qrScanImageExtension(url);
  final path =
      '${dir.path}/bim_qr_scan_${DateTime.now().microsecondsSinceEpoch}$ext';
  await Dio().download(
    url,
    path,
    options: Options(responseType: ResponseType.bytes),
  );
  return _QrScanImageSource(path: path, temporary: true);
}

String _qrScanImageExtension(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  for (final ext in const ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp']) {
    if (path.endsWith(ext)) {
      return ext;
    }
  }
  return '.jpg';
}

class _GroupCallInvitePickerPage extends StatefulWidget {
  const _GroupCallInvitePickerPage({
    required this.controller,
    required this.groupId,
    required this.mediaType,
    this.initialSelectedIds = const [],
  });

  final SessionController controller;
  final String groupId;
  final String mediaType;
  final List<String> initialSelectedIds;

  @override
  State<_GroupCallInvitePickerPage> createState() =>
      _GroupCallInvitePickerPageState();
}

class _GroupCallInvitePickerPageState
    extends State<_GroupCallInvitePickerPage> {
  late final Future<List<Map<String, Object?>>> _future;
  final Set<String> _selectedIds = <String>{};
  final Set<String> _validMemberIds = <String>{};
  bool _membersReady = false;

  @override
  void initState() {
    super.initState();
    _selectedIds.addAll(
      widget.initialSelectedIds
          .map(_privateReceiverIdFromChannel)
          .where((id) => id.isNotEmpty),
    );
    _future = _loadInviteMembers();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mediaType == 'video' ? '选择视频通话成员' : '选择语音通话成员';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _selectedInviteIds.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selectedInviteIds),
            child: Text(
              _selectedInviteIds.isEmpty
                  ? '发起'
                  : '发起(${_selectedInviteIds.length})',
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(text: snapshot.error.toString());
          }
          final members = snapshot.data ?? const <Map<String, Object?>>[];
          if (members.isEmpty) {
            return const _EmptyRow(text: '暂无可邀请成员');
          }
          return ListView.separated(
            itemCount: members.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final member = members[index];
              final userId = _memberUserId(member);
              final selected = _selectedIds.contains(userId);
              return ListTile(
                leading: _Avatar(
                  label: _memberTitle(member),
                  imageUrl: _avatarUrlFromMap(member),
                  size: 38,
                ),
                title: Text(
                  _memberTitle(member),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _memberSubtitle(member),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Checkbox(
                  value: selected,
                  onChanged: (_) => _toggle(userId),
                ),
                onTap: () => _toggle(userId),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, Object?>>> _loadInviteMembers() async {
    final result = await widget.controller.groupMembers(widget.groupId);
    final currentUserId = widget.controller.session?.userId.toString() ?? '';
    final members = _listFromResult(result)
        .where((item) {
          final id = _memberUserId(item);
          return id.isNotEmpty && id != currentUserId;
        })
        .toList(growable: false);
    final validMemberIds = members.map(_memberUserId).toSet();
    _validMemberIds
      ..clear()
      ..addAll(validMemberIds);
    _selectedIds.removeWhere((id) => !validMemberIds.contains(id));
    _membersReady = true;
    return members;
  }

  void _toggle(String userId) {
    if (userId.isEmpty) {
      return;
    }
    setState(() {
      if (!_selectedIds.remove(userId)) {
        _selectedIds.add(userId);
      }
    });
  }

  List<String> get _selectedInviteIds {
    if (!_membersReady) {
      return const [];
    }
    if (_validMemberIds.isEmpty) {
      return const [];
    }
    return _selectedIds.where(_validMemberIds.contains).toList(growable: false);
  }
}
