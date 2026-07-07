part of 'package:bim/src/features/home/home_page.dart';

Future<Map<String, String>?> _openInput(
  BuildContext context, {
  required String title,
  required List<ActionInputField> fields,
}) {
  return Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(
      builder: (_) => ActionInputPage(title: title, fields: fields),
    ),
  );
}

Future<void> _push(BuildContext context, Widget page) async {
  if (page is LiveKitCallPage) {
    await Navigator.of(context).push(_callPageRoute(page));
    return;
  }
  if (page is ChatPage) {
    await Navigator.of(context).push(_chatPageRoute(page));
    return;
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}

PageRoute<void> _chatPageRoute(ChatPage page) {
  return PageRouteBuilder<void>(
    opaque: true,
    pageBuilder: (_, __, ___) =>
        const ColoredBox(color: _chatPageColor, child: SizedBox.expand()),
    transitionsBuilder: (_, animation, __, ___) {
      return ColoredBox(
        color: _chatPageColor,
        child: FadeTransition(opacity: animation, child: page),
      );
    },
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: const Duration(milliseconds: 140),
  );
}

PageRoute<int> _callPageRoute(LiveKitCallPage page) {
  return PageRouteBuilder<int>(
    opaque: false,
    barrierColor: Colors.transparent,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

Future<bool> _confirmDanger(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmText,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return result == true;
}

void _openPrivateChat(
  BuildContext context,
  SessionController controller,
  Map<String, Object?> item,
) {
  final channelId = _friendChannelId(item);
  if (channelId.isEmpty) {
    return;
  }
  Navigator.of(context)
      .push(
        _chatPageRoute(
          ChatPage(
            controller: controller,
            title: _friendTitle(item),
            channelId: channelId,
            groupId: '',
            channelType: _privateChannelType,
          ),
        ),
      )
      .then(
        (_) => _markConversationReadAfterPop(
          controller,
          channelId,
          _privateChannelType,
        ),
      );
}

void _openGroupChat(
  BuildContext context,
  SessionController controller,
  Map<String, Object?> item,
) {
  final groupId = _groupIdFromItem(item);
  final channelId = _groupChannelId(item);
  if (channelId.isEmpty) {
    return;
  }
  Navigator.of(context)
      .push(
        _chatPageRoute(
          ChatPage(
            controller: controller,
            title: _groupTitle(item),
            channelId: channelId,
            groupId: groupId,
            channelType: _groupChannelType,
          ),
        ),
      )
      .then(
        (_) => _markConversationReadAfterPop(
          controller,
          channelId,
          _groupChannelType,
        ),
      );
}

Future<void> _markConversationReadAfterPop(
  SessionController controller,
  String channelId,
  int channelType,
) async {
  try {
    await controller.markConversationRead(
      channelId: channelId,
      channelType: channelType,
    );
  } catch (error, stackTrace) {
    AppLogger.error(
      'ui',
      'mark conversation read after pop failed',
      error: error,
      stackTrace: stackTrace,
      data: {'channel_id': channelId, 'channel_type': channelType},
    );
  }
}
