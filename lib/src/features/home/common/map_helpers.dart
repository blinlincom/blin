part of 'package:bim/src/features/home/home_page.dart';

String _value(
  Map<String, Object?> item,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = item[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return fallback;
}

int _intValue(Map<String, Object?> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return 0;
}

bool _boolValue(Object? value) {
  if (value is Map) {
    return value.isNotEmpty;
  }
  if (value is Iterable) {
    return value.isNotEmpty;
  }
  final text = value?.toString().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}

bool _sameStringMap(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key]?.toString() != entry.value?.toString()) {
      return false;
    }
  }
  return true;
}

String _groupMuteText(Map<String, Object?> state) {
  if (!_boolValue(state['muted'])) {
    return '';
  }
  final expire = _value(state, ['expire_time', 'mute_expire_time']);
  if (expire.isNotEmpty) {
    final expireAt = _parseUiTime(expire);
    if (expireAt != null && !expireAt.isAfter(DateTime.now())) {
      return '';
    }
  }
  final notice = _value(state, ['notice']);
  if (notice.isNotEmpty) {
    return notice;
  }
  final reason = _value(state, ['reason']);
  final permanent =
      _boolValue(state['permanent']) || _boolValue(state['mute_permanent']);
  final parts = <String>['你已被管理员禁言'];
  if (reason.isNotEmpty) {
    parts.add('原因：$reason');
  }
  parts.add(permanent || expire.isEmpty ? '永久生效' : '至 $expire');
  return parts.join('，');
}

DateTime? _parseUiTime(String value) {
  final numeric = int.tryParse(value);
  if (numeric != null) {
    final millis = numeric > 100000000000 ? numeric : numeric * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  return DateTime.tryParse(value.replaceFirst(' ', 'T'));
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<Map<String, Object?>> _mapListValue(
  Map<String, Object?> item,
  List<String> keys,
) {
  for (final key in keys) {
    final value = item[key];
    if (value is List) {
      return value
          .whereType<Map>()
          .map(
            (entry) => entry.map(
              (entryKey, entryValue) =>
                  MapEntry(entryKey.toString(), entryValue),
            ),
          )
          .toList(growable: false);
    }
  }
  return const [];
}

List<Map<String, Object?>> _listFromResult(Map<String, Object?> result) {
  Object? value = result['list'] ?? result['items'];
  final data = result['data'];
  if (value == null && data is Map) {
    value = data['list'] ?? data['items'] ?? data['rows'] ?? data['records'];
  }
  if (value == null && data is List) {
    value = data;
  }
  if (value is List) {
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }
  return const [];
}

bool _memberMatchesOnlineUser(
  Map<String, Object?> member,
  Map<String, Object?> onlineUser,
) {
  for (final id in _memberPresenceIds(member)) {
    if (_onlineUserMatches(onlineUser, id)) {
      return true;
    }
  }
  return false;
}

Iterable<String> _memberPresenceIds(Map<String, Object?> member) sync* {
  for (final key in [
    'uid',
    'im_uid',
    'wukong_uid',
    'channel_id',
    'user_uid',
    'member_uid',
  ]) {
    final value = _value(member, [key]);
    if (value.isNotEmpty) {
      yield value;
    }
  }
  final userId = _memberUserId(member);
  if (userId.isNotEmpty) {
    yield userId;
    yield _uidFromUserId(userId);
  }
  final user = _asObjectMap(member['user']);
  if (user.isNotEmpty) {
    yield* _memberPresenceIds(user);
  }
}

String _memberPresenceKey(Map<String, Object?> member) {
  for (final id in _memberPresenceIds(member)) {
    if (id.isNotEmpty) {
      return id;
    }
  }
  return jsonEncode(member);
}

bool _onlineUserMatches(Map<String, Object?> item, String receiverId) {
  if (_onlineFlagKnownFalse(item)) {
    return false;
  }
  final userId = _privateReceiverIdFromChannel(receiverId);
  final uid = _uidFromUserId(userId);
  for (final key in [
    'uid',
    'im_uid',
    'wukong_uid',
    'channel_id',
    'from_uid',
    'user_uid',
  ]) {
    final value = _value(item, [key]);
    if (value == uid || value == receiverId) {
      return true;
    }
  }
  for (final key in [
    'user_id',
    'userid',
    'id',
    'friend_id',
    'receiver_id',
    'member_id',
  ]) {
    if (_value(item, [key]) == userId) {
      return true;
    }
  }
  final user = _asObjectMap(item['user']);
  return user.isNotEmpty && _onlineUserMatches(user, receiverId);
}

bool _onlineFlagKnownFalse(Map<String, Object?> item) {
  for (final key in ['online', 'is_online', 'connected']) {
    final value = item[key];
    if (value != null && !_boolValue(value)) {
      return true;
    }
  }
  final status = _value(item, [
    'status',
    'online_status',
    'state',
  ]).toLowerCase();
  return status == 'offline' || status == '离线' || status == '0';
}

bool _sameMapList(
  List<Map<String, Object?>> left,
  List<Map<String, Object?>> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (jsonEncode(left[index]) != jsonEncode(right[index])) {
      return false;
    }
  }
  return true;
}

List<String> _idsFromText(String text) {
  return text
      .split(RegExp(r'[,，\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

String _uidFromUserId(String userId) {
  if (userId.startsWith('app')) {
    return userId;
  }
  return 'app${AppConfig.appId}user$userId';
}

String _privateReceiverIdFromChannel(String channelId) {
  final match = RegExp(r'user(\d+)$').firstMatch(channelId);
  return match?.group(1) ?? channelId;
}

String _nestedValue(Map<String, Object?> payload, List<String> paths) {
  for (final path in paths) {
    Object? current = payload;
    for (final key in path.split('.')) {
      if (current is Map) {
        current = current[key];
      } else {
        current = null;
      }
    }
    if (current != null && current.toString().isNotEmpty) {
      return current.toString();
    }
  }
  return '';
}
