part of 'package:bim/src/features/home/home_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _keyword = TextEditingController();
  List<Map<String, Object?>> _friends = const [];
  bool _loading = false;
  String? _loadError;
  Future<Map<String, Object?>>? _friendSearchFuture;
  String _friendSearchKeyword = '';
  String _message = '';
  String _error = '';
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    _friends = widget.controller.hasLoadedFriends
        ? widget.controller.cachedFriends(allowDisk: false)
        : widget.controller.cachedFriends(allowDisk: true);
    _refreshLocal(showLoading: _friends.isEmpty);
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _refreshLocal({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final friends = await widget.controller.loadFriends(forceRefresh: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _friends = friends;
        _loading = false;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _searchRemoteFriends() {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty) {
      setState(() => _error = '请输入账号');
      return;
    }
    setState(() {
      _friendSearchKeyword = keyword;
      _friendSearchFuture = widget.controller.searchFriends(
        keyword: keyword,
        limit: 20,
      );
      _message = '';
      _error = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: const BimTopBar(title: '搜索'),
      body: BimContentViewport(
        maxWidth: 760,
        child: _loading && _friends.isEmpty
            ? const BimLoadingState(label: '正在加载联系人')
            : _loadError != null && _friends.isEmpty
            ? _ErrorState(text: _loadError!, onRetry: () => _refreshLocal())
            : _buildSearchList(),
      ),
    );
  }

  Widget _buildSearchList() {
    final keyword = _keyword.text.trim().toLowerCase();
    final friends = _friends.where((item) {
      return keyword.isEmpty ||
          _friendTitle(item).toLowerCase().contains(keyword) ||
          _friendUsername(item).toLowerCase().contains(keyword);
    }).toList();
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: TextField(
            controller: _keyword,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _searchRemoteFriends(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '好友昵称或 @账号',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ButtonRow(
            children: [
              BimButton(
                label: '搜索账号',
                onPressed: _acting ? null : _searchRemoteFriends,
                icon: Icons.person_search_outlined,
              ),
              BimButton(
                label: '刷新本地',
                onPressed: () => _refreshLocal(showLoading: false),
                icon: Icons.refresh,
                kind: BimButtonKind.secondary,
              ),
            ],
          ),
        ),
        if (_acting) const _LinearBusy(),
        _ResultBlock(text: _message),
        _ErrorBlock(text: _error),
        if (_loadError != null) _InfoBar(text: '好友刷新失败：$_loadError'),
        const _SectionHeader(text: '添加朋友'),
        _RemoteFriendSearchBlock(
          controller: widget.controller,
          keyword: _friendSearchKeyword,
          future: _friendSearchFuture,
          onOpenChat: _openRemoteFriendChat,
          onApply: _applyRemoteFriend,
          onHandleIncoming: () =>
              _push(context, FriendRequestsPage(controller: widget.controller)),
        ),
        const _SectionHeader(text: '好友'),
        if (friends.isEmpty) const _EmptyRow(text: '没有匹配好友'),
        for (final item in friends)
          _ContactTile(
            title: _friendTitle(item),
            subtitle: _friendSubtitle(item),
            trailing: _friendUsername(item),
            isGroup: false,
            avatarUrl: _friendAvatarUrl(item),
            onTap: () => _openPrivateChat(context, widget.controller, item),
          ),
      ],
    );
  }

  Future<void> _applyRemoteFriend(Map<String, Object?> item) async {
    final friendId = _searchFriendId(item);
    if (friendId.isEmpty) {
      setState(() => _error = '用户信息为空');
      return;
    }
    setState(() {
      _acting = true;
      _message = '';
      _error = '';
    });
    try {
      final result = await widget.controller.applyFriend(
        friendId: friendId,
        remark: '通过搜索添加',
      );
      _message = _friendlyResult(result, successText: '好友申请已发送');
      if (_friendSearchKeyword.isNotEmpty) {
        _friendSearchFuture = widget.controller.searchFriends(
          keyword: _friendSearchKeyword,
          limit: 20,
        );
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  void _openRemoteFriendChat(Map<String, Object?> item) {
    final user = _asObjectMap(item['user']);
    final friendId = _searchFriendId(item);
    final channelId = _value(item, [
      'channel_id',
      'uid',
    ], fallback: _uidFromUserId(friendId));
    if (friendId.isEmpty || channelId.isEmpty) {
      setState(() => _error = '暂时无法打开该用户资料');
      return;
    }
    _openPrivateChat(context, widget.controller, {
      ...user,
      'friend': user,
      'friend_id': friendId,
      'userid': friendId,
      'channel_id': channelId,
    });
  }
}

class _RemoteFriendSearchBlock extends StatelessWidget {
  const _RemoteFriendSearchBlock({
    required this.controller,
    required this.keyword,
    required this.future,
    required this.onOpenChat,
    required this.onApply,
    required this.onHandleIncoming,
  });

  final SessionController controller;
  final String keyword;
  final Future<Map<String, Object?>>? future;
  final void Function(Map<String, Object?> item) onOpenChat;
  final void Function(Map<String, Object?> item) onApply;
  final VoidCallback onHandleIncoming;

  @override
  Widget build(BuildContext context) {
    final request = future;
    if (request == null) {
      return const _EmptyRow(text: '输入账号后搜索');
    }
    return FutureBuilder<Map<String, Object?>>(
      future: request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: BimLoadingState(compact: true),
          );
        }
        if (snapshot.hasError) {
          return _ErrorState(text: snapshot.error.toString());
        }
        final items = _listFromResult(snapshot.data ?? const {});
        if (items.isEmpty) {
          return _EmptyRow(text: keyword.isEmpty ? '暂无搜索结果' : '未找到用户');
        }
        return Column(
          children: [
            for (final item in items)
              _PlainListTile(
                icon: Icons.person_outline,
                title: _searchFriendTitle(item),
                subtitle: _searchFriendSubtitle(item),
                trailing: _searchFriendActionText(item),
                onTap: () {
                  if (_boolValue(item['is_friend'])) {
                    onOpenChat(item);
                  } else if (_boolValue(item['pending_in_apply'])) {
                    onHandleIncoming();
                  } else {
                    onApply(item);
                  }
                },
              ),
          ],
        );
      },
    );
  }
}
