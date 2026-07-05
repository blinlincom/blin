part of 'package:bim/src/features/home/home_page.dart';

String _friendTitle(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final remark = _value(item, ['remark']);
  if (remark.isNotEmpty) {
    return remark;
  }
  return _value(profile, [
    'nickname',
    'username',
    'name',
  ], fallback: _value(item, ['nickname', 'username', 'name'], fallback: '好友'));
}

String _friendUserId(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final raw = _value(item, ['friend_id', 'userid', 'user_id']);
  if (raw.isNotEmpty) {
    return raw;
  }
  final nested = _value(profile, ['userid', 'user_id', 'id']);
  if (nested.isNotEmpty) {
    return nested;
  }
  return _privateReceiverIdFromChannel(_value(item, ['uid', 'channel_id']));
}

String _friendUsername(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  return _value(profile, ['username'], fallback: _value(item, ['username']));
}

String _friendSubtitle(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final username = _friendUsername(item);
  final signature = _value(profile, [
    'signature',
    'bio',
  ], fallback: _value(item, ['signature']));
  return [
    _friendPresenceText(item),
    if (username.isNotEmpty) '用户名 $username',
    if (signature.isNotEmpty) signature,
  ].join(' · ');
}

String _friendPresenceText(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  for (final source in [item, profile]) {
    for (final key in ['online', 'is_online', 'connected']) {
      final value = source[key];
      if (value != null) {
        return _boolValue(value) ? '在线' : '离线';
      }
    }
    final status = _value(source, [
      'online_status',
      'status',
      'state',
    ]).toLowerCase();
    if (status == 'online' || status == 'connected' || status == '1') {
      return '在线';
    }
    if (status == 'offline' || status == '0' || status == '离线') {
      return '离线';
    }
  }
  return '离线';
}

String _friendAvatarUrl(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  return _avatarUrlFromMap(profile, fallback: _avatarUrlFromMap(item));
}

Map<String, Object?> _friendProfile(Map<String, Object?> item) {
  final friend = _asObjectMap(item['friend']);
  if (friend.isNotEmpty) {
    return friend;
  }
  final user = _asObjectMap(item['user']);
  if (user.isNotEmpty) {
    return user;
  }
  return item;
}

String _searchFriendId(Map<String, Object?> item) {
  final user = _asObjectMap(item['user']);
  return _value(item, [
    'friend_id',
    'user_id',
    'userid',
    'id',
  ], fallback: _value(user, ['userid', 'user_id', 'id']));
}

String _searchFriendTitle(Map<String, Object?> item) {
  final user = _asObjectMap(item['user']);
  return _value(user, [
    'nickname',
    'username',
    'name',
  ], fallback: _value(item, ['nickname', 'username', 'name'], fallback: '用户'));
}

String _groupAvatarUrl(Map<String, Object?> item) {
  return _avatarUrlFromMap(item);
}

String _avatarUrlFromMap(Map<String, Object?> item, {String fallback = ''}) {
  return _normalizeAvatarUrl(
    _value(item, [
      'avatar',
      'usertx',
      'user_avatar',
      'group_avatar',
      'headimg',
      'head_img',
      'photo',
      'portrait',
    ], fallback: fallback),
  );
}

String _normalizeAvatarUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.startsWith('data:')) {
    return value;
  }
  final uri = Uri.tryParse(value);
  if (uri != null && uri.hasScheme) {
    return value;
  }
  final base = Uri.tryParse(AppConfig.apiBaseUrl);
  if (base == null || !base.hasScheme || base.host.isEmpty) {
    return value;
  }
  final origin = base.replace(path: '/', query: '', fragment: '');
  if (value.startsWith('/')) {
    return origin.resolve(value).toString();
  }
  return origin.resolve(value).toString();
}

void _precacheConversationAvatars(
  BuildContext context,
  Iterable<Map<String, Object?>> conversations,
) {
  _precacheAvatarUrls(context, conversations.map(_conversationAvatarUrl));
}

void _precacheContactAvatars(
  BuildContext context,
  Iterable<Map<String, Object?>> friends,
  Iterable<Map<String, Object?>> groups,
) {
  _precacheAvatarUrls(context, [
    ...friends.map(_friendAvatarUrl),
    ...groups.map(_groupAvatarUrl),
  ]);
}

void _precacheMessageAvatars(
  BuildContext context,
  Iterable<Map<String, Object?>> messages,
  String currentUserAvatarUrl,
) {
  _precacheAvatarUrls(context, [
    if (currentUserAvatarUrl.isNotEmpty) currentUserAvatarUrl,
    ...messages.map(_messageSenderAvatarUrl),
  ]);
}

void _precacheAvatarUrls(BuildContext context, Iterable<String> urls) {
  final unique = <String>{};
  for (final url in urls.map(_normalizeAvatarUrl)) {
    if (url.isEmpty || !unique.add(url)) {
      continue;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      unawaited(
        precacheImage(NetworkImage(url), context).catchError((Object _) {}),
      );
    });
  }
}

String _searchFriendSubtitle(Map<String, Object?> item) {
  final user = _asObjectMap(item['user']);
  final username = _value(user, ['username']);
  final signature = _value(user, ['signature']);
  return [
    if (username.isNotEmpty) username,
    if (signature.isNotEmpty) signature,
    _friendStatusText(item),
  ].join(' · ');
}

String _searchFriendActionText(Map<String, Object?> item) {
  if (_boolValue(item['is_friend'])) {
    return '发消息';
  }
  if (_boolValue(item['pending_out_apply'])) {
    return '已申请';
  }
  if (_boolValue(item['pending_in_apply'])) {
    return '待处理';
  }
  return '添加';
}

String _friendChannelId(Map<String, Object?> item) {
  final profile = _friendProfile(item);
  final channelId = _value(item, [
    'channel_id',
    'uid',
    'im_uid',
  ], fallback: _value(profile, ['channel_id', 'uid', 'im_uid']));
  if (channelId.isNotEmpty) {
    return channelId;
  }
  final userId = _friendUserId(item);
  if (userId.isEmpty) {
    return '';
  }
  return _uidFromUserId(userId);
}

String _groupTitle(Map<String, Object?> item) {
  return _value(item, ['name', 'group_name', 'title'], fallback: '群聊');
}

String _groupIdFromItem(Map<String, Object?> item) {
  return _value(item, ['group_id', 'id']);
}

String _groupChannelId(Map<String, Object?> item) {
  return _value(item, ['channel_id', 'uid'], fallback: _groupIdFromItem(item));
}

String _memberTitle(Map<String, Object?> item) {
  return _value(item, ['nickname', 'username', 'name'], fallback: '群成员');
}

String _memberUsername(Map<String, Object?> item) {
  return _value(item, ['username'], fallback: _memberRoleText(item));
}

String _memberUserId(Map<String, Object?> item) {
  final value = _value(item, ['user_id', 'userid', 'member_id', 'id']);
  if (value.isNotEmpty) {
    return value;
  }
  return _privateReceiverIdFromChannel(_value(item, ['uid']));
}

String _memberSubtitle(Map<String, Object?> item) {
  final username = _memberUsername(item);
  final parts = [
    if (username.isNotEmpty && username != _memberRoleText(item))
      '用户名 $username',
    _memberRoleText(item),
  ];
  final muted = _boolValue(item['muted']);
  if (muted) {
    final permanent = _boolValue(item['mute_permanent']);
    final expire = _value(item, ['mute_expire_time']);
    parts.add(permanent ? '永久禁言' : '禁言至 $expire');
  }
  return parts.where((part) => part.isNotEmpty).join(' · ');
}

String _memberRoleText(Map<String, Object?> item) {
  final role = _intValue(item, ['role']);
  return switch (role) {
    1 => '群主',
    2 => '管理员',
    _ => '成员',
  };
}

String _requestTitle(Map<String, Object?> item, String type) {
  if (type == 'in') {
    return _value(item, [
      'from_nickname',
      'from_username',
      'nickname',
      'username',
      'from_user_id',
    ], fallback: '申请人');
  }
  return _value(item, [
    'to_nickname',
    'to_username',
    'nickname',
    'username',
    'to_user_id',
  ], fallback: '接收人');
}

String _requestStatus(Map<String, Object?> item) {
  final status = _value(item, ['status']);
  return switch (status) {
    '0' => '待处理',
    '1' => '已通过',
    '2' => '已拒绝',
    '3' => '已过期',
    _ => status.isEmpty ? '待处理' : status,
  };
}

bool _requestPending(Map<String, Object?> item) {
  final status = _value(item, ['status']);
  return status.isEmpty || status == '0' || status == 'pending';
}
