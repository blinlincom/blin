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

String _messageReadStatusText(Map<String, Object?> item) {
  final channelType = _intValue(item, ['channel_type']);
  if (channelType != _groupChannelType) {
    return '';
  }
  final payload = _asObjectMap(item['payload']);
  final sources = [
    item,
    _asObjectMap(item['receipt']),
    payload,
    _asObjectMap(payload['receipt']),
    _asObjectMap(payload['read_receipt']),
  ];
  var readCount = 0;
  var total = 0;
  for (final source in sources) {
    readCount = max(
      readCount,
      _intValue(source, ['read_count', 'reader_count']),
    );
    total = max(
      total,
      _intValue(source, ['total', 'member_count', 'target_count']),
    );
  }
  if (readCount <= 0) {
    return '';
  }
  if (total > 0) {
    return '$readCount/$total 已读';
  }
  return '$readCount人已读';
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

bool _messageRendersAsMedia(String contentType, Map<String, Object?> payload) {
  if (contentType == ChatContentTypes.image ||
      contentType == ChatContentTypes.gif ||
      contentType == ChatContentTypes.sticker ||
      contentType == ChatContentTypes.video) {
    return true;
  }
  if (contentType != ChatContentTypes.emoji) {
    return false;
  }
  final media = _asObjectMap(payload['media']);
  final content = _value(payload, ['content', 'text', 'emoji_text']);
  if (content.isNotEmpty && content != '[表情]' && content != '[消息]') {
    return false;
  }
  final packId = _value(payload, [
    'pack_id',
  ], fallback: _value(media, ['pack_id']));
  final asset = _value(
    payload,
    ['emoji_asset', 'asset', 'emoji_path', 'sticker_asset'],
    fallback: _value(media, [
      'emoji_asset',
      'asset',
      'emoji_path',
      'sticker_asset',
    ]),
  );
  if (packId.isEmpty ||
      packId == 'default' ||
      asset.startsWith(_emojiAssetRoot)) {
    return false;
  }
  final local = _mediaLocalPath(contentType, payload, media);
  if (local.isNotEmpty) {
    return true;
  }
  final remote = _mediaRemoteUrl(contentType, payload, media);
  return remote.isNotEmpty;
}

Map<String, Object?> _messageQuote(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final quote = _quoteMapFromPayload(payload);
  if (quote.isNotEmpty) {
    return quote;
  }
  final replyQuote = _quoteMapFromReply(payload);
  if (replyQuote.isNotEmpty) {
    return replyQuote;
  }
  final clientMsgNo = _value(payload, [
    'quote_client_msg_no',
    'reply_client_msg_no',
  ]);
  if (clientMsgNo.isEmpty) {
    return const {};
  }
  return {
    'client_msg_no': clientMsgNo,
    if (_value(payload, ['quote_sender_name']).isNotEmpty)
      'sender_name': _value(payload, ['quote_sender_name']),
    if (_value(payload, ['quote_content_preview']).isNotEmpty)
      'content_preview': _value(payload, ['quote_content_preview']),
    if (_value(payload, ['quote_content_type']).isNotEmpty)
      'content_type': _value(payload, ['quote_content_type']),
    if (_value(payload, ['quote_content_preview']).isEmpty)
      'status': 'unavailable',
  };
}

Map<String, Object?> _quoteMapFromPayload(Map<String, Object?> payload) {
  final direct = _asObjectMap(payload['quote']);
  if (direct.isNotEmpty) {
    return direct;
  }
  final raw = _value(payload, ['quote', 'quote_json']);
  if (raw.isEmpty || !raw.trimLeft().startsWith('{')) {
    return const {};
  }
  try {
    final decoded = jsonDecode(raw);
    return _asObjectMap(decoded);
  } on Object {
    return const {};
  }
}

Map<String, Object?> _quoteMapFromReply(Map<String, Object?> payload) {
  final reply = _replyMapFromPayload(payload);
  if (reply.isEmpty) {
    return const {};
  }
  final replyPayload = _asObjectMap(reply['payload']);
  final clientMsgNo = _value(reply, [
    'client_msg_no',
    'quote_client_msg_no',
    'reply_client_msg_no',
  ], fallback: _value(replyPayload, ['client_msg_no']));
  final messageId = _value(reply, [
    'message_id',
    'message_idstr',
    'root_mid',
  ], fallback: _value(replyPayload, ['message_id', 'message_idstr']));
  var messageSeq = _intValue(reply, ['message_seq']);
  if (messageSeq <= 0) {
    messageSeq = _intValue(replyPayload, ['message_seq']);
  }
  final contentType = _value(reply, [
    'content_type',
  ], fallback: _value(replyPayload, ['content_type']));
  final preview = _value(reply, [
    'content_preview',
    'preview',
    'content',
    'text',
  ], fallback: _value(replyPayload, ['content', 'text', 'remark']));
  final senderName = _value(
    reply,
    ['sender_name', 'from_name', 'nickname', 'from_nickname'],
    fallback: _value(replyPayload, [
      'sender_nickname',
      'sender_username',
      'from_nickname',
      'from_username',
    ]),
  );
  final senderUid = _value(reply, [
    'sender_uid',
    'from_uid',
  ], fallback: _value(replyPayload, ['sender_uid', 'from_uid']));
  if (clientMsgNo.isEmpty &&
      messageId.isEmpty &&
      messageSeq <= 0 &&
      preview.isEmpty &&
      contentType.isEmpty) {
    return const {};
  }
  return {
    if (clientMsgNo.isNotEmpty) 'client_msg_no': clientMsgNo,
    if (messageId.isNotEmpty) 'message_id': messageId,
    if (messageSeq > 0) 'message_seq': messageSeq,
    if (_value(replyPayload, ['channel_id']).isNotEmpty)
      'channel_id': _value(replyPayload, ['channel_id']),
    if (_intValue(replyPayload, ['channel_type']) > 0)
      'channel_type': _intValue(replyPayload, ['channel_type']),
    if (senderUid.isNotEmpty) 'sender_uid': senderUid,
    if (senderName.isNotEmpty) 'sender_name': senderName,
    if (contentType.isNotEmpty) 'content_type': contentType,
    'content_preview': preview.isNotEmpty
        ? preview
        : _quoteContentTypeText(contentType),
    'status': 'normal',
  };
}

Map<String, Object?> _replyMapFromPayload(Map<String, Object?> payload) {
  final direct = _asObjectMap(payload['reply']);
  if (direct.isNotEmpty) {
    return direct;
  }
  final raw = _value(payload, ['reply']);
  if (raw.isEmpty || !raw.trimLeft().startsWith('{')) {
    return const {};
  }
  try {
    final decoded = jsonDecode(raw);
    return _asObjectMap(decoded);
  } on Object {
    return const {};
  }
}

bool _canQuoteMessage(Map<String, Object?> item) {
  if (item.isEmpty || _isSystemNoticeMessage(item)) {
    return false;
  }
  if (_value(item, ['client_msg_no']).isEmpty) {
    return false;
  }
  final payload = _asObjectMap(item['payload']);
  if (_boolValue(payload['burn_after_read']) ||
      _asObjectMap(payload['burn_after_read']).isNotEmpty) {
    return false;
  }
  final contentType = _messageContentType(item);
  return switch (contentType) {
    ChatContentTypes.text ||
    ChatContentTypes.image ||
    ChatContentTypes.emoji ||
    ChatContentTypes.gif ||
    ChatContentTypes.sticker ||
    ChatContentTypes.voice ||
    ChatContentTypes.video ||
    ChatContentTypes.file ||
    ChatContentTypes.contactCard => true,
    _ => false,
  };
}

Map<String, Object?> _quoteSnapshotFromMessage(Map<String, Object?> item) {
  if (!_canQuoteMessage(item)) {
    return const {};
  }
  final payload = _asObjectMap(item['payload']);
  final contentType = _messageContentType(item);
  final preview = _quotePreviewForMessage(item, payload, contentType);
  return {
    'client_msg_no': _value(item, ['client_msg_no']),
    if (_intValue(item, ['message_seq']) > 0)
      'message_seq': _intValue(item, ['message_seq']),
    if (_value(item, ['channel_id']).isNotEmpty)
      'channel_id': _value(item, ['channel_id']),
    if (_intValue(item, ['channel_type']) > 0)
      'channel_type': _intValue(item, ['channel_type']),
    if (_value(item, ['from_uid']).isNotEmpty)
      'sender_uid': _value(item, ['from_uid']),
    'sender_name': _boolValue(item['is_me']) ? '我' : _messageSenderName(item),
    'content_type': contentType,
    'content_preview': preview,
    'status': 'normal',
  };
}

String _quoteSenderName(Map<String, Object?> quote) {
  final payload = _asObjectMap(quote['payload']);
  return _value(
    quote,
    ['sender_name', 'from_name', 'nickname', 'from_nickname'],
    fallback: _value(payload, [
      'sender_nickname',
      'sender_username',
      'from_nickname',
      'from_username',
    ]),
  );
}

String _quotePreviewText(Map<String, Object?> quote) {
  final status = _value(quote, ['status']).toLowerCase();
  if (status == 'recalled' || status == 'recall') {
    return '原消息已撤回';
  }
  if (status == 'burned' || status == 'burn_after_read') {
    return '阅后即焚消息';
  }
  if (status == 'unavailable') {
    return '原消息不可查看';
  }
  final preview = _value(quote, [
    'content_preview',
    'preview',
    'content',
    'text',
  ]);
  if (preview.isNotEmpty && preview != '[消息]') {
    return preview;
  }
  final payload = _asObjectMap(quote['payload']);
  final payloadPreview = _value(payload, ['content', 'text', 'remark']);
  if (payloadPreview.isNotEmpty && payloadPreview != '[消息]') {
    return payloadPreview;
  }
  return _quoteContentTypeText(
    _value(quote, [
      'content_type',
    ], fallback: _value(payload, ['content_type'])),
  );
}

String _quotePreviewForMessage(
  Map<String, Object?> item,
  Map<String, Object?> payload,
  String contentType,
) {
  final content = _messageContentText(item, payload).trim();
  if (content.isNotEmpty && content != '[消息]') {
    return content.length > 80 ? '${content.substring(0, 80)}...' : content;
  }
  return _quoteContentTypeText(contentType);
}

String _quoteContentTypeText(String contentType) {
  return switch (contentType) {
    ChatContentTypes.image => '[图片]',
    ChatContentTypes.emoji => '[表情]',
    ChatContentTypes.gif => '[GIF]',
    ChatContentTypes.sticker => '[贴纸]',
    ChatContentTypes.voice => '[语音]',
    ChatContentTypes.video => '[视频]',
    ChatContentTypes.file => '[文件]',
    ChatContentTypes.contactCard => '[名片]',
    ChatContentTypes.call => '[通话]',
    ChatContentTypes.walletNotice => '[钱包通知]',
    _ => '[消息]',
  };
}

bool _isSystemNoticeMessage(Map<String, Object?> item) {
  final contentType = _messageContentType(item);
  if (contentType == ChatContentTypes.call ||
      contentType == ChatContentTypes.walletNotice) {
    return false;
  }
  final payload = _asObjectMap(item['payload']);
  return contentType == ChatContentTypes.redPacketReceived ||
      contentType == ChatContentTypes.transferReceived ||
      contentType == 'cmd' ||
      _boolValue(item['is_system']) ||
      _boolValue(item['system_message']) ||
      _boolValue(payload['is_system']) ||
      _boolValue(payload['system_message']);
}

String _systemNoticeText(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final contentType = _messageContentType(item);
  if (contentType == ChatContentTypes.call) {
    return _callNoticeText(payload);
  }
  final content = _messageContentText(item, payload);
  if (content.isNotEmpty &&
      content != '[消息]' &&
      content != '[领取红包]' &&
      content != '已领取红包' &&
      content != '已收款' &&
      content != '[已收款]') {
    return content;
  }
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
  if (contentType == 'cmd') {
    final notice = _value(payload, ['notice', 'summary', 'text', 'content']);
    if (notice.isNotEmpty && notice != '[消息]') {
      return notice;
    }
  }
  return content.isEmpty ? '[系统消息]' : content;
}

String _callNoticeText(Map<String, Object?> payload) {
  final meta = _callMessageUi(payload);
  return meta.statusText.isEmpty
      ? meta.title
      : '${meta.title} ${meta.statusText}';
}

String _callConversationText(Map<String, Object?> payload, String content) {
  final meta = _callMessageUi(payload, content: content);
  return meta.statusText.isEmpty
      ? '[${meta.title}]'
      : '[${meta.title}] ${meta.statusText}';
}

String _callDurationLabel(int seconds) {
  final normalized = max(0, seconds);
  final hours = normalized ~/ 3600;
  final minutes = (normalized % 3600) ~/ 60;
  final remain = normalized % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${two(minutes)}:${two(remain)}';
  }
  return '${two(minutes)}:${two(remain)}';
}

class _CallMessageUi {
  const _CallMessageUi({
    required this.mediaType,
    required this.callType,
    required this.statusText,
  });

  final String mediaType;
  final String callType;
  final String statusText;

  bool get isVideo => mediaType == 'video';
  bool get isGroup => callType == 'group';
  String get mediaLabel => isVideo ? '视频通话' : '语音通话';
  String get title => isGroup ? '群$mediaLabel' : mediaLabel;
}

_CallMessageUi _callMessageUi(
  Map<String, Object?> payload, {
  String content = '',
}) {
  final call = _asObjectMap(payload['call']);
  final direct = _callDirectText(payload, content);
  final mediaType = _callMediaType(payload, call, direct);
  final callType = _callType(payload, call, direct);
  final duration = max(
    _intValue(call, ['duration', 'duration_seconds', 'seconds']),
    _intValue(payload, ['duration', 'duration_seconds', 'seconds']),
  );
  final status = _callStatusCategory(payload, call, direct);
  final statusText = switch (status) {
    'canceled' => '已取消',
    'rejected' => '已拒绝',
    'missed' => '未接听',
    'failed' => '通话异常结束',
    _ => _callDurationStatusText(duration, direct),
  };
  return _CallMessageUi(
    mediaType: mediaType,
    callType: callType,
    statusText: statusText,
  );
}

String _callDirectText(Map<String, Object?> payload, String content) {
  final raw = content.trim().isNotEmpty
      ? content.trim()
      : _value(payload, ['content', 'text']).trim();
  return raw == '[消息]' ? '' : raw;
}

String _callMediaType(
  Map<String, Object?> payload,
  Map<String, Object?> call,
  String direct,
) {
  final raw = _value(call, [
    'media_type',
    'media',
  ], fallback: _value(payload, ['media_type', 'media'])).toLowerCase();
  if (raw == 'video' || raw == '视频') {
    return 'video';
  }
  if (direct.contains('视频')) {
    return 'video';
  }
  return 'audio';
}

String _callType(
  Map<String, Object?> payload,
  Map<String, Object?> call,
  String direct,
) {
  final raw = _value(call, [
    'call_type',
  ], fallback: _value(payload, ['call_type'])).toLowerCase();
  if (raw == 'group' || raw == 'meeting' || raw == 'private') {
    return raw;
  }
  return direct.contains('群') ? 'group' : 'private';
}

String _callStatusCategory(
  Map<String, Object?> payload,
  Map<String, Object?> call,
  String direct,
) {
  final text = [
    _value(call, [
      'status',
      'state',
      'event',
    ], fallback: _value(payload, ['call_status', 'status', 'state', 'event'])),
    _value(call, [
      'status_text',
      'reason',
    ], fallback: _value(payload, ['status_text', 'reason'])),
    direct,
  ].join(' ').toLowerCase();
  if (text.contains('cancel') || text.contains('取消')) {
    return 'canceled';
  }
  if (text.contains('reject') || text.contains('拒绝')) {
    return 'rejected';
  }
  if (text.contains('miss') ||
      text.contains('timeout') ||
      text.contains('no_answer') ||
      text.contains('unanswered') ||
      text.contains('未接')) {
    return 'missed';
  }
  if (text.contains('fail') || text.contains('error') || text.contains('异常')) {
    return 'failed';
  }
  return '';
}

String _callDurationStatusText(int duration, String direct) {
  if (duration > 0) {
    return '通话时长 ${_callDurationLabel(duration)}';
  }
  final directDuration = RegExp(
    r'(?:(?:\d{1,2}:)?\d{1,2}:\d{2})',
  ).firstMatch(direct)?.group(0);
  if (directDuration != null && directDuration != '00:00') {
    return '通话时长 $directDuration';
  }
  final stripped = direct
      .replaceFirst(RegExp(r'^群?语音通话\s*'), '')
      .replaceFirst(RegExp(r'^群?视频通话\s*'), '')
      .trim();
  if (stripped.isNotEmpty && stripped != direct) {
    return stripped == '00:00' ? '' : stripped;
  }
  return '';
}

List<String> _callParticipantUserIds(
  Map<String, Object?> payload, {
  String currentUserId = '',
}) {
  final ids = <String>{};
  final call = _asObjectMap(payload['call']);

  void addId(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return;
    }
    final parts = _idsFromText(text).isEmpty ? [text] : _idsFromText(text);
    for (final part in parts) {
      final normalized = _privateReceiverIdFromChannel(part);
      if (normalized.isNotEmpty && normalized != currentUserId) {
        ids.add(normalized);
      }
    }
  }

  void collect(Object? value) {
    if (value is List) {
      for (final item in value) {
        collect(item);
      }
      return;
    }
    if (value is Map) {
      final map = value.map((key, value) => MapEntry(key.toString(), value));
      for (final key in [
        'user_id',
        'uid',
        'im_uid',
        'member_uid',
        'receiver_id',
        'id',
      ]) {
        addId(map[key]);
      }
      collect(map['user']);
      collect(map['member']);
      collect(map['profile']);
      return;
    }
    addId(value);
  }

  for (final source in [call, payload]) {
    collect(source['participants']);
    collect(source['invite_user_ids']);
    collect(source['invitee_ids']);
    collect(source['user_ids']);
    collect(source['members']);
  }
  return ids.toList(growable: false);
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
    if (actorIsMe && senderIsMe) {
      return '你领取了自己的红包';
    }
    if (actorIsMe) {
      return '你领取了$senderName的红包';
    }
    if (senderIsMe) {
      return '$actorName领取了你的红包';
    }
    if (actorName.isNotEmpty && actorName == senderName) {
      return '$actorName领取了自己的红包';
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

Map<String, Object?> _walletNoticePayload(Map<String, Object?> payload) {
  final notice = _asObjectMap(payload['wallet_notice']);
  return notice.isNotEmpty ? notice : payload;
}

String _walletNoticeScene(Map<String, Object?> payload) {
  return _value(_walletNoticePayload(payload), ['scene', 'type']);
}

String _walletNoticeTitle(Map<String, Object?> payload) {
  final notice = _walletNoticePayload(payload);
  final direct = _value(notice, ['title']);
  if (direct.isNotEmpty) {
    return direct;
  }
  final scene = _walletNoticeScene(payload);
  if (scene == 'pay_code_confirm_required') {
    return '待确认付款';
  }
  if (scene == 'scan_collect_success') {
    return '收款到账';
  }
  if (scene == 'scan_pay_success') {
    return '扫码付款成功';
  }
  return '钱包通知';
}

bool _walletNoticeIsRisk(Map<String, Object?> payload) {
  final scene = _walletNoticeScene(payload);
  final title = _walletNoticeTitle(payload);
  return scene == 'wallet_lock' ||
      scene == 'wallet_unlock' ||
      scene == 'wallet_freeze' ||
      scene == 'wallet_unfreeze' ||
      title.contains('钱包') ||
      title.contains('冻结') ||
      title.contains('解冻');
}

String _walletNoticeSummary(Map<String, Object?> payload) {
  final notice = _walletNoticePayload(payload);
  final summary = _value(notice, ['summary', 'content', 'remark']);
  if (summary.isNotEmpty) {
    return summary;
  }
  final amount = _value(notice, ['amount_label', 'amount']);
  if (amount.isEmpty) {
    return '交易成功';
  }
  return '${_walletNoticeTitle(payload)} $amount';
}

String _walletNoticeConversationText(Map<String, Object?> payload) {
  final title = _walletNoticeTitle(payload);
  final summary = _walletNoticeSummary(payload);
  if (_walletNoticeIsRisk(payload)) {
    return '[$title]$summary';
  }
  final prefix = title.contains('收款') ? '[收款]' : '[付款]';
  return '$prefix$summary';
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

bool _canReceiveOwnRedPacket(Map<String, Object?> payload, bool isGroup) {
  if (!isGroup) {
    return false;
  }
  final redPacket = _asObjectMap(payload['red_packet']);
  final packetType = _value(redPacket, ['packet_type']).toLowerCase();
  final receiverId = _intValue(redPacket, ['receiver_id']);
  return receiverId == 0 && (packetType == 'ordinary' || packetType == 'luck');
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
  final remaining = _moneyValue(redPacket, ['remaining_amount']);
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

String _transferStatusText(Map<String, Object?> payload) {
  final unavailable = _transferUnavailableText(payload);
  if (unavailable.isNotEmpty) {
    return unavailable;
  }
  if (_transferReceiveId(payload).isEmpty) {
    return '发送确认中';
  }
  return '点击收款';
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
    return BimColors.redPacket;
  }
  if (text.startsWith('[转账]')) {
    return BimColors.transfer;
  }
  if (text.startsWith('[收款]')) {
    return BimColors.primary;
  }
  if (text.startsWith('[付款]')) {
    return BimColors.transfer;
  }
  if (text.startsWith('[表情]') ||
      text.startsWith('[GIF]') ||
      text.startsWith('[贴纸]')) {
    return _primaryColor;
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

double _moneyValue(Map<String, Object?> source, List<String> keys) {
  final raw = _value(source, keys);
  if (raw.isEmpty) {
    return 0;
  }
  return double.tryParse(raw) ?? 0;
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
