part of 'package:bim/src/features/home/home_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  Future<WalletBalance>? _request;

  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadWalletBalance(refresh: true);
  }

  Future<void> _openPayPassword() async {
    await _push(context, WalletPayPasswordPage(controller: widget.controller));
    if (mounted) {
      setState(() {
        _request = widget.controller.loadWalletBalance(refresh: true);
      });
    }
  }

  Future<void> _openSecuritySettings() async {
    await _push(context, WalletSecurityPage(controller: widget.controller));
    if (mounted) {
      setState(() {
        _request = widget.controller.loadWalletBalance(refresh: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: '钱包',
        actions: [
          IconButton(
            tooltip: '账单',
            onPressed: () =>
                _push(context, WalletBillsPage(controller: widget.controller)),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: FutureBuilder<WalletBalance>(
        future: _request,
        initialData: widget.controller.walletBalance,
        builder: (context, snapshot) {
          final balance =
              snapshot.data ??
              widget.controller.walletBalance ??
              const WalletBalance();
          return RefreshIndicator(
            onRefresh: () async {
              final request = widget.controller.loadWalletBalance(
                refresh: true,
              );
              setState(() => _request = request);
              await request;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                BimBreakpoints.horizontalPadding(context),
                BimSpacing.x4,
                BimBreakpoints.horizontalPadding(context),
                BimSpacing.x8,
              ),
              children: [
                BimContentViewport(
                  maxWidth: 720,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WalletAssetStage(
                        balance: balance,
                        onPayReceive: () => _push(
                          context,
                          WalletPayReceivePage(controller: widget.controller),
                        ),
                        onBills: () => _push(
                          context,
                          WalletBillsPage(controller: widget.controller),
                        ),
                      ),
                      if (!balance.securityBound ||
                          !balance.payPasswordSet ||
                          balance.payPasswordLocked) ...[
                        const SizedBox(height: BimSpacing.x3),
                        _WalletSecurityNotice(balance: balance),
                      ],
                      const SizedBox(height: BimSpacing.x6),
                      _WalletToolStrip(
                        actions: [
                          _WalletAction(
                            icon: Icons.add_card_outlined,
                            label: '充值',
                            color: BimColors.primary,
                            onTap: () => _push(
                              context,
                              WalletRechargePage(controller: widget.controller),
                            ),
                          ),
                          _WalletAction(
                            icon: Icons.outbox_outlined,
                            label: '提现',
                            color: BimColors.transfer,
                            onTap: () => _push(
                              context,
                              WalletWithdrawPage(controller: widget.controller),
                            ),
                          ),
                          _WalletAction(
                            icon: Icons.fact_check_outlined,
                            label: '提现记录',
                            color: BimColors.secondaryText,
                            onTap: () => _push(
                              context,
                              WalletWithdrawRecordsPage(
                                controller: widget.controller,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: BimSpacing.x6),
                      const BimSectionHeader(text: '安全与管理'),
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: BimColors.surface,
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: BimColors.borderLight,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            _MenuTile(
                              icon: Icons.verified_user_outlined,
                              iconColor: BimColors.successText,
                              title: '账号安全',
                              subtitle: balance.securityBound
                                  ? '安全验证方式已绑定'
                                  : '绑定手机号或邮箱',
                              onTap: _openSecuritySettings,
                            ),
                            _MenuTile(
                              icon: Icons.lock_outline,
                              iconColor: BimColors.secondaryText,
                              title: balance.payPasswordSet ? '支付密码' : '设置支付密码',
                              subtitle: _walletPayPasswordSubtitle(balance),
                              onTap: _openPayPassword,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _walletPayPasswordSubtitle(WalletBalance balance) {
  if (!balance.securityBound) {
    return '需要先绑定安全验证方式';
  }
  if (balance.payPasswordLocked) {
    return '已锁定，请联系管理员';
  }
  if (!balance.payPasswordSet) {
    return '首次使用红包或转账前设置';
  }
  return '用于红包、转账和收付款确认';
}

class _WalletSecurityNotice extends StatelessWidget {
  const _WalletSecurityNotice({required this.balance});

  final WalletBalance balance;

  @override
  Widget build(BuildContext context) {
    final text = _walletPayPasswordSubtitle(balance);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: BimColors.warningSurface,
        border: Border.all(color: BimColors.warningBorder),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: Color(0xffb45309),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xff92400e),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletAssetStage extends StatelessWidget {
  const _WalletAssetStage({
    required this.balance,
    required this.onPayReceive,
    required this.onBills,
  });

  final WalletBalance balance;
  final VoidCallback onPayReceive;
  final VoidCallback onBills;

  @override
  Widget build(BuildContext context) {
    final statusText = balance.walletStatusName.isNotEmpty
        ? balance.walletStatusName
        : (balance.walletStatus == 1 ? '状态正常' : '当前受限');
    final hasFrozen = _walletAmountPositive(balance.frozenBalance);
    final hasRisk = hasFrozen || balance.walletStatus != 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        BimSpacing.x5,
        BimSpacing.x5,
        BimSpacing.x5,
        BimSpacing.x4,
      ),
      decoration: BoxDecoration(
        color: BimColors.textDark,
        borderRadius: BorderRadius.circular(BimRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '可用资产',
                  style: TextStyle(
                    color: BimColors.inverseSecondaryText,
                    fontSize: BimTypography.meta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _WalletStatusPill(
                label: statusText,
                danger: balance.walletStatus != 1,
              ),
            ],
          ),
          const SizedBox(height: BimSpacing.x4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '¥ ${balance.availableBalanceLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BimColors.inverseText,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ),
              const SizedBox(width: BimSpacing.x2),
              const _WalletEntryAnimation(),
            ],
          ),
          const SizedBox(height: BimSpacing.x3),
          Row(
            children: [
              Expanded(
                child: _WalletInlineMetric(
                  label: '账户余额',
                  value: '¥${balance.balanceLabel}',
                ),
              ),
              Container(width: 1, height: 30, color: const Color(0x26ffffff)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: BimSpacing.x4),
                  child: _WalletInlineMetric(
                    label: '冻结金额',
                    value: '¥${balance.frozenBalanceLabel}',
                  ),
                ),
              ),
            ],
          ),
          if (hasRisk) ...[
            const SizedBox(height: BimSpacing.x4),
            BimPressable(
              onTap: () => _showWalletFreezeDetails(context, balance),
              semanticLabel: '查看钱包限制详情',
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: BimDimensions.touchTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: BimSpacing.x3,
                  vertical: BimSpacing.x2,
                ),
                decoration: BoxDecoration(
                  color: BimColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(BimRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 17,
                      color: BimColors.warning,
                    ),
                    const SizedBox(width: BimSpacing.x2),
                    Expanded(
                      child: Text(
                        balance.freezeReason.isEmpty
                            ? statusText
                            : balance.freezeReason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: BimColors.inverseText,
                          fontSize: BimTypography.caption,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: BimColors.inverseSecondaryText,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: BimSpacing.x5),
          Row(
            children: [
              Expanded(
                child: _WalletStageAction(
                  icon: Icons.qr_code_scanner_rounded,
                  label: '收付款',
                  primary: true,
                  onTap: onPayReceive,
                ),
              ),
              const SizedBox(width: BimSpacing.x3),
              Expanded(
                child: _WalletStageAction(
                  icon: Icons.receipt_long_outlined,
                  label: '查看账单',
                  onTap: onBills,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletEntryAnimation extends StatelessWidget {
  const _WalletEntryAnimation();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 58,
      height: 58,
      child: Lottie.asset(
        'assets/lottie/wallet_entry.json',
        fit: BoxFit.contain,
        repeat: false,
        animate: !reduceMotion,
        frameRate: FrameRate.composition,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class _WalletStatusPill extends StatelessWidget {
  const _WalletStatusPill({required this.label, required this.danger});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? BimColors.warning : BimColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x2,
        vertical: BimSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(BimRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 7),
          const SizedBox(width: BimSpacing.x1),
          Text(
            label,
            style: const TextStyle(
              color: BimColors.inverseText,
              fontSize: BimTypography.caption,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletInlineMetric extends StatelessWidget {
  const _WalletInlineMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: BimColors.inverseSecondaryText,
            fontSize: BimTypography.caption,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: BimSpacing.x1),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: BimColors.inverseText,
            fontSize: BimTypography.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _WalletStageAction extends StatelessWidget {
  const _WalletStageAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return BimPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x3),
        decoration: BoxDecoration(
          color: primary
              ? BimColors.primary
              : BimColors.inverseText.withValues(alpha: 0.1),
          border: primary
              ? null
              : Border.all(
                  color: BimColors.inverseText.withValues(alpha: 0.12),
                ),
          borderRadius: BorderRadius.circular(BimRadius.sm),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: BimColors.inverseText, size: 20),
            const SizedBox(width: BimSpacing.x2),
            Text(
              label,
              style: const TextStyle(
                color: BimColors.inverseText,
                fontSize: BimTypography.body,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletToolStrip extends StatelessWidget {
  const _WalletToolStrip({required this.actions});

  final List<_WalletAction> actions;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border.symmetric(
          horizontal: BorderSide(color: BimColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: _WalletToolButton(action: actions[index])),
            if (index < actions.length - 1)
              Container(width: 1, height: 34, color: BimColors.borderLight),
          ],
        ],
      ),
    );
  }
}

class _WalletToolButton extends StatelessWidget {
  const _WalletToolButton({required this.action});

  final _WalletAction action;

  @override
  Widget build(BuildContext context) {
    return BimPressable(
      onTap: action.onTap,
      semanticLabel: action.label,
      child: SizedBox(
        height: 82,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: action.color, size: 24),
            const SizedBox(height: BimSpacing.x2),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: BimColors.text,
                fontSize: BimTypography.meta,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletAction {
  const _WalletAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}
