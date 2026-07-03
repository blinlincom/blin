import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:x25519/x25519.dart';

class TcpImCrypto {
  String _aesKey = '';
  String _salt = '';
  List<int>? _privateKey;
  List<int>? _publicKey;

  List<int> initClientKey() {
    final pair = generateKeyPair();
    _privateKey = pair.privateKey;
    _publicKey = pair.publicKey;
    return _publicKey!;
  }

  void setServerKeyAndSalt(String serverKey, String salt) {
    _salt = salt;
    final privateKey = _privateKey;
    if (privateKey == null) {
      throw StateError('TCP IM client key is not initialized');
    }
    final sharedSecret = X25519(privateKey, base64Decode(serverKey));
    final key = md5Text(base64Encode(sharedSecret));
    _aesKey = key.length > 16 ? key.substring(0, 16) : key;
  }

  String md5Text(String content) {
    return md5.convert(utf8.encode(content)).toString();
  }

  String aesEncrypt(String content) {
    final iv = IV(Uint8List.fromList(_salt.codeUnits));
    final key = Key(Uint8List.fromList(_aesKey.codeUnits));
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    return encrypter.encrypt(content, iv: iv).base64;
  }

  String aesDecrypt(String content) {
    final iv = IV(Uint8List.fromList(_salt.codeUnits));
    final key = Key(Uint8List.fromList(_aesKey.codeUnits));
    final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
    return encrypter.decrypt(Encrypted(base64Decode(content)), iv: iv);
  }
}
