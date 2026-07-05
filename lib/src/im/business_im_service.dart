import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/models.dart';
import 'gateway_stream_client.dart';
import 'im_cache_store.dart';
import 'im_message_types.dart';
import 'message_notification_sound.dart';

class BusinessImService extends ChangeNotifier {
  BusinessImService({required ApiClient api, required ImCacheStore cache})
    : _api = api,
      _cache = cache;

  final ApiClient _api;
  final ImCacheStore _cache;
  final MessageNotificationSound _messageSound = MessageNotificationSound();
  final Random _random = Random.secure();
  final StreamController<BusinessImMessageEvent> _messageEvents =
      StreamController<BusinessImMessageEvent>.broadcast();
  final StreamController<BusinessImPresenceEvent> _presenceEvents =
      StreamController<BusinessImPresenceEvent>.broadcast();

  UserSession? _session;
  String _device = '';
  GatewayStreamClient? _gatewayStream;
  int _gatewayEpoch = 0;
  String _gatewayTicket = '';
  String _gatewayAckUrl = '';
  DateTime? _gatewayTicketExpiresAt;
  final Queue<GatewayFrame> _gatewayAckQueue = Queue<GatewayFrame>();
  Timer? _reconnectTimer;
  bool _started = false;
  bool _manualStop = false;
  bool _connecting = false;
  bool _foreground = true;
  bool _closingForBackground = false;
  bool _gatewayAckDraining = false;
  int _reconnectAttempt = 0;
  int _conversationVersion = 0;
  String _statusText = '未连接';
  String? _lastError;
  List<Map<String, Object?>> _latestConversations = const [];
  final Map<String, int> _channelMessageVersions = <String, int>{};
  final Map<String, Future<List<Map<String, Object?>>>> _syncingChannels =
      <String, Future<List<Map<String, Object?>>>>{};
  Future<List<Map<String, Object?>>>? _syncingConversations;
  final Set<String> _historySyncedChannels = <String>{};
  final Map<String, DateTime> _historyRetryAfter = <String, DateTime>{};
  bool _serverConversationsSynced = false;
  bool _initialHistorySyncing = false;
  bool _hasRealtimeConnectedOnce = false;
  bool _suppressCatchupSoundOnNextConnect = true;
  int _soundFreshAfterSeconds = 0;
  final Set<String> _openMessageChannels = <String>{};
  final Set<String> _reportedReadReceiptKeys = <String>{};
  final Map<String, DateTime> _playedIncomingSoundIds = <String, DateTime>{};
  final Map<String, Map<String, Object?>> _groupMuteStates =
      <String, Map<String, Object?>>{};

  Stream<BusinessImMessageEvent> get messageEvents => _messageEvents.stream;
  Stream<BusinessImPresenceEvent> get presenceEvents => _presenceEvents.stream;
  bool get isStarted => _started;
  String get statusText => _statusText;
  String? get lastError => _lastError;
  int get conversationVersion => _conversationVersion;
  bool get initialHistorySyncing => _initialHistorySyncing;

  List<Map<String, Object?>> cachedConversations() {
    final chat = _session?.chat;
    if (chat == null) {
      return const [];
    }
    if (_latestConversations.isEmpty) {
      _latestConversations = _dedupeConversations(
        _cache.readConversations(chat.uid),
      );
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
    _serverConversationsSynced = false;
    _hasRealtimeConnectedOnce = false;
    _suppressCatchupSoundOnNextConnect = true;
    _soundFreshAfterSeconds = 0;
    _playedIncomingSoundIds.clear();
    _reportedReadReceiptKeys.clear();
    _latestConversations = _dedupeConversations(
      _cache
          .readConversations(chat.uid)
          .map(_hydrateConversationProfile)
          .toList(growable: false),
    );
    _initialHistorySyncing =
        _latestConversations.isEmpty && _conversationHistorySyncEnabled(chat);
    _cache.writeConversations(
      uid: chat.uid,
      conversations: _latestConversations,
    );
    _bumpConversations('cache_loaded', notify: false);
    AppLogger.info(
      'im',
      'business im start',
      data: {
        'uid': chat.uid,
        'device': device,
        'private_history_sync_enabled': chat.privateHistorySyncEnabled,
        'group_history_sync_enabled': chat.groupHistorySyncEnabled,
        'initial_history_syncing': _initialHistorySyncing,
        'gateway_stream_addr': chat.stream?.httpsStreamAddr.isNotEmpty == true
            ? chat.stream?.httpsStreamAddr
            : chat.route.httpsStreamAddr,
      },
    );
    unawaited(syncConversationsFromServer());
    await _connectRealtime();
  }

  Future<void> stop({bool logout = false}) async {
    _manualStop = true;
    _started = false;
    _connecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final gatewayStream = _gatewayStream;
    _gatewayStream = null;
    _gatewayTicket = '';
    _gatewayAckUrl = '';
    _gatewayTicketExpiresAt = null;
    _gatewayAckQueue.clear();
    _gatewayAckDraining = false;
    _syncingConversations = null;
    _initialHistorySyncing = false;
    _soundFreshAfterSeconds = 0;
    _gatewayEpoch++;
    await gatewayStream?.close().catchError((Object _) => null);
    if (logout) {
      _session = null;
      _latestConversations = const [];
      _groupMuteStates.clear();
      _serverConversationsSynced = false;
      _hasRealtimeConnectedOnce = false;
      _suppressCatchupSoundOnNextConnect = true;
      _playedIncomingSoundIds.clear();
      _reportedReadReceiptKeys.clear();
    }
    _setStatus('未连接');
  }

  void onAppBackgrounded(String state) {
    AppLogger.info('im', 'app backgrounded', data: {'state': state});
    if (state == 'inactive') {
      return;
    }
    _foreground = false;
    _suppressCatchupSoundOnNextConnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closingForBackground = true;
    unawaited(_closeRealtimeOnly());
  }

  void resumeConnection() {
    if (!_started || _session == null) {
      return;
    }
    _foreground = true;
    if (_gatewayStream == null && !_connecting) {
      unawaited(_connectRealtime());
    }
  }

  Future<List<Map<String, Object?>>> refreshLocalConversations({
    bool notify = true,
  }) async {
    final chat = _requireChat();
    _latestConversations = _dedupeConversations(
      _cache
          .readConversations(chat.uid)
          .map(_hydrateConversationProfile)
          .toList(growable: false),
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

  Future<List<Map<String, Object?>>> loadConversations() async {
    final chat = _requireChat();
    final local = await refreshLocalConversations(notify: false);
    if (!_conversationHistorySyncEnabled(chat)) {
      AppLogger.info(
        'im',
        'conversation load uses local cache only',
        data: {
          'count': local.length,
          'private_history_sync_enabled': chat.privateHistorySyncEnabled,
          'group_history_sync_enabled': chat.groupHistorySyncEnabled,
        },
      );
      return local;
    }
    if (local.isNotEmpty && _serverConversationsSynced) {
      return local;
    }
    return syncConversationsFromServer();
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
    // 离开聊天页前再确认一次已读，避免返回会话列表时红点仍停留在旧缓存。
    unawaited(
      markConversationRead(
        channelID: channelID,
        channelType: channelType,
      ).catchError((Object error, StackTrace stackTrace) {
        AppLogger.warn(
          'im',
          'mark conversation read on close failed',
          data: {
            'channel_id': channelID,
            'channel_type': channelType,
            'error': error.toString(),
          },
        );
      }),
    );
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
    unawaited(
      _reportReadReceiptsForMessages(
        channelId: channelID,
        channelType: channelType,
        messages: messages,
      ),
    );
    if (_clearConversationUnread(channelID, channelType, source: 'mark_read')) {
      _markMessageChannel(
        source: 'mark_read',
        channelId: channelID,
        channelType: channelType,
      );
    }
  }

  Future<void> _reportReadReceiptsForMessages({
    required String channelId,
    required int channelType,
    required List<Map<String, Object?>> messages,
  }) async {
    final session = _session;
    final chat = session?.chat;
    if (session == null || chat == null) {
      return;
    }
    final targets = messages
        .where((item) => item['is_me'] != true)
        .where((item) => _value(item, ['client_msg_no']).isNotEmpty)
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    for (final item in targets.reversed.take(50)) {
      final targetClientMsgNo = _value(item, ['client_msg_no']);
      final key = '${_messageKey(channelId, channelType)}|$targetClientMsgNo';
      if (!_reportedReadReceiptKeys.add(key)) {
        continue;
      }
      try {
        await _api.imBusinessAction(
          action: 'im_message_read_receipt',
          session: session,
          device: _device,
          params: {
            'target_client_msg_no': targetClientMsgNo,
            'client_msg_no': newClientMsgNo(),
            if (_intValue(item, ['message_seq']) > 0)
              'message_seq': _intValue(item, ['message_seq']).toString(),
          },
          secureResponse: true,
        );
      } catch (error, stackTrace) {
        AppLogger.warn(
          'im',
          'read receipt report failed',
          data: {
            'target_client_msg_no': targetClientMsgNo,
            'channel_id': channelId,
            'channel_type': channelType,
            'error': error.toString(),
            'stack': stackTrace.toString(),
          },
        );
      }
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

  Future<void> removePrivateConversationAfterFriendDelete({
    required String friendId,
    required String channelID,
  }) async {
    final chat = _requireChat();
    final channelId = _canonicalChannelId(
      channelID.isNotEmpty ? channelID : _uidFromUserId(friendId),
      chat.channelTypePerson,
    );
    if (friendId.isNotEmpty) {
      _cache.removeFriend(uid: chat.uid, friendId: friendId);
    }
    await clearChannelChatRecords(
      channelID: channelId,
      channelType: chat.channelTypePerson,
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
      _replaceConversationLastMessage(channelID, channelType, messages.last);
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

  Future<void> markRedPacketReceivedLocal({
    required String channelID,
    required int channelType,
    required String clientMsgNo,
    required String redPacketId,
    Map<String, Object?> result = const {},
  }) async {
    await _markPaymentReceivedLocal(
      channelID: channelID,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
      nestedKey: 'red_packet',
      idKey: 'red_packet_id',
      idValue: redPacketId,
      result: result,
      source: 'red_packet_received_local',
    );
  }

  Future<void> markTransferReceivedLocal({
    required String channelID,
    required int channelType,
    required String clientMsgNo,
    required String transferId,
    Map<String, Object?> result = const {},
  }) async {
    await _markPaymentReceivedLocal(
      channelID: channelID,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
      nestedKey: 'transfer',
      idKey: 'transfer_id',
      idValue: transferId,
      result: result,
      source: 'transfer_received_local',
    );
  }

  Future<void> _markPaymentReceivedLocal({
    required String channelID,
    required int channelType,
    required String clientMsgNo,
    required String nestedKey,
    required String idKey,
    required String idValue,
    required Map<String, Object?> result,
    required String source,
  }) async {
    if (clientMsgNo.isEmpty || idValue.isEmpty) {
      AppLogger.warn(
        'im',
        'payment local mark skipped',
        data: {
          'source': source,
          'reason': 'empty_client_msg_no_or_id',
          'client_msg_no': clientMsgNo,
          idKey: idValue,
          'channel_id': channelID,
          'channel_type': channelType,
        },
      );
      return;
    }
    channelID = _canonicalChannelId(channelID, channelType);
    if (!_canStoreChannel(
      channelID,
      channelType,
      source: source,
      payload: {'client_msg_no': clientMsgNo, idKey: idValue, 'result': result},
    )) {
      return;
    }
    AppLogger.info(
      'im',
      'payment local mark start',
      data: {
        'source': source,
        'client_msg_no': clientMsgNo,
        idKey: idValue,
        'channel_id': channelID,
        'channel_type': channelType,
      },
    );
    final messages = _readMessagesForChannel(channelID, channelType);
    final index = messages.indexWhere(
      (item) => _value(item, ['client_msg_no']) == clientMsgNo,
    );
    if (index < 0) {
      AppLogger.warn(
        'im',
        'payment local mark target not found',
        data: {
          'source': source,
          'client_msg_no': clientMsgNo,
          idKey: idValue,
          'channel_id': channelID,
          'channel_type': channelType,
          'message_count': messages.length,
        },
      );
      return;
    }
    final existing = messages[index];
    final payload = _asMap(existing['payload']);
    final nested = _asMap(payload[nestedKey]);
    final responsePayload = _asMap(result['payload']);
    final responseNested = _asMap(responsePayload[nestedKey]);
    final updatedNested = _cleanPayload({
      ...nested,
      ...responseNested,
      idKey: idValue,
      'received_by_me': '1',
      'my_receive_time': DateTime.now().toIso8601String(),
    });
    final updatedPayload = _cleanPayload({
      ...payload,
      nestedKey: updatedNested,
    });
    final updated = <String, Object?>{
      ...existing,
      'payload': updatedPayload,
      'content': _payloadContent(updatedPayload),
    };
    _upsertMessage(channelID, channelType, updated);
    _publishMessageEvent(
      source: source,
      channelId: channelID,
      channelType: channelType,
      message: updated,
    );
    _markMessageChannel(
      source: source,
      channelId: channelID,
      channelType: channelType,
    );
    AppLogger.info(
      'im',
      'payment marked received locally',
      data: {
        'client_msg_no': clientMsgNo,
        idKey: idValue,
        'channel_id': channelID,
        'channel_type': channelType,
        'uid': _requireChat().uid,
      },
    );
  }

  Future<List<Map<String, Object?>>> syncConversationsFromServer() async {
    final running = _syncingConversations;
    if (running != null) {
      AppLogger.info('im', 'reuse running server conversation sync');
      return running;
    }
    final future = _syncConversationsFromServerOnce();
    _syncingConversations = future;
    try {
      return await future;
    } finally {
      if (identical(_syncingConversations, future)) {
        _syncingConversations = null;
      }
    }
  }

  Future<List<Map<String, Object?>>> _syncConversationsFromServerOnce() async {
    final session = _requireSession();
    final chat = _requireChat();
    final local = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .toList();
    if (!_conversationHistorySyncEnabled(chat)) {
      _latestConversations = local;
      _serverConversationsSynced = true;
      AppLogger.info(
        'im',
        'server conversation sync skipped',
        data: {
          'reason': 'server_history_sync_disabled',
          'local_count': local.length,
          'private_history_sync_enabled': chat.privateHistorySyncEnabled,
          'group_history_sync_enabled': chat.groupHistorySyncEnabled,
        },
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
          .map(_hydrateConversationProfile)
          .where(
            (item) => _historySyncEnabledForType(
              _intValue(item, ['channel_type']),
              chat,
            ),
          )
          .where(_conversationVisibleAfterClear)
          .toList();
      _latestConversations = _mergeConversationLists(
        serverConversations,
        local,
      ).map(_hydrateConversationProfile).toList(growable: false);
      _cache.writeConversations(
        uid: chat.uid,
        conversations: _latestConversations,
      );
      _serverConversationsSynced = true;
      _bumpConversations('server_sync');
      AppLogger.info(
        'im',
        'server conversations synced',
        data: {
          'local_count': local.length,
          'server_raw_count': list.length,
          'server_accepted_count': serverConversations.length,
          'merged_count': _latestConversations.length,
          'private_history_sync_enabled': chat.privateHistorySyncEnabled,
          'group_history_sync_enabled': chat.groupHistorySyncEnabled,
        },
      );
      _initialHistorySyncing = false;
      if (_statusText == '同步中') {
        _setStatus('已连接');
      }
      notifyListeners();
      return _latestConversations;
    } catch (error, stackTrace) {
      _initialHistorySyncing = false;
      if (_statusText == '同步中') {
        _setStatus(statusBeforeSync);
      }
      AppLogger.error(
        'im',
        'server conversations sync failed',
        error: error,
        stackTrace: stackTrace,
      );
      notifyListeners();
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
    final retryAfter = _historyRetryAfter[key];
    final retryBlocked =
        retryAfter != null && DateTime.now().isBefore(retryAfter);
    final needsHistorySync = !historySynced && !retryBlocked;
    if (needsHistorySync) {
      AppLogger.info(
        'im',
        'channel history sync requested',
        data: {'channel_id': channelID, 'channel_type': channelType},
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
          'local_count': _readMessagesForChannel(channelID, channelType).length,
          'private_history_sync_enabled': chat.privateHistorySyncEnabled,
          'group_history_sync_enabled': chat.groupHistorySyncEnabled,
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
      AppLogger.info(
        'im',
        'channel history synced',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'server_raw_count': list.length,
          'server_accepted_count': messages.length,
          'merged_count': merged.length,
        },
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

  bool _conversationHistorySyncEnabled(ChatSession chat) {
    return chat.privateHistorySyncEnabled || chat.groupHistorySyncEnabled;
  }

  List<Map<String, Object?>> _mergeConversationLists(
    List<Map<String, Object?>> primary,
    List<Map<String, Object?>> secondary,
  ) {
    final merged = primary
        .map(_normalizeConversation)
        .where(_conversationVisibleAfterClear)
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    for (final conversation in secondary) {
      final normalized = _normalizeConversation(conversation);
      if (!_conversationVisibleAfterClear(normalized)) {
        continue;
      }
      final channelId = _value(normalized, ['channel_id']);
      final channelType = _intValue(normalized, ['channel_type']);
      final index = merged.indexWhere(
        (item) =>
            _value(item, ['channel_id']) == channelId &&
            _intValue(item, ['channel_type']) == channelType,
      );
      if (index >= 0) {
        merged[index] = _mergeNonEmpty(normalized, merged[index]);
      } else {
        merged.add(Map<String, Object?>.from(normalized));
      }
    }
    final deduped = _dedupeConversations(merged);
    deduped.sort(
      (a, b) => _value(b, [
        'msg_time',
        'create_time',
        'timestamp',
      ]).compareTo(_value(a, ['msg_time', 'create_time', 'timestamp'])),
    );
    return deduped;
  }

  List<Map<String, Object?>> _dedupeConversations(
    List<Map<String, Object?>> conversations,
  ) {
    final byChannel = <String, Map<String, Object?>>{};
    for (final raw in conversations) {
      final item = _normalizeConversation(raw);
      if (!_conversationVisibleAfterClear(item)) {
        continue;
      }
      final channelId = _value(item, ['channel_id']);
      final channelType = _intValue(item, ['channel_type']);
      final key = _messageKey(channelId, channelType);
      final current = byChannel[key];
      byChannel[key] = current == null ? item : _mergeNonEmpty(item, current);
    }
    return byChannel.values.toList(growable: false);
  }

  Map<String, Object?> _mergeNonEmpty(
    Map<String, Object?> base,
    Map<String, Object?> overlay,
  ) {
    final merged = Map<String, Object?>.from(base);
    for (final entry in overlay.entries) {
      if (_hasNonEmptyValue(entry.value)) {
        merged[entry.key] = entry.value;
      } else {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return merged;
  }

  bool _hasNonEmptyValue(Object? value) {
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

  void _rememberProfileFromMap(Map<String, Object?> item) {
    final chat = _session?.chat;
    if (chat == null) {
      return;
    }
    final candidates = <Map<String, Object?>>[
      item,
      _asMap(item['friend']),
      _asMap(item['user']),
      _asMap(item['from_user']),
    ];
    for (final profile in candidates) {
      if (profile.isEmpty) {
        continue;
      }
      final userId = _value(profile, ['friend_id', 'userid', 'user_id', 'id']);
      if (userId.isEmpty) {
        continue;
      }
      _cache.writeProfile(uid: chat.uid, userId: userId, profile: profile);
    }
  }

  Map<String, Object?> _hydrateConversationProfile(Map<String, Object?> item) {
    final chat = _session?.chat;
    if (chat == null ||
        _intValue(item, ['channel_type']) != chat.channelTypePerson) {
      return item;
    }
    final receiverId = _value(item, [
      'receiver_id',
      'peer_id',
      'friend_id',
      'user_id',
      'userid',
    ], fallback: _receiverIdFromChannel(_value(item, ['channel_id', 'uid'])));
    if (receiverId.isEmpty) {
      return item;
    }
    final profile = _cache.readProfile(uid: chat.uid, userId: receiverId);
    if (profile.isEmpty) {
      return item;
    }
    return {
      ...profile,
      ...item,
      'receiver_id': receiverId,
      if ((item['nickname']?.toString() ?? '').isEmpty &&
          (profile['nickname']?.toString() ?? '').isNotEmpty)
        'nickname': profile['nickname'],
      if ((item['username']?.toString() ?? '').isEmpty &&
          (profile['username']?.toString() ?? '').isNotEmpty)
        'username': profile['username'],
      if ((item['usertx']?.toString() ?? '').isEmpty &&
          (profile['usertx']?.toString() ?? '').isNotEmpty)
        'usertx': profile['usertx'],
      if ((item['avatar']?.toString() ?? '').isEmpty &&
          (profile['avatar']?.toString() ?? '').isNotEmpty)
        'avatar': profile['avatar'],
    };
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
    final waitServerConfirm = _messageMustWaitServerConfirm(contentType);
    if (!waitServerConfirm) {
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
    }
    final uploadProgress = _uploadProgressReporter(
      channelId: channelID,
      channelType: channelType,
      contentType: contentType,
      filePath: filePath,
      baseMessage: optimistic,
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
        onUploadProgress: uploadProgress,
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
      if (waitServerConfirm) {
        AppLogger.error(
          'im',
          'business message rejected before local display',
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

  bool _messageMustWaitServerConfirm(String contentType) {
    return contentType == ChatContentTypes.redPacket ||
        contentType == ChatContentTypes.transfer;
  }

  void Function(double progress)? _uploadProgressReporter({
    required String channelId,
    required int channelType,
    required String contentType,
    required String filePath,
    required Map<String, Object?> baseMessage,
  }) {
    if (filePath.isEmpty ||
        (contentType != ChatContentTypes.image &&
            contentType != ChatContentTypes.video)) {
      return null;
    }
    var lastProgress = -1.0;
    return (progress) {
      final normalized = progress.clamp(0, 1).toDouble();
      if (normalized < 1 && (normalized - lastProgress).abs() < 0.02) {
        return;
      }
      lastProgress = normalized;
      final payload = <String, Object?>{
        ..._asMap(baseMessage['payload']),
        'upload_progress': normalized.toStringAsFixed(3),
      };
      final message = <String, Object?>{
        ...baseMessage,
        'status': 'sending',
        'payload': payload,
        'content': _payloadContent(payload),
      };
      _upsertMessage(channelId, channelType, message);
      _publishMessageEvent(
        source: 'send_upload_progress',
        channelId: channelId,
        channelType: channelType,
        message: message,
      );
      _markMessageChannel(
        source: 'send_upload_progress',
        channelId: channelId,
        channelType: channelType,
      );
    };
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
        onUploadProgress: null,
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
    void Function(double progress)? onUploadProgress,
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
                onUploadProgress: onUploadProgress,
              )
            : await _api.sendPersonMessage(
                session: session,
                device: _device,
                receiverId: _receiverIdFromChannel(channelID),
                clientMsgNo: clientMsgNo,
                contentType: contentType,
                params: params,
                filePath: filePath,
                onUploadProgress: onUploadProgress,
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

  Future<void> _connectRealtime() async {
    if (_manualStop || _connecting || !_foreground) {
      return;
    }
    _connecting = true;
    _setStatus(_reconnectAttempt > 0 ? '重连中' : '连接中');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closingForBackground = false;
    await _closeRealtimeOnly();
    try {
      final chat = await _refreshGatewayChat();
      final stream = chat.stream;
      final openUrl = _gatewayOpenUrl(chat);
      if (stream == null || stream.ticket.isEmpty || openUrl.isEmpty) {
        throw ApiException('Gateway 实时连接材料缺失');
      }
      final uri = Uri.parse(openUrl);
      final client = GatewayStreamClient();
      final epoch = ++_gatewayEpoch;
      final lastCursor = _initialGatewayCursor(chat, stream);
      final connectStartedAtSeconds =
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _soundFreshAfterSeconds =
          (!_hasRealtimeConnectedOnce || _suppressCatchupSoundOnNextConnect)
          ? connectStartedAtSeconds - 2
          : 0;
      _gatewayStream = client;
      _gatewayTicket = stream.ticket;
      _gatewayTicketExpiresAt = DateTime.now().add(
        Duration(seconds: max(30, stream.expireIn)),
      );
      _gatewayAckUrl = _gatewayAckUrlFor(openUrl);
      AppLogger.info(
        'im',
        'gateway stream connect start',
        data: {'addr': openUrl, 'cursor_len': lastCursor.length},
      );
      await client.connect(
        uri: uri,
        ticket: stream.ticket,
        frameKey: stream.frameKey,
        lastCursor: lastCursor,
        onFrame: (frame) {
          if (epoch != _gatewayEpoch) {
            return;
          }
          _handleGatewayFrame(frame);
        },
        onClosed: (reason, error) {
          if (epoch != _gatewayEpoch) {
            return;
          }
          _handleRealtimeClosed(reason, error?.toString());
        },
      );
      if (_manualStop || !_foreground) {
        await client.close().catchError((Object _) => null);
        _connecting = false;
        if (!_foreground) {
          _setStatus('未连接');
        }
        return;
      }
      _connecting = false;
      _reconnectAttempt = 0;
      _lastError = null;
      _hasRealtimeConnectedOnce = true;
      _suppressCatchupSoundOnNextConnect = false;
      _setStatus('已连接');
      unawaited(syncConversationsFromServer());
      AppLogger.info(
        'im',
        'gateway stream connected',
        data: {'addr': openUrl, 'cursor_len': lastCursor.length},
      );
    } catch (error, stackTrace) {
      _connecting = false;
      await _closeRealtimeOnly();
      _lastError = error.toString();
      _setStatus('连接失败');
      AppLogger.error(
        'im',
        'gateway stream connect failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (error is ApiException && (error.code == 401 || error.code == 403)) {
        _started = false;
        return;
      }
      _scheduleReconnect('connect_failed');
    }
  }

  Future<ChatSession> _refreshGatewayChat() async {
    final session = _requireSession();
    final chat = await _api.connectIm(session: session, device: _device);
    _session = session.copyWith(chat: chat);
    return chat;
  }

  String _gatewayOpenUrl(ChatSession chat) {
    return (chat.stream?.httpsStreamAddr.isNotEmpty == true
            ? chat.stream!.httpsStreamAddr
            : chat.route.httpsStreamAddr)
        .trim();
  }

  String _initialGatewayCursor(ChatSession chat, GatewayStreamSession stream) {
    final local = _cache.readGatewayCursor(uid: chat.uid, device: _device);
    if (_isValidGatewayCursor(local)) {
      return local;
    }
    if (_isValidGatewayCursor(stream.lastCursor)) {
      return stream.lastCursor;
    }
    return '0-0';
  }

  bool _isValidGatewayCursor(String value) {
    return RegExp(r'^(\d+-\d+|0-0)$').hasMatch(value.trim());
  }

  String _gatewayAckUrlFor(String openUrl) {
    final uri = Uri.parse(openUrl);
    var path = uri.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    path = path.endsWith('/open')
        ? '${path.substring(0, path.length - 5)}/ack'
        : '$path/ack';
    return uri.replace(path: path).toString();
  }

  void _handleGatewayFrame(GatewayFrame frame) {
    if (frame.isHeartbeat) {
      if (_statusText != '已连接') {
        _setStatus('已连接');
      }
      return;
    }
    if (frame.isKick) {
      _lastError = frame.reason.isEmpty ? 'Gateway 已断开' : frame.reason;
      _handleRealtimeClosed('gateway_kick', _lastError);
      return;
    }
    if (frame.isError) {
      _lastError = frame.reason.isEmpty ? 'Gateway 返回错误' : frame.reason;
      _handleRealtimeClosed('gateway_error', _lastError);
      return;
    }
    if (_isGatewayPresenceFrame(frame)) {
      _handleGatewayPresence(frame);
      return;
    }
    if (_isGatewayReadReceiptFrame(frame)) {
      _handleGatewayReadReceipt(frame);
      return;
    }
    if (!frame.isMessage) {
      AppLogger.info('im', 'gateway frame ignored', data: {'type': frame.type});
      return;
    }
    _handleGatewayMessage(frame);
  }

  bool _isGatewayPresenceFrame(GatewayFrame frame) {
    final payload = frame.payload;
    final markers = <String>[
      frame.type,
      payload['type']?.toString() ?? '',
      payload['event']?.toString() ?? '',
      payload['cmd']?.toString() ?? '',
      payload['action']?.toString() ?? '',
      payload['content_type']?.toString() ?? '',
    ].map((item) => item.toLowerCase()).toList(growable: false);
    return markers.any(
      (item) =>
          item == 'presence' ||
          item == 'user_presence' ||
          item == 'online_status' ||
          item == 'user_online_status' ||
          item == 'user.onlinestatus',
    );
  }

  void _handleGatewayPresence(GatewayFrame frame) {
    final events = _presenceEventsFromFrame(frame);
    if (events.isEmpty) {
      AppLogger.warn(
        'im',
        'gateway presence ignored',
        data: {
          'type': frame.type,
          'client_msg_no': frame.clientMsgNo,
          'payload': frame.payload,
        },
      );
      unawaited(_ackGatewayFrame(frame));
      return;
    }
    for (final event in events) {
      if (!_presenceEvents.isClosed) {
        _presenceEvents.add(event);
      }
      AppLogger.info(
        'im',
        'gateway presence applied',
        data: {
          'uid': event.uid,
          'user_id': event.userId,
          'online': event.online,
          'device_flag': event.deviceFlag,
          'device_online_count': event.deviceOnlineCount,
          'total_online_count': event.totalOnlineCount,
          'event_time': event.eventTime,
        },
      );
    }
    notifyListeners();
    unawaited(_ackGatewayFrame(frame));
  }

  List<BusinessImPresenceEvent> _presenceEventsFromFrame(GatewayFrame frame) {
    final payload = frame.payload;
    final rawItems = <Object?>[];
    final directItems = payload['items'] ?? payload['list'] ?? payload['users'];
    if (directItems is Iterable) {
      rawItems.addAll(directItems);
    } else if (payload['data'] is Iterable) {
      rawItems.addAll(payload['data'] as Iterable);
    } else if (payload['data'] is Map) {
      final data = _asMap(payload['data']);
      final nested = data['items'] ?? data['list'] ?? data['users'];
      if (nested is Iterable) {
        rawItems.addAll(nested);
      } else {
        rawItems.add(data);
      }
    } else {
      rawItems.add(payload);
    }
    return rawItems
        .map(_presenceEventFromRaw)
        .whereType<BusinessImPresenceEvent>()
        .toList(growable: false);
  }

  BusinessImPresenceEvent? _presenceEventFromRaw(Object? raw) {
    final map = raw is String ? _presenceMapFromString(raw) : _asMap(raw);
    if (map.isEmpty) {
      return null;
    }
    final uid = _value(map, [
      'uid',
      'im_uid',
      'wukong_uid',
      'user_uid',
      'channel_id',
    ]);
    final userId = _value(map, [
      'user_id',
      'userid',
      'id',
      'friend_id',
      'member_id',
    ], fallback: _receiverIdFromChannel(uid));
    if (uid.isEmpty && userId.isEmpty) {
      return null;
    }
    return BusinessImPresenceEvent(
      uid: uid.isNotEmpty ? uid : _uidFromUserId(userId),
      userId: userId,
      online: _presenceOnlineValue(map),
      deviceFlag: _intValue(map, ['device_flag', 'device']),
      deviceOnlineCount: _intValue(map, ['device_online_count']),
      totalOnlineCount: _intValue(map, ['total_online_count']),
      eventTime: _value(map, ['event_time', 'timestamp', 'time']),
      payload: map,
    );
  }

  Map<String, Object?> _presenceMapFromString(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = _asMap(text);
    if (decoded.isNotEmpty) {
      return decoded;
    }
    final parts = text.split('-');
    if (parts.length < 6) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      'uid': parts[0],
      'device_flag': parts[1],
      'online': parts[2],
      'conn_id': parts[3],
      'device_online_count': parts[4],
      'total_online_count': parts[5],
    };
  }

  bool _presenceOnlineValue(Map<String, Object?> map) {
    for (final key in ['online', 'is_online', 'connected']) {
      final value = map[key];
      if (value != null) {
        return _boolValue(value);
      }
    }
    final status = _value(map, [
      'status',
      'online_status',
      'state',
    ]).toLowerCase();
    return status == 'online' ||
        status == 'connected' ||
        status == '1' ||
        status == '在线';
  }

  void _handleGatewayMessage(GatewayFrame frame) {
    final chat = _requireChat();
    final payload = frame.payload;
    var channelType = frame.channelType > 0
        ? frame.channelType
        : _intValue(payload, [
            'channel_type',
          ], fallback: chat.channelTypePerson);
    var channelId = frame.channelId.isNotEmpty
        ? frame.channelId
        : _value(payload, ['channel_id', 'group_id', 'to_uid', 'receiver_uid']);
    if (channelType == chat.channelTypePerson) {
      channelId = _gatewayPrivateChannelId(channelId, payload);
    }
    channelId = _canonicalChannelId(channelId, channelType);
    AppLogger.info(
      'im',
      'gateway message route resolved',
      data: {
        'client_msg_no': frame.clientMsgNo,
        'frame_channel_id': frame.channelId,
        'resolved_channel_id': channelId,
        'channel_type': channelType,
        'current_uid': chat.uid,
        'current_user_id': _requireSession().userId.toString(),
        'from_uid': _value(payload, ['from_uid', 'sender_uid']),
        'to_uid': _value(payload, ['to_uid', 'receiver_uid', 'target_uid']),
        'sender_id': _value(payload, [
          'sender_id',
          'from_id',
          'user_id',
          'userid',
        ]),
        'receiver_id': _value(payload, ['receiver_id', 'peer_id', 'friend_id']),
        'content_type': payload['content_type']?.toString() ?? '',
        'cmd': payload['cmd']?.toString() ?? '',
        'payload': payload,
      },
    );
    if (channelId.isEmpty || channelType <= 0) {
      AppLogger.error(
        'im',
        'gateway message missing channel',
        data: {
          'client_msg_no': frame.clientMsgNo,
          'channel_id': frame.channelId,
          'channel_type': frame.channelType,
          'has_cursor': frame.cursor.isNotEmpty,
        },
      );
      return;
    }
    if (_handleRecallPayload(payload, channelId, channelType)) {
      unawaited(_ackGatewayFrame(frame));
      AppLogger.info(
        'im',
        'gateway recall message handled',
        data: {
          'client_msg_no': frame.clientMsgNo,
          'channel_id': channelId,
          'channel_type': channelType,
        },
      );
      return;
    }
    if (_handleCommandPayload(payload, channelId, channelType)) {
      unawaited(_ackGatewayFrame(frame));
      AppLogger.info(
        'im',
        'gateway command message handled',
        data: {
          'client_msg_no': frame.clientMsgNo,
          'channel_id': channelId,
          'channel_type': channelType,
          'cmd': payload['cmd']?.toString() ?? '',
        },
      );
      return;
    }
    if (_handleActionReceiptPayload(payload, channelId, channelType)) {
      unawaited(_ackGatewayFrame(frame));
      AppLogger.info(
        'im',
        'gateway action receipt handled',
        data: {
          'client_msg_no': frame.clientMsgNo,
          'channel_id': channelId,
          'channel_type': channelType,
        },
      );
      return;
    }
    final message = _messageFromGatewayFrame(
      frame,
      channelId,
      channelType,
      payload,
    );
    if (message.isEmpty) {
      unawaited(_ackGatewayFrame(frame));
      AppLogger.info(
        'im',
        'gateway non-chat message ignored',
        data: {
          'client_msg_no': frame.clientMsgNo,
          'channel_id': channelId,
          'channel_type': channelType,
        },
      );
      return;
    }
    final upsertResult = _upsertMessage(channelId, channelType, message);
    if (!upsertResult.stored) {
      unawaited(_ackGatewayFrame(frame));
      AppLogger.info(
        'im',
        'gateway message ignored after local store rules',
        data: {
          'client_msg_no': frame.clientMsgNo,
          'channel_id': channelId,
          'channel_type': channelType,
        },
      );
      return;
    }
    _upsertConversationFromMessage(message);
    _publishMessageEvent(
      source: 'gateway_recv',
      channelId: channelId,
      channelType: channelType,
      message: message,
    );
    _playIncomingMessageSoundIfNeeded(
      message,
      frame,
      inserted: upsertResult.inserted,
    );
    _markMessageChannel(
      source: 'gateway_recv',
      channelId: channelId,
      channelType: channelType,
    );
    unawaited(_ackGatewayFrame(frame));
    AppLogger.info(
      'im',
      'gateway message received',
      data: {
        'client_msg_no': frame.clientMsgNo,
        'channel_id': channelId,
        'channel_type': channelType,
        'has_cursor': frame.cursor.isNotEmpty,
      },
    );
  }

  bool _isGatewayReadReceiptFrame(GatewayFrame frame) {
    final type = frame.type.toLowerCase();
    final payload = frame.payload;
    final cmd = payload['cmd']?.toString().toLowerCase() ?? '';
    final contentType = payload['content_type']?.toString().toLowerCase() ?? '';
    return type == 'read_receipt' ||
        type == 'message_read' ||
        type == 'receipt' ||
        contentType == 'read_receipt' ||
        cmd == 'read_receipt' ||
        cmd == 'message_read' ||
        cmd == 'message_read_receipt';
  }

  void _handleGatewayReadReceipt(GatewayFrame frame) {
    final chat = _requireChat();
    final payload = frame.payload;
    var channelType = frame.channelType > 0
        ? frame.channelType
        : _intValue(payload, [
            'channel_type',
          ], fallback: chat.channelTypePerson);
    var channelId = frame.channelId.isNotEmpty
        ? frame.channelId
        : _value(payload, ['channel_id', 'group_id', 'to_uid', 'receiver_uid']);
    if (channelType == chat.channelTypePerson) {
      channelId = _gatewayPrivateChannelId(channelId, payload);
    }
    channelId = _canonicalChannelId(channelId, channelType);
    if (channelId.isEmpty || channelType <= 0) {
      AppLogger.warn(
        'im',
        'gateway read receipt missing channel',
        data: {'client_msg_no': frame.clientMsgNo, 'type': frame.type},
      );
      return;
    }
    final handled = _applyReadReceiptPayload(
      payload,
      channelId,
      channelType,
      source: 'gateway_read_receipt',
    );
    unawaited(_ackGatewayFrame(frame));
    AppLogger.info(
      'im',
      handled ? 'gateway read receipt applied' : 'gateway read receipt ignored',
      data: {
        'client_msg_no': frame.clientMsgNo,
        'channel_id': channelId,
        'channel_type': channelType,
      },
    );
  }

  String _gatewayPrivateChannelId(
    String channelId,
    Map<String, Object?> payload,
  ) {
    final fromUid = _value(payload, ['from_uid', 'sender_uid']);
    final toUid = _value(payload, ['to_uid', 'receiver_uid', 'target_uid']);
    final peerUid = _value(payload, ['peer_uid', 'opposite_uid']);
    final senderId = _value(payload, [
      'sender_id',
      'from_id',
      'user_id',
      'userid',
    ]);
    final receiverId = _value(payload, ['receiver_id', 'peer_id', 'friend_id']);
    final fromSelf = _isCurrentUserMessage(
      senderId: senderId,
      senderUid: fromUid,
    );
    final candidates = fromSelf
        ? <String>[toUid, receiverId, peerUid, channelId, fromUid, senderId]
        : <String>[fromUid, senderId, peerUid, channelId, toUid, receiverId];
    final resolved = _firstPrivatePeerChannelCandidate(candidates);
    AppLogger.info(
      'im',
      'gateway private channel candidate resolved',
      data: {
        'raw_channel_id': channelId,
        'resolved_channel_id': resolved,
        'from_self': fromSelf,
        'from_uid': fromUid,
        'to_uid': toUid,
        'peer_uid': peerUid,
        'sender_id': senderId,
        'receiver_id': receiverId,
      },
    );
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return channelId;
  }

  Future<void> _ackGatewayFrame(GatewayFrame frame) async {
    if (!_isValidGatewayCursor(frame.cursor)) {
      return;
    }
    _gatewayAckQueue.add(frame);
    if (_gatewayAckDraining) {
      return;
    }
    _gatewayAckDraining = true;
    try {
      while (_gatewayAckQueue.isNotEmpty) {
        final current = _gatewayAckQueue.first;
        final success = await _ackGatewayFrameOnce(current);
        if (!success) {
          _handleRealtimeClosed('gateway_ack_failed', 'Gateway ACK 失败');
          return;
        }
        _gatewayAckQueue.removeFirst();
      }
    } finally {
      _gatewayAckDraining = false;
    }
  }

  Future<bool> _ackGatewayFrameOnce(GatewayFrame frame) async {
    final chat = _requireChat();
    try {
      var ticket = await _ensureGatewayAckTicket();
      try {
        await _api.ackGatewayCursor(
          ackUrl: _gatewayAckUrl,
          ticket: ticket,
          lastCursor: frame.cursor,
          clientMsgNos: [if (frame.clientMsgNo.isNotEmpty) frame.clientMsgNo],
        );
      } on ApiException catch (error) {
        if (error.code != 401) {
          rethrow;
        }
        ticket = await _ensureGatewayAckTicket(force: true);
        await _api.ackGatewayCursor(
          ackUrl: _gatewayAckUrl,
          ticket: ticket,
          lastCursor: frame.cursor,
          clientMsgNos: [if (frame.clientMsgNo.isNotEmpty) frame.clientMsgNo],
        );
      }
      _cache.writeGatewayCursor(
        uid: chat.uid,
        device: _device,
        cursor: frame.cursor,
      );
      return true;
    } catch (error, stackTrace) {
      AppLogger.error(
        'im',
        'gateway ack failed',
        error: error,
        stackTrace: stackTrace,
        data: {
          'cursor_len': frame.cursor.length,
          'client_msg_no': frame.clientMsgNo,
        },
      );
      return false;
    }
  }

  Future<String> _ensureGatewayAckTicket({bool force = false}) async {
    final expiresAt = _gatewayTicketExpiresAt;
    if (!force &&
        _gatewayTicket.isNotEmpty &&
        _gatewayAckUrl.isNotEmpty &&
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 15)))) {
      return _gatewayTicket;
    }
    final chat = await _refreshGatewayChat();
    final stream = chat.stream;
    final openUrl = _gatewayOpenUrl(chat);
    if (stream == null || stream.ticket.isEmpty || openUrl.isEmpty) {
      throw ApiException('Gateway ACK ticket 缺失');
    }
    _gatewayTicket = stream.ticket;
    _gatewayTicketExpiresAt = DateTime.now().add(
      Duration(seconds: max(30, stream.expireIn)),
    );
    _gatewayAckUrl = _gatewayAckUrlFor(openUrl);
    return _gatewayTicket;
  }

  void _handleRealtimeClosed(String source, String? reason) {
    if (_manualStop) {
      return;
    }
    if (_closingForBackground) {
      _closingForBackground = false;
      _setStatus('未连接');
      return;
    }
    unawaited(_closeRealtimeOnly());
    _lastError = reason?.isEmpty == false ? reason : _lastError;
    _setStatus('重连中');
    _scheduleReconnect(source);
  }

  void _scheduleReconnect(String source) {
    if (!_started || _manualStop || !_foreground) {
      AppLogger.info(
        'im',
        'skip gateway reconnect while backgrounded',
        data: {'source': source},
      );
      return;
    }
    _reconnectTimer?.cancel();
    final exponent = min(_reconnectAttempt, 6);
    final baseMs = min<int>(60000, 1000 * (1 << exponent));
    final jitterMs = _random.nextInt(max(1, (baseMs * 0.3).round()));
    final delayMs = baseMs + jitterMs;
    _reconnectAttempt++;
    AppLogger.warn(
      'im',
      'gateway reconnect scheduled',
      data: {
        'source': source,
        'delay_ms': delayMs,
        'attempt': _reconnectAttempt,
      },
    );
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), _connectRealtime);
  }

  Future<void> _closeRealtimeOnly() async {
    final gatewayStream = _gatewayStream;
    _gatewayStream = null;
    _gatewayTicket = '';
    _gatewayAckUrl = '';
    _gatewayTicketExpiresAt = null;
    _gatewayAckQueue.clear();
    _gatewayAckDraining = false;
    _gatewayEpoch++;
    await gatewayStream?.close().catchError((Object _) => null);
  }

  Map<String, Object?> _normalizeConversation(Map<String, Object?> item) {
    final rawPayload = _asMap(item['payload']);
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
          ? _privateChannelIdFromConversation(item, rawPayload)
          : _value(item, ['channel_id', 'uid', 'group_id', 'id']),
      resolvedType,
    );
    final receiverId = resolvedType == _requireChat().channelTypePerson
        ? _privateReceiverIdFromConversation(item, rawPayload, channelId)
        : '';
    if (resolvedType == _requireChat().channelTypePerson &&
        (channelId.isEmpty ||
            receiverId.isEmpty ||
            receiverId == _requireSession().userId.toString())) {
      AppLogger.warn(
        'im',
        'private conversation dropped',
        data: {
          'reason': channelId.isEmpty
              ? 'empty_channel'
              : receiverId.isEmpty
              ? 'empty_receiver'
              : 'self_receiver',
          'raw_channel_id': _value(item, ['channel_id', 'uid']),
          'resolved_channel_id': channelId,
          'receiver_id': receiverId,
          'payload': rawPayload,
        },
      );
      return <String, Object?>{
        ...item,
        'channel_type': resolvedType,
        'channel_id': '',
        'receiver_id': '',
        'unread_quantity': 0,
      };
    }
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
    ], fallback: rawPayload['content_type']?.toString() ?? '');
    final content = _value(item, [
      'content',
    ], fallback: _payloadContent(rawPayload));
    final payload = _ensureBusinessPayload(
      rawPayload,
      contentType: contentType,
      content: content,
      clientMsgNo: _value(item, ['last_client_msg_no', 'client_msg_no']),
    );
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
    final rawMap = _asMap(item['raw']);
    final messageMap = _asMap(item['message']);
    final raw = rawMap.isEmpty ? item : rawMap;
    final message = messageMap.isEmpty ? item : messageMap;
    final rawPayload = _asMap(message['payload']);
    final fromUser = _firstMap([
      item['fromUser'],
      item['from_user'],
      item['user'],
      message['from_user'],
      message['user'],
    ]);
    if (fromUser.isNotEmpty) {
      _rememberProfileFromMap(fromUser);
    }
    final contentType = _value(message, [
      'content_type',
    ], fallback: rawPayload['content_type']?.toString() ?? '');
    final content = _value(message, [
      'content',
      'text',
    ], fallback: _payloadContent(rawPayload));
    final payload = _ensureBusinessPayload(
      rawPayload,
      contentType: contentType,
      content: content,
      clientMsgNo: _value(message, [
        'client_msg_no',
      ], fallback: _value(raw, ['client_msg_no'])),
    );
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
    final normalizedPayload = payload.isEmpty ? message : payload;
    final normalizedContent = switch (contentType) {
      ChatContentTypes.redPacket => _redPacketContent({
        ...payload,
        if (content.isNotEmpty) 'content': content,
      }),
      ChatContentTypes.transfer => _transferContent({
        ...payload,
        if (content.isNotEmpty) 'content': content,
      }),
      _ => content.isNotEmpty ? content : _payloadContent(payload),
    };
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
      'content': normalizedContent,
      'content_type': contentType,
      'payload': normalizedPayload,
      'timestamp': _value(message, ['create_time', 'timestamp']),
      'status': _deliveryStatusFromSources([
        item,
        raw,
        message,
        normalizedPayload,
      ]),
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
    final rawMergedPayload = payload.isEmpty
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
    final queued = _boolValue(result['queued']);
    final clientMsgNo = _value(result, [
      'client_msg_no',
    ], fallback: _value(fallback, ['client_msg_no']));
    final contentType =
        rawMergedPayload['content_type']?.toString() ??
        fallback['content_type']?.toString() ??
        '';
    final mergedPayload = _ensureBusinessPayload(
      rawMergedPayload,
      contentType: contentType,
      content: _payloadContent(rawMergedPayload),
      clientMsgNo: clientMsgNo,
    );
    return <String, Object?>{
      ...fallback,
      'message_id': _value(result, [
        'message_id',
      ], fallback: _value(sendAck, ['message_id'])),
      'client_msg_no': clientMsgNo,
      'channel_id': channelId,
      'channel_type': channelType,
      'content': _payloadContent(mergedPayload).isNotEmpty
          ? _payloadContent(mergedPayload)
          : fallback['content'],
      'content_type': contentType.isNotEmpty
          ? contentType
          : mergedPayload['content_type']?.toString() ??
                fallback['content_type'],
      'payload': mergedPayload.isEmpty ? fallback['payload'] : mergedPayload,
      'from_uid': _value(fallback, ['from_uid']),
      'is_me': fallback['is_me'] == true,
      'status': _deliveryStatusFromSources([
        result,
        sendAck,
        mergedPayload,
      ], queued: queued),
      'send_ack': sendAck,
    };
  }

  String _deliveryStatusFromSources(
    List<Map<String, Object?>> sources, {
    bool queued = false,
    String fallback = 'sent',
  }) {
    if (queued) {
      return 'queued';
    }
    for (final source in sources) {
      if (_hasReadReceiptState(source)) {
        return 'read';
      }
    }
    for (final source in sources) {
      final status = _value(source, [
        'status',
        'receipt_status',
        'read_status',
      ]).toLowerCase();
      if (status == 'read' || status == 'readed' || status == 'seen') {
        return 'read';
      }
      if (status == 'sending' ||
          status == 'failed' ||
          status == 'queued' ||
          status == 'sent') {
        return status;
      }
      if (status == 'success' ||
          status == 'succeeded' ||
          status == 'delivered') {
        return 'sent';
      }
    }
    return fallback;
  }

  bool _hasReadReceiptState(Map<String, Object?> source) {
    final receipt = _asMap(source['receipt']);
    final readReceipt = _asMap(source['read_receipt']);
    final payloadReceipt = _asMap(_asMap(source['payload'])['receipt']);
    for (final item in [source, receipt, readReceipt, payloadReceipt]) {
      if (_boolValue(item['is_read']) ||
          _boolValue(item['read']) ||
          _boolValue(item['readed']) ||
          _boolValue(item['has_read'])) {
        return true;
      }
      final status = _value(item, [
        'receipt_status',
        'read_status',
        'status',
      ]).toLowerCase();
      if (status == 'read' || status == 'readed' || status == 'seen') {
        return true;
      }
      if (_intValue(item, ['read_at', 'read_time']) > 0 ||
          _intValue(item, ['read_count', 'reader_count']) > 0) {
        return true;
      }
    }
    return false;
  }

  Map<String, Object?> _messageFromGatewayFrame(
    GatewayFrame frame,
    String channelId,
    int channelType,
    Map<String, Object?> payload,
  ) {
    if (!_isDisplayableChatPayload(payload)) {
      return const <String, Object?>{};
    }
    final canonicalChannelId = _canonicalChannelId(channelId, channelType);
    final receiverId = channelType == _requireChat().channelTypePerson
        ? _receiverIdFromChannel(canonicalChannelId)
        : '';
    final fromUser = _userFromPayload(payload);
    if (fromUser.isNotEmpty) {
      _rememberProfileFromMap(fromUser);
    }
    final fromUid = _value(payload, ['from_uid', 'sender_uid']);
    final clientMsgNo = frame.clientMsgNo.isNotEmpty
        ? frame.clientMsgNo
        : _value(
            payload,
            ['client_msg_no'],
            fallback: frame.cursor.isNotEmpty ? 'gateway_${frame.cursor}' : '',
          );
    final messageTime = frame.timestamp > 0
        ? frame.timestamp
        : _intValue(payload, ['timestamp', 'create_time', 'client_timestamp']);
    return <String, Object?>{
      'message_id': frame.messageId,
      'client_msg_no': clientMsgNo,
      'message_seq': frame.messageSeq > 0
          ? frame.messageSeq
          : _intValue(payload, ['message_seq']),
      'channel_id': canonicalChannelId,
      'channel_type': channelType,
      if (receiverId.isNotEmpty) 'receiver_id': receiverId,
      'from_uid': fromUid,
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
        ], fallback: fromUid),
      ),
      'content': _payloadContent(payload),
      'content_type': payload['content_type']?.toString() ?? '',
      'payload': payload,
      'timestamp': _formatTimestamp(messageTime),
      'status': _deliveryStatusFromSources([payload]),
      if (fromUser.isNotEmpty) 'from_user': fromUser,
      if (frame.cursor.isNotEmpty) 'gateway_cursor': frame.cursor,
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

  Map<String, Object?> _ensureBusinessPayload(
    Map<String, Object?> payload, {
    required String contentType,
    String content = '',
    String clientMsgNo = '',
  }) {
    final type = contentType.isNotEmpty
        ? contentType
        : payload['content_type']?.toString() ?? '';
    if (!ChatContentTypes.displayable.contains(type)) {
      return payload;
    }
    if (payload['protocol']?.toString() == 'blin.chat.v1') {
      return payload;
    }
    return _cleanPayload({
      ...payload,
      'protocol': 'blin.chat.v1',
      'content_type': type,
      if (content.isNotEmpty) 'content': content,
      if (clientMsgNo.isNotEmpty) 'client_msg_no': clientMsgNo,
    });
  }

  bool _handleRecallPayload(
    Map<String, Object?> payload,
    String channelId,
    int channelType,
  ) {
    if (payload['protocol']?.toString() != 'blin.chat.v1' ||
        payload['content_type']?.toString() != 'recall') {
      return false;
    }
    final chat = _requireChat();
    final target = _value(payload, ['target_client_msg_no', 'client_msg_no']);
    if (target.isNotEmpty) {
      _cache.deleteMessage(
        uid: chat.uid,
        channelId: channelId,
        channelType: channelType,
        clientMsgNo: target,
      );
      _markMessageChannel(
        source: 'recall_cmd',
        channelId: channelId,
        channelType: channelType,
      );
      _publishMessageEvent(
        source: 'recall_cmd',
        channelId: channelId,
        channelType: channelType,
        message: <String, Object?>{
          'client_msg_no': target,
          'content_type': 'recall',
          'cmd': 'recall',
        },
      );
    }
    return true;
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
    final chat = _requireChat();
    if (_isReadReceiptCommand(cmd)) {
      _applyReadReceiptPayload(
        payload,
        channelId,
        channelType,
        source: 'read_receipt_cmd',
      );
      return true;
    }
    if (cmd == 'burn_after_read') {
      final target = _value(payload, ['target_client_msg_no', 'client_msg_no']);
      if (target.isNotEmpty) {
        _cache.deleteMessage(
          uid: chat.uid,
          channelId: channelId,
          channelType: channelType,
          clientMsgNo: target,
        );
        _markMessageChannel(
          source: 'burn_after_read_cmd',
          channelId: channelId,
          channelType: channelType,
        );
        _publishMessageEvent(
          source: 'burn_after_read_cmd',
          channelId: channelId,
          channelType: channelType,
          message: <String, Object?>{
            'client_msg_no': target,
            'content_type': 'cmd',
            'cmd': cmd,
          },
        );
      }
      return true;
    }
    if (cmd == 'friend_deleted') {
      final friendId = _value(payload, ['friend_id', 'target_user_id']);
      unawaited(
        removePrivateConversationAfterFriendDelete(
          friendId: friendId,
          channelID: channelId,
        ),
      );
      return true;
    }
    if (_isActionReceiptCommand(cmd)) {
      _handleActionReceiptPayload(payload, channelId, channelType);
      return true;
    }
    if (cmd != 'group_member_mute_changed' &&
        cmd != 'group_mute_changed' &&
        cmd != 'group_member_unmute') {
      return false;
    }
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

  bool _isReadReceiptCommand(String cmd) {
    final normalized = cmd.toLowerCase();
    return normalized == 'read_receipt' ||
        normalized == 'message_read' ||
        normalized == 'message_read_receipt';
  }

  bool _isActionReceiptCommand(String cmd) {
    final normalized = cmd.toLowerCase();
    return normalized == 'red_packet_received_receipt' ||
        normalized == 'transfer_received_receipt';
  }

  bool _handleActionReceiptPayload(
    Map<String, Object?> payload,
    String channelId,
    int channelType,
  ) {
    final receipt = _asMap(payload['receipt']);
    final action = _value(receipt, [
      'action',
    ], fallback: _value(payload, ['action', 'cmd']).replaceAll('_receipt', ''));
    if (action != ChatContentTypes.redPacketReceived &&
        action != ChatContentTypes.transferReceived) {
      return false;
    }
    final targets = _readReceiptTargets(payload);
    if (targets.isEmpty) {
      AppLogger.warn(
        'im',
        'action receipt missing target',
        data: {
          'action': action,
          'channel_id': channelId,
          'channel_type': channelType,
          'payload': payload,
        },
      );
      return false;
    }
    final receiptChannelId = _receiptChannelForTargets(
      channelId,
      channelType,
      targets,
    );
    if (receiptChannelId.isEmpty) {
      AppLogger.warn(
        'im',
        'action receipt channel missing',
        data: {
          'action': action,
          'raw_channel_id': channelId,
          'channel_type': channelType,
          'targets': targets.toList(growable: false),
          'payload': payload,
        },
      );
      return false;
    }
    if (receiptChannelId != channelId) {
      AppLogger.info(
        'im',
        'action receipt channel corrected',
        data: {
          'action': action,
          'raw_channel_id': channelId,
          'resolved_channel_id': receiptChannelId,
          'channel_type': channelType,
          'targets': targets.toList(growable: false),
        },
      );
    }
    var handled = false;
    for (final target in targets) {
      final messages = _readMessagesForChannel(receiptChannelId, channelType);
      final index = messages.indexWhere(
        (item) => _value(item, ['client_msg_no']) == target,
      );
      if (index < 0) {
        AppLogger.warn(
          'im',
          'action receipt target not found',
          data: {
            'action': action,
            'target_client_msg_no': target,
            'channel_id': receiptChannelId,
            'channel_type': channelType,
          },
        );
        continue;
      }
      final existing = messages[index];
      final existingPayload = _asMap(existing['payload']);
      final nestedKey = action == ChatContentTypes.redPacketReceived
          ? 'red_packet'
          : 'transfer';
      final existingNested = _asMap(existingPayload[nestedKey]);
      final nestedReceipt = _asMap(receipt[nestedKey]);
      final updatedNested = _cleanPayload({
        ...existingNested,
        ...receipt,
        ...nestedReceipt,
        if (_actionReceiptFromCurrentUser(receipt)) 'received_by_me': '1',
      });
      final updatedPayload = _cleanPayload({
        ...existingPayload,
        nestedKey: updatedNested,
        'receipt': {..._asMap(existingPayload['receipt']), action: receipt},
      });
      final updated = <String, Object?>{
        ...existing,
        'channel_id': receiptChannelId,
        'payload': updatedPayload,
        'content': _payloadContent(updatedPayload),
      };
      _upsertMessage(receiptChannelId, channelType, updated);
      _publishMessageEvent(
        source: 'gateway_action_receipt',
        channelId: receiptChannelId,
        channelType: channelType,
        message: updated,
      );
      handled = true;
    }
    if (handled) {
      _markMessageChannel(
        source: 'gateway_action_receipt',
        channelId: receiptChannelId,
        channelType: channelType,
      );
    }
    return handled;
  }

  String _receiptChannelForTargets(
    String fallbackChannelId,
    int channelType,
    Set<String> targets,
  ) {
    final chat = _requireChat();
    final fallback = _canonicalChannelId(fallbackChannelId, channelType);
    bool validChannel(String channelId) {
      return channelId.isNotEmpty &&
          (channelType != chat.channelTypePerson ||
              !_isCurrentUserChannel(channelId));
    }

    bool containsTarget(String channelId) {
      final messages = _cache.readMessages(
        uid: chat.uid,
        channelId: channelId,
        channelType: channelType,
      );
      return messages.any(
        (item) => targets.contains(item['client_msg_no']?.toString() ?? ''),
      );
    }

    if (validChannel(fallback) && containsTarget(fallback)) {
      return fallback;
    }
    for (final recent in _cache.readRecentChannels(chat.uid)) {
      final separator = recent.indexOf(':');
      if (separator <= 0 || separator >= recent.length - 1) {
        continue;
      }
      final recentType = int.tryParse(recent.substring(0, separator)) ?? 0;
      if (recentType != channelType) {
        continue;
      }
      final channelId = recent.substring(separator + 1);
      if (validChannel(channelId) && containsTarget(channelId)) {
        return channelId;
      }
    }
    return validChannel(fallback) ? fallback : '';
  }

  bool _actionReceiptFromCurrentUser(Map<String, Object?> receipt) {
    final currentUserId = _requireSession().userId.toString();
    final operatorId = _value(receipt, ['operator_id', 'reader_id']);
    final operatorUid = _value(receipt, ['operator_uid', 'reader_uid']);
    return (operatorId.isNotEmpty && operatorId == currentUserId) ||
        (operatorUid.isNotEmpty && _isCurrentUserChannel(operatorUid));
  }

  bool _applyReadReceiptPayload(
    Map<String, Object?> payload,
    String channelId,
    int channelType, {
    required String source,
  }) {
    final targets = _readReceiptTargets(payload);
    if (targets.isEmpty) {
      return false;
    }
    var handled = false;
    for (final target in targets) {
      final messages = _readMessagesForChannel(channelId, channelType);
      final index = messages.indexWhere(
        (item) => _value(item, ['client_msg_no']) == target,
      );
      if (index < 0) {
        continue;
      }
      final receipt = _readReceiptInfo(payload);
      final updated = <String, Object?>{
        ...messages[index],
        'status': 'read',
        if (receipt.isNotEmpty) 'receipt': receipt,
      };
      _upsertMessage(channelId, channelType, updated);
      _publishMessageEvent(
        source: source,
        channelId: channelId,
        channelType: channelType,
        message: updated,
      );
      handled = true;
    }
    if (handled) {
      _markMessageChannel(
        source: source,
        channelId: channelId,
        channelType: channelType,
      );
    }
    return handled;
  }

  Set<String> _readReceiptTargets(Map<String, Object?> payload) {
    final targets = <String>{};
    void addValue(Object? value) {
      if (value == null) {
        return;
      }
      if (value is Iterable) {
        for (final item in value) {
          addValue(item);
        }
        return;
      }
      final text = value.toString().trim();
      if (text.isEmpty) {
        return;
      }
      for (final item in text.split(',')) {
        final target = item.trim();
        if (target.isNotEmpty) {
          targets.add(target);
        }
      }
    }

    addValue(payload['target_client_msg_no']);
    addValue(payload['target_client_msg_nos']);
    addValue(payload['target_msg_no']);
    addValue(payload['target_msg_nos']);
    addValue(payload['message_client_msg_no']);
    addValue(payload['message_client_msg_nos']);
    addValue(payload['read_client_msg_no']);
    addValue(payload['read_client_msg_nos']);
    final receipt = _asMap(payload['receipt']);
    final transfer = _asMap(payload['transfer']);
    final redPacket = _asMap(payload['red_packet']);
    for (final source in [receipt, transfer, redPacket]) {
      addValue(source['target_client_msg_no']);
      addValue(source['target_client_msg_nos']);
      addValue(source['message_client_msg_no']);
      addValue(source['message_client_msg_nos']);
      addValue(source['read_client_msg_no']);
      addValue(source['read_client_msg_nos']);
      addValue(source['original_client_msg_no']);
      addValue(source['origin_client_msg_no']);
    }
    if (targets.isEmpty) {
      addValue(payload['client_msg_no']);
    }
    return targets;
  }

  Map<String, Object?> _readReceiptInfo(Map<String, Object?> payload) {
    final receipt = _asMap(payload['receipt']);
    final readAt = _value(payload, [
      'read_at',
      'read_time',
      'timestamp',
    ], fallback: DateTime.now().millisecondsSinceEpoch.toString());
    return _cleanPayload({
      ...receipt,
      'read_at': readAt,
      if (_value(payload, ['reader_uid', 'from_uid']).isNotEmpty)
        'reader_uid': _value(payload, ['reader_uid', 'from_uid']),
      if (_value(payload, ['reader_id', 'from_id']).isNotEmpty)
        'reader_id': _value(payload, ['reader_id', 'from_id']),
      if (_intValue(payload, ['read_count', 'reader_count']) > 0)
        'read_count': _intValue(payload, ['read_count', 'reader_count']),
      if (_intValue(payload, ['unread_count']) > 0)
        'unread_count': _intValue(payload, ['unread_count']),
      if (_intValue(payload, ['total_receivers']) > 0)
        'total_receivers': _intValue(payload, ['total_receivers']),
    });
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

  _MessageUpsertResult _upsertMessage(
    String channelId,
    int channelType,
    Map<String, Object?> message,
  ) {
    final normalizedChannelId = _canonicalChannelId(channelId, channelType);
    final normalizedMessage = <String, Object?>{
      ...message,
      'channel_id': normalizedChannelId,
      'channel_type': channelType,
    };
    if (!_canStoreChannel(
      normalizedChannelId,
      channelType,
      source: 'message_upsert',
      payload: normalizedMessage,
    )) {
      return const _MessageUpsertResult(stored: false, inserted: false);
    }
    if (!_messageVisibleAfterClear(normalizedMessage) ||
        !_messageNotDeleted(normalizedMessage)) {
      return const _MessageUpsertResult(stored: false, inserted: false);
    }
    final messages = _readMessagesForChannel(
      normalizedChannelId,
      channelType,
    ).toList();
    final clientMsgNo = normalizedMessage['client_msg_no']?.toString() ?? '';
    final messageSeq = _intValue(normalizedMessage, ['message_seq']);
    final index = messages.indexWhere(
      (item) => _sameMessageIdentity(item, clientMsgNo, messageSeq),
    );
    if (index >= 0) {
      messages[index] = _mergeMessageFields(messages[index], normalizedMessage);
    } else {
      messages.add(normalizedMessage);
    }
    AppLogger.info(
      'im',
      'message upserted',
      data: {
        'channel_id': normalizedChannelId,
        'channel_type': channelType,
        'client_msg_no': clientMsgNo,
        'message_seq': messageSeq,
        'is_update': index >= 0,
        'is_me': normalizedMessage['is_me'] == true,
        'content_type': _value(normalizedMessage, ['content_type']),
        'message_count': messages.length,
      },
    );
    _writeMessages(
      normalizedChannelId,
      channelType,
      _sortAndLimit(messages, 200),
    );
    return _MessageUpsertResult(stored: true, inserted: index < 0);
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
      return _filterVisibleMessages(primary);
    }
    if (channelType != chat.channelTypePerson) {
      return _filterVisibleMessages(primary);
    }
    if (_isCurrentUserChannel(channelId)) {
      AppLogger.warn(
        'im',
        'private self channel messages ignored',
        data: {
          'channel_id': channelId,
          'channel_type': channelType,
          'cached_count': primary.length,
        },
      );
      return const <Map<String, Object?>>[];
    }

    return _filterVisibleMessages(primary);
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

  void _playIncomingMessageSoundIfNeeded(
    Map<String, Object?> message,
    GatewayFrame frame, {
    required bool inserted,
  }) {
    // Only sound for a newly stored live message; replayed stream frames and
    // server history catch-up must not behave like a new foreground delivery.
    if (!inserted) {
      return;
    }
    if (!_foreground || _manualStop || !_started) {
      return;
    }
    if (_boolValue(message['is_me'])) {
      return;
    }
    if (_messageRequestsSilentNotification(message)) {
      return;
    }
    if (!_isFreshRealtimeGatewayMessage(frame, message)) {
      return;
    }
    if (!_claimIncomingSoundIdentity(message, frame)) {
      return;
    }
    unawaited(_messageSound.play());
  }

  bool _messageRequestsSilentNotification(Map<String, Object?> message) {
    final payload = _asMap(message['payload']);
    for (final source in [message, payload]) {
      for (final key in [
        'silent',
        'no_sound',
        'mute_notification',
        'notification_silent',
      ]) {
        final value = source[key];
        if (value != null && _boolValue(value)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isFreshRealtimeGatewayMessage(
    GatewayFrame frame,
    Map<String, Object?> message,
  ) {
    var timestamp = frame.timestamp > 0
        ? frame.timestamp
        : _intValue(message, ['timestamp', 'create_time']);
    if (timestamp <= 0) {
      return false;
    }
    if (timestamp > 9999999999) {
      timestamp = timestamp ~/ 1000;
    }
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_soundFreshAfterSeconds > 0 && timestamp < _soundFreshAfterSeconds) {
      return false;
    }
    final ageSeconds = nowSeconds - timestamp;
    return ageSeconds >= -30 && ageSeconds <= 60;
  }

  bool _claimIncomingSoundIdentity(
    Map<String, Object?> message,
    GatewayFrame frame,
  ) {
    final now = DateTime.now();
    _playedIncomingSoundIds.removeWhere(
      (_, playedAt) => now.difference(playedAt) > const Duration(minutes: 3),
    );
    final identity = _incomingSoundIdentity(message, frame);
    if (identity.isEmpty) {
      return true;
    }
    if (_playedIncomingSoundIds.containsKey(identity)) {
      return false;
    }
    _playedIncomingSoundIds[identity] = now;
    return true;
  }

  String _incomingSoundIdentity(
    Map<String, Object?> message,
    GatewayFrame frame,
  ) {
    final channelId = _value(message, ['channel_id']);
    final channelType = _intValue(message, ['channel_type']);
    final candidates = <String>[
      _value(message, ['client_msg_no']),
      frame.clientMsgNo,
      _value(message, ['message_id']),
      frame.messageId,
      if (_intValue(message, ['message_seq']) > 0)
        'seq:${_intValue(message, ['message_seq'])}',
      if (frame.messageSeq > 0) 'seq:${frame.messageSeq}',
      if (frame.cursor.isNotEmpty) 'cursor:${frame.cursor}',
    ];
    for (final value in candidates) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return '$channelType:$channelId:$normalized';
      }
    }
    return '';
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
    final existingPayload = _asMap(existing['payload']);
    final incomingPayload = _asMap(incoming['payload']);
    if (existingPayload.isNotEmpty || incomingPayload.isNotEmpty) {
      final payload = <String, Object?>{...existingPayload, ...incomingPayload};
      for (final key in ['red_packet', 'transfer', 'media', 'receipt']) {
        final existingNested = _asMap(existingPayload[key]);
        final incomingNested = _asMap(incomingPayload[key]);
        if (existingNested.isNotEmpty || incomingNested.isNotEmpty) {
          payload[key] = {...existingNested, ...incomingNested};
        }
      }
      merged['payload'] = payload;
    }
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

  bool _canStoreChannel(
    String channelId,
    int channelType, {
    required String source,
    Map<String, Object?> payload = const {},
  }) {
    final chat = _requireChat();
    if (channelId.isEmpty || channelType <= 0) {
      AppLogger.warn(
        'im',
        'channel store rejected',
        data: {
          'source': source,
          'reason': 'empty_channel',
          'channel_id': channelId,
          'channel_type': channelType,
          'payload': payload,
        },
      );
      return false;
    }
    if (channelType == chat.channelTypePerson &&
        _isCurrentUserChannel(channelId)) {
      AppLogger.warn(
        'im',
        'channel store rejected',
        data: {
          'source': source,
          'reason': 'self_private_channel',
          'channel_id': channelId,
          'channel_type': channelType,
          'current_uid': chat.uid,
          'current_user_id': _requireSession().userId.toString(),
          'payload': payload,
        },
      );
      return false;
    }
    return true;
  }

  void _writeMessages(
    String channelId,
    int channelType,
    List<Map<String, Object?>> messages,
  ) {
    if (!_canStoreChannel(
      channelId,
      channelType,
      source: 'write_messages',
      payload: {'message_count': messages.length},
    )) {
      return;
    }
    final visible = _filterVisibleMessages(messages);
    AppLogger.info(
      'im',
      'messages cached',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'input_count': messages.length,
        'visible_count': visible.length,
      },
    );
    _cache.writeMessages(
      uid: _requireChat().uid,
      channelId: channelId,
      channelType: channelType,
      messages: visible,
    );
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
    final rawChannelId = message['channel_id']?.toString() ?? '';
    final channelType =
        int.tryParse(message['channel_type']?.toString() ?? '') ?? 0;
    final channelId = _canonicalChannelId(rawChannelId, channelType);
    if (!_canStoreChannel(
      channelId,
      channelType,
      source: 'conversation_upsert',
      payload: message,
    )) {
      return;
    }
    final normalizedMessage = <String, Object?>{
      ...message,
      'channel_id': channelId,
      'channel_type': channelType,
    };
    if (!_messageVisibleAfterClear(normalizedMessage) ||
        !_messageNotDeleted(normalizedMessage)) {
      return;
    }
    final receiverId = channelType == chat.channelTypePerson
        ? _receiverIdFromMessage(normalizedMessage, channelId)
        : '';
    if (channelType == chat.channelTypePerson && receiverId.isEmpty) {
      AppLogger.warn(
        'im',
        'private conversation upsert rejected',
        data: {
          'reason': 'empty_receiver',
          'raw_channel_id': rawChannelId,
          'channel_id': channelId,
          'message': normalizedMessage,
        },
      );
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
    final payload = _asMap(normalizedMessage['payload']);
    _rememberProfileFromMap(normalizedMessage);
    final content = _messageConversationContent(normalizedMessage, payload);
    final isCurrentOpen = _openMessageChannels.contains(
      _messageKey(channelId, channelType),
    );
    final isOutgoing = normalizedMessage['is_me'] == true;
    final previousUnread = index >= 0
        ? _intValue(conversations[index], ['unread_quantity'])
        : 0;
    final next = _hydrateConversationProfile(<String, Object?>{
      if (index >= 0) ...conversations[index],
      'conversation_type': channelType == chat.channelTypeGroup
          ? 'group'
          : 'private',
      if (channelType == chat.channelTypeGroup) ...{
        'group_id': _value(payload, ['group_id'], fallback: channelId),
        'name': _value(payload, ['group_name'], fallback: '群聊'),
        'group_name': _value(payload, ['group_name'], fallback: '群聊'),
      },
      if (channelType == chat.channelTypePerson) 'receiver_id': receiverId,
      'channel_id': channelId,
      'channel_type': channelType,
      'content': content,
      'content_type': normalizedMessage['content_type']?.toString() ?? '',
      'payload': payload,
      'msg_time': normalizedMessage['timestamp']?.toString() ?? '',
      'last_client_msg_no':
          normalizedMessage['client_msg_no']?.toString() ?? '',
      'last_msg_seq': normalizedMessage['message_seq'] ?? 0,
      'unread_quantity': isOutgoing || isCurrentOpen ? 0 : previousUnread + 1,
    });
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
    AppLogger.info(
      'im',
      'conversation upserted from message',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'receiver_id': receiverId,
        'client_msg_no': normalizedMessage['client_msg_no']?.toString() ?? '',
        'is_update': index >= 0,
        'unread_quantity': _intValue(next, ['unread_quantity']),
        'conversation_count': conversations.length,
      },
    );
    _bumpConversations('message_upsert');
  }

  void _replaceConversationLastMessage(
    String channelId,
    int channelType,
    Map<String, Object?> message,
  ) {
    final chat = _requireChat();
    channelId = _canonicalChannelId(channelId, channelType);
    if (!_canStoreChannel(
      channelId,
      channelType,
      source: 'replace_conversation_last_message',
      payload: message,
    )) {
      return;
    }
    final receiverId = channelType == chat.channelTypePerson
        ? _receiverIdFromMessage(message, channelId)
        : '';
    if (channelType == chat.channelTypePerson && receiverId.isEmpty) {
      AppLogger.warn(
        'im',
        'private conversation last message rejected',
        data: {
          'reason': 'empty_receiver',
          'channel_id': channelId,
          'message': message,
        },
      );
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
          _intValue(item, ['channel_type']) == channelType,
    );
    final payload = _asMap(message['payload']);
    final previousUnread = index >= 0
        ? _intValue(conversations[index], ['unread_quantity'])
        : 0;
    final content = _messageConversationContent(message, payload);
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
      if (channelType == chat.channelTypePerson) 'receiver_id': receiverId,
      'channel_id': channelId,
      'channel_type': channelType,
      'content': content,
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
    AppLogger.info(
      'im',
      'conversation last message replaced',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'receiver_id': receiverId,
        'client_msg_no': message['client_msg_no']?.toString() ?? '',
        'conversation_count': conversations.length,
      },
    );
    _bumpConversations('replace_conversation_last_message');
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
    final conversations = <Map<String, Object?>>[];
    var targetIndex = -1;
    var targetUnread = 0;
    for (final raw in _cache.readConversations(chat.uid)) {
      final normalized = _normalizeConversation(raw);
      if (!_conversationVisibleAfterClear(normalized)) {
        continue;
      }
      if (normalized['channel_id']?.toString() == channelId &&
          _intValue(normalized, ['channel_type']) == channelType) {
        targetIndex = conversations.length;
        targetUnread = _intValue(raw, ['unread_quantity', 'unread']);
      }
      conversations.add(normalized);
    }
    if (targetIndex < 0 || targetUnread == 0) {
      return false;
    }
    conversations[targetIndex] = {
      ...conversations[targetIndex],
      'unread_quantity': 0,
    };
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
    final contentType = payload['content_type']?.toString() ?? '';
    if (content.isNotEmpty &&
        contentType != ChatContentTypes.redPacket &&
        contentType != ChatContentTypes.transfer) {
      return content;
    }
    return switch (contentType) {
      ChatContentTypes.image => '[图片]',
      ChatContentTypes.emoji => '[表情]',
      ChatContentTypes.gif => '[GIF]',
      ChatContentTypes.sticker => '[贴纸]',
      ChatContentTypes.voice => '[语音]',
      ChatContentTypes.video => '[视频]',
      ChatContentTypes.file => '[文件]',
      ChatContentTypes.contactCard => '[名片]',
      ChatContentTypes.transfer => _transferContent(payload),
      ChatContentTypes.redPacket => _redPacketContent(payload),
      ChatContentTypes.redPacketReceived => '[领取红包]',
      ChatContentTypes.transferReceived => '[已收款]',
      _ => '',
    };
  }

  String _messageConversationContent(
    Map<String, Object?> message,
    Map<String, Object?> payload,
  ) {
    final contentType = _value(message, [
      'content_type',
    ], fallback: payload['content_type']?.toString() ?? '');
    final content = message['content']?.toString() ?? '';
    if (contentType == ChatContentTypes.redPacket) {
      return _redPacketContent({
        ...payload,
        if (content.isNotEmpty) 'content': content,
      });
    }
    if (contentType == ChatContentTypes.transfer) {
      return _transferContent({
        ...payload,
        if (content.isNotEmpty) 'content': content,
      });
    }
    return content.isNotEmpty ? content : _payloadContent(payload);
  }

  String _redPacketContent(Map<String, Object?> payload) {
    final content = payload['content']?.toString().trim() ?? '';
    if (content.startsWith('[红包]') && content.length > '[红包]'.length) {
      return content;
    }
    final remark = _redPacketRemark(payload);
    return remark.isEmpty ? '[红包]' : '[红包]$remark';
  }

  String _redPacketRemark(Map<String, Object?> payload) {
    final redPacket = _asMap(payload['red_packet']);
    for (final source in [redPacket, payload]) {
      final value = _value(source, [
        'remark',
        'blessing',
        'bless',
        'wish',
        'greeting',
        'greetings',
        'message',
        'content',
        'text',
        'note',
      ]);
      if (_isValidRedPacketRemark(value)) {
        return value;
      }
    }
    return '';
  }

  bool _isValidRedPacketRemark(String value) {
    final text = value.trim();
    if (text.isEmpty ||
        text == '[红包]' ||
        text == '[消息]' ||
        text == '[red_packet]') {
      return false;
    }
    if (text.startsWith('{') || text.startsWith('[')) {
      return false;
    }
    final moneyLike = RegExp(
      r'^[¥￥]?\d+(\.\d+)?\s*(money|金币|integral|积分)?$',
      caseSensitive: false,
    );
    return !moneyLike.hasMatch(text);
  }

  String _transferContent(Map<String, Object?> payload) {
    return '[转账]请收款';
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String && value.trim().isNotEmpty) {
      final text = value.trim();
      final direct = _tryDecodeJsonMap(text);
      if (direct.isNotEmpty) {
        return direct;
      }
      try {
        final decoded = utf8.decode(base64Decode(text));
        return _tryDecodeJsonMap(decoded);
      } catch (_) {
        return const <String, Object?>{};
      }
    }
    return const <String, Object?>{};
  }

  Map<String, Object?> _firstMap(List<Object?> values) {
    for (final value in values) {
      final map = _asMap(value);
      if (map.isNotEmpty) {
        return map;
      }
    }
    return const <String, Object?>{};
  }

  Map<String, Object?> _tryDecodeJsonMap(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return decoded.map((key, item) => MapEntry(key.toString(), item));
      }
    } catch (_) {
      return const <String, Object?>{};
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
    final resolved = _firstPrivatePeerChannelCandidate(candidates);
    if (resolved.isNotEmpty) {
      return resolved;
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
      _value(item, ['sender_id', 'from_id']),
      _value(payload, ['sender_id', 'from_id']),
      _receiverIdFromChannel(_value(item, ['from_uid'])),
      _receiverIdFromChannel(_value(payload, ['from_uid', 'sender_uid'])),
      _receiverIdFromChannel(_value(item, ['to_uid'])),
      _receiverIdFromChannel(_value(payload, ['to_uid', 'target_uid'])),
    ];
    final currentUserId = _requireSession().userId.toString();
    for (final candidate in candidates) {
      if (candidate.isNotEmpty && candidate != currentUserId) {
        return candidate;
      }
    }
    final fallback = channelId.isEmpty ? '' : _receiverIdFromChannel(channelId);
    return fallback == currentUserId ? '' : fallback;
  }

  String _receiverIdFromMessage(
    Map<String, Object?> message,
    String channelId,
  ) {
    final payload = _asMap(message['payload']);
    final value = _value(message, [
      'receiver_id',
    ], fallback: _value(payload, ['receiver_id', 'peer_id', 'friend_id']));
    final currentUserId = _requireSession().userId.toString();
    if (value.isNotEmpty && value != currentUserId) {
      return value;
    }
    final fallback = _receiverIdFromChannel(channelId);
    return fallback == currentUserId ? '' : fallback;
  }

  String _firstPrivatePeerChannelCandidate(Iterable<String> candidates) {
    final currentUserId = _requireSession().userId.toString();
    for (final raw in candidates) {
      final value = raw.trim();
      if (value.isEmpty) {
        continue;
      }
      final receiverId = _receiverIdFromChannel(value);
      if (receiverId.isEmpty || receiverId == currentUserId) {
        continue;
      }
      final channelId = value.startsWith('app')
          ? value
          : _uidFromUserId(receiverId);
      if (!_isCurrentUserChannel(channelId)) {
        return channelId;
      }
    }
    return '';
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
    unawaited(_messageSound.dispose());
    unawaited(_messageEvents.close());
    unawaited(_presenceEvents.close());
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

class _MessageUpsertResult {
  const _MessageUpsertResult({required this.stored, required this.inserted});

  final bool stored;
  final bool inserted;
}

class BusinessImPresenceEvent {
  const BusinessImPresenceEvent({
    required this.uid,
    required this.userId,
    required this.online,
    required this.deviceFlag,
    required this.deviceOnlineCount,
    required this.totalOnlineCount,
    required this.eventTime,
    required this.payload,
  });

  final String uid;
  final String userId;
  final bool online;
  final int deviceFlag;
  final int deviceOnlineCount;
  final int totalOnlineCount;
  final String eventTime;
  final Map<String, Object?> payload;
}
