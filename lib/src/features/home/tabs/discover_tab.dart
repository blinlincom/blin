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
      if (!mounted) return;
      final avatar = _latestMomentAvatarFromPayload(data);
      if (avatar != _latestMomentAvatar) {
        setState(() => _latestMomentAvatar = avatar);
      }
    } catch (_) {
      // Keep the cached discovery view available when moments refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BimColors.background,
      child: ListView(
        padding: const EdgeInsets.only(
          top: BimSpacing.x3,
          bottom: BimSpacing.x8,
        ),
        children: [
          _DiscoverPrimaryEntry(
            avatarUrl: _latestMomentAvatar,
            onTap: () =>
                _push(context, MomentsPage(controller: widget.controller)),
          ),
          const _SectionHeader(text: '更多服务'),
          _MenuTile(
            icon: Icons.manage_search,
            iconColor: BimColors.primary,
            title: '搜一搜',
            subtitle: '查找好友、群聊和联系人',
            onTap: () =>
                _push(context, SearchPage(controller: widget.controller)),
          ),
          _MenuTile(
            icon: Icons.qr_code_scanner,
            iconColor: BimColors.textDark,
            title: '扫一扫',
            subtitle: '识别好友、群聊和收付款二维码',
            onTap: () => _push(
              context,
              FriendQrScannerPage(controller: widget.controller),
            ),
          ),
          _MenuTile(
            icon: Icons.currency_exchange_outlined,
            iconColor: BimColors.primary,
            title: 'OTC 买卖',
            subtitle: '通过认证商家买卖数字资产',
            onTap: () =>
                _push(context, OtcHomePage(controller: widget.controller)),
          ),
        ],
      ),
    );
  }
}

class _DiscoverPrimaryEntry extends StatelessWidget {
  const _DiscoverPrimaryEntry({required this.avatarUrl, required this.onTap});

  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimPressable(
      onTap: onTap,
      semanticLabel: '进入朋友圈',
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x4),
        decoration: const BoxDecoration(
          color: BimColors.surface,
          border: Border(bottom: BorderSide(color: BimColors.borderLight)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              color: BimColors.primaryWeak,
              child: const Icon(
                Icons.photo_library_outlined,
                color: BimColors.primary,
                size: 23,
              ),
            ),
            const SizedBox(width: BimSpacing.x3),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '朋友圈',
                    style: TextStyle(
                      color: BimColors.text,
                      fontSize: BimTypography.bodyLarge,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: BimSpacing.x1),
                  Text(
                    '查看朋友分享的最新动态',
                    style: TextStyle(
                      color: BimColors.secondaryText,
                      fontSize: BimTypography.meta,
                    ),
                  ),
                ],
              ),
            ),
            if (avatarUrl.isNotEmpty) ...[
              _Avatar(
                label: '最新动态',
                imageUrl: avatarUrl,
                size: 34,
                color: BimColors.mutedText,
              ),
              const SizedBox(width: BimSpacing.x2),
            ],
            const Icon(
              Icons.chevron_right,
              color: BimColors.mutedText,
              size: 21,
            ),
          ],
        ),
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
    if (avatar.isNotEmpty) return avatar;
  }
  return '';
}

String _discoverMomentAvatar(Map<String, Object?> post) {
  final direct = _avatarUrlFromMap(post);
  if (direct.isNotEmpty) return direct;
  for (final key in const ['user', 'author', 'member', 'profile']) {
    final nested = post[key];
    if (nested is Map) {
      final avatar = _avatarUrlFromMap(nested.cast<String, Object?>());
      if (avatar.isNotEmpty) return avatar;
    }
  }
  return '';
}
