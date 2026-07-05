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
      _ActionEntry(Icons.qr_code_scanner, '扫一扫', () => _showSoon(context)),
      _ActionEntry(Icons.payments_outlined, '收付款', () => _showSoon(context)),
      _ActionEntry(Icons.note_add_outlined, '新建笔记', () => _showSoon(context)),
      _ActionEntry(Icons.phone_outlined, '语音通话', () => _showSoon(context)),
      _ActionEntry(Icons.videocam_outlined, '视频通话', () => _showSoon(context)),
      _ActionEntry(
        Icons.group_work_outlined,
        '创建群聊',
        () => _push(context, CreateGroupPage(controller: controller)),
      ),
      _ActionEntry(
        Icons.contacts_outlined,
        '通讯录',
        () => Navigator.of(context).pop(),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('快捷操作')),
      body: SafeArea(
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

class _ActionEntry {
  const _ActionEntry(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}
