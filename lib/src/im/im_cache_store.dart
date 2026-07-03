import 'dart:convert';

import 'package:mmkv/mmkv.dart';

class ImCacheStore {
  ImCacheStore(this._kv);

  final MMKV _kv;

  static const _draftPrefix = 'im_draft';
  static const _recentPrefix = 'im_recent_channels';

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

  String _draftKey(String channelId, int channelType) {
    return '$_draftPrefix:$channelType:$channelId';
  }
}
