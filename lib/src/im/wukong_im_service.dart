import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wukongimfluttersdk/common/options.dart';
import 'package:wukongimfluttersdk/entity/channel.dart';
import 'package:wukongimfluttersdk/entity/conversation.dart';
import 'package:wukongimfluttersdk/entity/msg.dart';
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
  List<Map<String, Object?>> _latestConversations = const [];
  int _conversationVersion = 0;
  DateTime? _lastConversationSyncAt;
  String _lastConversationSyncKey = '';
  WKSyncConversation? _lastConversationSyncResult;
  Future<WKSyncConversation>? _conversationSyncRequest;
  final Map<String, Future<WKSyncChannelMsg>> _channelSyncRequests =
      <String, Future<WKSyncChannelMsg>>{};
  final Map<String, String> _groupIdsByChannel = <String, String>{};

  bool get isConnected => _status == WKConnectStatus.success;
  String get statusText => _statusText;
  String? get lastError => _lastError;
  List<Map<String, Object?>> get latestConversations => _latestConversations;
  int get conversationVersion => _conversationVersion;

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
      'connect',
      data: {
        'uid': chat.uid,
        'tcp': chat.route.tcpAddr,
        'device_flag': chat.deviceFlag,
      },
    );
    WKIM.shared.connectionManager.connect();
    await refreshLocalConversations();
  }

  Future<void> stop({bool logout = false}) async {
    AppLogger.info('im', 'stop', data: {'logout': logout});
    _refreshDebounce?.cancel();
    _refreshDebounce = null;
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
    _lastConversationSyncAt = null;
    _lastConversationSyncKey = '';
    _lastConversationSyncResult = null;
    _conversationSyncRequest = null;
    _channelSyncRequests.clear();
    _lastError = null;
    _setStatus(WKConnectStatus.fail);
  }

  String newClientMsgNo() => WKIM.shared.messageManager.generateClientMsgNo();

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
      maxSeq,
      0,
      20,
      0,
      (_) {
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
      () {},
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
        data: {'status': status, 'reason_code': reasonCode},
      );
      _setStatus(status);
    });
    WKIM.shared.conversationManager.addOnRefreshMsgListListener(_listenerKey, (
      messages,
    ) async {
      _latestConversations = await _mapConversations(messages);
      _conversationVersion++;
      AppLogger.info(
        'im',
        'conversation refresh listener',
        data: {'count': _latestConversations.length},
      );
      notifyListeners();
    });
    WKIM.shared.messageManager.addOnNewMsgListener(
      _listenerKey,
      (_) => _debouncedRefresh(),
    );
    WKIM.shared.messageManager.addOnRefreshMsgListener(
      _listenerKey,
      (_) => _debouncedRefresh(),
    );
    WKIM.shared.messageManager.addOnMsgInsertedListener(
      (_) => _debouncedRefresh(),
    );
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
      _lastError = error.toString();
      AppLogger.error(
        'im',
        'sync channel messages failed',
        error: error,
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
      back(WKSyncChannelMsg());
      notifyListeners();
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
        final friend = friends.cast<Map<String, Object?>?>().firstWhere(
          (item) =>
              item?['uid']?.toString() == channelID ||
              item?['userid']?.toString() == userId ||
              item?['id']?.toString() == userId,
          orElse: () => null,
        );
        channel.channelName =
            friend?['nickname']?.toString() ??
            friend?['username']?.toString() ??
            '';
        channel.channelRemark = friend?['remark']?.toString() ?? '';
        channel.avatar =
            friend?['usertx']?.toString() ??
            friend?['avatar']?.toString() ??
            '';
        channel.username = friend?['username']?.toString() ?? '';
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
    _statusText = switch (status) {
      WKConnectStatus.success => '已连接',
      WKConnectStatus.connecting => '连接中',
      WKConnectStatus.syncMsg => '同步消息中',
      WKConnectStatus.syncCompleted => '同步完成',
      WKConnectStatus.kicked => '已在其他设备登录',
      WKConnectStatus.noNetwork => '网络不可用',
      _ => '未连接',
    };
    notifyListeners();
  }

  bool _isStartedStatus(int status) {
    return status == WKConnectStatus.success ||
        status == WKConnectStatus.syncMsg ||
        status == WKConnectStatus.syncCompleted ||
        status == WKConnectStatus.connecting;
  }
}
