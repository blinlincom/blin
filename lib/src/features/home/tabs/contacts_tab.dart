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
              ),
              _MenuTile(
                icon: Icons.groups,
                iconColor: const Color(0xff36c56f),
                title: '群聊',
                subtitle: '',
                onTap: () =>
                    _push(context, MyGroupsPage(controller: widget.controller)),
              ),
              const _SectionHeader(text: '好友'),
              if (_loading && _friends.isEmpty)
                const SizedBox(
                  height: 160,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _friends.isEmpty)
                SizedBox(
                  height: 180,
                  child: _ErrorState(text: _error!, onRetry: () => _refresh()),
                )
              else if (_friends.isEmpty)
                const _EmptyRow(text: '暂无好友'),
              for (final item in _friends)
                _ContactTile(
                  key: ValueKey(
                    'friend-${_friendUserId(item)}-${_friendChannelId(item)}',
                  ),
                  title: _friendTitle(item),
                  subtitle: _friendSubtitle(item),
                  trailing: '',
                  isGroup: false,
                  avatarUrl: _friendAvatarUrl(item),
                  onTap: () =>
                      _openPrivateChat(context, widget.controller, item),
                  onLongPress: () => _push(
                    context,
                    PrivateChatActionsPage(
                      controller: widget.controller,
                      title: _friendTitle(item),
                      receiverId: _friendUserId(item),
                      channelId: _friendChannelId(item),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Positioned(
          right: 4,
          top: 96,
          bottom: 74,
          child: IgnorePointer(child: _AlphabetIndex()),
        ),
        if (_error != null && _friends.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _InfoBar(text: '通讯录刷新失败：$_error'),
          ),
      ],
    );
  }
}
