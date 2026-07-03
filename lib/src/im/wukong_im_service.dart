import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wukongimfluttersdk/common/options.dart';
import 'package:wukongimfluttersdk/entity/channel.dart';
import 'package:wukongimfluttersdk/entity/conversation.dart';
import 'package:wukongimfluttersdk/entity/msg.dart';
import 'package:wukongimfluttersdk/model/wk_text_content.dart';
import 'package:wukongimfluttersdk/proto/proto.dart';
import 'package:wukongimfluttersdk/type/const.dart';
import 'package:wukongimfluttersdk/wkim.dart';

import '../core/api_client.dart';
import '../core/app_logger.dart';
import '../core/app_config.dart';
import '../core/models.dart';
import 'bim_message_content.dart';
import 'im_message_types.dart';

class WukongImService extends ChangeNotifier {
  WukongImService({required ApiClient api}) : _api = api;

  static const _listenerKey = 'bim_client';

  final ApiClient _api;
  UserSession? _session;
  String _device = '';
  bool _listenersAttached = false;
  bool _contentRegistered = false;
  bool _setupCompleted = false;
  String _startedKey = '';
  Future<void>? _startRequest;
  int _status = WKConnectStatus.fail;
  String _statusText = '未连接';
  String? _lastError;
  Timer? _refreshDebounce;
  Timer? _connectionWatchdog;
  List<Map<String, Object?>> _latestConversations = const [];
  int _conversationVersion = 0;
  int _messageVersion = 0;
  DateTime _statusChangedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastReconnectAt;
  DateTime? _backgroundedAt;
  int _connectAttempt = 0;
  DateTime? _lastConversationSyncAt;
  String _lastConversationSyncKey = '';
  WKSyncConversation? _lastConversationSyncResult;
  Future<WKSyncConversation>? _conversationSyncRequest;
  final Map<String, Future<WKSyncChannelMsg>> _channelSyncRequests =
      <String, Future<WKSyncChannelMsg>>{};
  final Map<String, String> _groupIdsByChannel = <String, String>{};

  bool get isConnected => _isConnectedStatus(_status);
  bool get isStarted => _setupCompleted && _isStartedStatus(_status);
  String get statusText => _statusText;
  String? get lastError => _lastError;
  List<Map<String, Object?>> get latestConversations => _latestConversations;
  int get conversationVersion => _conversationVersion;
  int messageVersion({required String channelID, required int channelType}) =>
      _channelMessageVersions[_messageKey(channelID, channelType)] ?? 0;
  final Map<String, int> _channelMessageVersions = <String, int>{};

  Future<void> start(UserSession session, {required String device}) async {
    final existingRequest = _startRequest;
    if (existingRequest != null) {
      AppLogger.info('im', 'reuse start request');
      return existingRequest;
    }
    _startRequest = _startInternal(session, device: device);
    try {
      await _startRequest;
    } finally {
      _startRequest = null;
    }
  }

  Future<void> _startInternal(
    UserSession session, {
    required String device,
  }) async {
    AppLogger.info('im', 'start requested');
    final chat = session.chat;
    if (chat == null || chat.uid.isEmpty || chat.token.isEmpty) {
      _lastError = 'IM 登录信息为空';
      AppLogger.error('im', 'start failed', error: _lastError);
      _setStatus(WKConnectStatus.fail);
      return;
    }
    if (chat.route.tcpAddr.isEmpty) {
      _lastError = 'IM TCP 地址未配置';
      AppLogger.error('im', 'start failed', error: _lastError);
      _setStatus(WKConnectStatus.fail);
      return;
    }
    final startKey = [
      chat.uid,
      chat.token,
      chat.route.tcpAddr,
      chat.deviceFlag,
      device,
    ].join('|');
    if (_startedKey == startKey &&
        _setupCompleted &&
        _isStartedStatus(_status)) {
      _session = session;
      _device = device;
      AppLogger.info(
        'im',
        'start skipped same connection',
        data: {'status': _statusText, 'uid': chat.uid},
      );
      ensureConnected();
      await refreshLocalConversations(notify: false);
      return;
    }

    _session = session;
    _device = device;
    _registerBusinessContent();
    _attachListeners();

    final options = Options.newDefault(
      chat.uid,
      chat.token,
      addr: chat.route.tcpAddr,
    );
    options.deviceFlag = chat.deviceFlag;
    options.debug = false;
    // SDK 使用 TCP host:port；业务接口返回多个地址时，客户端只给 SDK tcp_addr。
    options.getAddr = (complete) async => complete(chat.route.tcpAddr);

    final initialized = await WKIM.shared.setup(options);
    if (!initialized) {
      _lastError = 'IM 本地数据库初始化失败';
      _setupCompleted = false;
      _startedKey = '';
      AppLogger.error('im', 'setup failed', error: _lastError);
      _setStatus(WKConnectStatus.fail);
      return;
    }

    _lastError = null;
    _setupCompleted = true;
    _startedKey = startKey;
    AppLogger.info(
      'im',
      'connect prepared',
      data: {
        'uid': chat.uid,
        'tcp': chat.route.tcpAddr,
        'device_flag': chat.deviceFlag,
      },
    );
    _connectViaManager(source: 'start', force: true);
    await refreshLocalConversations();
  }

  Future<void> stop({bool logout = false}) async {
    AppLogger.info('im', 'stop', data: {'logout': logout});
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
    _connectionWatchdog?.cancel();
    _connectionWatchdog = null;
    if (_listenersAttached) {
      WKIM.shared.connectionManager.removeOnConnectionStatus(_listenerKey);
      WKIM.shared.conversationManager.removeOnRefreshMsgListListener(
        _listenerKey,
      );
      WKIM.shared.messageManager.removeNewMsgListener(_listenerKey);
      WKIM.shared.messageManager.removeOnRefreshMsgListener(_listenerKey);
      WKIM.shared.cmdManager.removeCmdListener(_listenerKey);
      _listenersAttached = false;
    }
    WKIM.shared.connectionManager.disconnect(logout);
    _session = null;
    _device = '';
    _setupCompleted = false;
    _startedKey = '';
    _startRequest = null;
    _latestConversations = const [];
    _conversationVersion++;
    _messageVersion++;
    _channelMessageVersions.clear();
    _lastConversationSyncAt = null;
    _lastConversationSyncKey = '';
    _lastConversationSyncResult = null;
    _conversationSyncRequest = null;
    _channelSyncRequests.clear();
    _lastError = null;
    _setStatus(WKConnectStatus.fail);
  }

  String newClientMsgNo() => WKIM.shared.messageManager.generateClientMsgNo();

  void ensureConnected({bool force = false}) {
    _ensureConnected(source: 'ensure', force: force);
  }

  void resumeConnection() {
    final seconds = DateTime.now().difference(_statusChangedAt).inSeconds;
    if (_isConnectedStatus(_status)) {
      ensureConnected();
      return;
    }
    final force =
        _status == WKConnectStatus.connecting ||
        _status == WKConnectStatus.kicked ||
        seconds >= 6;
    _ensureConnected(source: 'resume', force: force);
  }

  void onAppBackgrounded(String state) {
    _backgroundedAt = DateTime.now();
    _connectionWatchdog?.cancel();
    _connectionWatchdog = null;
    AppLogger.info(
      'im',
      'app backgrounded',
      data: {'state': state, 'status': _statusText},
    );
  }

  void _ensureConnected({required String source, bool force = false}) {
    final current = _session;
    if (!_setupCompleted || current?.chat == null) {
      AppLogger.warn(
        'im',
        'ensure connected skipped',
        data: {
          'source': source,
          'setup': _setupCompleted,
          'has_session': current != null,
        },
      );
      return;
    }
    final now = DateTime.now();
    if (!force && _isConnectedStatus(_status)) {
      AppLogger.info(
        'im',
        'ensure connected already connected',
        data: {
          'source': source,
          'status': _statusText,
          'background_seconds': _backgroundSeconds(),
        },
      );
      unawaited(refreshLocalConversations(notify: false));
      return;
    }
    if (!force &&
        _status == WKConnectStatus.connecting &&
        now.difference(_statusChangedAt) < const Duration(seconds: 8)) {
      AppLogger.info(
        'im',
        'ensure connected wait current attempt',
        data: {'source': source, 'status': _statusText},
      );
      _scheduleConnectionWatchdog(source);
      return;
    }
    final lastReconnect = _lastReconnectAt;
    if (!force &&
        lastReconnect != null &&
        now.difference(lastReconnect) < const Duration(seconds: 3)) {
      AppLogger.info(
        'im',
        'ensure connected throttled',
        data: {'source': source, 'status': _statusText},
      );
      return;
    }
    _connectViaManager(source: source, force: force);
  }

  void _connectViaManager({required String source, bool force = false}) {
    _lastReconnectAt = DateTime.now();
    _connectAttempt++;
    AppLogger.warn(
      'im',
      'connection manager connect',
      data: {
        'source': source,
        'attempt': _connectAttempt,
        'status': _statusText,
        'force': force,
        'background_seconds': _backgroundSeconds(),
      },
    );
    if (force) {
      WKIM.shared.connectionManager.disconnect(false);
    }
    WKIM.shared.connectionManager.connect();
    _scheduleConnectionWatchdog(source);
    unawaited(
      refreshLocalConversations(notify: false).catchError((Object error) {
        AppLogger.warn(
          'im',
          'ensure connected conversation refresh failed',
          data: {'error': error.toString()},
        );
        return <Map<String, Object?>>[];
      }),
    );
  }

  void _scheduleConnectionWatchdog(String source) {
    _connectionWatchdog?.cancel();
    _connectionWatchdog = Timer(const Duration(seconds: 12), () {
      if (!_setupCompleted || _isConnectedStatus(_status)) {
        return;
      }
      AppLogger.warn(
        'im',
        'connection watchdog reconnect',
        data: {
          'source': source,
          'status': _statusText,
          'seconds': DateTime.now().difference(_statusChangedAt).inSeconds,
        },
      );
      _ensureConnected(source: 'watchdog:$source', force: true);
    });
  }

  Future<List<Map<String, Object?>>> localMessages({
    required String channelID,
    required int channelType,
    String groupId = '',
    int limit = 50,
  }) async {
    if (channelType == WKChannelType.group && groupId.isNotEmpty) {
      _groupIdsByChannel[channelID] = groupId;
    }
    final messages = await _getOrSyncHistory(
      channelID: channelID,
      channelType: channelType,
      limit: limit,
    );
    messages.sort((a, b) => a.orderSeq.compareTo(b.orderSeq));
    final start = messages.length > limit ? messages.length - limit : 0;
    return messages.skip(start).map(_messageToMap).toList();
  }

  Future<Map<String, Object?>?> localMessageByClientMsgNo(
    String clientMsgNo,
  ) async {
    if (clientMsgNo.isEmpty) {
      return null;
    }
    final message = await WKIM.shared.messageManager.getWithClientMsgNo(
      clientMsgNo,
    );
    return message == null ? null : _messageToMap(message);
  }

  Future<void> sendTextMessage({
    required String channelID,
    required int channelType,
    required String content,
    List<String> mentionUids = const [],
    bool mentionAll = false,
    String replyClientMsgNo = '',
    bool burnAfterRead = false,
    int burnAfterReadSeconds = 0,
  }) async {
    if (!_setupCompleted) {
      throw ApiException('IM 未初始化');
    }
    if (!_isConnectedStatus(_status)) {
      ensureConnected(force: true);
      throw ApiException('IM 正在连接，请稍后重试');
    }
    final text = WKTextContent(content);
    text.contentType = ImMessageTypes.text;
    if (mentionAll || mentionUids.isNotEmpty) {
      text.mentionInfo = WKMentionInfo()
        ..mentionAll = mentionAll
        ..uids = mentionUids;
    }
    if (replyClientMsgNo.isNotEmpty) {
      final replyMessage = await WKIM.shared.messageManager
          .getWithClientMsgNo(replyClientMsgNo)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      text.reply = WKReply()
        ..rootMid = replyMessage?.messageID ?? ''
        ..messageId = replyMessage?.messageID ?? replyClientMsgNo
        ..messageSeq = replyMessage?.messageSeq ?? 0
        ..fromUID = replyMessage?.fromUID ?? ''
        ..payload = replyMessage?.messageContent;
    }
    final options = WKSendOptions();
    options.setting = Setting()..receipt = 1;
    if (burnAfterRead && burnAfterReadSeconds > 0) {
      options.expire = burnAfterReadSeconds;
    }
    AppLogger.info(
      'im',
      'sdk send text',
      data: {
        'channel_id': channelID,
        'channel_type': channelType,
        'mention_count': mentionUids.length,
        'mention_all': mentionAll,
        'reply': replyClientMsgNo.isNotEmpty,
        'burn_after_read': burnAfterRead,
      },
    );
    await WKIM.shared.messageManager.sendWithOption(
      text,
      WKChannel(channelID, channelType),
      options,
    );
  }

  Future<void> sendBusinessMessage({
    required String channelID,
    required int channelType,
    required int contentType,
    Map<String, Object?> payload = const {},
    bool receipt = true,
    bool burnAfterRead = false,
    int burnAfterReadSeconds = 0,
    String replyClientMsgNo = '',
  }) async {
    if (!_setupCompleted) {
      throw ApiException('IM 未初始化');
    }
    if (!_isConnectedStatus(_status)) {
      ensureConnected(force: true);
      throw ApiException('IM 正在连接，请稍后重试');
    }
    final cleanPayload = <String, dynamic>{
      for (final entry in payload.entries)
        if (entry.value != null && entry.value.toString().isNotEmpty)
          entry.key: entry.value,
      'type': contentType,
    };
    final content = BimMessageContent(contentType, payload: cleanPayload);
    if (replyClientMsgNo.isNotEmpty) {
      final replyMessage = await WKIM.shared.messageManager
          .getWithClientMsgNo(replyClientMsgNo)
          .timeout(const Duration(seconds: 2), onTimeout: () => null);
      content.reply = WKReply()
        ..rootMid = replyMessage?.messageID ?? ''
        ..messageId = replyMessage?.messageID ?? replyClientMsgNo
        ..messageSeq = replyMessage?.messageSeq ?? 0
        ..fromUID = replyMessage?.fromUID ?? ''
        ..payload = replyMessage?.messageContent;
    }
    final options = WKSendOptions();
    options.setting = Setting()..receipt = receipt ? 1 : 0;
    if (burnAfterRead && burnAfterReadSeconds > 0) {
      options.expire = burnAfterReadSeconds;
    }
    AppLogger.info(
      'im',
      'sdk send business message',
      data: {
        'channel_id': channelID,
        'channel_type': channelType,
        'content_type': contentType,
        'payload_keys': cleanPayload.keys.toList(),
      },
    );
    await WKIM.shared.messageManager.sendWithOption(
      content,
      WKChannel(channelID, channelType),
      options,
    );
  }

  Future<void> syncChannelAfterSend({
    required String channelID,
    required int channelType,
    String groupId = '',
  }) async {
    if (channelType == WKChannelType.group && groupId.isNotEmpty) {
      _groupIdsByChannel[channelID] = groupId;
    }
    final maxSeq = await WKIM.shared.messageManager
        .getMaxMessageSeq(channelID, channelType)
        .timeout(const Duration(seconds: 3), onTimeout: () => 0);
    final completer = Completer<void>();
    AppLogger.info(
      'im',
      'sync channel after send',
      data: {
        'channel_id': channelID,
        'channel_type': channelType,
        'max_seq': maxSeq,
      },
    );
    WKIM.shared.messageManager.setSyncChannelMsgListener(
      channelID,
      channelType,
      0,
      0,
      50,
      0,
      (sync) {
        AppLogger.info(
          'im',
          'sync channel after send callback',
          data: {
            'channel_id': channelID,
            'channel_type': channelType,
            'count': sync?.messages?.length ?? 0,
            'more': sync?.more ?? 0,
          },
        );
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );
    await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        AppLogger.warn(
          'im',
          'sync channel after send timeout',
          data: {'channel_id': channelID, 'channel_type': channelType},
        );
      },
    );
    _markMessageChannel(
      source: 'send_sync',
      channelID: channelID,
      channelType: channelType,
    );
    await refreshLocalConversations();
  }

  Future<List<dynamic>> _getOrSyncHistory({
    required String channelID,
    required int channelType,
    required int limit,
  }) {
    final completer = Completer<List<dynamic>>();
    WKIM.shared.messageManager.getOrSyncHistoryMessages(
      channelID,
      channelType,
      0,
      true,
      0,
      limit,
      0,
      (messages) {
        if (!completer.isCompleted) {
          completer.complete(messages);
        }
      },
      () {
        AppLogger.info(
          'im',
          'history sync requested',
          data: {'channel_id': channelID, 'channel_type': channelType},
        );
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => <dynamic>[],
    );
  }

  Future<List<Map<String, Object?>>> refreshLocalConversations({
    bool notify = true,
  }) async {
    final list = await WKIM.shared.conversationManager.getAll().timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        AppLogger.warn('im', 'conversation getAll timeout');
        return <WKUIConversationMsg>[];
      },
    );
    _latestConversations = await _mapConversations(list).timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        AppLogger.warn('im', 'conversation map timeout');
        return <Map<String, Object?>>[];
      },
    );
    AppLogger.info(
      'im',
      'local conversations refreshed',
      data: {'count': _latestConversations.length, 'notify': notify},
    );
    if (notify) {
      _conversationVersion++;
      notifyListeners();
    }
    return _latestConversations;
  }

  void _registerBusinessContent() {
    if (_contentRegistered) {
      return;
    }
    final customTypes = <int>[
      ImMessageTypes.voice,
      ImMessageTypes.video,
      ImMessageTypes.file,
      ImMessageTypes.transfer,
      ImMessageTypes.redPacket,
      ImMessageTypes.redPacketReceived,
      ImMessageTypes.transferReceived,
      ImMessageTypes.emoji,
      ImMessageTypes.gif,
      ImMessageTypes.sticker,
      ImMessageTypes.contactCard,
      ImMessageTypes.recall,
    ];
    for (final type in customTypes) {
      WKIM.shared.messageManager.registerMsgContent(type, (dynamic data) {
        final payload = data is Map
            ? data.cast<String, dynamic>()
            : <String, dynamic>{};
        return BimMessageContent(type).decodeJson(payload);
      });
    }
    _contentRegistered = true;
  }

  void _attachListeners() {
    if (_listenersAttached) {
      return;
    }
    WKIM.shared.connectionManager.addOnConnectionStatus(_listenerKey, (
      status,
      reasonCode,
      connectInfo,
    ) {
      _lastError = reasonCode == null ? null : '连接错误 $reasonCode';
      AppLogger.info(
        'im',
        'connection status',
        data: {
          'status': status,
          'reason_code': reasonCode,
          'node_id': connectInfo?.nodeId ?? '',
          'attempt': _connectAttempt,
        },
      );
      _setStatus(status);
      if (_isConnectedStatus(status)) {
        _lastError = null;
        _connectionWatchdog?.cancel();
        _connectionWatchdog = null;
        unawaited(refreshLocalConversations(notify: false));
      } else if (status == WKConnectStatus.fail ||
          status == WKConnectStatus.noNetwork) {
        _scheduleConnectionWatchdog('status:$status');
      }
    });
    WKIM.shared.conversationManager.addOnRefreshMsgListListener(_listenerKey, (
      messages,
    ) async {
      _markMessageChannels(source: 'conversation_listener', messages: messages);
      _latestConversations = await _mapConversations(messages);
      _conversationVersion++;
      AppLogger.info(
        'im',
        'conversation refresh listener',
        data: {'count': _latestConversations.length},
      );
      notifyListeners();
    });
    WKIM.shared.messageManager.addOnNewMsgListener(_listenerKey, (messages) {
      AppLogger.info(
        'im',
        'new message listener',
        data: {
          'count': messages.length,
          'channels': _messageChannelList(messages),
        },
      );
      _markMessageChannels(source: 'new_message', messages: messages);
      _debouncedRefresh();
    });
    WKIM.shared.messageManager.addOnRefreshMsgListener(_listenerKey, (message) {
      _markMessageChannel(
        source: 'message_refresh',
        channelID: message.channelID,
        channelType: message.channelType,
      );
      _debouncedRefresh();
    });
    WKIM.shared.messageManager.addOnMsgInsertedListener((message) {
      _markMessageChannel(
        source: 'message_inserted',
        channelID: message.channelID,
        channelType: message.channelType,
      );
      _debouncedRefresh();
    });
    WKIM.shared.cmdManager.addOnCmdListener(_listenerKey, (cmd) {
      // 回执、撤回、阅后即焚等命令消息由服务端生成；客户端收到后刷新本地列表。
      _debouncedRefresh();
    });
    WKIM.shared.conversationManager.addOnSyncConversationListener(
      _syncConversations,
    );
    WKIM.shared.messageManager.addOnSyncChannelMsgListener(
      _syncChannelMessages,
    );
    WKIM.shared.channelManager.addOnGetChannelListener(_loadChannelInfo);
    _listenersAttached = true;
  }

  Future<void> _syncConversations(
    String lastMsgSeqs,
    int msgCount,
    int version,
    Function(WKSyncConversation) back,
  ) async {
    final current = _session;
    if (current == null || _device.isEmpty) {
      back(WKSyncConversation());
      return;
    }
    final syncKey = '$lastMsgSeqs|$msgCount|$version';
    final now = DateTime.now();
    final lastAt = _lastConversationSyncAt;
    if (_conversationSyncRequest != null) {
      AppLogger.info(
        'im',
        'reuse sync conversations request',
        data: {'key': syncKey},
      );
      back(await _conversationSyncRequest!);
      return;
    }
    if (lastAt != null &&
        syncKey == _lastConversationSyncKey &&
        _lastConversationSyncResult != null &&
        now.difference(lastAt) < const Duration(seconds: 5)) {
      AppLogger.warn(
        'im',
        'reuse recent sync conversations result',
        data: {'key': syncKey},
      );
      back(_lastConversationSyncResult!);
      return;
    }
    try {
      AppLogger.info(
        'im',
        'sync conversations start',
        data: {
          'last_msg_seqs': lastMsgSeqs,
          'msg_count': msgCount,
          'version': version,
        },
      );
      _conversationSyncRequest = _loadSyncConversations(
        current: current,
        msgCount: msgCount,
      );
      final sync = await _conversationSyncRequest!;
      _lastConversationSyncAt = DateTime.now();
      _lastConversationSyncKey = syncKey;
      _lastConversationSyncResult = sync;
      AppLogger.info(
        'im',
        'sync conversations success',
        data: {'count': sync.conversations?.length ?? 0},
      );
      back(sync);
    } catch (error) {
      _lastError = error.toString();
      AppLogger.error('im', 'sync conversations failed', error: error);
      back(WKSyncConversation());
      notifyListeners();
    } finally {
      _conversationSyncRequest = null;
    }
  }

  Future<void> _syncChannelMessages(
    String channelID,
    int channelType,
    int startMessageSeq,
    int endMessageSeq,
    int limit,
    int pullMode,
    Function(WKSyncChannelMsg?) back,
  ) async {
    final current = _session;
    if (current == null || _device.isEmpty) {
      back(WKSyncChannelMsg());
      return;
    }
    final requestKey = [
      channelID,
      channelType,
      startMessageSeq,
      endMessageSeq,
      limit,
      pullMode,
    ].join('|');
    final existingRequest = _channelSyncRequests[requestKey];
    if (existingRequest != null) {
      AppLogger.info(
        'im',
        'reuse sync channel messages request',
        data: {'key': requestKey},
      );
      back(await existingRequest);
      return;
    }
    try {
      AppLogger.info(
        'im',
        'sync channel messages start',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'start_seq': startMessageSeq,
          'end_seq': endMessageSeq,
          'limit': limit,
          'pull_mode': pullMode,
        },
      );
      final request = _loadSyncChannelMessages(
        current: current,
        channelID: channelID,
        channelType: channelType,
        startMessageSeq: startMessageSeq,
        endMessageSeq: endMessageSeq,
        limit: limit,
        pullMode: pullMode,
      );
      _channelSyncRequests[requestKey] = request;
      final sync = await request;
      AppLogger.info(
        'im',
        'sync channel messages success',
        data: {'channel_id': channelID, 'count': sync.messages?.length ?? 0},
      );
      back(sync);
    } catch (error) {
      final message = error.toString();
      if (!message.contains('client_msg_no已被其它消息内容占用')) {
        _lastError = message;
      }
      AppLogger.error(
        'im',
        'sync channel messages failed',
        error: error,
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'ignored': message.contains('client_msg_no已被其它消息内容占用'),
        },
      );
      back(WKSyncChannelMsg());
      if (!message.contains('client_msg_no已被其它消息内容占用')) {
        notifyListeners();
      }
    } finally {
      _channelSyncRequests.remove(requestKey);
    }
  }

  Future<void> _loadChannelInfo(
    String channelID,
    int channelType,
    Function(WKChannel) back,
  ) async {
    final channel = WKChannel(channelID, channelType);
    try {
      final current = _session;
      if (current == null || _device.isEmpty) {
        back(channel);
        return;
      }
      if (channelType == WKChannelType.group) {
        final groups = await _api.groups(session: current, device: _device);
        _rememberGroupChannels(groups);
        final group = groups.cast<Map<String, Object?>?>().firstWhere(
          (item) =>
              item?['channel_id']?.toString() == channelID ||
              item?['id']?.toString() == _groupIdFromChannel(channelID),
          orElse: () => null,
        );
        channel.channelName = group?['name']?.toString() ?? '';
        channel.avatar = group?['avatar']?.toString() ?? '';
      } else {
        final friends = await _api.friends(session: current, device: _device);
        final userId = _userIdFromUid(channelID);
        final friend = friends.cast<Map<String, Object?>?>().firstWhere((item) {
          final profile = _friendProfile(item);
          return item?['uid']?.toString() == channelID ||
              profile['uid']?.toString() == channelID ||
              item?['friend_id']?.toString() == userId ||
              profile['userid']?.toString() == userId ||
              profile['user_id']?.toString() == userId ||
              profile['id']?.toString() == userId;
        }, orElse: () => null);
        final profile = _friendProfile(friend);
        channel.channelName = friend?['remark']?.toString().isNotEmpty == true
            ? friend!['remark'].toString()
            : profile['nickname']?.toString().isNotEmpty == true
            ? profile['nickname'].toString()
            : profile['username']?.toString() ?? '';
        channel.channelRemark = friend?['remark']?.toString() ?? '';
        channel.avatar =
            profile['usertx']?.toString() ??
            profile['avatar']?.toString() ??
            '';
        channel.username = profile['username']?.toString() ?? '';
        channel.follow = friend == null ? 0 : 1;
      }
    } catch (error) {
      // 频道资料失败不影响消息收发，SDK 仍能用 channelID 展示。
      AppLogger.warn(
        'im',
        'load channel info failed',
        data: {
          'channel_id': channelID,
          'channel_type': channelType,
          'error': error.toString(),
        },
      );
    }
    back(channel);
  }

  Future<WKSyncConversation> _loadSyncConversations({
    required UserSession current,
    required int msgCount,
  }) async {
    final list = await _api.conversations(
      session: current,
      device: _device,
      limit: msgCount <= 0 ? 50 : msgCount,
    );
    _rememberGroupChannels(list);
    return WKSyncConversation()
      ..uid = current.chat?.uid ?? ''
      ..conversations = _buildSyncConversations(list);
  }

  Future<WKSyncChannelMsg> _loadSyncChannelMessages({
    required UserSession current,
    required String channelID,
    required int channelType,
    required int startMessageSeq,
    required int endMessageSeq,
    required int limit,
    required int pullMode,
  }) async {
    final data = channelType == WKChannelType.group
        ? await _api.groupMessagePage(
            session: current,
            device: _device,
            groupId: _groupIdFromChannel(channelID),
            startMessageSeq: startMessageSeq,
            endMessageSeq: endMessageSeq,
            limit: limit <= 0 ? 50 : limit,
            pullMode: pullMode,
          )
        : await _api.personMessagePage(
            session: current,
            device: _device,
            receiverId: _userIdFromUid(channelID),
            startMessageSeq: startMessageSeq,
            endMessageSeq: endMessageSeq,
            limit: limit <= 0 ? 50 : limit,
            pullMode: pullMode,
          );
    final messages = _buildSyncMessages(data['list']);
    final sync = WKSyncChannelMsg()
      ..messages = messages
      ..more = _readInt(data, 'more');
    if (messages.isNotEmpty) {
      sync.startMessageSeq = messages.first.messageSeq;
      sync.endMessageSeq = messages.last.messageSeq;
    }
    return sync;
  }

  List<WKSyncConvMsg> _buildSyncConversations(List<Map<String, Object?>> list) {
    final result = <WKSyncConvMsg>[];
    for (final item in list) {
      final channelID = item['channel_id']?.toString() ?? '';
      if (channelID.isEmpty) {
        continue;
      }
      final payload = _payloadFromConversation(item);
      final timestamp = _timestampFromText(item['msg_time']);
      final msg = WKSyncConvMsg()
        ..channelID = channelID
        ..channelType = _readInt(item, 'channel_type')
        ..lastClientMsgNO = item['last_client_msg_no']?.toString() ?? ''
        ..lastMsgSeq = _readInt(item, 'last_msg_seq')
        ..timestamp = timestamp
        ..unread = _readInt(item, 'unread_quantity')
        ..version = timestamp;
      if (msg.channelType <= 0) {
        msg.channelType = item['conversation_type']?.toString() == 'group'
            ? WKChannelType.group
            : WKChannelType.personal;
      }
      if (msg.lastClientMsgNO.isNotEmpty) {
        msg.recents = [
          WKSyncMsg()
            ..messageID = item['message_id']?.toString() ?? ''
            ..clientMsgNO = msg.lastClientMsgNO
            ..channelID = msg.channelID
            ..channelType = msg.channelType
            ..messageSeq = msg.lastMsgSeq
            ..timestamp = timestamp
            ..fromUID = _fromUid(item, msg.channelID, msg.channelType)
            ..payload = payload,
        ];
      }
      result.add(msg);
    }
    return result;
  }

  void _rememberGroupChannels(List<Map<String, Object?>> list) {
    for (final item in list) {
      final channelID = item['channel_id']?.toString() ?? '';
      final groupId =
          item['group_id']?.toString() ?? item['id']?.toString() ?? '';
      if (channelID.isNotEmpty && groupId.isNotEmpty) {
        _groupIdsByChannel[channelID] = groupId;
      }
    }
  }

  List<WKSyncMsg> _buildSyncMessages(Object? value) {
    if (value is! List) {
      return [];
    }
    final result = <WKSyncMsg>[];
    for (final rawItem in value.whereType<Map>()) {
      final item = rawItem.cast<String, Object?>();
      final message = _asMap(item['message']);
      final raw = _asMap(item['raw']);
      final payload = _asMap(message['payload']);
      if (payload.isEmpty && message['content'] != null) {
        payload['content'] = message['content'];
      }
      payload['type'] ??= _contentTypeCode(message['content_type']);
      final sync = WKSyncMsg()
        ..messageID = raw['message_idstr']?.toString().isNotEmpty == true
            ? raw['message_idstr'].toString()
            : raw['message_id']?.toString() ?? message['id']?.toString() ?? ''
        ..clientMsgNO = raw['client_msg_no']?.toString().isNotEmpty == true
            ? raw['client_msg_no'].toString()
            : message['client_msg_no']?.toString() ?? ''
        ..messageSeq = _readInt(raw, 'message_seq') == 0
            ? _readInt(message, 'message_seq')
            : _readInt(raw, 'message_seq')
        ..fromUID = _fromUserUid(item, payload)
        ..channelID =
            raw['channel_id']?.toString() ??
            payload['channel_id']?.toString() ??
            ''
        ..channelType = _readInt(raw, 'channel_type')
        ..timestamp = _timestampFromText(message['create_time'])
        ..payload = payload;
      if (sync.clientMsgNO.isEmpty) {
        continue;
      }
      result.add(sync);
    }
    result.sort((a, b) => a.messageSeq.compareTo(b.messageSeq));
    return result;
  }

  Map<String, dynamic> _payloadFromConversation(Map<String, Object?> item) {
    final payload = _asMap(item['payload']);
    if (payload.isEmpty) {
      payload['content'] = item['content']?.toString() ?? '';
      payload['content_type'] = item['content_type']?.toString() ?? '';
      payload['type'] = _contentTypeCode(payload['content_type']);
      if (item['image_path'] != null) {
        payload['image_path'] = item['image_path'];
      }
      if (item['asset_type'] != null) {
        payload['asset_type'] = item['asset_type'];
      }
    }
    payload['type'] ??= _contentTypeCode(payload['content_type']);
    return payload;
  }

  String _fromUid(
    Map<String, Object?> item,
    String channelID,
    int channelType,
  ) {
    final payload = _asMap(item['payload']);
    final senderUid = payload['sender_uid']?.toString() ?? '';
    if (senderUid.isNotEmpty) {
      return senderUid;
    }
    if (channelType == WKChannelType.personal) {
      return channelID;
    }
    return _session?.chat?.uid ?? '';
  }

  String _fromUserUid(Map<String, Object?> item, Map<String, dynamic> payload) {
    final senderUid = payload['sender_uid']?.toString() ?? '';
    if (senderUid.isNotEmpty) {
      return senderUid;
    }
    final fromUser = _asMap(item['fromUser']);
    final uid = fromUser['uid']?.toString() ?? '';
    if (uid.isNotEmpty) {
      return uid;
    }
    final id =
        fromUser['id']?.toString() ?? fromUser['userid']?.toString() ?? '';
    return id.isEmpty ? '' : _businessUid(id);
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  int _contentTypeCode(Object? contentType) {
    return switch (contentType?.toString()) {
      'text' => ImMessageTypes.text,
      'image' => ImMessageTypes.image,
      'voice' => ImMessageTypes.voice,
      'video' => ImMessageTypes.video,
      'file' => ImMessageTypes.file,
      'transfer' => ImMessageTypes.transfer,
      'red_packet' => ImMessageTypes.redPacket,
      'red_packet_received' => ImMessageTypes.redPacketReceived,
      'transfer_received' => ImMessageTypes.transferReceived,
      'emoji' => ImMessageTypes.emoji,
      'gif' => ImMessageTypes.gif,
      'sticker' => ImMessageTypes.sticker,
      'contact_card' => ImMessageTypes.contactCard,
      'recall' => ImMessageTypes.recall,
      _ => ImMessageTypes.text,
    };
  }

  int _readInt(Map<dynamic, dynamic> map, String key) {
    final value = map[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _timestampFromText(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    final text = value?.toString() ?? '';
    if (text.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      return int.tryParse(text) ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    return parsed.millisecondsSinceEpoch ~/ 1000;
  }

  String _userIdFromUid(String uid) {
    final match = RegExp(r'user(\d+)$').firstMatch(uid);
    return match?.group(1) ?? uid;
  }

  String _groupIdFromChannel(String channelID) {
    return _groupIdsByChannel[channelID] ?? channelID;
  }

  String _businessUid(String userId) {
    return 'app${AppConfig.appId}user$userId';
  }

  Map<String, dynamic> _friendProfile(Map<String, Object?>? item) {
    if (item == null) {
      return <String, dynamic>{};
    }
    final friend = _asMap(item['friend']);
    return friend.isEmpty ? _asMap(item) : friend;
  }

  void _markMessageChannels({
    required String source,
    required List<dynamic> messages,
  }) {
    final changed = <String>{};
    for (final message in messages) {
      final channelID = message.channelID?.toString() ?? '';
      final channelType = message.channelType is int
          ? message.channelType as int
          : int.tryParse(message.channelType?.toString() ?? '') ?? 0;
      if (channelID.isEmpty || channelType <= 0) {
        continue;
      }
      changed.add(_messageKey(channelID, channelType));
      _channelMessageVersions[_messageKey(channelID, channelType)] =
          (_channelMessageVersions[_messageKey(channelID, channelType)] ?? 0) +
          1;
    }
    if (changed.isEmpty) {
      return;
    }
    _messageVersion++;
    AppLogger.info(
      'im',
      'message channels changed',
      data: {
        'source': source,
        'message_version': _messageVersion,
        'channels': changed.toList(),
      },
    );
    notifyListeners();
  }

  void _markMessageChannel({
    required String source,
    required String channelID,
    required int channelType,
  }) {
    if (channelID.isEmpty || channelType <= 0) {
      return;
    }
    final key = _messageKey(channelID, channelType);
    _channelMessageVersions[key] = (_channelMessageVersions[key] ?? 0) + 1;
    _messageVersion++;
    AppLogger.info(
      'im',
      'message channel changed',
      data: {
        'source': source,
        'channel_id': channelID,
        'channel_type': channelType,
        'message_version': _messageVersion,
        'channel_version': _channelMessageVersions[key],
      },
    );
    notifyListeners();
  }

  List<String> _messageChannelList(List<dynamic> messages) {
    final channels = <String>{};
    for (final message in messages) {
      final channelID = message.channelID?.toString() ?? '';
      final channelType = message.channelType?.toString() ?? '';
      if (channelID.isNotEmpty && channelType.isNotEmpty) {
        channels.add('$channelType:$channelID');
      }
    }
    return channels.toList();
  }

  String _messageKey(String channelID, int channelType) {
    return '$channelType:$channelID';
  }

  int _backgroundSeconds() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) {
      return 0;
    }
    return DateTime.now().difference(backgroundedAt).inSeconds;
  }

  void _debouncedRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 180),
      refreshLocalConversations,
    );
  }

  Future<List<Map<String, Object?>>> _mapConversations(
    List<WKUIConversationMsg> list,
  ) async {
    final result = <Map<String, Object?>>[];
    for (final item in list) {
      final channel = await item.getWkChannel();
      final message = await item.getWkMsg();
      final title = _channelTitle(item, channel);
      result.add({
        'conversation_type': item.channelType == WKChannelType.group
            ? 'group'
            : 'private',
        'channel_id': item.channelID,
        'channel_type': item.channelType,
        'name': title,
        'nickname': title,
        'username': title,
        'content':
            message?.messageContent?.displayText() ??
            _fallbackContent(message?.content),
        'content_type': message?.contentType,
        'unread_quantity': item.unreadCount,
        'last_client_msg_no': item.clientMsgNo,
        'last_msg_seq': item.lastMsgSeq,
        'msg_time': _formatTimestamp(item.lastMsgTimestamp),
      });
    }
    return result;
  }

  Map<String, Object?> _messageToMap(dynamic message) {
    final isMe = message.fromUID == _session?.chat?.uid;
    final content = message.messageContent;
    final payload = content is BimMessageContent
        ? content.payload
        : _asMap(message.content);
    return {
      'client_msg_no': message.clientMsgNO,
      'message_id': message.messageID,
      'message_seq': message.messageSeq,
      'from_uid': message.fromUID,
      'is_me': isMe,
      'content':
          message.messageContent?.displayText() ??
          _fallbackContent(message.content),
      'content_type': message.contentType,
      'payload': payload,
      'timestamp': _formatTimestamp(message.timestamp),
      'status': message.status,
    };
  }

  String _channelTitle(WKUIConversationMsg item, dynamic channel) {
    final remark = channel?.channelRemark?.toString() ?? '';
    if (remark.isNotEmpty) {
      return remark;
    }
    final name = channel?.channelName?.toString() ?? '';
    if (name.isNotEmpty) {
      return name;
    }
    final username = channel?.username?.toString() ?? '';
    if (username.isNotEmpty) {
      return username;
    }
    return item.channelType == WKChannelType.group ? '群聊' : item.channelID;
  }

  String _fallbackContent(String? raw) {
    if (raw == null || raw.isEmpty) {
      return '';
    }
    return raw.length > 80 ? '${raw.substring(0, 80)}...' : raw;
  }

  String _formatTimestamp(int seconds) {
    if (seconds <= 0) {
      return '';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  void _setStatus(int status) {
    _status = status;
    _statusChangedAt = DateTime.now();
    _statusText = switch (status) {
      WKConnectStatus.success => '已连接',
      WKConnectStatus.connecting => '连接中',
      WKConnectStatus.syncMsg => '同步消息中',
      WKConnectStatus.syncCompleted => '同步完成',
      WKConnectStatus.kicked => '已在其他设备登录',
      WKConnectStatus.noNetwork => '网络不可用',
      _ => '未连接',
    };
    if (status == WKConnectStatus.connecting) {
      _scheduleConnectionWatchdog('status_connecting');
    }
    notifyListeners();
  }

  bool _isStartedStatus(int status) {
    return status == WKConnectStatus.success ||
        status == WKConnectStatus.syncMsg ||
        status == WKConnectStatus.syncCompleted ||
        status == WKConnectStatus.connecting;
  }

  bool _isConnectedStatus(int status) {
    return status == WKConnectStatus.success ||
        status == WKConnectStatus.syncMsg ||
        status == WKConnectStatus.syncCompleted;
  }
}
