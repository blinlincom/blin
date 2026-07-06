import 'package:bim/src/core/api_payload_crypto.dart';
import 'package:bim/src/core/api_signer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds IM request sign using backend rule', () {
    const signer = ApiSigner('demo_appkey');
    final sign = signer.sign({
      'appid': '900000002',
      'usertoken': 'token',
      'device': 'ios-device-001',
      'device_flag': '0',
      'timestamp': '1783038000',
      'receiver_id': '900100002',
      'content_type': 'text',
      'content': 'hello',
      'client_msg_no': 'doc-1783038000-001',
    });

    expect(sign, '1e0781ffe6d0baa9cd8f515fb2538341');
  });

  test('encrypts secure payload using backend AES-128-CBC rule', () {
    final result = ApiPayloadCrypto.encrypt(
      payload: const {'type': '1', 'content': 'hello'},
      appId: '1',
      appKey: 'appkey',
      userToken: 'token',
      device: 'device',
      clientMsgNo: 'client',
      timestamp: '100',
      nonce: 'nonce',
    );

    expect(
      result['secure_payload'],
      'xq3g85NV7/+zaOJu/samn2yAxYcu2Vevc/HGKDcoPDk=',
    );
    expect(result['secure_payload_alg'], 'AES-128-CBC');
  });
}
