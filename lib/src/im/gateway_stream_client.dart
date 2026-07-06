import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/app_logger.dart';
import '../core/crypto_helpers.dart';

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

  factory GatewayFrame.fromJson(Map<String, Object?> map) {
    final payload = map['payload'];
    return GatewayFrame(
      type: map['type']?.toString() ?? '',
      cursor: map['cursor']?.toString() ?? '',
      channelId: map['channel_id']?.toString() ?? '',
      channelType: int.tryParse(map['channel_type']?.toString() ?? '') ?? 0,
      clientMsgNo: map['client_msg_no']?.toString() ?? '',
      messageId: map['message_id']?.toString() ?? '',
      messageSeq: int.tryParse(map['message_seq']?.toString() ?? '') ?? 0,
      timestamp: int.tryParse(map['timestamp']?.toString() ?? '') ?? 0,
      reason: map['reason']?.toString() ?? map['message']?.toString() ?? '',
      payload: _payloadMap(payload),
    );
  }
}

Map<String, Object?> _payloadMap(Object? value) {
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  if (value is! String || value.trim().isEmpty) {
    return const <String, Object?>{};
  }
  final text = value.trim();
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
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return const <String, Object?>{};
  }
  return const <String, Object?>{};
}

class GatewayStreamException implements Exception {
  const GatewayStreamException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GatewayStreamClient {
  GatewayStreamClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  StreamSubscription<List<int>>? _subscription;
  Timer? _watchdog;
  Uint8List _buffer = Uint8List(0);
  DateTime _lastFrameAt = DateTime.now();
  bool _closed = false;
  bool _closedNotified = false;
  String _streamId = '';
  int _chunkSeq = 0;
  int _frameSeq = 0;
  void Function(String reason, Object? error)? _onClosed;

  Future<void> connect({
    required Uri uri,
    required String ticket,
    required String frameKey,
    required String lastCursor,
    required void Function(GatewayFrame frame) onFrame,
    required void Function(String reason, Object? error) onClosed,
  }) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw GatewayStreamException('Gateway 实时地址必须是 HTTP/HTTPS');
    }
    if (frameKey.trim().isEmpty) {
      throw const GatewayStreamException('Gateway 帧密钥缺失');
    }
    _onClosed = onClosed;
    _closed = false;
    _closedNotified = false;
    _streamId = AppLogger.traceId('gateway');
    _chunkSeq = 0;
    _frameSeq = 0;
    _buffer = Uint8List(0);
    _lastFrameAt = DateTime.now();
    AppLogger.info(
      'im',
      'gateway stream connect start',
      data: {
        'stream_id': _streamId,
        'scheme': uri.scheme,
        'host': uri.host,
        'port': uri.hasPort ? uri.port : 0,
        'path': uri.path,
        'ticket_len': ticket.length,
        'frame_key_len': frameKey.length,
        'last_cursor': lastCursor,
        'last_cursor_len': lastCursor.length,
      },
    );
    final request = await _httpClient
        .postUrl(uri)
        .timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final body = jsonEncode({'ticket': ticket, 'last_cursor': lastCursor});
    request.add(utf8.encode(body));
    final response = await request.close().timeout(const Duration(seconds: 12));
    if (response.statusCode != HttpStatus.ok) {
      final text = await utf8.decoder.bind(response).join();
      AppLogger.warn(
        'im',
        'gateway stream connect rejected',
        data: {
          'stream_id': _streamId,
          'status_code': response.statusCode,
          'body_len': text.length,
          'body': text,
        },
      );
      throw GatewayStreamException(
        'Gateway 打开失败(${response.statusCode}) $text',
      );
    }
    AppLogger.info(
      'im',
      'gateway stream connected',
      data: {
        'stream_id': _streamId,
        'status_code': response.statusCode,
        'content_type': response.headers.contentType?.toString() ?? '',
      },
    );
    _watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
      final silentSeconds = DateTime.now().difference(_lastFrameAt).inSeconds;
      if (silentSeconds > 75) {
        AppLogger.warn(
          'im',
          'gateway heartbeat timeout',
          data: {'silent_seconds': silentSeconds},
        );
        close();
        _notifyClosed('heartbeat_timeout', null);
      }
    });
    _subscription = response.listen(
      (chunk) {
        _lastFrameAt = DateTime.now();
        try {
          _chunkSeq++;
          AppLogger.info(
            'im',
            'gateway chunk received',
            data: {
              'stream_id': _streamId,
              'chunk_no': _chunkSeq,
              'chunk_bytes': chunk.length,
              'buffer_before': _buffer.length,
            },
          );
          _appendAndDecode(Uint8List.fromList(chunk), frameKey, onFrame);
        } catch (error) {
          if (_closed) {
            return;
          }
          unawaited(close());
          _notifyClosed('frame_decode_error', error);
        }
      },
      onError: (Object error) {
        if (_closed) {
          return;
        }
        _notifyClosed('stream_error', error);
      },
      onDone: () {
        if (_closed) {
          return;
        }
        _notifyClosed('stream_done', null);
      },
      cancelOnError: true,
    );
  }

  Future<void> close() async {
    AppLogger.info(
      'im',
      'gateway stream close requested',
      data: {
        'stream_id': _streamId,
        'chunk_count': _chunkSeq,
        'frame_count': _frameSeq,
        'buffer_bytes': _buffer.length,
      },
    );
    _closed = true;
    _watchdog?.cancel();
    _watchdog = null;
    await _subscription?.cancel().catchError((Object _) => null);
    _subscription = null;
    _httpClient.close(force: true);
  }

  void _appendAndDecode(
    Uint8List chunk,
    String frameKey,
    void Function(GatewayFrame frame) onFrame,
  ) {
    _buffer = Uint8List.fromList([..._buffer, ...chunk]);
    while (_buffer.length >= 4) {
      final length = ByteData.sublistView(_buffer, 0, 4).getUint32(0);
      if (length <= 0 || length > 1024 * 1024) {
        throw const GatewayStreamException('Gateway 帧长度异常');
      }
      final frameLength = 4 + length;
      if (_buffer.length < frameLength) {
        return;
      }
      final payload = _buffer.sublist(4, frameLength);
      _buffer = _buffer.sublist(frameLength);
      final frameNo = ++_frameSeq;
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) {
        AppLogger.warn(
          'im',
          'gateway frame skipped for non-map payload',
          data: {
            'stream_id': _streamId,
            'frame_no': frameNo,
            'frame_bytes': length,
            'buffer_remaining': _buffer.length,
          },
        );
        continue;
      }
      final map = decoded.map((key, value) => MapEntry(key.toString(), value));
      final rawFrame = _decryptFrameEnvelope(map, frameKey);
      final frame = GatewayFrame.fromJson(
        rawFrame.map((key, value) => MapEntry(key.toString(), value)),
      );
      AppLogger.info(
        'im',
        'gateway frame received',
        data: {
          'stream_id': _streamId,
          'frame_no': frameNo,
          'frame_bytes': length,
          'buffer_remaining': _buffer.length,
          'encrypted_keys': map.keys.toList(growable: false),
          'type': frame.type,
          'has_cursor': frame.cursor.isNotEmpty,
          'cursor_len': frame.cursor.length,
          'cursor': frame.cursor,
          'channel_id': frame.channelId,
          'channel_type': frame.channelType,
          'client_msg_no': frame.clientMsgNo,
          'message_id': frame.messageId,
          'message_seq': frame.messageSeq,
          'timestamp': frame.timestamp,
          'payload_summary': _payloadSummary(frame.payload),
          'payload': frame.payload,
        },
      );
      onFrame(frame);
    }
  }

  Map<String, Object?> _decryptFrameEnvelope(
    Map<String, Object?> map,
    String frameKey,
  ) {
    if (map['type'] != 'secure') {
      throw const GatewayStreamException('Gateway 返回了未加密帧');
    }
    if (map['alg']?.toString() != 'AES-256-GCM') {
      throw const GatewayStreamException('Gateway 帧加密算法不支持');
    }
    final keyBytes = base64Decode(frameKey);
    if (keyBytes.length != 32) {
      throw const GatewayStreamException('Gateway 帧密钥长度错误');
    }
    final nonce = base64Decode(map['nonce']?.toString() ?? '');
    final ciphertext = base64Decode(map['ciphertext']?.toString() ?? '');
    final plain = CryptoHelpers.aesGcmDecrypt(
      key: keyBytes,
      nonce: nonce,
      cipherText: ciphertext,
      associatedData: utf8.encode('bim-gateway-frame-v1'),
    );
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map) {
      throw const GatewayStreamException('Gateway 帧明文格式错误');
    }
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }

  void _notifyClosed(String reason, Object? error) {
    if (_closedNotified) {
      return;
    }
    _closedNotified = true;
    _watchdog?.cancel();
    _watchdog = null;
    AppLogger.warn(
      'im',
      'gateway stream closed',
      data: {
        'stream_id': _streamId,
        'reason': reason,
        'error': error?.toString() ?? '',
        'chunk_count': _chunkSeq,
        'frame_count': _frameSeq,
        'buffer_bytes': _buffer.length,
      },
    );
    _onClosed?.call(reason, error);
  }
}

Map<String, Object?> _payloadSummary(Map<String, Object?> payload) {
  final content = payload['content']?.toString() ?? '';
  return {
    'key_count': payload.length,
    'keys': payload.keys.take(80).toList(growable: false),
    'content_type': payload['content_type']?.toString() ?? '',
    'type': payload['type']?.toString() ?? '',
    'cmd': payload['cmd']?.toString() ?? '',
    'content_len': content.length,
    'has_red_packet': payload['red_packet'] is Map,
    'has_transfer': payload['transfer'] is Map,
    'has_file_path': (payload['file_path']?.toString() ?? '').isNotEmpty,
    'has_image_path': (payload['image_path']?.toString() ?? '').isNotEmpty,
    'has_video_path': (payload['video_path']?.toString() ?? '').isNotEmpty,
  };
}
