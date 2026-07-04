import 'dart:io';
import 'dart:math';

import 'app_logger.dart';
import 'package:flutter/services.dart';
import 'package:mmkv/mmkv.dart';
import 'package:path_provider/path_provider.dart';

class SecureCache {
  SecureCache._();

  static const _storeName = 'bim_store_v1';
  static const _channel = MethodChannel('bimotc.com/cache_security');
  static const _fallbackKeyFile = '.bim_cache_key';
  static const _keyAlphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static Future<MMKV> initialize() async {
    final supportDir = await getApplicationSupportDirectory();
    final rootDir = Directory('${supportDir.path}/.bim_data');
    if (!rootDir.existsSync()) {
      rootDir.createSync(recursive: true);
    }

    await MMKV.initialize(rootDir: rootDir.path, logLevel: MMKVLogLevel.Error);
    final key = await _cacheKey();
    return MMKV(_storeName, cryptKey: key, rootDir: rootDir.path);
  }

  static Future<String> _cacheKey() async {
    try {
      final key = await _channel.invokeMethod<String>('getCacheKey');
      if (key == null || key.isEmpty) {
        throw StateError('Secure cache key is empty.');
      }
      return key;
    } on MissingPluginException {
      AppLogger.info(
        'cache',
        'secure cache native key channel unavailable, using local key file',
      );
    }

    final supportDir = await getApplicationSupportDirectory();
    final keyFile = File('${supportDir.path}/$_fallbackKeyFile');
    if (await keyFile.exists()) {
      final saved = (await keyFile.readAsString()).trim();
      if (saved.isNotEmpty) {
        return saved;
      }
    }

    final key = _newCryptKey();
    await keyFile.writeAsString(key, flush: true);
    return key;
  }

  static String _newCryptKey() {
    final random = Random.secure();
    return List<String>.generate(
      16,
      (_) => _keyAlphabet[random.nextInt(_keyAlphabet.length)],
    ).join();
  }
}
