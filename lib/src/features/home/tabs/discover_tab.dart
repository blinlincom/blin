part of 'package:bim/src/features/home/home_page.dart';

class DiscoverTab extends StatelessWidget {
  const DiscoverTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final session = controller.session;
    return ColoredBox(
      color: _pageColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
        children: [
          _MenuTile(
            icon: Icons.camera_alt_outlined,
            iconColor: const Color(0xff45c463),
            title: '朋友圈',
            subtitle: '',
            trailing: _Avatar(
              label: _sessionDisplayName(session),
              imageUrl: session?.avatar ?? '',
              size: 28,
              color: const Color(0xff8e99a8),
              circle: true,
            ),
            onTap: () => _showSoon(context),
          ),
          const _GroupGap(),
          _MenuTile(
            icon: Icons.crop_free,
            iconColor: const Color(0xff2f80ed),
            title: '扫一扫',
            subtitle: '',
            onTap: () => _showSoon(context),
          ),
          _MenuTile(
            icon: Icons.vibration_outlined,
            iconColor: const Color(0xff3d8bff),
            title: '摇一摇',
            subtitle: '',
            onTap: () => _showSoon(context),
          ),
          const _GroupGap(),
          _MenuTile(
            icon: Icons.explore_outlined,
            iconColor: const Color(0xffffb020),
            title: '看一看',
            subtitle: '',
            onTap: () => _showSoon(context),
          ),
          _MenuTile(
            icon: Icons.manage_search,
            iconColor: const Color(0xffff5c5c),
            title: '搜一搜',
            subtitle: '',
            onTap: () => _push(context, SearchPage(controller: controller)),
          ),
          const _GroupGap(),
          _MenuTile(
            icon: Icons.people_outline,
            iconColor: const Color(0xff3d8bff),
            title: '附近的人',
            subtitle: '',
            onTap: () => _showSoon(context),
          ),
          const _GroupGap(),
          _MenuTile(
            icon: Icons.sports_esports_outlined,
            iconColor: const Color(0xff45c463),
            title: '游戏',
            subtitle: '',
            onTap: () => _showSoon(context),
          ),
          const _GroupGap(),
          _MenuTile(
            icon: Icons.widgets_outlined,
            iconColor: const Color(0xff8a68ff),
            title: '小程序',
            subtitle: '',
            onTap: () => _showSoon(context),
          ),
        ],
      ),
    );
  }
}
