import 'package:flutter/material.dart';
import 'package:mmkv/mmkv.dart';

import 'src/app/bim_app.dart';
import 'src/app/session_controller.dart';
import 'src/core/api_client.dart';
import 'src/core/session_store.dart';
import 'src/im/chat_feature_service.dart';
import 'src/im/im_cache_store.dart';
import 'src/im/wukong_im_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize(logLevel: MMKVLogLevel.Error);
  final store = SessionStore(MMKV.defaultMMKV());
  final api = ApiClient();
  final im = WukongImService(api: api);
  final chat = ChatFeatureService(
    api: api,
    im: im,
    cache: ImCacheStore(MMKV.defaultMMKV()),
  );
  final controller = SessionController(
    api: api,
    store: store,
    im: im,
    chat: chat,
  );
  runApp(BimApp(controller: controller));
}
