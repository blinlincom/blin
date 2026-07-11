part of 'package:bim/src/features/home/home_page.dart';

class MyGroupsPage extends StatefulWidget {
  const MyGroupsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<MyGroupsPage> createState() => _MyGroupsPageState();
}

class _MyGroupsPageState extends State<MyGroupsPage> {
  final _search = TextEditingController();
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
    _search.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _openCreateGroup() async {
    await _push(context, CreateGroupPage(controller: widget.controller));
    if (mounted) {
      await _refresh(showLoading: false);
    }
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
    final keyword = _search.text.trim().toLowerCase();
    final visibleGroups = keyword.isEmpty
        ? _groups
        : _groups
              .where((item) {
                final title = _groupTitle(item).toLowerCase();
                final notice = _value(item, [
                  'notice',
                  'description',
                ]).toLowerCase();
                return title.contains(keyword) || notice.contains(keyword);
              })
              .toList(growable: false);
    return BimScaffold(
      topBar: BimTopBar(
        title: '我的群聊',
        actions: [
          IconButton(
            tooltip: '发起群聊',
            onPressed: _openCreateGroup,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading && _groups.isEmpty
          ? const BimLoadingState(label: '正在加载群聊')
          : _error != null && _groups.isEmpty
          ? _ErrorState(text: _error!, onRetry: () => _refresh())
          : RefreshIndicator(
              onRefresh: () => _refresh(showLoading: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: BimSpacing.x6),
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
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索群聊名称或公告',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: keyword.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空搜索',
                                  onPressed: _search.clear,
                                  icon: const Icon(Icons.close, size: 19),
                                ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: BimBreakpoints.horizontalPadding(context),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: BimSectionHeader(
                        text: keyword.isEmpty
                            ? '共 ${_groups.length} 个群聊'
                            : '找到 ${visibleGroups.length} 个群聊',
                      ),
                    ),
                  ),
                  if (visibleGroups.isEmpty)
                    BimEmptyState(
                      title: keyword.isEmpty ? '还没有群聊' : '没有找到相关群聊',
                      message: keyword.isEmpty
                          ? '可以从联系人中选择好友发起群聊'
                          : '请尝试其他群聊名称或公告关键词',
                      icon: Icons.groups_outlined,
                      actionLabel: keyword.isEmpty ? '发起群聊' : '清空搜索',
                      onAction: keyword.isEmpty
                          ? _openCreateGroup
                          : _search.clear,
                    )
                  else
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(BimRadius.sm),
                          child: Column(
                            children: [
                              for (
                                var index = 0;
                                index < visibleGroups.length;
                                index++
                              )
                                BimListTile(
                                  title: _groupTitle(visibleGroups[index]),
                                  subtitle: _value(visibleGroups[index], [
                                    'notice',
                                    'description',
                                  ]),
                                  subtitleMaxLines: 2,
                                  leading: _Avatar(
                                    label: _groupTitle(visibleGroups[index]),
                                    imageUrl: _groupAvatarUrl(
                                      visibleGroups[index],
                                    ),
                                    size: 46,
                                    color: BimColors.primary,
                                    icon: Icons.groups_outlined,
                                  ),
                                  trailing: Text(
                                    '${_intValue(visibleGroups[index], ['member_count', 'members'])}人',
                                    style: const TextStyle(
                                      color: BimColors.mutedText,
                                      fontSize: BimTypography.caption,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  showDivider:
                                      index != visibleGroups.length - 1,
                                  onTap: () => _openGroupChat(
                                    context,
                                    widget.controller,
                                    visibleGroups[index],
                                  ),
                                  onLongPress: () => _push(
                                    context,
                                    GroupDetailPage(
                                      controller: widget.controller,
                                      title: _groupTitle(visibleGroups[index]),
                                      groupId: _groupIdFromItem(
                                        visibleGroups[index],
                                      ),
                                      channelId: _groupChannelId(
                                        visibleGroups[index],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_error != null) BimNoticeBanner(text: '群聊刷新失败：$_error'),
                ],
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
    required this.currentUserRole,
    required this.isSelf,
    super.key,
  });

  final SessionController controller;
  final String groupId;
  final Map<String, Object?> member;
  final int currentUserRole;
  final bool isSelf;

  @override
  State<GroupMemberActionPage> createState() => _GroupMemberActionPageState();
}

class _GroupMemberActionPageState extends State<GroupMemberActionPage> {
  String _message = '';
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final memberId = _memberUserId(widget.member);
    final targetRole = _intValue(widget.member, ['role']);
    final isOwner = widget.currentUserRole == 1;
    final canManage =
        !widget.isSelf &&
        (isOwner || (widget.currentUserRole == 2 && targetRole == 0));
    return BimScaffold(
      topBar: BimTopBar(title: _memberTitle(widget.member)),
      body: BimContentViewport(
        maxWidth: 680,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BimSpacing.x4,
                BimSpacing.x4,
                BimSpacing.x4,
                BimSpacing.x2,
              ),
              child: Row(
                children: [
                  _Avatar(
                    label: _memberTitle(widget.member),
                    imageUrl: _avatarUrlFromMap(widget.member),
                    size: 58,
                  ),
                  const SizedBox(width: BimSpacing.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _memberTitle(widget.member),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: BimSpacing.x1),
                        Text(
                          _memberSubtitle(widget.member),
                          style: const TextStyle(
                            color: BimColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.isSelf)
              _PlainListTile(
                icon: Icons.chat_bubble_outline,
                title: '发送消息',
                subtitle: '进入与该成员的私聊',
                trailing: '',
                onTap: () {
                  final channelId = _uidFromUserId(memberId);
                  Navigator.of(context).push(
                    _chatPageRoute(
                      ChatPage(
                        controller: widget.controller,
                        title: _memberTitle(widget.member),
                        channelId: channelId,
                        groupId: '',
                        channelType: _privateChannelType,
                      ),
                    ),
                  );
                },
              ),
            _PlainListTile(
              icon: Icons.badge_outlined,
              title: '成员',
              subtitle: _memberSubtitle(widget.member),
              trailing: _memberRoleText(widget.member),
            ),
            if (canManage)
              _PlainListTile(
                icon: Icons.volume_off_outlined,
                title: '永久禁言',
                subtitle: '由系统或管理员限制该成员发言',
                trailing: '',
                onTap: () => _mute(memberId, permanent: true),
              ),
            if (canManage)
              _PlainListTile(
                icon: Icons.timer_outlined,
                title: '限时禁言',
                subtitle: '设置禁言秒数和原因',
                trailing: '',
                onTap: () => _mute(memberId, permanent: false),
              ),
            if (canManage)
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
            if (isOwner && targetRole == 0)
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
            if (isOwner && targetRole == 2)
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
            if (isOwner && !widget.isSelf)
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
            if (canManage)
              _PlainListTile(
                icon: Icons.person_remove_outlined,
                title: '移出群聊',
                subtitle: '移出后对方将不再收到本群消息',
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
