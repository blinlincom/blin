part of 'package:bim/src/features/home/home_page.dart';

class MineTab extends StatelessWidget {
  const MineTab({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final session = controller.session;
        return ColoredBox(
          color: BimColors.background,
          child: ListView(
            padding: const EdgeInsets.only(bottom: BimSpacing.x8),
            children: [
              _MineIdentitySection(controller: controller, session: session),
              const _SectionHeader(text: '常用服务'),
              _MenuTile(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: BimColors.transfer,
                title: '钱包',
                subtitle: '余额、收付款和账单',
                onTap: () => _push(context, WalletPage(controller: controller)),
              ),
              _MenuTile(
                icon: Icons.photo_library_outlined,
                iconColor: BimColors.success,
                title: '朋友圈',
                subtitle: '查看自己的动态和朋友互动',
                onTap: () =>
                    _push(context, MomentsPage(controller: controller)),
              ),
              _MenuTile(
                icon: Icons.qr_code_scanner,
                iconColor: BimColors.textDark,
                title: '扫一扫',
                subtitle: '识别好友、群聊和收付款二维码',
                onTap: () =>
                    _push(context, FriendQrScannerPage(controller: controller)),
              ),
              const _SectionHeader(text: '账号与应用'),
              _MenuTile(
                icon: Icons.settings_outlined,
                iconColor: BimColors.secondaryText,
                title: '设置与存储',
                subtitle: '聊天记录、消息接收和连接状态',
                onTap: () =>
                    _push(context, ConnectionInfoPage(controller: controller)),
              ),
              if (controller.imError != null)
                _MineConnectionNotice(
                  message: '消息连接暂时异常，点击查看',
                  onTap: controller.clearError,
                ),
              const _SectionHeader(text: '登录状态'),
              BimSettingsTile(
                title: '退出登录',
                tone: BimSettingsTileTone.danger,
                showChevron: false,
                onTap: () => _confirmLogout(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新验证账号，当前设备的会话状态将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出', style: TextStyle(color: BimColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.logout();
    }
  }
}

class _MineIdentitySection extends StatelessWidget {
  const _MineIdentitySection({required this.controller, required this.session});

  final SessionController controller;
  final UserSession? session;

  @override
  Widget build(BuildContext context) {
    final name = _sessionDisplayName(session);
    return Container(
      color: BimColors.surface,
      padding: const EdgeInsets.fromLTRB(
        BimSpacing.x5,
        BimSpacing.x6,
        BimSpacing.x4,
        BimSpacing.x6,
      ),
      child: Row(
        children: [
          _Avatar(
            label: name.isEmpty ? 'B' : name.characters.first,
            imageUrl: session?.avatar ?? '',
            size: 64,
            color: BimColors.mutedText,
          ),
          const SizedBox(width: BimSpacing.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BimColors.textDark,
                    fontSize: BimTypography.profile,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: BimSpacing.x2),
                _MineStatusLine(controller: controller),
                const SizedBox(height: BimSpacing.x1),
                Text(
                  _atName(session?.username ?? ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BimColors.secondaryText,
                    fontSize: BimTypography.meta,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          BimPressable(
            onTap: () => _push(context, MyFriendQrPage(controller: controller)),
            semanticLabel: '我的二维码',
            child: const SizedBox(
              width: BimDimensions.touchTarget,
              height: BimDimensions.touchTarget,
              child: Icon(Icons.qr_code_2, color: BimColors.text, size: 24),
            ),
          ),
          const Icon(Icons.chevron_right, color: BimColors.mutedText, size: 20),
        ],
      ),
    );
  }
}

class _MineConnectionNotice extends StatelessWidget {
  const _MineConnectionNotice({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BimPressable(
      onTap: onTap,
      semanticLabel: message,
      child: Container(
        constraints: const BoxConstraints(minHeight: BimDimensions.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x4),
        color: BimColors.primaryWeak,
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: BimColors.primary, size: 19),
            const SizedBox(width: BimSpacing.x2),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: BimColors.primaryPressed,
                  fontSize: BimTypography.meta,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MineStatusLine extends StatelessWidget {
  const _MineStatusLine({required this.controller});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    final text = _statusText;
    final connected = text == '在线';
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: connected ? BimColors.online : BimColors.mutedText,
        ),
        const SizedBox(width: BimSpacing.x2),
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: BimColors.secondaryText,
            fontSize: BimTypography.caption,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String get _statusText {
    if (controller.imError != null) return '连接异常';
    final status = controller.imStatusText;
    if (status == '已连接') return '在线';
    if (status == '连接中') return '连接中...';
    if (status == '重连中') return '重连中...';
    if (status == '同步中') return '同步中...';
    return status.isEmpty ? '离线' : status;
  }
}
