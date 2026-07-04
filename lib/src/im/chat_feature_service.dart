import '../core/api_client.dart';
import '../core/models.dart';
import 'im_cache_store.dart';

class ChatFeatureService {
  ChatFeatureService({required ApiClient api, required ImCacheStore cache})
    : _api = api,
      _cache = cache;

  final ApiClient _api;
  final ImCacheStore _cache;

  // 实时收包由 TCP 长连接负责，草稿等轻量状态写入 MMKV。
  String readDraft({required String channelId, required int channelType}) {
    return _cache.readDraft(channelId: channelId, channelType: channelType);
  }

  void writeDraft({
    required String channelId,
    required int channelType,
    required String text,
  }) {
    _cache.writeDraft(
      channelId: channelId,
      channelType: channelType,
      text: text,
    );
  }

  void clearDraft({required String channelId, required int channelType}) {
    _cache.clearDraft(channelId: channelId, channelType: channelType);
  }

  Future<Map<String, Object?>> action({
    required String action,
    required UserSession session,
    required String device,
    Map<String, Object?> params = const {},
    bool secureResponse = true,
  }) {
    return _api.imBusinessAction(
      action: action,
      session: session,
      device: device,
      params: _clean(params),
      secureResponse: secureResponse,
    );
  }

  Future<Map<String, Object?>> friendApply({
    required UserSession session,
    required String device,
    required String friendId,
    String remark = '',
  }) {
    return action(
      action: 'im_friend_apply',
      session: session,
      device: device,
      params: {'friend_id': friendId, if (remark.isNotEmpty) 'remark': remark},
    );
  }

  Future<Map<String, Object?>> friendHandle({
    required UserSession session,
    required String device,
    required String applyId,
    required bool accept,
    String handleMsg = '',
  }) {
    return action(
      action: 'im_friend_handle',
      session: session,
      device: device,
      params: {
        'apply_id': applyId,
        'accept': accept ? '1' : '0',
        if (handleMsg.isNotEmpty) 'handle_msg': handleMsg,
      },
    );
  }

  Future<Map<String, Object?>> friendApplyList({
    required UserSession session,
    required String device,
    String type = 'in',
    String status = '',
    int page = 1,
    int limit = 20,
  }) {
    return action(
      action: 'im_friend_apply_list',
      session: session,
      device: device,
      params: {
        'type': type,
        if (status.isNotEmpty) 'status': status,
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );
  }

  Future<Map<String, Object?>> friendStatus({
    required UserSession session,
    required String device,
    required String friendId,
  }) {
    return action(
      action: 'im_friend_status',
      session: session,
      device: device,
      params: {'friend_id': friendId},
    );
  }

  Future<Map<String, Object?>> friendSearch({
    required UserSession session,
    required String device,
    String keyword = '',
    int limit = 20,
  }) {
    return action(
      action: 'im_friend_search',
      session: session,
      device: device,
      params: {
        if (keyword.isNotEmpty) 'keyword': keyword,
        'limit': limit.toString(),
      },
    );
  }

  Future<Map<String, Object?>> friendDelete({
    required UserSession session,
    required String device,
    required String friendId,
  }) {
    return action(
      action: 'im_friend_delete',
      session: session,
      device: device,
      params: {'friend_id': friendId},
    );
  }

  Future<Map<String, Object?>> groupCreate({
    required UserSession session,
    required String device,
    required String name,
    List<String> memberIds = const [],
    String avatar = '',
    String notice = '',
  }) {
    return action(
      action: 'im_group_create',
      session: session,
      device: device,
      params: {
        'name': name,
        if (memberIds.isNotEmpty) 'member_ids': memberIds.join(','),
        if (avatar.isNotEmpty) 'avatar': avatar,
        if (notice.isNotEmpty) 'notice': notice,
      },
    );
  }

  Future<Map<String, Object?>> groupUpdate({
    required UserSession session,
    required String device,
    required String groupId,
    String name = '',
    String avatar = '',
    String notice = '',
  }) {
    return action(
      action: 'im_group_update',
      session: session,
      device: device,
      params: {
        'group_id': groupId,
        if (name.isNotEmpty) 'name': name,
        if (avatar.isNotEmpty) 'avatar': avatar,
        if (notice.isNotEmpty) 'notice': notice,
      },
    );
  }

  Future<Map<String, Object?>> groupMembers({
    required UserSession session,
    required String device,
    required String groupId,
  }) {
    return action(
      action: 'im_group_members',
      session: session,
      device: device,
      params: {'group_id': groupId},
    );
  }

  Future<Map<String, Object?>> groupMembersAdd({
    required UserSession session,
    required String device,
    required String groupId,
    required List<String> memberIds,
  }) {
    return action(
      action: 'im_group_members_add',
      session: session,
      device: device,
      params: {'group_id': groupId, 'member_ids': memberIds.join(',')},
    );
  }

  Future<Map<String, Object?>> groupMembersRemove({
    required UserSession session,
    required String device,
    required String groupId,
    required List<String> memberIds,
  }) {
    return action(
      action: 'im_group_members_remove',
      session: session,
      device: device,
      params: {'group_id': groupId, 'member_ids': memberIds.join(',')},
    );
  }

  Future<Map<String, Object?>> groupMemberMute({
    required UserSession session,
    required String device,
    required String groupId,
    required String memberId,
    int expireSeconds = 0,
    String reason = '',
  }) {
    return action(
      action: 'im_group_member_mute',
      session: session,
      device: device,
      params: {
        'group_id': groupId,
        'member_id': memberId,
        if (expireSeconds > 0) 'expire_seconds': expireSeconds.toString(),
        if (reason.isNotEmpty) 'reason': reason,
      },
    );
  }

  Future<Map<String, Object?>> groupMemberUnmute({
    required UserSession session,
    required String device,
    required String groupId,
    required String memberId,
  }) {
    return action(
      action: 'im_group_member_unmute',
      session: session,
      device: device,
      params: {'group_id': groupId, 'member_id': memberId},
    );
  }

  Future<Map<String, Object?>> groupMuteStatus({
    required UserSession session,
    required String device,
    required String groupId,
  }) {
    return action(
      action: 'im_group_mute_status',
      session: session,
      device: device,
      params: {'group_id': groupId},
    );
  }

  Future<Map<String, Object?>> groupAdminSet({
    required UserSession session,
    required String device,
    required String groupId,
    required String memberId,
    required bool isAdmin,
  }) {
    return action(
      action: 'im_group_admin_set',
      session: session,
      device: device,
      params: {
        'group_id': groupId,
        'member_id': memberId,
        'is_admin': isAdmin ? '1' : '0',
      },
    );
  }

  Future<Map<String, Object?>> groupOwnerTransfer({
    required UserSession session,
    required String device,
    required String groupId,
    required String newOwnerId,
  }) {
    return action(
      action: 'im_group_owner_transfer',
      session: session,
      device: device,
      params: {'group_id': groupId, 'new_owner_id': newOwnerId},
    );
  }

  Future<Map<String, Object?>> groupLeave({
    required UserSession session,
    required String device,
    required String groupId,
  }) {
    return action(
      action: 'im_group_leave',
      session: session,
      device: device,
      params: {'group_id': groupId},
    );
  }

  Future<Map<String, Object?>> groupDelete({
    required UserSession session,
    required String device,
    required String groupId,
  }) {
    return action(
      action: 'im_group_delete',
      session: session,
      device: device,
      params: {'group_id': groupId},
    );
  }

  Future<Map<String, Object?>> privateConversationDelete({
    required UserSession session,
    required String device,
    required String receiverId,
  }) {
    return _api.deletePrivateConversation(
      session: session,
      device: device,
      receiverId: receiverId,
    );
  }

  Future<Map<String, Object?>> groupConversationDelete({
    required UserSession session,
    required String device,
    required String groupId,
  }) {
    return _api.deleteGroupConversation(
      session: session,
      device: device,
      groupId: groupId,
    );
  }

  Future<Map<String, Object?>> clearAllChatRecords({
    required UserSession session,
    required String device,
  }) {
    return _api.clearAllChatRecords(session: session, device: device);
  }

  Future<Map<String, Object?>> deleteMessageForSelf({
    required UserSession session,
    required String device,
    required String targetClientMsgNo,
  }) {
    return _api.deleteMessageForSelf(
      session: session,
      device: device,
      targetClientMsgNo: targetClientMsgNo,
    );
  }

  Future<Map<String, Object?>> retryMessages({
    required UserSession session,
    required String device,
    int limit = 20,
  }) {
    return action(
      action: 'im_retry_messages',
      session: session,
      device: device,
      params: {'limit': limit.toString()},
    );
  }

  Future<Map<String, Object?>> onlineUsers({
    required UserSession session,
    required String device,
    int page = 1,
    int limit = 20,
  }) {
    return action(
      action: 'im_online_users',
      session: session,
      device: device,
      params: {'page': page.toString(), 'limit': limit.toString()},
    );
  }

  Map<String, Object?> _clean(Map<String, Object?> params) {
    return Map<String, Object?>.fromEntries(
      params.entries.where((entry) => entry.value != null),
    );
  }
}
