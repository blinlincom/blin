part of 'package:bim/src/features/home/home_page.dart';

class DiscoverTab extends StatefulWidget {
  const DiscoverTab({required this.controller, super.key});

  final SessionController controller;

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  String _latestMomentAvatar = '';

  @override
  void initState() {
    super.initState();
    _latestMomentAvatar = _latestMomentAvatarFromPosts(
      widget.controller.cachedMomentsFeed(),
    );
    unawaited(_loadLatestMomentAvatar());
  }

  Future<void> _loadLatestMomentAvatar() async {
    try {
      final data = await widget.controller.loadMomentsFeed(page: 1, limit: 5);
      if (!mounted) {
        return;
      }
      final avatar = _latestMomentAvatarFromPayload(data);
      if (avatar != _latestMomentAvatar) {
        setState(() => _latestMomentAvatar = avatar);
      }
    } catch (_) {
      // 发现页入口只展示缓存头像，朋友圈失败不打断主流程。
    }
  }

  @override
  Widget build(BuildContext context) {
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
            trailing: _latestMomentAvatar.isEmpty
                ? null
                : _Avatar(
                    label: '朋友圈',
                    imageUrl: _latestMomentAvatar,
                    size: 28,
                    color: const Color(0xff8e99a8),
                  ),
            onTap: () =>
                _push(context, MomentsPage(controller: widget.controller)),
          ),
          const _GroupGap(),
          _MenuTile(
            icon: Icons.manage_search,
            iconColor: const Color(0xffff5c5c),
            title: '搜一搜',
            subtitle: '搜索好友、群聊和本地联系人',
            onTap: () =>
                _push(context, SearchPage(controller: widget.controller)),
          ),
          _MenuTile(
            icon: Icons.qr_code_scanner,
            iconColor: const Color(0xff111827),
            title: '扫一扫',
            subtitle: '添加好友、收付款',
            onTap: () => _push(
              context,
              FriendQrScannerPage(controller: widget.controller),
            ),
          ),
        ],
      ),
    );
  }
}

String _latestMomentAvatarFromPayload(Map<String, Object?> payload) {
  final raw = payload['list'];
  if (raw is Iterable) {
    return _latestMomentAvatarFromPosts(
      raw
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList(growable: false),
    );
  }
  return '';
}

String _latestMomentAvatarFromPosts(List<Map<String, Object?>> posts) {
  for (final post in posts) {
    final avatar = _discoverMomentAvatar(post);
    if (avatar.isNotEmpty) {
      return avatar;
    }
  }
  return '';
}

String _discoverMomentAvatar(Map<String, Object?> post) {
  final direct = _avatarUrlFromMap(post);
  if (direct.isNotEmpty) {
    return direct;
  }
  for (final key in const ['user', 'author', 'member', 'profile']) {
    final nested = post[key];
    if (nested is Map) {
      final avatar = _avatarUrlFromMap(nested.cast<String, Object?>());
      if (avatar.isNotEmpty) {
        return avatar;
      }
    }
  }
  return '';
}
