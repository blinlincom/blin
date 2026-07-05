import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/app_logger.dart';
import '../core/models.dart';
import '../core/session_store.dart';
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
  }) : _api = api,
       _store = store,
       _im = im,
       _chat = chat,
       _cache = cache {
    _im.addListener(notifyListeners);
  }

  final ApiClient _api;
  final SessionStore _store;
  final BusinessImService _im;
  final ChatFeatureService _chat;
  final ImCacheStore _cache;

  UserSession? _session;
  AppInfo? _appInfo;
  String _device = '';
  bool _booting = true;
  bool _busy = false;
  String? _error;
  int _lastColdLaunchAt = 0;
  int _lastHotResumeAt = 0;
  DateTime? _lastHotRefreshAt;
  Future<void>? _refreshRequest;
  List<Map<String, Object?>> _friendCache = const [];
  List<Map<String, Object?>> _groupCache = const [];
  DateTime? _friendCacheAt;
  DateTime? _groupCacheAt;
  Future<List<Map<String, Object?>>>? _friendRequest;
  Future<List<Map<String, Object?>>>? _groupRequest;

  UserSession? get session => _session;
  AppInfo? get appInfo => _appInfo;
  String get device => _device;
  bool get booting => _booting;
  bool get busy => _busy;
  String? get error => _error;
  bool get isLoggedIn => _session?.userToken.isNotEmpty == true;
  int get lastColdLaunchAt => _lastColdLaunchAt;
  int get lastHotResumeAt => _lastHotResumeAt;
  String get imStatusText => _im.statusText;
  String? get imError => _im.lastError;
  int get conversationVersion => _im.conversationVersion;
  Stream<BusinessImMessageEvent> get messageEvents => _im.messageEvents;

  List<Map<String, Object?>> cachedConversations() => _im.cachedConversations();

  List<Map<String, Object?>> cachedFriends() {
    if (_friendCache.isNotEmpty) {
      return _copyList(_friendCache);
    }
    final uid = _chatUid();
    if (uid.isEmpty) {
      return const [];
    }
    _friendCache = _cache.readFriendList(uid);
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
    _session = _store.readSession();

    try {
      _appInfo = await _api.getAppInfo();
      if (_session != null) {
        await _refreshLoggedInSession();
      }
      AppLogger.info(
        'session',
        'cold start success',
        data: {'logged_in': _session != null, 'device': _device},
      );
    } on ApiException catch (error) {
      if (error.code == 401 || error.code == 403) {
        _store.clearSession();
        _session = null;
      }
      _error = error.message;
      AppLogger.error(
        'session',
        'cold start api error',
        error: error,
        data: {'code': error.code},
      );
    } catch (error) {
      _error = error.toString();
      AppLogger.error('session', 'cold start failed', error: error);
    } finally {
      _booting = false;
      notifyListeners();
    }
  }

  Future<void> hotResume() async {
    AppLogger.info('session', 'hot resume');
    _lastHotResumeAt = _store.markHotResume();
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
    } on ApiException catch (error) {
      if (error.code == 401 || error.code == 403) {
        _store.clearSession();
        _session = null;
      }
      _error = error.message;
      AppLogger.error(
        'session',
        'hot resume api error',
        error: error,
        data: {'code': error.code},
      );
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      AppLogger.error('session', 'hot resume failed', error: error);
      notifyListeners();
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
      await _refreshLoggedInSession();
    });
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

  Future<void> sendEmailCode(String email) {
    return _runBusy(() => _api.sendEmailCode(email, device: _device));
  }

  Future<void> sendMobileCode(String mobile) {
    return _runBusy(() => _api.sendMobileCode(mobile, device: _device));
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

  Future<List<Map<String, Object?>>> loadFriends() async {
    final current = _requireSession();
    if (_isCacheFresh(_friendCacheAt)) {
      AppLogger.info(
        'session',
        'load friends memory cache',
        data: {'count': _friendCache.length},
      );
      return _friendCache;
    }
    if (_friendRequest != null) {
      AppLogger.info('session', 'reuse friends request');
      return _friendRequest!;
    }
    AppLogger.info('session', 'load friends start');
    _friendRequest = _api
        .friends(session: current, device: _device)
        .timeout(const Duration(seconds: 15));
    final list = await _friendRequest!.whenComplete(
      () => _friendRequest = null,
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
    return list;
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
      'im_message_read_receipt',
      params: {
        'target_client_msg_no': targetClientMsgNo,
        'client_msg_no': _im.newClientMsgNo(),
        if (messageSeq > 0) 'message_seq': messageSeq.toString(),
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

  Future<Map<String, Object?>> receiveTransfer(String transferId) {
    return sendImAction(
      'im_person_transfer_receive',
      params: {
        'transfer_id': transferId,
        'client_msg_no': _im.newClientMsgNo(),
      },
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
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: _uidFromUserId(receiverId),
      channelType: 1,
      contentType: ChatContentTypes.contactCard,
      payload: {'card_user_id': cardUserId},
    );
    return const {'msg': '已发送'};
  }

  Future<Map<String, Object?>> sendGroupContactCard({
    required String groupId,
    required String cardUserId,
    String channelId = '',
  }) async {
    _requireSession();
    await _sendBusinessMessage(
      channelId: channelId.isEmpty ? groupId : channelId,
      channelType: 2,
      contentType: ChatContentTypes.contactCard,
      groupId: groupId,
      payload: {'group_id': groupId, 'card_user_id': cardUserId},
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
        'transfer_id': _tradeNo('tr'),
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
        'transfer_id': _tradeNo('gtr'),
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
        'red_packet_id': _tradeNo('rp'),
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
        'red_packet_id': _tradeNo('grp'),
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
    return _chat.friendStatus(
      session: current,
      device: _device,
      friendId: friendId,
    );
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
      _friendCache = _cache.readFriendList(uid);
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
    final withProfile = await _api.getCurrentUser(withChat, device: _device);
    _session = withProfile;
    _store.writeSession(withProfile);
    await _im.start(withProfile, device: _device);
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

  String _tradeNo(String prefix) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final tail = millis.toRadixString(36);
    return '${prefix}_${_session?.userId ?? '0'}_$tail';
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

  void _writeFriendCache(List<Map<String, Object?>> friends) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    _cache.writeFriendList(uid: uid, friends: friends);
    for (final item in friends) {
      final profile = _profileFromFriendItem(item);
      final userId = _profileUserId(profile, fallback: item);
      if (userId.isNotEmpty) {
        _cache.writeProfile(uid: uid, userId: userId, profile: profile);
      }
    }
  }

  void _writeGroupCache(List<Map<String, Object?>> groups) {
    final uid = _chatUid();
    if (uid.isEmpty) {
      return;
    }
    _cache.writeGroupList(uid: uid, groups: groups);
  }

  void _clearListCaches() {
    _friendCache = const [];
    _groupCache = const [];
    _friendCacheAt = null;
    _groupCacheAt = null;
    _friendRequest = null;
    _groupRequest = null;
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

  @override
  void dispose() {
    _im.removeListener(notifyListeners);
    unawaited(_im.stop());
    super.dispose();
  }
}
