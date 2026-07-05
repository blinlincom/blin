part of 'package:bim/src/features/home/home_page.dart';

class PrivateChatActionsPage extends StatefulWidget {
  const PrivateChatActionsPage({
    required this.controller,
    required this.title,
    required this.receiverId,
    required this.channelId,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String receiverId;
  final String channelId;

  @override
  State<PrivateChatActionsPage> createState() => _PrivateChatActionsPageState();
}

class _PrivateChatActionsPageState extends State<PrivateChatActionsPage> {
  String _message = '';
  String _error = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          children: [
            _PlainListTile(
              icon: Icons.badge_outlined,
              title: '对方',
              subtitle: widget.title,
              trailing: '',
            ),
            _PlainListTile(
              icon: Icons.manage_search,
              title: '好友状态',
              subtitle: '查看是否已添加为好友',
              trailing: '',
              onTap: _friendStatus,
            ),
            _PlainListTile(
              icon: Icons.delete_outline,
              title: '清空聊天',
              subtitle: '只清空自己看到的单聊记录',
              trailing: '',
              onTap: _deleteConversation,
            ),
            _PlainListTile(
              icon: Icons.person_remove_outlined,
              title: '删除好友',
              subtitle: '删除后重新按非好友规则执行',
              trailing: '',
              onTap: _deleteFriend,
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _friendStatus() async {
    try {
      final result = await widget.controller.friendStatus(widget.receiverId);
      setState(() {
        _message = _friendStatusText(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteFriend() async {
    await _run(() => widget.controller.deleteFriend(widget.receiverId));
  }

  Future<void> _deleteConversation() async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空聊天记录',
      content: '将清空你自己看到的这个单聊记录和会话，不影响对方。',
      confirmText: '清空',
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => widget.controller.deletePrivateConversation(
        receiverId: widget.receiverId,
        channelId: widget.channelId,
      ),
    );
  }

  Future<void> _run(Future<Map<String, Object?>> Function() task) async {
    try {
      final result = await task();
      setState(() {
        _message = _friendlyResult(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}
