import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/models.dart';
import 'im_cache_store.dart';
import 'im_message_types.dart';
import 'tcp_im_crypto.dart';
import 'tcp_im_proto.dart';

class BusinessImService extends ChangeNotifier {
  BusinessImService({required ApiClient api, required ImCacheStore cache})
    : _api = api,
      _cache = cache;

  final ApiClient _api;
  final ImCacheStore _cache;
  final Random _random = Random.secure();
  final StreamController<BusinessImMessageEvent> _messageEvents =
      StreamController<BusinessImMessageEvent>.broadcast();

  UserSession? _session;
  String _device = '';
  Socket? _socket;
  WebSocket? _webSocket;
  int _socketEpoch = 0;
  TcpImCrypto _crypto = TcpImCrypto();
  TcpImProto _proto = TcpImProto();
  Uint8List _frameBuffer = Uint8List(0);
  Timer? _tcpHeartbeatTimer;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _manualStop = false;
  bool _connecting = false;
  bool _foreground = true;
  bool _closingForBackground = false;
  int _missedPongCount = 0;
  int _reconnectAttempt = 0;
  int _conversationVersion = 0;
  String _statusText = '未连接';
  String? _lastError;
  List<Map<String, Object?>> _latestConversations = const [];
  final Map<String, int> _channelMessageVersions = <String, int>{};
  final Map<String, Future<List<Map<String, Object?>>>> _syncingChannels =
      <String, Future<List<Map<String, Object?>>>>{};
  final Set<String> _historySyncedChannels = <String>{};
  final Map<String, DateTime> _historyRetryAfter = <String, DateTime>{};
  final Set<String> _openMessageChannels = <String>{};
  final Map<String, Map<String, Object?>> _groupMuteStates =
      <String, Map<String, Object?>>{};

  Stream<BusinessImMessageEvent> get messageEvents => _messageEvents.stream;
  bool get isStarted => _started;
  String get statusText => _statusText;
  String? get lastError => _lastError;
  int get conversationVersion => _conversationVersion;

  List<Map<String, Object?>> cachedConversations() {
    final chat = _session?.chat;
    if (chat == null) {
      return const [];
    }
    if (_latestConversations.isEmpty) {
      _latestConversations = _cache
          .readConversations(chat.uid)
          .map(_normalizeConversation)
          .where(_conversationVisibleAfterClear)
          .toList();
    }
    return _latestConversations
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  int messageVersion({required String channelID, required int channelType}) {
    return _channelMessageVersions[_messageKey(channelID, channelType)] ?? 0;
  }

  Map<String, Object?> groupMuteState({
    required String channelID,
    required String groupId,
  }) {
    final chat = _requireChat();
    final candidates = [
      _messageKey(
        _canonicalChannelId(channelID, chat.channelTypeGroup),
        chat.channelTypeGroup,
      ),
      if (groupId.isNotEmpty) _messageKey(groupId, chat.channelTypeGroup),
    ];
    for (final key in candidates) {
      final state = _groupMuteStates[key];
      if (state != null) {
        return Map<String, Object?>.from(state);
      }
    }
    return const <String, Object?>{};
  }

  void applyGroupMuteState({
    required String channelID,
    required String groupId,
    required Map<String, Object?> state,
    required String source,
  }) {
    if (state.isEmpty) {
      return;
    }
    final chat = _requireChat();
    final canonicalChannelId = _canonicalChannelId(
      channelID.isNotEmpty ? channelID : groupId,
      chat.channelTypeGroup,
    );
    final normalized = _normalizeGroupMuteState(
      state,
      channelId: canonicalChannelId,
      groupId: groupId,
    );
    final keys = <String>{
      _messageKey(canonicalChannelId, chat.channelTypeGroup),
      if (groupId.isNotEmpty) _messageKey(groupId, chat.channelTypeGroup),
    };
    for (final key in keys) {
      _groupMuteStates[key] = normalized;
    }
    AppLogger.info(
      'im',
      'group mute state updated',
      data: {
        'source': source,
        'channel_id': canonicalChannelId,
        'group_id': normalized['group_id']?.toString() ?? groupId,
        'muted': normalized['muted'],
      },
    );
    notifyListeners();
  }

  Future<void> start(UserSession session, {required String device}) async {
    final chat = session.chat;
    if (chat == null || chat.uid.isEmpty || chat.token.isEmpty) {
      throw ApiException('IM 登录材料缺失');
    }
    _manualStop = false;
    _started = true;
    _session = session;
    _device = device;
    _groupMuteStates.clear();
    _historySyncedChannels.clear();
    _historyRetryAfter.clear();
    _latestConversations = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList();
    _bumpConversations('cache_loaded', notify: false);
    AppLogger.info(
      'im',
      'business im start',
      data: {
        'uid': chat.uid,
        'device': device,
        'tcp_addr': chat.route.tcpAddr,
        'wss_addr': chat.route.wssAddr,
        'ws_addr': chat.route.wsAddr,
        'websocket_addr': chat.route.websocketAddr,
      },
    );
    unawaited(syncConversationsFromServer());
    await _connectTcp();
  }

  Future<void> stop({bool logout = false}) async {
    _manualStop = true;
    _started = false;
    _connecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopTcpHeartbeat();
    final socket = _socket;
    final webSocket = _webSocket;
    _socket = null;
    _webSocket = null;
    _socketEpoch++;
    if (webSocket != null) {
      await webSocket
          .close(WebSocketStatus.normalClosure)
          .catchError((Object _) => null);
    }
    if (socket != null) {
      await socket.close().catchError((Object _) => socket);
      socket.destroy();
    }
    if (logout) {
      _session = null;
      _latestConversations = const [];
      _groupMuteStates.clear();
    }
    _setStatus('未连接');
  }

  void onAppBackgrounded(String state) {
    AppLogger.info('im', 'app backgrounded', data: {'state': state});
    if (state == 'inactive') {
      return;
    }
    _foreground = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopTcpHeartbeat();
    _closingForBackground = true;
    unawaited(_closeSocketOnly());
  }

  void resumeConnection() {
    if (!_started || _session == null) {
      return;
    }
    _foreground = true;
    if (_socket == null && _webSocket == null && !_connecting) {
      unawaited(_connectTcp());
    }
  }

  Future<List<Map<String, Object?>>> refreshLocalConversations({
    bool notify = true,
  }) async {
    final chat = _requireChat();
    _latestConversations = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList();
    _seedConversationTailMessages(
      _latestConversations,
      source: 'local_refresh',
    );
    _cache.writeConversations(
      uid: chat.uid,
      conversations: _latestConversations,
    );
    if (notify) {
      _bumpConversations('local_refresh');
    }
    AppLogger.info(
      'im',
      'local conversations loaded',
      data: {'count': _latestConversations.length, 'notify': notify},
    );
    return _latestConversations;
  }

  Future<void> openConversation({
    required String channelID,
    required int channelType,
  }) async {
    channelID = _canonicalChannelId(channelID, channelType);
    _openMessageChannels.add(_messageKey(channelID, channelType));
    await markConversationRead(channelID: channelID, channelType: channelType);
  }

  void closeConversation({
    required String channelID,
    required int channelType,
  }) {
    channelID = _canonicalChannelId(channelID, channelType);
    _openMessageChannels.remove(_messageKey(channelID, channelType));
  }

  Future<void> markConversationRead({
    required String channelID,
    required int channelType,
  }) async {
    channelID = _canonicalChannelId(channelID, channelType);
    final chat = _requireChat();
    final messages = _cache.readMessages(
      uid: chat.uid,
      channelId: channelID,
      channelType: channelType,
    );
    _writeReadMarkerForMessages(channelID, channelType, messages);
    if (_clearConversationUnread(channelID, channelType, source: 'mark_read')) {
      _markMessageChannel(
        source: 'mark_read',
        channelId: channelID,
        channelType: channelType,
      );
    }
  }

  Future<void> clearAllChatRecords() async {
    final chat = _requireChat();
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final channels = _cache.clearAllChatRecords(
      uid: chat.uid,
      timestampMs: timestampMs,
    );
    _latestConversations = const [];
    _historySyncedChannels.clear();
    _historyRetryAfter.clear();
    _syncingChannels.clear();
    for (final channel in channels) {
      final channelId = channel['channel_id']?.toString() ?? '';
      final channelType =
          int.tryParse(channel['channel_type']?.toString() ?? '') ?? 0;
      if (channelId.isEmpty || channelType <= 0) {
        continue;
      }
      _markMessageChannel(
        source: 'clear_all_chats',
        channelId: channelId,
        channelType: channelType,
      );
    }
    _bumpConversations('clear_all_chats');
    AppLogger.info(
      'im',
      'all local chat records cleared',
      data: {'channel_count': channels.length},
    );
  }

  Future<void> clearChannelChatRecords({
    required String channelID,
    required int channelType,
  }) async {
    final chat = _requireChat();
    channelID = _canonicalChannelId(channelID, channelType);
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    _cache.clearChannelChatRecords(
      uid: chat.uid,
      channelId: channelID,
      channelType: channelType,
      timestampMs: timestampMs,
    );
    _latestConversations = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList(growable: false);
    _historySyncedChannels.remove(_messageKey(channelID, channelType));
    _historyRetryAfter.remove(_messageKey(channelID, channelType));
    _syncingChannels.remove(_messageKey(channelID, channelType));
    _markMessageChannel(
      source: 'clear_channel_chat',
      channelId: channelID,
      channelType: channelType,
    );
    _bumpConversations('clear_channel_chat');
    AppLogger.info(
      'im',
      'channel local chat records cleared',
      data: {'channel_id': channelID, 'channel_type': channelType},
    );
  }

  Future<void> deleteLocalMessage({
    required String channelID,
    required int channelType,
    required String clientMsgNo,
  }) async {
    if (clientMsgNo.isEmpty) {
      return;
    }
    final chat = _requireChat();
    channelID = _canonicalChannelId(channelID, channelType);
    _cache.deleteMessage(
      uid: chat.uid,
      channelId: channelID,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
    );
    _markMessageChannel(
      source: 'delete_local_message',
      channelId: channelID,
      channelType: channelType,
    );
    final messages = _readMessagesForChannel(channelID, channelType);
    if (messages.isNotEmpty) {
      _replaceConversationTailFromMessage(
        channelID,
        channelType,
        messages.last,
      );
    } else {
      _latestConversations = _cache
          .readConversations(chat.uid)
          .map(_normalizeConversation)
          .where(
            (item) =>
                item['channel_id']?.toString() != channelID ||
                _intValue(item, ['channel_type']) != channelType,
          )
          .where(_conversationVisibleAfterClear)
          .toList(growable: false);
      _cache.writeConversations(
        uid: chat.uid,
        conversations: _latestConversations,
      );
      _bumpConversations('delete_last_local_message');
    }
  }

  Future<List<Map<String, Object?>>> syncConversationsFromServer() async {
    final session = _requireSession();
    final chat = _requireChat();
    final local = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList();
    if (!chat.privateHistorySyncEnabled && !chat.groupHistorySyncEnabled) {
      _latestConversations = local;
      AppLogger.info(
        'im',
        'server conversation sync skipped',
        data: {'reason': 'server_history_sync_disabled'},
      );
      return _latestConversations;
    }
    final statusBeforeSync = _statusText;
    if (statusBeforeSync == '已连接') {
      _setStatus('同步中');
    }
    try {
      final list = await _api.conversations(
        session: session,
        device: _device,
        limit: 50,
      );
      final serverConversations = list
          .map(_normalizeConversation)
          .where(
            (item) => _historySyncEnabledForType(
              _intValue(item, ['channel_type']),
              chat,
            ),
          )
          .where(_conversationVisibleAfterClear)
          .toList();
      final localOnlyConversations = local
          .where(
            (item) => !_historySyncEnabledForType(
              _intValue(item, ['channel_type']),
              chat,
            ),
          )
          .where(_conversationVisibleAfterClear)
          .toList();
      _latestConversations = _mergeConversationLists(
        serverConversations,
        localOnlyConversations,
      );
      _seedConversationTailMessages(
        _latestConversations,
        source: 'server_sync',
      );
      _cache.writeConversations(
        uid: chat.uid,
        conversations: _latestConversations,
      );
      _bumpConversations('server_sync');
      AppLogger.info(
        'im',
        'server conversations synced',
        data: {'count': _latestConversations.length},
      );
      if (_statusText == '同步中') {
        _setStatus('已连接');
      }
      return _latestConversations;
    } catch (error, stackTrace) {
      if (_statusText == '同步中') {
        _setStatus(statusBeforeSync);
      }
      AppLogger.error(
        'im',
        'server conversations sync failed',
        error: error,
        stackTrace: stackTrace,
      );
      return _latestConversations;
    }
  }

  Future<List<Map<String, Object?>>> localMessages({
    required String channelID,
    required int channelType,
    String groupId = '',
    int limit = 50,
  }) async {
    final rawChannelId = channelID;
    channelID = _canonicalChannelId(channelID, channelType);
    var cached = _readMessagesForChannel(channelID, channelType);
    AppLogger.info(
      'im',
      'local messages cache read',
      data: {
        'raw_channel_id': rawChannelId,
        'channel_id': channelID,
        'channel_type': channelType,
        'count': cached.length,
      },
    );
    final key = _messageKey(channelID, channelType);
    final historySynced = _historySyncedChannels.contains(key);
    final missingTailBeforeSync =
        !historySynced &&
        _conversationTailMissing(channelID, channelType, cached);
    final retryAfter = _historyRetryAfter[key];
    final retryBlocked =
        retryAfter != null && DateTime.now().isBefore(retryAfter);
    final needsHistorySync = !historySynced && !retryBlocked;
    if (needsHistorySync) {
      AppLogger.info(
        'im',
        'channel history sync requested',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'tail_missing': missingTailBeforeSync,
        },
      );
      cached = await syncChannelMessages(
        channelID: channelID,
        channelType: channelType,
        groupId: groupId,
        limit: limit,
      );
    } else if (retryBlocked) {
      AppLogger.info(
        'im',
        'channel history sync throttled',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'retry_after': retryAfter.toIso8601String(),
        },
      );
    }
    cached = _seedConversationTailMessageForChannel(
      channelID,
      channelType,
      cached,
      source: 'local_messages',
    );
    final sorted = _sortAndLimit(cached, limit);
    if (_openMessageChannels.contains(key)) {
      _writeReadMarkerForMessages(channelID, channelType, sorted);
      _clearConversationUnread(channelID, channelType, source: 'local_read');
    }
    return sorted;
  }

  Future<List<Map<String, Object?>>> syncChannelMessages({
    required String channelID,
    required int channelType,
    String groupId = '',
    int limit = 50,
  }) async {
    channelID = _canonicalChannelId(channelID, channelType);
    final key = _messageKey(channelID, channelType);
    final running = _syncingChannels[key];
    if (running != null) {
      AppLogger.info(
        'im',
        'reuse running channel history sync',
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
      return running;
    }
    final future = _syncChannelMessagesOnce(
      channelID: channelID,
      channelType: channelType,
      groupId: groupId,
      limit: limit,
    );
    _syncingChannels[key] = future;
    try {
      return await future;
    } finally {
      if (identical(_syncingChannels[key], future)) {
        _syncingChannels.remove(key);
      }
    }
  }

  Future<List<Map<String, Object?>>> _syncChannelMessagesOnce({
    required String channelID,
    required int channelType,
    String groupId = '',
    int limit = 50,
  }) async {
    final session = _requireSession();
    final chat = _requireChat();
    if (!_historySyncEnabledForType(channelType, chat)) {
      _historySyncedChannels.add(_messageKey(channelID, channelType));
      AppLogger.info(
        'im',
        'channel history sync skipped',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'reason': 'server_history_sync_disabled',
        },
      );
      return _sortAndLimit(
        _readMessagesForChannel(channelID, channelType),
        limit,
      );
    }
    try {
      final list = channelType == chat.channelTypeGroup
          ? await _api.groupMessages(
              session: session,
              device: _device,
              groupId: groupId.isNotEmpty
                  ? groupId
                  : _groupIdForChannel(channelID),
              limit: limit,
            )
          : await _api.personMessages(
              session: session,
              device: _device,
              receiverId: _receiverIdFromChannel(channelID),
              limit: limit,
            );
      final messages = list
          .map(
            (item) => _normalizeHistoryMessage(
              item,
              channelId: channelID,
              channelType: channelType,
            ),
          )
          .where((item) => item.isNotEmpty)
          .where(_messageVisibleAfterClear)
          .where(_messageNotDeleted)
          .toList();
      final merged = _mergeMessages(
        _readMessagesForChannel(channelID, channelType),
        messages,
      );
      _writeMessages(channelID, channelType, _sortAndLimit(merged, 200));
      _historySyncedChannels.add(_messageKey(channelID, channelType));
      _historyRetryAfter.remove(_messageKey(channelID, channelType));
      _markMessageChannel(
        source: 'history_sync',
        channelId: channelID,
        channelType: channelType,
      );
      return _sortAndLimit(merged, limit);
    } catch (error, stackTrace) {
      AppLogger.error(
        'im',
        'channel history sync failed',
        error: error,
        stackTrace: stackTrace,
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
      _historyRetryAfter[_messageKey(channelID, channelType)] = DateTime.now()
          .add(const Duration(seconds: 20));
      return _readMessagesForChannel(channelID, channelType);
    }
  }

  bool _historySyncEnabledForType(int channelType, ChatSession chat) {
    if (channelType == chat.channelTypeGroup) {
      return chat.groupHistorySyncEnabled;
    }
    if (channelType == chat.channelTypePerson) {
      return chat.privateHistorySyncEnabled;
    }
    return true;
  }

  List<Map<String, Object?>> _mergeConversationLists(
    List<Map<String, Object?>> primary,
    List<Map<String, Object?>> secondary,
  ) {
    final merged = primary
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    for (final conversation in secondary) {
      final channelId = _value(conversation, ['channel_id']);
      final channelType = _intValue(conversation, ['channel_type']);
      final exists = merged.any(
        (item) =>
            _value(item, ['channel_id']) == channelId &&
            _intValue(item, ['channel_type']) == channelType,
      );
      if (!exists) {
        merged.add(Map<String, Object?>.from(conversation));
      }
    }
    merged.sort(
      (a, b) => _value(b, [
        'msg_time',
        'create_time',
        'timestamp',
      ]).compareTo(_value(a, ['msg_time', 'create_time', 'timestamp'])),
    );
    return merged;
  }

  Future<Map<String, Object?>?> localMessageByClientMsgNo(
    String clientMsgNo,
  ) async {
    if (clientMsgNo.isEmpty) {
      return null;
    }
    final chat = _requireChat();
    for (final channel in _cache.readRecentChannels(chat.uid)) {
      final parts = channel.split(':');
      if (parts.length != 2) {
        continue;
      }
      final channelType = int.tryParse(parts[0]) ?? 0;
      final channelId = parts[1];
      final messages = _cache.readMessages(
        uid: chat.uid,
        channelId: channelId,
        channelType: channelType,
      );
      for (final message in messages) {
        if (message['client_msg_no']?.toString() == clientMsgNo) {
          return message;
        }
      }
    }
    return null;
  }

  String newClientMsgNo() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final random = List<int>.generate(
      8,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return 'bim_${_requireSession().userId}_$micros$random';
  }

  Future<Map<String, Object?>> sendTextMessage({
    required String channelID,
    required int channelType,
    required String content,
    String groupId = '',
    List<String> mentionUserIds = const [],
    bool mentionAll = false,
    String replyClientMsgNo = '',
    bool burnAfterRead = false,
    int burnAfterReadSeconds = 0,
  }) {
    return sendBusinessMessage(
      channelID: channelID,
      channelType: channelType,
      contentType: ChatContentTypes.text,
      groupId: groupId,
      payload: {
        'content': content,
        if (mentionUserIds.isNotEmpty)
          'mention_user_ids': mentionUserIds.join(','),
        if (mentionAll) 'mention_all': '1',
        if (replyClientMsgNo.isNotEmpty)
          'reply_client_msg_no': replyClientMsgNo,
        if (burnAfterRead) 'burn_after_read': '1',
        if (burnAfterRead && burnAfterReadSeconds > 0)
          'burn_after_read_seconds': burnAfterReadSeconds.toString(),
      },
    );
  }

  Future<Map<String, Object?>> sendBusinessMessage({
    required String channelID,
    required int channelType,
    required String contentType,
    String groupId = '',
    Map<String, Object?> payload = const {},
    String filePath = '',
  }) async {
    channelID = _canonicalChannelId(channelID, channelType);
    final session = _requireSession();
    final chat = _requireChat();
    if (channelType == chat.channelTypeGroup) {
      final muteState = groupMuteState(channelID: channelID, groupId: groupId);
      final muteNotice = _activeGroupMuteNotice(muteState);
      if (muteNotice.isNotEmpty) {
        throw ApiException(muteNotice);
      }
    }
    final clientMsgNo = newClientMsgNo();
    final serverPayload = Map<String, Object?>.from(payload)
      ..remove('file_path');
    final cleanPayload = _cleanPayload({
      ...serverPayload,
      'protocol': 'blin.chat.v1',
      'content_type': contentType,
      'client_msg_no': clientMsgNo,
    });
    final localPayload = _cleanPayload({
      ...payload,
      if (filePath.isNotEmpty) 'file_path': filePath,
      'protocol': 'blin.chat.v1',
      'content_type': contentType,
      'client_msg_no': clientMsgNo,
    });
    final optimistic = _localOutgoingMessage(
      channelId: channelID,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
      contentType: contentType,
      payload: localPayload,
    );
    _upsertMessage(channelID, channelType, optimistic);
    _upsertConversationFromMessage(optimistic);
    _publishMessageEvent(
      source: 'send_local',
      channelId: channelID,
      channelType: channelType,
      message: optimistic,
    );
    _markMessageChannel(
      source: 'send_local',
      channelId: channelID,
      channelType: channelType,
    );
    try {
      final result = await _sendBusinessMessageWithRetry(
        session: session,
        chat: chat,
        channelID: channelID,
        channelType: channelType,
        groupId: groupId,
        clientMsgNo: clientMsgNo,
        contentType: contentType,
        params: cleanPayload,
        filePath: filePath,
      );
      final confirmed = _normalizeSendResult(
        result,
        fallback: optimistic,
        channelId: channelID,
        channelType: channelType,
      );
      _upsertMessage(channelID, channelType, confirmed);
      _upsertConversationFromMessage(confirmed);
      _publishMessageEvent(
        source: 'send_confirmed',
        channelId: channelID,
        channelType: channelType,
        message: confirmed,
      );
      _markMessageChannel(
        source: 'send_confirmed',
        channelId: channelID,
        channelType: channelType,
      );
      AppLogger.info(
        'im',
        'business message sent',
        data: {
          'client_msg_no': clientMsgNo,
          'channel_id': channelID,
          'channel_type': channelType,
          'content_type': contentType,
        },
      );
      return result;
    } catch (error, stackTrace) {
      final failed = Map<String, Object?>.from(optimistic)
        ..['status'] = 'failed'
        ..['error'] = error.toString();
      _upsertMessage(channelID, channelType, failed);
      _publishMessageEvent(
        source: 'send_failed',
        channelId: channelID,
        channelType: channelType,
        message: failed,
      );
      _markMessageChannel(
        source: 'send_failed',
        channelId: channelID,
        channelType: channelType,
      );
      AppLogger.error(
        'im',
        'business message send failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'client_msg_no': clientMsgNo,
          'channel_id': channelID,
          'channel_type': channelType,
          'content_type': contentType,
        },
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> retryBusinessMessage(
    Map<String, Object?> failedMessage,
  ) async {
    final session = _requireSession();
    final chat = _requireChat();
    final channelType = _intValue(failedMessage, ['channel_type']);
    final channelID = _canonicalChannelId(
      _value(failedMessage, ['channel_id']),
      channelType,
    );
    final clientMsgNo = _value(failedMessage, ['client_msg_no']);
    final contentType = _value(failedMessage, ['content_type']);
    if (channelID.isEmpty || channelType <= 0 || clientMsgNo.isEmpty) {
      throw ApiException('消息状态异常，无法重发');
    }
    if (channelType == chat.channelTypeGroup) {
      final muteState = groupMuteState(
        channelID: channelID,
        groupId: _groupIdForChannel(channelID),
      );
      final muteNotice = _activeGroupMuteNotice(muteState);
      if (muteNotice.isNotEmpty) {
        throw ApiException(muteNotice);
      }
    }
    final payload = _cleanPayload({
      ..._asMap(failedMessage['payload']),
      'client_msg_no': clientMsgNo,
      if (contentType.isNotEmpty) 'content_type': contentType,
    });
    final filePath = _value(payload, ['file_path']);
    final serverPayload = Map<String, Object?>.from(payload)
      ..remove('file_path');
    final sending = Map<String, Object?>.from(failedMessage)
      ..['status'] = 'sending'
      ..['payload'] = payload
      ..['content_type'] = contentType
      ..['content'] = _payloadContent(payload)
      ..remove('error');
    _upsertMessage(channelID, channelType, sending);
    _publishMessageEvent(
      source: 'retry_local',
      channelId: channelID,
      channelType: channelType,
      message: sending,
    );
    _markMessageChannel(
      source: 'retry_local',
      channelId: channelID,
      channelType: channelType,
    );
    try {
      final result = await _sendBusinessMessageWithRetry(
        session: session,
        chat: chat,
        channelID: channelID,
        channelType: channelType,
        groupId: _value(payload, ['group_id']),
        clientMsgNo: clientMsgNo,
        contentType: contentType,
        params: serverPayload,
        filePath: filePath,
      );
      final confirmed = _normalizeSendResult(
        result,
        fallback: sending,
        channelId: channelID,
        channelType: channelType,
      );
      _upsertMessage(channelID, channelType, confirmed);
      _upsertConversationFromMessage(confirmed);
      _publishMessageEvent(
        source: 'retry_confirmed',
        channelId: channelID,
        channelType: channelType,
        message: confirmed,
      );
      _markMessageChannel(
        source: 'retry_confirmed',
        channelId: channelID,
        channelType: channelType,
      );
      return result;
    } catch (error, stackTrace) {
      final failed = Map<String, Object?>.from(sending)
        ..['status'] = 'failed'
        ..['error'] = error.toString();
      _upsertMessage(channelID, channelType, failed);
      _publishMessageEvent(
        source: 'retry_failed',
        channelId: channelID,
        channelType: channelType,
        message: failed,
      );
      _markMessageChannel(
        source: 'retry_failed',
        channelId: channelID,
        channelType: channelType,
      );
      AppLogger.error(
        'im',
        'business message retry failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'client_msg_no': clientMsgNo,
          'channel_id': channelID,
          'channel_type': channelType,
          'content_type': contentType,
        },
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> _sendBusinessMessageWithRetry({
    required UserSession session,
    required ChatSession chat,
    required String channelID,
    required int channelType,
    required String groupId,
    required String clientMsgNo,
    required String contentType,
    required Map<String, Object?> params,
    required String filePath,
  }) async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final result = channelType == chat.channelTypeGroup
            ? await _api.sendGroupMessage(
                session: session,
                device: _device,
                groupId: groupId.isNotEmpty
                    ? groupId
                    : _groupIdForChannel(channelID),
                clientMsgNo: clientMsgNo,
                contentType: contentType,
                params: params,
                filePath: filePath,
              )
            : await _api.sendPersonMessage(
                session: session,
                device: _device,
                receiverId: _receiverIdFromChannel(channelID),
                clientMsgNo: clientMsgNo,
                contentType: contentType,
                params: params,
                filePath: filePath,
              );
        if (attempt > 1) {
          AppLogger.info(
            'im',
            'business message retry succeeded',
            data: {'client_msg_no': clientMsgNo, 'attempt': attempt},
          );
        }
        return result;
      } catch (error, stackTrace) {
        if (attempt >= maxAttempts || !_isRetryableSendError(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        AppLogger.warn(
          'im',
          'business message retry scheduled',
          data: {
            'client_msg_no': clientMsgNo,
            'attempt': attempt,
            'error': error.toString(),
          },
        );
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    throw ApiException('消息发送失败');
  }

  bool _isRetryableSendError(Object error) {
    if (error is ApiException) {
      final code = error.code;
      return code == null || code == 408 || code == 429 || code >= 500;
    }
    return error is SocketException ||
        error is TimeoutException ||
        error is IOException;
  }

  Future<void> _connectTcp() async {
    if (_manualStop || _connecting || !_foreground) {
      return;
    }
    final chat = _requireChat();
    final endpoint = _resolveRealtimeEndpoint(chat.route);
    if (endpoint == null) {
      _lastError = 'IM 实时连接地址为空';
      _setStatus('连接失败');
      AppLogger.error('im', 'missing realtime address');
      return;
    }
    _connecting = true;
    _setStatus('连接中');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopTcpHeartbeat();
    _closingForBackground = false;
    await _closeSocketOnly();
    _crypto = TcpImCrypto();
    _proto = TcpImProto();
    _frameBuffer = Uint8List(0);
    try {
      AppLogger.info(
        'im',
        'realtime connect start',
        data: {'transport': endpoint.transport, 'addr': endpoint.logAddress},
      );
      if (endpoint.isWebSocket) {
        final webSocket = await WebSocket.connect(
          endpoint.uri.toString(),
        ).timeout(const Duration(seconds: 6));
        if (_manualStop || !_foreground) {
          await webSocket
              .close(WebSocketStatus.normalClosure)
              .catchError((Object _) => null);
          _connecting = false;
          if (!_foreground) {
            _setStatus('未连接');
          }
          return;
        }
        final epoch = ++_socketEpoch;
        _webSocket = webSocket;
        _connecting = false;
        webSocket.listen(
          (Object? event) {
            if (epoch != _socketEpoch) {
              return;
            }
            if (event is List<int>) {
              _onTcpData(Uint8List.fromList(event));
              return;
            }
            if (event is String) {
              _onTcpData(Uint8List.fromList(utf8.encode(event)));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (epoch != _socketEpoch) {
              return;
            }
            AppLogger.error(
              'im',
              'websocket error',
              error: error,
              stackTrace: stackTrace,
              data: {'transport': endpoint.transport},
            );
            _handleTcpClosed('websocket_error', error.toString());
          },
          onDone: () {
            if (epoch != _socketEpoch) {
              return;
            }
            _handleTcpClosed('websocket_done', '');
          },
          cancelOnError: true,
        );
      } else {
        final socket = await Socket.connect(
          endpoint.uri.host,
          endpoint.uri.port,
          timeout: const Duration(seconds: 6),
        );
        if (_manualStop || !_foreground) {
          await socket.close().catchError((Object _) => socket);
          socket.destroy();
          _connecting = false;
          if (!_foreground) {
            _setStatus('未连接');
          }
          return;
        }
        final epoch = ++_socketEpoch;
        _socket = socket;
        _connecting = false;
        socket.listen(
          _onTcpData,
          onError: (Object error, StackTrace stackTrace) {
            if (epoch != _socketEpoch) {
              return;
            }
            AppLogger.error(
              'im',
              'tcp socket error',
              error: error,
              stackTrace: stackTrace,
            );
            _handleTcpClosed('socket_error', error.toString());
          },
          onDone: () {
            if (epoch != _socketEpoch) {
              return;
            }
            _handleTcpClosed('socket_done', '');
          },
          cancelOnError: true,
        );
      }
      _connecting = false;
      _sendConnectPacket(chat);
    } catch (error, stackTrace) {
      _connecting = false;
      _lastError = error.toString();
      _setStatus('连接失败');
      AppLogger.error(
        'im',
        'realtime connect failed',
        error: error,
        stackTrace: stackTrace,
        data: {'transport': endpoint.transport, 'addr': endpoint.logAddress},
      );
      _scheduleReconnect('connect_failed');
    }
  }

  void _sendConnectPacket(ChatSession chat) {
    final publicKey = _crypto.initClientKey();
    final packet = TcpConnectPacket(
      version: _proto.protoVersion,
      deviceFlag: chat.deviceFlag,
      deviceId: chat.device.isNotEmpty ? chat.device : _device,
      uid: chat.uid,
      token: chat.token,
      clientTimestamp: DateTime.now().millisecondsSinceEpoch,
      clientKey: base64Encode(publicKey),
    );
    _sendPacket(packet);
    AppLogger.info(
      'im',
      'tcp connect packet sent',
      data: {'uid': chat.uid, 'device_flag': chat.deviceFlag},
    );
  }

  void _onTcpData(Uint8List data) {
    _missedPongCount = 0;
    AppLogger.info('im', 'tcp data received', data: {'bytes': data.length});
    _frameBuffer = Uint8List.fromList([..._frameBuffer, ...data]);
    while (_frameBuffer.isNotEmpty) {
      final length = TcpImProto.frameLength(_frameBuffer);
      if (length == 0 || _frameBuffer.length < length) {
        return;
      }
      final frame = _frameBuffer.sublist(0, length);
      _frameBuffer = _frameBuffer.sublist(length);
      AppLogger.info(
        'im',
        'tcp frame ready',
        data: {
          'bytes': frame.length,
          'packet_type': TcpPacketType.values[frame[0] >> 4].name,
        },
      );
      _decodePacket(frame);
    }
  }

  void _decodePacket(Uint8List data) {
    try {
      final packet = _proto.decode(data);
      switch (packet.packetType) {
        case TcpPacketType.connack:
          _handleConnack(packet as TcpConnackPacket);
          break;
        case TcpPacketType.recv:
          _handleRecv(packet as TcpRecvPacket);
          break;
        case TcpPacketType.sendack:
          _handleSendAck(packet as TcpSendAckPacket);
          break;
        case TcpPacketType.disconnect:
          final disconnect = packet as TcpDisconnectPacket;
          _lastError = disconnect.reason.isEmpty
              ? '服务端断开连接(${disconnect.reasonCode})'
              : disconnect.reason;
          _setStatus('已断开');
          _handleTcpClosed('disconnect', _lastError);
          break;
        case TcpPacketType.pong:
          _missedPongCount = 0;
          AppLogger.info('im', 'tcp pong');
          break;
        case TcpPacketType.ping:
          _sendPacket(TcpPongPacket());
          break;
        case TcpPacketType.reserved:
        case TcpPacketType.connect:
        case TcpPacketType.send:
        case TcpPacketType.recvack:
          break;
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'im',
        'tcp packet decode failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleConnack(TcpConnackPacket packet) {
    if (packet.reasonCode != 1) {
      _lastError = 'IM 握手失败(${packet.reasonCode})';
      _setStatus('连接失败');
      _scheduleReconnect('connack_failed');
      return;
    }
    _crypto.setServerKeyAndSalt(packet.serverKey, packet.salt);
    _reconnectAttempt = 0;
    _lastError = null;
    _setStatus('已连接');
    _startTcpHeartbeat();
    unawaited(syncConversationsFromServer());
    AppLogger.info(
      'im',
      'tcp connected',
      data: {'node_id': packet.nodeId, 'proto': packet.serviceProtoVersion},
    );
  }

  void _handleRecv(TcpRecvPacket packet) {
    final decrypted = _decryptRecvPayload(packet);
    if (decrypted == null) {
      return;
    }
    packet.payload = decrypted;
    final chat = _requireChat();
    var channelId = packet.channelId;
    if (packet.channelType == chat.channelTypePerson &&
        _isCurrentUserChannel(packet.channelId) &&
        packet.fromUid.isNotEmpty) {
      channelId = packet.fromUid;
    }
    channelId = _canonicalChannelId(channelId, packet.channelType);
    final payload = _decodeBusinessPayload(packet.payload);
    if (_handleCommandPayload(payload, channelId, packet.channelType)) {
      _sendRecvAck(packet);
      AppLogger.info(
        'im',
        'tcp command message handled',
        data: {
          'client_msg_no': packet.clientMsgNo,
          'channel_id': channelId,
          'channel_type': packet.channelType,
          'cmd': payload['cmd']?.toString() ?? '',
        },
      );
      return;
    }
    final message = _messageFromTcp(packet, channelId, decodedPayload: payload);
    if (message.isEmpty) {
      _sendRecvAck(packet);
      AppLogger.info(
        'im',
        'tcp non-chat message ignored',
        data: {
          'client_msg_no': packet.clientMsgNo,
          'channel_id': channelId,
          'channel_type': packet.channelType,
        },
      );
      return;
    }
    _upsertMessage(channelId, packet.channelType, message);
    _upsertConversationFromMessage(message);
    _publishMessageEvent(
      source: 'tcp_recv',
      channelId: channelId,
      channelType: packet.channelType,
      message: message,
    );
    _markMessageChannel(
      source: 'tcp_recv',
      channelId: channelId,
      channelType: packet.channelType,
    );
    _sendRecvAck(packet);
    AppLogger.info(
      'im',
      'tcp message received',
      data: {
        'client_msg_no': packet.clientMsgNo,
        'channel_id': channelId,
        'channel_type': packet.channelType,
        'from_uid': packet.fromUid,
      },
    );
  }

  String? _decryptRecvPayload(TcpRecvPacket packet) {
    final verifySource = StringBuffer()
      ..write(packet.messageId)
      ..write(packet.messageSeq)
      ..write(packet.clientMsgNo)
      ..write(packet.messageTime)
      ..write(packet.fromUid)
      ..write(packet.channelId)
      ..write(packet.channelType)
      ..write(packet.payload);
    final localMsgKey = _crypto.md5Text(
      _crypto.aesEncrypt(verifySource.toString()),
    );
    if (packet.msgKey.isNotEmpty && packet.msgKey != localMsgKey) {
      AppLogger.warn(
        'im',
        'tcp message key mismatch',
        data: {'client_msg_no': packet.clientMsgNo},
      );
      return null;
    }
    try {
      return _crypto.aesDecrypt(packet.payload);
    } catch (error, stackTrace) {
      AppLogger.error(
        'im',
        'tcp payload decrypt failed',
        error: error,
        stackTrace: stackTrace,
        data: {'client_msg_no': packet.clientMsgNo},
      );
      return null;
    }
  }

  void _handleSendAck(TcpSendAckPacket packet) {
    AppLogger.info(
      'im',
      'tcp sendack received',
      data: {
        'client_seq': packet.clientSeq,
        'message_seq': packet.messageSeq,
        'reason_code': packet.reasonCode,
      },
    );
  }

  void _sendRecvAck(TcpRecvPacket packet) {
    if (packet.header.noPersist) {
      return;
    }
    final ack =
        TcpRecvAckPacket(
            messageId: packet.messageId,
            messageSeq: packet.messageSeq,
          )
          ..header.noPersist = packet.header.noPersist
          ..header.showUnread = packet.header.showUnread
          ..header.syncOnce = packet.header.syncOnce;
    _sendPacket(ack);
  }

  void _sendPacket(TcpPacket packet) {
    final bytes = _proto.encode(packet);
    final webSocket = _webSocket;
    if (webSocket != null) {
      webSocket.add(bytes);
      return;
    }
    _socket?.add(bytes);
  }

  void _startTcpHeartbeat() {
    _stopTcpHeartbeat();
    _tcpHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_missedPongCount >= 2) {
        AppLogger.warn('im', 'tcp heartbeat timeout');
        _handleTcpClosed('heartbeat_timeout', 'TCP 心跳超时');
        return;
      }
      _missedPongCount++;
      _sendPacket(TcpPingPacket());
      AppLogger.info('im', 'tcp ping');
    });
  }

  void _stopTcpHeartbeat() {
    _tcpHeartbeatTimer?.cancel();
    _tcpHeartbeatTimer = null;
    _missedPongCount = 0;
  }

  void _handleTcpClosed(String source, String? reason) {
    if (_manualStop) {
      return;
    }
    if (_closingForBackground) {
      _closingForBackground = false;
      _setStatus('未连接');
      return;
    }
    _stopTcpHeartbeat();
    unawaited(_closeSocketOnly());
    _lastError = reason?.isEmpty == false ? reason : _lastError;
    _setStatus('重连中');
    _scheduleReconnect(source);
  }

  void _scheduleReconnect(String source) {
    if (!_started || _manualStop || !_foreground) {
      AppLogger.info(
        'im',
        'skip tcp reconnect while backgrounded',
        data: {'source': source},
      );
      return;
    }
    _reconnectTimer?.cancel();
    final seconds = min(20, 2 + _reconnectAttempt * 2);
    _reconnectAttempt++;
    AppLogger.warn(
      'im',
      'tcp reconnect scheduled',
      data: {
        'source': source,
        'seconds': seconds,
        'attempt': _reconnectAttempt,
      },
    );
    _reconnectTimer = Timer(Duration(seconds: seconds), _connectTcp);
  }

  Future<void> _closeSocketOnly() async {
    final socket = _socket;
    final webSocket = _webSocket;
    _socket = null;
    _webSocket = null;
    _socketEpoch++;
    if (webSocket != null) {
      await webSocket
          .close(WebSocketStatus.normalClosure)
          .catchError((Object _) => null);
    }
    if (socket != null) {
      await socket.close().catchError((Object _) => socket);
      socket.destroy();
    }
  }

  Map<String, Object?> _normalizeConversation(Map<String, Object?> item) {
    final payload = _asMap(item['payload']);
    final channelType = _intValue(item, ['channel_type']);
    final type = channelType == _requireChat().channelTypeGroup
        ? 'group'
        : 'private';
    final resolvedType = channelType == 0
        ? (type == 'group'
              ? _requireChat().channelTypeGroup
              : _requireChat().channelTypePerson)
        : channelType;
    final channelId = _canonicalChannelId(
      resolvedType == _requireChat().channelTypePerson
          ? _privateChannelIdFromConversation(item, payload)
          : _value(item, ['channel_id', 'uid', 'group_id', 'id']),
      resolvedType,
    );
    final receiverId = resolvedType == _requireChat().channelTypePerson
        ? _privateReceiverIdFromConversation(item, payload, channelId)
        : '';
    final unread =
        _isConversationRead(
          channelId: channelId,
          channelType: resolvedType,
          item: item,
        )
        ? 0
        : _intValue(item, ['unread_quantity', 'unread']);
    final contentType = _value(item, [
      'content_type',
    ], fallback: payload['content_type']?.toString() ?? '');
    final content = _value(item, [
      'content',
    ], fallback: _payloadContent(payload));
    final displayable = _isDisplayableChatPayload(
      payload,
      contentType: contentType,
    );
    return <String, Object?>{
      ...item,
      'conversation_type': item['conversation_type']?.toString() ?? type,
      'channel_type': resolvedType,
      'channel_id': channelId,
      if (receiverId.isNotEmpty) 'receiver_id': receiverId,
      'content': displayable ? content : '',
      'content_type': displayable ? contentType : '',
      'payload': payload,
      'msg_time': displayable
          ? _value(item, ['msg_time', 'create_time', 'timestamp'])
          : '',
      'unread_quantity': displayable ? unread : 0,
    };
  }

  Map<String, Object?> _normalizeHistoryMessage(
    Map<String, Object?> item, {
    required String channelId,
    required int channelType,
  }) {
    final raw = _asMap(item['raw']);
    final message = _asMap(item['message']);
    final payload = _asMap(message['payload']);
    final fromUser = _asMap(item['fromUser']);
    final contentType = _value(message, [
      'content_type',
    ], fallback: payload['content_type']?.toString() ?? '');
    if (!_isDisplayableChatPayload(payload, contentType: contentType)) {
      return const <String, Object?>{};
    }
    final fromUid = _value(
      raw,
      ['from_uid'],
      fallback: _value(payload, [
        'sender_uid',
      ], fallback: _uidFromUser(fromUser)),
    );
    final canonicalChannelId = _canonicalChannelId(channelId, channelType);
    final senderId = _value(payload, [
      'sender_id',
      'from_id',
      'user_id',
      'userid',
    ], fallback: _value(fromUser, ['id', 'user_id', 'userid']));
    return <String, Object?>{
      'message_id': _value(raw, [
        'message_id',
        'message_idstr',
      ], fallback: _value(message, ['id'])),
      'client_msg_no': _value(message, [
        'client_msg_no',
      ], fallback: _value(raw, ['client_msg_no'])),
      'message_seq': _intValue(message, [
        'message_seq',
      ], fallback: _intValue(raw, ['message_seq'])),
      'channel_id': canonicalChannelId,
      'channel_type': channelType,
      'from_uid': fromUid,
      'is_me': _isCurrentUserMessage(senderId: senderId, senderUid: fromUid),
      'content': _value(message, [
        'content',
      ], fallback: _payloadContent(payload)),
      'content_type': contentType,
      'payload': payload.isEmpty ? message : payload,
      'timestamp': _value(message, ['create_time', 'timestamp']),
      'status': 'sent',
      'from_user': fromUser,
    };
  }

  Map<String, Object?> _normalizeSendResult(
    Map<String, Object?> result, {
    required Map<String, Object?> fallback,
    required String channelId,
    required int channelType,
  }) {
    final payload = _asMap(result['payload']);
    final fallbackPayload = _asMap(fallback['payload']);
    final mergedPayload = payload.isEmpty
        ? fallbackPayload
        : <String, Object?>{
            ...payload,
            if (_value(fallbackPayload, ['file_path']).isNotEmpty)
              'file_path': _value(fallbackPayload, ['file_path']),
            if (_value(fallbackPayload, ['name']).isNotEmpty &&
                _value(payload, ['name', 'file_name']).isEmpty)
              'name': _value(fallbackPayload, ['name']),
            if (_value(fallbackPayload, ['size']).isNotEmpty &&
                _value(payload, ['size', 'file_size']).isEmpty)
              'size': _value(fallbackPayload, ['size']),
            if (_value(fallbackPayload, ['mime']).isNotEmpty &&
                _value(payload, ['mime']).isEmpty)
              'mime': _value(fallbackPayload, ['mime']),
          };
    final sendAck = _asMap(result['send_ack']);
    return <String, Object?>{
      ...fallback,
      'message_id': _value(result, [
        'message_id',
      ], fallback: _value(sendAck, ['message_id'])),
      'client_msg_no': _value(result, [
        'client_msg_no',
      ], fallback: _value(fallback, ['client_msg_no'])),
      'channel_id': channelId,
      'channel_type': channelType,
      'content': _payloadContent(mergedPayload).isNotEmpty
          ? _payloadContent(mergedPayload)
          : fallback['content'],
      'content_type':
          mergedPayload['content_type']?.toString() ?? fallback['content_type'],
      'payload': mergedPayload.isEmpty ? fallback['payload'] : mergedPayload,
      'from_uid': _value(fallback, ['from_uid']),
      'is_me': fallback['is_me'] == true,
      'status': _boolValue(result['queued']) ? 'queued' : 'sent',
      'send_ack': sendAck,
    };
  }

  Map<String, Object?> _messageFromTcp(
    TcpRecvPacket packet,
    String channelId, {
    Map<String, Object?>? decodedPayload,
  }) {
    final payload = decodedPayload ?? _decodeBusinessPayload(packet.payload);
    if (!_isDisplayableChatPayload(payload)) {
      return const <String, Object?>{};
    }
    final canonicalChannelId = _canonicalChannelId(
      channelId,
      packet.channelType,
    );
    final receiverId = packet.channelType == _requireChat().channelTypePerson
        ? _receiverIdFromChannel(canonicalChannelId)
        : '';
    final fromUser = _userFromPayload(payload);
    return <String, Object?>{
      'message_id': packet.messageId.toString(),
      'client_msg_no': packet.clientMsgNo,
      'message_seq': packet.messageSeq,
      'channel_id': canonicalChannelId,
      'channel_type': packet.channelType,
      if (receiverId.isNotEmpty) 'receiver_id': receiverId,
      'from_uid': packet.fromUid,
      'is_me': _isCurrentUserMessage(
        senderId: _value(payload, [
          'sender_id',
          'from_id',
          'user_id',
          'userid',
        ]),
        senderUid: _value(payload, [
          'sender_uid',
          'from_uid',
        ], fallback: packet.fromUid),
      ),
      'content': _payloadContent(payload),
      'content_type': payload['content_type']?.toString() ?? '',
      'payload': payload,
      'timestamp': _formatTimestamp(packet.messageTime),
      'status': 'sent',
      if (fromUser.isNotEmpty) 'from_user': fromUser,
      'header': {
        'no_persist': packet.header.noPersist,
        'show_unread': packet.header.showUnread,
        'sync_once': packet.header.syncOnce,
      },
    };
  }

  Map<String, Object?> _userFromPayload(Map<String, Object?> payload) {
    final senderId = _value(payload, [
      'sender_id',
      'from_id',
      'user_id',
      'userid',
    ]);
    final username = _value(payload, [
      'sender_username',
      'from_username',
      'username',
    ]);
    final nickname = _value(payload, [
      'sender_nickname',
      'from_nickname',
      'nickname',
    ]);
    final avatar = _value(payload, [
      'sender_avatar',
      'from_avatar',
      'usertx',
      'avatar',
    ]);
    if (senderId.isEmpty &&
        username.isEmpty &&
        nickname.isEmpty &&
        avatar.isEmpty) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      if (senderId.isNotEmpty) 'id': senderId,
      if (senderId.isNotEmpty) 'userid': senderId,
      if (username.isNotEmpty) 'username': username,
      if (nickname.isNotEmpty) 'nickname': nickname,
      if (avatar.isNotEmpty) 'usertx': avatar,
    };
  }

  Map<String, Object?> _messageFromConversationTail(
    Map<String, Object?> conversation,
  ) {
    final channelType = _intValue(conversation, ['channel_type']);
    final channelId = _value(conversation, ['channel_id']);
    if (channelId.isEmpty || channelType <= 0) {
      return const <String, Object?>{};
    }
    final payload = _asMap(conversation['payload']);
    final clientMsgNo = _value(conversation, [
      'last_client_msg_no',
      'client_msg_no',
    ], fallback: _value(payload, ['client_msg_no']));
    final messageSeq = _intValue(conversation, [
      'last_msg_seq',
      'message_seq',
    ], fallback: _intValue(payload, ['message_seq']));
    final content = _value(conversation, [
      'content',
    ], fallback: _payloadContent(payload));
    final contentType = _value(conversation, [
      'content_type',
    ], fallback: payload['content_type']?.toString() ?? '');
    if (!_isDisplayableChatPayload(payload, contentType: contentType)) {
      return const <String, Object?>{};
    }
    final timestamp = _value(conversation, [
      'msg_time',
      'create_time',
      'timestamp',
    ]);
    if (clientMsgNo.isEmpty &&
        messageSeq <= 0 &&
        content.isEmpty &&
        timestamp.isEmpty) {
      return const <String, Object?>{};
    }
    final fromUid = _value(conversation, [
      'from_uid',
      'sender_uid',
    ], fallback: _value(payload, ['from_uid', 'sender_uid']));
    final senderId = _value(
      conversation,
      ['sender_id', 'from_id', 'user_id', 'userid'],
      fallback: _value(payload, ['sender_id', 'from_id', 'user_id', 'userid']),
    );
    final normalizedPayload = payload.isEmpty
        ? _cleanPayload({
            'content': _value(conversation, ['content']),
            'content_type': contentType,
            if (clientMsgNo.isNotEmpty) 'client_msg_no': clientMsgNo,
          })
        : payload;
    return <String, Object?>{
      'message_id': _value(conversation, ['message_id', 'message_idstr']),
      'client_msg_no': clientMsgNo.isNotEmpty
          ? clientMsgNo
          : _conversationTailLocalMsgNo(
              channelId: channelId,
              channelType: channelType,
              messageSeq: messageSeq,
              content: content,
              timestamp: timestamp,
            ),
      'message_seq': messageSeq,
      'channel_id': channelId,
      'channel_type': channelType,
      if (_value(conversation, ['receiver_id']).isNotEmpty)
        'receiver_id': _value(conversation, ['receiver_id']),
      'from_uid': fromUid,
      'is_me': _isCurrentUserMessage(senderId: senderId, senderUid: fromUid),
      'content': content,
      'content_type': contentType,
      'payload': normalizedPayload,
      'timestamp': timestamp,
      'status': 'sent',
      'from_conversation_tail': true,
    };
  }

  String _conversationTailLocalMsgNo({
    required String channelId,
    required int channelType,
    required int messageSeq,
    required String content,
    required String timestamp,
  }) {
    final source = '$channelType|$channelId|$messageSeq|$timestamp|$content';
    return 'conversation_tail_${_crypto.md5Text(source)}';
  }

  Map<String, Object?> _localOutgoingMessage({
    required String channelId,
    required int channelType,
    required String clientMsgNo,
    required String contentType,
    required Map<String, Object?> payload,
  }) {
    return <String, Object?>{
      'message_id': '',
      'client_msg_no': clientMsgNo,
      'message_seq': 0,
      'channel_id': channelId,
      'channel_type': channelType,
      'from_uid': _requireChat().uid,
      'is_me': true,
      'content': _payloadContent(payload),
      'content_type': contentType,
      'payload': payload,
      'timestamp': _formatTimestamp(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ),
      'status': 'sending',
    };
  }

  Map<String, Object?> _decodeBusinessPayload(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const <String, Object?>{};
    }
    final direct = _tryJsonMap(text);
    if (direct.isNotEmpty) {
      return direct;
    }
    try {
      final decoded = utf8.decode(base64Decode(text));
      final base64Json = _tryJsonMap(decoded);
      if (base64Json.isNotEmpty) {
        return base64Json;
      }
      return {'content': decoded};
    } catch (_) {
      return {'content': text};
    }
  }

  bool _isDisplayableChatPayload(
    Map<String, Object?> payload, {
    String contentType = '',
  }) {
    final type = contentType.isNotEmpty
        ? contentType
        : payload['content_type']?.toString() ?? '';
    if (payload['protocol']?.toString() != 'blin.chat.v1') {
      return false;
    }
    if (type == 'cmd' || type == 'recall') {
      return false;
    }
    return ChatContentTypes.displayable.contains(type);
  }

  bool _handleCommandPayload(
    Map<String, Object?> payload,
    String channelId,
    int channelType,
  ) {
    if (payload['protocol']?.toString() != 'blin.chat.v1' ||
        payload['content_type']?.toString() != 'cmd') {
      return false;
    }
    final cmd = payload['cmd']?.toString() ?? '';
    if (cmd != 'group_member_mute_changed' &&
        cmd != 'group_mute_changed' &&
        cmd != 'group_member_unmute') {
      return false;
    }
    final chat = _requireChat();
    if (channelType != chat.channelTypeGroup) {
      return true;
    }
    final targetUid = _value(payload, ['target_uid', 'member_uid']);
    final targetUserId = _value(payload, ['target_user_id', 'member_id']);
    final selfUserId = _requireSession().userId.toString();
    final targetsSelf =
        (targetUid.isNotEmpty && targetUid == chat.uid) ||
        (targetUserId.isNotEmpty && targetUserId == selfUserId);
    if (!targetsSelf) {
      return true;
    }
    applyGroupMuteState(
      channelID: channelId,
      groupId: _value(payload, ['group_id']),
      state: payload,
      source: 'tcp_cmd',
    );
    return true;
  }

  Map<String, Object?> _normalizeGroupMuteState(
    Map<String, Object?> state, {
    required String channelId,
    required String groupId,
  }) {
    final expireTime = _value(state, ['expire_time', 'mute_expire_time']);
    final muted = _boolValue(state['muted']);
    final permanent =
        _boolValue(state['permanent']) ||
        _boolValue(state['mute_permanent']) ||
        (muted && expireTime.isEmpty);
    final reason = _value(state, ['reason']);
    final resolvedGroupId = _value(state, [
      'group_id',
    ], fallback: groupId.isNotEmpty ? groupId : _groupIdForChannel(channelId));
    return <String, Object?>{
      ...state,
      'group_id': resolvedGroupId,
      'channel_id': channelId,
      'channel_type': _requireChat().channelTypeGroup,
      'muted': muted ? 1 : 0,
      'permanent': permanent ? 1 : 0,
      'reason': reason,
      'expire_time': expireTime,
      'notice': _groupMuteNotice(
        muted: muted,
        reason: reason,
        expireTime: expireTime,
        permanent: permanent,
        fallback: _value(state, ['notice']),
      ),
    };
  }

  String _activeGroupMuteNotice(Map<String, Object?> state) {
    if (!_boolValue(state['muted'])) {
      return '';
    }
    final expireTime = _value(state, ['expire_time', 'mute_expire_time']);
    if (expireTime.isNotEmpty) {
      final expireAt = _parseServerTime(expireTime);
      if (expireAt != null && !expireAt.isAfter(DateTime.now())) {
        return '';
      }
    }
    return _groupMuteNotice(
      muted: true,
      reason: _value(state, ['reason']),
      expireTime: expireTime,
      permanent:
          _boolValue(state['permanent']) ||
          _boolValue(state['mute_permanent']) ||
          expireTime.isEmpty,
      fallback: _value(state, ['notice']),
    );
  }

  String _groupMuteNotice({
    required bool muted,
    required String reason,
    required String expireTime,
    required bool permanent,
    required String fallback,
  }) {
    if (fallback.isNotEmpty) {
      return fallback;
    }
    if (!muted) {
      return '你已恢复群内发言';
    }
    final parts = <String>['你已被管理员禁言'];
    if (reason.isNotEmpty) {
      parts.add('原因：$reason');
    }
    parts.add(permanent ? '永久生效' : '至 $expireTime');
    return parts.join('，');
  }

  DateTime? _parseServerTime(String value) {
    final numeric = int.tryParse(value);
    if (numeric != null) {
      final millis = numeric > 100000000000 ? numeric : numeric * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return DateTime.tryParse(value.replaceFirst(' ', 'T'));
  }

  Map<String, Object?> _tryJsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
  }

  void _upsertMessage(
    String channelId,
    int channelType,
    Map<String, Object?> message,
  ) {
    if (!_messageVisibleAfterClear(message) || !_messageNotDeleted(message)) {
      return;
    }
    final messages = _readMessagesForChannel(channelId, channelType).toList();
    final clientMsgNo = message['client_msg_no']?.toString() ?? '';
    final messageSeq = _intValue(message, ['message_seq']);
    final index = messages.indexWhere(
      (item) => _sameMessageIdentity(item, clientMsgNo, messageSeq),
    );
    if (index >= 0) {
      messages[index] = _mergeMessageFields(messages[index], message);
    } else {
      messages.add(message);
    }
    _writeMessages(channelId, channelType, _sortAndLimit(messages, 200));
  }

  void _seedConversationTailMessages(
    List<Map<String, Object?>> conversations, {
    required String source,
  }) {
    for (final conversation in conversations) {
      final channelType = _intValue(conversation, ['channel_type']);
      final channelId = _value(conversation, ['channel_id']);
      if (channelId.isEmpty || channelType <= 0) {
        continue;
      }
      final current = _readMessagesForChannel(channelId, channelType);
      _seedConversationTailMessageForChannel(
        channelId,
        channelType,
        current,
        conversation: conversation,
        source: source,
      );
    }
  }

  List<Map<String, Object?>> _seedConversationTailMessageForChannel(
    String channelId,
    int channelType,
    List<Map<String, Object?>> current, {
    Map<String, Object?>? conversation,
    required String source,
  }) {
    final normalizedChannelId = _canonicalChannelId(channelId, channelType);
    final sourceConversation =
        conversation ??
        _conversationForChannel(normalizedChannelId, channelType);
    if (sourceConversation.isEmpty) {
      return current;
    }
    final tail = _messageFromConversationTail(sourceConversation);
    if (tail.isEmpty) {
      return current;
    }
    if (!_messageVisibleAfterClear(tail) || !_messageNotDeleted(tail)) {
      return current;
    }
    final merged = _mergeMessages(current, [tail]);
    final sorted = _sortAndLimit(merged, 200);
    if (_tailMessageMissing(tail, current) ||
        !_sameMessageList(current, sorted)) {
      _writeMessages(normalizedChannelId, channelType, sorted);
      _markMessageChannel(
        source: 'conversation_tail_$source',
        channelId: normalizedChannelId,
        channelType: channelType,
      );
    }
    return sorted;
  }

  List<Map<String, Object?>> _readMessagesForChannel(
    String channelId,
    int channelType,
  ) {
    final chat = _requireChat();
    final primary = _cache
        .readMessages(
          uid: chat.uid,
          channelId: channelId,
          channelType: channelType,
        )
        .toList();
    if (channelType == chat.channelTypeGroup) {
      return _filterVisibleMessages(
        _readAliasMessagesForChannel(
          channelId: channelId,
          channelType: channelType,
          primary: primary,
          belongsToAlias: (message) =>
              _messageBelongsToGroup(message, channelId),
          logSource: 'group message cache migrated',
        ),
      );
    }
    if (channelType != chat.channelTypePerson) {
      return _filterVisibleMessages(primary);
    }

    return _filterVisibleMessages(
      _readAliasMessagesForChannel(
        channelId: channelId,
        channelType: channelType,
        primary: primary,
        belongsToAlias: (message) =>
            _messageBelongsToPrivatePeer(message, channelId),
        logSource: 'private message cache migrated',
      ),
    );
  }

  List<Map<String, Object?>> _readAliasMessagesForChannel({
    required String channelId,
    required int channelType,
    required List<Map<String, Object?>> primary,
    required bool Function(Map<String, Object?> message) belongsToAlias,
    required String logSource,
  }) {
    final chat = _requireChat();
    final merged = primary
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    var migrated = false;
    for (final recent in _cache.readRecentChannels(chat.uid)) {
      final parts = recent.split(':');
      if (parts.length != 2 || parts[0] != channelType.toString()) {
        continue;
      }
      final aliasChannelId = parts[1];
      if (aliasChannelId == channelId) {
        continue;
      }
      final aliasMessages = _cache.readMessages(
        uid: chat.uid,
        channelId: aliasChannelId,
        channelType: channelType,
      );
      for (final raw in aliasMessages) {
        final message = Map<String, Object?>.from(raw);
        if (!belongsToAlias(message)) {
          continue;
        }
        migrated = true;
        message['channel_id'] = channelId;
        final clientMsgNo = message['client_msg_no']?.toString() ?? '';
        final index = clientMsgNo.isEmpty
            ? -1
            : merged.indexWhere(
                (item) => item['client_msg_no']?.toString() == clientMsgNo,
              );
        if (index >= 0) {
          merged[index] = _mergeMessageFields(merged[index], message);
        } else {
          merged.add(message);
        }
      }
    }
    if (migrated) {
      final sorted = _sortAndLimit(merged, 200);
      _writeMessages(channelId, channelType, sorted);
      AppLogger.info(
        'im',
        logSource,
        data: {'channel_id': channelId, 'count': sorted.length},
      );
      return sorted;
    }
    return primary;
  }

  void _publishMessageEvent({
    required String source,
    required String channelId,
    required int channelType,
    required Map<String, Object?> message,
  }) {
    if (_messageEvents.isClosed) {
      return;
    }
    final conversation = _conversationForChannel(channelId, channelType);
    _messageEvents.add(
      BusinessImMessageEvent(
        source: source,
        channelId: channelId,
        channelType: channelType,
        message: Map<String, Object?>.from(message),
        conversation: conversation,
      ),
    );
  }

  List<Map<String, Object?>> _mergeMessages(
    List<Map<String, Object?>> current,
    List<Map<String, Object?>> incoming,
  ) {
    final merged = current
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    for (final message in incoming) {
      final clientMsgNo = message['client_msg_no']?.toString() ?? '';
      final messageSeq = _intValue(message, ['message_seq']);
      final index = merged.indexWhere(
        (item) => _sameMessageIdentity(item, clientMsgNo, messageSeq),
      );
      if (index >= 0) {
        merged[index] = _mergeMessageFields(merged[index], message);
      } else {
        merged.add(message);
      }
    }
    return merged;
  }

  bool _sameMessageIdentity(
    Map<String, Object?> item,
    String clientMsgNo,
    int messageSeq,
  ) {
    if (clientMsgNo.isNotEmpty &&
        item['client_msg_no']?.toString() == clientMsgNo) {
      return true;
    }
    return messageSeq > 0 && _intValue(item, ['message_seq']) == messageSeq;
  }

  Map<String, Object?> _mergeMessageFields(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final merged = <String, Object?>{...existing, ...incoming};
    final sameClientMsgNo =
        _value(existing, ['client_msg_no']).isNotEmpty &&
        _value(existing, ['client_msg_no']) ==
            _value(incoming, ['client_msg_no']);
    if (sameClientMsgNo && existing['is_me'] == true) {
      merged['is_me'] = true;
      merged['from_uid'] = _value(existing, [
        'from_uid',
      ], fallback: _requireChat().uid);
    }
    return merged;
  }

  bool _tailMessageMissing(
    Map<String, Object?> tail,
    List<Map<String, Object?>> messages,
  ) {
    final clientMsgNo = _value(tail, ['client_msg_no']);
    final messageSeq = _intValue(tail, ['message_seq']);
    return !messages.any(
      (item) => _sameMessageIdentity(item, clientMsgNo, messageSeq),
    );
  }

  bool _sameMessageList(
    List<Map<String, Object?>> left,
    List<Map<String, Object?>> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (jsonEncode(left[index]) != jsonEncode(right[index])) {
        return false;
      }
    }
    return true;
  }

  void _writeMessages(
    String channelId,
    int channelType,
    List<Map<String, Object?>> messages,
  ) {
    final visible = _filterVisibleMessages(messages);
    _cache.writeMessages(
      uid: _requireChat().uid,
      channelId: channelId,
      channelType: channelType,
      messages: visible,
    );
  }

  bool _conversationTailMissing(
    String channelId,
    int channelType,
    List<Map<String, Object?>> messages,
  ) {
    final conversation = _conversationForChannel(channelId, channelType);
    if (conversation.isEmpty) {
      return false;
    }
    final lastClientMsgNo = _value(conversation, [
      'last_client_msg_no',
      'client_msg_no',
    ]);
    final lastSeq = _intValue(conversation, ['last_msg_seq', 'message_seq']);
    if (lastClientMsgNo.isEmpty && lastSeq <= 0) {
      return false;
    }
    for (final message in messages) {
      if (lastClientMsgNo.isNotEmpty &&
          _value(message, ['client_msg_no']) == lastClientMsgNo) {
        return false;
      }
      if (lastSeq > 0 && _intValue(message, ['message_seq']) == lastSeq) {
        return false;
      }
    }
    return true;
  }

  void _writeReadMarkerForMessages(
    String channelId,
    int channelType,
    List<Map<String, Object?>> messages,
  ) {
    final chat = _requireChat();
    final lastSeq = messages.fold<int>(
      0,
      (maxSeq, item) => max(maxSeq, _intValue(item, ['message_seq'])),
    );
    final sorted = _sortAndLimit(messages, messages.length);
    final lastMsgNo = sorted.isEmpty
        ? ''
        : sorted.last['client_msg_no']?.toString() ?? '';
    _cache.writeReadMarker(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
      marker: {
        'message_seq': lastSeq,
        'client_msg_no': lastMsgNo,
        'read_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
    );
  }

  void _upsertConversationFromMessage(Map<String, Object?> message) {
    final chat = _requireChat();
    final channelId = message['channel_id']?.toString() ?? '';
    final channelType =
        int.tryParse(message['channel_type']?.toString() ?? '') ?? 0;
    if (channelId.isEmpty || channelType <= 0) {
      return;
    }
    if (!_messageVisibleAfterClear(message) || !_messageNotDeleted(message)) {
      return;
    }
    final conversations = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList();
    final index = conversations.indexWhere(
      (item) =>
          item['channel_id']?.toString() == channelId &&
          (int.tryParse(item['channel_type']?.toString() ?? '') ?? 0) ==
              channelType,
    );
    final payload = _asMap(message['payload']);
    final content = message['content']?.toString() ?? _payloadContent(payload);
    final isCurrentOpen = _openMessageChannels.contains(
      _messageKey(channelId, channelType),
    );
    final isOutgoing = message['is_me'] == true;
    final previousUnread = index >= 0
        ? _intValue(conversations[index], ['unread_quantity'])
        : 0;
    final next = <String, Object?>{
      if (index >= 0) ...conversations[index],
      'conversation_type': channelType == chat.channelTypeGroup
          ? 'group'
          : 'private',
      if (channelType == chat.channelTypeGroup) ...{
        'group_id': _value(payload, ['group_id'], fallback: channelId),
        'name': _value(payload, ['group_name'], fallback: '群聊'),
        'group_name': _value(payload, ['group_name'], fallback: '群聊'),
      },
      if (channelType == chat.channelTypePerson)
        'receiver_id': _receiverIdFromMessage(message, channelId),
      'channel_id': channelId,
      'channel_type': channelType,
      'content': content,
      'content_type': message['content_type']?.toString() ?? '',
      'payload': payload,
      'msg_time': message['timestamp']?.toString() ?? '',
      'last_client_msg_no': message['client_msg_no']?.toString() ?? '',
      'last_msg_seq': message['message_seq'] ?? 0,
      'unread_quantity': isOutgoing || isCurrentOpen ? 0 : previousUnread + 1,
    };
    if (index >= 0) {
      conversations[index] = next;
    } else {
      conversations.insert(0, next);
    }
    conversations.sort(
      (a, b) => (b['msg_time']?.toString() ?? '').compareTo(
        a['msg_time']?.toString() ?? '',
      ),
    );
    _latestConversations = conversations;
    _cache.writeConversations(uid: chat.uid, conversations: conversations);
    _bumpConversations('message_upsert');
  }

  void _replaceConversationTailFromMessage(
    String channelId,
    int channelType,
    Map<String, Object?> message,
  ) {
    final chat = _requireChat();
    final conversations = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList();
    final index = conversations.indexWhere(
      (item) =>
          item['channel_id']?.toString() == channelId &&
          _intValue(item, ['channel_type']) == channelType,
    );
    final payload = _asMap(message['payload']);
    final previousUnread = index >= 0
        ? _intValue(conversations[index], ['unread_quantity'])
        : 0;
    final next = <String, Object?>{
      if (index >= 0) ...conversations[index],
      'conversation_type': channelType == chat.channelTypeGroup
          ? 'group'
          : 'private',
      if (channelType == chat.channelTypeGroup) ...{
        'group_id': _value(payload, ['group_id'], fallback: channelId),
        'name': _value(payload, ['group_name'], fallback: '群聊'),
        'group_name': _value(payload, ['group_name'], fallback: '群聊'),
      },
      if (channelType == chat.channelTypePerson)
        'receiver_id': _receiverIdFromMessage(message, channelId),
      'channel_id': channelId,
      'channel_type': channelType,
      'content': message['content']?.toString() ?? _payloadContent(payload),
      'content_type': message['content_type']?.toString() ?? '',
      'payload': payload,
      'msg_time': message['timestamp']?.toString() ?? '',
      'last_client_msg_no': message['client_msg_no']?.toString() ?? '',
      'last_msg_seq': message['message_seq'] ?? 0,
      'unread_quantity': previousUnread,
    };
    if (index >= 0) {
      conversations[index] = next;
    } else {
      conversations.insert(0, next);
    }
    conversations.sort(
      (a, b) => (b['msg_time']?.toString() ?? '').compareTo(
        a['msg_time']?.toString() ?? '',
      ),
    );
    _latestConversations = conversations;
    _cache.writeConversations(uid: chat.uid, conversations: conversations);
    _bumpConversations('replace_conversation_tail');
  }

  Map<String, Object?> _conversationForChannel(
    String channelId,
    int channelType,
  ) {
    final chat = _requireChat();
    for (final item in _cache.readConversations(chat.uid)) {
      if (item['channel_id']?.toString() == channelId &&
          (int.tryParse(item['channel_type']?.toString() ?? '') ?? 0) ==
              channelType) {
        final normalized = _normalizeConversation(item);
        if (!_conversationVisibleAfterClear(normalized)) {
          return const <String, Object?>{};
        }
        return normalized;
      }
    }
    return const <String, Object?>{};
  }

  bool _clearConversationUnread(
    String channelId,
    int channelType, {
    required String source,
  }) {
    final chat = _requireChat();
    final conversations = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList();
    final index = conversations.indexWhere(
      (item) =>
          item['channel_id']?.toString() == channelId &&
          (int.tryParse(item['channel_type']?.toString() ?? '') ?? 0) ==
              channelType,
    );
    if (index < 0 ||
        _intValue(conversations[index], ['unread_quantity']) == 0) {
      return false;
    }
    conversations[index] = {...conversations[index], 'unread_quantity': 0};
    _latestConversations = conversations;
    _cache.writeConversations(uid: chat.uid, conversations: conversations);
    _bumpConversations(source);
    return true;
  }

  List<Map<String, Object?>> _sortAndLimit(
    List<Map<String, Object?>> messages,
    int limit,
  ) {
    final sorted = messages.toList()
      ..sort((a, b) {
        final seqA = _intValue(a, ['message_seq']);
        final seqB = _intValue(b, ['message_seq']);
        if (seqA != seqB && seqA > 0 && seqB > 0) {
          return seqA.compareTo(seqB);
        }
        return (a['timestamp']?.toString() ?? '').compareTo(
          b['timestamp']?.toString() ?? '',
        );
      });
    if (sorted.length <= limit) {
      return sorted;
    }
    return sorted.sublist(sorted.length - limit);
  }

  void _markMessageChannel({
    required String source,
    required String channelId,
    required int channelType,
  }) {
    final key = _messageKey(channelId, channelType);
    _channelMessageVersions[key] = (_channelMessageVersions[key] ?? 0) + 1;
    AppLogger.info(
      'im',
      'message channel changed',
      data: {
        'source': source,
        'channel_id': channelId,
        'channel_type': channelType,
        'version': _channelMessageVersions[key],
      },
    );
    notifyListeners();
  }

  void _bumpConversations(String source, {bool notify = true}) {
    _conversationVersion++;
    AppLogger.info(
      'im',
      'conversations changed',
      data: {
        'source': source,
        'version': _conversationVersion,
        'count': _latestConversations.length,
      },
    );
    if (notify) {
      notifyListeners();
    }
  }

  void _setStatus(String text) {
    if (_statusText == text) {
      return;
    }
    _statusText = text;
    notifyListeners();
  }

  UserSession _requireSession() {
    final current = _session;
    if (current == null) {
      throw ApiException('请先登录', code: 401);
    }
    return current;
  }

  ChatSession _requireChat() {
    final chat = _requireSession().chat;
    if (chat == null) {
      throw ApiException('IM 登录材料缺失');
    }
    return chat;
  }

  _RealtimeEndpoint? _resolveRealtimeEndpoint(ImRoute route) {
    return _parseWebSocketEndpoint(route.wssAddr, preferSecure: true) ??
        _parseWebSocketEndpoint(route.websocketAddr, preferSecure: route.tls) ??
        _parseWebSocketEndpoint(route.wsAddr) ??
        _parseTcpEndpoint(route.tcpAddr);
  }

  _RealtimeEndpoint? _parseWebSocketEndpoint(
    String value, {
    bool preferSecure = false,
  }) {
    var raw = value.trim();
    if (raw.isEmpty) {
      return null;
    }
    if (!raw.contains('://')) {
      raw = '${preferSecure ? 'wss' : 'ws'}://$raw';
    }
    var uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      uri = uri.replace(scheme: scheme == 'https' ? 'wss' : 'ws');
    } else if (preferSecure && scheme == 'ws') {
      uri = uri.replace(scheme: 'wss');
    } else if (scheme != 'ws' && scheme != 'wss') {
      return null;
    }
    return _RealtimeEndpoint.websocket(uri);
  }

  _RealtimeEndpoint? _parseTcpEndpoint(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      return null;
    }
    final uri = raw.contains('://')
        ? Uri.tryParse(raw)
        : Uri.tryParse('tcp://$raw');
    if (uri == null || uri.host.isEmpty || uri.port <= 0) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        final port = int.tryParse(parts[1]);
        if (port != null) {
          return _RealtimeEndpoint.tcp(parts[0], port);
        }
      }
      return null;
    }
    return _RealtimeEndpoint.tcp(uri.host, uri.port);
  }

  Map<String, Object?> _cleanPayload(Map<String, Object?> payload) {
    return Map<String, Object?>.fromEntries(
      payload.entries.where(
        (entry) => entry.value != null && entry.value.toString().isNotEmpty,
      ),
    );
  }

  List<Map<String, Object?>> _filterVisibleMessages(
    List<Map<String, Object?>> messages,
  ) {
    return messages
        .where(_messageVisibleAfterClear)
        .where(_messageNotDeleted)
        .toList(growable: false);
  }

  bool _conversationVisibleAfterClear(Map<String, Object?> conversation) {
    final chat = _session?.chat;
    if (chat == null) {
      return true;
    }
    final channelId = _value(conversation, ['channel_id']);
    final channelType = _intValue(conversation, ['channel_type']);
    if (channelId.isEmpty || channelType <= 0) {
      return false;
    }
    final boundary = _cache.readChannelClearMarker(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
    );
    if (boundary <= 0) {
      return true;
    }
    final timestamp = _objectTimestampMs(conversation, [
      'msg_time',
      'timestamp',
      'create_time',
    ]);
    return timestamp > boundary;
  }

  bool _messageVisibleAfterClear(Map<String, Object?> message) {
    final chat = _session?.chat;
    if (chat == null) {
      return true;
    }
    final channelId = _value(message, ['channel_id']);
    final channelType = _intValue(message, ['channel_type']);
    if (channelId.isEmpty || channelType <= 0) {
      return false;
    }
    final boundary = _cache.readChannelClearMarker(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
    );
    if (boundary <= 0) {
      return true;
    }
    final timestamp = _objectTimestampMs(message, [
      'timestamp',
      'create_time',
      'msg_time',
    ]);
    return timestamp > boundary;
  }

  bool _messageNotDeleted(Map<String, Object?> message) {
    final chat = _session?.chat;
    if (chat == null) {
      return true;
    }
    final clientMsgNo = _value(message, ['client_msg_no']);
    if (clientMsgNo.isEmpty) {
      return true;
    }
    final channelId = _value(message, ['channel_id']);
    final channelType = _intValue(message, ['channel_type']);
    if (channelId.isEmpty || channelType <= 0) {
      return false;
    }
    final deleted = _cache.readDeletedMessages(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
    );
    return !deleted.contains(clientMsgNo);
  }

  int _objectTimestampMs(Map<String, Object?> item, List<String> keys) {
    for (final key in keys) {
      final timestamp = _timestampMs(item[key]);
      if (timestamp > 0) {
        return timestamp;
      }
    }
    final payload = _asMap(item['payload']);
    for (final key in [
      'create_time',
      'client_timestamp',
      'timestamp',
      'msg_time',
    ]) {
      final timestamp = _timestampMs(payload[key]);
      if (timestamp > 0) {
        return timestamp;
      }
    }
    return 0;
  }

  int _timestampMs(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is num) {
      final number = value.toInt();
      return number > 100000000000 ? number : number * 1000;
    }
    final text = value.toString().trim();
    if (text.isEmpty) {
      return 0;
    }
    final numeric = int.tryParse(text);
    if (numeric != null) {
      return numeric > 100000000000 ? numeric : numeric * 1000;
    }
    final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    return parsed?.millisecondsSinceEpoch ?? 0;
  }

  String _payloadContent(Map<String, Object?> payload) {
    final content = payload['content']?.toString() ?? '';
    if (content.isNotEmpty) {
      return content;
    }
    return switch (payload['content_type']?.toString()) {
      ChatContentTypes.image => '[图片]',
      ChatContentTypes.emoji => '[表情]',
      ChatContentTypes.gif => '[GIF]',
      ChatContentTypes.sticker => '[贴纸]',
      ChatContentTypes.voice => '[语音]',
      ChatContentTypes.video => '[视频]',
      ChatContentTypes.file => '[文件]',
      ChatContentTypes.contactCard => '[名片]',
      ChatContentTypes.transfer => '[转账]',
      ChatContentTypes.redPacket => '[红包]',
      ChatContentTypes.redPacketReceived => '[领取红包]',
      ChatContentTypes.transferReceived => '[已收款]',
      _ => '',
    };
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  String _value(
    Map<dynamic, dynamic> map,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    return fallback;
  }

  int _intValue(
    Map<dynamic, dynamic> map,
    List<String> keys, {
    int fallback = 0,
  }) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
    return fallback;
  }

  bool _boolValue(Object? value) {
    if (value is bool) {
      return value;
    }
    return value?.toString() == '1' || value?.toString() == 'true';
  }

  String _receiverIdFromChannel(String channelId) {
    final match = RegExp(r'user(\d+)$').firstMatch(channelId);
    return match?.group(1) ?? channelId;
  }

  String _canonicalChannelId(String channelId, int channelType) {
    if (channelId.isEmpty) {
      return channelId;
    }
    final chat = _requireChat();
    if (channelType == chat.channelTypeGroup) {
      return _canonicalGroupChannelId(channelId);
    }
    if (channelType != chat.channelTypePerson) {
      return channelId;
    }
    if (_isCurrentUserChannel(channelId)) {
      final fromConversation = _privatePeerChannelFromConversations(channelId);
      return fromConversation.isNotEmpty ? fromConversation : channelId;
    }
    return _uidFromUserId(_receiverIdFromChannel(channelId));
  }

  String _canonicalGroupChannelId(String channelId) {
    final chat = _requireChat();
    for (final item in _cache.readConversations(chat.uid)) {
      final itemChannelId = _value(item, ['channel_id', 'uid']);
      final itemGroupId = _value(item, ['group_id', 'id']);
      if (channelId == itemChannelId) {
        return itemChannelId;
      }
      if (itemGroupId.isNotEmpty && channelId == itemGroupId) {
        return itemChannelId.isNotEmpty ? itemChannelId : channelId;
      }
    }
    return channelId;
  }

  String _privatePeerChannelFromConversations(String channelId) {
    final chat = _requireChat();
    for (final item in _cache.readConversations(chat.uid)) {
      final itemChannelId = _value(item, ['channel_id', 'uid']);
      if (itemChannelId != channelId) {
        continue;
      }
      final receiverId = _privateReceiverIdFromConversation(
        item,
        _asMap(item['payload']),
        channelId,
      );
      if (receiverId.isNotEmpty &&
          receiverId != _requireSession().userId.toString()) {
        return _uidFromUserId(receiverId);
      }
    }
    return '';
  }

  String _privateChannelIdFromConversation(
    Map<String, Object?> item,
    Map<String, Object?> payload,
  ) {
    final candidates = [
      _value(item, ['peer_uid', 'opposite_uid', 'target_uid', 'receiver_uid']),
      _value(payload, [
        'peer_uid',
        'opposite_uid',
        'target_uid',
        'receiver_uid',
      ]),
      _value(item, ['from_uid']),
      _value(payload, ['from_uid', 'sender_uid']),
      _value(item, ['to_uid']),
      _value(payload, ['to_uid']),
      _value(item, ['channel_id', 'uid']),
    ];
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && !_isCurrentUserChannel(candidate)) {
        return candidate;
      }
    }
    final receiverId = _privateReceiverIdFromConversation(item, payload, '');
    if (receiverId.isNotEmpty) {
      return _uidFromUserId(receiverId);
    }
    return _value(item, ['channel_id', 'uid']);
  }

  String _privateReceiverIdFromConversation(
    Map<String, Object?> item,
    Map<String, Object?> payload,
    String channelId,
  ) {
    final candidates = [
      _value(item, [
        'receiver_id',
        'peer_id',
        'friend_id',
        'user_id',
        'userid',
      ]),
      _value(payload, [
        'receiver_id',
        'peer_id',
        'friend_id',
        'user_id',
        'userid',
      ]),
    ];
    final currentUserId = _requireSession().userId.toString();
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && candidate != currentUserId) {
        return candidate;
      }
    }
    return channelId.isEmpty ? '' : _receiverIdFromChannel(channelId);
  }

  String _receiverIdFromMessage(
    Map<String, Object?> message,
    String channelId,
  ) {
    final payload = _asMap(message['payload']);
    final value = _value(message, [
      'receiver_id',
    ], fallback: _value(payload, ['receiver_id', 'peer_id', 'friend_id']));
    return value.isNotEmpty ? value : _receiverIdFromChannel(channelId);
  }

  bool _messageBelongsToPrivatePeer(
    Map<String, Object?> message,
    String channelId,
  ) {
    final peerId = _receiverIdFromChannel(channelId);
    if (peerId.isEmpty) {
      return false;
    }
    final currentUid = _requireChat().uid;
    final fromUid = _value(message, ['from_uid']);
    if (fromUid.isNotEmpty &&
        fromUid != currentUid &&
        _receiverIdFromChannel(fromUid) == peerId) {
      return true;
    }
    final payload = _asMap(message['payload']);
    final candidates = [
      _value(message, ['channel_id']),
      _value(message, ['receiver_id', 'peer_id', 'friend_id']),
      _value(payload, ['receiver_id', 'peer_id', 'friend_id']),
      _value(payload, ['from_uid', 'sender_uid']),
      _value(payload, ['to_uid', 'target_uid']),
    ];
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && _receiverIdFromChannel(candidate) == peerId) {
        return true;
      }
    }
    return false;
  }

  bool _messageBelongsToGroup(Map<String, Object?> message, String channelId) {
    final groupId = _groupIdForChannel(channelId);
    final payload = _asMap(message['payload']);
    final candidates = [
      _value(message, ['channel_id']),
      _value(message, ['group_id']),
      _value(payload, ['channel_id']),
      _value(payload, ['group_id']),
    ];
    for (final candidate in candidates) {
      if (candidate.isEmpty) {
        continue;
      }
      if (candidate == channelId || candidate == groupId) {
        return true;
      }
    }
    return false;
  }

  bool _isConversationRead({
    required String channelId,
    required int channelType,
    required Map<String, Object?> item,
  }) {
    final marker = _cache.readReadMarker(
      uid: _requireChat().uid,
      channelId: channelId,
      channelType: channelType,
    );
    if (marker.isEmpty) {
      return false;
    }
    final markerSeq = _intValue(marker, ['message_seq']);
    final lastSeq = _intValue(item, ['last_msg_seq', 'message_seq']);
    if (markerSeq > 0 && lastSeq > 0 && lastSeq <= markerSeq) {
      return true;
    }
    final markerMsgNo = _value(marker, ['client_msg_no']);
    final lastMsgNo = _value(item, ['last_client_msg_no', 'client_msg_no']);
    if (markerMsgNo.isNotEmpty && markerMsgNo == lastMsgNo) {
      return true;
    }
    return false;
  }

  bool _isCurrentUserChannel(String channelId) {
    final current = _requireSession();
    final chat = _requireChat();
    if (channelId == chat.uid || channelId == current.userId.toString()) {
      return true;
    }
    return _receiverIdFromChannel(channelId) == current.userId.toString();
  }

  bool _isCurrentUserMessage({String senderId = '', String senderUid = ''}) {
    final current = _requireSession();
    final chat = _requireChat();
    final currentUserId = current.userId.toString();
    if (senderId.isNotEmpty && senderId == currentUserId) {
      return true;
    }
    if (senderUid.isNotEmpty && senderUid == chat.uid) {
      return true;
    }
    if (senderUid.isNotEmpty &&
        _receiverIdFromChannel(senderUid) == currentUserId) {
      return true;
    }
    return false;
  }

  String _groupIdForChannel(String channelId) {
    final conversations = _cache.readConversations(_requireChat().uid);
    for (final item in conversations) {
      if (item['channel_id']?.toString() != channelId) {
        continue;
      }
      final groupId = _value(item, ['group_id', 'id']);
      if (groupId.isNotEmpty) {
        return groupId;
      }
    }
    return channelId;
  }

  String _uidFromUser(Map<String, Object?> user) {
    final uid = user['uid']?.toString() ?? '';
    if (uid.isNotEmpty) {
      return uid;
    }
    final id =
        user['id']?.toString() ??
        user['userid']?.toString() ??
        user['user_id']?.toString() ??
        '';
    return id.isEmpty ? '' : 'app${AppConfig.appId}user$id';
  }

  String _uidFromUserId(String userId) {
    if (userId.startsWith('app')) {
      return userId;
    }
    return 'app${AppConfig.appId}user$userId';
  }

  String _formatTimestamp(int seconds) {
    if (seconds <= 0) {
      return DateTime.now().toIso8601String().substring(0, 19);
    }
    return DateTime.fromMillisecondsSinceEpoch(
      seconds * 1000,
    ).toIso8601String().substring(0, 19).replaceFirst('T', ' ');
  }

  String _messageKey(String channelID, int channelType) {
    return '$channelType:$channelID';
  }

  @override
  void dispose() {
    unawaited(stop());
    unawaited(_messageEvents.close());
    super.dispose();
  }
}

class BusinessImMessageEvent {
  const BusinessImMessageEvent({
    required this.source,
    required this.channelId,
    required this.channelType,
    required this.message,
    required this.conversation,
  });

  final String source;
  final String channelId;
  final int channelType;
  final Map<String, Object?> message;
  final Map<String, Object?> conversation;
}

class _RealtimeEndpoint {
  const _RealtimeEndpoint._({
    required this.uri,
    required this.isWebSocket,
    required this.transport,
  });

  factory _RealtimeEndpoint.websocket(Uri uri) {
    return _RealtimeEndpoint._(
      uri: uri,
      isWebSocket: true,
      transport: uri.scheme.toLowerCase() == 'wss' ? 'wss' : 'ws',
    );
  }

  factory _RealtimeEndpoint.tcp(String host, int port) {
    return _RealtimeEndpoint._(
      uri: Uri(scheme: 'tcp', host: host, port: port),
      isWebSocket: false,
      transport: 'tcp',
    );
  }

  final Uri uri;
  final bool isWebSocket;
  final String transport;

  String get logAddress =>
      isWebSocket ? uri.toString() : '${uri.host}:${uri.port}';
}
