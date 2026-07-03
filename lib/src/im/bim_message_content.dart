import 'package:wukongimfluttersdk/model/wk_message_content.dart';

import 'im_message_types.dart';

class BimMessageContent extends WKMessageContent {
  BimMessageContent(int type, {Map<String, dynamic>? payload}) {
    contentType = type;
    _payload = payload ?? <String, dynamic>{};
    content = _readContent(_payload);
  }

  Map<String, dynamic> _payload = <String, dynamic>{};

  Map<String, dynamic> get payload => Map.unmodifiable(_payload);

  @override
  Map<String, dynamic> encodeJson() {
    final json = Map<String, dynamic>.from(_payload);
    json['type'] = contentType;
    if (content.isNotEmpty) {
      json['content'] = content;
    }
    return json;
  }

  @override
  WKMessageContent decodeJson(Map<String, dynamic> json) {
    _payload = Map<String, dynamic>.from(json);
    content = _readContent(_payload);
    return this;
  }

  @override
  String displayText() {
    final display = _displayByType();
    if (display.isNotEmpty) {
      return display;
    }
    return content.isEmpty ? '[消息]' : content;
  }

  @override
  String searchableWord() => displayText();

  String _displayByType() {
    switch (contentType) {
      case ImMessageTypes.voice:
        return '[语音]';
      case ImMessageTypes.video:
        return '[视频]';
      case ImMessageTypes.file:
        return _fileDisplay();
      case ImMessageTypes.transfer:
        return '[转账]';
      case ImMessageTypes.redPacket:
        return '[红包]';
      case ImMessageTypes.redPacketReceived:
        return '[红包已领取]';
      case ImMessageTypes.transferReceived:
        return '[转账已收款]';
      case ImMessageTypes.emoji:
        return _emojiDisplay();
      case ImMessageTypes.gif:
        return '[GIF]';
      case ImMessageTypes.sticker:
        return '[贴纸]';
      case ImMessageTypes.contactCard:
        return '[名片]';
      case ImMessageTypes.recall:
        return '消息已撤回';
    }
    return '';
  }

  String _fileDisplay() {
    final name = _firstNonEmpty(['file_name', 'name']);
    if (name.isNotEmpty) {
      return '[文件]$name';
    }
    final media = _payload['media'];
    if (media is Map && media['name'] != null) {
      return '[文件]${media['name']}';
    }
    return '[文件]';
  }

  String _emojiDisplay() {
    final code = _firstNonEmpty(['emoji_code', 'content']);
    return code.isEmpty ? '[表情]' : code;
  }

  String _readContent(Map<String, dynamic> json) {
    final value = json['content'];
    if (value != null && value.toString().isNotEmpty) {
      return value.toString();
    }
    return _firstNonEmpty([
      'text',
      'remark',
      'emoji_code',
      'file_name',
      'name',
    ]);
  }

  String _firstNonEmpty(List<String> keys) {
    for (final key in keys) {
      final value = _payload[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    return '';
  }
}
