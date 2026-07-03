import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/session_store.dart';
import '../im/chat_feature_service.dart';
import '../im/wukong_im_service.dart';

class SessionController extends ChangeNotifier {
  SessionController({
    required ApiClient api,
    required SessionStore store,
    required WukongImService im,
    required ChatFeatureService chat,
  }) : _api = api,
       _store = store,
       _im = im,
       _chat = chat {
    _im.addListener(notifyListeners);
  }

  final ApiClient _api;
  final SessionStore _store;
  final WukongImService _im;
  final ChatFeatureService _chat;

  UserSession? _session;
  AppInfo? _appInfo;
  String _device = '';
  bool _booting = true;
  bool _busy = false;
  String? _error;
  int _lastColdLaunchAt = 0;
  int _lastHotResumeAt = 0;

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

  Future<void> coldStart() async {
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
    } on ApiException catch (error) {
      if (error.code == 401 || error.code == 403) {
        _store.clearSession();
        _session = null;
      }
      _error = error.message;
    } catch (error) {
      _error = error.toString();
    } finally {
      _booting = false;
      notifyListeners();
    }
  }

  Future<void> hotResume() async {
    _lastHotResumeAt = _store.markHotResume();
    _session = _store.readSession();
    notifyListeners();
    if (_session == null) {
      return;
    }
    try {
      await _refreshLoggedInSession();
    } on ApiException catch (error) {
      if (error.code == 401 || error.code == 403) {
        _store.clearSession();
        _session = null;
      }
      _error = error.message;
      notifyListeners();
    } catch (error) {
      _error = error.toString();
      notifyListeners();
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
    String mobile = '',
    String email = '',
    String captcha = '',
    String inviteCode = '',
  }) async {
    await _runBusy(() {
      return _api.register(
        username: username,
        password: password,
        mobile: mobile,
        email: email,
        captcha: captcha,
        inviteCode: inviteCode,
        device: _device,
      );
    });
  }

  Future<void> sendEmailCode(String email) {
    return _runBusy(() => _api.sendEmailCode(email));
  }

  Future<void> sendMobileCode(String mobile) {
    return _runBusy(() => _api.sendMobileCode(mobile));
  }

  Future<List<Map<String, Object?>>> loadConversations() async {
    final current = _requireSession();
    final local = await _im.refreshLocalConversations();
    if (local.isNotEmpty) {
      return local;
    }
    return _api.conversations(session: current, device: _device);
  }

  Future<List<Map<String, Object?>>> loadFriends() async {
    final current = _requireSession();
    return _api.friends(session: current, device: _device);
  }

  Future<List<Map<String, Object?>>> loadGroups() async {
    final current = _requireSession();
    return _api.groups(session: current, device: _device);
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
    final current = _requireSession();
    final content = text.trim();
    if (content.isEmpty) {
      throw ApiException('消息内容不能为空');
    }
    if (channelType == 2) {
      await _chat.sendGroupText(
        session: current,
        device: _device,
        groupId: groupId.isEmpty ? channelId : groupId,
        content: content,
        mentionUserIds: mentionUserIds,
        mentionAll: mentionAll,
        replyClientMsgNo: replyClientMsgNo,
        burnAfterRead: burnAfterRead,
        burnAfterReadSeconds: burnAfterReadSeconds,
      );
    } else {
      await _chat.sendPrivateText(
        session: current,
        device: _device,
        receiverId: _userIdFromUid(channelId),
        content: content,
        replyClientMsgNo: replyClientMsgNo,
        burnAfterRead: burnAfterRead,
        burnAfterReadSeconds: burnAfterReadSeconds,
      );
    }
    _chat.clearDraft(channelId: channelId, channelType: channelType);
    await _im.refreshLocalConversations();
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
  }) {
    final current = _requireSession();
    return _chat.sendPrivateMedia(
      session: current,
      device: _device,
      receiverId: receiverId,
      contentType: contentType,
      url: url,
      filePath: filePath,
      params: params,
    );
  }

  Future<Map<String, Object?>> sendGroupMedia({
    required String groupId,
    required String contentType,
    String url = '',
    String filePath = '',
    Map<String, Object?> params = const {},
  }) {
    final current = _requireSession();
    return _chat.sendGroupMedia(
      session: current,
      device: _device,
      groupId: groupId,
      contentType: contentType,
      url: url,
      filePath: filePath,
      params: params,
    );
  }

  Future<Map<String, Object?>> sendPrivateContactCard({
    required String receiverId,
    required String cardUserId,
  }) {
    final current = _requireSession();
    return _chat.sendPrivateContactCard(
      session: current,
      device: _device,
      receiverId: receiverId,
      cardUserId: cardUserId,
    );
  }

  Future<Map<String, Object?>> sendGroupContactCard({
    required String groupId,
    required String cardUserId,
  }) {
    final current = _requireSession();
    return _chat.sendGroupContactCard(
      session: current,
      device: _device,
      groupId: groupId,
      cardUserId: cardUserId,
    );
  }

  Future<Map<String, Object?>> sendPrivateTransfer({
    required String receiverId,
    required String money,
    required String assetType,
  }) {
    final current = _requireSession();
    return _chat.sendPrivateTransfer(
      session: current,
      device: _device,
      receiverId: receiverId,
      money: money,
      assetType: assetType,
    );
  }

  Future<Map<String, Object?>> sendGroupTransfer({
    required String groupId,
    required String receiverId,
    required String money,
    required String assetType,
  }) {
    final current = _requireSession();
    return _chat.sendGroupTransfer(
      session: current,
      device: _device,
      groupId: groupId,
      receiverId: receiverId,
      money: money,
      assetType: assetType,
    );
  }

  Future<Map<String, Object?>> sendPrivateRedPacket({
    required String receiverId,
    required String money,
    required String assetType,
    String remark = '',
  }) {
    final current = _requireSession();
    return _chat.sendPrivateRedPacket(
      session: current,
      device: _device,
      receiverId: receiverId,
      money: money,
      assetType: assetType,
      remark: remark,
    );
  }

  Future<Map<String, Object?>> sendGroupRedPacket({
    required String groupId,
    required String money,
    required String assetType,
    required String packetType,
    int quantity = 1,
    String receiverId = '',
    String remark = '',
  }) {
    final current = _requireSession();
    return _chat.sendGroupRedPacket(
      session: current,
      device: _device,
      groupId: groupId,
      money: money,
      assetType: assetType,
      packetType: packetType,
      quantity: quantity,
      receiverId: receiverId,
      remark: remark,
    );
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

  Future<Map<String, Object?>> deleteFriend(String friendId) {
    final current = _requireSession();
    return _chat.friendDelete(
      session: current,
      device: _device,
      friendId: friendId,
    );
  }

  Future<Map<String, Object?>> retryMessages({int limit = 20}) {
    final current = _requireSession();
    return _chat.retryMessages(session: current, device: _device, limit: limit);
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
    bool deletePeer = false,
  }) {
    final current = _requireSession();
    return _chat.privateConversationDelete(
      session: current,
      device: _device,
      receiverId: receiverId,
      deletePeer: deletePeer,
    );
  }

  Future<void> logout() async {
    final current = _session;
    _store.clearSession();
    _session = null;
    notifyListeners();
    if (current == null) {
      return;
    }
    try {
      await _im.stop(logout: true);
      await _api.logout(session: current, device: _device);
    } catch (_) {
      // 本地退出必须即时生效，服务端设备退出失败由下次登录覆盖 token。
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
    final current = _requireSession();
    final chat = await _api.connectIm(session: current, device: _device);
    final withChat = current.copyWith(chat: chat);
    final withProfile = await _api.getCurrentUser(withChat);
    _session = withProfile;
    _store.writeSession(withProfile);
    await _im.start(withProfile, device: _device);
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await task();
    } on ApiException catch (error) {
      _error = error.message;
      rethrow;
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _userIdFromUid(String uid) {
    final match = RegExp(r'user(\d+)$').firstMatch(uid);
    return match?.group(1) ?? uid;
  }

  @override
  void dispose() {
    _im.removeListener(notifyListeners);
    unawaited(_im.stop());
    super.dispose();
  }
}
