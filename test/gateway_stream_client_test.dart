import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bim/src/im/gateway_stream_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

void main() {
  test('marks stream healthy only after a valid encrypted frame', () async {
    final key = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (index) => index + 11),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestHandled = Completer<void>();
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.binary;
        request.response.add(
          _secureFrameBytes(
            key: key,
            nonce: nonce,
            frame: const <String, Object?>{
              'type': 'heartbeat',
              'timestamp': 123,
            },
          ),
        );
        await request.response.flush();
        requestHandled.complete();
      }),
    );
    final client = GatewayStreamClient();
    final frameReceived = Completer<GatewayFrame>();

    await client.connect(
      uri: Uri.parse('http://127.0.0.1:${server.port}/api/sync/open'),
      ticket: 'ticket',
      frameKey: base64Encode(key),
      lastCursor: '0-0',
      onFrame: (frame) => frameReceived.complete(frame),
      onClosed: (_, _) {},
    );

    final frame = await frameReceived.future.timeout(
      const Duration(seconds: 2),
    );
    expect(frame.isHeartbeat, isTrue);
    expect(client.hasValidatedFrame, isTrue);
    expect(client.isHealthy(), isTrue);
    await requestHandled.future;
    await client.close();
    await server.close(force: true);
  });

  test('exposes gateway rejection status for ticket refresh', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.first.then((request) async {
        await utf8.decoder.bind(request).join();
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write('{"message":"ticket expired"}');
        await request.response.close();
      }),
    );
    final client = GatewayStreamClient();

    await expectLater(
      client.connect(
        uri: Uri.parse('http://127.0.0.1:${server.port}/api/sync/open'),
        ticket: 'expired-ticket',
        frameKey: base64Encode(Uint8List(32)),
        lastCursor: '0-0',
        onFrame: (_) {},
        onClosed: (_, _) {},
      ),
      throwsA(
        isA<GatewayStreamException>().having(
          (error) => error.statusCode,
          'statusCode',
          HttpStatus.unauthorized,
        ),
      ),
    );

    await client.close();
    await server.close(force: true);
  });
}

Uint8List _secureFrameBytes({
  required Uint8List key,
  required Uint8List nonce,
  required Map<String, Object?> frame,
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(key),
        128,
        nonce,
        Uint8List.fromList(utf8.encode('bim-gateway-frame-v1')),
      ),
    );
  final ciphertext = cipher.process(
    Uint8List.fromList(utf8.encode(jsonEncode(frame))),
  );
  final envelope = utf8.encode(
    jsonEncode(<String, Object?>{
      'type': 'secure',
      'alg': 'AES-256-GCM',
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(ciphertext),
    }),
  );
  final bytes = BytesBuilder(copy: false)
    ..add((ByteData(4)..setUint32(0, envelope.length)).buffer.asUint8List())
    ..add(envelope);
  return bytes.takeBytes();
}
