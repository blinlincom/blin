import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app/bim_app.dart';
import 'src/app/session_controller.dart';
import 'src/core/api_client.dart';
import 'src/core/app_logger.dart';
import 'src/core/secure_cache.dart';
import 'src/core/session_store.dart';
import 'src/features/moments/moments_cache_store.dart';
import 'src/im/business_im_service.dart';
import 'src/im/chat_feature_service.dart';
import 'src/im/im_cache_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await AppLogger.initialize();
  final kv = await SecureCache.initialize();
  final store = SessionStore(kv);
  final api = ApiClient();
  final imCache = ImCacheStore(kv);
  final momentsCache = MomentsCacheStore(kv);
  final im = BusinessImService(api: api, cache: imCache);
  final chat = ChatFeatureService(api: api, cache: imCache);
  final controller = SessionController(
    api: api,
    store: store,
    im: im,
    chat: chat,
    cache: imCache,
    momentsCache: momentsCache,
  );
  runApp(BimApp(controller: controller));
}
