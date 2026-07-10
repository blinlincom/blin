part of 'package:bim/src/features/home/home_page.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _name = TextEditingController();
  final _notice = TextEditingController();
  final _selected = <String>{};
  late Future<List<Map<String, Object?>>> _friendsFuture;
  bool _loading = false;
  String _error = '';
  String _message = '';

  @override
  void initState() {
    super.initState();
    _friendsFuture = _loadFriends();
  }

  @override
  void dispose() {
    _name.dispose();
    _notice.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _loadFriends() {
    return widget.controller.loadFriends();
  }

  void _reloadFriends() {
    setState(() => _friendsFuture = _loadFriends());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: BimTopBar(
        title: '发起群聊',
        actions: [
          TextButton(
            onPressed: _loading ? null : _create,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成'),
          ),
        ],
      ),
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
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '群名称',
                        hintText: '给这个群起个名字',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notice,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '群公告',
                        hintText: '可选，创建后群成员可见',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const _GroupGap(),
            _InfoBar(
              text: _selected.isEmpty
                  ? '请选择至少一位好友'
                  : '已选择 ${_selected.length} 位好友',
            ),
            if (_loading) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            const _SectionHeader(text: '选择好友'),
            FutureBuilder<List<Map<String, Object?>>>(
              future: _friendsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: BimLoadingState(compact: true),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorState(
                    text: snapshot.error.toString(),
                    onRetry: _reloadFriends,
                  );
                }
                final friends = snapshot.data ?? [];
                if (friends.isEmpty) {
                  return const _EmptyRow(text: '暂无好友');
                }
                return Column(
                  children: [
                    for (final item in friends)
                      _SelectableContactTile(
                        title: _friendTitle(item),
                        subtitle: _friendSubtitle(item),
                        avatarUrl: _friendAvatarUrl(item),
                        selected: _selected.contains(_friendUserId(item)),
                        onTap: () {
                          final id = _friendUserId(item);
                          if (id.isEmpty) {
                            return;
                          }
                          setState(() {
                            if (_selected.contains(id)) {
                              _selected.remove(id);
                            } else {
                              _selected.add(id);
                            }
                          });
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '群名称不能为空');
      return;
    }
    final memberIds = _selected.toList();
    if (memberIds.isEmpty) {
      setState(() => _error = '请选择至少一位好友');
      return;
    }
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      final result = await widget.controller.createGroup(
        name: name,
        memberIds: memberIds,
        notice: _notice.text.trim(),
      );
      setState(() => _message = _friendlyResult(result, successText: '群聊已创建'));
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({
    required this.controller,
    required this.title,
    required this.groupId,
    required this.channelId,
    this.avatarUrl = '',
    this.memberCount,
    this.onlineCount,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String groupId;
  final String channelId;
  final String avatarUrl;
  final int? memberCount;
  final int? onlineCount;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  int? _loadedMemberCount;
  Future<Map<String, Object?>>? _membersFuture;
  List<Map<String, Object?>> _members = const [];
  String _error = '';
  String _message = '';
  late bool _pinned;

  @override
  void initState() {
    super.initState();
    _pinned = _initialPinned();
    _refreshMembers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: BimTopBar(
        title: '聊天信息${_groupCountTitleSuffix()}',
        actions: [
          IconButton(
            tooltip: '查找聊天记录',
            icon: const Icon(Icons.search),
            onPressed: _openMessageSearch,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            FutureBuilder<Map<String, Object?>>(
              future: _membersFuture,
              builder: (context, snapshot) {
                final done = snapshot.connectionState == ConnectionState.done;
                return _GroupInfoMemberGrid(
                  loading: !done && _members.isEmpty,
                  members: _members,
                  onOpenAll: _openMembers,
                  onAdd: _addMembers,
                );
              },
            ),
            const _GroupGap(),
            _GroupSettingsInfoTile(
              title: '群聊名称',
              value: widget.title.isEmpty ? '群聊' : widget.title,
              onTap: _updateGroup,
            ),
            _GroupSettingsInfoTile(
              title: '群公告',
              value: '查看或更新群公告',
              onTap: _updateGroup,
            ),
            _GroupSettingsNavTile(title: '添加成员', onTap: _addMembers),
            const _GroupGap(),
            _GroupSettingsNavTile(title: '查找聊天记录', onTap: _openMessageSearch),
            const _GroupGap(),
            _GroupSettingsSwitchTile(
              title: '置顶聊天',
              value: _pinned,
              onChanged: _changePinned,
            ),
            const _GroupGap(),
            _GroupSettingsDangerTile(
              title: '清空聊天记录',
              onTap: _clearGroupConversation,
            ),
            const _GroupGap(),
            _GroupSettingsDangerTile(
              title: '退出群聊',
              onTap: () =>
                  _run(() => widget.controller.leaveGroup(widget.groupId)),
            ),
            _GroupSettingsDangerTile(
              title: '解散群聊',
              onTap: () =>
                  _run(() => widget.controller.deleteGroup(widget.groupId)),
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  String _groupCountTitleSuffix() {
    final count = _loadedMemberCount ?? widget.memberCount;
    return count == null || count <= 0 ? '' : '($count)';
  }

  void _refreshMembers() {
    final future = widget.controller.groupMembers(widget.groupId);
    _membersFuture = future;
    unawaited(
      future
          .then((data) {
            if (!mounted) {
              return;
            }
            final members = _listFromResult(data);
            if (_sameMapList(_members, members) &&
                _loadedMemberCount == members.length) {
              return;
            }
            setState(() => _syncLoadedMembers(members));
          })
          .catchError((Object error) {
            if (mounted) {
              setState(() => _error = error.toString());
            }
          }),
    );
  }

  void _syncLoadedMembers(List<Map<String, Object?>> members) {
    if (_sameMapList(_members, members) &&
        _loadedMemberCount == members.length) {
      return;
    }
    _members = members;
    _loadedMemberCount = members.length;
  }

  bool _initialPinned() {
    final conversation = _currentConversation();
    if (conversation.isEmpty) {
      return false;
    }
    for (final key in const ['is_pinned', 'pinned', 'is_top', 'top']) {
      final value = conversation[key];
      if (value != null) {
        return _boolValue(value);
      }
    }
    return false;
  }

  Map<String, Object?> _currentConversation() {
    for (final item in widget.controller.cachedConversations()) {
      final channelType = _channelTypeFromConversation(item);
      final channelId = _value(item, ['channel_id', 'channelID', 'uid']);
      final groupId = _value(item, ['group_id', 'id']);
      if (channelType == _groupChannelType &&
          (channelId == widget.channelId || groupId == widget.groupId)) {
        return item;
      }
    }
    return const {};
  }

  Future<void> _changePinned(bool value) async {
    final previous = _pinned;
    setState(() {
      _pinned = value;
      _message = '';
      _error = '';
    });
    try {
      await widget.controller.setConversationPinned(
        channelId: widget.channelId,
        channelType: _groupChannelType,
        pinned: value,
      );
    } catch (error) {
      setState(() {
        _pinned = previous;
        _error = error.toString();
      });
    }
  }

  void _openMessageSearch() {
    _push(
      context,
      ChatMessageSearchPage(
        controller: widget.controller,
        title: widget.title,
        channelId: widget.channelId,
        channelType: _groupChannelType,
        groupId: widget.groupId,
      ),
    );
  }

  Future<void> _openMembers() async {
    await _push(
      context,
      GroupMemberListPage(
        controller: widget.controller,
        groupId: widget.groupId,
      ),
    );
    if (mounted) {
      setState(_refreshMembers);
    }
  }

  Future<void> _updateGroup() async {
    final data = await _openInput(
      context,
      title: '更新群资料',
      fields: const [
        ActionInputField(id: 'name', label: '群名称'),
        ActionInputField(id: 'avatar', label: '群头像地址'),
        ActionInputField(id: 'notice', label: '群公告', maxLines: 3),
      ],
    );
    if (data == null) {
      return;
    }
    await _run(
      () => widget.controller.updateGroup(
        groupId: widget.groupId,
        name: data['name'] ?? '',
        avatar: data['avatar'] ?? '',
        notice: data['notice'] ?? '',
      ),
    );
  }

  Future<void> _addMembers() async {
    final data = await _openInput(
      context,
      title: '添加群成员',
      fields: const [
        ActionInputField(id: 'member_ids', label: '成员账号', hint: '多个账号用逗号分隔'),
      ],
    );
    if (data == null) {
      return;
    }
    final ids = _idsFromText(data['member_ids'] ?? '');
    if (ids.isEmpty) {
      setState(() => _error = '成员不能为空');
      return;
    }
    await _run(
      () => widget.controller.addGroupMembers(
        groupId: widget.groupId,
        memberIds: ids,
      ),
    );
  }

  Future<void> _clearGroupConversation() async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空群聊记录',
      content: '将清空你自己看到的这个群聊记录和会话，不影响其他群成员。',
      confirmText: '清空',
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => widget.controller.deleteGroupConversation(
        groupId: widget.groupId,
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
        _refreshMembers();
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class GroupProfilePage extends StatefulWidget {
  const GroupProfilePage({
    required this.controller,
    required this.title,
    required this.groupId,
    required this.channelId,
    this.avatarUrl = '',
    this.memberCount,
    this.onlineCount,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String groupId;
  final String channelId;
  final String avatarUrl;
  final int? memberCount;
  final int? onlineCount;

  @override
  State<GroupProfilePage> createState() => _GroupProfilePageState();
}

class _GroupProfilePageState extends State<GroupProfilePage> {
  late Future<Map<String, Object?>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = widget.controller.groupMembers(widget.groupId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: const BimTopBar(title: '群聊资料'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ColoredBox(
              color: _surfaceColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                child: Row(
                  children: [
                    _Avatar(
                      label: widget.title,
                      imageUrl: widget.avatarUrl,
                      size: 72,
                      color: const Color(0xff34c759),
                      icon: Icons.groups,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title.isEmpty ? '群聊' : widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _groupProfileMeta,
                            style: const TextStyle(
                              color: _mutedColor,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const _GroupGap(),
            _ProfileInfoRow(label: '群名称', value: widget.title),
            FutureBuilder<Map<String, Object?>>(
              future: _membersFuture,
              builder: (context, snapshot) {
                final members = snapshot.connectionState == ConnectionState.done
                    ? _listFromResult(snapshot.data ?? const {})
                    : const <Map<String, Object?>>[];
                final owner = members.firstWhere(
                  (item) => _intValue(item, ['role']) == 1,
                  orElse: () => const <String, Object?>{},
                );
                return Column(
                  children: [
                    _ProfileInfoRow(
                      label: '群主',
                      value: owner.isEmpty ? '未获取' : _memberTitle(owner),
                    ),
                    _ProfileInfoRow(
                      label: '成员',
                      value: members.isEmpty
                          ? _groupProfileMeta
                          : '${members.length}人',
                    ),
                  ],
                );
              },
            ),
            const _GroupGap(),
            _PlainListTile(
              icon: Icons.groups_outlined,
              title: '查看全部群成员',
              subtitle: '成员资料、禁言和踢出',
              trailing: '',
              onTap: () => _push(
                context,
                GroupMemberListPage(
                  controller: widget.controller,
                  groupId: widget.groupId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _groupProfileMeta {
    final member = widget.memberCount == null ? '' : '${widget.memberCount}人';
    final online = widget.onlineCount == null ? '' : '${widget.onlineCount}人在线';
    final parts = [member, online].where((item) => item.isNotEmpty).toList();
    return parts.isEmpty ? '群聊' : parts.join(' · ');
  }
}

class GroupMemberListPage extends StatefulWidget {
  const GroupMemberListPage({
    required this.controller,
    required this.groupId,
    super.key,
  });

  final SessionController controller;
  final String groupId;

  @override
  State<GroupMemberListPage> createState() => _GroupMemberListPageState();
}

class _GroupMemberListPageState extends State<GroupMemberListPage> {
  var _version = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: const BimTopBar(title: '群成员'),
      body: SafeArea(
        child: FutureBuilder<Map<String, Object?>>(
          key: ValueKey(_version),
          future: widget.controller.groupMembers(widget.groupId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const BimLoadingState(label: '正在加载群成员');
            }
            if (snapshot.hasError) {
              return _ErrorState(text: snapshot.error.toString());
            }
            final members = _listFromResult(snapshot.data ?? const {});
            if (members.isEmpty) {
              return const _EmptyState(text: '暂无成员');
            }
            return ListView(
              children: [
                for (final member in members)
                  _PlainListTile(
                    icon: Icons.person_outline,
                    title: _memberTitle(member),
                    subtitle: _memberSubtitle(member),
                    trailing: _memberUsername(member),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupMemberActionPage(
                            controller: widget.controller,
                            groupId: widget.groupId,
                            member: member,
                          ),
                        ),
                      );
                      if (mounted) {
                        setState(() => _version++);
                      }
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GroupInfoMemberGrid extends StatelessWidget {
  const _GroupInfoMemberGrid({
    required this.loading,
    required this.members,
    required this.onOpenAll,
    required this.onAdd,
  });

  final bool loading;
  final List<Map<String, Object?>> members;
  final VoidCallback onOpenAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    const columns = 5;
    const rows = 4;
    const spacing = 8.0;
    final availableWidth = max(0.0, width - 36);
    final itemWidth = (availableWidth - spacing * (columns - 1)) / columns;
    final avatarSize = min(56.0, itemWidth);
    final previewCount = columns * rows - 1;
    final preview = members.take(previewCount).toList(growable: false);
    final showMore = members.length > previewCount;
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          children: [
            Wrap(
              spacing: spacing,
              runSpacing: 18,
              children: [
                for (final member in preview)
                  _GroupMemberGridItem(
                    width: itemWidth,
                    avatarSize: avatarSize,
                    title: _memberTitle(member),
                    avatarUrl: _avatarUrlFromMap(member),
                    onTap: onOpenAll,
                  ),
                _GroupMemberAddItem(
                  width: itemWidth,
                  avatarSize: avatarSize,
                  onTap: onAdd,
                ),
              ],
            ),
            if (loading && members.isEmpty) ...[
              const SizedBox(height: 18),
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ] else if (showMore) ...[
              const SizedBox(height: 22),
              InkWell(
                onTap: onOpenAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        '更多群成员',
                        style: TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: _mutedColor,
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GroupMemberGridItem extends StatelessWidget {
  const _GroupMemberGridItem({
    required this.width,
    required this.avatarSize,
    required this.title,
    required this.avatarUrl,
    required this.onTap,
  });

  final double width;
  final double avatarSize;
  final String title;
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            _Avatar(
              label: title,
              imageUrl: avatarUrl,
              size: avatarSize,
              color: const Color(0xff8e99a8),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _mutedColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMemberAddItem extends StatelessWidget {
  const _GroupMemberAddItem({
    required this.width,
    required this.avatarSize,
    required this.onTap,
  });

  final double width;
  final double avatarSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Container(
              width: avatarSize,
              height: avatarSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _surfaceColor,
                border: Border.all(color: _mutedColor.withValues(alpha: 0.45)),
                borderRadius: BorderRadius.circular(_avatarRadius(56)),
              ),
              child: const Icon(Icons.add, color: _mutedColor, size: 30),
            ),
            const SizedBox(height: 8),
            const Text(
              '添加',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: _mutedColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupSettingsNavTile extends StatelessWidget {
  const _GroupSettingsNavTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(title: title, onTap: onTap, minHeight: 62);
  }
}

class _GroupSettingsInfoTile extends StatelessWidget {
  const _GroupSettingsInfoTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      value: value,
      onTap: onTap,
      valueMaxLines: 2,
      minHeight: 62,
    );
  }
}

class _GroupSettingsSwitchTile extends StatelessWidget {
  const _GroupSettingsSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return BimSettingsSwitchTile(
      title: title,
      value: value,
      onChanged: onChanged,
    );
  }
}

class _GroupSettingsDangerTile extends StatelessWidget {
  const _GroupSettingsDangerTile({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimSettingsTile(
      title: title,
      onTap: onTap,
      tone: BimSettingsTileTone.danger,
      showChevron: false,
      minHeight: 62,
    );
  }
}

class MyGroupsPage extends StatefulWidget {
  const MyGroupsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MyGroupsPage> createState() => _MyGroupsPageState();
}

class _MyGroupsPageState extends State<MyGroupsPage> {
  List<Map<String, Object?>> _groups = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _groups = widget.controller.cachedGroups();
    _precacheContactAvatars(context, const [], _groups);
    _refresh(showLoading: _groups.isEmpty);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final groups = widget.controller.cachedGroups();
    if (_sameMapList(_groups, groups)) {
      return;
    }
    _precacheContactAvatars(context, const [], groups);
    setState(() {
      _groups = groups;
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
      final groups = await widget.controller.loadGroups();
      if (!mounted) {
        return;
      }
      _precacheContactAvatars(context, const [], groups);
      setState(() {
        _groups = groups;
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
      appBar: const BimTopBar(title: '我的群聊'),
      body: SafeArea(
        child: _loading && _groups.isEmpty
            ? const BimLoadingState(label: '正在加载群聊')
            : _error != null && _groups.isEmpty
            ? _ErrorState(text: _error!, onRetry: () => _refresh())
            : RefreshIndicator(
                onRefresh: () => _refresh(showLoading: false),
                child: ListView(
                  children: [
                    if (_groups.isEmpty) const _EmptyRow(text: '暂无群聊'),
                    for (final item in _groups)
                      _PlainListTile(
                        icon: Icons.groups_outlined,
                        title: _groupTitle(item),
                        subtitle: _value(item, ['notice', 'description']),
                        trailing:
                            '${_intValue(item, ['member_count', 'members'])}人',
                        avatarUrl: _groupAvatarUrl(item),
                        onTap: () =>
                            _openGroupChat(context, widget.controller, item),
                        onLongPress: () => _push(
                          context,
                          GroupDetailPage(
                            controller: widget.controller,
                            title: _groupTitle(item),
                            groupId: _groupIdFromItem(item),
                            channelId: _groupChannelId(item),
                          ),
                        ),
                      ),
                    if (_error != null) _InfoBar(text: '群聊刷新失败：$_error'),
                  ],
                ),
              ),
      ),
    );
  }
}

class GroupMemberActionPage extends StatefulWidget {
  const GroupMemberActionPage({
    required this.controller,
    required this.groupId,
    required this.member,
    super.key,
  });

  final SessionController controller;
  final String groupId;
  final Map<String, Object?> member;

  @override
  State<GroupMemberActionPage> createState() => _GroupMemberActionPageState();
}

class _GroupMemberActionPageState extends State<GroupMemberActionPage> {
  String _message = '';
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final memberId = _memberUserId(widget.member);
    return Scaffold(
      appBar: BimTopBar(title: _memberTitle(widget.member)),
      body: SafeArea(
        child: ListView(
          children: [
            _PlainListTile(
              icon: Icons.badge_outlined,
              title: '成员',
              subtitle: _memberSubtitle(widget.member),
              trailing: _memberRoleText(widget.member),
            ),
            _PlainListTile(
              icon: Icons.volume_off_outlined,
              title: '永久禁言',
              subtitle: '由系统或管理员限制该成员发言',
              trailing: '',
              onTap: () => _mute(memberId, permanent: true),
            ),
            _PlainListTile(
              icon: Icons.timer_outlined,
              title: '限时禁言',
              subtitle: '设置禁言秒数和原因',
              trailing: '',
              onTap: () => _mute(memberId, permanent: false),
            ),
            _PlainListTile(
              icon: Icons.volume_up_outlined,
              title: '解除禁言',
              subtitle: '恢复该成员群内发言',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.unmuteGroupMember(
                  groupId: widget.groupId,
                  memberId: memberId,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.admin_panel_settings_outlined,
              title: '设为管理员',
              subtitle: '仅群主可操作',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.setGroupAdmin(
                  groupId: widget.groupId,
                  memberId: memberId,
                  isAdmin: true,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.remove_moderator_outlined,
              title: '取消管理员',
              subtitle: '仅群主可操作',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.setGroupAdmin(
                  groupId: widget.groupId,
                  memberId: memberId,
                  isAdmin: false,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.workspace_premium_outlined,
              title: '转让群主',
              subtitle: '新群主必须是当前成员',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.transferGroupOwner(
                  groupId: widget.groupId,
                  newOwnerId: memberId,
                ),
              ),
            ),
            _PlainListTile(
              icon: Icons.person_remove_outlined,
              title: '移出群聊',
              subtitle: '同步移除频道订阅者',
              trailing: '',
              onTap: () => _run(
                () => widget.controller.removeGroupMembers(
                  groupId: widget.groupId,
                  memberIds: [memberId],
                ),
              ),
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _mute(String memberId, {required bool permanent}) async {
    var seconds = 0;
    var reason = '';
    if (!permanent) {
      final data = await _openInput(
        context,
        title: '限时禁言',
        fields: const [
          ActionInputField(
            id: 'expire_seconds',
            label: '禁言秒数',
            keyboardType: TextInputType.number,
          ),
          ActionInputField(id: 'reason', label: '原因'),
        ],
      );
      if (data == null) {
        return;
      }
      seconds = int.tryParse(data['expire_seconds'] ?? '') ?? 0;
      reason = data['reason'] ?? '';
      if (seconds <= 0) {
        setState(() => _error = '限时禁言秒数必须大于 0');
        return;
      }
    }
    await _run(
      () => widget.controller.muteGroupMember(
        groupId: widget.groupId,
        memberId: memberId,
        expireSeconds: seconds,
        reason: reason,
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
