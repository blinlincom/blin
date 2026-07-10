part of 'package:bim/src/features/home/home_page.dart';

class ConnectionInfoPage extends StatelessWidget {
  const ConnectionInfoPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.session;
        return BimScaffold(
          topBar: const BimTopBar(title: '消息与存储'),
          body: BimContentViewport(
            maxWidth: 720,
            child: ListView(
              children: [
                _MenuTile(
                  icon: Icons.phone_android_outlined,
                  iconColor: _primaryColor,
                  title: '设备',
                  subtitle: controller.device,
                  onTap: () {},
                ),
                _MenuTile(
                  icon: Icons.person_outline,
                  iconColor: const Color(0xff7c5cff),
                  title: '当前账号',
                  subtitle: _sessionDisplayName(session),
                  onTap: () {},
                ),
                _MenuTile(
                  icon: Icons.router_outlined,
                  iconColor: const Color(0xff20c997),
                  title: '连接地址',
                  subtitle: _gatewayStreamAddress(session?.chat),
                  onTap: () {},
                ),
                _MenuTile(
                  icon: Icons.notifications_active_outlined,
                  iconColor: BimColors.success,
                  title: '后台消息接收',
                  subtitle: _backgroundReceiveSubtitle(controller),
                  trailing: Switch.adaptive(
                    value: controller.backgroundReceiveProtectionEnabled,
                    onChanged: (value) => unawaited(
                      controller.setBackgroundReceiveProtectionEnabled(value),
                    ),
                  ),
                  onTap: () => _push(
                    context,
                    BackgroundReceiveProtectionPage(controller: controller),
                  ),
                ),
                _MenuTile(
                  icon: Icons.ac_unit_outlined,
                  iconColor: const Color(0xff5ac8fa),
                  title: '冷启动',
                  subtitle: _formatTime(controller.lastColdLaunchAt),
                  onTap: () {},
                ),
                _MenuTile(
                  icon: Icons.replay_circle_filled_outlined,
                  iconColor: BimColors.warning,
                  title: '热启动',
                  subtitle: _formatTime(controller.lastHotResumeAt),
                  onTap: () {},
                ),
                _MenuTile(
                  icon: Icons.bug_report_outlined,
                  iconColor: const Color(0xff5e6ad2),
                  title: '诊断日志',
                  subtitle: '查看接口请求和连接错误',
                  onTap: () => _push(context, const DiagnosticsLogPage()),
                ),
                _MenuTile(
                  icon: Icons.delete_sweep_outlined,
                  iconColor: _dangerColor,
                  title: '清空聊天记录',
                  subtitle: '只清空本账号单聊、群聊和会话列表',
                  onTap: () => _confirmClearAllChats(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _backgroundReceiveSubtitle(SessionController controller) {
    if (!controller.backgroundReceiveProtectionEnabled) {
      return '已关闭，打开应用后补齐离线消息';
    }
    final status = controller.backgroundReceiveStatus;
    if (!status.supported) {
      return status.note.isEmpty ? '当前平台不支持后台常驻' : status.note;
    }
    if (!status.notificationPermissionGranted) {
      return '需要开启通知权限';
    }
    if (!status.batteryOptimizationIgnored) {
      return '建议关闭电池优化';
    }
    return status.serviceRunning ? '后台接收保护运行中' : '等待后台服务启动';
  }

  Future<void> _confirmClearAllChats(BuildContext context) async {
    final confirmed = await _confirmDanger(
      context,
      title: '清空聊天记录',
      content: '将清空本账号在本机和服务端历史同步中的单聊、群聊记录，不影响好友、群资料和其他用户。',
      confirmText: '清空',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      await controller.clearAllChatRecords();
      if (!context.mounted) {
        return;
      }
      showBimSnackBar(context, '聊天记录已清空', tone: BimNoticeTone.success);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      showBimSnackBar(context, error.toString(), tone: BimNoticeTone.error);
    }
  }
}

class BackgroundReceiveProtectionPage extends StatefulWidget {
  const BackgroundReceiveProtectionPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<BackgroundReceiveProtectionPage> createState() =>
      _BackgroundReceiveProtectionPageState();
}

class _BackgroundReceiveProtectionPageState
    extends State<BackgroundReceiveProtectionPage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.refreshBackgroundReceiveStatus());
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final status = controller.backgroundReceiveStatus;
        return BimScaffold(
          topBar: const BimTopBar(title: '消息接收保护'),
          body: BimContentViewport(
            maxWidth: 720,
            child: ListView(
              children: [
                BimSettingsSwitchTile(
                  value: controller.backgroundReceiveProtectionEnabled,
                  onChanged: (value) => unawaited(
                    controller.setBackgroundReceiveProtectionEnabled(value),
                  ),
                  title: '后台接收保护',
                  subtitle: '开启后，Android 会通过前台服务尽量保持消息连接',
                ),
                const _GroupGap(),
                _ProtectionStatusTile(
                  icon: Icons.link_outlined,
                  title: '连接状态',
                  value: controller.imStatusText,
                  ok: controller.imStatusText == '已连接',
                ),
                _ProtectionStatusTile(
                  icon: Icons.notifications_none,
                  title: '通知权限',
                  value: status.supported
                      ? (status.notificationPermissionGranted ? '已开启' : '未开启')
                      : '不适用',
                  ok: !status.supported || status.notificationPermissionGranted,
                  onTap: status.supported
                      ? controller.openBackgroundNotificationSettings
                      : null,
                ),
                _ProtectionStatusTile(
                  icon: Icons.battery_saver_outlined,
                  title: '电池优化',
                  value: status.supported
                      ? (status.batteryOptimizationIgnored ? '已放行' : '可能限制后台')
                      : '不适用',
                  ok: !status.supported || status.batteryOptimizationIgnored,
                  onTap: status.supported
                      ? controller.openBackgroundBatterySettings
                      : null,
                ),
                _ProtectionStatusTile(
                  icon: Icons.memory_outlined,
                  title: '后台服务',
                  value: status.supported
                      ? (status.serviceRunning ? '运行中' : '未运行')
                      : '不支持',
                  ok:
                      !status.supported ||
                      !controller.backgroundReceiveProtectionEnabled ||
                      status.serviceRunning,
                ),
                if (status.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: Text(
                      status.note,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  child: BimButton(
                    label: '重新检测',
                    onPressed: () =>
                        unawaited(controller.refreshBackgroundReceiveStatus()),
                    icon: Icons.refresh,
                    kind: BimButtonKind.secondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProtectionStatusTile extends StatelessWidget {
  const _ProtectionStatusTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.ok,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool ok;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _MenuTile(
      icon: icon,
      iconColor: ok ? BimColors.success : BimColors.warning,
      title: title,
      subtitle: value,
      onTap: onTap ?? () {},
      trailing: Icon(
        ok ? Icons.check_circle_outline : Icons.error_outline,
        color: ok ? BimColors.success : BimColors.warning,
        size: 20,
      ),
    );
  }
}

class DiagnosticsLogPage extends StatelessWidget {
  const DiagnosticsLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: '诊断日志',
        actions: [
          IconButton(
            tooltip: '复制',
            onPressed: () => _copyLogs(context),
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: '清空',
            onPressed: AppLogger.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: BimContentViewport(
        maxWidth: 900,
        child: ValueListenableBuilder<int>(
          valueListenable: AppLogger.revision,
          builder: (context, _, _) {
            final logs = AppLogger.entries.reversed.toList();
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: logs.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 12),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '日志文件',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        AppLogger.filePath.isEmpty
                            ? '日志文件尚未初始化'
                            : AppLogger.filePath,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _mutedColor,
                        ),
                      ),
                      if (logs.isEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('暂无日志'),
                      ],
                    ],
                  );
                }
                final item = logs[index - 1];
                final isError = item.level == 'ERROR';
                final isWarn = item.level == 'WARN';
                return SelectableText(
                  item.line,
                  style: TextStyle(
                    fontSize: 12,
                    color: isError
                        ? _dangerColor
                        : isWarn
                        ? const Color(0xff8a5a00)
                        : _textColor,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _copyLogs(BuildContext context) async {
    final text = await AppLogger.exportText();
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      showBimSnackBar(context, '日志已复制', tone: BimNoticeTone.success);
    }
  }
}
