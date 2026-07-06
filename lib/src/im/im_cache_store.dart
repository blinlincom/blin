import 'dart:convert';

import 'package:mmkv/mmkv.dart';

class ImCacheStore {
  ImCacheStore(this._kv);

  final MMKV _kv;

  static const _draftPrefix = 'im_draft';
  static const _recentPrefix = 'im_recent_channels';
  static const _conversationPrefix = 'im_conversations';
  static const _messagePrefix = 'im_messages';
  static const _friendListPrefix = 'im_friend_list';
  static const _groupListPrefix = 'im_group_list';
  static const _profilePrefix = 'im_profile';
  static const _readPrefix = 'im_read_marker';
  static const _gatewayCursorPrefix = 'im_gateway_cursor';
  static const _clearPrefix = 'im_chat_clear_marker';
  static const _deletedPrefix = 'im_deleted_messages';
  static const _historySyncedPrefix = 'im_history_synced';

  String readDraft({required String channelId, required int channelType}) {
    return _kv.decodeString(_draftKey(channelId, channelType)) ?? '';
  }

  void writeDraft({
    required String channelId,
    required int channelType,
    required String text,
  }) {
    final key = _draftKey(channelId, channelType);
    if (text.trim().isEmpty) {
      _kv.removeValue(key);
      return;
    }
    _kv.encodeString(key, text);
  }

  void clearDraft({required String channelId, required int channelType}) {
    _kv.removeValue(_draftKey(channelId, channelType));
  }

  int readGlobalClearMarker(String uid) {
    return _kv.decodeInt(_globalClearKey(uid));
  }

  void writeGlobalClearMarker({required String uid, required int timestampMs}) {
    _kv.encodeInt(_globalClearKey(uid), timestampMs);
  }

  int readChannelClearMarker({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    final global = readGlobalClearMarker(uid);
    final channel = _kv.decodeInt(
      _channelClearKey(uid, channelId, channelType),
    );
    return global > channel ? global : channel;
  }

  void writeChannelClearMarker({
    required String uid,
    required String channelId,
    required int channelType,
    required int timestampMs,
  }) {
    _kv.encodeInt(_channelClearKey(uid, channelId, channelType), timestampMs);
  }

  void removeChannelClearMarker({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    _kv.removeValue(_channelClearKey(uid, channelId, channelType));
  }

  Set<String> readDeletedMessages({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    final raw = _kv.decodeString(_deletedKey(uid, channelId, channelType));
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const {};
    }
    return decoded.map((item) => item.toString()).toSet();
  }

  void rememberDeletedMessage({
    required String uid,
    required String channelId,
    required int channelType,
    required String clientMsgNo,
  }) {
    if (clientMsgNo.isEmpty) {
      return;
    }
    final deleted = readDeletedMessages(
      uid: uid,
      channelId: channelId,
      channelType: channelType,
    ).toSet();
    deleted.add(clientMsgNo);
    _kv.encodeString(
      _deletedKey(uid, channelId, channelType),
      jsonEncode(deleted.toList(growable: false)),
    );
  }

  List<Map<String, Object?>> clearAllChatRecords({
    required String uid,
    required int timestampMs,
  }) {
    final channels = knownChannels(uid);
    writeGlobalClearMarker(uid: uid, timestampMs: timestampMs);
    final prefixes = [
      '$_conversationPrefix:$uid',
      '$_recentPrefix:$uid',
      '$_messagePrefix:$uid:',
      '$_readPrefix:$uid:',
      '$_deletedPrefix:$uid:',
      '$_historySyncedPrefix:$uid:',
    ];
    final keys = _kv.allKeys
        .where((key) => prefixes.any(key.startsWith))
        .toList(growable: false);
    if (keys.isNotEmpty) {
      _kv.removeValues(keys);
    }
    for (final channel in channels) {
      final channelId = channel['channel_id']?.toString() ?? '';
      final channelType =
          int.tryParse(channel['channel_type']?.toString() ?? '') ?? 0;
      if (channelId.isEmpty || channelType <= 0) {
        continue;
      }
      clearDraft(channelId: channelId, channelType: channelType);
    }
    return channels;
  }

  void clearChannelChatRecords({
    required String uid,
    required String channelId,
    required int channelType,
    required int timestampMs,
  }) {
    writeChannelClearMarker(
      uid: uid,
      channelId: channelId,
      channelType: channelType,
      timestampMs: timestampMs,
    );
    _kv.removeValues([
      _messageKey(uid, channelId, channelType),
      _readMarkerKey(uid, channelId, channelType),
      _deletedKey(uid, channelId, channelType),
      _historySyncedKey(uid, channelId, channelType),
      _draftKey(channelId, channelType),
    ]);
    final conversations = readConversations(uid)
        .where(
          (item) =>
              item['channel_id']?.toString() != channelId ||
              (int.tryParse(item['channel_type']?.toString() ?? '') ?? 0) !=
                  channelType,
        )
        .toList(growable: false);
    writeConversations(uid: uid, conversations: conversations);
    final recent = readRecentChannels(uid)
        .where((item) => item != '$channelType:$channelId')
        .toList(growable: false);
    _kv.encodeString('$_recentPrefix:$uid', jsonEncode(recent));
  }

  void removeChannelCache({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    _kv.removeValues([
      _messageKey(uid, channelId, channelType),
      _readMarkerKey(uid, channelId, channelType),
      _deletedKey(uid, channelId, channelType),
      _historySyncedKey(uid, channelId, channelType),
      _draftKey(channelId, channelType),
    ]);
    final conversations = readConversations(uid)
        .where(
          (item) =>
              item['channel_id']?.toString() != channelId ||
              (int.tryParse(item['channel_type']?.toString() ?? '') ?? 0) !=
                  channelType,
        )
        .toList(growable: false);
    writeConversations(uid: uid, conversations: conversations);
    final recent = readRecentChannels(uid)
        .where((item) => item != '$channelType:$channelId')
        .toList(growable: false);
    _kv.encodeString('$_recentPrefix:$uid', jsonEncode(recent));
  }

  void deleteMessage({
    required String uid,
    required String channelId,
    required int channelType,
    required String clientMsgNo,
  }) {
    rememberDeletedMessage(
      uid: uid,
      channelId: channelId,
      channelType: channelType,
      clientMsgNo: clientMsgNo,
    );
    final messages =
        readMessages(uid: uid, channelId: channelId, channelType: channelType)
            .where((item) => item['client_msg_no']?.toString() != clientMsgNo)
            .toList();
    writeMessages(
      uid: uid,
      channelId: channelId,
      channelType: channelType,
      messages: messages,
    );
  }

  List<Map<String, Object?>> knownChannels(String uid) {
    final channels = <String, Map<String, Object?>>{};
    for (final conversation in readConversations(uid)) {
      final channelId = conversation['channel_id']?.toString() ?? '';
      final channelType =
          int.tryParse(conversation['channel_type']?.toString() ?? '') ?? 0;
      if (channelId.isEmpty || channelType <= 0) {
        continue;
      }
      channels['$channelType:$channelId'] = {
        'channel_id': channelId,
        'channel_type': channelType,
      };
    }
    for (final recent in readRecentChannels(uid)) {
      final separator = recent.indexOf(':');
      if (separator <= 0 || separator >= recent.length - 1) {
        continue;
      }
      final channelType = int.tryParse(recent.substring(0, separator)) ?? 0;
      final channelId = recent.substring(separator + 1);
      if (channelId.isEmpty || channelType <= 0) {
        continue;
      }
      channels['$channelType:$channelId'] = {
        'channel_id': channelId,
        'channel_type': channelType,
      };
    }
    return channels.values.toList(growable: false);
  }

  List<String> readRecentChannels(String uid) {
    final raw = _kv.decodeString('$_recentPrefix:$uid');
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((item) => item.toString()).toList(growable: false);
    }
    return const [];
  }

  void rememberRecentChannel({
    required String uid,
    required String channelId,
    int maxCount = 20,
  }) {
    final list = readRecentChannels(uid).toList();
    list.remove(channelId);
    list.insert(0, channelId);
    if (list.length > maxCount) {
      list.removeRange(maxCount, list.length);
    }
    _kv.encodeString('$_recentPrefix:$uid', jsonEncode(list));
  }

  List<Map<String, Object?>> readConversations(String uid) {
    return _readMapList('$_conversationPrefix:$uid');
  }

  void writeConversations({
    required String uid,
    required List<Map<String, Object?>> conversations,
  }) {
    _kv.encodeString('$_conversationPrefix:$uid', jsonEncode(conversations));
  }

  List<Map<String, Object?>> readFriendList(String uid) {
    return _readMapList('$_friendListPrefix:$uid');
  }

  void writeFriendList({
    required String uid,
    required List<Map<String, Object?>> friends,
  }) {
    _kv.encodeString('$_friendListPrefix:$uid', jsonEncode(friends));
  }

  void removeFriend({required String uid, required String friendId}) {
    if (friendId.isEmpty) {
      return;
    }
    final friends = readFriendList(
      uid,
    ).where((item) => _profileUserId(item) != friendId).toList(growable: false);
    writeFriendList(uid: uid, friends: friends);
  }

  Map<String, Object?> readProfile({
    required String uid,
    required String userId,
  }) {
    if (userId.isEmpty) {
      return const {};
    }
    return _readMap('$_profilePrefix:$uid:$userId');
  }

  void writeProfile({
    required String uid,
    required String userId,
    required Map<String, Object?> profile,
  }) {
    if (userId.isEmpty || profile.isEmpty) {
      return;
    }
    final current = readProfile(uid: uid, userId: userId);
    _kv.encodeString(
      '$_profilePrefix:$uid:$userId',
      jsonEncode({
        ...current,
        ..._nonEmptyFields(profile),
        'userid': userId,
        'id': userId,
      }),
    );
  }

  List<Map<String, Object?>> readGroupList(String uid) {
    return _readMapList('$_groupListPrefix:$uid');
  }

  void writeGroupList({
    required String uid,
    required List<Map<String, Object?>> groups,
  }) {
    _kv.encodeString('$_groupListPrefix:$uid', jsonEncode(groups));
  }

  List<Map<String, Object?>> readMessages({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    return _readMapList(_messageKey(uid, channelId, channelType));
  }

  void writeMessages({
    required String uid,
    required String channelId,
    required int channelType,
    required List<Map<String, Object?>> messages,
  }) {
    _kv.encodeString(
      _messageKey(uid, channelId, channelType),
      jsonEncode(messages),
    );
    rememberRecentChannel(uid: uid, channelId: '$channelType:$channelId');
  }

  Map<String, Object?> readReadMarker({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    return _readMap(_readMarkerKey(uid, channelId, channelType));
  }

  void writeReadMarker({
    required String uid,
    required String channelId,
    required int channelType,
    required Map<String, Object?> marker,
  }) {
    _kv.encodeString(
      _readMarkerKey(uid, channelId, channelType),
      jsonEncode(marker),
    );
  }

  String readGatewayCursor({required String uid, required String device}) {
    return _kv.decodeString(_gatewayCursorKey(uid, device)) ?? '';
  }

  void writeGatewayCursor({
    required String uid,
    required String device,
    required String cursor,
  }) {
    if (cursor.isEmpty) {
      return;
    }
    _kv.encodeString(_gatewayCursorKey(uid, device), cursor);
  }

  bool isChannelHistorySynced({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    return _kv.decodeInt(_historySyncedKey(uid, channelId, channelType)) == 1;
  }

  void writeChannelHistorySynced({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    if (uid.isEmpty || channelId.isEmpty || channelType <= 0) {
      return;
    }
    _kv.encodeInt(_historySyncedKey(uid, channelId, channelType), 1);
  }

  void removeChannelHistorySynced({
    required String uid,
    required String channelId,
    required int channelType,
  }) {
    _kv.removeValue(_historySyncedKey(uid, channelId, channelType));
  }

  String _draftKey(String channelId, int channelType) {
    return '$_draftPrefix:$channelType:$channelId';
  }

  String _messageKey(String uid, String channelId, int channelType) {
    return '$_messagePrefix:$uid:$channelType:$channelId';
  }

  String _readMarkerKey(String uid, String channelId, int channelType) {
    return '$_readPrefix:$uid:$channelType:$channelId';
  }

  String _gatewayCursorKey(String uid, String device) {
    return '$_gatewayCursorPrefix:$uid:$device';
  }

  String _historySyncedKey(String uid, String channelId, int channelType) {
    return '$_historySyncedPrefix:$uid:$channelType:$channelId';
  }

  String _globalClearKey(String uid) {
    return '$_clearPrefix:$uid:all';
  }

  String _channelClearKey(String uid, String channelId, int channelType) {
    return '$_clearPrefix:$uid:$channelType:$channelId';
  }

  String _deletedKey(String uid, String channelId, int channelType) {
    return '$_deletedPrefix:$uid:$channelType:$channelId';
  }

  Map<String, Object?> _readMap(String key) {
    final raw = _kv.decodeString(key);
    if (raw == null || raw.isEmpty) {
      return const {};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return _normalizeMap(decoded);
    }
    return const {};
  }

  List<Map<String, Object?>> _readMapList(String key) {
    final raw = _kv.decodeString(key);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const [];
    }
    return decoded
        .whereType<Map>()
        .map((item) => _normalizeMap(item))
        .toList(growable: false);
  }

  Map<String, Object?> _normalizeMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, Object?> _nonEmptyFields(Map<String, Object?> map) {
    return Map<String, Object?>.fromEntries(
      map.entries.where((entry) {
        final value = entry.value;
        if (value == null) {
          return false;
        }
        if (value is String) {
          return value.trim().isNotEmpty;
        }
        if (value is Iterable || value is Map) {
          return true;
        }
        return value.toString().trim().isNotEmpty;
      }),
    );
  }

  String _profileUserId(Map<String, Object?> item) {
    final nested = item['friend'] is Map
        ? _normalizeMap(item['friend'] as Map)
        : item['user'] is Map
        ? _normalizeMap(item['user'] as Map)
        : item;
    for (final key in ['friend_id', 'userid', 'user_id', 'id']) {
      final value = item[key]?.toString() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    for (final key in ['userid', 'user_id', 'id']) {
      final value = nested[key]?.toString() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    final uid =
        (item['uid'] ??
                item['channel_id'] ??
                nested['uid'] ??
                nested['channel_id'])
            ?.toString() ??
        '';
    final match = RegExp(r'user(\d+)$').firstMatch(uid);
    return match?.group(1) ?? '';
  }
}
