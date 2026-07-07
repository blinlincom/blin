import 'dart:io';

import 'package:flutter/services.dart';

import '../core/app_logger.dart';

class BackgroundReceiveStatus {
  const BackgroundReceiveStatus({
    required this.platform,
    required this.supported,
    required this.serviceRunning,
    required this.notificationPermissionGranted,
    required this.batteryOptimizationIgnored,
    required this.note,
  });

  final String platform;
  final bool supported;
  final bool serviceRunning;
  final bool notificationPermissionGranted;
  final bool batteryOptimizationIgnored;
  final String note;

  factory BackgroundReceiveStatus.unsupported(String platform, String note) {
    return BackgroundReceiveStatus(
      platform: platform,
      supported: false,
      serviceRunning: false,
      notificationPermissionGranted: false,
      batteryOptimizationIgnored: false,
      note: note,
    );
  }

  factory BackgroundReceiveStatus.fromMap(Map<Object?, Object?> map) {
    return BackgroundReceiveStatus(
      platform: map['platform']?.toString() ?? '',
      supported: _boolValue(map['supported']),
      serviceRunning: _boolValue(map['service_running']),
      notificationPermissionGranted: _boolValue(
        map['notification_permission_granted'],
      ),
      batteryOptimizationIgnored: _boolValue(
        map['battery_optimization_ignored'],
      ),
      note: map['note']?.toString() ?? '',
    );
  }
}

class BackgroundReceiveGuard {
  const BackgroundReceiveGuard._();

  static const _channel = MethodChannel('bimotc.com/background_receive');

  static Future<void> start({
    required bool enabled,
    required String statusText,
    required String uid,
  }) async {
    if (!enabled) {
      await stop(reason: 'disabled');
      return;
    }
    if (!Platform.isAndroid) {
      AppLogger.info(
        'background',
        'background receive start skipped on platform',
        data: {'platform': _platformName, 'uid': uid},
      );
      return;
    }
    try {
      await _channel.invokeMethod<void>('start', {
        'title': 'BIM 正在接收消息',
        'text': statusText,
        'uid': uid,
      });
      AppLogger.info(
        'background',
        'background receive guard started',
        data: {'uid': uid, 'status': statusText},
      );
    } on MissingPluginException {
      AppLogger.warn('background', 'background receive channel missing');
    } catch (error, stackTrace) {
      AppLogger.warn(
        'background',
        'background receive guard start failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  static Future<void> update({
    required bool enabled,
    required String statusText,
    required String uid,
  }) async {
    if (!enabled || !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('update', {
        'title': 'BIM 正在接收消息',
        'text': statusText,
        'uid': uid,
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'background',
        'background receive guard update failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  static Future<void> stop({String reason = ''}) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stop', {'reason': reason});
      AppLogger.info(
        'background',
        'background receive guard stopped',
        data: {'reason': reason},
      );
    } on MissingPluginException {
      AppLogger.warn('background', 'background receive channel missing');
    } catch (error, stackTrace) {
      AppLogger.warn(
        'background',
        'background receive guard stop failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  static Future<BackgroundReceiveStatus> status() async {
    if (!Platform.isAndroid) {
      return BackgroundReceiveStatus.unsupported(
        _platformName,
        Platform.isIOS
            ? 'iOS 不允许普通聊天长时间后台常驻连接，打开应用后会自动补齐离线消息。'
            : '当前平台不支持 Android 前台服务保活。',
      );
    }
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('status');
      if (raw == null) {
        return BackgroundReceiveStatus.unsupported('android', '未读取到后台接收状态');
      }
      return BackgroundReceiveStatus.fromMap(raw);
    } on MissingPluginException {
      return BackgroundReceiveStatus.unsupported('android', '原生后台接收通道未注册');
    } catch (error, stackTrace) {
      AppLogger.warn(
        'background',
        'background receive status failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
      return BackgroundReceiveStatus.unsupported('android', error.toString());
    }
  }

  static Future<void> openNotificationSettings() async {
    await _openSettings('openNotificationSettings');
  }

  static Future<void> openBatterySettings() async {
    await _openSettings('openBatterySettings');
  }

  static Future<void> _openSettings(String method) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(method);
    } catch (error, stackTrace) {
      AppLogger.warn(
        'background',
        'background receive settings open failed',
        data: {
          'method': method,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    }
  }

  static String get _platformName {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    return 'unknown';
  }
}

bool _boolValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value == null) {
    return false;
  }
  final text = value.toString().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes' || text == 'on';
}
