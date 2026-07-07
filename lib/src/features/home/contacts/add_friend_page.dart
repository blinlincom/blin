part of 'package:bim/src/features/home/home_page.dart';

class AddFriendPage extends StatefulWidget {
  const AddFriendPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _friendId = TextEditingController();
  final _remark = TextEditingController();
  bool _loading = false;
  String _message = '';
  String _error = '';

  @override
  void dispose() {
    _friendId.dispose();
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('添加好友')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ColoredBox(
              color: _surfaceColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  children: [
                    TextField(
                      controller: _friendId,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        hintText: '只能通过用户名添加好友',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _remark,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '申请备注',
                        hintText: '告诉对方你是谁',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const _GroupGap(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  FilledButton.icon(
                    onPressed: _loading ? null : _apply,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('发送申请'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _checkStatus,
                    icon: const Icon(Icons.manage_search),
                    label: const Text('查看好友状态'),
                  ),
                ],
              ),
            ),
            if (_loading) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _checkStatus() async {
    final id = _friendId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '用户名不能为空');
      return;
    }
    await _run(() async {
      final result = await widget.controller.friendStatus(id);
      _message = _friendStatusText(result);
    });
  }

  Future<void> _apply() async {
    final id = _friendId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '用户名不能为空');
      return;
    }
    await _run(() async {
      final result = await widget.controller.applyFriend(
        friendId: id,
        remark: _remark.text.trim(),
      );
      _message = _friendlyResult(result, successText: '好友申请已发送');
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      await task();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}
