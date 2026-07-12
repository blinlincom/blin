import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_logger.dart';

class GatewayFrame {
  const GatewayFrame({
    required this.type,
    this.cursor = '',
    this.channelId = '',
    this.channelType = 0,
    this.clientMsgNo = '',
    this.messageId = '',
    this.messageSeq = 0,
    this.timestamp = 0,
    this.reason = '',
    this.payload = const <String, Object?>{},
  });

  final String type;
  final String cursor;
  final String channelId;
  final int channelType;
  final String clientMsgNo;
  final String messageId;
  final int messageSeq;
  final int timestamp;
  final String reason;
  final Map<String, Object?> payload;

  bool get isMessage => type == 'message';
  bool get isHeartbeat => type == 'heartbeat';
  bool get isKick => type == 'kick';
  bool get isError => type == 'error';

  factory GatewayFrame.fromEvent({
    required String eventId,
    required String eventType,
    required Map<String, Object?> data,
  }) {
    final rawPayload = data['payload'];
    final payload = rawPayload is Map
        ? _objectMap(rawPayload)
        : <String, Object?>{};
    return GatewayFrame(
      type: _normalizeEventType(eventType, data),
      cursor: eventId,
      channelId: data['channel_id']?.toString() ?? '',
      channelType: int.tryParse(data['channel_type']?.toString() ?? '') ?? 0,
      clientMsgNo: data['client_msg_no']?.toString() ?? '',
      messageId: data['message_id']?.toString() ?? data['id']?.toString() ?? '',
      messageSeq: int.tryParse(data['message_seq']?.toString() ?? '') ?? 0,
      timestamp: _eventTimestamp(data),
      reason: data['reason']?.toString() ?? data['message']?.toString() ?? '',
      payload: <String, Object?>{...payload, ...data, 'event_type': eventType},
    );
  }
}

String _normalizeEventType(String eventType, Map<String, Object?> data) {
  final value = eventType.trim().toLowerCase();
  if (value == 'read_receipt' ||
      value.contains('presence') ||
      value.startsWith('call_') ||
      value == 'kick' ||
      value == 'error') {
    return value;
  }
  if (data.containsKey('channel_id') || data.containsKey('client_msg_no')) {
    return 'message';
  }
  return value;
}

int _eventTimestamp(Map<String, Object?> data) {
  final raw = data['timestamp'] ?? data['created_at'];
  final numeric = int.tryParse(raw?.toString() ?? '');
  if (numeric != null) return numeric;
  return DateTime.tryParse(raw?.toString() ?? '')?.millisecondsSinceEpoch ??
      DateTime.now().millisecondsSinceEpoch;
}

class GatewayStreamException implements Exception {
  const GatewayStreamException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Maintains the authenticated WSS connection, heartbeat, cursor and ACK.
class GatewayStreamClient {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _watchdog;
  DateTime? _lastFrameAt;
  bool _closed = true;
  bool _closedNotified = false;
  void Function(String reason, Object? error)? _onClosed;

  DateTime? get lastFrameAt => _lastFrameAt;
  bool get hasValidatedFrame => _lastFrameAt != null;

  bool isHealthy({Duration staleAfter = const Duration(seconds: 65)}) {
    final last = _lastFrameAt;
    return !_closed &&
        last != null &&
        DateTime.now().difference(last) <= staleAfter;
  }

  Future<void> connect({
    required Uri uri,
    required String ticket,
    required String frameKey,
    required String lastCursor,
    required void Function(GatewayFrame frame) onFrame,
    required void Function(String reason, Object? error) onClosed,
  }) async {
    final wsUri = _webSocketUri(uri);
    if (ticket.trim().isEmpty) {
      throw const GatewayStreamException('Gateway 连接票据缺失');
    }
    _onClosed = onClosed;
    _closed = false;
    _closedNotified = false;
    _lastFrameAt = null;
    AppLogger.info(
      'im',
      'gateway websocket connect start',
      data: {
        'scheme': wsUri.scheme,
        'host': wsUri.host,
        'path': wsUri.path,
        'last_cursor': lastCursor,
      },
    );
    try {
      final socket = await WebSocket.connect(
        wsUri.toString(),
      ).timeout(const Duration(seconds: 10));
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      socket.add(
        jsonEncode({
          'type': 'connect',
          'ticket': ticket,
          'last_event_id': lastCursor.isEmpty ? '0-0' : lastCursor,
        }),
      );
      _subscription = socket.listen(
        (raw) => _handleRaw(raw, onFrame),
        onError: (Object error, StackTrace stackTrace) {
          _notifyClosed('socket_error', error);
        },
        onDone: () => _notifyClosed('socket_closed', null),
        cancelOnError: true,
      );
      _watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
        final last = _lastFrameAt;
        if (last != null &&
            DateTime.now().difference(last) > const Duration(seconds: 70)) {
          _notifyClosed('heartbeat_timeout', null);
          unawaited(close());
        }
      });
    } catch (error) {
      _closed = true;
      throw GatewayStreamException('Gateway 连接失败: $error');
    }
  }

  Uri _webSocketUri(Uri uri) {
    if (uri.scheme == 'wss' || uri.scheme == 'ws') return uri;
    if (uri.scheme == 'https') return uri.replace(scheme: 'wss');
    if (uri.scheme == 'http') return uri.replace(scheme: 'ws');
    throw const GatewayStreamException('Gateway 地址必须使用 WS/WSS');
  }

  void _handleRaw(dynamic raw, void Function(GatewayFrame frame) onFrame) {
    try {
      final decoded = jsonDecode(
        raw is String ? raw : utf8.decode(raw as List<int>),
      );
      if (decoded is! Map) return;
      final map = _objectMap(decoded);
      final type = map['type']?.toString() ?? '';
      _lastFrameAt = DateTime.now();
      if (type == 'ping') {
        _socket?.add(jsonEncode({'type': 'pong'}));
        onFrame(const GatewayFrame(type: 'heartbeat'));
        return;
      }
      if (type == 'event') {
        final eventId = map['event_id']?.toString() ?? '';
        final envelope = _objectMap(map['payload']);
        final eventType = envelope['event_type']?.toString() ?? '';
        final data = _decodeEventData(envelope['data']);
        onFrame(
          GatewayFrame.fromEvent(
            eventId: eventId,
            eventType: eventType,
            data: data,
          ),
        );
        if (eventId.isNotEmpty) {
          _socket?.add(jsonEncode({'type': 'ack', 'event_id': eventId}));
        }
        return;
      }
      onFrame(
        GatewayFrame(
          type: type,
          reason: map['reason']?.toString() ?? map['message']?.toString() ?? '',
          payload: map,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'im',
        'gateway frame decode failed',
        error: error,
        stackTrace: stackTrace,
      );
      _notifyClosed('invalid_frame', error);
    }
  }

  Map<String, Object?> _decodeEventData(Object? value) {
    if (value is Map) return _objectMap(value);
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return _objectMap(decoded);
    }
    return <String, Object?>{};
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _watchdog?.cancel();
    _watchdog = null;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close(WebSocketStatus.normalClosure, 'client_close');
    _socket = null;
  }

  void _notifyClosed(String reason, Object? error) {
    if (_closedNotified) return;
    _closedNotified = true;
    _closed = true;
    _watchdog?.cancel();
    AppLogger.warn(
      'im',
      'gateway websocket closed',
      data: {'reason': reason, 'error': error?.toString() ?? ''},
    );
    _onClosed?.call(reason, error);
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return value.map((key, item) => MapEntry(key.toString(), item));
}
