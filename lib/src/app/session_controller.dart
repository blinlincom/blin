import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../calls/livekit_call_models.dart';
import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/models.dart';
import '../core/session_store.dart';
import '../features/moments/moments_cache_store.dart';
import '../im/background_receive_guard.dart';
import '../im/business_im_service.dart';
import '../im/chat_feature_service.dart';
import '../im/im_cache_store.dart';
import '../im/im_message_types.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required ApiClient api,
    required SessionStore store,
    required BusinessImService im,
    required ChatFeatureService chat,
    required ImCacheStore cache,
    required MomentsCacheStore momentsCache,
  }) : _api = api,
       _store = store,
       _im = im,
       _chat = chat,
       _cache = cache,
       _momentsCache = momentsCache {
    _hydrateCachedLaunchState();
    _lastImStatusText = _im.statusText;
    _im.addListener(_onImServiceChanged);
    _presenceSub = _im.presenceEvents.listen(_onPresenceEvent);
    _friendSub = _im.friendEvents.listen(_onFriendEvent);
  }

  final ApiClient _api;
  final SessionStore _store;
  final BusinessImService _im;
  final ChatFeatureService _chat;
  final ImCacheStore _cache;
  final MomentsCacheStore _momentsCache;

  UserSession? _session;
  AppInfo? _appInfo;
  String _device = '';
  bool _booting = true;
  bool _busy = false;
  bool _loginTransitioning = false;
  String? _error;
  int _lastColdLaunchAt = 0;
  int _lastHotResumeAt = 0;
  int _lastResumeLifecycleHandledAt = 0;
  int _lastSessionVerifiedAt = 0;
  DateTime? _lastHotRefreshAt;
  String _lastImStatusText = '';
  bool _handlingImRevocation = false;
  bool _appInfoResolved = false;
  Future<bool>? _appInfoRequest;
  Future<void>? _presenceRefreshRequest;
  Future<void>? _refreshRequest;
  Future<void>? _cachedImStartRequest;
  List<Map<String, Object?>> _friendCache = const [];
  List<Map<String, Object?>> _groupCache = const [];
  List<Map<String, Object?>> _serviceAccountCache = const [];
  DateTime? _friendCacheAt;
  DateTime? _groupCacheAt;
  DateTime? _serviceAccountCacheAt;
  Future<FriendSnapshot>? _friendRequest;
  Future<List<Map<String, Object?>>>? _groupRequest;
  Future<List<Map<String, Object?>>>? _serviceAccountRequest;
  List<Map<String, Object?>> _friendApplyInCache = const [];
  List<Map<String, Object?>> _friendApplyOutCache = const [];
  int _friendApplyUnreadCount = 0;
  final Map<String, Map<String, Object?>> _friendStatusCache =
      <String, Map<String, Object?>>{};
  final Map<String, DateTime> _friendStatusCacheAt = <String, DateTime>{};
  final Map<String, Future<Map<String, Object?>>> _friendStatusRequests =
      <String, Future<Map<String, Object?>>>{};
  final List<BusinessImPresenceEvent> _pendingPresenceEvents =
      <BusinessImPresenceEvent>[];
  StreamSubscription<BusinessImPresenceEvent>? _presenceSub;
  StreamSubscription<BusinessImFriendEvent>? _friendSub;
  bool _backgroundReceiveProtectionEnabled = true;
  BackgroundReceiveStatus _backgroundReceiveStatus =
      BackgroundReceiveStatus.unsupported('unknown', '尚未检测');
  WalletBalance? _walletBalance;
  Future<WalletBalance>? _walletBalanceRequest;

  UserSession? get session => _session;
  AppInfo? get appInfo => _appInfo;
  bool get appInfoResolved => _appInfoResolved;
  AppAuthConfig get authConfig => _appInfo?.auth ?? AppAuthConfig.defaults;
  String get device => _device;
  bool get booting => _booting;
  bool get busy => _busy;
  String? get error => _error;
  bool get isLoggedIn =>
      !_loginTransitioning &&
      (_session?.userToken.isNotEmpty == true ||
          _store.readSession()?.userToken.isNotEmpty == true);
  bool get isSessionRestoring =>
      _booting || _refreshRequest != null || (isLoggedIn && !_im.isStarted);
  int get lastColdLaunchAt => _lastColdLaunchAt;
  int get lastHotResumeAt => _lastHotResumeAt;
  int get lastSessionVerifiedAt => _lastSessionVerifiedAt;
  String get imStatusText => _im.statusText;
  String? get imError => _im.lastError;
  bool get backgroundReceiveProtectionEnabled =>
      _backgroundReceiveProtectionEnabled;
  BackgroundReceiveStatus get backgroundReceiveStatus =>
      _backgroundReceiveStatus;
  bool get _effectiveBackgroundKeepAliveEnabled =>
      _backgroundReceiveProtectionEnabled && Platform.isAndroid;
  int get conversationVersion => _im.conversationVersion;
  bool get initialHistorySyncing => _im.initialHistorySyncing;
  bool get initialHistorySyncBlocked => _im.initialHistorySyncBlocked;
  BusinessImInitialSyncState get initialHistorySyncState =>
      _im.initialHistorySyncState;
  bool get hasLoadedFriends => _friendCacheAt != null;
  bool get hasLoadedServiceAccounts => _serviceAccountCacheAt != null;
  int get friendApplyUnreadCount => _friendApplyUnreadCount;
  Stream<BusinessImMessageEvent> get messageEvents => _im.messageEvents;
  Stream<BusinessImPresenceEvent> get presenceEvents => _im.presenceEvents;
  Stream<BusinessImCallEvent> get callEvents => _im.callEvents;
  Stream<BusinessImFriendEvent> get friendEvents => _im.friendEvents;
  WalletBalance? get walletBalance {
    final current = _session ?? _store.readSession();
    if (_walletBalance != null) {
      return _walletBalance;
    }
    if (current == null) {
      return null;
    }
    _walletBalance = _store.readWalletBalance(current.userId);
    return _walletBalance;
  }

  List<Map<String, Object?>> cachedConversations() {
    final memoryCache = _im.cachedConversations();
    if (memoryCache.isNotEmpty) {
      return memoryCache;
    }
    final current = _session ?? _store.readSession();
    if (current == null) {
      return const [];
    }
    return _cachedConversationsForSession(current);
  }

  void _hydrateCachedLaunchState() {
    _device = _store.ensureDeviceId();
    _session = _store.readSession();
    final cachedAppInfo = _store.readAppInfo();
    _appInfoResolved = cachedAppInfo != null;
    _appInfo = cachedAppInfo ?? const AppInfo(name: AppConfig.appName);
    _backgroundReceiveProtectionEnabled = _store
        .readBackgroundReceiveProtectionEnabled();
    _lastSessionVerifiedAt = _store.readSessionVerifiedAt();
    if (_session != null) {
      _walletBalance = _store.readWalletBalance(_session!.userId);
    }
    final chatUid = _session?.chat?.uid ?? '';
    if (chatUid.isNotEmpty) {
      _friendApplyUnreadCount = _cache.readFriendApplyUnread(chatUid);
      _friendApplyInCache = _cache.readFriendApplyList(
        uid: chatUid,
        type: 'in',
      );
      _friendApplyOutCache = _cache.readFriendApplyList(
        uid: chatUid,
        type: 'out',
      );
    }
    AppLogger.info(
      'session',
      'launch cache hydrated',
      data: {
        'logged_in': _session != null,
        'device': _device,
        'background_receive_enabled': _backgroundReceiveProtectionEnabled,
        'last_session_verified_at': _lastSessionVerifiedAt,
        'friend_apply_unread': _friendApplyUnreadCount,
      },
    );
  }

  List<Map<String, Object?>> cachedFriends({bool allowDisk = true}) {
    if (_friendCache.isNotEmpty) {
      return _copyList(_friendCache);
    }
    if (!allowDisk) {
      return const [];
    }
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    _friendCache = _hydrateFriendList(_cache.readFriendList(uid), uid: uid);
    return _copyList(_friendCache);
  }

  List<Map<String, Object?>> cachedFriendApplications({
    String type = 'in',
    bool allowDisk = true,
  }) {
    final normalized = _friendApplyType(type);
    final memory = normalized == 'out'
        ? _friendApplyOutCache
        : _friendApplyInCache;
    if (memory.isNotEmpty) {
      return _copyList(memory);
    }
    if (!allowDisk) {
      return const [];
    }
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    final cached = _cache.readFriendApplyList(uid: uid, type: normalized);
    if (normalized == 'out') {
      _friendApplyOutCache = cached;
    } else {
      _friendApplyInCache = cached;
    }
    return _copyList(cached);
  }

  List<Map<String, Object?>> cachedGroups() {
    if (_groupCache.isNotEmpty) {
      return _copyList(_groupCache);
    }
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    _groupCache = _cache.readGroupList(uid);
    return _copyList(_groupCache);
  }

  List<Map<String, Object?>> cachedServiceAccounts({bool allowDisk = true}) {
    if (_serviceAccountCache.isNotEmpty) {
      return _copyList(_serviceAccountCache);
    }
    if (!allowDisk) {
      return const [];
    }
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    _serviceAccountCache = _cache.readServiceAccounts(uid);
    return _copyList(_serviceAccountCache);
  }

  Map<String, Object?> groupMuteState({
    required String channelId,
    required String groupId,
  }) {
    return _im.groupMuteState(channelID: channelId, groupId: groupId);
  }

  int messageVersion({required String channelId, required int channelType}) =>
      _im.messageVersion(channelID: channelId, channelType: channelType);

  Future<void> coldStart() async {
    AppLogger.info('session', 'cold start');
    _booting = true;
    _error = null;
    notifyListeners();

    _device = _store.ensureDeviceId();
    _lastColdLaunchAt = _store.markColdLaunch();
    _lastHotResumeAt = _store.readResumeAt();
    _lastSessionVerifiedAt = _store.readSessionVerifiedAt();
    _session = _store.readSession();
    final cachedAppInfo = _store.readAppInfo();
    _appInfoResolved = cachedAppInfo != null;
    _appInfo = cachedAppInfo ?? const AppInfo(name: AppConfig.appName);

    try {
      if (_session != null) {
        _refreshAppInfoInBackground(
          source: 'cold_start_logged_in',
          hasCachedAppInfo: cachedAppInfo != null,
        );
        await _refreshLoggedInSession();
      } else if (cachedAppInfo != null) {
        _refreshAppInfoInBackground(
          source: 'cold_start_auth_cached',
          hasCachedAppInfo: true,
        );
      } else {
        await _requestAppInfo(source: 'cold_start_auth');
      }
      AppLogger.info(
        'session',
        'cold start success',
        data: {'logged_in': _session != null, 'device': _device},
      );
    } on ApiException catch (error, stackTrace) {
      _handleSessionRefreshApiError(
        error,
        source: 'cold_start',
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      _handleSessionRefreshUnexpectedError(
        error,
        source: 'cold_start',
        stackTrace: stackTrace,
      );
    } finally {
      _booting = false;
      notifyListeners();
    }
  }

  Future<void> hotResume() async {
    AppLogger.info('session', 'hot resume');
    _lastHotResumeAt = _store.markHotResume();
    _lastSessionVerifiedAt = _store.readSessionVerifiedAt();
    final memorySession = _session;
    final storedSession = _store.readSession();
    if (storedSession == null) {
      if (memorySession == null) {
        AppLogger.info('session', 'hot resume without cached session');
        return;
      }
      _session = memorySession;
      _store.writeSession(memorySession);
      AppLogger.warn(
        'session',
        'hot resume kept memory session after empty disk cache',
        data: {
          'user_id': memorySession.userId,
          'last_session_verified_at': _lastSessionVerifiedAt,
        },
      );
    } else {
      _session = storedSession;
      if (!_isSameSessionIdentity(memorySession, storedSession)) {
        AppLogger.info(
          'session',
          'hot resume restored persisted session',
          data: {'user_id': storedSession.userId},
        );
        notifyListeners();
      }
    }
    if (_session == null) {
      return;
    }
    unawaited(_applyBackgroundReceiveProtection(source: 'hot_resume'));
    if (_im.isStarted) {
      AppLogger.info('session', 'hot resume use existing im session');
      _im.resumeConnection();
      return;
    }
    final lastRefresh = _lastHotRefreshAt;
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < const Duration(seconds: 20)) {
      AppLogger.info('session', 'skip hot resume refresh');
      _im.resumeConnection();
      return;
    }
    try {
      await _refreshLoggedInSession();
      _im.resumeConnection();
      _lastHotRefreshAt = DateTime.now();
      AppLogger.info('session', 'hot resume success');
    } on ApiException catch (error, stackTrace) {
      _handleSessionRefreshApiError(
        error,
        source: 'hot_resume',
        stackTrace: stackTrace,
      );
      notifyListeners();
    } catch (error, stackTrace) {
      _handleSessionRefreshUnexpectedError(
        error,
        source: 'hot_resume',
        stackTrace: stackTrace,
      );
      notifyListeners();
    }
  }

  bool _isSameSessionIdentity(UserSession? left, UserSession? right) {
    return left?.userId == right?.userId &&
        left?.userToken == right?.userToken &&
        left?.chat?.uid == right?.chat?.uid;
  }

  void _refreshAppInfoInBackground({
    required String source,
    required bool hasCachedAppInfo,
  }) {
    AppLogger.info(
      'session',
      'app info refresh scheduled',
      data: {'source': source, 'has_cached_app_info': hasCachedAppInfo},
    );
    unawaited(_requestAppInfo(source: source));
  }

  Future<bool> _requestAppInfo({required String source}) {
    final existing = _appInfoRequest;
    if (existing != null) {
      AppLogger.info(
        'session',
        'reuse app info request',
        data: {'source': source},
      );
      return existing;
    }
    final request = _loadAppInfo(source: source);
    _appInfoRequest = request;
    request.whenComplete(() {
      if (identical(_appInfoRequest, request)) {
        _appInfoRequest = null;
      }
    });
    return request;
  }

  Future<bool> _loadAppInfo({required String source}) async {
    try {
      final appInfo = await _api.getAppInfo();
      final previous = _appInfo;
      final changed =
          previous == null ||
          jsonEncode(previous.toJson()) != jsonEncode(appInfo.toJson());
      _appInfo = appInfo;
      _appInfoResolved = true;
      _store.writeAppInfo(appInfo);
      AppLogger.info(
        'session',
        'app info refreshed',
        data: {'source': source, 'app_name': appInfo.name},
      );
      if (changed) {
        notifyListeners();
      }
      return true;
    } catch (error, stackTrace) {
      AppLogger.warn(
        'session',
        'app info refresh failed',
        data: {
          'source': source,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      return false;
    }
  }

  Future<bool> refreshAppInfoForAuth({String source = 'auth_page'}) async {
    if (_booting && !_appInfoResolved) {
      final refreshed = await _requestAppInfo(source: source);
      return refreshed || _appInfoResolved;
    }
    if (_appInfoResolved) {
      _refreshAppInfoInBackground(source: source, hasCachedAppInfo: true);
      return true;
    }
    return _requestAppInfo(source: source);
  }

  void _handleSessionRefreshApiError(
    ApiException error, {
    required String source,
    required StackTrace stackTrace,
  }) {
    if (_shouldEndCachedLogin(error)) {
      _endCachedLogin(
        source: source,
        message: error.message.isEmpty ? '登录状态已失效' : error.message,
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    _error = null;
    AppLogger.warn(
      'session',
      'session refresh failed, keep cached login',
      data: {
        'source': source,
        'code': error.code,
        'message': error.message,
        'last_session_verified_at': _lastSessionVerifiedAt,
      },
    );
    _startCachedImForPersistentLogin(source: source);
  }

  void _handleSessionRefreshUnexpectedError(
    Object error, {
    required String source,
    required StackTrace stackTrace,
  }) {
    if (_session == null) {
      _error = error.toString();
      AppLogger.error(
        'session',
        '$source failed without cached login',
        error: error,
        stackTrace: stackTrace,
      );
      return;
    }
    _error = null;
    AppLogger.warn(
      'session',
      'session refresh crashed, keep cached login',
      data: {
        'source': source,
        'error': error.toString(),
        'stack': stackTrace.toString(),
        'last_session_verified_at': _lastSessionVerifiedAt,
      },
    );
    _startCachedImForPersistentLogin(source: source);
  }

  bool _shouldEndCachedLogin(ApiException error) {
    final text = error.message.toLowerCase();
    return _containsAny(text, const [
      'account disabled',
      'account banned',
      'account frozen',
      'account deleted',
      'password changed',
      'token revoked',
      'session revoked',
      'credential revoked',
      'login session expired',
      'device kicked',
      'forced logout',
      'force logout',
      '账号已禁用',
      '账户已禁用',
      '账号被禁用',
      '账户被禁用',
      '账号已冻结',
      '账户已冻结',
      '账号被冻结',
      '账户被冻结',
      '账号已注销',
      '账户已注销',
      '账号被注销',
      '账户被注销',
      '密码已修改',
      '密码被修改',
      '登录密码已修改',
      'token已吊销',
      'token被吊销',
      '登录态已吊销',
      '会话已吊销',
      '凭证已吊销',
      '凭证被吊销',
      '登录状态已失效',
      '登录会话已失效',
      '设备已被踢',
      '设备被踢',
      '被踢下线',
      '踢下线',
      '强制下线',
      '强制退出',
    ]);
  }

  bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  void _endCachedLogin({
    required String source,
    required String message,
    required Object error,
    required StackTrace stackTrace,
  }) {
    _store.clearSession();
    _session = null;
    _clearListCaches();
    _error = message;
    AppLogger.error(
      'session',
      'cached login ended by explicit server revocation',
      error: error,
      stackTrace: stackTrace,
      data: {'source': source, 'message': message},
    );
    unawaited(
      _im.stop(logout: true).catchError((Object stopError) {
        AppLogger.warn(
          'session',
          'im stop after session revocation failed',
          data: {'source': source, 'error': stopError.toString()},
        );
      }),
    );
  }

  void _startCachedImForPersistentLogin({required String source}) {
    final current = _session ?? _store.readSession();
    if (current == null) {
      return;
    }
    if (_im.isStarted) {
      AppLogger.info(
        'session',
        'cached login keeps existing im session',
        data: {'source': source},
      );
      _im.resumeConnection();
      return;
    }
    final chat = current.chat;
    if (chat == null || chat.uid.isEmpty || chat.token.isEmpty) {
      AppLogger.warn(
        'session',
        'cached im start skipped without chat materials',
        data: {'source': source, 'has_chat': chat != null},
      );
      return;
    }
    final existing = _cachedImStartRequest;
    if (existing != null) {
      AppLogger.info(
        'session',
        'reuse cached im start request',
        data: {'source': source, 'uid': chat.uid},
      );
      unawaited(existing);
      return;
    }
    AppLogger.info(
      'session',
      'cached im start scheduled for persistent login',
      data: {'source': source, 'uid': chat.uid},
    );
    final request = _queueCachedImStart(current, source: source);
    unawaited(request);
  }

  Future<void> _queueCachedImStart(
    UserSession session, {
    required String source,
  }) {
    late final Future<void> request;
    request = _startCachedIm(session, source: source).whenComplete(() {
      if (identical(_cachedImStartRequest, request)) {
        _cachedImStartRequest = null;
      }
    });
    _cachedImStartRequest = request;
    return request;
  }

  Future<void> _startCachedIm(
    UserSession session, {
    required String source,
  }) async {
    try {
      await _im.start(
        session,
        device: _device,
        backgroundKeepAliveEnabled: _effectiveBackgroundKeepAliveEnabled,
      );
      unawaited(_applyBackgroundReceiveProtection(source: source));
      AppLogger.info(
        'session',
        'cached im start success',
        data: {'source': source},
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'session',
        'cached im start failed, keep cached login',
        data: {
          'source': source,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    }
  }

  void appLifecycleChanged(AppLifecycleState state) {
    AppLogger.info('session', 'app lifecycle', data: {'state': state.name});
    switch (state) {
      case AppLifecycleState.resumed:
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastResumeLifecycleHandledAt < 1200) {
          AppLogger.info(
            'session',
            'hot resume skipped by lifecycle debounce',
            data: {'elapsed_ms': now - _lastResumeLifecycleHandledAt},
          );
          return;
        }
        _lastResumeLifecycleHandledAt = now;
        hotResume();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _im.onAppBackgrounded(state.name);
        break;
    }
  }

  Future<void> login({
    required String username,
    required String password,
    String captcha = '',
  }) async {
    await _runBusy(() async {
      _loginTransitioning = true;
      try {
        final session = await _api.login(
          username: username,
          password: password,
          captcha: captcha,
          device: _device,
        );
        _handlingImRevocation = false;
        _session = session;
        _store.writeSession(session);
        try {
          await _refreshLoggedInSession();
        } catch (error, stackTrace) {
          await _rollbackFreshLogin(
            source: 'login_password',
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
      } finally {
        _loginTransitioning = false;
      }
    });
  }

  Future<void> loginWithMobile({
    required String mobile,
    required String code,
    String captcha = '',
  }) async {
    await _runBusy(() async {
      _loginTransitioning = true;
      try {
        final session = await _api.loginWithMobile(
          mobile: mobile,
          code: code,
          captcha: captcha,
          device: _device,
        );
        _handlingImRevocation = false;
        _session = session;
        _store.writeSession(session);
        try {
          await _refreshLoggedInSession();
        } catch (error, stackTrace) {
          await _rollbackFreshLogin(
            source: 'login_mobile',
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
      } finally {
        _loginTransitioning = false;
      }
    });
  }

  Future<ImageCaptcha> loadImageCaptcha({required int type}) {
    return _api.getImageCaptcha(type: type);
  }

  Future<void> _rollbackFreshLogin({
    required String source,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    _store.clearSession();
    _session = null;
    _clearListCaches();
    await _im.stop().catchError((Object stopError, StackTrace stopStack) {
      AppLogger.warn(
        'session',
        'fresh login rollback im stop failed',
        data: {
          'source': source,
          'error': stopError.toString(),
          'stack': stopStack.toString(),
        },
      );
    });
    AppLogger.error(
      'session',
      'fresh login initialization failed and rolled back',
      error: error,
      stackTrace: stackTrace,
      data: {'source': source},
    );
  }

  Future<void> register({
    required String username,
    required String password,
    String nickname = '',
    String mobile = '',
    String email = '',
    String captcha = '',
    String inviteCode = '',
  }) async {
    await _runBusy(() {
      return _api.register(
        username: username,
        password: password,
        nickname: nickname,
        mobile: mobile,
        email: email,
        captcha: captcha,
        inviteCode: inviteCode,
        device: _device,
      );
    });
  }

  Future<void> sendEmailCode(
    String email, {
    int type = 1,
    String captcha = '',
  }) {
    return _runBusy(
      () => _api.sendEmailCode(
        email,
        device: _device,
        type: type,
        captcha: captcha,
      ),
    );
  }

  Future<void> sendMobileCode(
    String mobile, {
    int type = 2,
    String captcha = '',
  }) {
    return _runBusy(
      () => _api.sendMobileCode(
        mobile,
        device: _device,
        type: type,
        captcha: captcha,
      ),
    );
  }

  Future<WalletBalance> loadWalletBalance({bool refresh = true}) async {
    final current = _requireSession();
    if (!refresh) {
      final cached = _store.readWalletBalance(current.userId);
      if (cached != null) {
        _walletBalance = cached;
        notifyListeners();
        return cached;
      }
    }
    final running = _walletBalanceRequest;
    if (running != null) {
      return running;
    }
    final request = _api
        .walletBalance(session: current, device: _device)
        .then((value) {
          _walletBalance = value;
          _store.writeWalletBalance(userId: current.userId, data: value);
          AppLogger.info(
            'wallet',
            'wallet balance loaded',
            data: {
              'balance': value.balance,
              'pay_password_set': value.payPasswordSet,
              'merchant_enabled': value.merchantEnabled,
            },
          );
          notifyListeners();
          return value;
        })
        .whenComplete(() => _walletBalanceRequest = null);
    _walletBalanceRequest = request;
    return request;
  }

  Future<OtcConfig> loadOtcConfig() {
    final current = _requireSession();
    return _api.otcConfig(session: current, device: _device);
  }

  Future<UsdtWalletOverview> loadUsdtWalletOverview() {
    final current = _requireSession();
    return _api.usdtWalletOverview(session: current, device: _device);
  }

  Future<Map<String, Object?>> loadUsdtDepositAddress() {
    final current = _requireSession();
    return _api.usdtDepositAddress(session: current, device: _device);
  }

  Future<Map<String, Object?>> previewUsdtTransfer({
    required String username,
    required String amount,
  }) {
    final current = _requireSession();
    return _api.usdtTransferPreview(
      session: current,
      device: _device,
      username: username,
      amount: amount,
    );
  }

  Future<Map<String, Object?>> createUsdtTransfer({
    required String username,
    required String amount,
    required String payPassword,
    String remark = '',
  }) {
    final current = _requireSession();
    return _api.usdtTransferCreate(
      session: current,
      device: _device,
      username: username,
      amount: amount,
      payPassword: payPassword,
      remark: remark,
    );
  }

  Future<Map<String, Object?>> previewUsdtWithdraw({
    required String address,
    required String amount,
  }) {
    final current = _requireSession();
    return _api.usdtWithdrawPreview(
      session: current,
      device: _device,
      address: address,
      amount: amount,
    );
  }

  Future<Map<String, Object?>> createUsdtWithdraw({
    required String address,
    required String amount,
    required String payPassword,
  }) {
    final current = _requireSession();
    return _api.usdtWithdrawCreate(
      session: current,
      device: _device,
      address: address,
      amount: amount,
      payPassword: payPassword,
    );
  }

  Future<List<UsdtAssetBill>> loadUsdtAssetBills() {
    final current = _requireSession();
    return _api.usdtAssetBills(session: current, device: _device);
  }

  Future<List<OtcAd>> loadOtcAds(String side) {
    final current = _requireSession();
    return _api.otcAds(session: current, device: _device, side: side);
  }

  Future<List<OtcOrder>> loadOtcOrders() {
    final current = _requireSession();
    return _api.otcOrders(session: current, device: _device);
  }

  Future<OtcOrder> createOtcOrder({
    required int adId,
    required String side,
    required String fiatAmount,
    required int addressId,
    required int paymentMethodId,
  }) {
    final current = _requireSession();
    return _api.otcCreateOrder(
      session: current,
      device: _device,
      adId: adId,
      side: side,
      fiatAmount: fiatAmount,
      addressId: addressId,
      paymentMethodId: paymentMethodId,
    );
  }

  Future<List<Map<String, Object?>>> loadOtcAddresses() {
    final current = _requireSession();
    return _api.otcAddresses(session: current, device: _device);
  }

  Future<Map<String, Object?>> saveOtcAddress({
    required int assetId,
    required int networkId,
    required String label,
    required String address,
  }) {
    final current = _requireSession();
    return _api.otcSaveAddress(
      session: current,
      device: _device,
      assetId: assetId,
      networkId: networkId,
      label: label,
      address: address,
    );
  }

  Future<List<Map<String, Object?>>> loadOtcPaymentMethods() {
    final current = _requireSession();
    return _api.otcPaymentMethods(session: current, device: _device);
  }

  Future<Map<String, Object?>> saveOtcPaymentMethod({
    required String type,
    required String name,
    required String account,
    String bankName = '',
  }) {
    final current = _requireSession();
    return _api.otcSavePaymentMethod(
      session: current,
      device: _device,
      type: type,
      name: name,
      account: account,
      bankName: bankName,
    );
  }

  Future<Map<String, Object?>> applyOtcMerchant({
    required String payPassword,
    String remark = '',
  }) {
    final current = _requireSession();
    return _api.otcApplyMerchant(
      session: current,
      device: _device,
      payPassword: payPassword,
      remark: remark,
    );
  }

  Future<Map<String, Object?>> createOtcMerchantAd({
    required String side,
    required int assetId,
    required int networkId,
    required String price,
    required String minFiat,
    required String maxFiat,
    required String availableAsset,
    required List<String> paymentMethods,
    String terms = '',
  }) {
    final current = _requireSession();
    return _api.otcCreateMerchantAd(
      session: current,
      device: _device,
      side: side,
      assetId: assetId,
      networkId: networkId,
      price: price,
      minFiat: minFiat,
      maxFiat: maxFiat,
      availableAsset: availableAsset,
      paymentMethods: paymentMethods,
      terms: terms,
    );
  }

  Future<Map<String, Object?>> payOtcMerchantDeposit(String payPassword) {
    final current = _requireSession();
    return _api.otcPayMerchantDeposit(
      session: current,
      device: _device,
      payPassword: payPassword,
    );
  }

  Future<List<WalletBill>> loadWalletBills({
    String scene = 'all',
    int page = 1,
    int limit = 20,
  }) {
    final current = _requireSession();
    return _api.walletBills(
      session: current,
      device: _device,
      scene: scene,
      page: page,
      limit: limit,
    );
  }

  Future<WalletBill> loadWalletBillDetail(int billId) {
    final current = _requireSession();
    return _api.walletBillDetail(
      session: current,
      device: _device,
      billId: billId,
    );
  }

  Future<Map<String, Object?>> sendWalletPayPasswordCode({
    String verificationMethod = '',
    required String captcha,
  }) {
    final current = _requireSession();
    return _api.walletSendPayPasswordCode(
      session: current,
      device: _device,
      verificationMethod: verificationMethod,
      captcha: captcha,
    );
  }

  Future<UserSecurityInfo> loadUserSecurityInfo() {
    final current = _requireSession();
    return _api.userSecurityInfo(session: current, device: _device);
  }

  Future<void> sendMobileBindCode({
    required String mobile,
    required String captcha,
  }) {
    final current = _requireSession();
    return _api.sendUserMobileBindCode(
      session: current,
      device: _device,
      mobile: mobile,
      captcha: captcha,
    );
  }

  Future<UserSecurityInfo> confirmMobileBind({
    required String mobile,
    required String code,
  }) {
    final current = _requireSession();
    return _api.confirmUserMobileBind(
      session: current,
      device: _device,
      mobile: mobile,
      code: code,
    );
  }

  Future<void> sendEmailBindCode({
    required String email,
    required String captcha,
  }) {
    final current = _requireSession();
    return _api.sendUserEmailBindCode(
      session: current,
      device: _device,
      email: email,
      captcha: captcha,
    );
  }

  Future<UserSecurityInfo> confirmEmailBind({
    required String email,
    required String code,
  }) {
    final current = _requireSession();
    return _api.confirmUserEmailBind(
      session: current,
      device: _device,
      email: email,
      code: code,
    );
  }

  Future<void> setWalletPayPassword({
    required String password,
    required String verificationMethod,
    required String verifyCode,
  }) async {
    final current = _requireSession();
    await _api.walletSetPayPassword(
      session: current,
      device: _device,
      password: password,
      verificationMethod: verificationMethod,
      verifyCode: verifyCode,
    );
    await loadWalletBalance(refresh: true);
  }

  Future<void> rechargeWalletByKm(String km) async {
    final current = _requireSession();
    await _api.walletRechargeKm(session: current, device: _device, km: km);
    await loadWalletBalance(refresh: true);
  }

  Future<void> withdrawWallet({
    required String amount,
    required String account,
    required String name,
    String remark = '',
  }) async {
    final current = _requireSession();
    await _api.walletWithdraw(
      session: current,
      device: _device,
      amount: amount,
      account: account,
      name: name,
      remark: remark,
    );
    await loadWalletBalance(refresh: true);
  }

  Future<List<WalletWithdrawRecord>> loadWalletWithdrawRecords({
    int page = 1,
    int limit = 20,
  }) {
    final current = _requireSession();
    return _api.walletWithdrawRecords(
      session: current,
      device: _device,
      page: page,
      limit: limit,
    );
  }

  Future<WalletOrder> currentWalletCollectCode({
    String amount = '',
    String remark = '',
  }) {
    final current = _requireSession();
    return _api.walletCurrentCollectCode(
      session: current,
      device: _device,
      amount: amount,
      remark: remark,
    );
  }

  Future<WalletOrder> currentWalletPayCode({
    String remark = '',
    String payPassword = '',
  }) {
    final current = _requireSession();
    return _api.walletCurrentPayCode(
      session: current,
      device: _device,
      remark: remark,
      payPassword: payPassword,
    );
  }

  Future<WalletOrder> scanWalletQr(String qrToken) {
    final current = _requireSession();
    return _api.walletScanQr(
      session: current,
      device: _device,
      qrToken: qrToken,
    );
  }

  Future<WalletOrder> confirmWalletQrPay({
    required String qrToken,
    required String payPassword,
    String amount = '',
  }) async {
    final current = _requireSession();
    final order = await _api.walletConfirmQrPay(
      session: current,
      device: _device,
      qrToken: qrToken,
      payPassword: payPassword,
      amount: amount,
      requestId: _walletRequestId(),
    );
    await loadWalletBalance(refresh: true);
    return order;
  }

  Future<WalletOrder> confirmWalletPayCodeOrder({
    required String orderNo,
    required String payPassword,
  }) async {
    final current = _requireSession();
    final order = await _api.walletConfirmQrPay(
      session: current,
      device: _device,
      orderNo: orderNo,
      payPassword: payPassword,
      amount: '',
      requestId: _walletRequestId(),
    );
    await loadWalletBalance(refresh: true);
    return order;
  }

  Future<WalletOrder> loadWalletOrderStatus(String orderNo) {
    final current = _requireSession();
    return _api.walletOrderStatus(
      session: current,
      device: _device,
      orderNo: orderNo,
    );
  }

  Future<List<Map<String, Object?>>> loadConversations() async {
    final current = _requireSession();
    final cached = _cachedConversationsForSession(current);
    AppLogger.info('session', 'load conversations start');
    try {
      await _ensureImReadyForConversationRead(cachedCount: cached.length);
      final local = await _im.loadConversations().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          AppLogger.warn(
            'session',
            'local conversations timeout, use cached conversations',
            data: {'cached_count': cached.length},
          );
          final memoryCache = _im.cachedConversations();
          return memoryCache.isNotEmpty ? memoryCache : cached;
        },
      );
      AppLogger.info(
        'session',
        'load conversations local success',
        data: {'count': local.length},
      );
      return local;
    } catch (error, stackTrace) {
      final memoryCache = _im.cachedConversations();
      final fallback = memoryCache.isNotEmpty ? memoryCache : cached;
      if (fallback.isNotEmpty) {
        final isLoginRace = error.toString().contains('请先登录');
        if (isLoginRace) {
          AppLogger.info(
            'session',
            'conversation load deferred until im session ready',
            data: {'cached_count': fallback.length},
          );
        } else {
          AppLogger.warn(
            'session',
            'load conversations failed, keep cached conversations',
            data: {
              'cached_count': fallback.length,
              'error': error.toString(),
              'stack': stackTrace.toString(),
            },
          );
          _startCachedImForPersistentLogin(
            source: 'load_conversations_fallback',
          );
        }
        return fallback;
      }
      rethrow;
    }
  }

  Future<void> _ensureImReadyForConversationRead({
    required int cachedCount,
  }) async {
    if (_im.isStarted) {
      return;
    }
    final refresh = _refreshRequest;
    if (refresh != null) {
      AppLogger.info(
        'session',
        'conversation load waits session refresh',
        data: {'cached_count': cachedCount},
      );
      await refresh;
      if (_im.isStarted) {
        return;
      }
    }
    final current = _session ?? _store.readSession();
    final chat = current?.chat;
    if (current == null ||
        chat == null ||
        chat.uid.isEmpty ||
        chat.token.isEmpty) {
      return;
    }
    final start = _cachedImStartRequest;
    if (start != null) {
      AppLogger.info(
        'session',
        'conversation load waits cached im start',
        data: {'uid': chat.uid, 'cached_count': cachedCount},
      );
      await start;
      return;
    }
    AppLogger.info(
      'session',
      'conversation load starts cached im session',
      data: {'uid': chat.uid, 'cached_count': cachedCount},
    );
    final request = _queueCachedImStart(current, source: 'conversation_load');
    await request;
  }

  Future<List<Map<String, Object?>>> loadFriends({
    bool forceRefresh = false,
  }) async {
    final current = _requireSession();
    if (!forceRefresh && _isCacheFresh(_friendCacheAt)) {
      AppLogger.info(
        'session',
        'load friends memory cache',
        data: {'count': _friendCache.length},
      );
      return _copyList(_friendCache);
    }
    var request = _friendRequest;
    if (request == null) {
      AppLogger.info('session', 'load friends start');
      request = _api
          .friends(session: current, device: _device)
          .timeout(const Duration(seconds: 15));
      _friendRequest = request;
    } else {
      AppLogger.info('session', 'reuse friends request');
    }
    final snapshot = await request.whenComplete(() {
      if (identical(_friendRequest, request)) {
        _friendRequest = null;
      }
    });
    if (!snapshot.complete || snapshot.version.isEmpty) {
      throw ApiException('好友数据同步未完成');
    }
    final list = _mergePendingPresenceIntoFriendList(
      _hydrateFriendList(snapshot.items),
    );
    _friendCache = list;
    _friendCacheAt = DateTime.now();
    _writeFriendCache(list);
    notifyListeners();
    AppLogger.info(
      'session',
      'load friends success',
      data: {'count': list.length},
    );
    return _copyList(list);
  }

  Future<List<Map<String, Object?>>> loadServiceAccounts({
    bool forceRefresh = false,
  }) async {
    final current = _requireSession();
    if (!forceRefresh && _isCacheFresh(_serviceAccountCacheAt)) {
      AppLogger.info(
        'session',
        'load service accounts memory cache',
        data: {'count': _serviceAccountCache.length},
      );
      return _copyList(_serviceAccountCache);
    }
    if (_serviceAccountRequest != null) {
      AppLogger.info('session', 'reuse service accounts request');
      return _serviceAccountRequest!;
    }
    AppLogger.info('session', 'load service accounts start');
    _serviceAccountRequest = _api
        .serviceAccounts(session: current, device: _device)
        .timeout(const Duration(seconds: 15));
    final list = await _serviceAccountRequest!.whenComplete(
      () => _serviceAccountRequest = null,
    );
    _serviceAccountCache = list;
    _serviceAccountCacheAt = DateTime.now();
    _writeServiceAccountCache(list);
    notifyListeners();
    AppLogger.info(
      'session',
      'load service accounts success',
      data: {'count': list.length},
    );
    return _copyList(list);
  }

  Future<Map<String, Object?>> loadServiceAccountDetail(int serviceId) async {
    final current = _requireSession();
    final detail = await _api.serviceAccountDetail(
      session: current,
      device: _device,
      serviceId: serviceId,
    );
    _upsertServiceAccountCache(detail);
    return detail;
  }

  Future<Map<String, Object?>> updateServiceAccountSettings({
    required int serviceId,
    bool? muted,
    bool? pinned,
    bool? following,
  }) async {
    final current = _requireSession();
    final updated = await _api.updateServiceAccountSettings(
      session: current,
      device: _device,
      serviceId: serviceId,
      muted: muted,
      pinned: pinned,
      following: following,
    );
    _upsertServiceAccountCache(updated);
    notifyListeners();
    return updated;
  }

  Future<List<Map<String, Object?>>> loadGroups() async {
    final current = _requireSession();
    if (_isCacheFresh(_groupCacheAt)) {
      AppLogger.info(
        'session',
        'load groups memory cache',
        data: {'count': _groupCache.length},
      );
      return _groupCache;
    }
    if (_groupRequest != null) {
      AppLogger.info('session', 'reuse groups request');
      return _groupRequest!;
    }
    AppLogger.info('session', 'load groups start');
    _groupRequest = _api
        .groups(session: current, device: _device)
        .timeout(const Duration(seconds: 15));
    final list = await _groupRequest!.whenComplete(() => _groupRequest = null);
    _groupCache = list;
    _groupCacheAt = DateTime.now();
    _writeGroupCache(list);
    notifyListeners();
    AppLogger.info(
      'session',
      'load groups success',
      data: {'count': list.length},
    );
    return list;
  }

  List<Map<String, Object?>> cachedMomentsFeed() {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    return _copyList(_momentsCache.readFeed(uid));
  }

  void writeMomentsFeed(List<Map<String, Object?>> posts) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    _momentsCache.writeFeed(uid: uid, posts: _copyList(posts));
  }

  String readMomentsDraft() {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return '';
    }
    return _momentsCache.readDraft(uid);
  }

  void writeMomentsDraft(String text) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    _momentsCache.writeDraft(uid: uid, text: text);
  }

  void clearMomentsDraft() {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    _momentsCache.clearDraft(uid);
  }

  Future<Map<String, Object?>> loadMomentsFeed({
    int page = 1,
    int limit = 20,
  }) async {
    final current = _requireSession();
    AppLogger.info(
      'moments',
      'load feed start',
      data: {'page': page, 'limit': limit},
    );
    final data = await _api.momentsFeed(
      session: current,
      device: _device,
      page: page,
      limit: limit,
    );
    final list = _mapListFromPayload(data);
    if (page <= 1) {
      _momentsCache.writeFeed(uid: _chatUid(), posts: list);
    }
    AppLogger.info(
      'moments',
      'load feed success',
      data: {'page': page, 'count': list.length},
    );
    return data;
  }

  Future<Map<String, Object?>> loadUserMoments({
    required int userId,
    int page = 1,
    int limit = 4,
  }) {
    final current = _requireSession();
    return _api.momentsUser(
      session: current,
      device: _device,
      userId: userId,
      page: page,
      limit: limit,
    );
  }

  Future<Map<String, Object?>> publishMoment({
    required String content,
    required String mediaJson,
    int visibility = 0,
    List<int> visibleUserIds = const [],
    List<int> remindUserIds = const [],
    String location = '',
  }) async {
    final current = _requireSession();
    final data = await _api.momentsPublish(
      session: current,
      device: _device,
      content: content,
      mediaJson: mediaJson,
      visibility: visibility,
      visibleUserIds: visibleUserIds,
      remindUserIds: remindUserIds,
      location: location,
    );
    final post = data['post'];
    if (post is Map) {
      final uid = _chatUid();
      final cached = _momentsCache.readFeed(uid);
      _momentsCache.writeFeed(
        uid: uid,
        posts: [
          post.cast<String, Object?>(),
          ...cached.where(
            (item) =>
                item['post_id']?.toString() != post['post_id']?.toString(),
          ),
        ],
      );
      notifyListeners();
    }
    clearMomentsDraft();
    return data;
  }

  Future<Map<String, Object?>> uploadMomentMedia({
    required String filePath,
    required String mediaType,
    String name = '',
    String mime = '',
    int size = 0,
    int width = 0,
    int height = 0,
    int duration = 0,
    void Function(double progress)? onUploadProgress,
  }) {
    final current = _requireSession();
    return _api.momentsMediaUpload(
      session: current,
      device: _device,
      filePath: filePath,
      mediaType: mediaType,
      name: name,
      mime: mime,
      size: size,
      width: width,
      height: height,
      duration: duration,
      onUploadProgress: onUploadProgress,
    );
  }

  Future<Map<String, Object?>> uploadProfileBackground({
    required String filePath,
    void Function(double progress)? onUploadProgress,
  }) async {
    final current = _requireSession();
    final data = await _api.uploadProfileBackground(
      session: current,
      device: _device,
      filePath: filePath,
      onUploadProgress: onUploadProgress,
    );
    final url = _stringValue(data, const [
      'url',
      'userbg',
      'profile_background',
      'profile_background_url',
      'moments_background',
      'moments_cover',
      'cover_url',
      'background_url',
    ]);
    if (url.isNotEmpty) {
      final updated = current.copyWith(profileBackground: url);
      _session = updated;
      _store.writeSession(updated);
      notifyListeners();
    }
    return data;
  }

  Future<Map<String, Object?>> likeMoment(int postId, {required bool liked}) {
    final current = _requireSession();
    return liked
        ? _api.momentsUnlike(session: current, device: _device, postId: postId)
        : _api.momentsLike(session: current, device: _device, postId: postId);
  }

  Future<Map<String, Object?>> commentMoment({
    required int postId,
    required String content,
    int replyCommentId = 0,
    int replyUserId = 0,
  }) {
    final current = _requireSession();
    return _api.momentsCommentAdd(
      session: current,
      device: _device,
      postId: postId,
      content: content,
      replyCommentId: replyCommentId,
      replyUserId: replyUserId,
    );
  }

  Future<Map<String, Object?>> deleteMoment(int postId) {
    final current = _requireSession();
    return _api.momentsDelete(
      session: current,
      device: _device,
      postId: postId,
    );
  }

  Future<Map<String, Object?>> deleteMomentComment(int commentId) {
    final current = _requireSession();
    return _api.momentsCommentDelete(
      session: current,
      device: _device,
      commentId: commentId,
    );
  }

  Future<List<Map<String, Object?>>> loadLocalMessages({
    required String channelId,
    required int channelType,
    String groupId = '',
  }) {
    return _im.localMessages(
      channelID: channelId,
      channelType: channelType,
      groupId: groupId,
    );
  }

  List<Map<String, Object?>> cachedLocalMessages({
    required String channelId,
    required int channelType,
  }) {
    return _im.cachedLocalMessages(
      channelID: channelId,
      channelType: channelType,
    );
  }

  bool isChannelInvalid({required String channelId, required int channelType}) {
    return _im.isInvalidChannel(channelID: channelId, channelType: channelType);
  }

  Future<void> openConversation({
    required String channelId,
    required int channelType,
  }) {
    return _im.openConversation(channelID: channelId, channelType: channelType);
  }

  Future<void> markConversationRead({
    required String channelId,
    required int channelType,
  }) {
    return _im.markConversationRead(
      channelID: channelId,
      channelType: channelType,
    );
  }

  Future<void> markConversationVisibleRead({
    required String channelId,
    required int channelType,
  }) {
    return _im.markConversationVisibleRead(
      channelID: channelId,
      channelType: channelType,
    );
  }

  void closeConversation({
    required String channelId,
    required int channelType,
  }) {
    _im.closeConversation(channelID: channelId, channelType: channelType);
  }

  Future<Map<String, Object?>?> localMessageByClientMsgNo(String clientMsgNo) {
    return _im.localMessageByClientMsgNo(clientMsgNo);
  }

  Future<void> refreshLocalConversations() {
    return _im.refreshLocalConversations();
  }

  Future<void> sendTextMessage({
    required String channelId,
    required int channelType,
    required String text,
    String groupId = '',
    List<String> mentionUserIds = const [],
    bool mentionAll = false,
    String replyClientMsgNo = '',
    Map<String, Object?> quote = const {},
    bool burnAfterRead = false,
    int burnAfterReadSeconds = 0,
  }) async {
    _requireSession();
    final content = text.trim();
    if (content.isEmpty) {
      throw ApiException('消息内容不能为空');
    }
    AppLogger.info(
      'session',
      'send text start',
      data: {
        'channel_id': channelId,
        'channel_type': channelType,
        'group_id': groupId,
        'content_length': content.length,
      },
    );
    await _im.sendTextMessage(
      channelID: channelId,
      channelType: channelType,
      content: content,
      groupId: groupId,
      mentionUserIds: mentionUserIds,
      mentionAll: mentionAll,
      replyClientMsgNo: replyClientMsgNo,
      quote: quote,
      burnAfterRead: burnAfterRead,
      burnAfterReadSeconds: burnAfterReadSeconds,
    );
    _chat.clearDraft(channelId: channelId, channelType: channelType);
  }

  String readDraft({required String channelId, required int channelType}) {
    return _chat.readDraft(channelId: channelId, channelType: channelType);
  }

  void writeDraft({
    required String channelId,
    required int channelType,
    required String text,
  }) {
    _chat.writeDraft(
      channelId: channelId,
      channelType: channelType,
      text: text,
    );
  }

  Future<Map<String, Object?>> sendImAction(
    String action, {
    Map<String, Object?> params = const {},
  }) {
    final current = _requireSession();
    return _chat.action(
      action: action,
      session: current,
      device: _device,
      params: params,
    );
  }

  Future<LiveKitCallInfo> createLiveKitCall({
    required String callType,
    required String mediaType,
    String receiverId = '',
    String groupId = '',
    String title = '',
    List<String> inviteUserIds = const [],
  }) async {
    final current = _requireSession();
    final result = await _api.liveKitCallCreate(
      session: current,
      device: _device,
      callType: callType,
      mediaType: mediaType,
      receiverId: receiverId,
      groupId: groupId,
      title: title,
      inviteUserIds: inviteUserIds,
    );
    return LiveKitCallInfo.fromJson(result);
  }

  Future<LiveKitCallInfo> acceptLiveKitCall(int callId) async {
    final current = _requireSession();
    final result = await _api.liveKitCallAccept(
      session: current,
      device: _device,
      callId: callId,
    );
    return LiveKitCallInfo.fromJson(result);
  }

  Future<LiveKitCallInfo> rejectLiveKitCall(int callId) async {
    final current = _requireSession();
    final result = await _api.liveKitCallReject(
      session: current,
      device: _device,
      callId: callId,
    );
    return LiveKitCallInfo.fromJson(result);
  }

  Future<LiveKitCallInfo> cancelLiveKitCall(int callId) async {
    final current = _requireSession();
    final result = await _api.liveKitCallCancel(
      session: current,
      device: _device,
      callId: callId,
    );
    return LiveKitCallInfo.fromJson(result);
  }

  Future<LiveKitCallInfo> hangupLiveKitCall(
    int callId, {
    bool endCall = false,
  }) async {
    final current = _requireSession();
    final result = await _api.liveKitCallHangup(
      session: current,
      device: _device,
      callId: callId,
      endCall: endCall,
    );
    return LiveKitCallInfo.fromJson(result);
  }

  Future<LiveKitCallInfo> liveKitCallToken(int callId) async {
    final current = _requireSession();
    final result = await _api.liveKitCallToken(
      session: current,
      device: _device,
      callId: callId,
    );
    return LiveKitCallInfo.fromJson(result);
  }

  Future<Map<String, Object?>> recallMessage({
    required String targetClientMsgNo,
  }) {
    return sendImAction(
      'im_message_recall',
      params: {
        'target_client_msg_no': targetClientMsgNo,
        'client_msg_no': _im.newClientMsgNo(),
      },
    );
  }

  Future<Map<String, Object?>> deleteMessageForSelf({
    required String targetClientMsgNo,
    required String channelId,
    required int channelType,
  }) async {
    final current = _requireSession();
    final result = await _chat.deleteMessageForSelf(
      session: current,
      device: _device,
      targetClientMsgNo: targetClientMsgNo,
    );
    await _im.deleteLocalMessage(
      channelID: channelId,
      channelType: channelType,
      clientMsgNo: targetClientMsgNo,
    );
    notifyListeners();
    return result;
  }

  Future<void> deleteLocalMessageOnly({
    required String targetClientMsgNo,
    required String channelId,
    required int channelType,
  }) async {
    await _im.deleteLocalMessage(
      channelID: channelId,
      channelType: channelType,
      clientMsgNo: targetClientMsgNo,
    );
    notifyListeners();
  }

  Future<Map<String, Object?>> readReceipt({
    required String targetClientMsgNo,
    required String channelId,
    required int channelType,
    int messageSeq = 0,
  }) {
    return sendImAction(
      'im_message_read_receipts',
      params: {
        'client_msg_no': _im.newClientMsgNo(),
        'channel_id': channelId,
        'channel_type': channelType.toString(),
        'receipts': jsonEncode([
          {
            'target_client_msg_no': targetClientMsgNo,
            if (messageSeq > 0) 'message_seq': messageSeq,
          },
        ]),
      },
    );
  }

  Future<Map<String, Object?>> receiptStatus({
    required String targetClientMsgNo,
    required String channelId,
    required int channelType,
  }) {
    return sendImAction(
      'im_message_receipt_status',
      params: {
        'target_client_msg_no': targetClientMsgNo,
        'channel_id': channelId,
        'channel_type': channelType.toString(),
      },
    );
  }

  Future<Map<String, Object?>> burnAfterRead({
    required String targetClientMsgNo,
    required String channelId,
    required int channelType,
  }) {
    return sendImAction(
      'im_burn_after_read',
      params: {
        'target_client_msg_no': targetClientMsgNo,
        'client_msg_no': _im.newClientMsgNo(),
        'channel_id': channelId,
        'channel_type': channelType.toString(),
      },
    );
  }

  Future<Map<String, Object?>> receiveRedPacket({
    required String redPacketId,
    bool group = false,
  }) {
    return sendImAction(
      group ? 'im_group_red_packet_receive' : 'im_person_red_packet_receive',
      params: {
        'red_packet_id': redPacketId,
        'client_msg_no': _im.newClientMsgNo(),
      },
    );
  }

  Future<Map<String, Object?>> redPacketDetail(String redPacketId) {
    return sendImAction(
      'im_red_packet_detail',
      params: {'red_packet_id': redPacketId},
    );
  }

  Future<void> markRedPacketReceivedLocal({
    required String channelId,
    required int channelType,
    required String clientMsgNo,
    required String redPacketId,
    Map<String, Object?> result = const {},
  }) {
    return _im.markRedPacketReceivedLocal(
      channelID: channelId,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
      redPacketId: redPacketId,
      result: result,
    );
  }

  Future<Map<String, Object?>> receiveTransfer(String transferId) {
    return sendImAction(
      'im_person_transfer_receive',
      params: {
        'transfer_id': transferId,
        'client_msg_no': _im.newClientMsgNo(),
      },
    );
  }

  Future<Map<String, Object?>> transferDetail(String transferId) {
    return sendImAction(
      'im_transfer_detail',
      params: {'transfer_id': transferId},
    );
  }

  Future<void> markTransferReceivedLocal({
    required String channelId,
    required int channelType,
    required String clientMsgNo,
    required String transferId,
    Map<String, Object?> result = const {},
  }) {
    return _im.markTransferReceivedLocal(
      channelID: channelId,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
      transferId: transferId,
      result: result,
    );
  }

  Future<Map<String, Object?>> sendPrivateMedia({
    required String receiverId,
    required String contentType,
    String url = '',
    String filePath = '',
    Map<String, Object?> params = const {},
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: _uidFromUserId(receiverId),
      channelType: 1,
      contentType: contentType,
      filePath: filePath,
      payload: {...params, if (url.isNotEmpty) 'url': url},
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendGroupMedia({
    required String groupId,
    required String contentType,
    String channelId = '',
    String url = '',
    String filePath = '',
    Map<String, Object?> params = const {},
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: channelId.isEmpty ? groupId : channelId,
      channelType: 2,
      contentType: contentType,
      groupId: groupId,
      filePath: filePath,
      payload: {...params, 'group_id': groupId, if (url.isNotEmpty) 'url': url},
    );
    return const {'msg': '已发送'};
  }

  List<Map<String, Object?>> cachedStickerPacks() {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    return _copyList(_cache.readStickerPacks(uid));
  }

  Set<String> cachedOwnedStickerPackIds() {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const {};
    }
    return _cache.readOwnedStickerPackIds(uid);
  }

  Future<List<Map<String, Object?>>> loadStickerPacks({
    bool refresh = true,
  }) async {
    final current = _requireSession();
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    final cached = _cache.readStickerPacks(uid);
    if (!refresh && cached.isNotEmpty) {
      return _copyList(cached);
    }
    final result = await _api.stickerPacks(
      session: current,
      device: _device,
      limit: 100,
    );
    final packs = _mapListFromPayload(result);
    _cache.writeStickerPacks(uid: uid, packs: packs);
    AppLogger.info(
      'session',
      'sticker packs loaded',
      data: {'count': packs.length},
    );
    notifyListeners();
    return _copyList(packs);
  }

  Future<Set<String>> loadOwnedStickerPackIds({bool refresh = true}) async {
    final current = _requireSession();
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const {};
    }
    final cached = _cache.readOwnedStickerPackIds(uid);
    if (!refresh && cached.isNotEmpty) {
      return cached;
    }
    final result = await _api.stickerMine(session: current, device: _device);
    final packs = _mapListFromPayload(result);
    final ids = <String>{
      ...packs.map(_stickerPackId).where((item) => item.isNotEmpty),
      ..._stringListFromPayload(result, const [
        'pack_ids',
        'ids',
        'owned_pack_ids',
      ]),
    };
    _cache.writeOwnedStickerPackIds(uid: uid, packIds: ids);
    AppLogger.info(
      'session',
      'owned sticker packs loaded',
      data: {'count': ids.length},
    );
    notifyListeners();
    return ids;
  }

  Future<void> buyStickerPack(String packId) async {
    final current = _requireSession();
    final uid = _chatUid();
    final normalized = packId.trim();
    if (uid.isEmpty || normalized.isEmpty) {
      throw ApiException('表情包无效');
    }
    await _api.stickerPackBuy(
      session: current,
      device: _device,
      packId: normalized,
    );
    _cache.addOwnedStickerPackId(uid: uid, packId: normalized);
    AppLogger.info(
      'session',
      'sticker pack bought',
      data: {'pack_id': normalized},
    );
    notifyListeners();
  }

  Future<void> sendBurnAfterReadState({
    required String channelId,
    required int channelType,
    String groupId = '',
    required bool enabled,
    required int seconds,
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: channelId,
      channelType: channelType,
      contentType: 'cmd',
      groupId: groupId,
      payload: {
        'cmd': 'burn_after_read_state',
        'channel_id': channelId,
        'channel_type': channelType.toString(),
        'enabled': enabled ? '1' : '0',
        'seconds': seconds > 0 ? seconds.toString() : '0',
        if (groupId.isNotEmpty) 'group_id': groupId,
      },
    );
  }

  Future<Map<String, Object?>> sendPrivateContactCard({
    required String receiverId,
    required String cardUserId,
    Map<String, Object?> params = const {},
  }) async {
    _requireSession();
    _ensureContactCardIsFriend(cardUserId);
    await _sendBusinessMessage(
      channelId: _uidFromUserId(receiverId),
      channelType: 1,
      contentType: ChatContentTypes.contactCard,
      payload: {...params, 'card_user_id': cardUserId},
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendGroupContactCard({
    required String groupId,
    required String cardUserId,
    String channelId = '',
    Map<String, Object?> params = const {},
  }) async {
    _requireSession();
    _ensureContactCardIsFriend(cardUserId);
    await _sendBusinessMessage(
      channelId: channelId.isEmpty ? groupId : channelId,
      channelType: 2,
      contentType: ChatContentTypes.contactCard,
      groupId: groupId,
      payload: {...params, 'group_id': groupId, 'card_user_id': cardUserId},
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendPrivateTransfer({
    required String receiverId,
    required String money,
    required String assetType,
    required String payPassword,
    String remark = '',
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: _uidFromUserId(receiverId),
      channelType: 1,
      contentType: ChatContentTypes.transfer,
      payload: {
        'receiver_id': receiverId,
        'money': money,
        'asset_type': assetType,
        'pay_password': payPassword,
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendGroupTransfer({
    required String groupId,
    required String receiverId,
    required String money,
    required String assetType,
    required String payPassword,
    String remark = '',
    String channelId = '',
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: channelId.isEmpty ? groupId : channelId,
      channelType: 2,
      contentType: ChatContentTypes.transfer,
      groupId: groupId,
      payload: {
        'group_id': groupId,
        'receiver_id': receiverId,
        'money': money,
        'asset_type': assetType,
        'pay_password': payPassword,
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendPrivateRedPacket({
    required String receiverId,
    required String money,
    required String assetType,
    required String payPassword,
    String remark = '',
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: _uidFromUserId(receiverId),
      channelType: 1,
      contentType: ChatContentTypes.redPacket,
      payload: {
        'receiver_id': receiverId,
        'money': money,
        'asset_type': assetType,
        'pay_password': payPassword,
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendGroupRedPacket({
    required String groupId,
    required String money,
    required String assetType,
    required String payPassword,
    required String packetType,
    int quantity = 1,
    String receiverId = '',
    String remark = '',
    String channelId = '',
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: channelId.isEmpty ? groupId : channelId,
      channelType: 2,
      contentType: ChatContentTypes.redPacket,
      groupId: groupId,
      payload: {
        'group_id': groupId,
        'money': money,
        'asset_type': assetType,
        'pay_password': payPassword,
        'packet_type': packetType,
        'quantity': quantity.toString(),
        if (receiverId.isNotEmpty) 'receiver_id': receiverId,
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> applyFriend({
    required String friendId,
    String remark = '',
  }) {
    final current = _requireSession();
    return _chat.friendApply(
      session: current,
      device: _device,
      friendId: friendId,
      remark: remark,
    );
  }

  Future<Map<String, Object?>> handleFriendApply({
    required String applyId,
    required bool accept,
    String handleMsg = '',
  }) async {
    final current = _requireSession();
    final result = await _chat.friendHandle(
      session: current,
      device: _device,
      applyId: applyId,
      accept: accept,
      handleMsg: handleMsg,
    );
    _upsertFriendApplyCache(
      _friendApplyFromResult(result),
      type: 'in',
      statusOverride: accept ? 1 : 2,
    );
    if (accept) {
      await loadFriends(forceRefresh: true);
    }
    _clearFriendApplyUnread();
    notifyListeners();
    return result;
  }

  Future<Map<String, Object?>> friendApplyList({
    String type = 'in',
    String status = '',
    int page = 1,
    int limit = 20,
  }) async {
    final current = _requireSession();
    final normalized = _friendApplyType(type);
    final result = await _chat.friendApplyList(
      session: current,
      device: _device,
      type: normalized,
      status: status,
      page: page,
      limit: limit,
    );
    final items = _mapListFromPayload(result);
    if (status.isEmpty && page == 1) {
      _writeFriendApplyCache(normalized, items);
      if (normalized == 'in') {
        _syncFriendApplyUnreadWithPending(items);
      }
      notifyListeners();
    }
    return result;
  }

  Future<Map<String, Object?>> addGroupMembers({
    required String groupId,
    required List<String> memberIds,
  }) {
    final current = _requireSession();
    return _chat.groupMembersAdd(
      session: current,
      device: _device,
      groupId: groupId,
      memberIds: memberIds,
    );
  }

  Future<Map<String, Object?>> groupMembers(String groupId) {
    final current = _requireSession();
    return _chat.groupMembers(
      session: current,
      device: _device,
      groupId: groupId,
    );
  }

  Future<Map<String, Object?>> removeGroupMembers({
    required String groupId,
    required List<String> memberIds,
  }) {
    final current = _requireSession();
    return _chat.groupMembersRemove(
      session: current,
      device: _device,
      groupId: groupId,
      memberIds: memberIds,
    );
  }

  Future<Map<String, Object?>> muteGroupMember({
    required String groupId,
    required String memberId,
    int expireSeconds = 0,
    String reason = '',
  }) {
    final current = _requireSession();
    return _chat.groupMemberMute(
      session: current,
      device: _device,
      groupId: groupId,
      memberId: memberId,
      expireSeconds: expireSeconds,
      reason: reason,
    );
  }

  Future<Map<String, Object?>> unmuteGroupMember({
    required String groupId,
    required String memberId,
  }) {
    final current = _requireSession();
    return _chat.groupMemberUnmute(
      session: current,
      device: _device,
      groupId: groupId,
      memberId: memberId,
    );
  }

  Future<Map<String, Object?>> loadGroupMuteStatus({
    required String groupId,
    required String channelId,
  }) async {
    final current = _requireSession();
    final result = await _chat.groupMuteStatus(
      session: current,
      device: _device,
      groupId: groupId,
    );
    _im.applyGroupMuteState(
      channelID: channelId,
      groupId: groupId,
      state: result,
      source: 'server_status',
    );
    return result;
  }

  Future<Map<String, Object?>> createGroup({
    required String name,
    List<String> memberIds = const [],
    String avatar = '',
    String notice = '',
  }) {
    final current = _requireSession();
    return _chat.groupCreate(
      session: current,
      device: _device,
      name: name,
      memberIds: memberIds,
      avatar: avatar,
      notice: notice,
    );
  }

  Future<Map<String, Object?>> updateGroup({
    required String groupId,
    String name = '',
    String avatar = '',
    String notice = '',
  }) {
    final current = _requireSession();
    return _chat.groupUpdate(
      session: current,
      device: _device,
      groupId: groupId,
      name: name,
      avatar: avatar,
      notice: notice,
    );
  }

  Future<Map<String, Object?>> deleteGroup(String groupId) {
    final current = _requireSession();
    return _chat.groupDelete(
      session: current,
      device: _device,
      groupId: groupId,
    );
  }

  Future<Map<String, Object?>> leaveGroup(String groupId) {
    final current = _requireSession();
    return _chat.groupLeave(
      session: current,
      device: _device,
      groupId: groupId,
    );
  }

  Future<Map<String, Object?>> setGroupAdmin({
    required String groupId,
    required String memberId,
    required bool isAdmin,
  }) {
    final current = _requireSession();
    return _chat.groupAdminSet(
      session: current,
      device: _device,
      groupId: groupId,
      memberId: memberId,
      isAdmin: isAdmin,
    );
  }

  Future<Map<String, Object?>> transferGroupOwner({
    required String groupId,
    required String newOwnerId,
  }) {
    final current = _requireSession();
    return _chat.groupOwnerTransfer(
      session: current,
      device: _device,
      groupId: groupId,
      newOwnerId: newOwnerId,
    );
  }

  Future<Map<String, Object?>> friendStatus(String friendId) {
    final current = _requireSession();
    final normalizedFriendId = friendId.trim();
    final cached = _friendStatusCache[normalizedFriendId];
    final cachedAt = _friendStatusCacheAt[normalizedFriendId];
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 8)) {
      AppLogger.info(
        'session',
        'friend status memory cache',
        data: {'friend_id': normalizedFriendId},
      );
      return Future.value(Map<String, Object?>.from(cached));
    }
    final running = _friendStatusRequests[normalizedFriendId];
    if (running != null) {
      AppLogger.info(
        'session',
        'reuse friend status request',
        data: {'friend_id': normalizedFriendId},
      );
      return running;
    }
    final request = _chat
        .friendStatus(
          session: current,
          device: _device,
          friendId: normalizedFriendId,
        )
        .then((result) {
          final stored = Map<String, Object?>.from(result);
          _friendStatusCache[normalizedFriendId] = stored;
          _friendStatusCacheAt[normalizedFriendId] = DateTime.now();
          return Map<String, Object?>.from(stored);
        })
        .whenComplete(() {
          _friendStatusRequests.remove(normalizedFriendId);
        });
    _friendStatusRequests[normalizedFriendId] = request;
    return request;
  }

  Future<Map<String, Object?>> searchFriends({
    String keyword = '',
    int limit = 20,
  }) {
    final current = _requireSession();
    return _chat.friendSearch(
      session: current,
      device: _device,
      keyword: keyword,
      limit: limit,
    );
  }

  Future<Map<String, Object?>> deleteFriend(String friendId) async {
    final current = _requireSession();
    final result = await _chat.friendDelete(
      session: current,
      device: _device,
      friendId: friendId,
    );
    final uid = _chatUid();
    if (uid.isNotEmpty) {
      _cache.removeFriend(uid: uid, friendId: friendId);
      _friendCache = _hydrateFriendList(_cache.readFriendList(uid), uid: uid);
      _friendCacheAt = DateTime.now();
    }
    await _im.removePrivateConversationAfterFriendDelete(
      friendId: friendId,
      channelID: 'app${AppConfig.appId}user$friendId',
    );
    notifyListeners();
    return result;
  }

  Future<Map<String, Object?>> retryMessages({int limit = 20}) {
    final current = _requireSession();
    return _chat.retryMessages(session: current, device: _device, limit: limit);
  }

  Future<void> retryFailedMessage(Map<String, Object?> message) async {
    _requireSession();
    await _im.retryBusinessMessage(message);
  }

  Future<Map<String, Object?>> onlineUsers({int page = 1, int limit = 20}) {
    final current = _requireSession();
    return _chat.onlineUsers(
      session: current,
      device: _device,
      page: page,
      limit: limit,
    );
  }

  Future<Map<String, Object?>> deletePrivateConversation({
    required String receiverId,
    required String channelId,
  }) async {
    final current = _requireSession();
    final result = await _chat.privateConversationDelete(
      session: current,
      device: _device,
      receiverId: receiverId,
    );
    final chat = current.chat;
    await _im.clearChannelChatRecords(
      channelID: channelId,
      channelType: chat?.channelTypePerson ?? 1,
    );
    notifyListeners();
    return result;
  }

  Future<Map<String, Object?>> deleteGroupConversation({
    required String groupId,
    required String channelId,
  }) async {
    final current = _requireSession();
    final result = await _chat.groupConversationDelete(
      session: current,
      device: _device,
      groupId: groupId,
    );
    final chat = current.chat;
    await _im.clearChannelChatRecords(
      channelID: channelId,
      channelType: chat?.channelTypeGroup ?? 2,
    );
    notifyListeners();
    return result;
  }

  Future<void> setConversationPinned({
    required String channelId,
    required int channelType,
    required bool pinned,
  }) async {
    _requireSession();
    await _im.setConversationPinned(
      channelID: channelId,
      channelType: channelType,
      pinned: pinned,
    );
    notifyListeners();
  }

  Future<Map<String, Object?>> deleteConversation({
    required Map<String, Object?> conversation,
  }) async {
    final current = _requireSession();
    final chat = current.chat;
    final channelType = _conversationChannelType(conversation, chat);
    var channelId = _conversationStringValue(conversation, [
      'channel_id',
      'uid',
    ]);
    if (channelType == (chat?.channelTypeGroup ?? 2)) {
      final groupId = _conversationStringValue(conversation, [
        'group_id',
        'id',
      ], fallback: channelId);
      channelId = channelId.isNotEmpty ? channelId : groupId;
      return deleteGroupConversation(groupId: groupId, channelId: channelId);
    }
    final receiverId = _conversationStringValue(conversation, [
      'receiver_id',
      'peer_id',
      'friend_id',
      'user_id',
      'userid',
    ], fallback: _userIdFromUid(channelId));
    channelId = channelId.isNotEmpty ? channelId : _uidFromUserId(receiverId);
    return deletePrivateConversation(
      receiverId: receiverId,
      channelId: channelId,
    );
  }

  Future<Map<String, Object?>> clearAllChatRecords() async {
    final current = _requireSession();
    final result = await _chat.clearAllChatRecords(
      session: current,
      device: _device,
    );
    await _im.clearAllChatRecords();
    notifyListeners();
    return result;
  }

  Future<void> setBackgroundReceiveProtectionEnabled(bool enabled) async {
    _backgroundReceiveProtectionEnabled = enabled;
    _store.writeBackgroundReceiveProtectionEnabled(enabled);
    _im.setBackgroundKeepAliveEnabled(_effectiveBackgroundKeepAliveEnabled);
    notifyListeners();
    await _applyBackgroundReceiveProtection(source: 'user_setting');
    await refreshBackgroundReceiveStatus();
    AppLogger.info(
      'session',
      'background receive protection changed',
      data: {'enabled': enabled},
    );
  }

  Future<void> refreshBackgroundReceiveStatus() async {
    _backgroundReceiveStatus = await BackgroundReceiveGuard.status();
    notifyListeners();
    AppLogger.info(
      'session',
      'background receive status refreshed',
      data: {
        'platform': _backgroundReceiveStatus.platform,
        'supported': _backgroundReceiveStatus.supported,
        'service_running': _backgroundReceiveStatus.serviceRunning,
        'notification_permission_granted':
            _backgroundReceiveStatus.notificationPermissionGranted,
        'battery_optimization_ignored':
            _backgroundReceiveStatus.batteryOptimizationIgnored,
      },
    );
  }

  Future<void> openBackgroundNotificationSettings() {
    return BackgroundReceiveGuard.openNotificationSettings();
  }

  Future<void> openBackgroundBatterySettings() {
    return BackgroundReceiveGuard.openBatterySettings();
  }

  Future<void> logout() async {
    AppLogger.info('session', 'logout start');
    final current = _session;
    _store.clearSession();
    _session = null;
    _clearListCaches();
    unawaited(BackgroundReceiveGuard.stop(reason: 'logout'));
    notifyListeners();
    if (current == null) {
      return;
    }
    try {
      await _im.stop(logout: true);
      await _api.logout(session: current, device: _device);
      AppLogger.info('session', 'logout success');
    } catch (_) {
      // 本地退出必须即时生效，服务端设备退出失败由下次登录覆盖 token。
      AppLogger.warn('session', 'logout remote failed');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> _applyBackgroundReceiveProtection({
    required String source,
  }) async {
    final current = _session ?? _store.readSession();
    final chat = current?.chat;
    if (!_backgroundReceiveProtectionEnabled ||
        current == null ||
        chat == null ||
        chat.uid.isEmpty) {
      await BackgroundReceiveGuard.stop(reason: source);
      return;
    }
    await BackgroundReceiveGuard.start(
      enabled: _backgroundReceiveProtectionEnabled,
      statusText: _backgroundReceiveStatusText,
      uid: chat.uid,
    );
    unawaited(refreshBackgroundReceiveStatus());
  }

  String get _backgroundReceiveStatusText {
    final status = _im.statusText;
    if (status == '已连接') {
      return '消息连接正常';
    }
    if (status == '连接中') {
      return '连接中...';
    }
    if (status == '重连中') {
      return '重连中...';
    }
    if (status == '同步中') {
      return '同步中...';
    }
    return status.isEmpty ? '等待连接' : status;
  }

  UserSession _requireSession() {
    var current = _session;
    if (current == null) {
      current = _store.readSession();
      if (current != null) {
        _session = current;
        AppLogger.warn(
          'session',
          'session restored from persistent cache on demand',
          data: {'user_id': current.userId},
        );
      }
    }
    if (current == null) {
      throw ApiException('请先登录', code: 401);
    }
    return current;
  }

  List<Map<String, Object?>> _cachedConversationsForSession(
    UserSession session,
  ) {
    final uid = session.chat?.uid ?? '';
    if (uid.isEmpty) {
      return const [];
    }
    return _copyList(_cache.readConversations(uid));
  }

  Future<void> _refreshLoggedInSession() async {
    final existing = _refreshRequest;
    if (existing != null) {
      AppLogger.info('session', 'reuse refresh logged in session request');
      return existing;
    }
    _refreshRequest = _doRefreshLoggedInSession();
    try {
      await _refreshRequest;
    } finally {
      _refreshRequest = null;
    }
  }

  Future<void> _doRefreshLoggedInSession() async {
    final current = _requireSession();
    AppLogger.info('session', 'refresh logged in session start');
    final chat = await _api.connectIm(session: current, device: _device);
    final withChat = current.copyWith(chat: chat);
    _session = withChat;
    _store.writeSession(withChat);
    final withProfile = await _api.getCurrentUser(withChat, device: _device);
    _session = withProfile;
    _store.writeSession(withProfile);
    _lastSessionVerifiedAt = _store.markSessionVerified();
    await _im.start(
      withProfile,
      device: _device,
      chatIsFresh: true,
      backgroundKeepAliveEnabled: _effectiveBackgroundKeepAliveEnabled,
    );
    unawaited(_applyBackgroundReceiveProtection(source: 'session_refresh'));
    unawaited(_warmBasicData());
    AppLogger.info(
      'session',
      'refresh logged in session success',
      data: {
        'uid': withProfile.chat?.uid ?? '',
        'gateway_stream':
            withProfile.chat?.stream?.httpsStreamAddr.isNotEmpty == true
            ? withProfile.chat?.stream?.httpsStreamAddr
            : withProfile.chat?.route.httpsStreamAddr ?? '',
      },
    );
  }

  Future<void> _warmBasicData() async {
    try {
      await Future.wait([
        loadFriends(),
        loadGroups(),
        loadServiceAccounts(),
        friendApplyList(type: 'in'),
        friendApplyList(type: 'out'),
      ]);
      AppLogger.info('session', 'basic data warmup success');
    } catch (error, stackTrace) {
      AppLogger.warn(
        'session',
        'basic data warmup failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
    }
  }

  Future<void> _sendBusinessMessage({
    required String channelId,
    required int channelType,
    required String contentType,
    String groupId = '',
    String filePath = '',
    Map<String, Object?> payload = const {},
  }) {
    return _im.sendBusinessMessage(
      channelID: channelId,
      channelType: channelType,
      contentType: contentType,
      groupId: groupId,
      payload: payload,
      filePath: filePath,
    );
  }

  bool _isCacheFresh(DateTime? time) {
    if (time == null) {
      return false;
    }
    return DateTime.now().difference(time) < const Duration(seconds: 30);
  }

  String _chatUid() => _session?.chat?.uid ?? '';

  List<Map<String, Object?>> _copyList(List<Map<String, Object?>> list) {
    return list
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  List<Map<String, Object?>> _mapListFromPayload(Map<String, Object?> data) {
    Object? list;
    for (final key in [
      'list',
      'items',
      'rows',
      'records',
      'packs',
      'packages',
    ]) {
      final value = data[key];
      if (value is List) {
        list = value;
        break;
      }
    }
    final nested = data['data'];
    if (list == null && nested is List) {
      list = nested;
    }
    if (list == null && nested is Map) {
      return _mapListFromPayload(nested.cast<String, Object?>());
    }
    if (list is! List) {
      return const [];
    }
    return list
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }

  Map<String, Object?> _friendApplyFromResult(Map<String, Object?> result) {
    final direct = _normalizeMap(result['apply']);
    if (direct.isNotEmpty) {
      return direct;
    }
    final data = _normalizeMap(result['data']);
    final nested = _normalizeMap(data['apply']);
    if (nested.isNotEmpty) {
      return nested;
    }
    return const <String, Object?>{};
  }

  Map<String, Object?> _normalizeMap(Object? value) {
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.from(value);
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const <String, Object?>{};
  }

  String _friendApplyType(String type) {
    return type == 'out' ? 'out' : 'in';
  }

  void _writeFriendApplyCache(
    String type,
    List<Map<String, Object?>> applications,
  ) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    final normalized = _friendApplyType(type);
    final next = _dedupeFriendApplications(applications);
    if (normalized == 'out') {
      _friendApplyOutCache = next;
    } else {
      _friendApplyInCache = next;
    }
    _cache.writeFriendApplyList(uid: uid, type: normalized, applications: next);
  }

  void _upsertFriendApplyCache(
    Map<String, Object?> application, {
    required String type,
    int? statusOverride,
  }) {
    if (application.isEmpty) {
      return;
    }
    final normalized = _friendApplyType(type);
    final nextItem = Map<String, Object?>.from(application);
    if (statusOverride != null) {
      nextItem['status'] = statusOverride;
    }
    final list = normalized == 'out'
        ? List<Map<String, Object?>>.from(_friendApplyOutCache)
        : List<Map<String, Object?>>.from(_friendApplyInCache);
    final id = _friendApplyId(nextItem);
    final index = id.isEmpty
        ? -1
        : list.indexWhere((item) => _friendApplyId(item) == id);
    if (index >= 0) {
      list[index] = {...list[index], ...nextItem};
    } else {
      list.insert(0, nextItem);
    }
    _writeFriendApplyCache(normalized, list);
  }

  List<Map<String, Object?>> _dedupeFriendApplications(
    List<Map<String, Object?>> applications,
  ) {
    final seen = <String>{};
    final next = <Map<String, Object?>>[];
    for (final item in applications) {
      final normalized = Map<String, Object?>.from(item);
      final id = _friendApplyId(normalized);
      final key = id.isNotEmpty
          ? id
          : '${normalized['from_user_id']}:${normalized['to_user_id']}:${normalized['create_time']}';
      if (!seen.add(key)) {
        continue;
      }
      next.add(normalized);
    }
    return next;
  }

  String _friendApplyId(Map<String, Object?> item) {
    for (final key in ['apply_id', 'id']) {
      final value = item[key]?.toString() ?? '';
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  bool _friendApplyPending(Map<String, Object?> item) {
    final status = item['status']?.toString() ?? '';
    return status.isEmpty || status == '0' || status == 'pending';
  }

  void _syncFriendApplyUnreadWithPending(
    List<Map<String, Object?>> applications,
  ) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    final pendingCount = applications.where(_friendApplyPending).length;
    if (_friendApplyUnreadCount > pendingCount) {
      _friendApplyUnreadCount = pendingCount;
      _cache.writeFriendApplyUnread(uid: uid, count: _friendApplyUnreadCount);
    }
  }

  void _clearFriendApplyUnread() {
    final uid = _chatUid();
    if (uid.isEmpty || _friendApplyUnreadCount == 0) {
      return;
    }
    _friendApplyUnreadCount = 0;
    _cache.writeFriendApplyUnread(uid: uid, count: 0);
  }

  void markFriendApplicationsRead() {
    _clearFriendApplyUnread();
    notifyListeners();
  }

  void _onFriendEvent(BusinessImFriendEvent event) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      AppLogger.warn(
        'session',
        'friend event ignored without chat uid',
        data: {'event': event.event, 'payload': event.payload},
      );
      return;
    }
    final detail = _normalizeMap(event.payload['friend']);
    final apply = _friendApplyFromFriendEvent(event, detail);
    final currentUserId = _session?.userId.toString() ?? '';
    AppLogger.info(
      'session',
      'friend event received',
      data: {
        'event': event.event,
        'apply_id': _friendApplyId(apply),
        'friend_id': event.payload['friend_id']?.toString() ?? '',
      },
    );
    if (event.event == 'friend_apply_created') {
      final existed =
          _friendApplyId(apply).isNotEmpty &&
          _friendApplyInCache.any(
            (item) => _friendApplyId(item) == _friendApplyId(apply),
          );
      _upsertFriendApplyCache(apply, type: 'in', statusOverride: 0);
      if (_friendApplyId(apply).isNotEmpty && !existed) {
        _friendApplyUnreadCount += 1;
        _cache.writeFriendApplyUnread(uid: uid, count: _friendApplyUnreadCount);
      }
      notifyListeners();
      return;
    }
    if (event.event == 'friend_apply_accepted' ||
        event.event == 'friend_apply_rejected') {
      final accepted = event.event == 'friend_apply_accepted';
      final type = _friendApplyTypeForEventApply(apply, currentUserId);
      _upsertFriendApplyCache(
        apply,
        type: type,
        statusOverride: accepted ? 1 : 2,
      );
      if (accepted) {
        _friendCacheAt = null;
        unawaited(loadFriends(forceRefresh: true));
      }
      notifyListeners();
      return;
    }
    if (event.event == 'friend_deleted') {
      final friendId = event.payload['friend_id']?.toString() ?? '';
      if (friendId.isNotEmpty) {
        _cache.removeFriend(uid: uid, friendId: friendId);
        _friendCache = _hydrateFriendList(_cache.readFriendList(uid), uid: uid);
        _friendCacheAt = DateTime.now();
      }
      notifyListeners();
    }
  }

  Map<String, Object?> _friendApplyFromFriendEvent(
    BusinessImFriendEvent event,
    Map<String, Object?> detail,
  ) {
    final payload = event.payload;
    final currentUserId = _session?.userId.toString() ?? '';
    final senderId = payload['sender_id']?.toString() ?? '';
    final receiverId = payload['receiver_id']?.toString() ?? '';
    final fromUserId =
        detail['from_user_id']?.toString().trim().isNotEmpty == true
        ? detail['from_user_id']?.toString()
        : senderId;
    final toUserId = detail['to_user_id']?.toString().trim().isNotEmpty == true
        ? detail['to_user_id']?.toString()
        : receiverId;
    return <String, Object?>{
      ...detail,
      if ((detail['id']?.toString() ?? '').isEmpty &&
          (detail['apply_id']?.toString() ?? '').isNotEmpty)
        'id': detail['apply_id'],
      if ((detail['apply_id']?.toString() ?? '').isEmpty &&
          (detail['id']?.toString() ?? '').isNotEmpty)
        'apply_id': detail['id'],
      if ((detail['from_user_id']?.toString() ?? '').isEmpty)
        'from_user_id': fromUserId,
      if ((detail['to_user_id']?.toString() ?? '').isEmpty)
        'to_user_id': toUserId,
      if ((detail['friend_id']?.toString() ?? '').isEmpty)
        'friend_id': payload['friend_id']?.toString() ?? senderId,
      if ((detail['status']?.toString() ?? '').isEmpty)
        'status': event.event == 'friend_apply_rejected'
            ? 2
            : event.event == 'friend_apply_accepted'
            ? 1
            : 0,
      if ((detail['from_user']?.toString() ?? '').isEmpty &&
          payload['sender_id']?.toString() == fromUserId)
        'from_user': _friendEventUserFromPayload(payload, prefix: 'sender'),
      if ((detail['to_user']?.toString() ?? '').isEmpty &&
          payload['receiver_id']?.toString() == toUserId)
        'to_user': _friendEventUserFromPayload(payload, prefix: 'receiver'),
      if ((detail['create_time']?.toString() ?? '').isEmpty)
        'create_time': DateTime.now().toIso8601String(),
      if (currentUserId.isNotEmpty) 'current_user_id': currentUserId,
    };
  }

  Map<String, Object?> _friendEventUserFromPayload(
    Map<String, Object?> payload, {
    required String prefix,
  }) {
    final user = <String, Object?>{};
    final id = payload['${prefix}_id']?.toString() ?? '';
    final uid = payload['${prefix}_uid']?.toString() ?? '';
    if (id.isNotEmpty) {
      user['id'] = id;
      user['userid'] = id;
      user['user_id'] = id;
    }
    if (uid.isNotEmpty) {
      user['uid'] = uid;
      user['channel_id'] = uid;
    }
    return user;
  }

  String _friendApplyTypeForEventApply(
    Map<String, Object?> apply,
    String currentUserId,
  ) {
    if (currentUserId.isEmpty) {
      return 'in';
    }
    final from = apply['from_user_id']?.toString() ?? '';
    return from == currentUserId ? 'out' : 'in';
  }

  String _stringValue(Map<String, Object?> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    final nested = source['data'];
    if (nested is Map<String, Object?>) {
      return _stringValue(nested, keys);
    }
    if (nested is Map) {
      return _stringValue(nested.cast<String, Object?>(), keys);
    }
    return '';
  }

  String _stickerPackId(Map<String, Object?> item) {
    final sources = <Map<String, Object?>>[
      item,
      if (item['pack'] is Map)
        (item['pack'] as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        ),
    ];
    for (final source in sources) {
      for (final key in ['pack_id', 'id', 'package_id', 'sticker_pack_id']) {
        final value = source[key]?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return '';
  }

  List<String> _stringListFromPayload(
    Map<String, Object?> data,
    List<String> keys,
  ) {
    Object? value;
    for (final key in keys) {
      final current = data[key];
      if (current is List || current is String) {
        value = current;
        break;
      }
    }
    final nested = data['data'];
    if (value == null && nested is Map) {
      return _stringListFromPayload(nested.cast<String, Object?>(), keys);
    }
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    if (value is String) {
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  void _writeFriendCache(List<Map<String, Object?>> friends) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    final hydrated = _hydrateFriendList(friends, uid: uid);
    for (final item in hydrated) {
      final profile = _profileFromFriendItem(item);
      final userId = _profileUserId(profile, fallback: item);
      if (userId.isNotEmpty) {
        _cache.writeProfile(uid: uid, userId: userId, profile: profile);
      }
    }
    _cache.writeFriendList(uid: uid, friends: hydrated);
  }

  void _writeGroupCache(List<Map<String, Object?>> groups) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    _cache.writeGroupList(uid: uid, groups: groups);
  }

  void _writeServiceAccountCache(List<Map<String, Object?>> accounts) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    _cache.writeServiceAccounts(uid: uid, accounts: accounts);
  }

  void _upsertServiceAccountCache(Map<String, Object?> account) {
    if (account.isEmpty) {
      return;
    }
    final accountKey = _serviceAccountKey(account);
    if (accountKey.isEmpty) {
      return;
    }
    final next = _serviceAccountCache
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    final index = next.indexWhere(
      (item) => _serviceAccountKey(item) == accountKey,
    );
    if (index >= 0) {
      next[index] = {...next[index], ...account};
    } else {
      next.add(Map<String, Object?>.from(account));
    }
    _serviceAccountCache = next;
    _serviceAccountCacheAt = DateTime.now();
    _writeServiceAccountCache(next);
  }

  String _serviceAccountKey(Map<String, Object?> item) {
    for (final key in ['service_id', 'id', 'code', 'channel_id', 'user_id']) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != '0') {
        return '$key:$value';
      }
    }
    return '';
  }

  void _onPresenceEvent(BusinessImPresenceEvent event) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      AppLogger.warn(
        'session',
        'presence event ignored without chat uid',
        data: {
          'event_uid': event.uid,
          'event_user_id': event.userId,
          'online': event.online,
        },
      );
      return;
    }
    AppLogger.info(
      'session',
      'presence event received',
      data: {
        'uid': uid,
        'event_uid': event.uid,
        'event_user_id': event.userId,
        'online': event.online,
        'device_flag': event.deviceFlag,
        'device_online_count': event.deviceOnlineCount,
        'total_online_count': event.totalOnlineCount,
        'event_time': event.eventTime,
        'memory_friend_count': _friendCache.length,
      },
    );
    if (_isSelfPresenceEvent(event, uid)) {
      AppLogger.info(
        'session',
        'self presence event ignored for friend cache',
        data: {
          'uid': uid,
          'event_uid': event.uid,
          'event_user_id': event.userId,
          'online': event.online,
        },
      );
      return;
    }
    _rememberFriendPresenceStatus(event);
    final current = _friendCache.isNotEmpty
        ? _friendCache
        : _hydrateFriendList(_cache.readFriendList(uid), uid: uid);
    if (current.isEmpty) {
      _queuePendingPresenceEvent(event);
      AppLogger.info(
        'session',
        'presence event queued before friend cache',
        data: {
          'uid': uid,
          'event_uid': event.uid,
          'event_user_id': event.userId,
          'online': event.online,
          'pending_count': _pendingPresenceEvents.length,
        },
      );
      return;
    }
    final next = _mergePresenceIntoFriendList(current, event);
    final changed = !identical(current, next);
    if (!changed) {
      AppLogger.info(
        'session',
        'presence event did not match friend cache',
        data: {
          'uid': uid,
          'event_uid': event.uid,
          'event_user_id': event.userId,
          'online': event.online,
          'friend_count': current.length,
        },
      );
      return;
    }
    _friendCache = next;
    _friendCacheAt ??= DateTime.now();
    _writeFriendCache(next);
    AppLogger.info(
      'session',
      'friend presence updated',
      data: {
        'uid': event.uid,
        'user_id': event.userId,
        'online': event.online,
        'friend_count': next.length,
      },
    );
    notifyListeners();
  }

  bool _isSelfPresenceEvent(BusinessImPresenceEvent event, String uid) {
    final currentUserId = _session?.userId.toString() ?? '';
    final eventUserId = event.userId.isNotEmpty
        ? event.userId
        : _userIdFromUid(event.uid);
    return (event.uid.isNotEmpty && event.uid == uid) ||
        (currentUserId.isNotEmpty && eventUserId == currentUserId);
  }

  void _queuePendingPresenceEvent(BusinessImPresenceEvent event) {
    final key = _presenceEventKey(event);
    _pendingPresenceEvents.removeWhere(
      (item) => _presenceEventKey(item) == key,
    );
    _pendingPresenceEvents.add(event);
    if (_pendingPresenceEvents.length > 200) {
      _pendingPresenceEvents.removeRange(
        0,
        _pendingPresenceEvents.length - 200,
      );
    }
  }

  String _presenceEventKey(BusinessImPresenceEvent event) {
    final userId = event.userId.isNotEmpty
        ? event.userId
        : _userIdFromUid(event.uid);
    final userKey = userId.isNotEmpty ? userId : event.uid;
    return '$userKey:${event.deviceFlag}';
  }

  List<Map<String, Object?>> _mergePresenceIntoFriendList(
    List<Map<String, Object?>> current,
    BusinessImPresenceEvent event,
  ) {
    var changed = false;
    final next = current
        .map((item) {
          if (!_friendMatchesPresence(item, event)) {
            return item;
          }
          changed = true;
          return _mergePresenceIntoFriend(item, event);
        })
        .toList(growable: false);
    return changed ? next : current;
  }

  List<Map<String, Object?>> _mergePendingPresenceIntoFriendList(
    List<Map<String, Object?>> friends,
  ) {
    if (_pendingPresenceEvents.isEmpty || friends.isEmpty) {
      return friends;
    }
    var next = friends;
    var applied = 0;
    final stillPending = <BusinessImPresenceEvent>[];
    for (final event in _pendingPresenceEvents) {
      final merged = _mergePresenceIntoFriendList(next, event);
      if (identical(merged, next)) {
        stillPending.add(event);
      } else {
        next = merged;
        applied += 1;
      }
    }
    _pendingPresenceEvents
      ..clear()
      ..addAll(stillPending);
    AppLogger.info(
      'session',
      'pending presence replayed into friends',
      data: {
        'friend_count': friends.length,
        'applied_count': applied,
        'remaining_count': _pendingPresenceEvents.length,
      },
    );
    return next;
  }

  void _rememberFriendPresenceStatus(BusinessImPresenceEvent event) {
    final userId = event.userId.isNotEmpty
        ? event.userId
        : _userIdFromUid(event.uid);
    if (userId.isEmpty) {
      return;
    }
    final status = <String, Object?>{
      'friend_id': userId,
      'userid': userId,
      'user_id': userId,
      'uid': event.uid,
      'online': event.online ? 1 : 0,
      'is_online': event.online ? 1 : 0,
      'online_status': event.online ? 'online' : 'offline',
      'device_flag': event.deviceFlag,
      'device_online_count': event.deviceOnlineCount,
      'total_online_count': event.totalOnlineCount,
      'presence_event_time': event.eventTime,
    };
    _friendStatusCache[userId] = status;
    _friendStatusCacheAt[userId] = DateTime.now();
  }

  void _onImServiceChanged() {
    final status = _im.statusText;
    final revocationMessage = _im.sessionRevocationMessage;
    if (revocationMessage != null && !_handlingImRevocation) {
      _handlingImRevocation = true;
      _store.clearSession();
      _session = null;
      _clearListCaches();
      _error = revocationMessage;
      unawaited(BackgroundReceiveGuard.stop(reason: 'session_revoked'));
      AppLogger.warn(
        'session',
        'session ended by gateway revocation',
        data: {'message': revocationMessage},
      );
    }
    final becameConnected = status == '已连接' && _lastImStatusText != status;
    _lastImStatusText = status;
    final chat = _session?.chat;
    if (_backgroundReceiveProtectionEnabled &&
        chat != null &&
        chat.uid.isNotEmpty) {
      unawaited(
        BackgroundReceiveGuard.update(
          enabled: true,
          statusText: _backgroundReceiveStatusText,
          uid: chat.uid,
        ),
      );
    }
    if (becameConnected) {
      _refreshFriendPresenceAfterConnect();
    }
    notifyListeners();
  }

  void _refreshFriendPresenceAfterConnect() {
    if (_session == null ||
        _device.isEmpty ||
        _presenceRefreshRequest != null) {
      return;
    }
    _presenceRefreshRequest = loadFriends(forceRefresh: true)
        .timeout(const Duration(seconds: 12))
        .then<void>((_) {
          AppLogger.info('session', 'friend presence refreshed after connect');
        })
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.warn(
            'session',
            'friend presence refresh after connect failed',
            data: {'error': error.toString(), 'stack': stackTrace.toString()},
          );
        })
        .whenComplete(() {
          _presenceRefreshRequest = null;
        });
  }

  bool _friendMatchesPresence(
    Map<String, Object?> item,
    BusinessImPresenceEvent event,
  ) {
    final profile = _profileFromFriendItem(item);
    final eventUserId = event.userId.isNotEmpty
        ? event.userId
        : _userIdFromUid(event.uid);
    final eventUid = event.uid.isNotEmpty && event.uid.startsWith('app')
        ? event.uid
        : (eventUserId.isEmpty ? '' : _uidFromUserId(eventUserId));
    final userId = _profileUserId(profile, fallback: item);
    if (eventUserId.isNotEmpty && userId == eventUserId) {
      return true;
    }
    for (final key in [
      'uid',
      'im_uid',
      'wukong_uid',
      'channel_id',
      'user_uid',
    ]) {
      final value = item[key]?.toString() ?? profile[key]?.toString() ?? '';
      if (value.isNotEmpty && (value == event.uid || value == eventUid)) {
        return true;
      }
    }
    return false;
  }

  Map<String, Object?> _mergePresenceIntoFriend(
    Map<String, Object?> item,
    BusinessImPresenceEvent event,
  ) {
    final next = Map<String, Object?>.from(item);
    final fields = <String, Object?>{
      'uid': event.uid,
      'online': event.online ? 1 : 0,
      'is_online': event.online ? 1 : 0,
      'online_status': event.online ? 'online' : 'offline',
      'device_flag': event.deviceFlag,
      'device_online_count': event.deviceOnlineCount,
      'total_online_count': event.totalOnlineCount,
      'presence_event_time': event.eventTime,
    };
    next.addAll(fields);
    for (final nestedKey in ['friend', 'user']) {
      final nested = next[nestedKey];
      if (nested is Map) {
        next[nestedKey] = {
          ...nested.map((key, value) => MapEntry(key.toString(), value)),
          ...fields,
        };
      }
    }
    return next;
  }

  void _clearListCaches() {
    _friendCache = const [];
    _groupCache = const [];
    _serviceAccountCache = const [];
    _friendCacheAt = null;
    _groupCacheAt = null;
    _serviceAccountCacheAt = null;
    _friendRequest = null;
    _groupRequest = null;
    _serviceAccountRequest = null;
    _friendStatusCache.clear();
    _friendStatusCacheAt.clear();
    _friendStatusRequests.clear();
    _pendingPresenceEvents.clear();
    _refreshRequest = null;
    _lastHotRefreshAt = null;
  }

  Map<String, Object?> _profileFromFriendItem(Map<String, Object?> item) {
    final friend = item['friend'];
    if (friend is Map) {
      return friend.map((key, value) => MapEntry(key.toString(), value));
    }
    final user = item['user'];
    if (user is Map) {
      return user.map((key, value) => MapEntry(key.toString(), value));
    }
    return item;
  }

  List<Map<String, Object?>> _hydrateFriendList(
    List<Map<String, Object?>> friends, {
    String uid = '',
  }) {
    final chatUid = uid.isEmpty ? _chatUid() : uid;
    if (chatUid.isEmpty) {
      return _copyList(friends);
    }
    return friends
        .map((item) => _hydrateFriendItem(item, uid: chatUid))
        .toList(growable: false);
  }

  Map<String, Object?> _hydrateFriendItem(
    Map<String, Object?> item, {
    required String uid,
  }) {
    final profile = _profileFromFriendItem(item);
    final userId = _profileUserId(profile, fallback: item);
    if (userId.isEmpty) {
      return Map<String, Object?>.from(item);
    }
    final cached = _cache.readProfile(uid: uid, userId: userId);
    final mergedProfile = _mergeNonEmpty(cached, profile);
    final mergedItem = _mergeNonEmpty(mergedProfile, item);
    final nestedKey = item['friend'] is Map
        ? 'friend'
        : item['user'] is Map
        ? 'user'
        : '';
    if (nestedKey.isNotEmpty) {
      mergedItem[nestedKey] = mergedProfile;
    }
    mergedItem['userid'] = userId;
    mergedItem['user_id'] ??= userId;
    return mergedItem;
  }

  Map<String, Object?> _mergeNonEmpty(
    Map<String, Object?> base,
    Map<String, Object?> overlay,
  ) {
    final merged = Map<String, Object?>.from(base);
    for (final entry in overlay.entries) {
      if (_hasNonEmptyValue(entry.value)) {
        merged[entry.key] = entry.value;
      } else {
        merged.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return merged;
  }

  bool _hasNonEmptyValue(Object? value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is Map || value is Iterable) {
      return true;
    }
    return value.toString().trim().isNotEmpty;
  }

  String _profileUserId(
    Map<String, Object?> profile, {
    Map<String, Object?> fallback = const {},
  }) {
    for (final source in [profile, fallback]) {
      for (final key in ['friend_id', 'userid', 'user_id', 'id']) {
        final value = source[key]?.toString() ?? '';
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    return '';
  }

  void _ensureContactCardIsFriend(String cardUserId) {
    final id = cardUserId.trim();
    if (id.isEmpty) {
      throw ApiException('名片用户不能为空');
    }
    final friends = cachedFriends();
    final matched = friends.any((friend) {
      final profile = _friendProfileFromItem(friend);
      return _profileUserId(profile, fallback: friend) == id;
    });
    if (!matched) {
      AppLogger.warn(
        'session',
        'contact card blocked because user is not friend',
        data: {'card_user_id': id, 'friend_count': friends.length},
      );
      throw ApiException('只能发送自己的好友名片');
    }
  }

  Map<String, Object?> _friendProfileFromItem(Map<String, Object?> item) {
    final friend = item['friend'];
    if (friend is Map) {
      return friend.map((key, value) => MapEntry(key.toString(), value));
    }
    final user = item['user'];
    if (user is Map) {
      return user.map((key, value) => MapEntry(key.toString(), value));
    }
    return item;
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await task();
    } on ApiException catch (error) {
      _error = error.message;
      if (error.code == 0) {
        AppLogger.warn(
          'session',
          'busy task rejected by business rule',
          data: {'code': error.code, 'message': error.message},
        );
      } else {
        AppLogger.error(
          'session',
          'busy task api error',
          error: error,
          data: {'code': error.code},
        );
      }
      rethrow;
    } catch (error) {
      _error = error.toString();
      AppLogger.error('session', 'busy task failed', error: error);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _uidFromUserId(String userId) {
    if (userId.startsWith('app')) {
      return userId;
    }
    return 'app${_api.appId}user$userId';
  }

  int _conversationIntValue(Map<String, Object?> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is int) {
        return value;
      }
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
    return 0;
  }

  int _conversationChannelType(Map<String, Object?> source, ChatSession? chat) {
    final direct = _conversationIntValue(source, ['channel_type']);
    if (direct > 0) {
      return direct;
    }
    return source['conversation_type']?.toString() == 'group'
        ? chat?.channelTypeGroup ?? 2
        : chat?.channelTypePerson ?? 1;
  }

  String _conversationStringValue(
    Map<String, Object?> source,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = source[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  String _userIdFromUid(String uid) {
    final match = RegExp(r'user(\d+)$').firstMatch(uid);
    return match?.group(1) ?? '';
  }

  String _walletRequestId() {
    final random = Random.secure();
    final nonce = List<int>.generate(
      8,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return 'wallet_${DateTime.now().microsecondsSinceEpoch}_$nonce';
  }

  @override
  void dispose() {
    _im.removeListener(_onImServiceChanged);
    unawaited(_presenceSub?.cancel());
    unawaited(_friendSub?.cancel());
    unawaited(_im.stop());
    super.dispose();
  }
}
