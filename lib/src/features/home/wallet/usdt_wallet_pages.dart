part of 'package:bim/src/features/home/home_page.dart';

class UsdtWalletPage extends StatefulWidget {
  const UsdtWalletPage({required this.controller, super.key});
  final SessionController controller;

  @override
  State<UsdtWalletPage> createState() => _UsdtWalletPageState();
}

class _UsdtWalletPageState extends State<UsdtWalletPage> {
  late Future<UsdtWalletOverview> _request;

  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadUsdtWalletOverview();
  }

  Future<void> _refresh() async {
    final next = widget.controller.loadUsdtWalletOverview();
    setState(() => _request = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: BimTopBar(
      title: 'USDT',
      actions: [
        IconButton(
          tooltip: '账单',
          onPressed: () =>
              _push(context, UsdtBillsPage(controller: widget.controller)),
          icon: const Icon(Icons.receipt_long_outlined),
        ),
      ],
    ),
    body: FutureBuilder<UsdtWalletOverview>(
      future: _request,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const BimLoadingState(label: '正在读取数字资产');
        }
        final wallet = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              BimBreakpoints.horizontalPadding(context),
              BimSpacing.x4,
              BimBreakpoints.horizontalPadding(context),
              MediaQuery.paddingOf(context).bottom + BimSpacing.x6,
            ),
            children: [
              BimContentViewport(
                maxWidth: 720,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(BimSpacing.x5),
                      decoration: BoxDecoration(
                        color: BimColors.surface,
                        border: Border.all(color: BimColors.border),
                        borderRadius: BorderRadius.circular(BimRadius.lg),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.currency_exchange,
                                color: BimColors.successText,
                              ),
                              SizedBox(width: BimSpacing.x2),
                              Text(
                                'USDT · TRC20',
                                style: TextStyle(
                                  color: BimColors.textDark,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: BimSpacing.x5),
                          Text(
                            wallet.totalBalance,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: BimColors.textDark,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: BimSpacing.x4),
                          Row(
                            children: [
                              Expanded(
                                child: _UsdtMetric(
                                  label: '可用',
                                  value: wallet.availableBalance,
                                ),
                              ),
                              Expanded(
                                child: _UsdtMetric(
                                  label: '冻结',
                                  value: wallet.frozenBalance,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BimSpacing.x4),
                    Row(
                      children: [
                        Expanded(
                          child: _UsdtAction(
                            icon: Icons.south_west,
                            label: '充值',
                            enabled: wallet.depositEnabled,
                            onTap: () => _push(
                              context,
                              UsdtDepositPage(controller: widget.controller),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _UsdtAction(
                            icon: Icons.swap_horiz,
                            label: '转账',
                            enabled: wallet.transferEnabled,
                            onTap: () => _push(
                              context,
                              UsdtTransferPage(controller: widget.controller),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _UsdtAction(
                            icon: Icons.north_east,
                            label: '提币',
                            enabled: wallet.withdrawEnabled,
                            onTap: () => _push(
                              context,
                              UsdtWithdrawPage(controller: widget.controller),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!wallet.depositEnabled || !wallet.withdrawEnabled) ...[
                      const SizedBox(height: BimSpacing.x4),
                      const BimNoticeBanner(
                        text: '部分链上功能尚未开放，站内转账和已有余额查询不受影响。',
                      ),
                    ],
                    const SizedBox(height: BimSpacing.x5),
                    BimSettingsTile(
                      title: 'USDT 账单',
                      value: '充值、转账和提币记录',
                      onTap: () => _push(
                        context,
                        UsdtBillsPage(controller: widget.controller),
                      ),
                    ),
                    BimSettingsTile(
                      title: 'OTC 买卖',
                      value: '使用余额买入或出售数字资产',
                      onTap: () => _push(
                        context,
                        OtcHomePage(controller: widget.controller),
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

class _UsdtMetric extends StatelessWidget {
  const _UsdtMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: BimColors.secondaryText)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

class _UsdtAction extends StatelessWidget {
  const _UsdtAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => BimPressable(
    onTap: enabled ? onTap : null,
    semanticLabel: label,
    child: SizedBox(
      height: 72,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: enabled ? BimColors.primary : BimColors.mutedText),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: enabled ? BimColors.textDark : BimColors.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class UsdtDepositPage extends StatefulWidget {
  const UsdtDepositPage({required this.controller, super.key});
  final SessionController controller;
  @override
  State<UsdtDepositPage> createState() => _UsdtDepositPageState();
}

class _UsdtDepositPageState extends State<UsdtDepositPage> {
  late Future<Map<String, Object?>> _request;
  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadUsdtDepositAddress();
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: const BimTopBar(title: '充值 USDT'),
    body: FutureBuilder<Map<String, Object?>>(
      future: _request,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return BimEmptyState(
            title: '暂时无法获取充值地址',
            message: _walletInlineError(snapshot.error!),
          );
        if (!snapshot.hasData) return const BimLoadingState(label: '正在分配充值地址');
        final data = snapshot.data!;
        final address = '${data['address'] ?? ''}';
        return ListView(
          padding: const EdgeInsets.all(BimSpacing.x5),
          children: [
            const Text(
              'USDT · TRC20',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: BimTypography.title,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: BimSpacing.x5),
            SelectableText(
              address,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5),
            ),
            const SizedBox(height: BimSpacing.x4),
            BimButton(
              label: '复制地址',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) showBimSnackBar(context, '地址已复制');
              },
            ),
            const SizedBox(height: BimSpacing.x4),
            BimNoticeBanner(
              text:
                  '${data['notice'] ?? '仅支持USDT-TRC20充值'}\n最低充值 ${data['min_deposit'] ?? '0'} USDT',
              tone: BimNoticeTone.warning,
            ),
          ],
        );
      },
    ),
  );
}

class UsdtTransferPage extends StatefulWidget {
  const UsdtTransferPage({required this.controller, super.key});
  final SessionController controller;
  @override
  State<UsdtTransferPage> createState() => _UsdtTransferPageState();
}

class _UsdtTransferPageState extends State<UsdtTransferPage> {
  final _username = TextEditingController();
  final _amount = TextEditingController();
  final _remark = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _username.dispose();
    _amount.dispose();
    _remark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: const BimTopBar(title: 'USDT 转账'),
    body: ListView(
      padding: const EdgeInsets.all(BimSpacing.x4),
      children: [
        TextField(
          controller: _username,
          decoration: const InputDecoration(
            labelText: '收款用户名',
            prefixText: '@ ',
          ),
        ),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '转账数量',
            suffixText: 'USDT',
          ),
        ),
        TextField(
          controller: _remark,
          maxLength: 120,
          decoration: const InputDecoration(labelText: '备注（选填）'),
        ),
        const BimNoticeBanner(text: '站内转账实时到账且不可撤回，请核对收款人的用户名和资料。'),
        const SizedBox(height: BimSpacing.x4),
        BimButton(label: '继续', busy: _busy, onPressed: _busy ? null : _submit),
      ],
    ),
  );
  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final preview = await widget.controller.previewUsdtTransfer(
        username: _username.text.trim(),
        amount: _amount.text.trim(),
      );
      if (!mounted) return;
      final receiver = preview['receiver'] is Map
          ? Map<String, Object?>.from(preview['receiver'] as Map)
          : <String, Object?>{};
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认转账'),
          content: Text(
            '向 ${receiver['nickname'] ?? ''} @${receiver['username'] ?? ''}\n转账 ${preview['amount']} USDT',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final password = await _showWalletPayPasswordSheet(
        context,
        title: '验证支付密码',
        amountLabel: '${preview['amount']} USDT',
      );
      if (password.isEmpty || !mounted) return;
      await widget.controller.createUsdtTransfer(
        username: _username.text.trim(),
        amount: _amount.text.trim(),
        payPassword: password,
        remark: _remark.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      showBimSnackBar(context, '转账成功', tone: BimNoticeTone.success);
    } catch (error) {
      if (mounted)
        showBimSnackBar(
          context,
          _walletInlineError(error),
          tone: BimNoticeTone.error,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class UsdtWithdrawPage extends StatefulWidget {
  const UsdtWithdrawPage({required this.controller, super.key});
  final SessionController controller;
  @override
  State<UsdtWithdrawPage> createState() => _UsdtWithdrawPageState();
}

class _UsdtWithdrawPageState extends State<UsdtWithdrawPage> {
  final _address = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;
  @override
  void dispose() {
    _address.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: const BimTopBar(title: '提币 USDT'),
    body: ListView(
      padding: const EdgeInsets.all(BimSpacing.x4),
      children: [
        TextField(
          controller: _address,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'TRC20 地址'),
        ),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '提币数量',
            suffixText: 'USDT',
          ),
        ),
        const BimNoticeBanner(
          text: '链上提币不可撤回，请确认地址属于TRON/TRC20网络。',
          tone: BimNoticeTone.warning,
        ),
        const SizedBox(height: BimSpacing.x4),
        BimButton(label: '继续', busy: _busy, onPressed: _busy ? null : _submit),
      ],
    ),
  );
  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final preview = await widget.controller.previewUsdtWithdraw(
        address: _address.text.trim(),
        amount: _amount.text.trim(),
      );
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认提币'),
          content: Text(
            '提币 ${preview['amount']} USDT\n手续费 ${preview['fee']} USDT\n实际到账 ${preview['receive_amount']} USDT\n\n${preview['address']}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回检查'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final password = await _showWalletPayPasswordSheet(
        context,
        title: '验证支付密码',
        amountLabel: '${preview['amount']} USDT',
      );
      if (password.isEmpty || !mounted) return;
      await widget.controller.createUsdtWithdraw(
        address: _address.text.trim(),
        amount: _amount.text.trim(),
        payPassword: password,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showBimSnackBar(context, '提币申请已提交', tone: BimNoticeTone.success);
    } catch (error) {
      if (mounted)
        showBimSnackBar(
          context,
          _walletInlineError(error),
          tone: BimNoticeTone.error,
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class UsdtBillsPage extends StatelessWidget {
  const UsdtBillsPage({required this.controller, super.key});
  final SessionController controller;
  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: const BimTopBar(title: 'USDT 账单'),
    body: FutureBuilder<List<UsdtAssetBill>>(
      future: controller.loadUsdtAssetBills(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const BimLoadingState(label: '正在加载账单');
        final list = snapshot.data!;
        if (list.isEmpty) return const BimEmptyState(title: '暂无USDT账单');
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = list[index];
            final delta = item.availableDelta;
            final incoming = !delta.startsWith('-') && delta != '0.00000000';
            return ListTile(
              title: Text(_usdtBillTitle(item.businessType)),
              subtitle: Text('${item.createTime}\n${item.businessNo}'),
              isThreeLine: true,
              trailing: Text(
                '${incoming ? '+' : ''}$delta',
                style: TextStyle(
                  color: incoming ? BimColors.successText : BimColors.textDark,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

String _usdtBillTitle(String type) => switch (type) {
  'internal_transfer' => '站内转账',
  'withdraw_freeze' => '提币申请',
  'deposit' => '链上充值',
  _ => 'USDT余额变动',
};
