import '../core/api_client.dart';
import '../core/models.dart';
import 'im_cache_store.dart';
import 'im_message_types.dart';
import 'wukong_im_service.dart';

class ChatFeatureService {
  ChatFeatureService({
    required ApiClient api,
    required WukongImService im,
    required ImCacheStore cache,
  }) : _api = api,
       _im = im,
       _cache = cache;

  final ApiClient _api;
  final WukongImService _im;
  final ImCacheStore _cache;

  // SDK 负责实时连接、本地消息库和 client_msg_no；业务端负责权限和资金类规则。
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

  Future<Map<String, Object?>> sendPrivate({
    required UserSession session,
    required String device,
    required String receiverId,
    required String contentType,
    Map<String, Object?> params = const {},
    String filePath = '',
    String clientMsgNo = '',
  }) {
    return _api.sendPersonMessage(
      session: session,
      device: device,
      receiverId: receiverId,
      clientMsgNo: _messageNo(clientMsgNo),
      contentType: contentType,
      params: _clean(params),
      filePath: filePath,
    );
  }

  Future<Map<String, Object?>> sendGroup({
    required UserSession session,
    required String device,
    required String groupId,
    required String contentType,
    Map<String, Object?> params = const {},
    String filePath = '',
    String clientMsgNo = '',
  }) {
    return _api.sendGroupMessage(
      session: session,
      device: device,
      groupId: groupId,
      clientMsgNo: _messageNo(clientMsgNo),
      contentType: contentType,
      params: _clean(params),
      filePath: filePath,
    );
  }

  Future<Map<String, Object?>> sendPrivateText({
    required UserSession session,
    required String device,
    required String receiverId,
    required String content,
    String replyClientMsgNo = '',
    bool burnAfterRead = false,
    int burnAfterReadSeconds = 0,
  }) {
    return sendPrivate(
      session: session,
      device: device,
      receiverId: receiverId,
      contentType: ChatContentTypes.text,
      params: {
        'content': content,
        if (replyClientMsgNo.isNotEmpty)
          'reply_client_msg_no': replyClientMsgNo,
        if (burnAfterRead) 'burn_after_read': '1',
        if (burnAfterReadSeconds > 0)
          'burn_after_read_seconds': burnAfterReadSeconds.toString(),
      },
    );
  }

  Future<Map<String, Object?>> sendGroupText({
    required UserSession session,
    required String device,
    required String groupId,
    required String content,
    List<String> mentionUserIds = const [],
    bool mentionAll = false,
    String replyClientMsgNo = '',
    bool burnAfterRead = false,
    int burnAfterReadSeconds = 0,
  }) {
    return sendGroup(
      session: session,
      device: device,
      groupId: groupId,
      contentType: ChatContentTypes.text,
      params: {
        'content': content,
        if (mentionUserIds.isNotEmpty)
          'mention_user_ids': mentionUserIds.join(','),
        if (mentionAll) 'mention_all': '1',
        if (replyClientMsgNo.isNotEmpty)
          'reply_client_msg_no': replyClientMsgNo,
        if (burnAfterRead) 'burn_after_read': '1',
        if (burnAfterReadSeconds > 0)
          'burn_after_read_seconds': burnAfterReadSeconds.toString(),
      },
    );
  }

  Future<Map<String, Object?>> sendPrivateMedia({
    required UserSession session,
    required String device,
    required String receiverId,
    required String contentType,
    String url = '',
    String filePath = '',
    Map<String, Object?> params = const {},
  }) {
    return sendPrivate(
      session: session,
      device: device,
      receiverId: receiverId,
      contentType: contentType,
      params: {if (url.isNotEmpty) 'url': url, ...params},
      filePath: filePath,
    );
  }

  Future<Map<String, Object?>> sendGroupMedia({
    required UserSession session,
    required String device,
    required String groupId,
    required String contentType,
    String url = '',
    String filePath = '',
    Map<String, Object?> params = const {},
  }) {
    return sendGroup(
      session: session,
      device: device,
      groupId: groupId,
      contentType: contentType,
      params: {if (url.isNotEmpty) 'url': url, ...params},
      filePath: filePath,
    );
  }

  Future<Map<String, Object?>> sendPrivateContactCard({
    required UserSession session,
    required String device,
    required String receiverId,
    required String cardUserId,
  }) {
    return sendPrivate(
      session: session,
      device: device,
      receiverId: receiverId,
      contentType: ChatContentTypes.contactCard,
      params: {'card_user_id': cardUserId},
    );
  }

  Future<Map<String, Object?>> sendGroupContactCard({
    required UserSession session,
    required String device,
    required String groupId,
    required String cardUserId,
  }) {
    return sendGroup(
      session: session,
      device: device,
      groupId: groupId,
      contentType: ChatContentTypes.contactCard,
      params: {'card_user_id': cardUserId},
    );
  }

  Future<Map<String, Object?>> sendPrivateTransfer({
    required UserSession session,
    required String device,
    required String receiverId,
    required String money,
    required String assetType,
  }) {
    return sendPrivate(
      session: session,
      device: device,
      receiverId: receiverId,
      contentType: ChatContentTypes.transfer,
      params: {'money': money, 'asset_type': assetType},
    );
  }

  Future<Map<String, Object?>> sendGroupTransfer({
    required UserSession session,
    required String device,
    required String groupId,
    required String receiverId,
    required String money,
    required String assetType,
  }) {
    return sendGroup(
      session: session,
      device: device,
      groupId: groupId,
      contentType: ChatContentTypes.transfer,
      params: {
        'receiver_id': receiverId,
        'money': money,
        'asset_type': assetType,
      },
    );
  }

  Future<Map<String, Object?>> sendPrivateRedPacket({
    required UserSession session,
    required String device,
    required String receiverId,
    required String money,
    required String assetType,
    String remark = '',
  }) {
    return sendPrivate(
      session: session,
      device: device,
      receiverId: receiverId,
      contentType: ChatContentTypes.redPacket,
      params: {
        'money': money,
        'asset_type': assetType,
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
  }

  Future<Map<String, Object?>> sendGroupRedPacket({
    required UserSession session,
    required String device,
    required String groupId,
    required String money,
    required String assetType,
    required String packetType,
    int quantity = 1,
    String receiverId = '',
    String remark = '',
  }) {
    return sendGroup(
      session: session,
      device: device,
      groupId: groupId,
      contentType: ChatContentTypes.redPacket,
      params: {
        'money': money,
        'asset_type': assetType,
        'packet_type': packetType,
        'quantity': quantity.toString(),
        if (receiverId.isNotEmpty) 'receiver_id': receiverId,
        if (remark.isNotEmpty) 'remark': remark,
      },
    );
  }

  Future<Map<String, Object?>> action({
    required String action,
    required UserSession session,
    required String device,
    Map<String, Object?> params = const {},
  }) {
    return _api.imBusinessAction(
      action: action,
      session: session,
      device: device,
      params: _clean(params),
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
    String friendId = '',
    int limit = 20,
  }) {
    return action(
      action: 'im_friend_search',
      session: session,
      device: device,
      params: {
        if (keyword.isNotEmpty) 'keyword': keyword,
        if (friendId.isNotEmpty) 'friend_id': friendId,
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
    bool deletePeer = false,
  }) {
    return action(
      action: 'im_person_conversation_delete',
      session: session,
      device: device,
      params: {'receiver_id': receiverId, if (deletePeer) 'delete_peer': '1'},
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

  String _messageNo(String clientMsgNo) {
    return clientMsgNo.isEmpty ? _im.newClientMsgNo() : clientMsgNo;
  }

  Map<String, Object?> _clean(Map<String, Object?> params) {
    return Map<String, Object?>.fromEntries(
      params.entries.where((entry) => entry.value != null),
    );
  }
}
