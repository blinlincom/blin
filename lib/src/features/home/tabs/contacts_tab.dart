part of 'package:bim/src/features/home/home_page.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({required this.controller, super.key});

  final SessionController controller;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<Map<String, Object?>> _friends = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _friends = widget.controller.hasLoadedFriends
        ? widget.controller.cachedFriends(allowDisk: false)
        : const [];
    _precacheContactAvatars(context, _friends, const []);
    _refresh(showLoading: _friends.isEmpty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!widget.controller.hasLoadedFriends) {
      return;
    }
    final friends = widget.controller.cachedFriends(allowDisk: false);
    if (_sameMapList(_friends, friends)) {
      return;
    }
    _precacheContactAvatars(context, friends, const []);
    setState(() {
      _friends = friends;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final friends = await widget.controller.loadFriends(forceRefresh: true);
      if (!mounted) {
        return;
      }
      _precacheContactAvatars(context, friends, const []);
      setState(() {
        _friends = friends;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _refresh(showLoading: false),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              _SearchBar(
                hintText: '搜索',
                onTap: () =>
                    _push(context, SearchPage(controller: widget.controller)),
              ),
              _MenuTile(
                icon: Icons.group_add,
                iconColor: const Color(0xffffa51f),
                title: '新的朋友',
                subtitle: '',
                onTap: () => _push(
                  context,
                  FriendRequestsPage(controller: widget.controller),
                ),
                trailing: widget.controller.friendApplyUnreadCount > 0
                    ? _UnreadBadge(
                        count: widget.controller.friendApplyUnreadCount,
                        compact: true,
                      )
                    : null,
              ),
              _MenuTile(
                icon: Icons.groups,
                iconColor: const Color(0xff36c56f),
                title: '群聊',
                subtitle: '',
                onTap: () =>
                    _push(context, MyGroupsPage(controller: widget.controller)),
              ),
              const _SectionHeader(text: '联系人'),
              _MenuTile(
                icon: Icons.person_outline,
                iconColor: _primaryColor,
                title: '联系人',
                subtitle: _contactsSubtitle,
                onTap: () => _push(
                  context,
                  ContactsListPage(controller: widget.controller),
                ),
              ),
            ],
          ),
        ),
        if (_error != null && _friends.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _InfoBar(text: '联系人刷新失败：$_error'),
          ),
      ],
    );
  }

  String get _contactsSubtitle {
    if (_loading && _friends.isEmpty) {
      return '正在同步';
    }
    if (_error != null && _friends.isEmpty) {
      return '点击重试';
    }
    final count = _friends.length;
    if (count <= 0) {
      return '暂无联系人';
    }
    return '$count 位联系人';
  }
}

class ContactsListPage extends StatefulWidget {
  const ContactsListPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<ContactsListPage> createState() => _ContactsListPageState();
}

class _ContactsListPageState extends State<ContactsListPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, Object?>> _friends = const [];
  bool _loading = false;
  String? _error;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _friends = widget.controller.hasLoadedFriends
        ? widget.controller.cachedFriends(allowDisk: false)
        : widget.controller.cachedFriends(allowDisk: true);
    _precacheContactAvatars(context, _friends, const []);
    _searchController.addListener(_onSearchChanged);
    _refresh(showLoading: _friends.isEmpty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!widget.controller.hasLoadedFriends) {
      return;
    }
    final friends = widget.controller.cachedFriends(allowDisk: false);
    if (_sameMapList(_friends, friends)) {
      return;
    }
    _precacheContactAvatars(context, friends, const []);
    setState(() {
      _friends = friends;
      _loading = false;
      _error = null;
    });
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _keyword) {
      return;
    }
    setState(() => _keyword = next);
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final friends = await widget.controller.loadFriends(forceRefresh: true);
      if (!mounted) {
        return;
      }
      _precacheContactAvatars(context, friends, const []);
      setState(() {
        _friends = friends;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<Map<String, Object?>> get _visibleFriends {
    final keyword = _keyword.toLowerCase();
    if (keyword.isEmpty) {
      return _friends;
    }
    return _friends
        .where((friend) {
          final title = _friendTitle(friend).toLowerCase();
          final username = _friendUsername(friend).toLowerCase();
          return title.contains(keyword) || username.contains(keyword);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visibleFriends = _visibleFriends;
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('联系人')),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () => _refresh(showLoading: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _ContactsListSearchField(controller: _searchController),
                  const _SectionHeader(text: '联系人'),
                  if (_loading && _friends.isEmpty)
                    const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null && _friends.isEmpty)
                    SizedBox(
                      height: 200,
                      child: _ErrorState(
                        text: _error!,
                        onRetry: () => _refresh(),
                      ),
                    )
                  else if (_friends.isEmpty)
                    const _EmptyRow(text: '暂无联系人')
                  else if (visibleFriends.isEmpty)
                    const _EmptyRow(text: '没有匹配的联系人')
                  else
                    for (final item in visibleFriends)
                      _ContactTile(
                        key: ValueKey(
                          'contact-${_friendUserId(item)}-${_friendChannelId(item)}',
                        ),
                        title: _friendTitle(item),
                        subtitle: _friendSubtitle(item),
                        trailing: '',
                        isGroup: false,
                        avatarUrl: _friendAvatarUrl(item),
                        onTap: () => _openContactProfile(item),
                        onLongPress: () =>
                            _openPrivateChat(context, widget.controller, item),
                      ),
                ],
              ),
            ),
            if (visibleFriends.length >= 12)
              const Positioned(
                right: 4,
                top: 88,
                bottom: 24,
                child: IgnorePointer(child: _AlphabetIndex()),
              ),
            if (_error != null && _friends.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _InfoBar(text: '联系人刷新失败：$_error'),
              ),
          ],
        ),
      ),
    );
  }

  void _openContactProfile(Map<String, Object?> item) {
    _push(
      context,
      FriendProfilePage(
        controller: widget.controller,
        title: _friendTitle(item),
        receiverId: _friendUserId(item),
        channelId: _friendChannelId(item),
        avatarUrl: _friendAvatarUrl(item),
        online: _friendPresenceText(item) == '在线',
        onOpenChat: () => _openPrivateChat(context, widget.controller, item),
      ),
    );
  }
}

class _ContactsListSearchField extends StatelessWidget {
  const _ContactsListSearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        child: SizedBox(
          height: 36,
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: '搜索联系人',
              hintStyle: const TextStyle(
                color: _mutedColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: _mutedColor,
                size: 18,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              isDense: true,
              filled: true,
              fillColor: _fillColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(
              color: _textColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
