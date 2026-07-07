part of 'package:bim/src/features/home/home_page.dart';

class _ContactCardPickerPage extends StatefulWidget {
  const _ContactCardPickerPage({required this.controller});

  final SessionController controller;

  @override
  State<_ContactCardPickerPage> createState() => _ContactCardPickerPageState();
}

class _ContactCardPickerPageState extends State<_ContactCardPickerPage> {
  final _keyword = TextEditingController();
  List<Map<String, Object?>> _friends = const [];
  bool _loading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _friends = widget.controller.cachedFriends(allowDisk: true);
    _keyword.addListener(() => setState(() {}));
    _loadFriends(showLoading: _friends.isEmpty);
  }

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }

  Future<void> _loadFriends({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = '';
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
        _error = '';
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'contact card friends load failed',
        data: {'error': error.toString(), 'stack': stackTrace.toString()},
      );
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
    final filteredFriends = _filteredFriends();
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('选择名片'),
        centerTitle: true,
        toolbarHeight: BimDimensions.appBar,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        titleTextStyle: const TextStyle(
          color: _textColor,
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: _lightBorderColor),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _loadFriends(showLoading: false),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            children: [
              ColoredBox(
                color: _surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                  child: TextField(
                    controller: _keyword,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '搜索好友昵称或用户名',
                      hintStyle: const TextStyle(
                        color: _mutedColor,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: _mutedColor,
                        size: 18,
                      ),
                      filled: true,
                      fillColor: _fillColor,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              if (_loading && _friends.isEmpty)
                const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error.isNotEmpty && _friends.isEmpty)
                SizedBox(
                  height: 200,
                  child: _ErrorState(
                    text: _error,
                    onRetry: () => _loadFriends(),
                  ),
                )
              else ...[
                if (_error.isNotEmpty) _InfoBar(text: '好友刷新失败：$_error'),
                const _SectionHeader(text: '我的好友'),
                if (filteredFriends.isEmpty)
                  const _EmptyRow(text: '没有可发送的好友名片'),
                for (final friend in filteredFriends)
                  _ContactTile(
                    title: _friendTitle(friend),
                    subtitle: _friendSubtitle(friend),
                    trailing: _friendUsername(friend),
                    isGroup: false,
                    avatarUrl: _friendAvatarUrl(friend),
                    onTap: () => Navigator.of(
                      context,
                    ).pop<Map<String, Object?>>(_contactCardPayload(friend)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, Object?>> _filteredFriends() {
    final keyword = _keyword.text.trim().toLowerCase();
    if (keyword.isEmpty) {
      return _friends;
    }
    return _friends
        .where((friend) {
          return _friendTitle(friend).toLowerCase().contains(keyword) ||
              _friendUsername(friend).toLowerCase().contains(keyword);
        })
        .toList(growable: false);
  }

  Map<String, Object?> _contactCardPayload(Map<String, Object?> friend) {
    final profile = _friendProfile(friend);
    final userId = _friendUserId(friend);
    final username = _friendUsername(friend);
    final nickname = _friendTitle(friend);
    final avatar = _friendAvatarUrl(friend);
    return {
      'card_user_id': userId,
      'card_uid': _value(profile, [
        'uid',
        'im_uid',
      ], fallback: _value(friend, ['uid', 'im_uid', 'channel_id'])),
      'card_username': username,
      'card_nickname': nickname,
      'card_name': nickname,
      'card_avatar': avatar,
      if (_value(friend, ['remark']).isNotEmpty)
        'card_remark': _value(friend, ['remark']),
    };
  }
}
