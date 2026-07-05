part of 'package:bim/src/features/home/home_page.dart';

String _formatTime(int millis) {
  if (millis <= 0) {
    return '暂无';
  }
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _gatewayStreamAddress(ChatSession? chat) {
  if (chat == null) {
    return '';
  }
  final streamAddr = chat.stream?.httpsStreamAddr ?? '';
  return streamAddr.isNotEmpty ? streamAddr : chat.route.httpsStreamAddr;
}

bool _shouldShowTimeDivider(List<Map<String, Object?>> messages, int index) {
  if (index == 0) {
    return true;
  }
  final current = _messageDateTime(messages[index]);
  final previous = _messageDateTime(messages[index - 1]);
  if (current == null || previous == null) {
    return false;
  }
  return current.difference(previous).inMinutes.abs() >= 5;
}

String _messageTimeLabel(Map<String, Object?> item) {
  final time = _messageDateTime(item);
  if (time == null) {
    return '';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay =
      time.year == now.year && time.month == now.month && time.day == now.day;
  final clock = '${two(time.hour)}:${two(time.minute)}';
  if (sameDay) {
    return clock;
  }
  return '${two(time.month)}-${two(time.day)} $clock';
}

String _messageBubbleTime(Map<String, Object?> item) {
  final label = _messageTimeLabel(item);
  if (label.length >= 5) {
    return label.substring(label.length - 5);
  }
  return label;
}

DateTime? _messageDateTime(Map<String, Object?> item) {
  final raw = _value(item, ['timestamp', 'create_time', 'msg_time']);
  if (raw.isEmpty) {
    return null;
  }
  final numeric = int.tryParse(raw);
  if (numeric != null) {
    final millis = numeric > 100000000000 ? numeric : numeric * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}

String _messageSenderName(Map<String, Object?> item) {
  final fromUser = _asObjectMap(item['from_user']);
  return _value(
    fromUser,
    ['nickname', 'username', 'name'],
    fallback: _value(item, ['from_nickname', 'from_username'], fallback: '成员'),
  );
}

String _messageSenderAvatarUrl(Map<String, Object?> item) {
  final fromUser = _asObjectMap(item['from_user']);
  return _avatarUrlFromMap(fromUser, fallback: _avatarUrlFromMap(item));
}

String _messageStatus(Map<String, Object?> item) {
  final status = _value(item, ['status']).toLowerCase();
  if (_hasReadReceiptState(item)) {
    return 'read';
  }
  return switch (status) {
    'read' || 'readed' || 'seen' => 'read',
    'queued' => 'queued',
    'sending' => 'sending',
    'failed' => 'failed',
    'sent' || 'success' || 'succeeded' || 'delivered' => 'sent',
    _ => status,
  };
}

bool _hasReadReceiptState(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final receipt = _asObjectMap(item['receipt']);
  final payloadReceipt = _asObjectMap(payload['receipt']);
  for (final source in [item, payload, receipt, payloadReceipt]) {
    if (_boolValue(source['is_read']) ||
        _boolValue(source['read']) ||
        _boolValue(source['readed']) ||
        _boolValue(source['has_read'])) {
      return true;
    }
    final status = _value(source, [
      'receipt_status',
      'read_status',
      'status',
    ]).toLowerCase();
    if (status == 'read' || status == 'readed' || status == 'seen') {
      return true;
    }
    if (_intValue(source, ['read_at']) > 0 ||
        _intValue(source, ['read_time']) > 0 ||
        _intValue(source, ['read_count']) > 0 ||
        _intValue(source, ['reader_count']) > 0) {
      return true;
    }
  }
  return false;
}

String _messageContentType(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  return _value(item, [
    'content_type',
  ], fallback: _value(payload, ['content_type']));
}

String _messageContentText(
  Map<String, Object?> item,
  Map<String, Object?> payload,
) {
  final content = _value(item, ['content']);
  if (content.isNotEmpty && content != '[消息]') {
    return content;
  }
  return _value(payload, ['content', 'text', 'remark'], fallback: content);
}

bool _isSystemNoticeMessage(Map<String, Object?> item) {
  final contentType = _messageContentType(item);
  return contentType == ChatContentTypes.redPacketReceived ||
      contentType == ChatContentTypes.transferReceived ||
      _boolValue(item['is_system']) ||
      _boolValue(_asObjectMap(item['payload'])['is_system']);
}

String _systemNoticeText(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final content = _messageContentText(item, payload);
  if (content.isNotEmpty &&
      content != '[消息]' &&
      content != '[领取红包]' &&
      content != '[已收款]') {
    return content;
  }
  final contentType = _messageContentType(item);
  if (contentType == ChatContentTypes.redPacketReceived) {
    return _paymentNoticeText(
      payload,
      action: ChatContentTypes.redPacketReceived,
    );
  }
  if (contentType == ChatContentTypes.transferReceived) {
    return _paymentNoticeText(
      payload,
      action: ChatContentTypes.transferReceived,
    );
  }
  return content.isEmpty ? '[系统消息]' : content;
}

String _paymentNoticeText(
  Map<String, Object?> payload, {
  required String action,
}) {
  final actorIsMe = _boolValue(payload['actor_is_me']);
  final senderIsMe = _boolValue(payload['sender_is_me']);
  final actorName = _value(payload, ['actor_name'], fallback: '对方');
  final senderName = _value(payload, ['sender_name'], fallback: '对方');
  if (action == ChatContentTypes.redPacketReceived) {
    if (actorIsMe) {
      return '你领取了$senderName的红包';
    }
    if (senderIsMe) {
      return '$actorName领取了你的红包';
    }
    return '$actorName领取了$senderName的红包';
  }
  if (action == ChatContentTypes.transferReceived) {
    if (actorIsMe) {
      return '你已收取$senderName的转账';
    }
    if (senderIsMe) {
      return '$actorName已收取你的转账';
    }
    return '$actorName已收取$senderName的转账';
  }
  return actorIsMe ? '你完成了操作' : '$actorName完成了操作';
}

String _durationLabel(Map<String, Object?> payload) {
  final seconds = _value(payload, ['duration']);
  if (seconds.isEmpty) {
    return '';
  }
  return '$seconds 秒';
}

String _paymentAmount(Map<String, Object?> payload) {
  final redPacket = _asObjectMap(payload['red_packet']);
  final transfer = _asObjectMap(payload['transfer']);
  final source = redPacket.isNotEmpty
      ? redPacket
      : transfer.isNotEmpty
      ? transfer
      : payload;
  final money = _value(source, ['money', 'amount']);
  final asset = _value(source, ['asset_type']);
  if (money.isEmpty) {
    return '';
  }
  if (asset.isEmpty || asset == 'money' || asset == '金币') {
    final value = double.tryParse(money);
    return value == null ? '¥$money' : '¥${value.toStringAsFixed(2)}';
  }
  return '$money $asset';
}

String _redPacketRemark(Map<String, Object?> payload, {String fallback = ''}) {
  final redPacket = _asObjectMap(payload['red_packet']);
  for (final source in [redPacket, payload]) {
    final value = _value(source, [
      'remark',
      'blessing',
      'bless',
      'wish',
      'greeting',
      'greetings',
      'message',
      'content',
      'text',
      'note',
    ]);
    if (_isValidRedPacketRemark(value)) {
      return value;
    }
  }
  return _isValidRedPacketRemark(fallback) ? fallback.trim() : '';
}

String _redPacketRawId(Map<String, Object?> payload) {
  return _nestedValue(payload, [
    'red_packet.red_packet_id',
    'red_packet.packet_id',
    'red_packet.id',
    'red_packet_id',
    'packet_id',
  ]);
}

String _redPacketReceiveId(Map<String, Object?> payload) {
  final raw = _redPacketRawId(payload);
  final parsed = int.tryParse(raw);
  return parsed != null && parsed > 0 ? parsed.toString() : '';
}

String _redPacketUnavailableText(Map<String, Object?> payload) {
  final redPacket = _asObjectMap(payload['red_packet']);
  if (_boolValue(redPacket['received_by_me']) ||
      _boolValue(payload['received_by_me'])) {
    return '红包已领取';
  }
  final status = _value(redPacket, [
    'status',
  ], fallback: _value(payload, ['status']));
  if (status.isNotEmpty && status != '0') {
    return '红包已领取或已失效';
  }
  final quantity = _intValue(redPacket, ['quantity']);
  final receiveCount = _intValue(redPacket, ['receive_count']);
  final remaining = _intValue(redPacket, ['remaining_amount']);
  if (quantity > 0 && receiveCount >= quantity) {
    return '红包已领取完';
  }
  if (quantity > 0 && remaining == 0 && receiveCount > 0) {
    return '红包已领取完';
  }
  return '';
}

String _redPacketStatusText(
  Map<String, Object?> payload, {
  required bool receiving,
}) {
  if (receiving) {
    return '领取中';
  }
  final unavailable = _redPacketUnavailableText(payload);
  if (unavailable.isNotEmpty) {
    return unavailable;
  }
  if (_redPacketReceiveId(payload).isEmpty) {
    return '发送确认中';
  }
  final redPacket = _asObjectMap(payload['red_packet']);
  final quantity = _intValue(redPacket, ['quantity']);
  final receiveCount = _intValue(redPacket, ['receive_count']);
  if (quantity > 1 && receiveCount > 0) {
    return '$receiveCount/$quantity 已领取';
  }
  return '点击领取';
}

String _transferRawId(Map<String, Object?> payload) {
  return _nestedValue(payload, [
    'transfer.transfer_id',
    'transfer.id',
    'transfer_id',
  ]);
}

String _transferReceiveId(Map<String, Object?> payload) {
  final raw = _transferRawId(payload);
  final parsed = int.tryParse(raw);
  return parsed != null && parsed > 0 ? parsed.toString() : '';
}

String _transferUnavailableText(Map<String, Object?> payload) {
  final transfer = _asObjectMap(payload['transfer']);
  if (_boolValue(transfer['received_by_me']) ||
      _boolValue(payload['received_by_me'])) {
    return '转账已收款';
  }
  final status = _value(transfer, [
    'status',
  ], fallback: _value(payload, ['status']));
  if (status == '1' || status == 'received' || status == '已收款') {
    return '转账已收款';
  }
  if (status == '2' || status == 'expired' || status == '已过期') {
    return '转账已过期';
  }
  return '';
}

bool _isValidRedPacketRemark(String value) {
  final text = value.trim();
  if (text.isEmpty ||
      text == '[红包]' ||
      text == '[消息]' ||
      text == '[red_packet]') {
    return false;
  }
  if (text.startsWith('{') || text.startsWith('[')) {
    return false;
  }
  final moneyLike = RegExp(
    r'^[¥￥]?\d+(\.\d+)?\s*(money|金币|integral|积分)?$',
    caseSensitive: false,
  );
  return !moneyLike.hasMatch(text);
}

Color? _conversationPrefixColor(String text) {
  if (text.startsWith('[红包]')) {
    return const Color(0xffe64340);
  }
  if (text.startsWith('[转账]')) {
    return const Color(0xffff8a00);
  }
  return null;
}

double _uploadProgress(Map<String, Object?> payload) {
  final raw = _value(payload, ['upload_progress', 'progress']);
  final parsed = double.tryParse(raw);
  if (parsed == null) {
    return 0;
  }
  if (parsed > 1) {
    return (parsed / 100).clamp(0, 1).toDouble();
  }
  return parsed.clamp(0, 1).toDouble();
}

String _fileSizeLabel(Object? raw) {
  final bytes = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (bytes == null || bytes <= 0) {
    return raw?.toString() ?? '';
  }
  if (bytes < 1024) {
    return '${bytes}B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)}KB';
  }
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}
