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
    return BimScaffold(
      topBar: BimTopBar(
        title: '新的朋友',
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => setState(() => _version++),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '添加好友',
            onPressed: () =>
                _push(context, AddFriendPage(controller: widget.controller)),
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              BimBreakpoints.horizontalPadding(context),
              BimSpacing.x3,
              BimBreakpoints.horizontalPadding(context),
              BimSpacing.x2,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: BimSegmentedControl<String>(
                selected: _type,
                options: const [
                  BimSegmentOption(value: 'in', label: '收到的申请'),
                  BimSegmentOption(value: 'out', label: '发出的申请'),
                ],
                onChanged: (value) => setState(() => _type = value),
              ),
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
          return const BimLoadingState(label: '正在加载好友申请');
        }
        if (snapshot.hasError && items.isEmpty) {
          return _ErrorState(text: snapshot.error.toString(), onRetry: _reload);
        }
        if (items.isEmpty) {
          return BimEmptyState(
            title: widget.type == 'in' ? '暂无新的好友申请' : '还没有发出申请',
            message: widget.type == 'in' ? '收到新的申请后会显示在这里' : '可以通过用户名搜索并添加好友',
            icon: widget.type == 'in'
                ? Icons.person_add_alt_1_outlined
                : Icons.manage_search_outlined,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              BimBreakpoints.horizontalPadding(context),
              BimSpacing.x2,
              BimBreakpoints.horizontalPadding(context),
              BimSpacing.x6,
            ),
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: BimSpacing.x2),
            itemBuilder: (context, index) {
              final item = items[index];
              final applyId = _value(item, ['apply_id', 'id']);
              final title = _requestTitle(item, widget.type);
              final status = _requestStatus(item);
              final busy = widget.handlingApplyId == applyId;
              return _FriendRequestTile(
                title: title,
                avatarUrl: _requestAvatarUrl(item, widget.type),
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

class _FriendRequestTile extends StatelessWidget {
  const _FriendRequestTile({
    required this.title,
    required this.avatarUrl,
    required this.remark,
    required this.status,
    required this.pending,
    required this.onAccept,
    required this.onReject,
    this.busy = false,
  });

  final String title;
  final String avatarUrl;
  final String remark;
  final String status;
  final bool pending;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final statusColor = pending
        ? BimColors.primary
        : status.contains('通过')
        ? BimColors.success
        : BimColors.mutedText;
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border.all(color: BimColors.borderLight),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: 46,
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
                    remark.isEmpty ? '请求添加你为好友' : remark,
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
              const SizedBox(width: BimSpacing.x2),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 70,
                    height: 36,
                    child: FilledButton(
                      onPressed: onAccept,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BimRadius.sm),
                        ),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('接受'),
                    ),
                  ),
                  SizedBox(
                    height: 34,
                    child: TextButton(
                      onPressed: onReject,
                      child: const Text('忽略'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(width: BimSpacing.x2),
              Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: BimTypography.caption,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
