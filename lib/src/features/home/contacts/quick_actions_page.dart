part of 'package:bim/src/features/home/home_page.dart';

class QuickActionsPage extends StatelessWidget {
  const QuickActionsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionEntry(
        Icons.groups_outlined,
        '发起群聊',
        () => _push(context, CreateGroupPage(controller: controller)),
      ),
      _ActionEntry(
        Icons.person_add_alt_1,
        '添加朋友',
        () => _push(context, SearchPage(controller: controller)),
      ),
      _ActionEntry(
        Icons.phone_outlined,
        '语音会议',
        () => _startMeeting(context, controller, mediaType: 'audio'),
      ),
      _ActionEntry(
        Icons.videocam_outlined,
        '视频会议',
        () => _startMeeting(context, controller, mediaType: 'video'),
      ),
    ];
    return BimScaffold(
      topBar: const BimTopBar(title: '快捷操作'),
      body: BimContentViewport(
        maxWidth: 680,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: GridView.builder(
            itemCount: actions.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 18,
              crossAxisSpacing: 18,
              mainAxisExtent: 96,
            ),
            itemBuilder: (context, index) {
              final item = actions[index];
              return _ActionCircle(
                icon: item.icon,
                label: item.label,
                onTap: item.onTap,
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<void> _startMeeting(
  BuildContext context,
  SessionController controller, {
  required String mediaType,
}) async {
  final selected = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(
      builder: (_) => _MeetingInvitePickerPage(
        controller: controller,
        mediaType: mediaType,
      ),
    ),
  );
  if (selected == null || selected.isEmpty || !context.mounted) {
    return;
  }
  await _push(
    context,
    LiveKitCallPage.create(
      controller: controller,
      callType: 'meeting',
      mediaType: mediaType,
      title: mediaType == 'video' ? '视频会议' : '语音会议',
      inviteUserIds: selected,
    ),
  );
}

class _MeetingInvitePickerPage extends StatefulWidget {
  const _MeetingInvitePickerPage({
    required this.controller,
    required this.mediaType,
  });

  final SessionController controller;
  final String mediaType;

  @override
  State<_MeetingInvitePickerPage> createState() =>
      _MeetingInvitePickerPageState();
}

class _MeetingInvitePickerPageState extends State<_MeetingInvitePickerPage> {
  late final Future<List<Map<String, Object?>>> _future;
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    _future = widget.controller.loadFriends(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mediaType == 'video' ? '选择视频会议成员' : '选择语音会议成员';
    final selected = _selectedIds.toList(growable: false);
    return BimScaffold(
      topBar: BimTopBar(
        title: title,
        actions: [
          TextButton(
            onPressed: selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(selected),
            child: Text(selected.isEmpty ? '发起' : '发起(${selected.length})'),
          ),
        ],
      ),
      body: BimContentViewport(
        maxWidth: 760,
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const BimLoadingState(label: '正在加载好友');
            }
            if (snapshot.hasError) {
              return _ErrorState(text: snapshot.error.toString());
            }
            final friends = snapshot.data ?? const <Map<String, Object?>>[];
            if (friends.isEmpty) {
              return const _EmptyRow(text: '暂无可邀请好友');
            }
            return ListView.separated(
              itemCount: friends.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final friend = friends[index];
                final userId = _friendUserId(friend);
                final checked = _selectedIds.contains(userId);
                return InkWell(
                  onTap: () => _toggle(userId),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: BimDimensions.contactRow,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    color: _surfaceColor,
                    child: Row(
                      children: [
                        _Avatar(
                          label: _friendTitle(friend),
                          imageUrl: _friendAvatarUrl(friend),
                          size: 38,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _friendTitle(friend),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _textColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _friendSubtitle(friend),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _mutedColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Checkbox(
                          value: checked,
                          onChanged: (_) => _toggle(userId),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _toggle(String userId) {
    if (userId.isEmpty) {
      return;
    }
    setState(() {
      if (!_selectedIds.remove(userId)) {
        _selectedIds.add(userId);
      }
    });
  }
}

class _ActionEntry {
  const _ActionEntry(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
