part of 'package:bim/src/features/home/home_page.dart';

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
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 20, 26),
              child: Row(
                children: [
                  _Avatar(
                    label: _avatarText(session),
                    size: 68,
                    color: const Color(0xff8e99a8),
                  ),
                  const SizedBox(width: 16),
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
                        Row(
                          children: const [
                            Icon(
                              Icons.check_circle,
                              size: 13,
                              color: Color(0xff36c56f),
                            ),
                            SizedBox(width: 4),
                            Text(
                              '在线',
                              style: TextStyle(
                                color: _mutedColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '账号：${session?.username ?? ''}',
                          style: const TextStyle(color: _mutedColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '二维码',
                    onPressed: () => _showSoon(context),
                    icon: const Icon(Icons.qr_code_2),
                  ),
                ],
              ),
            ),
            _MenuTile(
              icon: Icons.security_outlined,
              iconColor: const Color(0xff20c997),
              title: '服务',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            const _GroupGap(),
            _MenuTile(
              icon: Icons.bookmark_border,
              iconColor: const Color(0xffff3b30),
              title: '收藏',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            _MenuTile(
              icon: Icons.photo_library_outlined,
              iconColor: const Color(0xff34c759),
              title: '朋友圈',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            _MenuTile(
              icon: Icons.wallet_outlined,
              iconColor: _primaryColor,
              title: '卡包',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            _MenuTile(
              icon: Icons.emoji_emotions_outlined,
              iconColor: const Color(0xffffc043),
              title: '表情',
              subtitle: '',
              onTap: () => _showSoon(context),
            ),
            const _GroupGap(),
            _MenuTile(
              icon: Icons.settings_outlined,
              iconColor: _mutedColor,
              title: '设置',
              subtitle: '',
              onTap: () =>
                  _push(context, ConnectionInfoPage(controller: controller)),
            ),
            if (controller.imError != null)
              _MenuTile(
                icon: Icons.error_outline,
                iconColor: _dangerColor,
                title: '连接异常',
                subtitle: controller.imError!,
                onTap: controller.clearError,
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
