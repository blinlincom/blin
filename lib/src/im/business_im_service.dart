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

  UserSession? _session;
  String _device = '';
  Socket? _socket;
  TcpImCrypto _crypto = TcpImCrypto();
  TcpImProto _proto = TcpImProto();
  Uint8List _frameBuffer = Uint8List(0);
  Timer? _tcpHeartbeatTimer;
  Timer? _userHeartbeatTimer;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _manualStop = false;
  bool _connecting = false;
  int _missedPongCount = 0;
  int _reconnectAttempt = 0;
  int _conversationVersion = 0;
  String _statusText = '未连接';
  String? _lastError;
  List<Map<String, Object?>> _latestConversations = const [];
  final Map<String, int> _channelMessageVersions = <String, int>{};
  final Set<String> _historySyncedChannels = <String>{};

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
    _startUserHeartbeat();
    await _connectTcp();
  }

  Future<void> stop({bool logout = false}) async {
    _manualStop = true;
    _started = false;
    _connecting = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopTcpHeartbeat();
    _stopUserHeartbeat();
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
  }

  void resumeConnection() {
    if (!_started || _session == null) {
      return;
    }
    if (_socket == null && !_connecting) {
      unawaited(_connectTcp());
    }
    _startUserHeartbeat();
  }

  Future<List<Map<String, Object?>>> refreshLocalConversations({
    bool notify = true,
  }) async {
    final chat = _requireChat();
    _latestConversations = _cache.readConversations(chat.uid);
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
    final chat = _requireChat();
    var cached = _cache.readMessages(
      uid: chat.uid,
      channelId: channelID,
      channelType: channelType,
    );
    final key = _messageKey(channelID, channelType);
    if (cached.isEmpty || !_historySyncedChannels.contains(key)) {
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
        _cache.readMessages(
          uid: chat.uid,
          channelId: channelID,
          channelType: channelType,
        ),
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
      AppLogger.error(
        'im',
        'channel history sync failed',
        error: error,
        stackTrace: stackTrace,
        data: {'channel_id': channelID, 'channel_type': channelType},
      );
      return _cache.readMessages(
        uid: chat.uid,
        channelId: channelID,
        channelType: channelType,
      );
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
    if (_manualStop || _connecting) {
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
      _socket = socket;
      _connecting = false;
      socket.listen(
        _onTcpData,
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.error(
            'im',
            'tcp socket error',
            error: error,
            stackTrace: stackTrace,
          );
          _handleTcpClosed('socket_error', error.toString());
        },
        onDone: () => _handleTcpClosed('socket_done', ''),
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
    _frameBuffer = Uint8List.fromList([..._frameBuffer, ...data]);
    while (_frameBuffer.isNotEmpty) {
      final length = TcpImProto.frameLength(_frameBuffer);
      if (length == 0 || _frameBuffer.length < length) {
        return;
      }
      final frame = _frameBuffer.sublist(0, length);
      _frameBuffer = _frameBuffer.sublist(length);
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
    unawaited(_syncAfterConnected());
    AppLogger.info(
      'im',
      'tcp connected',
      data: {'node_id': packet.nodeId, 'proto': packet.serviceProtoVersion},
    );
  }

  Future<void> _syncAfterConnected() async {
    await syncConversationsFromServer();
    final chat = _requireChat();
    final recent = _cache.readRecentChannels(chat.uid).take(10);
    for (final channel in recent) {
      final parts = channel.split(':');
      if (parts.length != 2) {
        continue;
      }
      final channelType = int.tryParse(parts[0]) ?? 0;
      final channelId = parts[1];
      if (channelType <= 0 || channelId.isEmpty) {
        continue;
      }
      await syncChannelMessages(
        channelID: channelId,
        channelType: channelType,
        groupId: channelType == chat.channelTypeGroup
            ? _groupIdForChannel(channelId)
            : '',
        limit: 50,
      );
    }
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
        packet.channelId == chat.uid &&
        packet.fromUid.isNotEmpty) {
      channelId = packet.fromUid;
    }
    final message = _messageFromTcp(packet, channelId);
    _upsertMessage(channelId, packet.channelType, message);
    _upsertConversationFromMessage(message);
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

  void _startUserHeartbeat() {
    _stopUserHeartbeat();
    _sendUserHeartbeat();
    _userHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 55),
      (_) => _sendUserHeartbeat(),
    );
  }

  void _stopUserHeartbeat() {
    _userHeartbeatTimer?.cancel();
    _userHeartbeatTimer = null;
  }

  Future<void> _sendUserHeartbeat() async {
    final session = _session;
    if (!_started || session == null || _device.isEmpty) {
      return;
    }
    try {
      await _api
          .userHeartbeat(session: session, device: _device)
          .timeout(const Duration(seconds: 8));
      AppLogger.info('im', 'user heartbeat success');
    } catch (error, stackTrace) {
      AppLogger.error(
        'im',
        'user heartbeat failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _handleTcpClosed(String source, String? reason) {
    if (_manualStop) {
      return;
    }
    _stopTcpHeartbeat();
    unawaited(_closeSocketOnly());
    _lastError = reason?.isEmpty == false ? reason : _lastError;
    _setStatus('重连中');
    _scheduleReconnect(source);
  }

  void _scheduleReconnect(String source) {
    if (!_started || _manualStop) {
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
    return <String, Object?>{
      ...item,
      'conversation_type': item['conversation_type']?.toString() ?? type,
      'channel_type': channelType == 0
          ? (type == 'group'
                ? _requireChat().channelTypeGroup
                : _requireChat().channelTypePerson)
          : channelType,
      'channel_id': _value(item, ['channel_id', 'uid']),
      'content': _value(item, ['content'], fallback: _payloadContent(payload)),
      'content_type': _value(item, [
        'content_type',
      ], fallback: payload['content_type']?.toString() ?? ''),
      'payload': payload,
      'msg_time': _value(item, ['msg_time', 'create_time', 'timestamp']),
      'unread_quantity': _intValue(item, ['unread_quantity', 'unread']),
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
      'channel_id': channelId,
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
    return <String, Object?>{
      'message_id': packet.messageId.toString(),
      'client_msg_no': packet.clientMsgNo,
      'message_seq': packet.messageSeq,
      'channel_id': channelId,
      'channel_type': packet.channelType,
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
    final chat = _requireChat();
    final messages = _cache
        .readMessages(
          uid: chat.uid,
          channelId: channelId,
          channelType: channelType,
        )
        .toList();
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
    final conversations = _cache.readConversations(chat.uid).toList();
    final index = conversations.indexWhere(
      (item) =>
          item['channel_id']?.toString() == channelId &&
          (int.tryParse(item['channel_type']?.toString() ?? '') ?? 0) ==
              channelType,
    );
    final payload = _asMap(message['payload']);
    final content = message['content']?.toString() ?? _payloadContent(payload);
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
      'channel_id': channelId,
      'channel_type': channelType,
      'content': content,
      'content_type': message['content_type']?.toString() ?? '',
      'payload': payload,
      'msg_time': message['timestamp']?.toString() ?? '',
      'last_client_msg_no': message['client_msg_no']?.toString() ?? '',
      'last_msg_seq': message['message_seq'] ?? 0,
      'unread_quantity': message['is_me'] == true
          ? (index >= 0 ? conversations[index]['unread_quantity'] ?? 0 : 0)
          : (index >= 0
                ? (_intValue(conversations[index], ['unread_quantity']) + 1)
                : 1),
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
    super.dispose();
  }
}

class _TcpEndpoint {
  const _TcpEndpoint(this.host, this.port);

  final String host;
  final int port;
}
