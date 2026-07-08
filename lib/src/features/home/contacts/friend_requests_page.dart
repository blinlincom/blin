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
  String _handlingApplyId = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.markFriendApplicationsRead();
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('好友申请')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _SegmentButton(
                      label: '收到',
                      selected: _type == 'in',
                      onTap: () => setState(() => _type = 'in'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SegmentButton(
                      label: '发出',
                      selected: _type == 'out',
                      onTap: () => setState(() => _type = 'out'),
                    ),
                  ),
                  const SizedBox(width: 8),
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
              child: _FriendRequestList(
                key: ValueKey('$_type-$_version'),
                controller: widget.controller,
                type: _type,
                handlingApplyId: _handlingApplyId,
                onAccept: (applyId) => _handle(applyId, true),
                onReject: (applyId) => _handle(applyId, false),
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
    if (_handlingApplyId.isNotEmpty) {
      return;
    }
    setState(() {
      _handlingApplyId = applyId;
      _error = '';
    });
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
    } finally {
      if (mounted) {
        setState(() => _handlingApplyId = '');
      }
    }
  }
}

class _FriendRequestList extends StatefulWidget {
  const _FriendRequestList({
    required this.controller,
    required this.type,
    required this.handlingApplyId,
    required this.onAccept,
    required this.onReject,
    super.key,
  });

  final SessionController controller;
  final String type;
  final String handlingApplyId;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;

  @override
  State<_FriendRequestList> createState() => _FriendRequestListState();
}

class _FriendRequestListState extends State<_FriendRequestList> {
  late Future<Map<String, Object?>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.friendApplyList(type: widget.type);
  }

  @override
  void didUpdateWidget(_FriendRequestList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _future = widget.controller.friendApplyList(type: widget.type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cached = widget.controller.cachedFriendApplications(
      type: widget.type,
    );
    return FutureBuilder<Map<String, Object?>>(
      future: _future,
      builder: (context, snapshot) {
        final items =
            snapshot.connectionState == ConnectionState.done && snapshot.hasData
            ? _listFromResult(snapshot.data ?? const {})
            : cached;
        if (snapshot.connectionState != ConnectionState.done && items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && items.isEmpty) {
          return _ErrorState(text: snapshot.error.toString(), onRetry: _reload);
        }
        if (items.isEmpty) {
          return const _EmptyState(text: '暂无申请');
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final applyId = _value(item, ['apply_id', 'id']);
              final title = _requestTitle(item, widget.type);
              final status = _requestStatus(item);
              final busy = widget.handlingApplyId == applyId;
              return _FriendRequestTile(
                title: title,
                remark: _value(item, ['remark', 'handle_msg']),
                status: status,
                pending: widget.type == 'in' && _requestPending(item),
                busy: busy,
                onAccept: busy ? null : () => widget.onAccept(applyId),
                onReject: busy ? null : () => widget.onReject(applyId),
              );
            },
          ),
        );
      },
    );
  }

  void _reload() {
    setState(() {
      _future = widget.controller.friendApplyList(type: widget.type);
    });
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _surfaceColor : _fillColor,
          border: Border.all(color: selected ? _primaryColor : _borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? _primaryColor : _secondaryTextColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.title,
    required this.remark,
    required this.status,
    required this.pending,
    required this.onAccept,
    required this.onReject,
    this.busy = false,
  });

  final String title;
  final String remark;
  final String status;
  final bool pending;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            _Avatar(
              label: title,
              imageUrl: '',
              size: 42,
              color: _primaryColor,
              icon: Icons.person_outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    remark.isEmpty ? status : '$remark  $status',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _secondaryTextColor,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (pending) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onReject, child: const Text('拒绝')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(58, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('同意'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
