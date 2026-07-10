import 'dart:typed_data';

import 'package:pointycastle/export.dart';

class BinaryCodec {
  const BinaryCodec._();

  static Uint8List aesCbcPkcs7Encrypt({
    required List<int> key,
    required List<int> iv,
    required List<int> plain,
  }) {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            true,
            PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
              ParametersWithIV<KeyParameter>(
                KeyParameter(Uint8List.fromList(key)),
                Uint8List.fromList(iv),
              ),
              null,
            ),
          );
    return cipher.process(Uint8List.fromList(plain));
  }

  static Uint8List aesCbcPkcs7Decrypt({
    required List<int> key,
    required List<int> iv,
    required List<int> cipherText,
  }) {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
              ParametersWithIV<KeyParameter>(
                KeyParameter(Uint8List.fromList(key)),
                Uint8List.fromList(iv),
              ),
              null,
            ),
          );
    return cipher.process(Uint8List.fromList(cipherText));
  }

  static Uint8List aesGcmDecrypt({
    required List<int> key,
    required List<int> nonce,
    required List<int> cipherText,
    required List<int> associatedData,
  }) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(Uint8List.fromList(key)),
          128,
          Uint8List.fromList(nonce),
          Uint8List.fromList(associatedData),
        ),
      );
    return cipher.process(Uint8List.fromList(cipherText));
  }
}
