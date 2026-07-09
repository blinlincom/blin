part of 'package:bim/src/features/home/home_page.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({required this.controller, super.key});

  final SessionController controller;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  List<Map<String, Object?>> _friends = const [];
  List<Map<String, Object?>> _serviceAccounts = const [];
  bool _loading = false;
  bool _serviceLoading = false;
  String? _error;
  String? _serviceError;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _friends = widget.controller.hasLoadedFriends
        ? widget.controller.cachedFriends(allowDisk: false)
        : const [];
    _serviceAccounts = widget.controller.hasLoadedServiceAccounts
        ? widget.controller.cachedServiceAccounts(allowDisk: false)
        : widget.controller.cachedServiceAccounts();
    _precacheContactAvatars(context, _friends, const []);
    _precacheAvatarUrls(context, _serviceAccounts.map(_serviceAccountAvatar));
    _refresh(showLoading: _friends.isEmpty && _serviceAccounts.isEmpty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    var changed = false;
    var friends = _friends;
    var services = _serviceAccounts;
    if (widget.controller.hasLoadedFriends) {
      final nextFriends = widget.controller.cachedFriends(allowDisk: false);
      if (!_sameMapList(_friends, nextFriends)) {
        friends = nextFriends;
        changed = true;
      }
    }
    if (widget.controller.hasLoadedServiceAccounts) {
      final nextServices = widget.controller.cachedServiceAccounts(
        allowDisk: false,
      );
      if (!_sameMapList(_serviceAccounts, nextServices)) {
        services = nextServices;
        changed = true;
      }
    }
    if (!changed) {
      return;
    }
    _precacheContactAvatars(context, friends, const []);
    _precacheAvatarUrls(context, services.map(_serviceAccountAvatar));
    setState(() {
      _friends = friends;
      _serviceAccounts = services;
      _loading = false;
      _serviceLoading = false;
      _error = null;
      _serviceError = null;
    });
  }

  Future<void> _refresh({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _serviceLoading = true;
        _error = null;
        _serviceError = null;
      });
    }
    List<Map<String, Object?>>? friends;
    List<Map<String, Object?>>? services;
    Object? friendError;
    Object? serviceError;
    try {
      friends = await widget.controller.loadFriends(forceRefresh: true);
    } catch (error) {
      friendError = error;
    }
    try {
      services = await widget.controller.loadServiceAccounts(
        forceRefresh: true,
      );
    } catch (error) {
      serviceError = error;
    }
    if (!mounted) {
      return;
    }
    final nextFriends = friends ?? _friends;
    final nextServices = services ?? _serviceAccounts;
    _precacheContactAvatars(context, nextFriends, const []);
    _precacheAvatarUrls(context, nextServices.map(_serviceAccountAvatar));
    setState(() {
      _friends = nextFriends;
      _serviceAccounts = nextServices;
      _loading = false;
      _serviceLoading = false;
      _error = friendError?.toString();
      _serviceError = serviceError?.toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final groupedFriends = _groupContactsByLetter(_friends);
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
              _MenuTile(
                icon: Icons.verified_user_outlined,
                iconColor: const Color(0xff2563eb),
                title: '服务号',
                subtitle: _serviceAccountsSubtitle,
                onTap: () => _push(
                  context,
                  ServiceAccountsPage(controller: widget.controller),
                ),
                trailing: _serviceLoading && _serviceAccounts.isNotEmpty
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              const _SectionHeader(text: '联系人'),
              if (_loading && _friends.isEmpty)
                const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _friends.isEmpty)
                SizedBox(
                  height: 200,
                  child: _ErrorState(text: _error!, onRetry: () => _refresh()),
                )
              else if (_friends.isEmpty)
                const _EmptyRow(text: '暂无联系人')
              else
                for (final group in groupedFriends) ...[
                  _SectionHeader(text: group.key),
                  for (final item in group.value)
                    _ContactTile(
                      key: ValueKey(
                        'contact-tab-${_friendUserId(item)}-${_friendChannelId(item)}',
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
            ],
          ),
        ),
        if (_friends.length >= 12)
          const Positioned(
            right: 4,
            top: 176,
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
        if (_serviceError != null && _serviceAccounts.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: _error != null && _friends.isNotEmpty ? 34 : 0,
            child: _InfoBar(text: '服务号刷新失败：$_serviceError'),
          ),
      ],
    );
  }

  String get _serviceAccountsSubtitle {
    if (_serviceLoading && _serviceAccounts.isEmpty) {
      return '正在同步';
    }
    if (_serviceError != null && _serviceAccounts.isEmpty) {
      return '点击重试';
    }
    final count = _serviceAccounts.length;
    if (count <= 0) {
      return '暂无服务号';
    }
    return '$count 个服务号';
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

class ServiceAccountsPage extends StatefulWidget {
  const ServiceAccountsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<ServiceAccountsPage> createState() => _ServiceAccountsPageState();
}

class _ServiceAccountsPageState extends State<ServiceAccountsPage> {
  List<Map<String, Object?>> _accounts = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _accounts = widget.controller.hasLoadedServiceAccounts
        ? widget.controller.cachedServiceAccounts(allowDisk: false)
        : widget.controller.cachedServiceAccounts();
    _precacheAvatarUrls(context, _accounts.map(_serviceAccountAvatar));
    _refresh(showLoading: _accounts.isEmpty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!widget.controller.hasLoadedServiceAccounts) {
      return;
    }
    final accounts = widget.controller.cachedServiceAccounts(allowDisk: false);
    if (_sameMapList(_accounts, accounts)) {
      return;
    }
    _precacheAvatarUrls(context, accounts.map(_serviceAccountAvatar));
    setState(() {
      _accounts = accounts;
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
      final accounts = await widget.controller.loadServiceAccounts(
        forceRefresh: true,
      );
      if (!mounted) {
        return;
      }
      _precacheAvatarUrls(context, accounts.map(_serviceAccountAvatar));
      setState(() {
        _accounts = accounts;
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
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('服务号')),
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
                  const _SectionHeader(text: '服务号'),
                  if (_loading && _accounts.isEmpty)
                    const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null && _accounts.isEmpty)
                    SizedBox(
                      height: 200,
                      child: _ErrorState(
                        text: _error!,
                        onRetry: () => _refresh(),
                      ),
                    )
                  else if (_accounts.isEmpty)
                    const _EmptyRow(text: '暂无服务号')
                  else
                    for (final item in _accounts)
                      _ContactTile(
                        key: ValueKey(
                          'service-${_serviceAccountId(item)}-${_serviceAccountChannelId(item)}',
                        ),
                        title: _serviceAccountName(item),
                        subtitle: _serviceAccountSubtitle(item),
                        trailing: _boolValue(item['muted']) ? '免打扰' : '',
                        isGroup: false,
                        avatarUrl: _serviceAccountAvatar(item),
                        onTap: () => _openServiceAccount(item),
                      ),
                ],
              ),
            ),
            if (_error != null && _accounts.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _InfoBar(text: '服务号刷新失败：$_error'),
              ),
          ],
        ),
      ),
    );
  }

  void _openServiceAccount(Map<String, Object?> account) {
    final channelId = _serviceAccountChannelId(account);
    if (channelId.isEmpty) {
      _showWalletMessage(context, '服务号暂不可用');
      return;
    }
    Navigator.of(context)
        .push(
          _chatPageRoute(
            PaymentServicePage(
              controller: widget.controller,
              title: _serviceAccountName(account),
              channelId: channelId,
              channelType: _serviceAccountChannelType(account),
              serviceAccount: account,
            ),
          ),
        )
        .then(
          (_) => _markConversationReadAfterPop(
            widget.controller,
            channelId,
            _serviceAccountChannelType(account),
          ),
        );
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

String _serviceAccountId(Map<String, Object?> item) {
  return _value(item, ['service_id', 'id', 'code', 'user_id']);
}

String _serviceAccountName(Map<String, Object?> item) {
  return _value(item, [
    'name',
    'nickname',
    'title',
  ], fallback: _value(item, ['code'], fallback: '服务号'));
}

String _serviceAccountSubtitle(Map<String, Object?> item) {
  final description = _value(item, ['description', 'signature', 'remark']);
  if (description.isNotEmpty) {
    return description;
  }
  return '通知与服务';
}

String _serviceAccountAvatar(Map<String, Object?> item) {
  return _avatarUrlFromMap(item);
}

String _serviceAccountChannelId(Map<String, Object?> item) {
  return _value(item, [
    'channel_id',
    'uid',
    'im_uid',
  ], fallback: _value(item, ['user_id']));
}

int _serviceAccountChannelType(Map<String, Object?> item) {
  final value = _intValue(item, ['channel_type']);
  return value > 0 ? value : _privateChannelType;
}

bool _serviceAccountAllowUnfollow(Map<String, Object?> item) {
  return _boolValue(item['allow_unfollow']);
}

List<MapEntry<String, List<Map<String, Object?>>>> _groupContactsByLetter(
  List<Map<String, Object?>> friends,
) {
  final sorted = friends.map(Map<String, Object?>.from).toList();
  sorted.sort((left, right) {
    final leftLetter = _contactSortLetter(left);
    final rightLetter = _contactSortLetter(right);
    final letterResult = leftLetter.compareTo(rightLetter);
    if (letterResult != 0) {
      return letterResult;
    }
    return _friendTitle(left).compareTo(_friendTitle(right));
  });
  final groups = <MapEntry<String, List<Map<String, Object?>>>>[];
  for (final item in sorted) {
    final letter = _contactSortLetter(item);
    if (groups.isEmpty || groups.last.key != letter) {
      groups.add(MapEntry(letter, <Map<String, Object?>>[item]));
    } else {
      groups.last.value.add(item);
    }
  }
  return groups;
}

String _contactSortLetter(Map<String, Object?> item) {
  final title = _friendTitle(item).trim();
  final source = title.isEmpty ? _friendUsername(item).trim() : title;
  if (source.isEmpty) {
    return '#';
  }
  final first = source.characters.first.toUpperCase();
  if (RegExp(r'^[A-Z]$').hasMatch(first)) {
    return first;
  }
  return '#';
}
