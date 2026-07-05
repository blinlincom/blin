part of 'package:bim/src/features/home/home_page.dart';

String _avatarInitial(String label) {
  final text = label.trim();
  if (text.isEmpty) {
    return 'B';
  }
  return text.characters.first.toUpperCase();
}

String _friendlyResult(
  Map<String, Object?> result, {
  String successText = '操作成功',
}) {
  final message = _value(result, ['message', 'msg']);
  if (message.isNotEmpty) {
    return message;
  }
  final data = result['data'];
  if (data is Map) {
    final nested = _value(
      data.map((key, value) => MapEntry(key.toString(), value)),
      ['message', 'msg'],
    );
    if (nested.isNotEmpty) {
      return nested;
    }
  }
  return successText;
}

String _friendStatusText(Map<String, Object?> result) {
  final isFriend = _boolValue(result['is_friend']);
  final pendingOut = _boolValue(result['pending_out_apply']);
  final pendingIn = _boolValue(result['pending_in_apply']);
  final count = _intValue(result, ['non_friend_message_count']);
  final limit = _intValue(result, ['non_friend_message_limit']);
  if (isFriend) {
    return '你们已经是好友，可以正常聊天。';
  }
  if (pendingOut) {
    return '好友申请已发送，等待对方通过。';
  }
  if (pendingIn) {
    return '对方已申请添加你为好友，请到新的朋友里处理。';
  }
  final max = limit <= 0 ? 3 : limit;
  return '还不是好友，只能先发送文字消息，当前已发送 $count/$max 条。';
}

String _receiptText(Map<String, Object?> result, {required bool isGroup}) {
  final receipt = _asObjectMap(result['receipt']);
  final redPacket = _asObjectMap(result['red_packet']);
  final transfer = _asObjectMap(result['transfer']);
  final parts = <String>[];
  final readCount = _intValue(receipt, ['read_count']);
  final unreadCount = _intValue(receipt, ['unread_count']);
  final total = _intValue(receipt, ['total_receivers']);
  if (isGroup) {
    if (total > 0) {
      parts.add('$readCount/$total 人已读');
    } else {
      parts.add('$readCount 人已读');
    }
  } else {
    parts.add(readCount > 0 ? '对方已读' : '对方未读');
  }
  if (unreadCount > 0 && isGroup) {
    parts.add('$unreadCount 人未读');
  }
  if (redPacket.isNotEmpty) {
    final receiveCount = _intValue(redPacket, ['receive_count']);
    final quantity = _intValue(redPacket, ['quantity']);
    final status = _value(redPacket, ['status']);
    final progress = quantity > 0 ? '$receiveCount/$quantity' : '$receiveCount';
    parts.add('红包领取 $progress${status.isEmpty ? '' : ' · $status'}');
  }
  if (transfer.isNotEmpty) {
    final status = _value(transfer, ['status']);
    parts.add(status.isEmpty ? '转账待处理' : '转账$status');
  }
  return parts.join('\n');
}
