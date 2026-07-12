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
    return BimScaffold(
      topBar: BimTopBar(
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
      body: BimContentViewport(
        maxWidth: 760,
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

class _GroupFriendPickerPage extends StatefulWidget {
  const _GroupFriendPickerPage({
    required this.controller,
    required this.excludedUserIds,
  });

  final SessionController controller;
  final Set<String> excludedUserIds;

  @override
  State<_GroupFriendPickerPage> createState() => _GroupFriendPickerPageState();
}

class _GroupFriendPickerPageState extends State<_GroupFriendPickerPage> {
  final Set<String> _selected = {};
  late Future<List<Map<String, Object?>>> _friendsFuture;

  @override
  void initState() {
    super.initState();
    _friendsFuture = widget.controller.loadFriends();
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: _selected.isEmpty ? '选择联系人' : '已选择 ${_selected.length} 人',
        actions: [
          TextButton(
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(
                    context,
                  ).pop<List<String>>(_selected.toList(growable: false)),
            child: const Text('完成'),
          ),
        ],
      ),
      body: BimContentViewport(
        maxWidth: 760,
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: _friendsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const BimLoadingState(label: '正在加载联系人');
            }
            if (snapshot.hasError) {
              return _ErrorState(
                text: snapshot.error.toString(),
                onRetry: () => setState(
                  () => _friendsFuture = widget.controller.loadFriends(
                    forceRefresh: true,
                  ),
                ),
              );
            }
            final friends = (snapshot.data ?? const [])
                .where(
                  (friend) =>
                      !widget.excludedUserIds.contains(_friendUserId(friend)),
                )
                .toList(growable: false);
            if (friends.isEmpty) {
              return const BimEmptyState(
                title: '没有可添加的联系人',
                message: '群内已经包含你的全部联系人',
              );
            }
            return ListView.builder(
              itemCount: friends.length,
              itemBuilder: (context, index) {
                final friend = friends[index];
                final id = _friendUserId(friend);
                return _SelectableContactTile(
                  title: _friendTitle(friend),
                  subtitle: _friendSubtitle(friend),
                  avatarUrl: _friendAvatarUrl(friend),
                  selected: _selected.contains(id),
                  onTap: () => setState(() {
                    if (!_selected.add(id)) {
                      _selected.remove(id);
                    }
                  }),
                );
              },
            );
          },
        ),
      ),
    );
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
  List<Map<String, Object?>> _members = const [];
  bool _membersLoading = true;
  String _error = '';
  String _message = '';
  late bool _pinned;
  String _groupAvatar = '';
  late String _groupTitle;
  String _groupNotice = '';

  @override
  void initState() {
    super.initState();
    _pinned = _initialPinned();
    _groupAvatar = widget.avatarUrl;
    _groupTitle = widget.title;
    _hydrateGroupDetails();
    _refreshMembers();
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: '聊天信息${_groupCountTitleSuffix()}',
        actions: [
          IconButton(
            tooltip: '查找聊天记录',
            icon: const Icon(Icons.search),
            onPressed: _openMessageSearch,
          ),
        ],
      ),
      body: BimContentViewport(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.only(bottom: BimSpacing.x8),
          children: [
            _GroupInfoMemberGrid(
              loading: _membersLoading,
              expectedMemberCount: _loadedMemberCount ?? widget.memberCount,
              members: _members,
              onOpenAll: _openMembers,
              onAdd: _addMembers,
            ),
            const _SectionHeader(text: '群聊资料'),
            _GroupAvatarSettingsTile(
              title: _groupTitle,
              imageUrl: _groupAvatar,
              members: _members,
              onTap: _uploadGroupAvatar,
            ),
            _GroupSettingsInfoTile(
              title: '群聊名称',
              value: _groupTitle.isEmpty ? '群聊' : _groupTitle,
              onTap: _updateGroupName,
            ),
            _GroupSettingsInfoTile(
              title: '群公告',
              value: _groupNotice.isEmpty ? '暂无群公告' : _groupNotice,
              onTap: _updateGroupNotice,
            ),
            const _SectionHeader(text: '聊天设置'),
            _GroupSettingsNavTile(title: '查找聊天记录', onTap: _openMessageSearch),
            _GroupSettingsSwitchTile(
              title: '置顶聊天',
              subtitle: '在消息列表顶部显示该群聊',
              value: _pinned,
              onChanged: _changePinned,
            ),
            const _SectionHeader(text: '聊天数据'),
            _GroupSettingsDangerTile(
              title: '清空聊天记录',
              onTap: _clearGroupConversation,
            ),
            const _SectionHeader(text: '群管理'),
            _GroupSettingsDangerTile(title: '退出群聊', onTap: _leaveGroup),
            _GroupSettingsDangerTile(title: '解散群聊', onTap: _deleteGroup),
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

  void _hydrateGroupDetails() {
    for (final group in widget.controller.cachedGroups()) {
      if (_groupIdFromItem(group) != widget.groupId &&
          _groupChannelId(group) != widget.channelId) {
        continue;
      }
      final title = _groupTitleFromData(group);
      final notice = _groupNoticeFromData(group);
      final avatar = _groupAvatarUrl(group);
      if (title.isNotEmpty) _groupTitle = title;
      _groupNotice = notice;
      if (avatar.isNotEmpty) _groupAvatar = avatar;
      break;
    }
  }

  String _groupTitleFromData(Map<String, Object?> group) {
    final nested = _asObjectMap(group['group']);
    return _value(group, [
      'name',
      'group_name',
      'title',
    ], fallback: _value(nested, ['name', 'group_name', 'title']));
  }

  String _groupNoticeFromData(Map<String, Object?> group) {
    final nested = _asObjectMap(group['group']);
    return _value(group, [
      'notice',
      'announcement',
    ], fallback: _value(nested, ['notice', 'announcement']));
  }

  void _refreshMembers() {
    if (_members.isEmpty) {
      _membersLoading = true;
    }
    final future = widget.controller.groupMembers(widget.groupId);
    unawaited(
      future
          .then((data) {
            if (!mounted) {
              return;
            }
            final members = _listFromResult(data);
            if (_sameMapList(_members, members) &&
                _loadedMemberCount == members.length) {
              if (_membersLoading) {
                setState(() => _membersLoading = false);
              }
              return;
            }
            setState(() {
              _syncLoadedMembers(members);
              _membersLoading = false;
            });
          })
          .catchError((Object error) {
            if (mounted) {
              setState(() {
                _membersLoading = false;
                _error = error.toString();
              });
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
      _refreshMembers();
    }
  }

  Future<void> _updateGroupName() async {
    final data = await _openInput(
      context,
      title: '修改群聊名称',
      fields: [
        ActionInputField(id: 'name', label: '群聊名称', initial: _groupTitle),
      ],
    );
    if (data == null) {
      return;
    }
    final name = data['name']?.trim() ?? '';
    if (name.isEmpty) {
      setState(() => _error = '群聊名称不能为空');
      return;
    }
    await _run(() async {
      final result = await widget.controller.updateGroup(
        groupId: widget.groupId,
        name: name,
      );
      if (mounted) setState(() => _groupTitle = name);
      return result;
    });
  }

  Future<void> _updateGroupNotice() async {
    final data = await _openInput(
      context,
      title: '编辑群公告',
      fields: [
        ActionInputField(
          id: 'notice',
          label: '群公告',
          initial: _groupNotice,
          hint: '群成员可在群资料中查看',
          maxLines: 6,
        ),
      ],
    );
    if (data == null) return;
    final notice = data['notice']?.trim() ?? '';
    await _run(() async {
      final result = await widget.controller.updateGroup(
        groupId: widget.groupId,
        notice: notice,
      );
      if (mounted) setState(() => _groupNotice = notice);
      return result;
    });
  }

  Future<void> _uploadGroupAvatar() async {
    final selected = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) =>
            const _InAppMediaPickerPage(contentType: ChatContentTypes.image),
      ),
    );
    final filePath = selected?['file_path']?.trim() ?? '';
    if (filePath.isEmpty || !mounted) {
      return;
    }
    await _run(() async {
      final result = await widget.controller.uploadGroupAvatar(
        groupId: widget.groupId,
        filePath: filePath,
      );
      final avatar = _value(result, ['avatar']);
      if (avatar.isNotEmpty && mounted) {
        setState(() => _groupAvatar = avatar);
      }
      return result;
    });
  }

  Future<void> _addMembers() async {
    final existingIds = _members
        .map(_memberUserId)
        .where((item) => item.isNotEmpty)
        .toSet();
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => _GroupFriendPickerPage(
          controller: widget.controller,
          excludedUserIds: existingIds,
        ),
      ),
    );
    if (ids == null || ids.isEmpty || !mounted) {
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

  Future<void> _leaveGroup() async {
    final confirmed = await _confirmDanger(
      context,
      title: '退出群聊',
      content: '退出后将不再接收该群聊消息，需要其他成员重新邀请才能加入。',
      confirmText: '退出',
    );
    if (!confirmed) {
      return;
    }
    await _run(() => widget.controller.leaveGroup(widget.groupId));
  }

  Future<void> _deleteGroup() async {
    final confirmed = await _confirmDanger(
      context,
      title: '解散群聊',
      content: '解散后所有成员都将退出，且该操作无法撤销。',
      confirmText: '解散',
    );
    if (!confirmed) {
      return;
    }
    await _run(() => widget.controller.deleteGroup(widget.groupId));
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
    return BimScaffold(
      topBar: const BimTopBar(title: '群聊资料'),
      body: BimContentViewport(
        maxWidth: 680,
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
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: const BimTopBar(title: '群成员'),
      body: BimContentViewport(
        maxWidth: 760,
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
            final currentUserId =
                widget.controller.session?.userId.toString() ?? '';
            final self = members.where(
              (item) => _memberUserId(item) == currentUserId,
            );
            final selfRole = self.isEmpty ? 0 : _intValue(self.first, ['role']);
            return StatefulBuilder(
              builder: (context, updateFilter) {
                final query = _searchController.text.trim().toLowerCase();
                final visible = members
                    .where((member) {
                      if (query.isEmpty) return true;
                      return _memberTitle(
                            member,
                          ).toLowerCase().contains(query) ||
                          _memberUsername(member).toLowerCase().contains(query);
                    })
                    .toList(growable: false);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(BimSpacing.x4),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => updateFilter(() {}),
                        decoration: const InputDecoration(
                          hintText: '搜索群成员',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? const _EmptyState(text: '没有找到群成员')
                          : ListView.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final member = visible[index];
                                return ListTile(
                                  leading: _Avatar(
                                    label: _memberTitle(member),
                                    imageUrl: _avatarUrlFromMap(member),
                                    size: 42,
                                  ),
                                  title: Text(_memberTitle(member)),
                                  subtitle: Text(_memberSubtitle(member)),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => GroupMemberActionPage(
                                          controller: widget.controller,
                                          groupId: widget.groupId,
                                          member: member,
                                          currentUserRole: selfRole,
                                          isSelf:
                                              _memberUserId(member) ==
                                              currentUserId,
                                        ),
                                      ),
                                    );
                                    if (mounted) setState(() => _version++);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
