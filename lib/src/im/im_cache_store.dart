import 'dart:convert';

import 'package:mmkv/mmkv.dart';

class ImCacheStore {
  ImCacheStore(this._kv);

  final MMKV _kv;

  static const _draftPrefix = 'im_draft';
  static const _recentPrefix = 'im_recent_channels';
  static const _conversationPrefix = 'im_conversations';
  static const _messagePrefix = 'im_messages';
  static const _readPrefix = 'im_read_marker';

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

  String _draftKey(String channelId, int channelType) {
    return '$_draftPrefix:$channelType:$channelId';
  }

  String _messageKey(String uid, String channelId, int channelType) {
    return '$_messagePrefix:$uid:$channelType:$channelId';
  }

  String _readMarkerKey(String uid, String channelId, int channelType) {
    return '$_readPrefix:$uid:$channelType:$channelId';
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
}
