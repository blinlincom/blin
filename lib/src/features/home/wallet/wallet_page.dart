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
      topBar: const BimTopBar(title: '钱包'),
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
                BimSpacing.x3,
                BimBreakpoints.horizontalPadding(context),
                BimSpacing.x8,
              ),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WalletBalanceBand(balance: balance),
                        if (!balance.securityBound ||
                            !balance.payPasswordSet ||
                            balance.payPasswordLocked) ...[
                          const SizedBox(height: BimSpacing.x3),
                          _WalletSecurityNotice(balance: balance),
                        ],
                        const BimSectionHeader(text: '常用功能'),
                        _WalletActionGrid(
                          actions: [
                            _WalletAction(
                              icon: Icons.qr_code_scanner,
                              label: '收付款',
                              color: const Color(0xff0f766e),
                              onTap: () => _push(
                                context,
                                WalletPayReceivePage(
                                  controller: widget.controller,
                                ),
                              ),
                            ),
                            _WalletAction(
                              icon: Icons.add_card_outlined,
                              label: '充值',
                              color: const Color(0xff2563eb),
                              onTap: () => _push(
                                context,
                                WalletRechargePage(
                                  controller: widget.controller,
                                ),
                              ),
                            ),
                            _WalletAction(
                              icon: Icons.outbox_outlined,
                              label: '提现',
                              color: BimColors.danger,
                              onTap: () => _push(
                                context,
                                WalletWithdrawPage(
                                  controller: widget.controller,
                                ),
                              ),
                            ),
                            _WalletAction(
                              icon: Icons.receipt_long_outlined,
                              label: '账单',
                              color: BimColors.textDark,
                              onTap: () => _push(
                                context,
                                WalletBillsPage(controller: widget.controller),
                              ),
                            ),
                          ],
                        ),
                        const BimSectionHeader(text: '钱包管理'),
                        _MenuTile(
                          icon: Icons.verified_user_outlined,
                          iconColor: const Color(0xff0f766e),
                          title: '账号安全',
                          subtitle: balance.securityBound
                              ? '已绑定安全验证方式'
                              : '绑定手机号或邮箱',
                          onTap: _openSecuritySettings,
                        ),
                        _MenuTile(
                          icon: Icons.lock_outline,
                          iconColor: const Color(0xff6b7280),
                          title: balance.payPasswordSet ? '修改支付密码' : '设置支付密码',
                          subtitle: _walletPayPasswordSubtitle(balance),
                          onTap: _openPayPassword,
                        ),
                        _MenuTile(
                          icon: Icons.fact_check_outlined,
                          iconColor: const Color(0xff6b7280),
                          title: '提现记录',
                          subtitle: '查看审核状态',
                          onTap: () => _push(
                            context,
                            WalletWithdrawRecordsPage(
                              controller: widget.controller,
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _WalletBalanceBand extends StatelessWidget {
  const _WalletBalanceBand({required this.balance});

  final WalletBalance balance;

  @override
  Widget build(BuildContext context) {
    final statusText = balance.walletStatusName.isNotEmpty
        ? balance.walletStatusName
        : (balance.walletStatus == 1 ? '正常' : '受限');
    final hasFrozen = _walletAmountPositive(balance.frozenBalance);
    final hasRisk = hasFrozen || balance.walletStatus != 1;
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border.all(color: BimColors.borderLight),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '余额',
              style: TextStyle(
                color: _secondaryTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '¥${balance.balanceLabel}',
              style: const TextStyle(
                color: _textColor,
                fontSize: 36,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _WalletBalanceMetric(
                    label: '可用余额',
                    value: '¥${balance.availableBalanceLabel}',
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: _WalletBalanceMetric(
                    label: '冻结余额',
                    value: '¥${balance.frozenBalanceLabel}',
                  ),
                ),
              ],
            ),
            if (hasRisk) ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: () => _showWalletFreezeDetails(context, balance),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  decoration: BoxDecoration(
                    color: BimColors.warningSurface,
                    border: Border.all(color: BimColors.warningBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 17,
                        color: Color(0xffb45309),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '钱包$statusText${balance.freezeReason.isEmpty ? '' : '：${balance.freezeReason}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xff92400e),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Color(0xffb45309),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletBalanceMetric extends StatelessWidget {
  const _WalletBalanceMetric({required this.label, required this.value});

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
            color: _secondaryTextColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _textColor,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _WalletActionGrid extends StatelessWidget {
  const _WalletActionGrid({required this.actions});

  final List<_WalletAction> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            color: BimColors.surface,
            border: Border.all(color: BimColors.borderLight),
            borderRadius: BorderRadius.circular(BimRadius.sm),
          ),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: constraints.maxWidth < 420 ? 0.92 : 1.18,
            children: actions
                .map(
                  (action) => BimPressable(
                    onTap: action.onTap,
                    semanticLabel: action.label,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: action.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(BimRadius.sm),
                          ),
                          child: Icon(
                            action.icon,
                            color: action.color,
                            size: 23,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          action.label,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
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
