import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../design/theme.dart';
import '../features/auth/auth_page.dart';
import '../features/home/home_page.dart';
import 'realtime_event_coordinator.dart';
import 'session_controller.dart';

class BimApp extends StatefulWidget {
  const BimApp({required this.controller, super.key});

  final SessionController controller;

  @override
  State<BimApp> createState() => _BimAppState();
}

class _BimAppState extends State<BimApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _callOverlayKey = GlobalKey<CallOverlayHostState>();
  late final RealtimeEventCoordinator _realtimeCoordinator;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  FriendQrTarget? _pendingFriendQrTarget;
  String _lastFriendQrLink = '';
  DateTime? _lastFriendQrLinkAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _realtimeCoordinator = RealtimeEventCoordinator(
      controller: widget.controller,
      navigatorKey: _navigatorKey,
      callOverlayKey: _callOverlayKey,
    )..start();
    _appLinks = AppLinks();
    _initDeepLinks();
    widget.controller.coldStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _realtimeCoordinator.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.appLifecycleChanged(state);
    _realtimeCoordinator.didChangeAppLifecycleState(state);
  }

  @override
  Future<bool> didPopRoute() async {
    if (_callOverlayKey.currentState?.handleSystemBack() == true) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: BimTheme.light(),
      builder: (context, child) {
        return CallOverlayHost(
          key: _callOverlayKey,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => _root(),
      ),
    );
  }

  Widget _root() {
    if (widget.controller.isLoggedIn) {
      _realtimeCoordinator.onSessionAvailable();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPendingFriendQrTarget();
      });
      return HomePage(controller: widget.controller);
    }
    return AuthPage(controller: widget.controller);
  }

  Future<void> _initDeepLinks() async {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleAppLink,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.warn(
          'deeplink',
          'uri link stream failed',
          data: {'error': error.toString(), 'stack': stackTrace.toString()},
        );
      },
    );
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleAppLink(initial);
      }
    } catch (error, stackTrace) {
      AppLogger.warn(
        'deeplink',
        'initial link failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  void _handleAppLink(Uri uri) {
    final target = parseFriendQrUri(uri);
    if (target == null) {
      AppLogger.info('deeplink', 'ignored app link', data: {'uri': '$uri'});
      return;
    }
    final now = DateTime.now();
    if (_lastFriendQrLink == target.raw &&
        _lastFriendQrLinkAt != null &&
        now.difference(_lastFriendQrLinkAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastFriendQrLink = target.raw;
    _lastFriendQrLinkAt = now;
    AppLogger.info(
      'deeplink',
      'friend qr link received',
      data: {
        'username': target.username,
        'logged_in': widget.controller.isLoggedIn,
      },
    );
    _pendingFriendQrTarget = target;
    if (widget.controller.isLoggedIn) {
      _openPendingFriendQrTarget();
    }
  }

  void _openPendingFriendQrTarget() {
    final target = _pendingFriendQrTarget;
    final navigator = _navigatorKey.currentState;
    if (target == null || navigator == null || !widget.controller.isLoggedIn) {
      return;
    }
    _pendingFriendQrTarget = null;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FriendQrResultPage(controller: widget.controller, target: target),
      ),
    );
  }
}
