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
      appBar: AppBar(
        title: const Text('发起群聊'),
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
                    child: Center(child: CircularProgressIndicator()),
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
    super.key,
  });

  final SessionController controller;
  final String title;
  final String groupId;
  final String channelId;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  var _version = 0;
  String _error = '';
  String _message = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader(text: '群设置'),
            _PlainListTile(
              icon: Icons.edit_outlined,
              title: '更新群资料',
              subtitle: '群名、头像、公告',
              trailing: '',
              onTap: _updateGroup,
            ),
            _PlainListTile(
              icon: Icons.person_add_alt_1,
              title: '添加成员',
              subtitle: '添加好友到群聊',
              trailing: '',
              onTap: _addMembers,
            ),
            _PlainListTile(
              icon: Icons.logout,
              title: '退出群聊',
              subtitle: '群主需要先转让群主',
              trailing: '',
              onTap: () =>
                  _run(() => widget.controller.leaveGroup(widget.groupId)),
            ),
            _PlainListTile(
              icon: Icons.delete_forever_outlined,
              title: '解散群聊',
              subtitle: '仅群主可操作',
              trailing: '',
              onTap: () =>
                  _run(() => widget.controller.deleteGroup(widget.groupId)),
            ),
            _PlainListTile(
              icon: Icons.delete_sweep_outlined,
              title: '清空聊天',
              subtitle: '只清空自己看到的群聊记录',
              trailing: '',
              onTap: _clearGroupConversation,
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            const _SectionHeader(text: '群成员'),
            FutureBuilder<Map<String, Object?>>(
              key: ValueKey(_version),
              future: widget.controller.groupMembers(widget.groupId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorState(text: snapshot.error.toString());
                }
                final members = _listFromResult(snapshot.data ?? const {});
                if (members.isEmpty) {
                  return const _EmptyRow(text: '暂无成员');
                }
                return Column(
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
          ],
        ),
      ),
    );
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
        ActionInputField(id: 'member_ids', label: '成员用户名', hint: '多个用户名用逗号分隔'),
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
        _version++;
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
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
      appBar: AppBar(title: const Text('我的群聊')),
      body: SafeArea(
        child: _loading && _groups.isEmpty
            ? const Center(child: CircularProgressIndicator())
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
      appBar: AppBar(title: Text(_memberTitle(widget.member))),
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
