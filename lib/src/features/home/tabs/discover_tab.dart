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
            onTap: () => _push(context, MomentsPage(controller: controller)),
          ),
          const _GroupGap(),
          _MenuTile(
            icon: Icons.manage_search,
            iconColor: const Color(0xffff5c5c),
            title: '搜一搜',
            subtitle: '搜索好友、群聊和本地联系人',
            onTap: () => _push(context, SearchPage(controller: controller)),
          ),
        ],
      ),
    );
  }
}
