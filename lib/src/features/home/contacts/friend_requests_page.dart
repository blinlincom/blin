part of 'package:bim/src/features/home/home_page.dart';

class FriendRequestsPage extends StatefulWidget {
  const FriendRequestsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage> {
  var _type = 'in';
  var _version = 0;
  String _error = '';
  String _message = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: _ButtonRow(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _type = 'in'),
                    child: Text(_type == 'in' ? '收到申请' : '收件箱'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _type = 'out'),
                    child: Text(_type == 'out' ? '发出申请' : '发件箱'),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: () => setState(() => _version++),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            Expanded(
              child: FutureBuilder<Map<String, Object?>>(
                key: ValueKey('$_type-$_version'),
                future: widget.controller.friendApplyList(type: _type),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(text: snapshot.error.toString());
                  }
                  final items = _listFromResult(snapshot.data ?? const {});
                  if (items.isEmpty) {
                    return const _EmptyState(text: '暂无申请');
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final applyId = _value(item, ['apply_id', 'id']);
                      final title = _requestTitle(item, _type);
                      final status = _requestStatus(item);
                      return _PlainListTile(
                        icon: Icons.person_outline,
                        title: title,
                        subtitle:
                            '${_value(item, ['remark', 'handle_msg'])} $status',
                        trailing: applyId,
                        onTap: _type == 'in' && _requestPending(item)
                            ? () => _handle(applyId, true)
                            : null,
                        onLongPress: _type == 'in' && _requestPending(item)
                            ? () => _handle(applyId, false)
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handle(String applyId, bool accept) async {
    if (applyId.isEmpty) {
      setState(() => _error = '申请信息为空');
      return;
    }
    try {
      final result = await widget.controller.handleFriendApply(
        applyId: applyId,
        accept: accept,
      );
      setState(() {
        _message = _friendlyResult(result, successText: accept ? '已同意' : '已拒绝');
        _error = '';
        _version++;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}
