import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/models.dart';
import '../core/session_store.dart';
import '../features/moments/moments_cache_store.dart';
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
  String? _error;
  int _lastColdLaunchAt = 0;
  int _lastHotResumeAt = 0;
  int _lastSessionVerifiedAt = 0;
  DateTime? _lastHotRefreshAt;
  String _lastImStatusText = '';
  Future<void>? _presenceRefreshRequest;
  Future<void>? _refreshRequest;
  List<Map<String, Object?>> _friendCache = const [];
  List<Map<String, Object?>> _groupCache = const [];
  DateTime? _friendCacheAt;
  DateTime? _groupCacheAt;
  Future<List<Map<String, Object?>>>? _friendRequest;
  Future<List<Map<String, Object?>>>? _groupRequest;
  final Map<String, Map<String, Object?>> _friendStatusCache =
      <String, Map<String, Object?>>{};
  final Map<String, DateTime> _friendStatusCacheAt = <String, DateTime>{};
  final Map<String, Future<Map<String, Object?>>> _friendStatusRequests =
      <String, Future<Map<String, Object?>>>{};
  final List<BusinessImPresenceEvent> _pendingPresenceEvents =
      <BusinessImPresenceEvent>[];
  StreamSubscription<BusinessImPresenceEvent>? _presenceSub;

  UserSession? get session => _session;
  AppInfo? get appInfo => _appInfo;
  AppAuthConfig get authConfig => _appInfo?.auth ?? AppAuthConfig.defaults;
  String get device => _device;
  bool get booting => _booting;
  bool get busy => _busy;
  String? get error => _error;
  bool get isLoggedIn => _session?.userToken.isNotEmpty == true;
  int get lastColdLaunchAt => _lastColdLaunchAt;
  int get lastHotResumeAt => _lastHotResumeAt;
  int get lastSessionVerifiedAt => _lastSessionVerifiedAt;
  String get imStatusText => _im.statusText;
  String? get imError => _im.lastError;
  int get conversationVersion => _im.conversationVersion;
  bool get initialHistorySyncing => _im.initialHistorySyncing;
  bool get initialHistorySyncBlocked => _im.initialHistorySyncBlocked;
  BusinessImInitialSyncState get initialHistorySyncState =>
      _im.initialHistorySyncState;
  bool get hasLoadedFriends => _friendCacheAt != null;
  Stream<BusinessImMessageEvent> get messageEvents => _im.messageEvents;
  Stream<BusinessImPresenceEvent> get presenceEvents => _im.presenceEvents;

  List<Map<String, Object?>> cachedConversations() => _im.cachedConversations();

  void _hydrateCachedLaunchState() {
    _device = _store.ensureDeviceId();
    _session = _store.readSession();
    _appInfo = _store.readAppInfo() ?? const AppInfo(name: AppConfig.appName);
    _lastSessionVerifiedAt = _store.readSessionVerifiedAt();
    AppLogger.info(
      'session',
      'launch cache hydrated',
      data: {
        'logged_in': _session != null,
        'device': _device,
        'last_session_verified_at': _lastSessionVerifiedAt,
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
    _appInfo = cachedAppInfo ?? const AppInfo(name: AppConfig.appName);
    _refreshAppInfoInBackground(
      source: 'cold_start',
      hasCachedAppInfo: cachedAppInfo != null,
    );

    try {
      if (_session != null) {
        await _refreshLoggedInSession();
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
    _session = _store.readSession();
    notifyListeners();
    if (_session == null) {
      return;
    }
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

  void _refreshAppInfoInBackground({
    required String source,
    required bool hasCachedAppInfo,
  }) {
    AppLogger.info(
      'session',
      'app info refresh scheduled',
      data: {'source': source, 'has_cached_app_info': hasCachedAppInfo},
    );
    unawaited(_refreshAppInfo(source: source));
  }

  Future<void> _refreshAppInfo({required String source}) async {
    try {
      final appInfo = await _api.getAppInfo();
      _appInfo = appInfo;
      _store.writeAppInfo(appInfo);
      AppLogger.info(
        'session',
        'app info refreshed',
        data: {'source': source, 'app_name': appInfo.name},
      );
      notifyListeners();
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
    }
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
    AppLogger.info(
      'session',
      'cached im start scheduled for persistent login',
      data: {'source': source, 'uid': chat.uid},
    );
    unawaited(_startCachedIm(current, source: source));
  }

  Future<void> _startCachedIm(
    UserSession session, {
    required String source,
  }) async {
    try {
      await _im.start(session, device: _device);
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
      final session = await _api.login(
        username: username,
        password: password,
        captcha: captcha,
        device: _device,
      );
      _session = session;
      _store.writeSession(session);
      try {
        await _refreshLoggedInSession();
      } on ApiException catch (error, stackTrace) {
        _handleSessionRefreshApiError(
          error,
          source: 'login_password',
          stackTrace: stackTrace,
        );
        if (_shouldEndCachedLogin(error)) {
          rethrow;
        }
      } catch (error, stackTrace) {
        _handleSessionRefreshUnexpectedError(
          error,
          source: 'login_password',
          stackTrace: stackTrace,
        );
      }
    });
  }

  Future<void> loginWithMobile({
    required String mobile,
    required String code,
    String captcha = '',
  }) async {
    await _runBusy(() async {
      final session = await _api.loginWithMobile(
        mobile: mobile,
        code: code,
        captcha: captcha,
        device: _device,
      );
      _session = session;
      _store.writeSession(session);
      try {
        await _refreshLoggedInSession();
      } on ApiException catch (error, stackTrace) {
        _handleSessionRefreshApiError(
          error,
          source: 'login_mobile',
          stackTrace: stackTrace,
        );
        if (_shouldEndCachedLogin(error)) {
          rethrow;
        }
      } catch (error, stackTrace) {
        _handleSessionRefreshUnexpectedError(
          error,
          source: 'login_mobile',
          stackTrace: stackTrace,
        );
      }
    });
  }

  Future<ImageCaptcha> loadImageCaptcha({required int type}) {
    return _api.getImageCaptcha(type: type);
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

  Future<void> sendEmailCode(String email, {int type = 1}) {
    return _runBusy(
      () => _api.sendEmailCode(email, device: _device, type: type),
    );
  }

  Future<void> sendMobileCode(String mobile, {int type = 2}) {
    return _runBusy(
      () => _api.sendMobileCode(mobile, device: _device, type: type),
    );
  }

  Future<List<Map<String, Object?>>> loadConversations() async {
    _requireSession();
    AppLogger.info('session', 'load conversations start');
    final local = await _im.loadConversations().timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        AppLogger.warn('session', 'local conversations timeout');
        return _im.cachedConversations();
      },
    );
    AppLogger.info(
      'session',
      'load conversations local success',
      data: {'count': local.length},
    );
    return local;
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
    if (_friendRequest != null) {
      AppLogger.info('session', 'reuse friends request');
      return _friendRequest!;
    }
    AppLogger.info('session', 'load friends start');
    _friendRequest = _api
        .friends(session: current, device: _device)
        .timeout(const Duration(seconds: 15));
    final rawList = await _friendRequest!.whenComplete(
      () => _friendRequest = null,
    );
    final list = _mergePendingPresenceIntoFriendList(
      _hydrateFriendList(rawList),
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
    int messageSeq = 0,
  }) {
    return sendImAction(
      'im_message_read_receipts',
      params: {
        'client_msg_no': _im.newClientMsgNo(),
        'receipts': jsonEncode([
          {
            'target_client_msg_no': targetClientMsgNo,
            if (messageSeq > 0) 'message_seq': messageSeq,
          },
        ]),
      },
    );
  }

  Future<Map<String, Object?>> receiptStatus(String targetClientMsgNo) {
    return sendImAction(
      'im_message_receipt_status',
      params: {'target_client_msg_no': targetClientMsgNo},
    );
  }

  Future<Map<String, Object?>> burnAfterRead(String targetClientMsgNo) {
    return sendImAction(
      'im_burn_after_read',
      params: {
        'target_client_msg_no': targetClientMsgNo,
        'client_msg_no': _im.newClientMsgNo(),
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

  Future<Map<String, Object?>> sendPrivateContactCard({
    required String receiverId,
    required String cardUserId,
    Map<String, Object?> params = const {},
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: _uidFromUserId(receiverId),
      channelType: 1,
      contentType: ChatContentTypes.contactCard,
      payload: {'card_user_id': cardUserId, ...params},
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
    await _sendBusinessMessage(
      channelId: channelId.isEmpty ? groupId : channelId,
      channelType: 2,
      contentType: ChatContentTypes.contactCard,
      groupId: groupId,
      payload: {'group_id': groupId, 'card_user_id': cardUserId, ...params},
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendPrivateTransfer({
    required String receiverId,
    required String money,
    required String assetType,
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
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendPrivateRedPacket({
    required String receiverId,
    required String money,
    required String assetType,
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
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendGroupRedPacket({
    required String groupId,
    required String money,
    required String assetType,
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
  }) {
    final current = _requireSession();
    return _chat.friendHandle(
      session: current,
      device: _device,
      applyId: applyId,
      accept: accept,
      handleMsg: handleMsg,
    );
  }

  Future<Map<String, Object?>> friendApplyList({
    String type = 'in',
    String status = '',
    int page = 1,
    int limit = 20,
  }) {
    final current = _requireSession();
    return _chat.friendApplyList(
      session: current,
      device: _device,
      type: type,
      status: status,
      page: page,
      limit: limit,
    );
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

  Future<void> logout() async {
    AppLogger.info('session', 'logout start');
    final current = _session;
    _store.clearSession();
    _session = null;
    _clearListCaches();
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

  UserSession _requireSession() {
    final current = _session;
    if (current == null) {
      throw ApiException('请先登录', code: 401);
    }
    return current;
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
    await _im.start(withProfile, device: _device, chatIsFresh: true);
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
      await Future.wait([loadFriends(), loadGroups()]);
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
    for (final key in ['list', 'items', 'rows', 'records']) {
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
    final becameConnected = status == '已连接' && _lastImStatusText != status;
    _lastImStatusText = status;
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
    _friendCacheAt = null;
    _groupCacheAt = null;
    _friendRequest = null;
    _groupRequest = null;
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

  Future<void> _runBusy(Future<void> Function() task) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await task();
    } on ApiException catch (error) {
      _error = error.message;
      AppLogger.error(
        'session',
        'busy task api error',
        error: error,
        data: {'code': error.code},
      );
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

  String _userIdFromUid(String uid) {
    final match = RegExp(r'user(\d+)$').firstMatch(uid);
    return match?.group(1) ?? '';
  }

  @override
  void dispose() {
    _im.removeListener(_onImServiceChanged);
    unawaited(_presenceSub?.cancel());
    unawaited(_im.stop());
    super.dispose();
  }
}
