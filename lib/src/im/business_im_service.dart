import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../calls/livekit_call_models.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/models.dart';
import 'gateway_stream_client.dart';
import 'im_cache_store.dart';
import 'im_message_types.dart';
import 'message_notification_sound.dart';

class BusinessImInitialSyncState {
  const BusinessImInitialSyncState({
    required this.syncing,
    required this.progress,
    required this.text,
    this.error,
  });

  final bool syncing;
  final double progress;
  final String text;
  final String? error;

  bool get blocked => syncing || error != null;
}

class _ServerHistoryLoadResult {
  const _ServerHistoryLoadResult({
    required this.messages,
    required this.complete,
  });

  final List<Map<String, Object?>> messages;
  final bool complete;
}

class BusinessImService extends ChangeNotifier {
  BusinessImService({required ApiClient api, required ImCacheStore cache})
    : _api = api,
      _cache = cache;

  static const int _messageCacheLimit = 1000;
  static const int _historySyncLimit = 500;
  static const int _readReceiptBatchSize = 100;

  final ApiClient _api;
  final ImCacheStore _cache;
  final MessageNotificationSound _messageSound = MessageNotificationSound();
  final Random _random = Random.secure();
  final StreamController<BusinessImMessageEvent> _messageEvents =
      StreamController<BusinessImMessageEvent>.broadcast();
  final StreamController<BusinessImPresenceEvent> _presenceEvents =
      StreamController<BusinessImPresenceEvent>.broadcast();
  final StreamController<BusinessImCallEvent> _callEvents =
      StreamController<BusinessImCallEvent>.broadcast();
  final StreamController<BusinessImFriendEvent> _friendEvents =
      StreamController<BusinessImFriendEvent>.broadcast();

  UserSession? _session;
  String _device = '';
  GatewayStreamClient? _gatewayStream;
  int _gatewayEpoch = 0;
  String _gatewayTicket = '';
  String _gatewayAckUrl = '';
  DateTime? _gatewayTicketExpiresAt;
  DateTime? _gatewayChatIssuedAt;
  bool _gatewayOpenTicketAvailable = false;
  final Queue<GatewayFrame> _gatewayAckQueue = Queue<GatewayFrame>();
  Timer? _reconnectTimer;
  Timer? _networkReconnectTimer;
  Timer? _connectionStableTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _started = false;
  bool _manualStop = false;
  bool _connecting = false;
  bool _foreground = true;
  bool _backgroundKeepAliveEnabled = true;
  bool _authInvalid = false;
  String? _sessionRevocationMessage;
  bool _gatewayAckDraining = false;
  bool _networkAvailable = true;
  bool _realtimeValidated = false;
  int _reconnectAttempt = 0;
  int _connectOperationEpoch = 0;
  CancelToken? _gatewayConnectCancelToken;
  String _networkSignature = '';
  DateTime? _realtimeValidatedAt;
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
  final Set<String> _invalidMessageChannels = <String>{};
  bool _serverConversationsSynced = false;
  bool _initialHistorySyncing = false;
  double _initialHistorySyncProgress = 0;
  String _initialHistorySyncText = '准备同步聊天数据';
  String? _initialHistorySyncError;
  bool _hasRealtimeConnectedOnce = false;
  bool _suppressCatchupSoundOnNextConnect = true;
  int _soundFreshAfterSeconds = 0;
  final Set<String> _openMessageChannels = <String>{};
  final Set<String> _readVisibleMessageChannels = <String>{};
  final Set<String> _reportedReadReceiptKeys = <String>{};
  final Set<String> _handledDeleteCommandKeys = <String>{};
  final Queue<String> _handledDeleteCommandKeyOrder = Queue<String>();
  final Map<String, DateTime> _playedIncomingSoundIds = <String, DateTime>{};
  final Map<String, Map<String, Object?>> _groupMuteStates =
      <String, Map<String, Object?>>{};
  final Map<String, int> _presenceLatestEventSeconds = <String, int>{};
  final Map<String, List<Map<String, Object?>>> _pendingActionReceipts =
      <String, List<Map<String, Object?>>>{};
  int _presenceRealtimeAfterSeconds = 0;

  Stream<BusinessImMessageEvent> get messageEvents => _messageEvents.stream;
  Stream<BusinessImPresenceEvent> get presenceEvents => _presenceEvents.stream;
  Stream<BusinessImCallEvent> get callEvents => _callEvents.stream;
  Stream<BusinessImFriendEvent> get friendEvents => _friendEvents.stream;
  bool get isStarted => _started;
  String get statusText => _statusText;
  String? get sessionRevocationMessage => _sessionRevocationMessage;
  String? get lastError => _lastError;
  bool get backgroundKeepAliveEnabled => _backgroundKeepAliveEnabled;
  int get conversationVersion => _conversationVersion;
  bool get initialHistorySyncing => _initialHistorySyncing;
  bool get initialHistorySyncBlocked =>
      _initialHistorySyncing || _initialHistorySyncError != null;
  BusinessImInitialSyncState get initialHistorySyncState =>
      BusinessImInitialSyncState(
        syncing: _initialHistorySyncing,
        progress: _initialHistorySyncProgress,
        text: _initialHistorySyncText,
        error: _initialHistorySyncError,
      );

  bool isInvalidChannel({required String channelID, required int channelType}) {
    channelID = _canonicalChannelId(channelID, channelType);
    return _invalidMessageChannels.contains(
      _messageKey(channelID, channelType),
    );
  }

  List<Map<String, Object?>> cachedConversations() {
    final chat = _session?.chat;
    if (chat == null) {
      return const [];
    }
    if (_latestConversations.isEmpty) {
      _latestConversations = _sortConversations(
        _dedupeConversations(_cache.readConversations(chat.uid)),
      );
    }
    return _sortConversations(
      _latestConversations,
    ).map((item) => Map<String, Object?>.from(item)).toList(growable: false);
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

  Future<void> start(
    UserSession session, {
    required String device,
    bool chatIsFresh = false,
    bool backgroundKeepAliveEnabled = true,
  }) async {
    final chat = session.chat;
    if (chat == null || chat.uid.isEmpty || chat.token.isEmpty) {
      throw ApiException('IM 登录材料缺失');
    }
    _manualStop = false;
    _started = true;
    _authInvalid = false;
    _sessionRevocationMessage = null;
    _backgroundKeepAliveEnabled = backgroundKeepAliveEnabled;
    _session = session;
    _device = device;
    _gatewayChatIssuedAt = chatIsFresh ? DateTime.now() : null;
    _gatewayOpenTicketAvailable = chatIsFresh;
    _groupMuteStates.clear();
    _historySyncedChannels.clear();
    _historyRetryAfter.clear();
    _invalidMessageChannels.clear();
    _serverConversationsSynced = false;
    _hasRealtimeConnectedOnce = false;
    _suppressCatchupSoundOnNextConnect = true;
    _soundFreshAfterSeconds = 0;
    _presenceRealtimeAfterSeconds = 0;
    _presenceLatestEventSeconds.clear();
    _pendingActionReceipts.clear();
    _playedIncomingSoundIds.clear();
    _reportedReadReceiptKeys.clear();
    _latestConversations = _dedupeConversations(
      _cache
          .readConversations(chat.uid)
          .map(_hydrateConversationProfile)
          .toList(growable: false),
    );
    _setInitialHistorySyncState(
      syncing:
          _latestConversations.isEmpty && _conversationHistorySyncEnabled(chat),
      progress: 0.04,
      text: '准备同步聊天数据',
      error: null,
      notify: false,
    );
    _cache.writeConversations(
      uid: chat.uid,
      conversations: _latestConversations,
    );
    _bumpConversations('cache_loaded', notify: false);
    await _startConnectivityMonitoring();
    AppLogger.info(
      'im',
      'business im start',
      data: {
        'uid': chat.uid,
        'device': device,
        'private_history_sync_enabled': chat.privateHistorySyncEnabled,
        'group_history_sync_enabled': chat.groupHistorySyncEnabled,
        'background_keep_alive_enabled': _backgroundKeepAliveEnabled,
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
    _authInvalid = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _networkReconnectTimer?.cancel();
    _networkReconnectTimer = null;
    _connectionStableTimer?.cancel();
    _connectionStableTimer = null;
    _connectOperationEpoch++;
    _gatewayConnectCancelToken?.cancel('realtime stopped');
    _gatewayConnectCancelToken = null;
    _realtimeValidated = false;
    _realtimeValidatedAt = null;
    final gatewayStream = _gatewayStream;
    _gatewayStream = null;
    _gatewayTicket = '';
    _gatewayAckUrl = '';
    _gatewayTicketExpiresAt = null;
    _gatewayChatIssuedAt = null;
    _gatewayOpenTicketAvailable = false;
    _gatewayAckQueue.clear();
    _gatewayAckDraining = false;
    _syncingConversations = null;
    _setInitialHistorySyncState(
      syncing: false,
      progress: 0,
      text: '准备同步聊天数据',
      error: null,
      notify: false,
    );
    _soundFreshAfterSeconds = 0;
    _presenceRealtimeAfterSeconds = 0;
    _presenceLatestEventSeconds.clear();
    _pendingActionReceipts.clear();
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
      _handledDeleteCommandKeys.clear();
      _handledDeleteCommandKeyOrder.clear();
      _presenceLatestEventSeconds.clear();
      _pendingActionReceipts.clear();
      _invalidMessageChannels.clear();
    }
    _setStatus('未连接');
  }

  void onAppBackgrounded(String state) {
    AppLogger.info('im', 'app backgrounded', data: {'state': state});
    if (state == 'inactive') {
      return;
    }
    _foreground = false;
    _readVisibleMessageChannels.clear();
    _suppressCatchupSoundOnNextConnect = true;
    if (!_backgroundKeepAliveEnabled) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _networkReconnectTimer?.cancel();
      _networkReconnectTimer = null;
      unawaited(
        _discardRealtimeConnection(
          source: 'background_keep_alive_disabled',
          reconnect: false,
        ),
      );
    }
    AppLogger.info(
      'im',
      'background realtime policy applied',
      data: {
        'state': state,
        'background_keep_alive_enabled': _backgroundKeepAliveEnabled,
        'gateway_active': _gatewayStream != null,
        'connecting': _connecting,
      },
    );
  }

  void resumeConnection() {
    if (!_started || _authInvalid || _session == null) {
      AppLogger.info(
        'im',
        'resume realtime skipped',
        data: {
          'started': _started,
          'auth_invalid': _authInvalid,
          'has_session': _session != null,
        },
      );
      return;
    }
    _foreground = true;
    final stream = _gatewayStream;
    final healthy = stream?.isHealthy() ?? false;
    AppLogger.info(
      'im',
      'resume realtime health checked',
      data: {
        'gateway_active': stream != null,
        'validated': _realtimeValidated,
        'healthy': healthy,
        'last_frame_at': stream?.lastFrameAt?.toIso8601String() ?? '',
      },
    );
    if (stream == null || !_realtimeValidated || !healthy) {
      unawaited(
        _discardRealtimeConnection(
          source: 'foreground_health_check',
          reconnect: true,
          delay: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  void setBackgroundKeepAliveEnabled(bool enabled) {
    if (_backgroundKeepAliveEnabled == enabled) {
      return;
    }
    _backgroundKeepAliveEnabled = enabled;
    AppLogger.info(
      'im',
      'background keep alive policy changed',
      data: {'enabled': enabled, 'foreground': _foreground},
    );
    if (!enabled && !_foreground) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      unawaited(
        _discardRealtimeConnection(
          source: 'background_policy_changed',
          reconnect: false,
        ),
      );
    } else if (enabled && _started && _gatewayStream == null && !_connecting) {
      unawaited(_connectRealtime());
    }
    notifyListeners();
  }

  Future<void> _startConnectivityMonitoring() async {
    final connectivity = Connectivity();
    try {
      final current = await connectivity.checkConnectivity();
      _networkSignature = _connectivitySignature(current);
      _networkAvailable = !_isNetworkUnavailable(current);
    } catch (error) {
      AppLogger.warn(
        'im',
        'initial connectivity check failed',
        data: {'error': error.toString()},
      );
    }
    if (_connectivitySubscription != null) {
      return;
    }
    _connectivitySubscription = connectivity.onConnectivityChanged.listen(
      _handleConnectivityChanged,
      onError: (Object error) {
        AppLogger.warn(
          'im',
          'connectivity listener failed',
          data: {'error': error.toString()},
        );
      },
    );
  }

  void _handleConnectivityChanged(List<ConnectivityResult> results) {
    final signature = _connectivitySignature(results);
    final wasAvailable = _networkAvailable;
    final previousSignature = _networkSignature;
    _networkSignature = signature;
    _networkAvailable = !_isNetworkUnavailable(results);
    AppLogger.info(
      'im',
      'network connectivity changed',
      data: {
        'previous': previousSignature,
        'current': signature,
        'available': _networkAvailable,
        'started': _started,
      },
    );
    if (!_started || _manualStop) {
      return;
    }
    if (!_networkAvailable) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _networkReconnectTimer?.cancel();
      _networkReconnectTimer = null;
      unawaited(
        _discardRealtimeConnection(
          source: 'network_unavailable',
          reconnect: false,
        ),
      );
      _setStatus('重连中');
      return;
    }
    final networkChanged =
        !wasAvailable ||
        (previousSignature.isNotEmpty && previousSignature != signature);
    if (networkChanged) {
      unawaited(
        _discardRealtimeConnection(
          source: wasAvailable ? 'network_switched' : 'network_restored',
          reconnect: true,
          delay: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  bool _isNetworkUnavailable(List<ConnectivityResult> results) {
    return results.isEmpty ||
        results.every((item) => item == ConnectivityResult.none);
  }

  String _connectivitySignature(List<ConnectivityResult> results) {
    final names = results.map((item) => item.name).toSet().toList()..sort();
    return names.join(',');
  }

  Future<void> _discardRealtimeConnection({
    required String source,
    required bool reconnect,
    Duration delay = Duration.zero,
  }) async {
    final operationEpoch = ++_connectOperationEpoch;
    _connecting = false;
    _gatewayConnectCancelToken?.cancel('realtime discarded: $source');
    _gatewayConnectCancelToken = null;
    _realtimeValidated = false;
    _realtimeValidatedAt = null;
    _connectionStableTimer?.cancel();
    _connectionStableTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _networkReconnectTimer?.cancel();
    _networkReconnectTimer = null;
    await _closeRealtimeOnly();
    if (operationEpoch != _connectOperationEpoch) {
      return;
    }
    AppLogger.info(
      'im',
      'realtime connection discarded',
      data: {
        'source': source,
        'reconnect': reconnect,
        'delay_ms': delay.inMilliseconds,
      },
    );
    if (!reconnect ||
        !_started ||
        _manualStop ||
        _authInvalid ||
        !_networkAvailable ||
        (!_foreground && !_backgroundKeepAliveEnabled)) {
      return;
    }
    _setStatus('重连中');
    _networkReconnectTimer = Timer(delay, _connectRealtime);
  }

  Future<List<Map<String, Object?>>> refreshLocalConversations({
    bool notify = true,
  }) async {
    final chat = _requireChat();
    _latestConversations = _sortConversations(
      _dedupeConversations(
        _cache
            .readConversations(chat.uid)
            .map(_hydrateConversationProfile)
            .toList(growable: false),
      ),
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

  Future<void> setConversationPinned({
    required String channelID,
    required int channelType,
    required bool pinned,
  }) async {
    final chat = _requireChat();
    final channelId = _canonicalChannelId(channelID, channelType);
    if (channelId.isEmpty || channelType <= 0) {
      return;
    }
    _cache.setConversationPinned(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
      pinned: pinned,
    );
    _latestConversations = _sortConversations(
      _latestConversations.isNotEmpty
          ? _latestConversations
          : _cache.readConversations(chat.uid),
    );
    _cache.writeConversations(
      uid: chat.uid,
      conversations: _latestConversations,
    );
    _bumpConversations(pinned ? 'pin_conversation' : 'unpin_conversation');
    AppLogger.info(
      'im',
      pinned ? 'conversation pinned' : 'conversation unpinned',
      data: {'channel_id': channelId, 'channel_type': channelType},
    );
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
    AppLogger.info(
      'im',
      'conversation opened',
      data: {'channel_id': channelID, 'channel_type': channelType},
    );
  }

  void closeConversation({
    required String channelID,
    required int channelType,
  }) {
    channelID = _canonicalChannelId(channelID, channelType);
    final key = _messageKey(channelID, channelType);
    _readVisibleMessageChannels.remove(key);
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
        return false;
      }),
    );
    _openMessageChannels.remove(key);
  }

  Future<void> markConversationVisibleRead({
    required String channelID,
    required int channelType,
  }) async {
    channelID = _canonicalChannelId(channelID, channelType);
    final key = _messageKey(channelID, channelType);
    if (!_foreground || !_openMessageChannels.contains(key)) {
      AppLogger.info(
        'im',
        'visible read ignored',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'foreground': _foreground,
          'open_channel': _openMessageChannels.contains(key),
        },
      );
      return;
    }
    final changed = await markConversationRead(
      channelID: channelID,
      channelType: channelType,
    );
    _readVisibleMessageChannels.add(key);
    if (changed) {
      AppLogger.info(
        'im',
        'conversation visible read',
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
    }
  }

  Future<bool> markConversationRead({
    required String channelID,
    required int channelType,
  }) async {
    channelID = _canonicalChannelId(channelID, channelType);
    final chat = _requireChat();
    final previousMarker = _cache.readReadMarker(
      uid: chat.uid,
      channelId: channelID,
      channelType: channelType,
    );
    final messages = _cache.readMessages(
      uid: chat.uid,
      channelId: channelID,
      channelType: channelType,
    );
    final markerAdvanced = _writeReadMarkerForMessages(
      channelID,
      channelType,
      messages,
      previousMarker: previousMarker,
    );
    if (markerAdvanced) {
      unawaited(
        _reportReadReceiptsForMessages(
          channelId: channelID,
          channelType: channelType,
          messages: messages,
          previousMarker: previousMarker,
        ),
      );
    }
    final unreadCleared = _clearConversationUnread(
      channelID,
      channelType,
      source: 'mark_read',
    );
    if (unreadCleared) {
      _markMessageChannel(
        source: 'mark_read',
        channelId: channelID,
        channelType: channelType,
      );
    }
    return markerAdvanced || unreadCleared;
  }

  Future<void> _reportReadReceiptsForMessages({
    required String channelId,
    required int channelType,
    required List<Map<String, Object?>> messages,
    required Map<String, Object?> previousMarker,
  }) async {
    final session = _session;
    final chat = session?.chat;
    if (session == null || chat == null) {
      return;
    }
    final targets = messages
        .where((item) => item['is_me'] != true)
        .where((item) => !_isSystemActionMessage(item))
        .where((item) => _value(item, ['client_msg_no']).isNotEmpty)
        .where((item) => !_readMarkerCoversMessage(previousMarker, item))
        .toList(growable: false);
    if (targets.isEmpty) {
      return;
    }
    final pending = <Map<String, Object?>>[];
    for (final item in targets) {
      final targetClientMsgNo = _value(item, ['client_msg_no']);
      final key = _readReceiptKey(channelId, channelType, targetClientMsgNo);
      if (!_reportedReadReceiptKeys.add(key)) {
        continue;
      }
      pending.add({
        'target_client_msg_no': targetClientMsgNo,
        if (_intValue(item, ['message_seq']) > 0)
          'message_seq': _intValue(item, ['message_seq']),
      });
    }
    if (pending.isEmpty) {
      return;
    }
    for (
      var offset = 0;
      offset < pending.length;
      offset += _readReceiptBatchSize
    ) {
      final chunk = pending
          .skip(offset)
          .take(_readReceiptBatchSize)
          .toList(growable: false);
      try {
        await _api.imBusinessAction(
          action: 'im_message_read_receipts',
          session: session,
          device: _device,
          params: {
            'client_msg_no': newClientMsgNo(),
            'channel_id': channelId,
            'channel_type': channelType.toString(),
            'receipts': jsonEncode(chunk),
          },
          secureResponse: true,
        );
        AppLogger.info(
          'im',
          'read receipt batch reported',
          data: {
            'channel_id': channelId,
            'channel_type': channelType,
            'count': chunk.length,
          },
        );
      } catch (error, stackTrace) {
        for (final item in chunk) {
          final targetClientMsgNo = _value(item, ['target_client_msg_no']);
          _reportedReadReceiptKeys.remove(
            _readReceiptKey(channelId, channelType, targetClientMsgNo),
          );
        }
        AppLogger.warn(
          'im',
          'read receipt batch report failed',
          data: {
            'channel_id': channelId,
            'channel_type': channelType,
            'count': chunk.length,
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
    _latestConversations = _sortConversations(_latestConversations);
    _forgetChannelHistorySynced(channelID, channelType);
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

  void storeRecallReceipt({
    required String channelID,
    required int channelType,
    required Map<String, Object?> receipt,
  }) {
    if (receipt.isEmpty) return;
    channelID = _canonicalChannelId(channelID, channelType);
    _upsertMessage(channelID, channelType, receipt);
    _upsertConversationFromMessage(receipt);
    _markMessageChannel(
      source: 'recall_receipt_local',
      channelId: channelID,
      channelType: channelType,
    );
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

  void _setInitialHistorySyncState({
    required bool syncing,
    required double progress,
    required String text,
    String? error,
    bool notify = true,
  }) {
    final normalizedProgress = progress.clamp(0, 1).toDouble();
    final changed =
        _initialHistorySyncing != syncing ||
        _initialHistorySyncProgress != normalizedProgress ||
        _initialHistorySyncText != text ||
        _initialHistorySyncError != error;
    _initialHistorySyncing = syncing;
    _initialHistorySyncProgress = normalizedProgress;
    _initialHistorySyncText = text;
    _initialHistorySyncError = error;
    if (changed && notify) {
      notifyListeners();
    }
  }

  void _updateInitialHistorySyncProgress(double progress, String text) {
    if (!_initialHistorySyncing) {
      return;
    }
    _setInitialHistorySyncState(
      syncing: true,
      progress: progress,
      text: text,
      error: null,
    );
  }

  Future<List<Map<String, Object?>>> _syncConversationsFromServerOnce() async {
    final session = _requireSession();
    final chat = _requireChat();
    final initialLocal = _currentLocalConversations(chat);
    final shouldGateInitialSync =
        initialLocal.isEmpty &&
        _latestConversations.isEmpty &&
        !_serverConversationsSynced &&
        _conversationHistorySyncEnabled(chat);
    if (shouldGateInitialSync && !_initialHistorySyncing) {
      _setInitialHistorySyncState(
        syncing: true,
        progress: 0.06,
        text: '准备同步聊天数据',
        error: null,
      );
    }
    final initialSync = _initialHistorySyncing;
    final statusBeforeSync = _statusText;
    if (initialSync && statusBeforeSync == '已连接') {
      _setStatus('同步中');
    }
    try {
      _updateInitialHistorySyncProgress(0.12, '正在连接消息服务');
      _updateInitialHistorySyncProgress(0.22, '正在获取会话列表');
      final list = await _api.conversations(
        session: session,
        device: _device,
        limit: 50,
      );
      _updateInitialHistorySyncProgress(0.36, '正在整理会话资料');
      final normalizedServerConversations = list
          .map(_normalizeConversation)
          .where((item) => _shouldAcceptServerConversation(item, chat))
          .where(_conversationVisibleAfterClear)
          .map(_rememberConversationProfile)
          .map(_hydrateConversationProfile)
          .toList();
      final serverConversations = await _hydrateEmptyConversationsFromHistory(
        normalizedServerConversations,
        onProgress: initialSync
            ? (completed, total) {
                final ratio = total <= 0 ? 1.0 : completed / total;
                final progress = 0.42 + ratio.clamp(0, 1).toDouble() * 0.43;
                _updateInitialHistorySyncProgress(
                  progress,
                  total <= 0 ? '正在恢复聊天记录' : '正在恢复聊天记录 $completed/$total',
                );
              }
            : null,
      );
      _updateInitialHistorySyncProgress(0.88, '正在合并聊天数据');
      final latestBeforeMerge = _latestConversations
          .map(_normalizeConversation)
          .where(_conversationVisibleAfterClear)
          .toList(growable: false);
      final freshLocal = _currentLocalConversations(chat);
      _latestConversations = _sortConversations(
        _mergeConversationLists(
              serverConversations,
              _mergeConversationLists(freshLocal, latestBeforeMerge),
            )
            .map(_rememberConversationProfile)
            .map(_hydrateConversationProfile)
            .toList(growable: false),
      );
      _updateInitialHistorySyncProgress(0.94, '正在写入本地缓存');
      _cache.writeConversations(
        uid: chat.uid,
        conversations: _latestConversations,
      );
      _serverConversationsSynced = true;
      _bumpConversations('server_sync');
      _updateInitialHistorySyncProgress(0.98, '正在刷新首页');
      AppLogger.info(
        'im',
        'server conversations synced',
        data: {
          'initial_local_count': initialLocal.length,
          'fresh_local_count': freshLocal.length,
          'memory_count': latestBeforeMerge.length,
          'server_raw_count': list.length,
          'server_accepted_count': serverConversations.length,
          'merged_count': _latestConversations.length,
          'private_history_sync_enabled': chat.privateHistorySyncEnabled,
          'group_history_sync_enabled': chat.groupHistorySyncEnabled,
        },
      );
      _setInitialHistorySyncState(
        syncing: false,
        progress: 1,
        text: '同步完成',
        error: null,
        notify: false,
      );
      if (initialSync && _statusText == '同步中') {
        _setStatus('已连接');
      }
      notifyListeners();
      return _latestConversations;
    } catch (error, stackTrace) {
      _setInitialHistorySyncState(
        syncing: false,
        progress: _initialHistorySyncProgress,
        text: '同步失败',
        error: initialSync ? '聊天数据同步失败，请检查网络后重试' : null,
        notify: false,
      );
      if (initialSync && _statusText == '同步中') {
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

  List<Map<String, Object?>> cachedLocalMessages({
    required String channelID,
    required int channelType,
    int limit = _messageCacheLimit,
  }) {
    final rawChannelId = channelID;
    channelID = _canonicalChannelId(channelID, channelType);
    final key = _messageKey(channelID, channelType);
    if (_invalidMessageChannels.contains(key)) {
      AppLogger.info(
        'im',
        'cached local messages skipped for invalid channel',
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
      return const <Map<String, Object?>>[];
    }
    final cached = _sortAndLimit(
      _readMessagesForChannel(channelID, channelType),
      limit,
    );
    AppLogger.info(
      'im',
      'cached local messages read',
      data: {
        'raw_channel_id': rawChannelId,
        'channel_id': channelID,
        'channel_type': channelType,
        'result_count': cached.length,
      },
    );
    return cached;
  }

  Future<List<Map<String, Object?>>> localMessages({
    required String channelID,
    required int channelType,
    String groupId = '',
    int limit = _messageCacheLimit,
  }) async {
    final rawChannelId = channelID;
    channelID = _canonicalChannelId(channelID, channelType);
    final key = _messageKey(channelID, channelType);
    if (_invalidMessageChannels.contains(key)) {
      AppLogger.info(
        'im',
        'local messages skipped for invalid channel',
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
      return const <Map<String, Object?>>[];
    }
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
    final historySynced = _isChannelHistorySynced(channelID, channelType);
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
          'cached_count': cached.length,
        },
      );
      if (cached.isEmpty) {
        cached = await syncChannelMessages(
          channelID: channelID,
          channelType: channelType,
          groupId: groupId,
          limit: limit,
        );
      } else {
        unawaited(
          syncChannelMessages(
            channelID: channelID,
            channelType: channelType,
            groupId: groupId,
            limit: limit,
          ),
        );
      }
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
    final syncedAfterLoad = _isChannelHistorySynced(channelID, channelType);
    final sorted = _sortAndLimit(cached, limit);
    AppLogger.info(
      'im',
      'local messages result',
      data: {
        'raw_channel_id': rawChannelId,
        'channel_id': channelID,
        'channel_type': channelType,
        'group_id': groupId,
        'history_synced': syncedAfterLoad,
        'needs_history_sync': needsHistorySync,
        'retry_blocked': retryBlocked,
        'open_channel': _openMessageChannels.contains(key),
        'read_visible_channel': _readVisibleMessageChannels.contains(key),
        'cached_count': cached.length,
        'result_count': sorted.length,
        'first_message': _messageLogSummary(
          sorted.isEmpty ? const <String, Object?>{} : sorted.first,
        ),
        'last_message': _messageLogSummary(
          sorted.isEmpty ? const <String, Object?>{} : sorted.last,
        ),
      },
    );
    if (_foreground && _readVisibleMessageChannels.contains(key)) {
      final previousMarker = _cache.readReadMarker(
        uid: _requireChat().uid,
        channelId: channelID,
        channelType: channelType,
      );
      _writeReadMarkerForMessages(channelID, channelType, sorted);
      unawaited(
        _reportReadReceiptsForMessages(
          channelId: channelID,
          channelType: channelType,
          messages: sorted,
          previousMarker: previousMarker,
        ),
      );
      _clearConversationUnread(channelID, channelType, source: 'local_read');
    }
    return sorted;
  }

  Future<List<Map<String, Object?>>> syncChannelMessages({
    required String channelID,
    required int channelType,
    String groupId = '',
    int limit = 50,
    bool unreadOnly = false,
    int unreadLimit = 0,
  }) async {
    channelID = _canonicalChannelId(channelID, channelType);
    final key = _messageKey(channelID, channelType);
    final syncKey = unreadOnly ? '$key:unread:${max(1, unreadLimit)}' : key;
    if (_invalidMessageChannels.contains(key)) {
      return const <Map<String, Object?>>[];
    }
    final running = _syncingChannels[syncKey];
    if (running != null) {
      AppLogger.info(
        'im',
        'reuse running channel history sync',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'unread_only': unreadOnly,
        },
      );
      return running;
    }
    final future = _syncChannelMessagesOnce(
      channelID: channelID,
      channelType: channelType,
      groupId: groupId,
      limit: limit,
      unreadOnly: unreadOnly,
      unreadLimit: unreadLimit,
    );
    _syncingChannels[syncKey] = future;
    try {
      return await future;
    } finally {
      if (identical(_syncingChannels[syncKey], future)) {
        _syncingChannels.remove(syncKey);
      }
    }
  }

  Future<List<Map<String, Object?>>> _syncChannelMessagesOnce({
    required String channelID,
    required int channelType,
    String groupId = '',
    int limit = 50,
    bool unreadOnly = false,
    int unreadLimit = 0,
  }) async {
    final session = _requireSession();
    final chat = _requireChat();
    if (!_historySyncEnabledForType(channelType, chat) && !unreadOnly) {
      _markChannelHistorySynced(channelID, channelType, persist: false);
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
        min(limit, _messageCacheLimit),
      );
    }
    try {
      final history = await _loadServerHistoryMessages(
        session: session,
        chat: chat,
        channelID: channelID,
        channelType: channelType,
        groupId: groupId,
        limit: max(limit, _historySyncLimit),
        unreadOnly: unreadOnly,
        unreadLimit: unreadLimit,
      );
      final list = history.messages;
      final messages = _normalizeServerHistoryMessages(
        rawMessages: list,
        channelId: channelID,
        channelType: channelType,
      );
      if (messages.isNotEmpty) {
        _clearLocalHistoryBoundaryAfterServerSync(
          channelId: channelID,
          channelType: channelType,
          acceptedCount: messages.length,
        );
      }
      final current = _readMessagesForChannel(channelID, channelType);
      final authoritativeCurrent = unreadOnly
          ? current
          : _applyAuthoritativeServerWindow(
              current: current,
              serverMessages: messages,
              serverRawCount: list.length,
              serverWindowComplete: history.complete,
              channelId: channelID,
              channelType: channelType,
            );
      final merged = _mergeMessages(authoritativeCurrent, messages);
      final storedMessages = _sortAndLimit(merged, _messageCacheLimit);
      _writeMessages(channelID, channelType, storedMessages);
      final conversationMessage = _lastConversationMessage(storedMessages);
      if (conversationMessage.isNotEmpty) {
        _replaceConversationLastMessage(
          channelID,
          channelType,
          conversationMessage,
        );
      }
      _markChannelHistorySynced(channelID, channelType, persist: !unreadOnly);
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
          'server_history_complete': history.complete,
          'unread_only': unreadOnly,
          'unread_limit': unreadLimit,
          'merged_count': merged.length,
          'stored_count': storedMessages.length,
          'server_first_message': _messageLogSummary(
            messages.isEmpty ? const <String, Object?>{} : messages.first,
          ),
          'server_last_message': _messageLogSummary(
            messages.isEmpty ? const <String, Object?>{} : messages.last,
          ),
          'stored_first_message': _messageLogSummary(
            storedMessages.isEmpty
                ? const <String, Object?>{}
                : storedMessages.first,
          ),
          'stored_last_message': _messageLogSummary(
            storedMessages.isEmpty
                ? const <String, Object?>{}
                : storedMessages.last,
          ),
          if (channelType == chat.channelTypePerson)
            'receiver_id': _receiverIdFromChannel(channelID),
          if (channelType == chat.channelTypeGroup)
            'group_id': groupId.isNotEmpty
                ? groupId
                : _groupIdForChannel(channelID),
        },
      );
      return _sortAndLimit(merged, min(limit, _messageCacheLimit));
    } catch (error, stackTrace) {
      if (channelType == chat.channelTypeGroup && _isMissingGroupError(error)) {
        AppLogger.warn(
          'im',
          'invalid group channel removed',
          data: {
            'channel_id': channelID,
            'channel_type': channelType,
            'group_id': groupId.isNotEmpty
                ? groupId
                : _groupIdForChannel(channelID),
            'error': error.toString(),
          },
        );
        _removeInvalidChannel(
          channelId: channelID,
          channelType: channelType,
          source: 'group_history_not_found',
        );
        return const <Map<String, Object?>>[];
      }
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

  Future<_ServerHistoryLoadResult> _loadServerHistoryMessages({
    required UserSession session,
    required ChatSession chat,
    required String channelID,
    required int channelType,
    required String groupId,
    required int limit,
    bool unreadOnly = false,
    int unreadLimit = 0,
  }) async {
    final effectiveUnreadLimit = max(1, unreadLimit);
    final pageLimit = unreadOnly
        ? min(200, effectiveUnreadLimit)
        : min(200, max(1, limit));
    final maxMessages = unreadOnly
        ? min(_messageCacheLimit, pageLimit)
        : min(_messageCacheLimit, max(limit, pageLimit));
    final all = <Map<String, Object?>>[];
    final seen = <String>{};
    var startMessageSeq = 0;
    var pullMode = 0;
    var page = 0;
    var complete = false;
    while (all.length < maxMessages) {
      page++;
      final pageData = channelType == chat.channelTypeGroup
          ? await _api.groupMessagePage(
              session: session,
              device: _device,
              groupId: groupId.isNotEmpty
                  ? groupId
                  : _groupIdForChannel(channelID),
              startMessageSeq: startMessageSeq,
              limit: pageLimit,
              pullMode: pullMode,
              unreadOnly: unreadOnly,
              unreadLimit: effectiveUnreadLimit,
            )
          : await _api.personMessagePage(
              session: session,
              device: _device,
              receiverId: _receiverIdFromChannel(channelID),
              startMessageSeq: startMessageSeq,
              limit: pageLimit,
              pullMode: pullMode,
              unreadOnly: unreadOnly,
              unreadLimit: effectiveUnreadLimit,
            );
      final pageMessages = _historyPageMessages(pageData);
      var added = 0;
      for (final message in pageMessages) {
        final key = _historyRawIdentity(message);
        if (key.isNotEmpty && !seen.add(key)) {
          continue;
        }
        all.add(message);
        added++;
        if (all.length >= maxMessages) {
          break;
        }
      }
      final more = _boolValue(pageData['more']);
      final minMessageSeq = _minRawHistoryMessageSeq(pageMessages);
      final serverNextStartSeq = _intValue(pageData, [
        'next_start_message_seq',
        'next_message_seq',
        'next_seq',
      ]);
      final nextStartSeq = serverNextStartSeq > 0
          ? serverNextStartSeq
          : (minMessageSeq > 0 ? max(0, minMessageSeq - 1) : 0);
      AppLogger.info(
        'im',
        'server history page loaded',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'page': page,
          'raw_count': pageMessages.length,
          'added_count': added,
          'total_count': all.length,
          'more': more ? 1 : 0,
          'start_message_seq': startMessageSeq,
          'min_message_seq': minMessageSeq,
          'next_start_message_seq': nextStartSeq,
          'server_next_start_message_seq': serverNextStartSeq,
          'pull_mode': pullMode,
          'unread_only': unreadOnly,
          'unread_limit': unreadOnly ? effectiveUnreadLimit : 0,
          'first_raw_message': _rawHistoryMessageLogSummary(
            pageMessages.isEmpty
                ? const <String, Object?>{}
                : pageMessages.first,
          ),
          'last_raw_message': _rawHistoryMessageLogSummary(
            pageMessages.isEmpty
                ? const <String, Object?>{}
                : pageMessages.last,
          ),
        },
      );
      if (unreadOnly || !more) {
        complete = true;
        break;
      }
      if (all.length >= maxMessages) {
        break;
      }
      if (page > 1 && added == 0 && pageMessages.isNotEmpty) {
        AppLogger.warn(
          'im',
          'server history pagination stopped',
          data: {
            'channel_id': channelID,
            'channel_type': channelType,
            'reason': 'no_new_messages',
            'page': page,
            'raw_count': pageMessages.length,
            'start_message_seq': startMessageSeq,
            'next_start_message_seq': nextStartSeq,
            'server_next_start_message_seq': serverNextStartSeq,
          },
        );
        break;
      }
      if (nextStartSeq <= 0 ||
          (pullMode == 1 && nextStartSeq >= startMessageSeq)) {
        AppLogger.warn(
          'im',
          'server history pagination stopped',
          data: {
            'channel_id': channelID,
            'channel_type': channelType,
            'reason': 'missing_next_start_message_seq',
            'page': page,
            'start_message_seq': startMessageSeq,
            'next_start_message_seq': nextStartSeq,
            'min_message_seq': minMessageSeq,
            'server_next_start_message_seq': serverNextStartSeq,
          },
        );
        break;
      }
      startMessageSeq = nextStartSeq;
      pullMode = 1;
    }
    return _ServerHistoryLoadResult(messages: all, complete: complete);
  }

  List<Map<String, Object?>> _historyPageMessages(
    Map<String, Object?> pageData,
  ) {
    for (final key in ['list', 'items', 'rows', 'records']) {
      final value = pageData[key];
      if (value is List) {
        return value
            .whereType<Map>()
            .map((item) => item.cast<String, Object?>())
            .toList(growable: false);
      }
    }
    final nested = pageData['data'];
    if (nested is Map) {
      return _historyPageMessages(nested.cast<String, Object?>());
    }
    if (nested is List) {
      return nested
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList(growable: false);
    }
    return const <Map<String, Object?>>[];
  }

  String _historyRawIdentity(Map<String, Object?> raw) {
    final message = _asMap(raw['message']).isEmpty
        ? raw
        : _asMap(raw['message']);
    final clientMsgNo = _value(message, [
      'client_msg_no',
    ], fallback: _value(raw, ['client_msg_no']));
    if (clientMsgNo.isNotEmpty) {
      return 'client:$clientMsgNo';
    }
    final seq = _intValue(message, [
      'message_seq',
    ], fallback: _intValue(raw, ['message_seq']));
    if (seq > 0) {
      return 'seq:$seq';
    }
    final messageId = _value(message, [
      'message_id',
      'message_idstr',
      'id',
    ], fallback: _value(raw, ['message_id', 'message_idstr', 'id']));
    return messageId.isEmpty ? '' : 'id:$messageId';
  }

  int _minRawHistoryMessageSeq(List<Map<String, Object?>> rawMessages) {
    var minSeq = 0;
    for (final raw in rawMessages) {
      final message = _asMap(raw['message']).isEmpty
          ? raw
          : _asMap(raw['message']);
      final seq = _intValue(message, [
        'message_seq',
      ], fallback: _intValue(raw, ['message_seq']));
      if (seq <= 0) {
        continue;
      }
      minSeq = minSeq == 0 ? seq : min(minSeq, seq);
    }
    return minSeq;
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

  int _conversationUnreadCount(Map<String, Object?> item) {
    return _intValue(item, ['unread_quantity', 'unread', 'unread_count']);
  }

  bool _shouldAcceptServerConversation(
    Map<String, Object?> item,
    ChatSession chat,
  ) {
    final channelType = _intValue(item, ['channel_type']);
    if (_historySyncEnabledForType(channelType, chat)) {
      return true;
    }
    return _conversationUnreadCount(item) > 0;
  }

  bool _isChannelHistorySynced(String channelId, int channelType) {
    final chat = _session?.chat;
    if (chat == null) {
      return false;
    }
    channelId = _canonicalChannelId(channelId, channelType);
    final key = _messageKey(channelId, channelType);
    if (_historySyncedChannels.contains(key)) {
      return true;
    }
    if (!_historySyncEnabledForType(channelType, chat)) {
      return false;
    }
    final persisted = _cache.isChannelHistorySynced(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
    );
    if (persisted) {
      _historySyncedChannels.add(key);
    }
    return persisted;
  }

  void _markChannelHistorySynced(
    String channelId,
    int channelType, {
    bool persist = true,
  }) {
    final chat = _session?.chat;
    if (chat == null) {
      return;
    }
    channelId = _canonicalChannelId(channelId, channelType);
    final key = _messageKey(channelId, channelType);
    _historySyncedChannels.add(key);
    if (persist && _historySyncEnabledForType(channelType, chat)) {
      _cache.writeChannelHistorySynced(
        uid: chat.uid,
        channelId: channelId,
        channelType: channelType,
      );
    }
  }

  void _forgetChannelHistorySynced(String channelId, int channelType) {
    final chat = _session?.chat;
    if (chat == null) {
      return;
    }
    channelId = _canonicalChannelId(channelId, channelType);
    final key = _messageKey(channelId, channelType);
    _historySyncedChannels.remove(key);
    _historyRetryAfter.remove(key);
    _syncingChannels.remove(key);
    _cache.removeChannelHistorySynced(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
    );
  }

  List<Map<String, Object?>> _currentLocalConversations(ChatSession chat) {
    return _sortConversations(
      _cache
          .readConversations(chat.uid)
          .map(_normalizeConversation)
          .where(_conversationVisibleAfterClear)
          .toList(growable: false),
    );
  }

  Future<List<Map<String, Object?>>> _hydrateEmptyConversationsFromHistory(
    List<Map<String, Object?>> conversations, {
    void Function(int completed, int total)? onProgress,
  }) async {
    final hydrated = <Map<String, Object?>>[];
    final total = conversations.length;
    if (total == 0) {
      onProgress?.call(0, 0);
      return hydrated;
    }
    var completed = 0;
    for (final item in conversations) {
      try {
        final channelId = _value(item, ['channel_id']);
        final channelType = _intValue(item, ['channel_type']);
        final shouldHydrateHistory = onProgress != null;
        final historyEnabled = _historySyncEnabledForType(
          channelType,
          _requireChat(),
        );
        final unreadCount = _conversationUnreadCount(item);
        final unreadOnly = !historyEnabled && unreadCount > 0;
        final hasSummary =
            _value(item, ['content']).isNotEmpty &&
            _value(item, ['content_type']).isNotEmpty &&
            _value(item, ['msg_time', 'timestamp', 'create_time']).isNotEmpty;
        if ((!shouldHydrateHistory && hasSummary && !unreadOnly) ||
            (!historyEnabled && !unreadOnly)) {
          hydrated.add(item);
          continue;
        }
        final messages = await syncChannelMessages(
          channelID: channelId,
          channelType: channelType,
          groupId: _value(item, ['group_id', 'id'], fallback: channelId),
          limit: unreadOnly
              ? min(max(unreadCount, 1), _historySyncLimit)
              : _historySyncLimit,
          unreadOnly: unreadOnly,
          unreadLimit: unreadCount,
        );
        final lastMessage = _lastConversationMessage(messages);
        if (lastMessage.isEmpty) {
          if (hasSummary) {
            AppLogger.warn(
              'im',
              'conversation history hydration kept server summary',
              data: {
                'channel_id': channelId,
                'channel_type': channelType,
                'reason': 'empty_history_with_summary',
              },
            );
            hydrated.add(item);
            continue;
          }
          AppLogger.info(
            'im',
            'empty conversation dropped after history hydration',
            data: {
              'channel_id': channelId,
              'channel_type': channelType,
              'reason': 'no_displayable_history_message',
            },
          );
          continue;
        }
        hydrated.add(_conversationSummaryFromMessage(item, lastMessage));
      } finally {
        completed++;
        onProgress?.call(completed, total);
      }
    }
    return hydrated;
  }

  Map<String, Object?> _conversationSummaryFromMessage(
    Map<String, Object?> conversation,
    Map<String, Object?> message,
  ) {
    final payload = _asMap(message['payload']);
    final channelType = _intValue(conversation, ['channel_type']);
    final channelId = _value(conversation, ['channel_id']);
    return _hydrateConversationProfile(<String, Object?>{
      ...conversation,
      'conversation_type': channelType == _requireChat().channelTypeGroup
          ? 'group'
          : 'private',
      'channel_id': channelId,
      'channel_type': channelType,
      'content': _messageConversationContent(message, payload),
      'content_type': _value(message, ['content_type']),
      'payload': payload,
      'msg_time': _value(message, ['timestamp', 'create_time', 'msg_time']),
      'last_client_msg_no': _value(message, ['client_msg_no']),
      'last_msg_seq': _intValue(message, ['message_seq']),
    });
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
        merged[index] = _mergeConversationFields(merged[index], normalized);
      } else {
        merged.add(Map<String, Object?>.from(normalized));
      }
    }
    return _sortConversations(_dedupeConversations(merged));
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
      byChannel[key] = current == null
          ? item
          : _mergeConversationFields(current, item);
    }
    return _sortConversations(byChannel.values.toList(growable: false));
  }

  List<Map<String, Object?>> _sortConversations(
    List<Map<String, Object?>> conversations,
  ) {
    final chat = _session?.chat;
    final pinnedKeys = chat == null
        ? const <String>{}
        : _cache.readPinnedConversationKeys(chat.uid);
    final list = conversations
        .map((raw) {
          final item = Map<String, Object?>.from(_normalizeConversation(raw));
          final channelId = _value(item, ['channel_id']);
          final channelType = _intValue(item, ['channel_type']);
          final pinned = pinnedKeys.contains(
            _messageKey(channelId, channelType),
          );
          item['is_pinned'] = pinned;
          return item;
        })
        .where(_conversationVisibleAfterClear)
        .toList(growable: false);
    list.sort((a, b) {
      final pinnedCompare =
          (_boolValue(b['is_pinned']) ? 1 : 0) -
          (_boolValue(a['is_pinned']) ? 1 : 0);
      if (pinnedCompare != 0) {
        return pinnedCompare;
      }
      return _objectTimestampMs(b, [
        'msg_time',
        'create_time',
        'timestamp',
      ]).compareTo(
        _objectTimestampMs(a, ['msg_time', 'create_time', 'timestamp']),
      );
    });
    return list;
  }

  Map<String, Object?> _mergeConversationFields(
    Map<String, Object?> current,
    Map<String, Object?> incoming,
  ) {
    final currentTime = _objectTimestampMs(current, [
      'msg_time',
      'timestamp',
      'create_time',
    ]);
    final incomingTime = _objectTimestampMs(incoming, [
      'msg_time',
      'timestamp',
      'create_time',
    ]);
    final incomingIsNewer = incomingTime > currentTime;
    final base = incomingIsNewer ? current : incoming;
    final overlay = incomingIsNewer ? incoming : current;
    final merged = _mergeNonEmpty(base, overlay);
    final preferredUnread = _intValue(overlay, ['unread_quantity', 'unread']);
    final alternateUnread = _intValue(base, ['unread_quantity', 'unread']);
    merged['unread_quantity'] =
        currentTime == incomingTime &&
            (preferredUnread == 0 || alternateUnread == 0)
        ? 0
        : preferredUnread;
    return merged;
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

  Map<String, Object?> _rememberConversationProfile(Map<String, Object?> item) {
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
    _cache.writeProfile(uid: chat.uid, userId: receiverId, profile: item);
    return item;
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
    Map<String, Object?> quote = const {},
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
        if (replyClientMsgNo.isNotEmpty)
          'quote_client_msg_no': replyClientMsgNo,
        if (quote.isNotEmpty) 'quote': quote,
        if (quote.isNotEmpty) 'quote_json': jsonEncode(quote),
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
    final normalizedPayload = _normalizeOutgoingPayload(contentType, payload);
    final senderPayload = <String, Object?>{
      'sender_id': session.userId.toString(),
      'sender_uid': chat.uid,
      ...normalizedPayload,
    };
    final serverPayload = Map<String, Object?>.from(senderPayload)
      ..remove('file_path');
    final cleanPayload = _cleanPayload({
      ...serverPayload,
      'protocol': 'blin.chat.v1',
      'content_type': contentType,
      'client_msg_no': clientMsgNo,
    });
    final localPayload = _cleanPayload({
      ...senderPayload,
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
      if (_isDisplayableChatPayload(
        _asMap(confirmed['payload']),
        contentType: contentType,
      )) {
        final existing = _readMessagesForChannel(channelID, channelType)
            .where(
              (item) => _sameMessageIdentity(
                item,
                clientMsgNo,
                _intValue(confirmed, ['message_seq']),
              ),
            )
            .firstOrNull;
        final alreadyConfirmed =
            existing != null &&
            _value(existing, ['message_id']) ==
                _value(confirmed, ['message_id']) &&
            _intValue(existing, ['message_seq']) ==
                _intValue(confirmed, ['message_seq']) &&
            _value(existing, ['status']) == _value(confirmed, ['status']);
        _upsertMessage(channelID, channelType, confirmed);
        _upsertConversationFromMessage(confirmed);
        if (!alreadyConfirmed) {
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
        }
      }
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
    return contentType == 'cmd' ||
        contentType == ChatContentTypes.redPacket ||
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
            contentType != ChatContentTypes.gif &&
            contentType != ChatContentTypes.sticker &&
            contentType != ChatContentTypes.emoji &&
            contentType != ChatContentTypes.voice &&
            contentType != ChatContentTypes.file &&
            contentType != ChatContentTypes.video)) {
      return null;
    }
    var lastProgress = -1.0;
    return (progress) {
      final normalized = progress.clamp(0, 1).toDouble();
      if (normalized < 1 && (normalized - lastProgress).abs() < 0.1) {
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
    final payload = _normalizeOutgoingPayload(
      contentType,
      _cleanPayload({
        ..._asMap(failedMessage['payload']),
        'client_msg_no': clientMsgNo,
        if (contentType.isNotEmpty) 'content_type': contentType,
      }),
    );
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
    if (_manualStop ||
        _connecting ||
        !_networkAvailable ||
        (!_foreground && !_backgroundKeepAliveEnabled)) {
      return;
    }
    final operationEpoch = ++_connectOperationEpoch;
    _connecting = true;
    _gatewayConnectCancelToken?.cancel('superseded connection request');
    final connectCancelToken = CancelToken();
    _gatewayConnectCancelToken = connectCancelToken;
    _realtimeValidated = false;
    _realtimeValidatedAt = null;
    _connectionStableTimer?.cancel();
    _connectionStableTimer = null;
    _setStatus(_reconnectAttempt > 0 ? '重连中' : '连接中');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeRealtimeOnly();
    try {
      final chat = await _gatewayChatForConnect(
        cancelToken: connectCancelToken,
      );
      final stream = chat.stream;
      final openUrl = _gatewayOpenUrl(chat);
      if (stream == null || stream.ticket.isEmpty || openUrl.isEmpty) {
        throw ApiException('Gateway 实时连接材料缺失');
      }
      _consumeGatewayOpenTicket();
      final uri = Uri.parse(openUrl);
      final client = GatewayStreamClient();
      final epoch = ++_gatewayEpoch;
      final lastCursor = _initialGatewayCursor(chat, stream);
      final connectStartedAtSeconds =
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      _presenceRealtimeAfterSeconds = connectStartedAtSeconds - 3;
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
      final recoveryReason = _hasRealtimeConnectedOnce || _reconnectAttempt > 0
          ? 'reconnect'
          : 'initial_connect';
      AppLogger.info(
        'im',
        'gateway stream connect start',
        data: {
          'addr': openUrl,
          'cursor_len': lastCursor.length,
          'foreground': _foreground,
          'background_keep_alive_enabled': _backgroundKeepAliveEnabled,
        },
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
          if (!frame.isKick && !frame.isError && !_realtimeValidated) {
            _markRealtimeValidated(
              epoch: epoch,
              recoveryReason: recoveryReason,
              cursor: lastCursor,
              openUrl: openUrl,
            );
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
      if (operationEpoch != _connectOperationEpoch) {
        await client.close().catchError((Object _) => null);
        return;
      }
      if (_manualStop || (!_foreground && !_backgroundKeepAliveEnabled)) {
        await client.close().catchError((Object _) => null);
        _connecting = false;
        if (!_foreground && !_backgroundKeepAliveEnabled) {
          _setStatus('未连接');
        }
        return;
      }
      AppLogger.info(
        'im',
        'gateway stream opened, awaiting validated frame',
        data: {
          'addr': openUrl,
          'cursor_len': lastCursor.length,
          'foreground': _foreground,
          'background_keep_alive_enabled': _backgroundKeepAliveEnabled,
        },
      );
    } catch (error, stackTrace) {
      if (operationEpoch != _connectOperationEpoch ||
          (error is DioException && CancelToken.isCancel(error))) {
        return;
      }
      _connecting = false;
      await _closeRealtimeOnly();
      AppLogger.error(
        'im',
        'gateway stream connect failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (error is ApiException && (error.code == 401 || error.code == 403)) {
        _lastError = null;
        _markRealtimeAuthInvalid(error, 'connect_failed');
        return;
      }
      if (error is GatewayStreamException &&
          (error.statusCode == 401 || error.statusCode == 403)) {
        _invalidateGatewayTransportTicket();
        _lastError = '实时连接票据已更新';
        _setStatus('重连中');
        _scheduleReconnect('gateway_open_ticket_rejected', immediate: true);
        return;
      }
      _lastError = error.toString();
      _setStatus('连接失败');
      _scheduleReconnect('connect_failed');
    }
  }

  void _markRealtimeValidated({
    required int epoch,
    required String recoveryReason,
    required String cursor,
    required String openUrl,
  }) {
    if (epoch != _gatewayEpoch || _realtimeValidated) {
      return;
    }
    _connecting = false;
    _realtimeValidated = true;
    _realtimeValidatedAt = DateTime.now();
    _lastError = null;
    _hasRealtimeConnectedOnce = true;
    _suppressCatchupSoundOnNextConnect = false;
    _setStatus('已连接');
    _connectionStableTimer?.cancel();
    _connectionStableTimer = Timer(const Duration(seconds: 30), () {
      if (epoch != _gatewayEpoch ||
          !_realtimeValidated ||
          !(_gatewayStream?.isHealthy() ?? false)) {
        return;
      }
      _reconnectAttempt = 0;
      AppLogger.info(
        'im',
        'gateway connection reached stable state',
        data: {
          'epoch': epoch,
          'validated_at': _realtimeValidatedAt?.toIso8601String() ?? '',
        },
      );
    });
    unawaited(
      _recoverOfflineMessagesAfterRealtimeConnected(
        reason: recoveryReason,
        cursor: cursor,
      ),
    );
    AppLogger.info(
      'im',
      'gateway stream validated',
      data: {
        'addr': openUrl,
        'cursor_len': cursor.length,
        'foreground': _foreground,
        'background_keep_alive_enabled': _backgroundKeepAliveEnabled,
      },
    );
  }

  void _invalidateGatewayTransportTicket() {
    _gatewayTicket = '';
    _gatewayAckUrl = '';
    _gatewayTicketExpiresAt = null;
    _gatewayChatIssuedAt = null;
    _gatewayOpenTicketAvailable = false;
  }

  Future<void> _recoverOfflineMessagesAfterRealtimeConnected({
    required String reason,
    required String cursor,
  }) async {
    final session = _session;
    final chat = session?.chat;
    if (session == null || chat == null) {
      return;
    }
    final startedAt = DateTime.now();
    AppLogger.info(
      'im',
      'offline sync start',
      data: {
        'reason': reason,
        'cursor_len': cursor.length,
        'conversation_count': _latestConversations.length,
        'private_history_sync_enabled': chat.privateHistorySyncEnabled,
        'group_history_sync_enabled': chat.groupHistorySyncEnabled,
      },
    );
    try {
      final conversations = await syncConversationsFromServer();
      var syncedChannels = 0;
      for (final conversation in conversations.take(30)) {
        final channelType = _intValue(conversation, ['channel_type']);
        final unreadCount = _conversationUnreadCount(conversation);
        final historyEnabled = _historySyncEnabledForType(channelType, chat);
        if (!historyEnabled && unreadCount <= 0) {
          continue;
        }
        final channelId = _value(conversation, ['channel_id']);
        if (channelId.isEmpty || channelType <= 0) {
          continue;
        }
        await syncChannelMessages(
          channelID: channelId,
          channelType: channelType,
          groupId: _value(conversation, ['group_id', 'id']),
          limit: historyEnabled
              ? _historySyncLimit
              : min(max(unreadCount, 1), _historySyncLimit),
          unreadOnly: !historyEnabled,
          unreadLimit: unreadCount,
        );
        syncedChannels++;
      }
      AppLogger.info(
        'im',
        'offline sync done',
        data: {
          'reason': reason,
          'conversation_count': conversations.length,
          'synced_channel_count': syncedChannels,
          'ms': DateTime.now().difference(startedAt).inMilliseconds,
        },
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'im',
        'offline sync failed',
        data: {
          'reason': reason,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    }
  }

  Future<ChatSession> _refreshGatewayChat({
    required bool forOpen,
    CancelToken? cancelToken,
  }) async {
    final session = _requireSession();
    final chat = await _api.connectIm(
      session: session,
      device: _device,
      cancelToken: cancelToken,
    );
    _session = session.copyWith(chat: chat);
    _gatewayChatIssuedAt = forOpen ? DateTime.now() : null;
    _gatewayOpenTicketAvailable = forOpen;
    return chat;
  }

  Future<ChatSession> _gatewayChatForConnect({CancelToken? cancelToken}) async {
    final cached = _validCachedGatewayChat();
    if (cached != null) {
      AppLogger.info(
        'im',
        'reuse fresh gateway chat for connect',
        data: {
          'uid': cached.uid,
          'expire_in': cached.stream?.expireIn ?? 0,
          'issued_at': _gatewayChatIssuedAt?.toIso8601String() ?? '',
        },
      );
      return cached;
    }
    return _refreshGatewayChat(forOpen: true, cancelToken: cancelToken);
  }

  void _consumeGatewayOpenTicket() {
    _gatewayOpenTicketAvailable = false;
    _gatewayChatIssuedAt = null;
  }

  ChatSession? _validCachedGatewayChat() {
    final chat = _session?.chat;
    final stream = chat?.stream;
    final issuedAt = _gatewayChatIssuedAt;
    if (chat == null ||
        stream == null ||
        !stream.isAvailable ||
        _gatewayOpenUrl(chat).isEmpty ||
        issuedAt == null ||
        !_gatewayOpenTicketAvailable) {
      return null;
    }
    final expiresAt = issuedAt.add(Duration(seconds: max(30, stream.expireIn)));
    if (!expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 15)))) {
      return null;
    }
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
    return '';
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
      final reason = frame.reason.trim();
      if (reason == 'device_replaced' || reason == 'session_revoked') {
        _authInvalid = true;
        _gatewayConnectCancelToken?.cancel('authentication invalid');
        _gatewayConnectCancelToken = null;
        _started = false;
        _manualStop = true;
        _connecting = false;
        _sessionRevocationMessage = reason == 'device_replaced'
            ? '账号已在另一台同平台设备登录'
            : '登录状态已失效';
        _lastError = _sessionRevocationMessage;
        _reconnectTimer?.cancel();
        _networkReconnectTimer?.cancel();
        _setStatus('未登录');
        unawaited(_closeRealtimeOnly());
        AppLogger.warn(
          'im',
          'terminal gateway kick received',
          data: {'reason': reason},
        );
        return;
      }
      _lastError = reason.isEmpty ? 'Gateway 已断开' : reason;
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
    if (_isGatewayCallFrame(frame)) {
      _handleGatewayCall(frame);
      return;
    }
    if (!frame.isMessage) {
      AppLogger.info('im', 'gateway frame ignored', data: {'type': frame.type});
      return;
    }
    _handleGatewayMessage(frame);
  }

  bool _isGatewayCallFrame(GatewayFrame frame) {
    final payload = frame.payload;
    final event = payload['event']?.toString().toLowerCase() ?? '';
    return frame.type.toLowerCase() == 'call' ||
        payload['type']?.toString().toLowerCase() == 'call' ||
        event.startsWith('call.');
  }

  void _handleGatewayCall(GatewayFrame frame) {
    try {
      final event = LiveKitCallEvent.fromGatewayPayload(frame.payload);
      AppLogger.info(
        'im',
        'gateway call event received',
        data: {
          'event': event.event,
          'call_id': event.call.callId,
          'call_type': event.call.callType,
          'media_type': event.call.mediaType,
          'operator_id': event.operatorId,
        },
      );
      if (!_callEvents.isClosed) {
        _callEvents.add(BusinessImCallEvent(source: 'gateway', event: event));
      }
    } catch (error, stackTrace) {
      AppLogger.error(
        'im',
        'gateway call event parse failed',
        error: error,
        stackTrace: stackTrace,
        data: {'payload': frame.payload},
      );
    } finally {
      unawaited(_ackGatewayFrame(frame));
    }
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
    var applied = 0;
    for (final event in events) {
      if (!_shouldApplyPresenceEvent(event)) {
        continue;
      }
      if (!_presenceEvents.isClosed) {
        _presenceEvents.add(event);
      }
      applied++;
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
    if (applied > 0) {
      notifyListeners();
    } else {
      AppLogger.info(
        'im',
        'gateway presence frame skipped',
        data: {
          'reason': 'stale_or_replayed',
          'event_count': events.length,
          'presence_realtime_after': _presenceRealtimeAfterSeconds,
        },
      );
    }
    unawaited(_ackGatewayFrame(frame));
  }

  bool _shouldApplyPresenceEvent(BusinessImPresenceEvent event) {
    final eventSeconds = _timestampSeconds(event.eventTime);
    final key = event.userId.isNotEmpty ? event.userId : event.uid;
    if (key.isEmpty) {
      return false;
    }
    final previous = _presenceLatestEventSeconds[key] ?? 0;
    if (eventSeconds > 0 && previous > 0 && eventSeconds < previous) {
      AppLogger.info(
        'im',
        'gateway presence ignored',
        data: {
          'reason': 'older_than_applied',
          'uid': event.uid,
          'user_id': event.userId,
          'online': event.online,
          'event_time': event.eventTime,
          'latest_event_time': previous,
        },
      );
      return false;
    }
    if (eventSeconds > 0) {
      _presenceLatestEventSeconds[key] = eventSeconds;
    }
    return true;
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
      await Future<void>.delayed(const Duration(milliseconds: 80));
      while (_gatewayAckQueue.isNotEmpty) {
        final batch = <GatewayFrame>[];
        while (_gatewayAckQueue.isNotEmpty && batch.length < 100) {
          batch.add(_gatewayAckQueue.removeFirst());
        }
        final success = await _ackGatewayFramesOnce(batch);
        if (!success) {
          _handleRealtimeClosed('gateway_ack_failed', 'Gateway ACK 失败');
          return;
        }
      }
    } finally {
      _gatewayAckDraining = false;
    }
  }

  Future<bool> _ackGatewayFramesOnce(List<GatewayFrame> frames) async {
    if (frames.isEmpty) {
      return true;
    }
    final chat = _requireChat();
    final frame = frames.last;
    final clientMsgNos = <String>{
      for (final item in frames)
        if (item.clientMsgNo.isNotEmpty) item.clientMsgNo,
    }.toList(growable: false);
    try {
      var ticket = await _ensureGatewayAckTicket();
      try {
        await _api.ackGatewayCursor(
          ackUrl: _gatewayAckUrl,
          ticket: ticket,
          lastCursor: frame.cursor,
          clientMsgNos: clientMsgNos,
        );
      } on ApiException catch (error) {
        if (error.code != 401 && error.code != 403) {
          rethrow;
        }
        AppLogger.warn(
          'im',
          'gateway ack ticket rejected, refreshing transport ticket',
          data: {'code': error.code, 'frame_count': frames.length},
        );
        try {
          ticket = await _ensureGatewayAckTicket(force: true);
        } on ApiException catch (refreshError) {
          if (refreshError.code == 401 || refreshError.code == 403) {
            _markRealtimeAuthInvalid(
              refreshError,
              'gateway_ack_ticket_refresh',
            );
          }
          rethrow;
        }
        await _api.ackGatewayCursor(
          ackUrl: _gatewayAckUrl,
          ticket: ticket,
          lastCursor: frame.cursor,
          clientMsgNos: clientMsgNos,
        );
      }
      _cache.writeGatewayCursor(
        uid: chat.uid,
        device: _device,
        cursor: frame.cursor,
      );
      if (frames.length > 1) {
        AppLogger.info(
          'im',
          'gateway ack batch committed',
          data: {
            'frame_count': frames.length,
            'client_msg_no_count': clientMsgNos.length,
            'cursor_len': frame.cursor.length,
          },
        );
      }
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

  void _markRealtimeAuthInvalid(ApiException error, String source) {
    _authInvalid = true;
    _started = false;
    _manualStop = true;
    _connecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _gatewayAckQueue.clear();
    _gatewayAckDraining = false;
    _lastError = null;
    _setStatus('未登录');
    unawaited(_closeRealtimeOnly());
    AppLogger.warn(
      'im',
      'gateway auth invalid, stop realtime reconnect',
      data: {'source': source, 'code': error.code, 'message': error.message},
    );
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
    final chat = await _refreshGatewayChat(forOpen: false);
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
    _connecting = false;
    _realtimeValidated = false;
    _realtimeValidatedAt = null;
    _connectionStableTimer?.cancel();
    _connectionStableTimer = null;
    if (_manualStop) {
      return;
    }
    if (!_foreground && !_backgroundKeepAliveEnabled) {
      unawaited(_closeRealtimeOnly());
      _setStatus('未连接');
      AppLogger.info(
        'im',
        'gateway stream closed while backgrounded',
        data: {'source': source, 'reason': reason ?? ''},
      );
      return;
    }
    unawaited(_closeRealtimeOnly());
    _lastError = reason?.isEmpty == false ? reason : _lastError;
    _setStatus('重连中');
    _scheduleReconnect(source);
  }

  void _scheduleReconnect(String source, {bool immediate = false}) {
    if (!_started ||
        _manualStop ||
        _authInvalid ||
        (!_foreground && !_backgroundKeepAliveEnabled)) {
      AppLogger.info(
        'im',
        'skip gateway reconnect',
        data: {
          'source': source,
          'foreground': _foreground,
          'background_keep_alive_enabled': _backgroundKeepAliveEnabled,
          'auth_invalid': _authInvalid,
          'started': _started,
          'manual_stop': _manualStop,
        },
      );
      return;
    }
    _reconnectTimer?.cancel();
    final exponent = min(_reconnectAttempt, 6);
    final baseMs = immediate ? 250 : min<int>(60000, 1000 * (1 << exponent));
    final jitterMs = immediate
        ? _random.nextInt(150)
        : _random.nextInt(max(1, (baseMs * 0.3).round()));
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
    _realtimeValidated = false;
    _realtimeValidatedAt = null;
    _gatewayEpoch++;
    await gatewayStream?.close().catchError((Object _) => null);
  }

  Map<String, Object?> _normalizeConversation(Map<String, Object?> item) {
    final rawPayload = _asMap(item['payload']);
    final resolvedType = _conversationChannelType(item, rawPayload);
    final type = resolvedType == _requireChat().channelTypeGroup
        ? 'group'
        : 'private';
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
    final contentType = _historyContentType(item, rawPayload);
    final rawContent = _value(item, [
      'content',
    ], fallback: _payloadContent(rawPayload));
    final payload = _ensureBusinessPayload(
      rawPayload,
      contentType: contentType,
      content: rawContent,
      clientMsgNo: _value(item, ['last_client_msg_no', 'client_msg_no']),
    );
    final actionNotice =
        contentType == ChatContentTypes.redPacketReceived ||
        contentType == ChatContentTypes.transferReceived;
    final displayable =
        !actionNotice &&
        _isDisplayableChatPayload(payload, contentType: contentType);
    final content = switch (contentType) {
      ChatContentTypes.redPacketReceived => _paymentReceiptContent(
        payload,
        action: ChatContentTypes.redPacketReceived,
      ),
      ChatContentTypes.transferReceived => _paymentReceiptContent(
        payload,
        action: ChatContentTypes.transferReceived,
      ),
      ChatContentTypes.call => _callContent(payload),
      ChatContentTypes.walletNotice => _walletNoticeConversationText(payload),
      _ => rawContent,
    };
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
    final contentType = _historyContentType(message, rawPayload);
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
      ChatContentTypes.redPacketReceived => _paymentReceiptContent(
        payload,
        action: ChatContentTypes.redPacketReceived,
      ),
      ChatContentTypes.transferReceived => _paymentReceiptContent(
        payload,
        action: ChatContentTypes.transferReceived,
      ),
      ChatContentTypes.call => _callContent(payload),
      ChatContentTypes.walletNotice => _walletNoticeConversationText(payload),
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
      if (channelType == _requireChat().channelTypePerson)
        'receiver_id': _receiverIdFromChannel(canonicalChannelId),
      'channel_type': channelType,
      'from_uid': fromUid,
      'is_me': _isCurrentUserMessage(senderId: senderId, senderUid: fromUid),
      'content': normalizedContent,
      'content_type': contentType,
      if (_contentTypeCode(contentType) > 0)
        'type': _contentTypeCode(contentType),
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

  List<Map<String, Object?>> _normalizeServerHistoryMessages({
    required List<Map<String, Object?>> rawMessages,
    required String channelId,
    required int channelType,
  }) {
    final normalizedMessages = <Map<String, Object?>>[];
    final dropped = <String, int>{};
    void drop(String reason) {
      dropped[reason] = (dropped[reason] ?? 0) + 1;
    }

    for (final raw in rawMessages) {
      final normalized = _normalizeHistoryMessage(
        raw,
        channelId: channelId,
        channelType: channelType,
      );
      if (normalized.isEmpty) {
        drop(_historyRawDropReason(raw));
        continue;
      }
      if (!_messageNotDeleted(normalized)) {
        drop('deleted_by_user');
        continue;
      }
      normalizedMessages.add(normalized);
    }

    final boundMessages = _bindPaymentActionMessagesToTargets(
      channelId,
      channelType,
      normalizedMessages,
    );
    final unboundPaymentActions =
        normalizedMessages.length - boundMessages.length;
    if (unboundPaymentActions > 0) {
      dropped['unbound_payment_action'] =
          (dropped['unbound_payment_action'] ?? 0) + unboundPaymentActions;
    }
    AppLogger.info(
      'im',
      'server history normalized',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'server_raw_count': rawMessages.length,
        'normalized_count': normalizedMessages.length,
        'accepted_count': boundMessages.length,
        'dropped': dropped,
      },
    );
    return boundMessages;
  }

  List<Map<String, Object?>> _applyAuthoritativeServerWindow({
    required List<Map<String, Object?>> current,
    required List<Map<String, Object?>> serverMessages,
    required int serverRawCount,
    required bool serverWindowComplete,
    required String channelId,
    required int channelType,
  }) {
    final chat = _requireChat();
    if (!serverWindowComplete) {
      AppLogger.info(
        'im',
        'local history prune skipped for incomplete server window',
        data: {
          'channel_id': channelId,
          'channel_type': channelType,
          'server_raw_count': serverRawCount,
          'server_accepted_count': serverMessages.length,
          'local_count': current.length,
        },
      );
      return current;
    }
    if (serverRawCount == 0) {
      if (current.isNotEmpty) {
        AppLogger.info(
          'im',
          'local history cleared by empty server window',
          data: {
            'channel_id': channelId,
            'channel_type': channelType,
            'removed_count': current.length,
          },
        );
      }
      return const <Map<String, Object?>>[];
    }
    if (serverMessages.isEmpty) {
      return current;
    }
    final serverClientMsgNos = <String>{};
    final serverMessageIds = <String>{};
    final serverPaymentActionKeys = <String>{};
    final serverSeqs = <int>{};
    var minSeq = 0;
    var minTimestamp = 0;
    for (final message in serverMessages) {
      final clientMsgNo = _value(message, ['client_msg_no']);
      if (clientMsgNo.isNotEmpty) {
        serverClientMsgNos.add(clientMsgNo);
      }
      final messageId = _value(message, ['message_id', 'message_idstr']);
      if (messageId.isNotEmpty) {
        serverMessageIds.add(messageId);
      }
      serverPaymentActionKeys.addAll(_paymentActionMessageKeys(message));
      final seq = _intValue(message, ['message_seq']);
      if (seq > 0) {
        serverSeqs.add(seq);
        minSeq = minSeq == 0 ? seq : min(minSeq, seq);
      }
      final timestamp = _objectTimestampMs(message, [
        'timestamp',
        'create_time',
        'msg_time',
      ]);
      if (timestamp > 0) {
        minTimestamp = minTimestamp == 0
            ? timestamp
            : min(minTimestamp, timestamp);
      }
    }
    var removed = 0;
    final filtered = <Map<String, Object?>>[];
    for (final message in current) {
      if (_isLocalOnlyPendingMessage(message)) {
        filtered.add(message);
        continue;
      }
      final clientMsgNo = _value(message, ['client_msg_no']);
      final messageId = _value(message, ['message_id', 'message_idstr']);
      final actionKeys = _paymentActionMessageKeys(message);
      final seq = _intValue(message, ['message_seq']);
      final knownByServer =
          (clientMsgNo.isNotEmpty &&
              serverClientMsgNos.contains(clientMsgNo)) ||
          (messageId.isNotEmpty && serverMessageIds.contains(messageId)) ||
          actionKeys.any(serverPaymentActionKeys.contains) ||
          (seq > 0 && serverSeqs.contains(seq));
      if (knownByServer) {
        filtered.add(message);
        continue;
      }
      final insideServerWindow = _insideServerHistoryWindow(
        message,
        minSeq: minSeq,
        minTimestamp: minTimestamp,
      );
      if (insideServerWindow) {
        if (_serverWindowPruneLocalOnly(message)) {
          filtered.add(message);
          continue;
        }
        removed++;
        if (clientMsgNo.isNotEmpty) {
          _cache.rememberDeletedMessage(
            uid: chat.uid,
            channelId: channelId,
            channelType: channelType,
            clientMsgNo: clientMsgNo,
          );
        }
        continue;
      }
      filtered.add(message);
    }
    if (removed > 0) {
      AppLogger.info(
        'im',
        'local history pruned by server window',
        data: {
          'channel_id': channelId,
          'channel_type': channelType,
          'server_count': serverMessages.length,
          'removed_count': removed,
        },
      );
    }
    return filtered;
  }

  bool _serverWindowPruneLocalOnly(Map<String, Object?> message) {
    return _isSystemActionMessage(message) ||
        _paymentActionMessageKeys(message).isNotEmpty ||
        _isLocalOnlyPendingMessage(message);
  }

  bool _isLocalOnlyPendingMessage(Map<String, Object?> message) {
    if (_intValue(message, ['message_seq']) > 0 ||
        _value(message, ['message_id']).isNotEmpty) {
      return false;
    }
    final status = _value(message, ['status']).toLowerCase();
    return status == 'sending' || status == 'queued' || status == 'failed';
  }

  bool _insideServerHistoryWindow(
    Map<String, Object?> message, {
    required int minSeq,
    required int minTimestamp,
  }) {
    final seq = _intValue(message, ['message_seq']);
    if (seq > 0 && minSeq > 0) {
      return seq >= minSeq;
    }
    final timestamp = _objectTimestampMs(message, [
      'timestamp',
      'create_time',
      'msg_time',
    ]);
    return timestamp > 0 && minTimestamp > 0 && timestamp >= minTimestamp;
  }

  String _historyRawDropReason(Map<String, Object?> item) {
    final message = _asMap(item['message']).isEmpty
        ? item
        : _asMap(item['message']);
    final payload = _ensureBusinessPayload(
      _asMap(message['payload']),
      contentType: _historyContentType(message, _asMap(message['payload'])),
      content: _value(message, ['content', 'text']),
      clientMsgNo: _value(message, ['client_msg_no']),
    );
    final type = _historyContentType(message, payload);
    if (type.isEmpty) {
      return 'empty_content_type';
    }
    if (!ChatContentTypes.displayable.contains(type)) {
      return 'unsupported_content_type:$type';
    }
    if (payload['protocol']?.toString() != 'blin.chat.v1') {
      return 'invalid_protocol';
    }
    return 'non_displayable';
  }

  String _historyContentType(
    Map<String, Object?> message,
    Map<String, Object?> payload,
  ) {
    final direct = _value(message, [
      'content_type',
    ], fallback: payload['content_type']?.toString() ?? '');
    if (direct.isNotEmpty) {
      return direct;
    }
    return _contentTypeFromCode(
      _intValue(message, ['type'], fallback: _intValue(payload, ['type'])),
    );
  }

  String _contentTypeFromCode(int code) {
    return switch (code) {
      ImMessageTypes.text => ChatContentTypes.text,
      ImMessageTypes.image => ChatContentTypes.image,
      ImMessageTypes.voice => ChatContentTypes.voice,
      ImMessageTypes.video => ChatContentTypes.video,
      ImMessageTypes.file => ChatContentTypes.file,
      ImMessageTypes.transfer => ChatContentTypes.transfer,
      ImMessageTypes.redPacket => ChatContentTypes.redPacket,
      ImMessageTypes.redPacketReceived => ChatContentTypes.redPacketReceived,
      ImMessageTypes.transferReceived => ChatContentTypes.transferReceived,
      ImMessageTypes.emoji => ChatContentTypes.emoji,
      ImMessageTypes.gif => ChatContentTypes.gif,
      ImMessageTypes.sticker => ChatContentTypes.sticker,
      ImMessageTypes.contactCard => ChatContentTypes.contactCard,
      ImMessageTypes.call => ChatContentTypes.call,
      ImMessageTypes.walletNotice => ChatContentTypes.walletNotice,
      _ => '',
    };
  }

  int _contentTypeCode(String contentType) {
    return switch (contentType) {
      ChatContentTypes.text => ImMessageTypes.text,
      ChatContentTypes.image => ImMessageTypes.image,
      ChatContentTypes.voice => ImMessageTypes.voice,
      ChatContentTypes.video => ImMessageTypes.video,
      ChatContentTypes.file => ImMessageTypes.file,
      ChatContentTypes.transfer => ImMessageTypes.transfer,
      ChatContentTypes.redPacket => ImMessageTypes.redPacket,
      ChatContentTypes.redPacketReceived => ImMessageTypes.redPacketReceived,
      ChatContentTypes.transferReceived => ImMessageTypes.transferReceived,
      ChatContentTypes.emoji => ImMessageTypes.emoji,
      ChatContentTypes.gif => ImMessageTypes.gif,
      ChatContentTypes.sticker => ImMessageTypes.sticker,
      ChatContentTypes.contactCard => ImMessageTypes.contactCard,
      ChatContentTypes.call => ImMessageTypes.call,
      ChatContentTypes.walletNotice => ImMessageTypes.walletNotice,
      _ => 0,
    };
  }

  List<Map<String, Object?>> _bindPaymentActionMessagesToTargets(
    String channelId,
    int channelType,
    List<Map<String, Object?>> messages,
  ) {
    final candidates = <Map<String, Object?>>[
      ..._readMessagesForChannel(channelId, channelType),
      ...messages,
    ];
    return messages
        .map(
          (message) => _bindPaymentActionMessageToTarget(message, candidates),
        )
        .where((message) => message.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, Object?> _bindPaymentActionMessageToTarget(
    Map<String, Object?> message,
    List<Map<String, Object?>> candidates,
  ) {
    final payload = _asMap(message['payload']);
    final action = _value(message, [
      'content_type',
    ], fallback: _value(payload, ['content_type']));
    if (action != ChatContentTypes.redPacketReceived &&
        action != ChatContentTypes.transferReceived) {
      return message;
    }
    final nestedKey = action == ChatContentTypes.redPacketReceived
        ? 'red_packet'
        : 'transfer';
    final idKey = action == ChatContentTypes.redPacketReceived
        ? 'red_packet_id'
        : 'transfer_id';
    final idValue = _paymentActionId(payload, nestedKey, idKey);
    final target = _paymentActionTargetMessage(
      action: action,
      payload: payload,
      nestedKey: nestedKey,
      idKey: idKey,
      idValue: idValue,
      candidates: candidates,
    );
    if (target.isEmpty) {
      AppLogger.warn(
        'im',
        'payment action target missing',
        data: {
          'action': action,
          'client_msg_no': _value(message, ['client_msg_no']),
          idKey: idValue,
          'channel_id': _value(message, ['channel_id']),
          'channel_type': _intValue(message, ['channel_type']),
        },
      );
      return const <String, Object?>{};
    }
    final receipt = _cleanPayload({
      ...payload,
      ..._asMap(payload[nestedKey]),
      'operator_id': _paymentActionActorId(payload, nestedKey),
      'operator_uid': _paymentActionActorUid(message, payload, nestedKey),
      'operator_nickname': _paymentActionActorName(payload, nestedKey),
    });
    final normalized = _paymentActionReceiptMessage(
      channelId: _value(message, [
        'channel_id',
      ], fallback: _value(target, ['channel_id'])),
      channelType: _intValue(message, [
        'channel_type',
      ], fallback: _intValue(target, ['channel_type'])),
      targetMessage: target,
      action: action,
      nestedKey: nestedKey,
      idKey: idKey,
      idValue: idValue,
      receipt: receipt,
      actorIsCurrentUser: _actionReceiptFromCurrentUser(receipt),
    );
    return {
      ...message,
      ...normalized,
      'message_id': _value(message, [
        'message_id',
      ], fallback: _value(normalized, ['message_id'])),
      'message_seq': 0,
      'payload': {
        ..._asMap(normalized['payload']),
        'server_action_client_msg_no': _value(message, ['client_msg_no']),
      },
    };
  }

  String _paymentActionId(
    Map<String, Object?> payload,
    String nestedKey,
    String idKey,
  ) {
    final nested = _asMap(payload[nestedKey]);
    return _value(payload, [
      idKey,
      'id',
    ], fallback: _value(nested, [idKey, 'id']));
  }

  String _paymentActionActorId(Map<String, Object?> payload, String nestedKey) {
    final nested = _asMap(payload[nestedKey]);
    final receipt = _asMap(payload['receipt']);
    return _value(
      receipt,
      [
        'operator_id',
        'reader_id',
        'actor_id',
        'receive_user_id',
        'receiver_user_id',
        'user_id',
        'userid',
        'id',
      ],
      fallback: _value(
        payload,
        ['operator_id', 'reader_id', 'actor_id'],
        fallback: _value(
          nested,
          [
            'operator_id',
            'reader_id',
            'actor_id',
            'receiver_id',
            'receive_user_id',
            'receiver_user_id',
            'user_id',
            'userid',
            'id',
          ],
          fallback: _value(payload, [
            'sender_id',
            'from_id',
            'user_id',
            'userid',
          ]),
        ),
      ),
    );
  }

  String _paymentActionActorUid(
    Map<String, Object?> message,
    Map<String, Object?> payload,
    String nestedKey,
  ) {
    final nested = _asMap(payload[nestedKey]);
    final receipt = _asMap(payload['receipt']);
    return _value(
      receipt,
      [
        'operator_uid',
        'reader_uid',
        'actor_uid',
        'receive_uid',
        'receiver_uid',
        'uid',
      ],
      fallback: _value(
        payload,
        ['operator_uid', 'reader_uid', 'actor_uid'],
        fallback: _value(
          nested,
          [
            'operator_uid',
            'reader_uid',
            'actor_uid',
            'receive_uid',
            'receiver_uid',
            'uid',
          ],
          fallback: _value(message, [
            'from_uid',
          ], fallback: _value(payload, ['sender_uid', 'from_uid', 'uid'])),
        ),
      ),
    );
  }

  String _paymentActionActorName(
    Map<String, Object?> payload,
    String nestedKey,
  ) {
    final nested = _asMap(payload[nestedKey]);
    final receipt = _asMap(payload['receipt']);
    return _value(
      receipt,
      [
        'operator_nickname',
        'reader_nickname',
        'actor_name',
        'actor_nickname',
        'nickname',
        'username',
      ],
      fallback: _value(
        payload,
        [
          'operator_nickname',
          'reader_nickname',
          'actor_name',
          'actor_nickname',
          'sender_nickname',
          'from_nickname',
          'sender_username',
          'from_username',
          'nickname',
          'username',
        ],
        fallback: _value(nested, [
          'operator_nickname',
          'reader_nickname',
          'actor_name',
          'actor_nickname',
          'receiver_nickname',
          'receiver_username',
          'nickname',
          'username',
        ]),
      ),
    );
  }

  Map<String, Object?> _paymentActionTargetMessage({
    required String action,
    required Map<String, Object?> payload,
    required String nestedKey,
    required String idKey,
    required String idValue,
    required List<Map<String, Object?>> candidates,
  }) {
    final targetClientMsgNo = _value(
      payload,
      [
        'target_client_msg_no',
        'source_client_msg_no',
        'original_client_msg_no',
      ],
      fallback: _value(_asMap(payload[nestedKey]), [
        'target_client_msg_no',
        'source_client_msg_no',
        'original_client_msg_no',
      ]),
    );
    final targetContentType = action == ChatContentTypes.redPacketReceived
        ? ChatContentTypes.redPacket
        : ChatContentTypes.transfer;
    for (final candidate in candidates) {
      if (targetClientMsgNo.isNotEmpty &&
          _value(candidate, ['client_msg_no']) == targetClientMsgNo) {
        return candidate;
      }
    }
    if (idValue.isEmpty) {
      return const <String, Object?>{};
    }
    for (final candidate in candidates) {
      final candidatePayload = _asMap(candidate['payload']);
      final candidateType = _value(candidate, [
        'content_type',
      ], fallback: _value(candidatePayload, ['content_type']));
      if (candidateType != targetContentType) {
        continue;
      }
      final candidateId = _paymentActionId(candidatePayload, nestedKey, idKey);
      if (candidateId == idValue) {
        return candidate;
      }
    }
    return const <String, Object?>{};
  }

  int _conversationChannelType(
    Map<String, Object?> item,
    Map<String, Object?> payload,
  ) {
    final chat = _requireChat();
    final direct = _intValue(item, ['channel_type']);
    if (direct > 0) {
      return direct;
    }
    final payloadType = _intValue(payload, ['channel_type']);
    if (payloadType > 0) {
      return payloadType;
    }
    final markers = <String>[
      _value(item, ['conversation_type']),
      _value(item, ['channel_type_name']),
      _value(item, ['type']),
      _value(payload, ['conversation_type']),
      _value(payload, ['channel_type_name']),
      _value(payload, ['scene']),
      _value(payload, ['type']),
    ].map((value) => value.trim().toLowerCase()).toList(growable: false);
    if (markers.any((value) => value == 'group' || value == 'group_chat')) {
      return chat.channelTypeGroup;
    }
    if (markers.any(
      (value) =>
          value == 'private' || value == 'person' || value == 'private_chat',
    )) {
      return chat.channelTypePerson;
    }
    return chat.channelTypePerson;
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
    final messageSeq = _intValue(
      result,
      ['message_seq'],
      fallback: _intValue(sendAck, [
        'message_seq',
      ], fallback: _intValue(fallback, ['message_seq'])),
    );
    final messageType = _intValue(
      result,
      ['type'],
      fallback: _intValue(
        sendAck,
        ['type'],
        fallback: _intValue(rawMergedPayload, [
          'type',
        ], fallback: _contentTypeCode(contentType)),
      ),
    );
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
      'message_seq': messageSeq,
      if (messageType > 0) 'type': messageType,
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
    final contentType = _historyContentType(payload, payload);
    final normalizedPayload = _ensureBusinessPayload(
      payload,
      contentType: contentType,
      content: _payloadContent(payload),
      clientMsgNo: clientMsgNo,
    );
    if (!_isDisplayableChatPayload(
      normalizedPayload,
      contentType: contentType,
    )) {
      return const <String, Object?>{};
    }
    final message = <String, Object?>{
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
      'content': _payloadContent(normalizedPayload),
      'content_type': contentType,
      if (_contentTypeCode(contentType) > 0)
        'type': _contentTypeCode(contentType),
      'payload': normalizedPayload,
      'timestamp': _formatTimestamp(messageTime),
      'status': _deliveryStatusFromSources([payload]),
      if (fromUser.isNotEmpty) 'from_user': fromUser,
      if (frame.cursor.isNotEmpty) 'gateway_cursor': frame.cursor,
    };
    return _bindPaymentActionMessageToTarget(
      message,
      _readMessagesForChannel(canonicalChannelId, channelType),
    );
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
      if (_contentTypeCode(contentType) > 0)
        'type': _contentTypeCode(contentType),
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
      if (!_rememberDeleteCommand(
        source: 'recall_cmd',
        channelId: channelId,
        channelType: channelType,
        targetClientMsgNo: target,
      )) {
        return true;
      }
      _cache.deleteMessage(
        uid: chat.uid,
        channelId: channelId,
        channelType: channelType,
        clientMsgNo: target,
      );
      final operatorId = _value(payload, ['operator_id', 'sender_id']);
      final currentUserId = _receiverIdFromChannel(chat.uid);
      final isMe = operatorId.isNotEmpty && operatorId == currentUserId;
      final receiptClientMsgNo = _value(payload, [
        'client_msg_no',
      ], fallback: 'recall-receipt-$target');
      final receipt = <String, Object?>{
        'client_msg_no': receiptClientMsgNo,
        'content_type': 'recall',
        'content': isMe ? '你撤回了一条消息' : '对方撤回了一条消息',
        'is_system': true,
        'system_message': true,
        'is_me': isMe,
        'create_time': _value(payload, ['recall_time', 'timestamp']),
        'payload': <String, Object?>{
          ...payload,
          'content_type': 'recall',
          'is_system': true,
          'system_message': true,
          'target_client_msg_no': target,
        },
      };
      _upsertMessage(channelId, channelType, receipt);
      _markMessageChannel(
        source: 'recall_cmd',
        channelId: channelId,
        channelType: channelType,
      );
      _publishMessageEvent(
        source: 'recall_cmd',
        channelId: channelId,
        channelType: channelType,
        message: <String, Object?>{...receipt, 'target_client_msg_no': target},
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
        if (!_rememberDeleteCommand(
          source: 'burn_after_read_cmd',
          channelId: channelId,
          channelType: channelType,
          targetClientMsgNo: target,
        )) {
          return true;
        }
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
    if (cmd == 'burn_after_read_state') {
      _publishMessageEvent(
        source: 'burn_after_read_state_cmd',
        channelId: channelId,
        channelType: channelType,
        message: <String, Object?>{
          'client_msg_no': _value(payload, ['client_msg_no']),
          'content_type': 'cmd',
          'cmd': cmd,
          'payload': Map<String, Object?>.from(payload),
        },
      );
      return true;
    }
    if (cmd == 'private_receipt_setting') {
      _publishMessageEvent(
        source: 'private_receipt_setting_cmd',
        channelId: channelId,
        channelType: channelType,
        message: <String, Object?>{
          'client_msg_no': _value(payload, ['client_msg_no']),
          'content_type': 'cmd',
          'cmd': cmd,
          'payload': Map<String, Object?>.from(payload),
        },
      );
      return true;
    }
    if (_isFriendCommand(cmd)) {
      _handleFriendCommandPayload(payload, channelId, channelType);
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

  bool _rememberDeleteCommand({
    required String source,
    required String channelId,
    required int channelType,
    required String targetClientMsgNo,
  }) {
    final key =
        '$source|${_messageKey(channelId, channelType)}|$targetClientMsgNo';
    if (!_handledDeleteCommandKeys.add(key)) {
      AppLogger.info(
        'im',
        'delete command duplicate ignored',
        data: {
          'source': source,
          'channel_id': channelId,
          'channel_type': channelType,
          'target_client_msg_no': targetClientMsgNo,
        },
      );
      return false;
    }
    _handledDeleteCommandKeyOrder.add(key);
    while (_handledDeleteCommandKeyOrder.length > 500) {
      final expired = _handledDeleteCommandKeyOrder.removeFirst();
      _handledDeleteCommandKeys.remove(expired);
    }
    return true;
  }

  bool _isReadReceiptCommand(String cmd) {
    final normalized = cmd.toLowerCase();
    return normalized == 'read_receipt' ||
        normalized == 'message_read' ||
        normalized == 'message_read_receipt';
  }

  bool _isFriendCommand(String cmd) {
    final normalized = cmd.toLowerCase();
    return normalized == 'friend_apply' ||
        normalized == 'friend_apply_created' ||
        normalized == 'friend_accepted' ||
        normalized == 'friend_apply_accepted' ||
        normalized == 'friend_rejected' ||
        normalized == 'friend_apply_rejected' ||
        normalized == 'friend_deleted';
  }

  void _handleFriendCommandPayload(
    Map<String, Object?> payload,
    String channelId,
    int channelType,
  ) {
    final chat = _requireChat();
    final rawCmd = _value(payload, ['cmd']);
    final event = _normalizeFriendCommand(rawCmd);
    final detail = _asMap(payload['friend']);
    final friendId = _value(detail, [
      'friend_id',
      'target_user_id',
      'user_id',
      'userid',
    ], fallback: _value(payload, ['friend_id', 'target_user_id']));
    if (event == 'friend_deleted' && friendId.isNotEmpty) {
      _cache.removeFriend(uid: chat.uid, friendId: friendId);
    }
    final normalizedPayload = <String, Object?>{
      ...payload,
      'event': event,
      'raw_cmd': rawCmd,
      'friend': detail,
      if (friendId.isNotEmpty) 'friend_id': friendId,
      'channel_id': channelId,
      'channel_type': channelType,
    };
    if (!_friendEvents.isClosed) {
      _friendEvents.add(
        BusinessImFriendEvent(
          source: 'gateway_cmd',
          event: event,
          payload: normalizedPayload,
        ),
      );
    }
    AppLogger.info(
      'im',
      'friend command handled',
      data: {
        'event': event,
        'raw_cmd': rawCmd,
        'apply_id': _value(detail, ['apply_id', 'id']),
        'friend_id': friendId,
        'channel_id': channelId,
        'channel_type': channelType,
      },
    );
    notifyListeners();
  }

  String _normalizeFriendCommand(String cmd) {
    final normalized = cmd.toLowerCase();
    return switch (normalized) {
      'friend_apply' => 'friend_apply_created',
      'friend_accepted' => 'friend_apply_accepted',
      'friend_rejected' => 'friend_apply_rejected',
      _ => normalized,
    };
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
        _storePendingActionReceipt(
          channelId: receiptChannelId,
          channelType: channelType,
          targetClientMsgNo: target,
          payload: payload,
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
      final flatReceipt = Map<String, Object?>.from(receipt)
        ..remove('red_packet')
        ..remove('transfer');
      final actionReceipt = _cleanPayload({...flatReceipt, ...nestedReceipt});
      final receiptFromCurrentUser = _actionReceiptFromCurrentUser(
        actionReceipt,
      );
      final updatedNested = _cleanPayload({
        ...existingNested,
        ...actionReceipt,
        if (receiptFromCurrentUser) 'received_by_me': '1',
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
      final receiptMessage = _paymentActionReceiptMessage(
        channelId: receiptChannelId,
        channelType: channelType,
        targetMessage: updated,
        action: action,
        nestedKey: nestedKey,
        idKey: action == ChatContentTypes.redPacketReceived
            ? 'red_packet_id'
            : 'transfer_id',
        idValue: _value(updatedNested, [
          action == ChatContentTypes.redPacketReceived
              ? 'red_packet_id'
              : 'transfer_id',
          'id',
        ]),
        receipt: actionReceipt,
        actorIsCurrentUser: receiptFromCurrentUser,
      );
      _upsertMessage(receiptChannelId, channelType, receiptMessage);
      _publishMessageEvent(
        source: 'gateway_action_receipt',
        channelId: receiptChannelId,
        channelType: channelType,
        message: updated,
      );
      _publishMessageEvent(
        source: 'gateway_action_receipt_notice',
        channelId: receiptChannelId,
        channelType: channelType,
        message: receiptMessage,
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

  void _storePendingActionReceipt({
    required String channelId,
    required int channelType,
    required String targetClientMsgNo,
    required Map<String, Object?> payload,
  }) {
    if (targetClientMsgNo.isEmpty) {
      return;
    }
    final key = _pendingActionReceiptKey(
      channelId: channelId,
      channelType: channelType,
      clientMsgNo: targetClientMsgNo,
    );
    final list = _pendingActionReceipts.putIfAbsent(
      key,
      () => <Map<String, Object?>>[],
    );
    final cmdClientMsgNo = _value(payload, ['client_msg_no']);
    if (cmdClientMsgNo.isNotEmpty &&
        list.any((item) => _value(item, ['client_msg_no']) == cmdClientMsgNo)) {
      return;
    }
    list.add(Map<String, Object?>.from(payload));
    while (_pendingActionReceipts.length > 128) {
      _pendingActionReceipts.remove(_pendingActionReceipts.keys.first);
    }
    AppLogger.info(
      'im',
      'action receipt pending',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'target_client_msg_no': targetClientMsgNo,
        'pending_for_target': list.length,
        'pending_targets': _pendingActionReceipts.length,
      },
    );
  }

  void _replayPendingActionReceipts({
    required String channelId,
    required int channelType,
    required String clientMsgNo,
  }) {
    final key = _pendingActionReceiptKey(
      channelId: channelId,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
    );
    final pending = _pendingActionReceipts.remove(key);
    if (pending == null || pending.isEmpty) {
      return;
    }
    AppLogger.info(
      'im',
      'action receipt pending replay',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'target_client_msg_no': clientMsgNo,
        'count': pending.length,
      },
    );
    for (final payload in pending) {
      _handleActionReceiptPayload(payload, channelId, channelType);
    }
  }

  String _pendingActionReceiptKey({
    required String channelId,
    required int channelType,
    required String clientMsgNo,
  }) {
    return '$channelType:$channelId:$clientMsgNo';
  }

  bool _actionReceiptFromCurrentUser(Map<String, Object?> receipt) {
    final currentUserId = _requireSession().userId.toString();
    final action = _value(receipt, ['action', 'content_type']);
    if (action == ChatContentTypes.redPacketReceived ||
        action == ChatContentTypes.transferReceived) {
      final nestedKey = action == ChatContentTypes.redPacketReceived
          ? 'red_packet'
          : 'transfer';
      final actorId = _paymentActionActorId(receipt, nestedKey);
      if (actorId.isNotEmpty) {
        return actorId == currentUserId;
      }
      final actorUid = _paymentActionActorUid(
        const <String, Object?>{},
        receipt,
        nestedKey,
      );
      if (actorUid.isNotEmpty) {
        return _isCurrentUserChannel(actorUid);
      }
    }
    final sources = [
      receipt,
      _asMap(receipt['receipt']),
      _asMap(receipt['red_packet']),
      _asMap(receipt['transfer']),
      _asMap(receipt['operator']),
      _asMap(receipt['reader']),
      _asMap(receipt['receiver']),
      _asMap(receipt['actor']),
      _asMap(receipt['user']),
    ];
    for (final source in sources) {
      final operatorId = _value(source, [
        'operator_id',
        'reader_id',
        'receiver_id',
        'receive_user_id',
        'receiver_user_id',
        'actor_id',
        'user_id',
        'userid',
        'id',
      ]);
      if (operatorId.isNotEmpty && operatorId == currentUserId) {
        return true;
      }
      final operatorUid = _value(source, [
        'operator_uid',
        'reader_uid',
        'receiver_uid',
        'receive_uid',
        'actor_uid',
        'uid',
      ]);
      if (operatorUid.isNotEmpty && _isCurrentUserChannel(operatorUid)) {
        return true;
      }
    }
    return false;
  }

  bool _isSystemActionMessage(Map<String, Object?> item) {
    final contentType = _value(item, [
      'content_type',
    ], fallback: _value(_asMap(item['payload']), ['content_type']));
    return contentType == ChatContentTypes.redPacketReceived ||
        contentType == ChatContentTypes.transferReceived ||
        _boolValue(item['is_system']) ||
        _boolValue(_asMap(item['payload'])['is_system']);
  }

  Map<String, Object?> _paymentActionReceiptMessage({
    required String channelId,
    required int channelType,
    required Map<String, Object?> targetMessage,
    required String action,
    required String nestedKey,
    required String idKey,
    required String idValue,
    required Map<String, Object?> receipt,
    required bool actorIsCurrentUser,
  }) {
    final session = _requireSession();
    final chat = _requireChat();
    final targetPayload = _asMap(targetMessage['payload']);
    final targetNested = _asMap(targetPayload[nestedKey]);
    final actorId = actorIsCurrentUser
        ? session.userId.toString()
        : _value(receipt, [
            'operator_id',
            'reader_id',
            'receiver_id',
            'receive_user_id',
            'receiver_user_id',
            'actor_id',
            'user_id',
            'userid',
            'id',
          ]);
    final actorUid = actorIsCurrentUser
        ? chat.uid
        : _value(receipt, [
            'operator_uid',
            'reader_uid',
            'receiver_uid',
            'receive_uid',
            'actor_uid',
            'uid',
          ]);
    final actorName = actorIsCurrentUser
        ? _currentUserDisplayName()
        : _displayNameFromSources([
            receipt,
            _asMap(receipt['operator']),
            _asMap(receipt['reader']),
            _asMap(receipt['receiver']),
            _asMap(receipt['user']),
          ], fallback: _profileDisplayName(actorId, fallback: '对方'));
    final senderIsCurrentUser = targetMessage['is_me'] == true;
    final senderId = _value(targetMessage, [
      'sender_id',
      'from_id',
      'user_id',
      'userid',
    ], fallback: _value(targetPayload, ['sender_id', 'from_id']));
    final senderName = senderIsCurrentUser
        ? '你'
        : _displayNameFromSources(
            [
              _asMap(targetMessage['from_user']),
              targetMessage,
              targetPayload,
              targetNested,
            ],
            fallback: _profileDisplayName(
              senderId,
              fallback: channelType == chat.channelTypeGroup ? '成员' : '对方',
            ),
          );
    final content = _paymentActionReceiptText(
      action: action,
      actorIsCurrentUser: actorIsCurrentUser,
      actorName: actorName,
      senderIsCurrentUser: senderIsCurrentUser,
      senderName: senderName,
    );
    final targetClientMsgNo = _value(targetMessage, ['client_msg_no']);
    final actorKey = actorId.isNotEmpty
        ? actorId
        : actorUid.isNotEmpty
        ? actorUid
        : actorName;
    final clientMsgNo = 'receipt_${action}_${targetClientMsgNo}_$actorKey'
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '_');
    final targetTimestamp = _objectTimestampMs(targetMessage, [
      'timestamp',
      'create_time',
      'msg_time',
    ]);
    final receiptTimestampSeconds = targetTimestamp > 0
        ? (targetTimestamp + 1000) ~/ 1000
        : DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = _cleanPayload({
      'protocol': 'blin.chat.v1',
      'content_type': action,
      'action': action,
      'content': content,
      'target_client_msg_no': targetClientMsgNo,
      if (idValue.isNotEmpty) idKey: idValue,
      'actor_id': actorId,
      'actor_uid': actorUid,
      'actor_name': actorName,
      'actor_is_me': actorIsCurrentUser ? '1' : '0',
      'sender_name': senderName,
      'sender_is_me': senderIsCurrentUser ? '1' : '0',
      nestedKey: {
        ...targetNested,
        ...receipt,
        if (idValue.isNotEmpty) idKey: idValue,
      },
      if (channelType == chat.channelTypeGroup)
        'group_id': _value(targetPayload, ['group_id'], fallback: channelId),
    });
    return _cleanPayload({
      'message_id': '',
      'client_msg_no': clientMsgNo,
      'message_seq': 0,
      'channel_id': channelId,
      'channel_type': channelType,
      if (channelType == chat.channelTypePerson)
        'receiver_id': _receiverIdFromMessage(targetMessage, channelId),
      'from_uid': actorIsCurrentUser ? chat.uid : actorUid,
      'is_me': actorIsCurrentUser,
      'is_system': '1',
      'content': content,
      'content_type': action,
      'payload': payload,
      'timestamp': _formatTimestamp(receiptTimestampSeconds),
      'status': 'sent',
    });
  }

  String _paymentActionReceiptText({
    required String action,
    required bool actorIsCurrentUser,
    required String actorName,
    required bool senderIsCurrentUser,
    required String senderName,
  }) {
    if (action == ChatContentTypes.redPacketReceived) {
      if (actorIsCurrentUser && senderIsCurrentUser) {
        return '你领取了自己的红包';
      }
      if (actorIsCurrentUser) {
        return '你领取了$senderName的红包';
      }
      if (senderIsCurrentUser) {
        return '$actorName领取了你的红包';
      }
      if (actorName.isNotEmpty && actorName == senderName) {
        return '$actorName领取了自己的红包';
      }
      return '$actorName领取了$senderName的红包';
    }
    if (action == ChatContentTypes.transferReceived) {
      if (actorIsCurrentUser) {
        return '你已收取$senderName的转账';
      }
      if (senderIsCurrentUser) {
        return '$actorName已收取你的转账';
      }
      return '$actorName已收取$senderName的转账';
    }
    return actorIsCurrentUser ? '你完成了操作' : '$actorName完成了操作';
  }

  String _currentUserDisplayName() {
    final current = _requireSession();
    if (current.nickname.trim().isNotEmpty) {
      return current.nickname.trim();
    }
    if (current.username.trim().isNotEmpty) {
      return current.username.trim();
    }
    return '你';
  }

  String _displayNameFromSources(
    List<Map<String, Object?>> sources, {
    required String fallback,
  }) {
    for (final source in sources) {
      final value = _value(source, [
        'nickname',
        'name',
        'username',
        'remark_name',
        'display_name',
        'sender_nickname',
        'from_nickname',
        'operator_nickname',
        'reader_nickname',
        'receiver_nickname',
        'actor_name',
      ]);
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return fallback;
  }

  String _profileDisplayName(String userId, {required String fallback}) {
    if (userId.isEmpty) {
      return fallback;
    }
    final chat = _session?.chat;
    if (chat == null) {
      return fallback;
    }
    final profile = _cache.readProfile(uid: chat.uid, userId: userId);
    return _displayNameFromSources([profile], fallback: fallback);
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
        includeConversation: false,
      );
      handled = true;
    }
    if (handled) {
      AppLogger.info(
        'im',
        'read receipt applied without channel reload',
        data: {
          'source': source,
          'channel_id': channelId,
          'channel_type': channelType,
          'target_count': targets.length,
        },
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
    final beforeCount = messages.length;
    var inserted = false;
    var updated = false;
    if (index >= 0) {
      messages[index] = _mergeMessageFields(messages[index], normalizedMessage);
      updated = true;
    } else {
      final actionIndex = messages.indexWhere(
        (item) => _samePaymentActionMessage(item, normalizedMessage),
      );
      if (actionIndex >= 0) {
        messages[actionIndex] = _mergeMessageFields(
          messages[actionIndex],
          normalizedMessage,
        );
        updated = true;
      } else {
        messages.add(normalizedMessage);
        inserted = true;
      }
    }
    AppLogger.info(
      'im',
      'message upserted',
      data: {
        'channel_id': normalizedChannelId,
        'channel_type': channelType,
        'client_msg_no': clientMsgNo,
        'message_seq': messageSeq,
        'is_update': updated,
        'inserted': inserted,
        'is_me': normalizedMessage['is_me'] == true,
        'content_type': _value(normalizedMessage, ['content_type']),
        'before_count': beforeCount,
        'after_count': messages.length,
        'action_dedupe_key': _paymentActionMessageKey(normalizedMessage),
        'message': _messageLogSummary(normalizedMessage),
      },
    );
    _writeMessages(
      normalizedChannelId,
      channelType,
      _sortAndLimit(messages, _messageCacheLimit),
    );
    if (clientMsgNo.isNotEmpty) {
      _replayPendingActionReceipts(
        channelId: normalizedChannelId,
        channelType: channelType,
        clientMsgNo: clientMsgNo,
      );
    }
    return _MessageUpsertResult(stored: true, inserted: inserted);
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
    bool includeConversation = true,
  }) {
    if (_messageEvents.isClosed) {
      return;
    }
    final conversation = includeConversation
        ? _conversationForChannel(channelId, channelType)
        : const <String, Object?>{};
    AppLogger.info(
      'im',
      'message event published',
      data: {
        'source': source,
        'channel_id': channelId,
        'channel_type': channelType,
        'include_conversation': includeConversation,
        'has_conversation': conversation.isNotEmpty,
        'message': _messageLogSummary(message),
      },
    );
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
    if (_manualStop || !_started) {
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
        final actionIndex = merged.indexWhere(
          (item) => _samePaymentActionMessage(item, message),
        );
        if (actionIndex >= 0) {
          merged[actionIndex] = _mergeMessageFields(
            merged[actionIndex],
            message,
          );
        } else {
          merged.add(message);
        }
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

  bool _samePaymentActionMessage(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    final leftKeys = _paymentActionMessageKeys(left);
    if (leftKeys.isEmpty) {
      return false;
    }
    final rightKeys = _paymentActionMessageKeys(right);
    return leftKeys.any(rightKeys.contains);
  }

  Set<String> _paymentActionMessageKeys(Map<String, Object?> message) {
    final keys = <String>{};
    final key = _paymentActionMessageKey(message);
    if (key.isNotEmpty) {
      keys.add(key);
    }
    final compactKey = _paymentActionCompactMessageKey(message);
    if (compactKey.isNotEmpty) {
      keys.add(compactKey);
    }
    return keys;
  }

  String _paymentActionMessageKey(Map<String, Object?> message) {
    final payload = _asMap(message['payload']);
    final action = _value(message, [
      'content_type',
    ], fallback: _value(payload, ['content_type', 'action']));
    if (action != ChatContentTypes.redPacketReceived &&
        action != ChatContentTypes.transferReceived) {
      return '';
    }
    final nestedKey = action == ChatContentTypes.redPacketReceived
        ? 'red_packet'
        : 'transfer';
    final idKey = action == ChatContentTypes.redPacketReceived
        ? 'red_packet_id'
        : 'transfer_id';
    final nested = _asMap(payload[nestedKey]);
    final targetClientMsgNo = _value(
      payload,
      [
        'target_client_msg_no',
        'source_client_msg_no',
        'original_client_msg_no',
      ],
      fallback: _value(nested, [
        'target_client_msg_no',
        'source_client_msg_no',
        'original_client_msg_no',
      ]),
    );
    final idValue = _paymentActionId(payload, nestedKey, idKey);
    final actionTarget = targetClientMsgNo.isNotEmpty
        ? targetClientMsgNo
        : idValue;
    if (actionTarget.isEmpty) {
      return '';
    }
    final actorKey = _paymentActionActorId(payload, nestedKey);
    final actorUid = _paymentActionActorUid(message, payload, nestedKey);
    final actor = actorKey.isNotEmpty ? actorKey : actorUid;
    if (actor.isEmpty) {
      return '';
    }
    return '$action:$actionTarget:$idValue:$actor';
  }

  String _paymentActionCompactMessageKey(Map<String, Object?> message) {
    final payload = _asMap(message['payload']);
    final action = _value(message, [
      'content_type',
    ], fallback: _value(payload, ['content_type', 'action']));
    if (action != ChatContentTypes.redPacketReceived &&
        action != ChatContentTypes.transferReceived) {
      return '';
    }
    final nestedKey = action == ChatContentTypes.redPacketReceived
        ? 'red_packet'
        : 'transfer';
    final idKey = action == ChatContentTypes.redPacketReceived
        ? 'red_packet_id'
        : 'transfer_id';
    final idValue = _paymentActionId(payload, nestedKey, idKey);
    if (idValue.isEmpty) {
      return '';
    }
    final actorKey = _paymentActionActorId(payload, nestedKey);
    final actorUid = _paymentActionActorUid(message, payload, nestedKey);
    final actor = actorKey.isNotEmpty ? actorKey : actorUid;
    if (actor.isEmpty) {
      return '';
    }
    return '$action:$idValue:$actor';
  }

  String _readReceiptKey(
    String channelId,
    int channelType,
    String clientMsgNo,
  ) {
    return '${_messageKey(channelId, channelType)}|$clientMsgNo';
  }

  bool _readMarkerCoversMessage(
    Map<String, Object?> marker,
    Map<String, Object?> message,
  ) {
    if (marker.isEmpty) {
      return false;
    }
    final markerSeq = _intValue(marker, ['message_seq']);
    final messageSeq = _intValue(message, ['message_seq']);
    if (markerSeq > 0 && messageSeq > 0) {
      return messageSeq <= markerSeq;
    }
    final markerMsgNo = _value(marker, ['client_msg_no']);
    final clientMsgNo = _value(message, ['client_msg_no']);
    return markerMsgNo.isNotEmpty && markerMsgNo == clientMsgNo;
  }

  Map<String, Object?> _mergeMessageFields(
    Map<String, Object?> existing,
    Map<String, Object?> incoming,
  ) {
    final merged = _mergeNonEmpty(existing, incoming);
    final existingPayload = _asMap(existing['payload']);
    final incomingPayload = _asMap(incoming['payload']);
    if (existingPayload.isNotEmpty || incomingPayload.isNotEmpty) {
      final payload = _mergeNonEmpty(existingPayload, incomingPayload);
      for (final key in [
        'red_packet',
        'transfer',
        'media',
        'receipt',
        'quote',
        'reply',
      ]) {
        final existingNested = _asMap(existingPayload[key]);
        final incomingNested = _asMap(incomingPayload[key]);
        if (existingNested.isNotEmpty || incomingNested.isNotEmpty) {
          payload[key] = _mergeNonEmpty(existingNested, incomingNested);
        }
      }
      _preserveNonEmptyString(payload, existingPayload, incomingPayload, [
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
        'quote_json',
      ]);
      merged['payload'] = payload;
    }
    _preservePositiveInt(merged, existing, incoming, ['message_seq']);
    _preserveNonEmptyString(merged, existing, incoming, [
      'message_id',
      'message_idstr',
      'client_msg_no',
      'content',
      'content_type',
      'timestamp',
      'from_uid',
    ]);
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

  void _preservePositiveInt(
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

  void _preserveNonEmptyString(
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

  bool _isMissingGroupError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('群聊不存在') ||
        text.contains('群不存在') ||
        text.contains('group not found') ||
        text.contains('group does not exist');
  }

  void _removeInvalidChannel({
    required String channelId,
    required int channelType,
    required String source,
  }) {
    final chat = _requireChat();
    channelId = _canonicalChannelId(channelId, channelType);
    _cache.removeChannelCache(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
    );
    final key = _messageKey(channelId, channelType);
    _invalidMessageChannels.add(key);
    _forgetChannelHistorySynced(channelId, channelType);
    _channelMessageVersions.remove(key);
    _latestConversations = _currentLocalConversations(
      chat,
    ).map(_hydrateConversationProfile).toList(growable: false);
    _bumpConversations(source);
    _markMessageChannel(
      source: source,
      channelId: channelId,
      channelType: channelType,
    );
  }

  void _clearLocalHistoryBoundaryAfterServerSync({
    required String channelId,
    required int channelType,
    required int acceptedCount,
  }) {
    final chat = _requireChat();
    channelId = _canonicalChannelId(channelId, channelType);
    final boundary = _cache.readChannelClearMarker(
      uid: chat.uid,
      channelId: channelId,
      channelType: channelType,
    );
    if (boundary <= 0) {
      return;
    }
    AppLogger.info(
      'im',
      'local history boundary kept after server sync',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'accepted_count': acceptedCount,
        'boundary': boundary,
      },
    );
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
    final beforeCount = _cache
        .readMessages(
          uid: _requireChat().uid,
          channelId: channelId,
          channelType: channelType,
        )
        .length;
    AppLogger.info(
      'im',
      'messages cached',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'input_count': messages.length,
        'visible_count': visible.length,
        'before_count': beforeCount,
        'after_count': visible.length,
        'first_message': _messageLogSummary(
          visible.isEmpty ? const <String, Object?>{} : visible.first,
        ),
        'last_message': _messageLogSummary(
          visible.isEmpty ? const <String, Object?>{} : visible.last,
        ),
      },
    );
    _cache.writeMessages(
      uid: _requireChat().uid,
      channelId: channelId,
      channelType: channelType,
      messages: visible,
    );
  }

  bool _writeReadMarkerForMessages(
    String channelId,
    int channelType,
    List<Map<String, Object?>> messages, {
    Map<String, Object?>? previousMarker,
  }) {
    final chat = _requireChat();
    final lastSeq = messages.fold<int>(
      0,
      (maxSeq, item) => max(maxSeq, _intValue(item, ['message_seq'])),
    );
    final sorted = _sortAndLimit(messages, messages.length);
    final lastMsgNo = sorted.isEmpty
        ? ''
        : sorted.last['client_msg_no']?.toString() ?? '';
    final previous =
        previousMarker ??
        _cache.readReadMarker(
          uid: chat.uid,
          channelId: channelId,
          channelType: channelType,
        );
    final previousSeq = _intValue(previous, ['message_seq']);
    final previousMsgNo = _value(previous, ['client_msg_no']);
    if (lastSeq < previousSeq ||
        (lastSeq == previousSeq &&
            (lastSeq > 0 || lastMsgNo.isEmpty || lastMsgNo == previousMsgNo))) {
      return false;
    }
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
    AppLogger.info(
      'im',
      'read marker cached',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'message_count': messages.length,
        'message_seq': lastSeq,
        'client_msg_no': lastMsgNo,
      },
    );
    return true;
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
    var normalizedMessage = <String, Object?>{
      ...message,
      'channel_id': channelId,
      'channel_type': channelType,
    };
    final storedMessages = _readMessagesForChannel(channelId, channelType);
    final storedIndex = storedMessages.indexWhere(
      (item) => _sameMessageIdentity(
        item,
        _value(normalizedMessage, ['client_msg_no']),
        _intValue(normalizedMessage, ['message_seq']),
      ),
    );
    if (storedIndex >= 0) {
      normalizedMessage = _mergeMessageFields(
        normalizedMessage,
        storedMessages[storedIndex],
      );
    }
    if (_isSystemActionMessage(normalizedMessage)) {
      AppLogger.info(
        'im',
        'conversation upsert skipped for action notice',
        data: {
          'channel_id': channelId,
          'channel_type': channelType,
          'client_msg_no': _value(normalizedMessage, ['client_msg_no']),
          'content_type': _value(normalizedMessage, ['content_type']),
        },
      );
      return;
    }
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
    final channelKey = _messageKey(channelId, channelType);
    final isCurrentOpen = _openMessageChannels.contains(channelKey);
    final isCurrentReadVisible =
        _foreground && _readVisibleMessageChannels.contains(channelKey);
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
      'unread_quantity': isOutgoing || isCurrentReadVisible
          ? 0
          : previousUnread + 1,
    });
    if (index >= 0) {
      conversations[index] = next;
    } else {
      conversations.insert(0, next);
    }
    _latestConversations = _sortConversations(conversations);
    _cache.writeConversations(
      uid: chat.uid,
      conversations: _latestConversations,
    );
    AppLogger.info(
      'im',
      'conversation upserted from message',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'receiver_id': receiverId,
        'client_msg_no': normalizedMessage['client_msg_no']?.toString() ?? '',
        'is_update': index >= 0,
        'is_outgoing': isOutgoing,
        'is_current_open': isCurrentOpen,
        'is_current_read_visible': isCurrentReadVisible,
        'previous_unread': previousUnread,
        'unread_quantity': _intValue(next, ['unread_quantity']),
        'conversation_count': _latestConversations.length,
        'message': _messageLogSummary(normalizedMessage),
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
    _latestConversations = _sortConversations(conversations);
    _cache.writeConversations(
      uid: chat.uid,
      conversations: _latestConversations,
    );
    AppLogger.info(
      'im',
      'conversation last message replaced',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'receiver_id': receiverId,
        'client_msg_no': message['client_msg_no']?.toString() ?? '',
        'is_update': index >= 0,
        'previous_unread': previousUnread,
        'unread_quantity': _intValue(next, ['unread_quantity']),
        'conversation_count': conversations.length,
        'message': _messageLogSummary(message),
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
    _latestConversations = _sortConversations(conversations);
    _cache.writeConversations(
      uid: chat.uid,
      conversations: _latestConversations,
    );
    _bumpConversations(source);
    return true;
  }

  Map<String, Object?> _lastConversationMessage(
    List<Map<String, Object?>> messages,
  ) {
    for (final message in messages.reversed) {
      if (!_isSystemActionMessage(message)) {
        return message;
      }
    }
    return const <String, Object?>{};
  }

  bool _isWalletNoticeMessage(Map<String, Object?> message) {
    final payload = _asMap(message['payload']);
    return _value(message, ['content_type']) == ChatContentTypes.walletNotice ||
        _value(payload, ['content_type']) == ChatContentTypes.walletNotice ||
        _asMap(payload['wallet_notice']).isNotEmpty;
  }

  int _messageTimestampMs(Map<String, Object?> message) {
    return _objectTimestampMs(message, const [
      'timestamp',
      'send_time',
      'create_time',
      'client_timestamp',
    ]);
  }

  List<Map<String, Object?>> _sortAndLimit(
    List<Map<String, Object?>> messages,
    int limit,
  ) {
    final sorted = messages.toList()
      ..sort((a, b) {
        if (_isWalletNoticeMessage(a) || _isWalletNoticeMessage(b)) {
          final timeCompare = _messageTimestampMs(
            a,
          ).compareTo(_messageTimestampMs(b));
          if (timeCompare != 0) return timeCompare;
        }
        final seqA = _intValue(a, ['message_seq']);
        final seqB = _intValue(b, ['message_seq']);
        if (seqA != seqB && seqA > 0 && seqB > 0) {
          return seqA.compareTo(seqB);
        }
        return (a['timestamp']?.toString() ?? '').compareTo(
          b['timestamp']?.toString() ?? '',
        );
      });
    final deduped = <Map<String, Object?>>[];
    final actionIndexes = <String, int>{};
    for (final message in sorted) {
      final actionKeys = _paymentActionMessageKeys(message);
      if (actionKeys.isEmpty) {
        deduped.add(message);
        continue;
      }
      int? existingIndex;
      for (final actionKey in actionKeys) {
        final index = actionIndexes[actionKey];
        if (index != null) {
          existingIndex = index;
          break;
        }
      }
      if (existingIndex == null) {
        for (final actionKey in actionKeys) {
          actionIndexes[actionKey] = deduped.length;
        }
        deduped.add(message);
      } else {
        deduped[existingIndex] = _mergeMessageFields(
          deduped[existingIndex],
          message,
        );
        for (final actionKey in actionKeys) {
          actionIndexes[actionKey] = existingIndex;
        }
      }
    }
    if (deduped.length <= limit) {
      return deduped;
    }
    return deduped.sublist(deduped.length - limit);
  }

  Map<String, Object?> _rawHistoryMessageLogSummary(Map<String, Object?> raw) {
    if (raw.isEmpty) {
      return const {'empty': true};
    }
    final message = _asMap(raw['message']).isEmpty
        ? raw
        : _asMap(raw['message']);
    final rawMeta = _asMap(raw['raw']);
    return {
      ..._messageLogSummary(message),
      if (rawMeta.isNotEmpty) ...{
        'raw_client_msg_no': _value(rawMeta, ['client_msg_no']),
        'raw_message_id': _value(rawMeta, ['message_id', 'message_idstr']),
        'raw_message_seq': _intValue(rawMeta, ['message_seq']),
        'raw_channel_id': _value(rawMeta, ['channel_id']),
        'raw_channel_type': _intValue(rawMeta, ['channel_type']),
      },
    };
  }

  Map<String, Object?> _messageLogSummary(Map<String, Object?> message) {
    if (message.isEmpty) {
      return const {'empty': true};
    }
    final payload = _asMap(message['payload']);
    final content = _value(message, [
      'content',
      'text',
    ], fallback: _value(payload, ['content', 'text']));
    final contentType = _value(message, [
      'content_type',
    ], fallback: _value(payload, ['content_type']));
    return {
      'client_msg_no': _value(message, [
        'client_msg_no',
      ], fallback: _value(payload, ['client_msg_no'])),
      'message_id': _value(message, ['message_id', 'message_idstr']),
      'message_seq': _intValue(message, ['message_seq']),
      'channel_id': _value(message, ['channel_id']),
      'channel_type': _intValue(message, ['channel_type']),
      'from_uid': _value(message, [
        'from_uid',
      ], fallback: _value(payload, ['from_uid'])),
      'is_me': _boolValue(message['is_me']),
      'status': _value(message, ['status']),
      'content_type': contentType,
      'type': _intValue(message, [
        'type',
      ], fallback: _intValue(payload, ['type'])),
      'timestamp': _value(message, ['timestamp', 'create_time', 'msg_time']),
      'content_len': content.length,
      if (content.isNotEmpty)
        'content_preview': content.substring(0, min(120, content.length)),
      'payload_keys': payload.keys.take(80).toList(growable: false),
      'has_red_packet': payload['red_packet'] is Map,
      'has_transfer': payload['transfer'] is Map,
      'has_reply':
          _value(payload, [
            'reply_client_msg_no',
            'quote_client_msg_no',
          ]).isNotEmpty ||
          _asMap(payload['quote']).isNotEmpty ||
          _asMap(payload['reply']).isNotEmpty ||
          _value(payload, ['reply']).isNotEmpty,
      'has_file_path': _value(payload, ['file_path']).isNotEmpty,
      'has_image_path': _value(payload, ['image_path']).isNotEmpty,
      'has_video_path': _value(payload, ['video_path']).isNotEmpty,
      'action_dedupe_key': _paymentActionMessageKey(message),
    };
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

  Map<String, Object?> _normalizeOutgoingPayload(
    String contentType,
    Map<String, Object?> payload,
  ) {
    final normalized = Map<String, Object?>.from(payload);
    if (contentType == ChatContentTypes.image ||
        contentType == ChatContentTypes.video ||
        contentType == ChatContentTypes.voice ||
        contentType == ChatContentTypes.file) {
      return _normalizeOutgoingMediaPayload(contentType, normalized);
    }
    if (contentType != ChatContentTypes.emoji &&
        contentType != ChatContentTypes.gif &&
        contentType != ChatContentTypes.sticker) {
      return normalized;
    }
    final media = _asMap(normalized['media']);
    final emojiId = _value(normalized, [
      'emoji_id',
      'emoji_code',
      'sticker_id',
    ], fallback: _value(media, ['emoji_id', 'emoji_code', 'sticker_id']));
    final emojiAsset = _value(
      normalized,
      ['emoji_asset', 'asset', 'emoji_path', 'sticker_asset'],
      fallback: _value(media, [
        'emoji_asset',
        'asset',
        'emoji_path',
        'sticker_asset',
      ]),
    );
    final url = _value(normalized, [
      'url',
      'file_url',
      'image_url',
      'gif_url',
    ], fallback: _value(media, ['url', 'file_url', 'image_url', 'gif_url']));
    final content = switch (contentType) {
      ChatContentTypes.gif => '[GIF]',
      ChatContentTypes.sticker => '[贴纸]',
      _ => '[表情]',
    };
    normalized
      ..['content'] = content
      ..remove('text')
      ..remove('emoji_label')
      ..remove('content_preview');
    if (emojiId.isNotEmpty) {
      normalized
        ..['emoji_id'] = emojiId
        ..['emoji_code'] = emojiId
        ..['sticker_id'] = _value(normalized, [
          'sticker_id',
        ], fallback: emojiId);
    }
    if (emojiAsset.isNotEmpty) {
      normalized
        ..['emoji_asset'] = emojiAsset
        ..['sticker_asset'] = emojiAsset;
    }
    if (url.isNotEmpty) {
      normalized['url'] = url;
    }
    normalized.putIfAbsent('pack_id', () => _value(media, ['pack_id']));
    normalized.putIfAbsent('format', () => _value(media, ['format']));
    final nextMedia = Map<String, Object?>.from(media);
    if (emojiId.isNotEmpty) {
      nextMedia
        ..['emoji_id'] = emojiId
        ..['emoji_code'] = emojiId
        ..['sticker_id'] = _value(nextMedia, ['sticker_id'], fallback: emojiId);
    }
    if (emojiAsset.isNotEmpty) {
      nextMedia
        ..['emoji_asset'] = emojiAsset
        ..['sticker_asset'] = emojiAsset
        ..['asset'] = emojiAsset;
    }
    if (url.isNotEmpty) {
      nextMedia['url'] = url;
    }
    nextMedia.putIfAbsent('pack_id', () => _value(normalized, ['pack_id']));
    nextMedia.putIfAbsent('format', () => _value(normalized, ['format']));
    normalized['media'] = nextMedia;
    return normalized;
  }

  Map<String, Object?> _normalizeOutgoingMediaPayload(
    String contentType,
    Map<String, Object?> payload,
  ) {
    final normalized = Map<String, Object?>.from(payload);
    final media = Map<String, Object?>.from(_asMap(normalized['media']));
    for (final key in const [
      'url',
      'file_path',
      'name',
      'mime',
      'size',
      'width',
      'height',
      'duration',
      'cover_url',
      'voice_url',
      'audio_url',
      'video_url',
      'file_url',
    ]) {
      final value = _value(normalized, [key], fallback: _value(media, [key]));
      if (value.isNotEmpty) {
        normalized[key] = value;
        media[key] = value;
      }
    }
    if (contentType == ChatContentTypes.voice) {
      final filePath = _value(normalized, ['file_path']);
      final voiceUrl = _value(normalized, [
        'voice_url',
        'audio_url',
        'url',
      ], fallback: filePath);
      if (voiceUrl.isNotEmpty) {
        normalized['voice_url'] = voiceUrl;
        normalized['audio_url'] = voiceUrl;
        media['voice_url'] = voiceUrl;
        media['audio_url'] = voiceUrl;
        media['url'] = _value(normalized, ['url'], fallback: voiceUrl);
      }
      final mime = _value(normalized, [
        'mime',
      ], fallback: _value(media, ['mime']));
      if (mime.isEmpty || mime == 'audio/*') {
        normalized['mime'] = 'audio/mp4';
        media['mime'] = 'audio/mp4';
      }
      normalized['content'] = _value(normalized, ['content'], fallback: '[语音]');
    }
    if (contentType == ChatContentTypes.video) {
      final videoUrl = _value(normalized, [
        'video_url',
        'url',
      ], fallback: _value(normalized, ['file_path']));
      if (videoUrl.isNotEmpty) {
        normalized['video_url'] = videoUrl;
        media['video_url'] = videoUrl;
      }
      normalized['content'] = _value(normalized, ['content'], fallback: '[视频]');
    }
    if (contentType == ChatContentTypes.image) {
      normalized['content'] = _value(normalized, ['content'], fallback: '[图片]');
    }
    if (contentType == ChatContentTypes.file) {
      normalized['content'] = _value(normalized, ['content'], fallback: '[文件]');
    }
    normalized['media'] = media;
    return normalized;
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

  int _timestampSeconds(Object? value) {
    final millis = _timestampMs(value);
    return millis <= 0 ? 0 : millis ~/ 1000;
  }

  String _payloadContent(Map<String, Object?> payload) {
    final content = payload['content']?.toString() ?? '';
    final contentType = payload['content_type']?.toString() ?? '';
    if (content.isNotEmpty &&
        contentType != ChatContentTypes.redPacket &&
        contentType != ChatContentTypes.transfer &&
        contentType != ChatContentTypes.redPacketReceived &&
        contentType != ChatContentTypes.transferReceived) {
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
      ChatContentTypes.redPacketReceived => _paymentReceiptContent(
        payload,
        action: ChatContentTypes.redPacketReceived,
      ),
      ChatContentTypes.transferReceived => _paymentReceiptContent(
        payload,
        action: ChatContentTypes.transferReceived,
      ),
      ChatContentTypes.call => _callContent(payload),
      ChatContentTypes.walletNotice => _walletNoticeConversationText(payload),
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
    if (contentType == ChatContentTypes.call) {
      return _callContent({
        ...payload,
        if (content.isNotEmpty) 'content': content,
      });
    }
    if (contentType == ChatContentTypes.walletNotice) {
      return _walletNoticeConversationText(payload);
    }
    return content.isNotEmpty ? content : _payloadContent(payload);
  }

  String _callContent(Map<String, Object?> payload) {
    final direct = payload['content']?.toString().trim() ?? '';
    if (direct.isNotEmpty && direct != '[消息]') {
      return direct;
    }
    final call = _asMap(payload['call']);
    final status = _value(call, [
      'status',
    ], fallback: _value(payload, ['call_status', 'status'])).toLowerCase();
    if (status == 'canceled' || status == 'cancelled') {
      return '已取消';
    }
    if (status == 'rejected') {
      return '已拒绝';
    }
    if (status == 'missed' || status == 'timeout') {
      return '未接听';
    }
    if (status == 'failed') {
      return '通话异常结束';
    }
    final mediaType = _value(call, [
      'media_type',
    ], fallback: _value(payload, ['media_type']));
    final callType = _value(call, [
      'call_type',
    ], fallback: _value(payload, ['call_type']));
    final media = mediaType == 'video' ? '视频通话' : '语音通话';
    final title = callType == 'group' ? '群$media' : media;
    final duration = _intValue(call, [
      'duration',
    ], fallback: _intValue(payload, ['duration']));
    return '$title ${_callDurationText(duration)}';
  }

  String _callDurationText(int seconds) {
    final normalized = max(0, seconds);
    final hours = normalized ~/ 3600;
    final minutes = (normalized % 3600) ~/ 60;
    final remain = normalized % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${two(minutes)}:${two(remain)}';
    }
    return '${two(minutes)}:${two(remain)}';
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

  Map<String, Object?> _walletNoticePayload(Map<String, Object?> payload) {
    final notice = _asMap(payload['wallet_notice']);
    return notice.isNotEmpty ? notice : payload;
  }

  String _walletNoticeConversationText(Map<String, Object?> payload) {
    final notice = _walletNoticePayload(payload);
    final scene = _value(notice, ['scene', 'type']);
    final title = _value(notice, ['title']);
    final isRisk = _walletNoticeIsRisk(scene, title);
    final isCollect = scene == 'scan_collect_success' || title.contains('收款');
    final summary = _value(notice, ['summary', 'content', 'remark']);
    if (summary.isNotEmpty) {
      if (isRisk) {
        return '[${title.isEmpty ? '钱包通知' : title}]$summary';
      }
      return '${isCollect ? '[收款]' : '[付款]'}$summary';
    }
    final amount = _value(notice, ['amount_label', 'amount']);
    if (amount.isNotEmpty) {
      if (isRisk) {
        return '[${title.isEmpty ? '钱包通知' : title}]$amount';
      }
      return '${isCollect ? '[收款]' : '[付款]'}${isCollect ? '收款到账' : '扫码付款成功'} $amount';
    }
    if (isRisk) {
      return '[${title.isEmpty ? '钱包通知' : title}]';
    }
    return isCollect ? '[收款]收款到账' : '[付款]扫码付款成功';
  }

  bool _walletNoticeIsRisk(String scene, String title) {
    return scene == 'wallet_lock' ||
        scene == 'wallet_unlock' ||
        scene == 'wallet_freeze' ||
        scene == 'wallet_unfreeze' ||
        title.contains('钱包') ||
        title.contains('冻结') ||
        title.contains('解冻');
  }

  String _paymentReceiptContent(
    Map<String, Object?> payload, {
    required String action,
  }) {
    final content = payload['content']?.toString().trim() ?? '';
    if (content.isNotEmpty &&
        content != '[消息]' &&
        content != '[领取红包]' &&
        content != '已领取红包' &&
        content != '[已收款]' &&
        content != '已收款') {
      return content;
    }
    final receipt = _asMap(payload['receipt']);
    final nestedKey = action == ChatContentTypes.redPacketReceived
        ? 'red_packet'
        : 'transfer';
    final nested = {
      ..._asMap(payload[nestedKey]),
      ..._asMap(receipt[nestedKey]),
    };
    final currentUserId = _session?.userId.toString() ?? '';
    final actorId = _value(
      payload,
      ['actor_id'],
      fallback: _value(receipt, [
        'operator_id',
        'reader_id',
        'receiver_id',
        'actor_id',
        'user_id',
      ], fallback: _value(nested, ['receiver_id'])),
    );
    final senderId = _value(payload, [
      'source_sender_id',
      'original_sender_id',
    ], fallback: _value(nested, ['sender_id']));
    final actorIsCurrentUser =
        _boolValue(payload['actor_is_me']) ||
        (actorId.isNotEmpty && actorId == currentUserId);
    final senderIsCurrentUser =
        _boolValue(payload['sender_is_me']) ||
        (senderId.isNotEmpty && senderId == currentUserId);
    final actorName = _displayNameFromSources([
      receipt,
      nested,
      payload,
    ], fallback: _profileDisplayName(actorId, fallback: '对方'));
    final senderName = _displayNameFromSources([
      nested,
      receipt,
      payload,
    ], fallback: _profileDisplayName(senderId, fallback: '对方'));
    return _paymentActionReceiptText(
      action: action,
      actorIsCurrentUser: actorIsCurrentUser,
      actorName: actorName,
      senderIsCurrentUser: senderIsCurrentUser,
      senderName: senderName,
    );
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
    _networkReconnectTimer?.cancel();
    _connectionStableTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    unawaited(stop());
    unawaited(_messageSound.dispose());
    unawaited(_messageEvents.close());
    unawaited(_presenceEvents.close());
    unawaited(_callEvents.close());
    unawaited(_friendEvents.close());
    super.dispose();
  }
}

class BusinessImCallEvent {
  const BusinessImCallEvent({required this.source, required this.event});

  final String source;
  final LiveKitCallEvent event;
}

class BusinessImFriendEvent {
  const BusinessImFriendEvent({
    required this.source,
    required this.event,
    required this.payload,
  });

  final String source;
  final String event;
  final Map<String, Object?> payload;
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
