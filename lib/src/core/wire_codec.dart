import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'binary_codec.dart';

class WireCodec {
  const WireCodec._();

  static Map<String, String> pack({
    required Map<String, Object?> payload,
    required String appId,
    required String appKey,
    required String userToken,
    required String device,
    required String clientMsgNo,
    required String timestamp,
    required String nonce,
  }) {
    final key = _key(appId: appId, appKey: appKey, userToken: userToken);
    final iv = _iv(
      device: device,
      clientMsgNo: clientMsgNo,
      timestamp: timestamp,
      nonce: nonce,
    );
    final plain = jsonEncode(_normalized(payload));
    final packed = BinaryCodec.aesCbcPkcs7Encrypt(
      key: key.codeUnits,
      iv: iv.codeUnits,
      plain: utf8.encode(plain),
    );
    return {
      'secure_payload': base64Encode(packed),
      'secure_payload_alg': 'AES-128-CBC',
      'secure_payload_version': '1',
    };
  }

  static Map<String, Object?> unpackResponse({
    required Map<String, Object?> payload,
    required String appId,
    required String appKey,
    required String userToken,
    required String device,
    required String timestamp,
    required String nonce,
  }) {
    final cipherText = payload['secure_payload']?.toString() ?? '';
    if (cipherText.isEmpty) {
      return payload;
    }
    if (payload['secure_payload_alg']?.toString() != 'AES-128-CBC') {
      throw const FormatException('secure_payload_alg不支持');
    }
    final key = _key(appId: appId, appKey: appKey, userToken: userToken);
    final iv = _responseIv(device: device, timestamp: timestamp, nonce: nonce);
    final plain = utf8.decode(
      BinaryCodec.aesCbcPkcs7Decrypt(
        key: key.codeUnits,
        iv: iv.codeUnits,
        cipherText: base64Decode(cipherText),
      ),
    );
    final decoded = jsonDecode(plain);
    if (decoded is Map) {
      return decoded.cast<String, Object?>();
    }
    throw const FormatException('secure_payload格式错误');
  }

  static Future<PackedWireFile> packFile({
    required String filePath,
    required String device,
    required String clientMsgNo,
    required String timestamp,
    required String nonce,
  }) async {
    final source = File(filePath);
    final bytes = await source.readAsBytes();
    final key = _fileKey(
      device: device,
      clientMsgNo: clientMsgNo,
      timestamp: timestamp,
      nonce: nonce,
    );
    final iv = _fileIv(
      device: device,
      clientMsgNo: clientMsgNo,
      timestamp: timestamp,
      nonce: nonce,
    );
    final packedBytes = BinaryCodec.aesCbcPkcs7Encrypt(
      key: key.codeUnits,
      iv: iv.codeUnits,
      plain: bytes,
    );
    final dir = await getTemporaryDirectory();
    final safeName = _basename(
      filePath,
    ).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final packedPath =
        '${dir.path}${Platform.pathSeparator}bim_wire_${DateTime.now().microsecondsSinceEpoch}_$safeName.bin';
    await File(packedPath).writeAsBytes(packedBytes, flush: true);
    return PackedWireFile(
      path: packedPath,
      originalName: safeName.isEmpty ? 'file' : safeName,
      originalSize: bytes.length,
      packedSha256: sha256.convert(packedBytes).toString(),
    );
  }

  static String _key({
    required String appId,
    required String appKey,
    required String userToken,
  }) {
    return md5
        .convert(utf8.encode('$appId|$appKey|$userToken'))
        .toString()
        .substring(0, 16);
  }

  static String _iv({
    required String device,
    required String clientMsgNo,
    required String timestamp,
    required String nonce,
  }) {
    return md5
        .convert(utf8.encode('$device|$clientMsgNo|$timestamp|$nonce'))
        .toString()
        .substring(0, 16);
  }

  static String _responseIv({
    required String device,
    required String timestamp,
    required String nonce,
  }) {
    return md5
        .convert(utf8.encode('$device|response|$timestamp|$nonce'))
        .toString()
        .substring(0, 16);
  }

  static String _fileKey({
    required String device,
    required String clientMsgNo,
    required String timestamp,
    required String nonce,
  }) {
    return sha256
        .convert(utf8.encode('file-key|$device|$clientMsgNo|$timestamp|$nonce'))
        .toString()
        .substring(0, 16);
  }

  static String _fileIv({
    required String device,
    required String clientMsgNo,
    required String timestamp,
    required String nonce,
  }) {
    return sha256
        .convert(utf8.encode('file-iv|$device|$clientMsgNo|$timestamp|$nonce'))
        .toString()
        .substring(0, 16);
  }

  static Object _normalized(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {
        for (final key in keys)
          if (value[key] != null) key: _normalized(value[key]),
      };
    }
    if (value is Iterable) {
      return value.map(_normalized).toList();
    }
    if (value is bool) {
      return value ? '1' : '0';
    }
    if (value is num) {
      return value.toString();
    }
    return value?.toString() ?? '';
  }

  static String _basename(String filePath) {
    final normalized = filePath.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }

  static String randomNonce() {
    final random = Random.secure();
    return List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class PackedWireFile {
  const PackedWireFile({
    required this.path,
    required this.originalName,
    required this.originalSize,
    required this.packedSha256,
  });

  final String path;
  final String originalName;
  final int originalSize;
  final String packedSha256;
}
