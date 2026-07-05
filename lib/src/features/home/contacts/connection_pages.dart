part of 'package:bim/src/features/home/home_page.dart';

class ConnectionInfoPage extends StatelessWidget {
  const ConnectionInfoPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return Scaffold(
      appBar: AppBar(title: const Text('消息连接')),
      body: SafeArea(
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
              icon: Icons.ac_unit_outlined,
              iconColor: const Color(0xff5ac8fa),
              title: '冷启动',
              subtitle: _formatTime(controller.lastColdLaunchAt),
              onTap: () {},
            ),
            _MenuTile(
              icon: Icons.replay_circle_filled_outlined,
              iconColor: const Color(0xffff9f0a),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('聊天记录已清空')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class DiagnosticsLogPage extends StatelessWidget {
  const DiagnosticsLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断日志'),
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
      body: SafeArea(
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日志已复制')));
    }
  }
}
