import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';

import 'src/app/bim_app.dart';
import 'src/app/session_controller.dart';
import 'src/core/api_client.dart';
import 'src/core/app_logger.dart';
import 'src/core/local_vault.dart';
import 'src/core/session_store.dart';
import 'src/features/moments/moments_cache_store.dart';
import 'src/im/business_im_service.dart';
import 'src/im/chat_feature_service.dart';
import 'src/im/im_cache_store.dart';
import 'src/design/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BootstrapApp());
  FlutterError.onError = (details) {
    AppLogger.error(
      'bootstrap',
      'flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error(
      'bootstrap',
      'platform dispatcher error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  await runZonedGuarded(_initializeAndRun, (error, stackTrace) {
    AppLogger.error(
      'bootstrap',
      'root zone error',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

Timer? _bootstrapWatchdog;

Future<void> _initializeAndRun() async {
  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  );
  _bootstrapWatchdog = Timer(const Duration(seconds: 3), () {
    AppLogger.warn('bootstrap', 'first frame watchdog still on bootstrap');
  });
  try {
    await AppLogger.initialize().timeout(const Duration(seconds: 2));
    AppLogger.info('bootstrap', 'initialize start');
    final kv = await LocalVault.initialize().timeout(
      const Duration(seconds: 5),
    );
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
    AppLogger.info('bootstrap', 'controller ready');
    runApp(BimApp(controller: controller));
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _bootstrapWatchdog?.cancel();
      _bootstrapWatchdog = null;
      AppLogger.info('bootstrap', 'main app first frame rendered');
    });
  } catch (error, stackTrace) {
    AppLogger.error(
      'bootstrap',
      'initialize failed',
      error: error,
      stackTrace: stackTrace,
    );
    runApp(_BootstrapApp(error: error.toString()));
  }
}

class _BootstrapApp extends StatelessWidget {
  const _BootstrapApp({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: BimColors.background,
        body: error == null
            ? const SizedBox.expand()
            : const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: BimSpacing.x8),
                  child: Text(
                    '启动失败，请查看本地日志',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: BimColors.danger,
                      fontSize: BimTypography.body,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
