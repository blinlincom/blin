import 'package:flutter/material.dart';

import '../../app/session_controller.dart';
import '../../core/app_config.dart';
import '../../core/models.dart';
import '../../im/im_message_types.dart';

const _borderColor = Color(0xffd7dce2);
const _lightBorderColor = Color(0xffedf0f3);
const _fillColor = Color(0xfff6f7f9);
const _mutedColor = Color(0xff69717d);
const _dangerColor = Color(0xffa40000);
const _privateChannelType = 1;
const _groupChannelType = 2;

class HomePage extends StatefulWidget {
  const HomePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      MessagesTab(controller: widget.controller),
      ContactsTab(controller: widget.controller),
      DiscoverTab(controller: widget.controller),
      MineTab(controller: widget.controller),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_title), actions: _actions()),
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _borderColor)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (value) => setState(() => _index = value),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: '消息',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts_outlined),
              activeIcon: Icon(Icons.contacts),
              label: '联系人',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: '发现',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() {
    return [
      if (_index == 1) ...[
        IconButton(
          tooltip: '加好友',
          onPressed: () => _open(AddFriendPage(controller: widget.controller)),
          icon: const Icon(Icons.person_add_alt_1),
        ),
        IconButton(
          tooltip: '好友申请',
          onPressed: () =>
              _open(FriendRequestsPage(controller: widget.controller)),
          icon: const Icon(Icons.inbox_outlined),
        ),
        IconButton(
          tooltip: '建群',
          onPressed: () =>
              _open(CreateGroupPage(controller: widget.controller)),
          icon: const Icon(Icons.group_add_outlined),
        ),
      ],
      IconButton(
        tooltip: '刷新',
        onPressed: () => setState(() {}),
        icon: const Icon(Icons.refresh),
      ),
    ];
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) {
      setState(() {});
    }
  }

  String get _title {
    return switch (_index) {
      0 => '消息',
      1 => '联系人',
      2 => '发现',
      _ => '我的',
    };
  }
}

class MessagesTab extends StatelessWidget {
  const MessagesTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return _AsyncList(
          loader: controller.loadConversations,
          emptyText: '暂无会话',
          header: _ConnectionHeader(
            text: controller.imError == null
                ? controller.imStatusText
                : '${controller.imStatusText} · ${controller.imError}',
          ),
          itemBuilder: (context, item) {
            final title = _conversationTitle(item);
            final content = item['content']?.toString() ?? '';
            final time = item['msg_time']?.toString() ?? '';
            final unread = _intValue(item, ['unread_quantity']);
            final channelId = _value(item, ['channel_id']);
            final channelType = _intValue(item, ['channel_type']);
            return _PlainListTile(
              icon: channelType == _groupChannelType
                  ? Icons.groups_outlined
                  : Icons.person_outline,
              title: title,
              subtitle: content.isEmpty ? '暂无最新消息' : content,
              trailing: unread > 0 ? '$unread' : time,
              onTap: () {
                if (channelId.isEmpty) {
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ChatPage(
                      controller: controller,
                      title: title,
                      channelId: channelId,
                      groupId: _value(item, [
                        'group_id',
                        'id',
                      ], fallback: channelId),
                      channelType: channelType == 0
                          ? _channelTypeFromConversation(item)
                          : channelType,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class ContactsTab extends StatelessWidget {
  const ContactsTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<List<Map<String, Object?>>>>(
      future: Future.wait([controller.loadFriends(), controller.loadGroups()]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(text: snapshot.error.toString());
        }
        final friends = snapshot.data?[0] ?? [];
        final groups = snapshot.data?[1] ?? [];
        return ListView(
          children: [
            const _SectionHeader(text: '操作'),
            _PlainListTile(
              icon: Icons.person_add_alt_1,
              title: '添加好友',
              subtitle: '发送好友申请或查询关系',
              trailing: '',
              onTap: () =>
                  _push(context, AddFriendPage(controller: controller)),
            ),
            _PlainListTile(
              icon: Icons.inbox_outlined,
              title: '好友申请',
              subtitle: '处理收到和发出的申请',
              trailing: '',
              onTap: () =>
                  _push(context, FriendRequestsPage(controller: controller)),
            ),
            _PlainListTile(
              icon: Icons.group_add_outlined,
              title: '创建群聊',
              subtitle: '选择好友或填写用户 ID',
              trailing: '',
              onTap: () =>
                  _push(context, CreateGroupPage(controller: controller)),
            ),
            const _SectionHeader(text: '好友'),
            if (friends.isEmpty) const _EmptyRow(text: '暂无好友'),
            for (final item in friends)
              _PlainListTile(
                icon: Icons.person_outline,
                title: _friendTitle(item),
                subtitle: _value(item, ['signature', 'remark', 'username']),
                trailing: _friendUserId(item),
                onTap: () => _openPrivateChat(context, controller, item),
                onLongPress: () => _push(
                  context,
                  PrivateChatActionsPage(
                    controller: controller,
                    title: _friendTitle(item),
                    receiverId: _friendUserId(item),
                    channelId: _friendChannelId(item),
                  ),
                ),
              ),
            const _SectionHeader(text: '群聊'),
            if (groups.isEmpty) const _EmptyRow(text: '暂无群聊'),
            for (final item in groups)
              _PlainListTile(
                icon: Icons.groups_outlined,
                title: _groupTitle(item),
                subtitle: _value(item, ['notice', 'description']),
                trailing: '${_intValue(item, ['member_count', 'members'])}人',
                onTap: () => _openGroupChat(context, controller, item),
              ),
          ],
        );
      },
    );
  }
}

class DiscoverTab extends StatelessWidget {
  const DiscoverTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const _SectionHeader(text: '常用'),
        _PlainListTile(
          icon: Icons.person_add_alt_1,
          title: '添加朋友',
          subtitle: '搜索用户 ID 并发送好友申请',
          trailing: '',
          onTap: () => _push(context, AddFriendPage(controller: controller)),
        ),
        _PlainListTile(
          icon: Icons.inbox_outlined,
          title: '新的朋友',
          subtitle: '查看和处理好友申请',
          trailing: '',
          onTap: () =>
              _push(context, FriendRequestsPage(controller: controller)),
        ),
        _PlainListTile(
          icon: Icons.group_add_outlined,
          title: '发起群聊',
          subtitle: '选择好友创建群',
          trailing: '',
          onTap: () => _push(context, CreateGroupPage(controller: controller)),
        ),
        _PlainListTile(
          icon: Icons.groups_outlined,
          title: '我的群聊',
          subtitle: '查看已加入的群',
          trailing: '',
          onTap: () => _push(context, MyGroupsPage(controller: controller)),
        ),
      ],
    );
  }
}

class MineTab extends StatelessWidget {
  const MineTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: _borderColor),
                    ),
                    child: Text(
                      _avatarText(session),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session?.nickname.isNotEmpty == true
                              ? session!.nickname
                              : session?.username ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID ${session?.userId ?? ''}',
                          style: const TextStyle(color: _mutedColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _PlainListTile(
              icon: Icons.phone_android_outlined,
              title: '设备',
              subtitle: controller.device,
              trailing: 'App',
            ),
            _PlainListTile(
              icon: Icons.tag_outlined,
              title: 'IM UID',
              subtitle: session?.chat?.uid ?? '',
              trailing: controller.imStatusText,
            ),
            if (controller.imError != null)
              _PlainListTile(
                icon: Icons.error_outline,
                title: '消息错误',
                subtitle: controller.imError!,
                trailing: '',
              ),
            _PlainListTile(
              icon: Icons.router_outlined,
              title: '连接地址',
              subtitle: session?.chat?.route.tcpAddr ?? '',
              trailing: 'TCP',
            ),
            _PlainListTile(
              icon: Icons.ac_unit_outlined,
              title: '冷启动',
              subtitle: _formatTime(controller.lastColdLaunchAt),
              trailing: 'MMKV',
            ),
            _PlainListTile(
              icon: Icons.replay_circle_filled_outlined,
              title: '热启动',
              subtitle: _formatTime(controller.lastHotResumeAt),
              trailing: 'resume',
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: OutlinedButton(
                onPressed: controller.logout,
                child: const Text('退出登录'),
              ),
            ),
          ],
        );
      },
    );
  }

  String _avatarText(UserSession? session) {
    final name = session?.nickname.isNotEmpty == true
        ? session!.nickname
        : session?.username ?? '';
    if (name.isEmpty) {
      return 'B';
    }
    return name.characters.first;
  }
}

class AddFriendPage extends StatefulWidget {
  const AddFriendPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends State<AddFriendPage> {
  final _friendId = TextEditingController();
  final _remark = TextEditingController();
  bool _loading = false;
  String _message = '';
  String _error = '';

  @override
  void dispose() {
    _friendId.dispose();
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加好友')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _friendId,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '好友用户 ID',
                hintText: '例如 900100002',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remark,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '申请备注'),
            ),
            const SizedBox(height: 16),
            _ButtonRow(
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _checkStatus,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('查询关系'),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _apply,
                  icon: const Icon(Icons.send),
                  label: const Text('发送申请'),
                ),
              ],
            ),
            if (_loading) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _checkStatus() async {
    final id = _friendId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '好友用户 ID 不能为空');
      return;
    }
    await _run(() async {
      final result = await widget.controller.friendStatus(id);
      _message = _friendStatusText(result);
    });
  }

  Future<void> _apply() async {
    final id = _friendId.text.trim();
    if (id.isEmpty) {
      setState(() => _error = '好友用户 ID 不能为空');
      return;
    }
    await _run(() async {
      final result = await widget.controller.applyFriend(
        friendId: id,
        remark: _remark.text.trim(),
      );
      _message = _friendlyResult(result, successText: '好友申请已发送');
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      await task();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('好友申请')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: _ButtonRow(
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => _type = 'in'),
                    child: Text(_type == 'in' ? '收到申请' : '收件箱'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => _type = 'out'),
                    child: Text(_type == 'out' ? '发出申请' : '发件箱'),
                  ),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: () => setState(() => _version++),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            Expanded(
              child: FutureBuilder<Map<String, Object?>>(
                key: ValueKey('$_type-$_version'),
                future: widget.controller.friendApplyList(type: _type),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(text: snapshot.error.toString());
                  }
                  final items = _listFromResult(snapshot.data ?? const {});
                  if (items.isEmpty) {
                    return const _EmptyState(text: '暂无申请');
                  }
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final applyId = _value(item, ['apply_id', 'id']);
                      final title = _requestTitle(item, _type);
                      final status = _requestStatus(item);
                      return _PlainListTile(
                        icon: Icons.person_outline,
                        title: title,
                        subtitle:
                            '${_value(item, ['remark', 'handle_msg'])} $status',
                        trailing: applyId,
                        onTap: _type == 'in' && _requestPending(item)
                            ? () => _handle(applyId, true)
                            : null,
                        onLongPress: _type == 'in' && _requestPending(item)
                            ? () => _handle(applyId, false)
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handle(String applyId, bool accept) async {
    if (applyId.isEmpty) {
      setState(() => _error = '申请 ID 为空');
      return;
    }
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
    }
  }
}

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _name = TextEditingController();
  final _notice = TextEditingController();
  final _avatar = TextEditingController();
  final _memberIds = TextEditingController();
  final _selected = <String>{};
  bool _loading = false;
  String _error = '';
  String _message = '';

  @override
  void dispose() {
    _name.dispose();
    _notice.dispose();
    _avatar.dispose();
    _memberIds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('创建群聊')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '群名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notice,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '群公告'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _avatar,
              decoration: const InputDecoration(labelText: '群头像 URL'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memberIds,
              decoration: const InputDecoration(
                labelText: '成员用户 ID',
                hintText: '多个 ID 用逗号分隔',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _create,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('创建'),
            ),
            if (_loading) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            const _SectionHeader(text: '选择好友'),
            FutureBuilder<List<Map<String, Object?>>>(
              future: widget.controller.loadFriends(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final friends = snapshot.data ?? [];
                if (friends.isEmpty) {
                  return const _EmptyRow(text: '暂无好友');
                }
                return Column(
                  children: [
                    for (final item in friends)
                      CheckboxListTile(
                        value: _selected.contains(_friendUserId(item)),
                        onChanged: (checked) {
                          final id = _friendUserId(item);
                          if (id.isEmpty) {
                            return;
                          }
                          setState(() {
                            if (checked == true) {
                              _selected.add(id);
                            } else {
                              _selected.remove(id);
                            }
                          });
                        },
                        title: Text(_friendTitle(item)),
                        subtitle: Text(_friendUserId(item)),
                        controlAffinity: ListTileControlAffinity.leading,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero,
                        ),
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
    final memberIds = <String>{
      ..._selected,
      ..._idsFromText(_memberIds.text),
    }.toList();
    setState(() {
      _loading = true;
      _error = '';
      _message = '';
    });
    try {
      final result = await widget.controller.createGroup(
        name: name,
        memberIds: memberIds,
        avatar: _avatar.text.trim(),
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
              subtitle: '输入用户 ID，同步群订阅者',
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
                        trailing: _memberUserId(member),
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
        ActionInputField(id: 'avatar', label: '群头像 URL'),
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
        ActionInputField(
          id: 'member_ids',
          label: '成员用户 ID',
          hint: '多个 ID 用逗号分隔',
        ),
      ],
    );
    if (data == null) {
      return;
    }
    final ids = _idsFromText(data['member_ids'] ?? '');
    if (ids.isEmpty) {
      setState(() => _error = '成员用户 ID 不能为空');
      return;
    }
    await _run(
      () => widget.controller.addGroupMembers(
        groupId: widget.groupId,
        memberIds: ids,
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

class MyGroupsPage extends StatelessWidget {
  const MyGroupsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的群聊')),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: controller.loadGroups(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _ErrorState(text: snapshot.error.toString());
            }
            final groups = snapshot.data ?? [];
            if (groups.isEmpty) {
              return const _EmptyState(text: '暂无群聊');
            }
            return ListView(
              children: [
                for (final item in groups)
                  _PlainListTile(
                    icon: Icons.groups_outlined,
                    title: _groupTitle(item),
                    subtitle: _value(item, ['notice', 'description']),
                    trailing:
                        '${_intValue(item, ['member_count', 'members'])}人',
                    onTap: () => _openGroupChat(context, controller, item),
                    onLongPress: () => _push(
                      context,
                      GroupDetailPage(
                        controller: controller,
                        title: _groupTitle(item),
                        groupId: _groupIdFromItem(item),
                        channelId: _groupChannelId(item),
                      ),
                    ),
                  ),
              ],
            );
          },
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
              title: '成员 ID',
              subtitle: memberId,
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

class PrivateChatActionsPage extends StatefulWidget {
  const PrivateChatActionsPage({
    required this.controller,
    required this.title,
    required this.receiverId,
    required this.channelId,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String receiverId;
  final String channelId;

  @override
  State<PrivateChatActionsPage> createState() => _PrivateChatActionsPageState();
}

class _PrivateChatActionsPageState extends State<PrivateChatActionsPage> {
  String _message = '';
  String _error = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          children: [
            _PlainListTile(
              icon: Icons.badge_outlined,
              title: '对方用户 ID',
              subtitle: widget.receiverId,
              trailing: '',
            ),
            _PlainListTile(
              icon: Icons.manage_search,
              title: '好友状态',
              subtitle: '查看是否已添加为好友',
              trailing: '',
              onTap: _friendStatus,
            ),
            _PlainListTile(
              icon: Icons.delete_outline,
              title: '清空聊天',
              subtitle: '删除当前设备上的单聊会话',
              trailing: '',
              onTap: () => _deleteConversation(false),
            ),
            _PlainListTile(
              icon: Icons.person_remove_outlined,
              title: '删除好友',
              subtitle: '删除后重新按非好友规则执行',
              trailing: '',
              onTap: _deleteFriend,
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  Future<void> _friendStatus() async {
    try {
      final result = await widget.controller.friendStatus(widget.receiverId);
      setState(() {
        _message = _friendStatusText(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteFriend() async {
    await _run(() => widget.controller.deleteFriend(widget.receiverId));
  }

  Future<void> _deleteConversation(bool deletePeer) async {
    await _run(
      () => widget.controller.deletePrivateConversation(
        receiverId: widget.receiverId,
        deletePeer: deletePeer,
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

class ChatPage extends StatefulWidget {
  const ChatPage({
    required this.controller,
    required this.title,
    required this.channelId,
    required this.groupId,
    required this.channelType,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String channelId;
  final String groupId;
  final int channelType;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _textController = TextEditingController();
  bool _sending = false;
  bool _toolsOpen = false;
  bool _burnAfterRead = false;
  bool _mentionAll = false;
  int _burnSeconds = 0;
  List<String> _mentionUserIds = const [];
  String _replyClientMsgNo = '';
  String _selectedClientMsgNo = '';
  int _selectedMessageSeq = 0;
  Map<String, Object?> _selectedPayload = const {};
  String? _error;
  String _message = '';

  bool get _isGroup => widget.channelType == _groupChannelType;
  String get _groupId =>
      widget.groupId.isEmpty ? widget.channelId : widget.groupId;
  String get _receiverId => _privateReceiverIdFromChannel(widget.channelId);

  @override
  void initState() {
    super.initState();
    _textController.text = widget.controller.readDraft(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    _textController.addListener(() {
      widget.controller.writeDraft(
        channelId: widget.channelId,
        channelType: widget.channelType,
        text: _textController.text,
      );
    });
  }

  @override
  void dispose() {
    widget.controller.writeDraft(
      channelId: widget.channelId,
      channelType: widget.channelType,
      text: _textController.text,
    );
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_isGroup)
            IconButton(
              tooltip: '群设置',
              onPressed: () => _push(
                context,
                GroupDetailPage(
                  controller: widget.controller,
                  title: widget.title,
                  groupId: _groupId,
                  channelId: widget.channelId,
                ),
              ),
              icon: const Icon(Icons.groups_outlined),
            )
          else
            IconButton(
              tooltip: '私聊设置',
              onPressed: () => _push(
                context,
                PrivateChatActionsPage(
                  controller: widget.controller,
                  title: widget.title,
                  receiverId: _receiverId,
                  channelId: widget.channelId,
                ),
              ),
              icon: const Icon(Icons.person_outline),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            return Column(
              children: [
                if (_error != null) _ChatError(text: _error!),
                if (_message.isNotEmpty) _InfoBar(text: _message),
                if (_replyClientMsgNo.isNotEmpty ||
                    _burnAfterRead ||
                    _mentionAll ||
                    _mentionUserIds.isNotEmpty)
                  _ChatOptionBar(text: _optionText(), onClear: _clearOptions),
                if (_selectedClientMsgNo.isNotEmpty)
                  _SelectedMessageBar(
                    onReply: () => setState(() {
                      _replyClientMsgNo = _selectedClientMsgNo;
                      _selectedClientMsgNo = '';
                    }),
                    onReceipt: _queryReceipt,
                    onRecall: _recallSelected,
                    onBurn: _burnSelected,
                    onReceiveRedPacket: _receiveSelectedRedPacket,
                    onReceiveTransfer: _receiveSelectedTransfer,
                    onClear: () => setState(() {
                      _selectedClientMsgNo = '';
                      _selectedPayload = const {};
                    }),
                  ),
                Expanded(
                  child: FutureBuilder<List<Map<String, Object?>>>(
                    future: widget.controller.loadLocalMessages(
                      channelId: widget.channelId,
                      channelType: widget.channelType,
                      groupId: widget.groupId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _ErrorState(text: snapshot.error.toString());
                      }
                      final messages = snapshot.data ?? [];
                      if (messages.isEmpty) {
                        return const _EmptyState(text: '暂无消息');
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final item = messages[index];
                          return _MessageRow(
                            item: item,
                            onLongPress: () => _selectMessage(item),
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_toolsOpen)
                  _ChatToolsPanel(
                    isGroup: _isGroup,
                    onTextOption: _openTextOptions,
                    onImage: () => _sendMedia(ChatContentTypes.image),
                    onEmoji: () => _sendMedia(ChatContentTypes.emoji),
                    onGif: () => _sendMedia(ChatContentTypes.gif),
                    onSticker: () => _sendMedia(ChatContentTypes.sticker),
                    onVoice: () => _sendMedia(ChatContentTypes.voice),
                    onVideo: () => _sendMedia(ChatContentTypes.video),
                    onFile: () => _sendMedia(ChatContentTypes.file),
                    onContactCard: _sendContactCard,
                    onTransfer: _sendTransfer,
                    onRedPacket: _sendRedPacket,
                    onGroupMembers: _isGroup ? _openGroupMembers : null,
                  ),
                _Composer(
                  controller: _textController,
                  sending: _sending,
                  toolsOpen: _toolsOpen,
                  onTools: () => setState(() => _toolsOpen = !_toolsOpen),
                  onSend: _sendText,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _selectMessage(Map<String, Object?> item) {
    setState(() {
      _selectedClientMsgNo = _value(item, ['client_msg_no']);
      _selectedMessageSeq = _intValue(item, ['message_seq']);
      _selectedPayload = _asObjectMap(item['payload']);
      _message = _selectedClientMsgNo.isEmpty ? '当前消息暂不可操作' : '已选中消息';
    });
  }

  Future<void> _sendText() async {
    await _runSending(() async {
      await widget.controller.sendTextMessage(
        channelId: widget.channelId,
        channelType: widget.channelType,
        groupId: widget.groupId,
        text: _textController.text,
        mentionUserIds: _mentionUserIds,
        mentionAll: _mentionAll,
        replyClientMsgNo: _replyClientMsgNo,
        burnAfterRead: _burnAfterRead,
        burnAfterReadSeconds: _burnSeconds,
      );
      _textController.clear();
      _replyClientMsgNo = '';
      _mentionUserIds = const [];
      _mentionAll = false;
      _message = '已发送';
    });
  }

  Future<void> _sendMedia(String contentType) async {
    final fields = _mediaFields(contentType);
    final data = await _openInput(
      context,
      title: _mediaTitle(contentType),
      fields: fields,
    );
    if (data == null) {
      return;
    }
    final url = data['url'] ?? '';
    final filePath = data['file_path'] ?? '';
    final params = Map<String, Object?>.from(data)
      ..remove('url')
      ..remove('file_path');
    if (_burnAfterRead) {
      params['burn_after_read'] = '1';
      if (_burnSeconds > 0) {
        params['burn_after_read_seconds'] = _burnSeconds.toString();
      }
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupMedia(
          groupId: _groupId,
          contentType: contentType,
          url: url,
          filePath: filePath,
          params: params,
        );
      } else {
        await widget.controller.sendPrivateMedia(
          receiverId: _receiverId,
          contentType: contentType,
          url: url,
          filePath: filePath,
          params: params,
        );
      }
      _message = '已发送';
    });
  }

  Future<void> _sendContactCard() async {
    final data = await _openInput(
      context,
      title: '发送名片',
      fields: const [ActionInputField(id: 'card_user_id', label: '名片用户 ID')],
    );
    if (data == null) {
      return;
    }
    final cardUserId = data['card_user_id'] ?? '';
    if (cardUserId.isEmpty) {
      setState(() => _error = '名片用户 ID 不能为空');
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupContactCard(
          groupId: _groupId,
          cardUserId: cardUserId,
        );
      } else {
        await widget.controller.sendPrivateContactCard(
          receiverId: _receiverId,
          cardUserId: cardUserId,
        );
      }
      _message = '已发送';
    });
  }

  Future<void> _sendTransfer() async {
    final data = await _openInput(
      context,
      title: '发送转账',
      fields: [
        const ActionInputField(
          id: 'money',
          label: '金额',
          keyboardType: TextInputType.number,
        ),
        const ActionInputField(
          id: 'asset_type',
          label: '资产类型',
          hint: 'money 或 integral',
          initial: 'money',
        ),
        if (_isGroup)
          const ActionInputField(id: 'receiver_id', label: '指定收款人 ID'),
      ],
    );
    if (data == null) {
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupTransfer(
          groupId: _groupId,
          receiverId: data['receiver_id'] ?? '',
          money: data['money'] ?? '',
          assetType: data['asset_type'] ?? 'money',
        );
      } else {
        await widget.controller.sendPrivateTransfer(
          receiverId: _receiverId,
          money: data['money'] ?? '',
          assetType: data['asset_type'] ?? 'money',
        );
      }
      _message = '已发送';
    });
  }

  Future<void> _sendRedPacket() async {
    final data = await _openInput(
      context,
      title: '发送红包',
      fields: [
        const ActionInputField(
          id: 'money',
          label: '金额',
          keyboardType: TextInputType.number,
        ),
        const ActionInputField(
          id: 'asset_type',
          label: '资产类型',
          hint: 'money 或 integral',
          initial: 'money',
        ),
        const ActionInputField(id: 'remark', label: '备注'),
        if (_isGroup)
          const ActionInputField(
            id: 'packet_type',
            label: '红包类型',
            hint: 'ordinary、luck、specified',
            initial: 'ordinary',
          ),
        if (_isGroup)
          const ActionInputField(
            id: 'quantity',
            label: '份数',
            keyboardType: TextInputType.number,
            initial: '1',
          ),
        if (_isGroup)
          const ActionInputField(id: 'receiver_id', label: '指定接收人 ID'),
      ],
    );
    if (data == null) {
      return;
    }
    await _runSending(() async {
      if (_isGroup) {
        await widget.controller.sendGroupRedPacket(
          groupId: _groupId,
          money: data['money'] ?? '',
          assetType: data['asset_type'] ?? 'money',
          packetType: data['packet_type'] ?? 'ordinary',
          quantity: int.tryParse(data['quantity'] ?? '') ?? 1,
          receiverId: data['receiver_id'] ?? '',
          remark: data['remark'] ?? '',
        );
      } else {
        await widget.controller.sendPrivateRedPacket(
          receiverId: _receiverId,
          money: data['money'] ?? '',
          assetType: data['asset_type'] ?? 'money',
          remark: data['remark'] ?? '',
        );
      }
      _message = '已发送';
    });
  }

  Future<void> _openTextOptions() async {
    final data = await _openInput(
      context,
      title: '文本选项',
      fields: [
        if (_isGroup)
          ActionInputField(
            id: 'mention_user_ids',
            label: '@成员 ID',
            hint: '多个 ID 用逗号分隔',
            initial: _mentionUserIds.join(','),
          ),
        if (_isGroup)
          ActionInputField(
            id: 'mention_all',
            label: '@所有人',
            hint: '填 1 表示开启',
            initial: _mentionAll ? '1' : '',
          ),
        ActionInputField(
          id: 'burn_after_read',
          label: '阅后即焚',
          hint: '填 1 表示开启',
          initial: _burnAfterRead ? '1' : '',
        ),
        ActionInputField(
          id: 'burn_after_read_seconds',
          label: '倒计时秒数',
          keyboardType: TextInputType.number,
          initial: _burnSeconds > 0 ? _burnSeconds.toString() : '',
        ),
      ],
    );
    if (data == null) {
      return;
    }
    setState(() {
      _mentionUserIds = _idsFromText(data['mention_user_ids'] ?? '');
      _mentionAll = (data['mention_all'] ?? '') == '1';
      _burnAfterRead = (data['burn_after_read'] ?? '') == '1';
      _burnSeconds = int.tryParse(data['burn_after_read_seconds'] ?? '') ?? 0;
    });
  }

  Future<void> _queryReceipt() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      await widget.controller.readReceipt(
        targetClientMsgNo: _selectedClientMsgNo,
        messageSeq: _selectedMessageSeq,
      );
      final status = await widget.controller.receiptStatus(
        _selectedClientMsgNo,
      );
      _message = _receiptText(status, isGroup: _isGroup);
    });
  }

  Future<void> _recallSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.recallMessage(
        targetClientMsgNo: _selectedClientMsgNo,
      );
      _message = _friendlyResult(result, successText: '消息已撤回');
    });
  }

  Future<void> _burnSelected() async {
    if (_selectedClientMsgNo.isEmpty) {
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.burnAfterRead(
        _selectedClientMsgNo,
      );
      _message = _friendlyResult(result, successText: '已触发阅后即焚');
    });
  }

  Future<void> _receiveSelectedRedPacket() async {
    final id = _nestedValue(_selectedPayload, [
      'red_packet.red_packet_id',
      'red_packet_id',
    ]);
    if (id.isEmpty) {
      setState(() => _error = '当前消息没有红包 ID');
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.receiveRedPacket(
        redPacketId: id,
        group: _isGroup,
      );
      _message = _friendlyResult(result, successText: '红包已领取');
    });
  }

  Future<void> _receiveSelectedTransfer() async {
    final id = _nestedValue(_selectedPayload, [
      'transfer.transfer_id',
      'transfer_id',
    ]);
    if (id.isEmpty) {
      setState(() => _error = '当前消息没有转账 ID');
      return;
    }
    await _runAction(() async {
      final result = await widget.controller.receiveTransfer(id);
      _message = _friendlyResult(result, successText: '转账已收款');
    });
  }

  Future<void> _openGroupMembers() async {
    await _push(
      context,
      GroupDetailPage(
        controller: widget.controller,
        title: widget.title,
        groupId: _groupId,
        channelId: widget.channelId,
      ),
    );
  }

  Future<void> _runSending(Future<void> Function() task) async {
    setState(() {
      _sending = true;
      _error = null;
      _message = '';
    });
    try {
      await task();
      await widget.controller.loadConversations();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _runAction(Future<void> Function() task) async {
    setState(() {
      _error = null;
      _message = '';
    });
    try {
      await task();
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _clearOptions() {
    setState(() {
      _replyClientMsgNo = '';
      _mentionUserIds = const [];
      _mentionAll = false;
      _burnAfterRead = false;
      _burnSeconds = 0;
    });
  }

  String _optionText() {
    final parts = <String>[];
    if (_replyClientMsgNo.isNotEmpty) {
      parts.add('引用 ${_shortNo(_replyClientMsgNo)}');
    }
    if (_mentionAll) {
      parts.add('@所有人');
    }
    if (_mentionUserIds.isNotEmpty) {
      parts.add('@${_mentionUserIds.join(',')}');
    }
    if (_burnAfterRead) {
      parts.add(_burnSeconds > 0 ? '阅后即焚 ${_burnSeconds}s' : '阅后即焚');
    }
    return parts.join(' · ');
  }
}

class ActionInputField {
  const ActionInputField({
    required this.id,
    required this.label,
    this.hint = '',
    this.initial = '',
    this.keyboardType,
    this.maxLines = 1,
  });

  final String id;
  final String label;
  final String hint;
  final String initial;
  final TextInputType? keyboardType;
  final int maxLines;
}

class ActionInputPage extends StatefulWidget {
  const ActionInputPage({required this.title, required this.fields, super.key});

  final String title;
  final List<ActionInputField> fields;

  @override
  State<ActionInputPage> createState() => _ActionInputPageState();
}

class _ActionInputPageState extends State<ActionInputPage> {
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      _controllers[field.id] = TextEditingController(text: field.initial);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final field in widget.fields) ...[
              TextField(
                controller: _controllers[field.id],
                keyboardType: field.keyboardType,
                maxLines: field.maxLines,
                decoration: InputDecoration(
                  labelText: field.label,
                  hintText: field.hint.isEmpty ? null : field.hint,
                ),
              ),
              const SizedBox(height: 12),
            ],
            _ButtonRow(
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _controllers.map(
                        (key, value) => MapEntry(key, value.text.trim()),
                      ),
                    );
                  },
                  child: const Text('确定'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AsyncList extends StatelessWidget {
  const _AsyncList({
    required this.loader,
    required this.itemBuilder,
    required this.emptyText,
    this.header,
  });

  final Future<List<Map<String, Object?>>> Function() loader;
  final Widget Function(BuildContext context, Map<String, Object?> item)
  itemBuilder;
  final String emptyText;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, Object?>>>(
      future: loader(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ErrorState(text: snapshot.error.toString());
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return Column(
            children: [
              if (header != null) header!,
              Expanded(child: _EmptyState(text: emptyText)),
            ],
          );
        }
        return ListView.builder(
          itemCount: items.length + (header == null ? 0 : 1),
          itemBuilder: (context, index) {
            if (header != null && index == 0) {
              return header!;
            }
            final itemIndex = header == null ? index : index - 1;
            return itemBuilder(context, items[itemIndex]);
          },
        );
      },
    );
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: _fillColor,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _mutedColor, fontSize: 13),
      ),
    );
  }
}

class _PlainListTile extends StatelessWidget {
  const _PlainListTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.icon,
    this.onTap,
    this.onLongPress,
  });

  final IconData? icon;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: ListTile(
        leading: icon == null ? null : Icon(icon, color: _mutedColor),
        onTap: onTap,
        onLongPress: onLongPress,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: trailing.isEmpty
            ? null
            : Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _mutedColor),
              ),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({required this.item, required this.onLongPress});

  final Map<String, Object?> item;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isMe = item['is_me'] == true;
    final text = item['content']?.toString() ?? '';
    final time = item['timestamp']?.toString() ?? '';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: _borderColor),
            color: isMe ? const Color(0xffeef5ff) : Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMe && _value(item, ['from_uid']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _value(item, ['from_uid']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _mutedColor, fontSize: 12),
                  ),
                ),
              Text(text.isEmpty ? '[消息]' : text),
              if (time.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    time,
                    style: const TextStyle(color: _mutedColor, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedMessageBar extends StatelessWidget {
  const _SelectedMessageBar({
    required this.onReply,
    required this.onReceipt,
    required this.onRecall,
    required this.onBurn,
    required this.onReceiveRedPacket,
    required this.onReceiveTransfer,
    required this.onClear,
  });

  final VoidCallback onReply;
  final VoidCallback onReceipt;
  final VoidCallback onRecall;
  final VoidCallback onBurn;
  final VoidCallback onReceiveRedPacket;
  final VoidCallback onReceiveTransfer;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: _fillColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('已选中消息'),
          _MiniButton(label: '引用', onTap: onReply),
          _MiniButton(label: '已读', onTap: onReceipt),
          _MiniButton(label: '撤回', onTap: onRecall),
          _MiniButton(label: '焚毁', onTap: onBurn),
          _MiniButton(label: '领红包', onTap: onReceiveRedPacket),
          _MiniButton(label: '收转账', onTap: onReceiveTransfer),
          IconButton(
            tooltip: '取消选择',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ChatOptionBar extends StatelessWidget {
  const _ChatOptionBar({required this.text, required this.onClear});

  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xfffffbeb),
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xff785800)),
            ),
          ),
          IconButton(
            tooltip: '清除选项',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ChatToolsPanel extends StatelessWidget {
  const _ChatToolsPanel({
    required this.isGroup,
    required this.onTextOption,
    required this.onImage,
    required this.onEmoji,
    required this.onGif,
    required this.onSticker,
    required this.onVoice,
    required this.onVideo,
    required this.onFile,
    required this.onContactCard,
    required this.onTransfer,
    required this.onRedPacket,
    this.onGroupMembers,
  });

  final bool isGroup;
  final VoidCallback onTextOption;
  final VoidCallback onImage;
  final VoidCallback onEmoji;
  final VoidCallback onGif;
  final VoidCallback onSticker;
  final VoidCallback onVoice;
  final VoidCallback onVideo;
  final VoidCallback onFile;
  final VoidCallback onContactCard;
  final VoidCallback onTransfer;
  final VoidCallback onRedPacket;
  final VoidCallback? onGroupMembers;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ToolItem(Icons.tune, '文本选项', onTextOption),
      _ToolItem(Icons.image_outlined, '图片', onImage),
      _ToolItem(Icons.emoji_emotions_outlined, '表情', onEmoji),
      _ToolItem(Icons.gif_box_outlined, 'GIF', onGif),
      _ToolItem(Icons.sticky_note_2_outlined, '贴纸', onSticker),
      _ToolItem(Icons.keyboard_voice_outlined, '语音', onVoice),
      _ToolItem(Icons.videocam_outlined, '视频', onVideo),
      _ToolItem(Icons.attach_file, '文件', onFile),
      _ToolItem(Icons.contact_page_outlined, '名片', onContactCard),
      _ToolItem(Icons.payments_outlined, '转账', onTransfer),
      _ToolItem(Icons.redeem_outlined, '红包', onRedPacket),
      if (isGroup && onGroupMembers != null)
        _ToolItem(Icons.groups_outlined, '群成员', onGroupMembers!),
    ];
    return Container(
      height: 210,
      decoration: const BoxDecoration(
        color: _fillColor,
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: items.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 64,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            onTap: item.onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: _borderColor),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, size: 22),
                  const SizedBox(height: 4),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolItem {
  const _ToolItem(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.toolsOpen,
    required this.onTools,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool toolsOpen;
  final VoidCallback onTools;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            IconButton(
              tooltip: toolsOpen ? '收起' : '更多',
              onPressed: onTools,
              icon: Icon(toolsOpen ? Icons.close : Icons.add),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(hintText: '输入消息'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '发送',
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(label),
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 10, runSpacing: 10, children: children);
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: _borderColor)),
      child: SelectableText(text),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      color: const Color(0xffffeeee),
      child: Text(text, style: const TextStyle(color: _dangerColor)),
    );
  }
}

class _ChatError extends StatelessWidget {
  const _ChatError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xffffeeee),
      child: Text(text, style: const TextStyle(color: _dangerColor)),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      color: const Color(0xffeef5ff),
      child: Text(text, maxLines: 5, overflow: TextOverflow.ellipsis),
    );
  }
}

class _LinearBusy extends StatelessWidget {
  const _LinearBusy();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 12),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: _fillColor,
      child: Text(
        text,
        style: const TextStyle(
          color: _mutedColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _lightBorderColor)),
      ),
      child: Text(text, style: const TextStyle(color: _mutedColor)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: _mutedColor)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _dangerColor),
        ),
      ),
    );
  }
}

Future<Map<String, String>?> _openInput(
  BuildContext context, {
  required String title,
  required List<ActionInputField> fields,
}) {
  return Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(
      builder: (_) => ActionInputPage(title: title, fields: fields),
    ),
  );
}

Future<void> _push(BuildContext context, Widget page) {
  return Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}

void _openPrivateChat(
  BuildContext context,
  SessionController controller,
  Map<String, Object?> item,
) {
  final channelId = _friendChannelId(item);
  if (channelId.isEmpty) {
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatPage(
        controller: controller,
        title: _friendTitle(item),
        channelId: channelId,
        groupId: '',
        channelType: _privateChannelType,
      ),
    ),
  );
}

void _openGroupChat(
  BuildContext context,
  SessionController controller,
  Map<String, Object?> item,
) {
  final groupId = _groupIdFromItem(item);
  final channelId = _groupChannelId(item);
  if (channelId.isEmpty) {
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatPage(
        controller: controller,
        title: _groupTitle(item),
        channelId: channelId,
        groupId: groupId,
        channelType: _groupChannelType,
      ),
    ),
  );
}

String _formatTime(int millis) {
  if (millis <= 0) {
    return '暂无';
  }
  final time = DateTime.fromMillisecondsSinceEpoch(millis);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _friendlyResult(
  Map<String, Object?> result, {
  String successText = '操作成功',
}) {
  final message = _value(result, ['message', 'msg']);
  if (message.isNotEmpty) {
    return message;
  }
  final data = result['data'];
  if (data is Map) {
    final nested = _value(
      data.map((key, value) => MapEntry(key.toString(), value)),
      ['message', 'msg'],
    );
    if (nested.isNotEmpty) {
      return nested;
    }
  }
  return successText;
}

String _friendStatusText(Map<String, Object?> result) {
  final isFriend = _boolValue(result['is_friend']);
  final pendingOut = _boolValue(result['pending_out_apply']);
  final pendingIn = _boolValue(result['pending_in_apply']);
  final count = _intValue(result, ['non_friend_message_count']);
  final limit = _intValue(result, ['non_friend_message_limit']);
  if (isFriend) {
    return '你们已经是好友，可以正常聊天。';
  }
  if (pendingOut) {
    return '好友申请已发送，等待对方通过。';
  }
  if (pendingIn) {
    return '对方已申请添加你为好友，请到新的朋友里处理。';
  }
  final max = limit <= 0 ? 3 : limit;
  return '还不是好友，只能先发送文字消息，当前已发送 $count/$max 条。';
}

String _receiptText(Map<String, Object?> result, {required bool isGroup}) {
  final receipt = _asObjectMap(result['receipt']);
  final redPacket = _asObjectMap(result['red_packet']);
  final transfer = _asObjectMap(result['transfer']);
  final parts = <String>[];
  final readCount = _intValue(receipt, ['read_count']);
  final unreadCount = _intValue(receipt, ['unread_count']);
  final total = _intValue(receipt, ['total_receivers']);
  if (isGroup) {
    if (total > 0) {
      parts.add('$readCount/$total 人已读');
    } else {
      parts.add('$readCount 人已读');
    }
  } else {
    parts.add(readCount > 0 ? '对方已读' : '对方未读');
  }
  if (unreadCount > 0 && isGroup) {
    parts.add('$unreadCount 人未读');
  }
  if (redPacket.isNotEmpty) {
    final receiveCount = _intValue(redPacket, ['receive_count']);
    final quantity = _intValue(redPacket, ['quantity']);
    final status = _value(redPacket, ['status']);
    final progress = quantity > 0 ? '$receiveCount/$quantity' : '$receiveCount';
    parts.add('红包领取 $progress${status.isEmpty ? '' : ' · $status'}');
  }
  if (transfer.isNotEmpty) {
    final status = _value(transfer, ['status']);
    parts.add(status.isEmpty ? '转账待处理' : '转账$status');
  }
  return parts.join('\n');
}

String _conversationTitle(Map<String, Object?> item) {
  if (_channelTypeFromConversation(item) == _groupChannelType) {
    return _value(item, ['name', 'group_name'], fallback: '群聊');
  }
  return _value(item, ['nickname', 'username', 'name'], fallback: '私聊');
}

int _channelTypeFromConversation(Map<String, Object?> item) {
  final value = _intValue(item, ['channel_type']);
  if (value > 0) {
    return value;
  }
  return item['conversation_type']?.toString() == 'group'
      ? _groupChannelType
      : _privateChannelType;
}

String _friendTitle(Map<String, Object?> item) {
  return _value(item, [
    'nickname',
    'remark',
    'username',
    'name',
  ], fallback: '好友');
}

String _friendUserId(Map<String, Object?> item) {
  final raw = _value(item, ['userid', 'user_id', 'friend_id', 'id']);
  if (raw.isNotEmpty) {
    return raw;
  }
  return _privateReceiverIdFromChannel(_value(item, ['uid', 'channel_id']));
}

String _friendChannelId(Map<String, Object?> item) {
  final channelId = _value(item, ['channel_id', 'uid', 'im_uid']);
  if (channelId.isNotEmpty) {
    return channelId;
  }
  final userId = _friendUserId(item);
  if (userId.isEmpty) {
    return '';
  }
  return _uidFromUserId(userId);
}

String _groupTitle(Map<String, Object?> item) {
  return _value(item, ['name', 'group_name', 'title'], fallback: '群聊');
}

String _groupIdFromItem(Map<String, Object?> item) {
  return _value(item, ['group_id', 'id']);
}

String _groupChannelId(Map<String, Object?> item) {
  return _value(item, ['channel_id', 'uid'], fallback: _groupIdFromItem(item));
}

String _memberTitle(Map<String, Object?> item) {
  return _value(item, ['nickname', 'username', 'name'], fallback: '群成员');
}

String _memberUserId(Map<String, Object?> item) {
  final value = _value(item, ['user_id', 'userid', 'member_id', 'id']);
  if (value.isNotEmpty) {
    return value;
  }
  return _privateReceiverIdFromChannel(_value(item, ['uid']));
}

String _memberSubtitle(Map<String, Object?> item) {
  final parts = [_memberRoleText(item)];
  final muted = _boolValue(item['muted']);
  if (muted) {
    final permanent = _boolValue(item['mute_permanent']);
    final expire = _value(item, ['mute_expire_time']);
    parts.add(permanent ? '永久禁言' : '禁言至 $expire');
  }
  return parts.where((part) => part.isNotEmpty).join(' · ');
}

String _memberRoleText(Map<String, Object?> item) {
  final role = _intValue(item, ['role']);
  return switch (role) {
    1 => '群主',
    2 => '管理员',
    _ => '成员',
  };
}

String _requestTitle(Map<String, Object?> item, String type) {
  if (type == 'in') {
    return _value(item, [
      'from_nickname',
      'from_username',
      'nickname',
      'username',
      'from_user_id',
    ], fallback: '申请人');
  }
  return _value(item, [
    'to_nickname',
    'to_username',
    'nickname',
    'username',
    'to_user_id',
  ], fallback: '接收人');
}

String _requestStatus(Map<String, Object?> item) {
  final status = _value(item, ['status']);
  return switch (status) {
    '0' => '待处理',
    '1' => '已通过',
    '2' => '已拒绝',
    '3' => '已过期',
    _ => status.isEmpty ? '待处理' : status,
  };
}

bool _requestPending(Map<String, Object?> item) {
  final status = _value(item, ['status']);
  return status.isEmpty || status == '0' || status == 'pending';
}

String _value(
  Map<String, Object?> item,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = item[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return fallback;
}

int _intValue(Map<String, Object?> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed;
    }
  }
  return 0;
}

bool _boolValue(Object? value) {
  final text = value?.toString().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}

Map<String, Object?> _asObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<Map<String, Object?>> _listFromResult(Map<String, Object?> result) {
  Object? value = result['list'] ?? result['items'];
  final data = result['data'];
  if (value == null && data is Map) {
    value = data['list'] ?? data['items'];
  }
  if (value is List) {
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList();
  }
  return const [];
}

List<String> _idsFromText(String text) {
  return text
      .split(RegExp(r'[,，\s]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
}

String _uidFromUserId(String userId) {
  if (userId.startsWith('app')) {
    return userId;
  }
  return 'app${AppConfig.appId}user$userId';
}

String _privateReceiverIdFromChannel(String channelId) {
  final match = RegExp(r'user(\d+)$').firstMatch(channelId);
  return match?.group(1) ?? channelId;
}

String _nestedValue(Map<String, Object?> payload, List<String> paths) {
  for (final path in paths) {
    Object? current = payload;
    for (final key in path.split('.')) {
      if (current is Map) {
        current = current[key];
      } else {
        current = null;
      }
    }
    if (current != null && current.toString().isNotEmpty) {
      return current.toString();
    }
  }
  return '';
}

String _shortNo(String value) {
  if (value.length <= 10) {
    return value;
  }
  return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
}

String _mediaTitle(String contentType) {
  return switch (contentType) {
    ChatContentTypes.image => '发送图片',
    ChatContentTypes.emoji => '发送表情',
    ChatContentTypes.gif => '发送 GIF',
    ChatContentTypes.sticker => '发送贴纸',
    ChatContentTypes.voice => '发送语音',
    ChatContentTypes.video => '发送视频',
    ChatContentTypes.file => '发送文件',
    _ => '发送媒体',
  };
}

List<ActionInputField> _mediaFields(String contentType) {
  final fields = <ActionInputField>[
    const ActionInputField(id: 'url', label: '资源 URL'),
    const ActionInputField(id: 'file_path', label: '本地文件路径'),
  ];
  switch (contentType) {
    case ChatContentTypes.emoji:
      fields.add(const ActionInputField(id: 'emoji_code', label: '表情编码'));
      break;
    case ChatContentTypes.sticker:
      fields.add(const ActionInputField(id: 'sticker_id', label: '贴纸 ID'));
      break;
    case ChatContentTypes.voice:
      fields.add(
        const ActionInputField(
          id: 'duration',
          label: '时长秒数',
          keyboardType: TextInputType.number,
        ),
      );
      break;
    case ChatContentTypes.video:
      fields
        ..add(const ActionInputField(id: 'cover_url', label: '封面 URL'))
        ..add(
          const ActionInputField(
            id: 'duration',
            label: '时长秒数',
            keyboardType: TextInputType.number,
          ),
        );
      break;
    case ChatContentTypes.file:
      fields
        ..add(const ActionInputField(id: 'name', label: '文件名'))
        ..add(const ActionInputField(id: 'mime', label: 'MIME 类型'))
        ..add(
          const ActionInputField(
            id: 'size',
            label: '文件大小',
            keyboardType: TextInputType.number,
          ),
        );
      break;
  }
  return fields;
}
