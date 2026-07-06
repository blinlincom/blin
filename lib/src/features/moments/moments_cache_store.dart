import 'dart:convert';

import 'package:mmkv/mmkv.dart';

class MomentsCacheStore {
  MomentsCacheStore(this._kv);

  final MMKV _kv;

  static const _feedPrefix = 'moments_feed';
  static const _draftPrefix = 'moments_draft';

  List<Map<String, Object?>> readFeed(String uid) {
    return _readMapList('$_feedPrefix:$uid');
  }

  void writeFeed({
    required String uid,
    required List<Map<String, Object?>> posts,
  }) {
    _kv.encodeString('$_feedPrefix:$uid', jsonEncode(posts));
  }

  String readDraft(String uid) => _kv.decodeString('$_draftPrefix:$uid') ?? '';

  void writeDraft({required String uid, required String text}) {
    final key = '$_draftPrefix:$uid';
    if (text.trim().isEmpty) {
      _kv.removeValue(key);
      return;
    }
    _kv.encodeString(key, text);
  }

  void clearDraft(String uid) {
    _kv.removeValue('$_draftPrefix:$uid');
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
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }
}
