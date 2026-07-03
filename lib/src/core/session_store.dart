import 'dart:convert';
import 'dart:math';

import 'package:mmkv/mmkv.dart';

import 'app_config.dart';
import 'models.dart';

class SessionStore {
  SessionStore(this._kv);

  final MMKV _kv;

  static const _sessionKey = 'session';
  static const _deviceKey = 'device';
  static const _launchAtKey = 'last_launch_at';
  static const _resumeAtKey = 'last_resume_at';

  UserSession? readSession() {
    final raw = _kv.decodeString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return UserSession.fromJson(decoded);
      }
      if (decoded is Map) {
        return UserSession.fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      clearSession();
    }
    return null;
  }

  void writeSession(UserSession session) {
    _kv.encodeString(_sessionKey, jsonEncode(session.toJson()));
  }

  void clearSession() {
    _kv.removeValue(_sessionKey);
  }

  String ensureDeviceId() {
    final cached = _kv.decodeString(_deviceKey);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final generated = _newDeviceId();
    _kv.encodeString(_deviceKey, generated);
    return generated;
  }

  int readLaunchAt() => _kv.decodeInt(_launchAtKey);

  int readResumeAt() => _kv.decodeInt(_resumeAtKey);

  int markColdLaunch() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _kv.encodeInt(_launchAtKey, now);
    return now;
  }

  int markHotResume() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _kv.encodeInt(_resumeAtKey, now);
    return now;
  }

  String _newDeviceId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${AppConfig.packageName}-$hex';
  }
}
