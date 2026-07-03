import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mmkv/mmkv.dart';
import 'package:path_provider/path_provider.dart';

class SecureCache {
  SecureCache._();

  static const _storeName = 'bim_store_v1';
  static const _channel = MethodChannel('bimotc.com/cache_security');

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
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Secure cache key channel is only implemented for Android.',
      );
    }
    final key = await _channel.invokeMethod<String>('getCacheKey');
    if (key == null || key.isEmpty) {
      throw StateError('Secure cache key is empty.');
    }
    return key;
  }
}
