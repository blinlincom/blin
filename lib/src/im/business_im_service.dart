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
  final Set<String> _openMessageChannels = <String>{};

  Stream<BusinessImMessageEvent> get messageEvents => _messageEvents.stream;
  bool get isStarted => _started;
  String get statusText => _statusText;
  String? get lastError => _lastError;
  int get conversationVersion => _conversationVersion;

  int messageVersion({required String channelID, required int channelType}) {
    return _channelMessageVersions[_messageKey(channelID, channelType)] ?? 0;
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
    _historySyncedChannels.clear();
    _latestConversations = _cache.readConversations(chat.uid);
    _bumpConversations('cache_loaded', notify: false);
    AppLogger.info(
      'im',
      'business im start',
      data: {'uid': chat.uid, 'device': device, 'tcp_addr': chat.route.tcpAddr},
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
    _socket = null;
    if (socket != null) {
      await socket.close().catchError((Object _) => socket);
      socket.destroy();
    }
    if (logout) {
      _session = null;
      _latestConversations = const [];
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
    if (_socket == null && !_connecting) {
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
        .toList();
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
    final lastSeq = messages.fold<int>(
      0,
      (maxSeq, item) => max(maxSeq, _intValue(item, ['message_seq'])),
    );
    final lastMsgNo = messages.isEmpty
        ? ''
        : messages.last['client_msg_no']?.toString() ?? '';
    _cache.writeReadMarker(
      uid: chat.uid,
      channelId: channelID,
      channelType: channelType,
      marker: {
        'message_seq': lastSeq,
        'client_msg_no': lastMsgNo,
        'read_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
    );
    if (_clearConversationUnread(channelID, channelType, source: 'mark_read')) {
      _markMessageChannel(
        source: 'mark_read',
        channelId: channelID,
        channelType: channelType,
      );
    }
  }

  Future<List<Map<String, Object?>>> syncConversationsFromServer() async {
    final session = _requireSession();
    final chat = _requireChat();
    try {
      final list = await _api.conversations(
        session: session,
        device: _device,
        limit: 50,
      );
      _latestConversations = list.map(_normalizeConversation).toList();
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
      return _latestConversations;
    } catch (error, stackTrace) {
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
    if (cached.isEmpty && !_historySyncedChannels.contains(key)) {
      cached = await syncChannelMessages(
        channelID: channelID,
        channelType: channelType,
        groupId: groupId,
        limit: limit,
      );
    }
    return _sortAndLimit(cached, limit);
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
          .toList();
      final merged = _mergeMessages(
        _readMessagesForChannel(channelID, channelType),
        messages,
      );
      _writeMessages(channelID, channelType, _sortAndLimit(merged, 200));
      _historySyncedChannels.add(_messageKey(channelID, channelType));
      _markMessageChannel(
        source: 'history_sync',
        channelId: channelID,
        channelType: channelType,
      );
      return _sortAndLimit(merged, limit);
    } catch (error, stackTrace) {
      _historySyncedChannels.add(_messageKey(channelID, channelType));
      AppLogger.error(
        'im',
        'channel history sync failed',
        error: error,
        stackTrace: stackTrace,
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
      return _readMessagesForChannel(channelID, channelType);
    }
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
    final clientMsgNo = newClientMsgNo();
    final cleanPayload = _cleanPayload({
      ...payload,
      'content_type': contentType,
      'client_msg_no': clientMsgNo,
    });
    final optimistic = _localOutgoingMessage(
      channelId: channelID,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
      contentType: contentType,
      payload: cleanPayload,
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
      final result = channelType == chat.channelTypeGroup
          ? await _api.sendGroupMessage(
              session: session,
              device: _device,
              groupId: groupId.isNotEmpty
                  ? groupId
                  : _groupIdForChannel(channelID),
              clientMsgNo: clientMsgNo,
              contentType: contentType,
              params: cleanPayload,
              filePath: filePath,
            )
          : await _api.sendPersonMessage(
              session: session,
              device: _device,
              receiverId: _receiverIdFromChannel(channelID),
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

  Future<void> _connectTcp() async {
    if (_manualStop || _connecting || !_foreground) {
      return;
    }
    final chat = _requireChat();
    final endpoint = _parseTcpEndpoint(chat.route.tcpAddr);
    if (endpoint == null) {
      _lastError = 'IM TCP 地址为空';
      _setStatus('连接失败');
      AppLogger.error('im', 'missing tcp address');
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
        'tcp connect start',
        data: {'host': endpoint.host, 'port': endpoint.port},
      );
      final socket = await Socket.connect(
        endpoint.host,
        endpoint.port,
        timeout: const Duration(seconds: 6),
      );
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
      _sendConnectPacket(chat);
    } catch (error, stackTrace) {
      _connecting = false;
      _lastError = error.toString();
      _setStatus('连接失败');
      AppLogger.error(
        'im',
        'tcp connect failed',
        error: error,
        stackTrace: stackTrace,
        data: {'host': endpoint.host, 'port': endpoint.port},
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
    final message = _messageFromTcp(packet, channelId);
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
    final socket = _socket;
    if (socket == null) {
      return;
    }
    socket.add(_proto.encode(packet));
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
    _socket = null;
    _socketEpoch++;
    if (socket == null) {
      return;
    }
    await socket.close().catchError((Object _) => socket);
    socket.destroy();
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
    return <String, Object?>{
      ...item,
      'conversation_type': item['conversation_type']?.toString() ?? type,
      'channel_type': resolvedType,
      'channel_id': channelId,
      if (receiverId.isNotEmpty) 'receiver_id': receiverId,
      'content': _value(item, ['content'], fallback: _payloadContent(payload)),
      'content_type': _value(item, [
        'content_type',
      ], fallback: payload['content_type']?.toString() ?? ''),
      'payload': payload,
      'msg_time': _value(item, ['msg_time', 'create_time', 'timestamp']),
      'unread_quantity': unread,
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
    final fromUid = _value(
      raw,
      ['from_uid'],
      fallback: _value(payload, [
        'sender_uid',
      ], fallback: _uidFromUser(fromUser)),
    );
    final currentUid = _requireChat().uid;
    final canonicalChannelId = _canonicalChannelId(channelId, channelType);
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
      'is_me': fromUid == currentUid,
      'content': _value(message, [
        'content',
      ], fallback: _payloadContent(payload)),
      'content_type': _value(message, [
        'content_type',
      ], fallback: payload['content_type']?.toString() ?? ''),
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
      'content': _payloadContent(payload).isNotEmpty
          ? _payloadContent(payload)
          : fallback['content'],
      'content_type':
          payload['content_type']?.toString() ?? fallback['content_type'],
      'payload': payload.isEmpty ? fallback['payload'] : payload,
      'status': _boolValue(result['queued']) ? 'queued' : 'sent',
      'send_ack': sendAck,
    };
  }

  Map<String, Object?> _messageFromTcp(TcpRecvPacket packet, String channelId) {
    final payload = _decodeBusinessPayload(packet.payload);
    final canonicalChannelId = _canonicalChannelId(
      channelId,
      packet.channelType,
    );
    final receiverId = packet.channelType == _requireChat().channelTypePerson
        ? _receiverIdFromChannel(canonicalChannelId)
        : '';
    return <String, Object?>{
      'message_id': packet.messageId.toString(),
      'client_msg_no': packet.clientMsgNo,
      'message_seq': packet.messageSeq,
      'channel_id': canonicalChannelId,
      'channel_type': packet.channelType,
      if (receiverId.isNotEmpty) 'receiver_id': receiverId,
      'from_uid': packet.fromUid,
      'is_me': packet.fromUid == _requireChat().uid,
      'content': _payloadContent(payload),
      'content_type': payload['content_type']?.toString() ?? '',
      'payload': payload,
      'timestamp': _formatTimestamp(packet.messageTime),
      'status': 'sent',
      'header': {
        'no_persist': packet.header.noPersist,
        'show_unread': packet.header.showUnread,
        'sync_once': packet.header.syncOnce,
      },
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
    final messages = _readMessagesForChannel(channelId, channelType).toList();
    final clientMsgNo = message['client_msg_no']?.toString() ?? '';
    final index = clientMsgNo.isEmpty
        ? -1
        : messages.indexWhere(
            (item) => item['client_msg_no']?.toString() == clientMsgNo,
          );
    if (index >= 0) {
      messages[index] = {...messages[index], ...message};
    } else {
      messages.add(message);
    }
    _writeMessages(channelId, channelType, _sortAndLimit(messages, 200));
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
    if (channelType != chat.channelTypePerson) {
      return primary;
    }

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
        if (!_messageBelongsToPrivatePeer(message, channelId)) {
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
          merged[index] = {...merged[index], ...message};
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
        'private message cache migrated',
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
      final index = clientMsgNo.isEmpty
          ? -1
          : merged.indexWhere(
              (item) => item['client_msg_no']?.toString() == clientMsgNo,
            );
      if (index >= 0) {
        merged[index] = {...merged[index], ...message};
      } else {
        merged.add(message);
      }
    }
    return merged;
  }

  void _writeMessages(
    String channelId,
    int channelType,
    List<Map<String, Object?>> messages,
  ) {
    _cache.writeMessages(
      uid: _requireChat().uid,
      channelId: channelId,
      channelType: channelType,
      messages: messages,
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
    final conversations = _cache
        .readConversations(chat.uid)
        .map(_normalizeConversation)
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

  Map<String, Object?> _conversationForChannel(
    String channelId,
    int channelType,
  ) {
    final chat = _requireChat();
    for (final item in _cache.readConversations(chat.uid)) {
      if (item['channel_id']?.toString() == channelId &&
          (int.tryParse(item['channel_type']?.toString() ?? '') ?? 0) ==
              channelType) {
        return _normalizeConversation(item);
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

  _TcpEndpoint? _parseTcpEndpoint(String value) {
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
          return _TcpEndpoint(parts[0], port);
        }
      }
      return null;
    }
    return _TcpEndpoint(uri.host, uri.port);
  }

  Map<String, Object?> _cleanPayload(Map<String, Object?> payload) {
    return Map<String, Object?>.fromEntries(
      payload.entries.where(
        (entry) => entry.value != null && entry.value.toString().isNotEmpty,
      ),
    );
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
    if (channelType != chat.channelTypePerson) {
      return channelId;
    }
    if (_isCurrentUserChannel(channelId)) {
      final fromConversation = _privatePeerChannelFromConversations(channelId);
      return fromConversation.isNotEmpty ? fromConversation : channelId;
    }
    return _uidFromUserId(_receiverIdFromChannel(channelId));
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

class _TcpEndpoint {
  const _TcpEndpoint(this.host, this.port);

  final String host;
  final int port;
}
