part of 'package:bim/src/features/home/home_page.dart';

String _sessionDisplayName(UserSession? session) {
  if (session == null) {
    return '';
  }
  if (session.nickname.isNotEmpty) {
    return session.nickname;
  }
  return session.username;
}

String _conversationTitle(Map<String, Object?> item) {
  if (_channelTypeFromConversation(item) == _groupChannelType) {
    return _value(item, ['name', 'group_name'], fallback: '群聊');
  }
  return _value(item, ['nickname', 'username', 'name'], fallback: '私聊');
}

String _conversationSubtitle(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final contentType = _value(item, [
    'content_type',
  ], fallback: _value(payload, ['content_type']));
  final content = _value(item, ['content']);
  if (contentType == ChatContentTypes.redPacket) {
    return _redPacketConversationText(payload, content);
  }
  if (contentType == ChatContentTypes.transfer) {
    return _transferConversationText(payload, content);
  }
  if (contentType == ChatContentTypes.call) {
    return _callConversationText(payload, content);
  }
  return content;
}

String _conversationTimeText(Map<String, Object?> item) {
  final time = _conversationDateTime(item);
  if (time == null) {
    return '';
  }
  final now = DateTime.now();
  final day = DateTime(time.year, time.month, time.day);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  String two(int value) => value.toString().padLeft(2, '0');

  if (day == today) {
    return '${two(time.hour)}:${two(time.minute)}';
  }
  if (day == yesterday) {
    return '昨天';
  }

  final weekStart = today.subtract(Duration(days: today.weekday - 1));
  if (day.isAfter(weekStart.subtract(const Duration(days: 1))) &&
      day.isBefore(today)) {
    return _weekdayText(time.weekday);
  }
  if (time.year == now.year) {
    return '${time.month}月${time.day}日';
  }
  return '${time.year}年${time.month}月${time.day}日';
}

DateTime? _conversationDateTime(Map<String, Object?> item) {
  final raw = _value(item, ['msg_time', 'timestamp', 'create_time']);
  if (raw.isEmpty) {
    return null;
  }
  return _parseUiTime(raw);
}

String _weekdayText(int weekday) {
  return switch (weekday) {
    DateTime.monday => '星期一',
    DateTime.tuesday => '星期二',
    DateTime.wednesday => '星期三',
    DateTime.thursday => '星期四',
    DateTime.friday => '星期五',
    DateTime.saturday => '星期六',
    DateTime.sunday => '星期日',
    _ => '',
  };
}

String _redPacketConversationText(
  Map<String, Object?> payload,
  String content,
) {
  final direct = content.trim();
  if (direct.startsWith('[红包]') && direct.length > '[红包]'.length) {
    return direct;
  }
  final remark = _redPacketRemark(payload, fallback: direct);
  return remark.isEmpty ? '[红包]' : '[红包]$remark';
}

String _transferConversationText(Map<String, Object?> payload, String content) {
  return '[转账]请收款';
}

String _conversationAvatarUrl(Map<String, Object?> item) {
  if (_channelTypeFromConversation(item) == _groupChannelType) {
    return _groupAvatarUrl(item);
  }
  return _avatarUrlFromMap(item);
}

String _conversationChannelId(Map<String, Object?> item, int channelType) {
  if (channelType == _privateChannelType) {
    final receiverId = _value(item, [
      'receiver_id',
      'peer_id',
      'friend_id',
      'user_id',
      'userid',
    ]);
    if (receiverId.isNotEmpty) {
      return _uidFromUserId(receiverId);
    }
  }
  final raw = _value(item, ['channel_id', 'uid']);
  if (channelType != _privateChannelType || raw.isEmpty) {
    return raw;
  }
  return _uidFromUserId(_privateReceiverIdFromChannel(raw));
}

int _channelTypeFromConversation(Map<String, Object?> item) {
  final value = _intValue(item, ['channel_type']);
  if (value > 0) {
    return value;
  }
  return item['conversation_type']?.toString() == 'group'
      ? _groupChannelType
      : _privateChannelType;
}
