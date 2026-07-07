import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_logger.dart';

class RealtimeNotificationPayload {
  const RealtimeNotificationPayload({
    required this.type,
    this.callId = 0,
    this.channelId = '',
    this.channelType = 0,
    this.clientMsgNo = '',
  });

  final String type;
  final int callId;
  final String channelId;
  final int channelType;
  final String clientMsgNo;

  bool get isCall => type == 'call';
  bool get isMessage => type == 'message';

  factory RealtimeNotificationPayload.fromMap(Map<Object?, Object?> map) {
    return RealtimeNotificationPayload(
      type: map['type']?.toString() ?? '',
      callId: int.tryParse(map['call_id']?.toString() ?? '') ?? 0,
      channelId: map['channel_id']?.toString() ?? '',
      channelType: int.tryParse(map['channel_type']?.toString() ?? '') ?? 0,
      clientMsgNo: map['client_msg_no']?.toString() ?? '',
    );
  }
}

class RealtimeNotificationBridge {
  RealtimeNotificationBridge._();

  static const _channel = MethodChannel('bimotc.com/realtime_notifications');
  static final StreamController<RealtimeNotificationPayload> _taps =
      StreamController<RealtimeNotificationPayload>.broadcast();
  static bool _configured = false;

  static Stream<RealtimeNotificationPayload> get taps => _taps.stream;

  static void configure() {
    if (_configured) {
      return;
    }
    _configured = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'notificationTap') {
        return null;
      }
      final args = call.arguments;
      if (args is! Map) {
        return null;
      }
      final payload = RealtimeNotificationPayload.fromMap(
        args.map((key, value) => MapEntry(key, value)),
      );
      AppLogger.info(
        'notification',
        'notification tap received',
        data: {
          'type': payload.type,
          'call_id': payload.callId,
          'channel_id': payload.channelId,
          'channel_type': payload.channelType,
          'client_msg_no': payload.clientMsgNo,
        },
      );
      _taps.add(payload);
      return null;
    });
  }

  static Future<RealtimeNotificationPayload?> getLaunchPayload() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getLaunchPayload',
      );
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return RealtimeNotificationPayload.fromMap(raw);
    } on MissingPluginException {
      AppLogger.warn('notification', 'realtime notification channel missing');
      return null;
    } catch (error, stackTrace) {
      AppLogger.warn(
        'notification',
        'read launch notification payload failed',
        data: {'error': '$error', 'stack': '$stackTrace'},
      );
      return null;
    }
  }

  static Future<bool> ensureNotificationPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      final granted = await _channel.invokeMethod<bool>(
        'ensureNotificationPermission',
      );
      return granted ?? false;
    } on MissingPluginException {
      AppLogger.warn('notification', 'realtime notification channel missing');
      return false;
    } catch (error, stackTrace) {
      AppLogger.warn(
        'notification',
        'request notification permission failed',
        data: {'error': '$error', 'stack': '$stackTrace'},
      );
      return false;
    }
  }

  static Future<void> showIncomingCall({
    required int callId,
    required String title,
    required String text,
    required bool video,
  }) async {
    if (!Platform.isAndroid || callId <= 0) {
      return;
    }
    await _invoke('showIncomingCall', {
      'call_id': callId,
      'title': title,
      'text': text,
      'video': video,
    });
  }

  static Future<void> cancelIncomingCall(int callId) async {
    if (!Platform.isAndroid || callId <= 0) {
      return;
    }
    await _invoke('cancelIncomingCall', {'call_id': callId});
  }

  static Future<void> showMessageNotification({
    required String channelId,
    required int channelType,
    required String clientMsgNo,
    required String title,
    required String text,
  }) async {
    if (!Platform.isAndroid || channelId.isEmpty || clientMsgNo.isEmpty) {
      return;
    }
    await _invoke('showMessageNotification', {
      'channel_id': channelId,
      'channel_type': channelType,
      'client_msg_no': clientMsgNo,
      'title': title,
      'text': text,
    });
  }

  static Future<void> cancelMessageNotification({
    required String channelId,
    required int channelType,
  }) async {
    if (!Platform.isAndroid || channelId.isEmpty) {
      return;
    }
    await _invoke('cancelMessageNotification', {
      'channel_id': channelId,
      'channel_type': channelType,
    });
  }

  static Future<void> _invoke(String method, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      AppLogger.warn('notification', 'realtime notification channel missing');
    } catch (error, stackTrace) {
      AppLogger.warn(
        'notification',
        'realtime notification bridge call failed',
        data: {'method': method, 'error': '$error', 'stack': '$stackTrace'},
      );
    }
  }
}
