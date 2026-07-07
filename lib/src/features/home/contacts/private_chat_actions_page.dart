part of 'package:bim/src/features/home/home_page.dart';

class PrivateChatActionsPage extends StatefulWidget {
  const PrivateChatActionsPage({
    required this.controller,
    required this.title,
    required this.receiverId,
    required this.channelId,
    this.avatarUrl = '',
    this.online = false,
    this.burnAfterRead = false,
    this.peerBurnAfterRead = false,
    this.burnSeconds = 0,
    this.peerBurnSeconds = 0,
    this.onBurnChanged,
    this.onStartVoiceCall,
    this.onStartVideoCall,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String receiverId;
  final String channelId;
  final String avatarUrl;
  final bool online;
  final bool burnAfterRead;
  final bool peerBurnAfterRead;
  final int burnSeconds;
  final int peerBurnSeconds;
  final Future<void> Function(bool enabled, int seconds)? onBurnChanged;
  final VoidCallback? onStartVoiceCall;
  final VoidCallback? onStartVideoCall;

  @override
  State<PrivateChatActionsPage> createState() => _PrivateChatActionsPageState();
}

class _PrivateChatActionsPageState extends State<PrivateChatActionsPage> {
  String _message = '';
  String _error = '';
  late bool _burnAfterRead;
  late int _burnSeconds;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _burnAfterRead = widget.burnAfterRead;
    _burnSeconds = widget.burnSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('消息设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ColoredBox(
              color: _surfaceColor,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  children: [
                    InkWell(
                      onTap: _openProfile,
                      child: Row(
                        children: [
                          _Avatar(
                            label: widget.title,
                            imageUrl: widget.avatarUrl,
                            size: 58,
                            color: const Color(0xff8e99a8),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title.isEmpty ? '好友' : widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _textColor,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  widget.online ? '在线' : '离线',
                                  style: const TextStyle(
                                    color: _mutedColor,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: _mutedColor),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _ProfileActionButton(
                            icon: Icons.message_outlined,
                            label: '发消息',
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ProfileActionButton(
                            icon: Icons.call_outlined,
                            label: '语音',
                            onTap: _startVoiceCall,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ProfileActionButton(
                            icon: Icons.videocam_outlined,
                            label: '视频',
                            onTap: _startVideoCall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const _GroupGap(),
            _SettingsSwitchTile(
              title: '阅后即焚',
              subtitle: _burnSubtitle,
              value: _burnAfterRead,
              onChanged: _busy || widget.onBurnChanged == null
                  ? null
                  : _changeBurnAfterRead,
            ),
            _PlainListTile(
              icon: Icons.timer_outlined,
              title: '阅后即焚倒计时',
              subtitle: _burnAfterRead ? '当前 $_burnSeconds 秒' : '开启后可设置',
              trailing: _burnAfterRead ? '设置' : '',
              onTap: _burnAfterRead ? _editBurnSeconds : null,
            ),
            const _GroupGap(),
            _PlainListTile(
              icon: Icons.person_outline,
              title: '查看好友资料',
              subtitle: '昵称、用户名、在线状态',
              trailing: '',
              onTap: _openProfile,
            ),
            _PlainListTile(
              icon: Icons.manage_search,
              title: '好友状态',
              subtitle: '检查好友关系和非好友限制',
              trailing: '',
              onTap: _friendStatus,
            ),
            const _GroupGap(),
            _PlainListTile(
              icon: Icons.delete_outline,
              title: '清空聊天',
              subtitle: '只清空自己看到的单聊记录',
              trailing: '',
              onTap: _deleteConversation,
            ),
            _PlainListTile(
              icon: Icons.person_remove_outlined,
              title: '删除好友',
              subtitle: '删除后重新按非好友规则执行',
              trailing: '',
              onTap: _deleteFriend,
            ),
            if (_busy) const _LinearBusy(),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
          ],
        ),
      ),
    );
  }

  String get _burnSubtitle {
    final parts = <String>[];
    if (_burnAfterRead) {
      parts.add(_burnSeconds > 0 ? '我已开启，$_burnSeconds 秒后焚毁' : '我已开启');
    } else {
      parts.add('关闭');
    }
    if (widget.peerBurnAfterRead) {
      parts.add(
        widget.peerBurnSeconds > 0
            ? '对方已开启 ${widget.peerBurnSeconds} 秒'
            : '对方已开启',
      );
    }
    return parts.join(' · ');
  }

  Future<void> _changeBurnAfterRead(bool value) async {
    final previousEnabled = _burnAfterRead;
    final previousSeconds = _burnSeconds;
    setState(() {
      _busy = true;
      _burnAfterRead = value;
      if (!value) {
        _burnSeconds = 0;
      }
      _message = '';
      _error = '';
    });
    try {
      await widget.onBurnChanged?.call(_burnAfterRead, _burnSeconds);
    } catch (error) {
      setState(() {
        _burnAfterRead = previousEnabled;
        _burnSeconds = previousSeconds;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editBurnSeconds() async {
    final data = await _openInput(
      context,
      title: '阅后即焚倒计时',
      fields: [
        ActionInputField(
          id: 'seconds',
          label: '秒数',
          keyboardType: TextInputType.number,
          initial: _burnSeconds > 0 ? _burnSeconds.toString() : '',
        ),
      ],
    );
    if (data == null) {
      return;
    }
    final seconds = int.tryParse(data['seconds'] ?? '') ?? 0;
    final old = _burnSeconds;
    setState(() {
      _busy = true;
      _burnSeconds = seconds;
      _message = '';
      _error = '';
    });
    try {
      await widget.onBurnChanged?.call(true, _burnSeconds);
    } catch (error) {
      setState(() {
        _burnSeconds = old;
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openProfile() async {
    await _push(
      context,
      FriendProfilePage(
        controller: widget.controller,
        title: widget.title,
        receiverId: widget.receiverId,
        channelId: widget.channelId,
        avatarUrl: widget.avatarUrl,
        online: widget.online,
        onOpenChat: () => Navigator.of(context).maybePop(),
        onStartVoiceCall: _startVoiceCall,
        onStartVideoCall: _startVideoCall,
      ),
    );
  }

  void _startVoiceCall() {
    Navigator.of(context).maybePop();
    widget.onStartVoiceCall?.call();
  }

  void _startVideoCall() {
    Navigator.of(context).maybePop();
    widget.onStartVideoCall?.call();
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

  Future<void> _deleteConversation() async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空聊天记录',
      content: '将清空你自己看到的这个单聊记录和会话，不影响对方。',
      confirmText: '清空',
    );
    if (!confirmed) {
      return;
    }
    await _run(
      () => widget.controller.deletePrivateConversation(
        receiverId: widget.receiverId,
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
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }
}

class FriendProfilePage extends StatefulWidget {
  const FriendProfilePage({
    required this.controller,
    required this.title,
    required this.receiverId,
    required this.channelId,
    this.avatarUrl = '',
    this.online = false,
    this.onOpenChat,
    this.onStartVoiceCall,
    this.onStartVideoCall,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String receiverId;
  final String channelId;
  final String avatarUrl;
  final bool online;
  final VoidCallback? onOpenChat;
  final VoidCallback? onStartVoiceCall;
  final VoidCallback? onStartVideoCall;

  @override
  State<FriendProfilePage> createState() => _FriendProfilePageState();
}

class _FriendProfilePageState extends State<FriendProfilePage> {
  Future<Map<String, Object?>>? _statusFuture;
  String _message = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _statusFuture = widget.controller.friendStatus(widget.receiverId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(title: const Text('好友资料')),
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
                      color: const Color(0xff8e99a8),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title.isEmpty ? '好友' : widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          _PresencePill(online: widget.online),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const _GroupGap(),
            FutureBuilder<Map<String, Object?>>(
              future: _statusFuture,
              builder: (context, snapshot) {
                final status = snapshot.connectionState == ConnectionState.done
                    ? snapshot.data ?? const <String, Object?>{}
                    : const <String, Object?>{};
                final signature = _friendSignatureFromStatus(status);
                final username = _friendUsernameFromStatus(status);
                return Column(
                  children: [
                    _ProfileInfoRow(
                      label: '用户名',
                      value: username.isEmpty ? '未获取' : username,
                    ),
                    _ProfileInfoRow(
                      label: '好友状态',
                      value: _statusText(snapshot),
                    ),
                    _ProfileInfoRow(
                      label: '个性签名',
                      value: signature.isEmpty ? '未设置' : signature,
                    ),
                  ],
                );
              },
            ),
            const _GroupGap(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _openChat,
                      icon: const Icon(Icons.message_outlined),
                      label: const Text('发消息'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 54,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _startVoiceCall,
                      child: const Icon(Icons.call_outlined),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 54,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _startVideoCall,
                      child: const Icon(Icons.videocam_outlined),
                    ),
                  ),
                ],
              ),
            ),
            _ResultBlock(text: _message),
            _ErrorBlock(text: _error),
            const _GroupGap(),
            _PlainListTile(
              icon: Icons.person_remove_outlined,
              title: '删除好友',
              subtitle: '删除后重新按非好友规则执行',
              trailing: '',
              onTap: _deleteFriend,
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(AsyncSnapshot<Map<String, Object?>> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return '正在查询';
    }
    if (snapshot.hasError) {
      return '查询失败';
    }
    return _friendStatusText(snapshot.data ?? const {});
  }

  Future<void> _deleteFriend() async {
    try {
      final result = await widget.controller.deleteFriend(widget.receiverId);
      setState(() {
        _message = _friendlyResult(result);
        _error = '';
      });
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  void _openChat() {
    Navigator.of(context).maybePop();
    widget.onOpenChat?.call();
  }

  void _startVoiceCall() {
    Navigator.of(context).maybePop();
    widget.onStartVoiceCall?.call();
  }

  void _startVideoCall() {
    Navigator.of(context).maybePop();
    widget.onStartVideoCall?.call();
  }
}

String _friendSignatureFromStatus(Map<String, Object?> status) {
  for (final source in [
    status,
    _asObjectMap(status['friend']),
    _asObjectMap(status['user']),
  ]) {
    final value = _value(source, ['signature', 'bio', 'description']);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

String _friendUsernameFromStatus(Map<String, Object?> status) {
  for (final source in [
    status,
    _asObjectMap(status['friend']),
    _asObjectMap(status['user']),
  ]) {
    final value = _value(source, ['username', 'account']);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _fillColor,
          border: Border.all(color: _lightBorderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _primaryColor, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: _textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: const TextStyle(
            color: _textColor,
            fontSize: BimTypography.body,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _mutedColor, fontSize: 12),
        ),
        activeThumbColor: _primaryColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _lightBorderColor)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(
                label,
                style: const TextStyle(color: _mutedColor, fontSize: 14),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresencePill extends StatelessWidget {
  const _PresencePill({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.circle,
          color: online ? _chatOnlineColor : _mutedColor,
          size: 8,
        ),
        const SizedBox(width: 6),
        Text(
          online ? '在线' : '离线',
          style: const TextStyle(color: _mutedColor, fontSize: 12),
        ),
      ],
    );
  }
}
