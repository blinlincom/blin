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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('钱包'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: FutureBuilder<WalletBalance>(
          future: _request,
          initialData: widget.controller.walletBalance,
          builder: (context, snapshot) {
            final balance =
                snapshot.data ??
                widget.controller.walletBalance ??
                const WalletBalance();
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                _WalletBalanceBand(balance: balance),
                const _GroupGap(),
                _WalletActionGrid(
                  actions: [
                    _WalletAction(
                      icon: Icons.qr_code_scanner,
                      label: '收付款',
                      color: const Color(0xff0f766e),
                      onTap: () => _push(
                        context,
                        WalletPayReceivePage(controller: widget.controller),
                      ),
                    ),
                    _WalletAction(
                      icon: Icons.add_card_outlined,
                      label: '充值',
                      color: const Color(0xff2563eb),
                      onTap: () => _push(
                        context,
                        WalletRechargePage(controller: widget.controller),
                      ),
                    ),
                    _WalletAction(
                      icon: Icons.outbox_outlined,
                      label: '提现',
                      color: const Color(0xffdc2626),
                      onTap: () => _push(
                        context,
                        WalletWithdrawPage(controller: widget.controller),
                      ),
                    ),
                    _WalletAction(
                      icon: Icons.receipt_long_outlined,
                      label: '账单',
                      color: const Color(0xff111827),
                      onTap: () => _push(
                        context,
                        WalletBillsPage(controller: widget.controller),
                      ),
                    ),
                  ],
                ),
                const _GroupGap(),
                _MenuTile(
                  icon: Icons.lock_outline,
                  iconColor: const Color(0xff6b7280),
                  title: balance.payPasswordSet ? '修改支付密码' : '设置支付密码',
                  subtitle: '用于收付款确认',
                  onTap: () => _push(
                    context,
                    WalletPayPasswordPage(controller: widget.controller),
                  ),
                ),
                _MenuTile(
                  icon: Icons.fact_check_outlined,
                  iconColor: const Color(0xff6b7280),
                  title: '提现记录',
                  subtitle: '查看审核状态',
                  onTap: () => _push(
                    context,
                    WalletWithdrawRecordsPage(controller: widget.controller),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WalletBalanceBand extends StatelessWidget {
  const _WalletBalanceBand({required this.balance});

  final WalletBalance balance;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
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
                fontSize: 38,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletActionGrid extends StatelessWidget {
  const _WalletActionGrid({required this.actions});

  final List<_WalletAction> actions;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.92,
        children: actions
            .map(
              (action) => InkWell(
                onTap: action.onTap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, color: action.color, size: 28),
                    const SizedBox(height: 9),
                    Text(
                      action.label,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
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

class WalletPayReceivePage extends StatelessWidget {
  const WalletPayReceivePage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('收付款'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          children: [
            _MenuTile(
              icon: Icons.call_received,
              iconColor: const Color(0xff0f766e),
              title: '收款码',
              subtitle: '设置金额后让对方扫码付款',
              onTap: () =>
                  _push(context, WalletCollectCodePage(controller: controller)),
            ),
            _MenuTile(
              icon: Icons.call_made,
              iconColor: const Color(0xff2563eb),
              title: '付款码',
              subtitle: '短时有效，只能被收款方消费一次',
              onTap: () =>
                  _push(context, WalletPayCodePage(controller: controller)),
            ),
            const _GroupGap(),
            _MenuTile(
              icon: Icons.qr_code_scanner,
              iconColor: const Color(0xff111827),
              title: '扫一扫付款',
              subtitle: '扫描对方收款码后确认支付',
              onTap: () =>
                  _push(context, WalletScanPage(controller: controller)),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletCollectCodePage extends StatefulWidget {
  const WalletCollectCodePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletCollectCodePage> createState() => _WalletCollectCodePageState();
}

class _WalletCollectCodePageState extends State<WalletCollectCodePage> {
  final _amount = TextEditingController();
  final _remark = TextEditingController();
  WalletOrder? _order;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await widget.controller.createWalletCollectCode(
        amount: _amount.text.trim(),
        remark: _remark.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _order = order);
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('收款码'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (order == null) ...[
              _WalletTextField(
                controller: _amount,
                label: '金额',
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              _WalletTextField(controller: _remark, label: '备注', hint: '选填'),
              const SizedBox(height: 22),
              _WalletPrimaryButton(
                text: _busy ? '生成中...' : '生成收款码',
                onPressed: _busy ? null : _create,
              ),
            ] else
              _WalletQrBlock(
                title: '收款金额 ¥${order.amountLabel}',
                subtitle: order.remark.isEmpty ? '等待对方付款' : order.remark,
                payload: order.qrPayload,
                expireText: order.expireTime,
              ),
          ],
        ),
      ),
    );
  }
}

class WalletPayCodePage extends StatefulWidget {
  const WalletPayCodePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletPayCodePage> createState() => _WalletPayCodePageState();
}

class _WalletPayCodePageState extends State<WalletPayCodePage> {
  final _amount = TextEditingController();
  final _payeeUsername = TextEditingController();
  final _password = TextEditingController();
  WalletOrder? _order;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _payeeUsername.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await widget.controller.createWalletPayCode(
        amount: _amount.text.trim(),
        payeeUsername: _payeeUsername.text.trim(),
        payPassword: _password.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() => _order = order);
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('付款码'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (order == null) ...[
              _WalletTextField(
                controller: _payeeUsername,
                label: '收款方用户名',
                hint: '@username',
              ),
              const SizedBox(height: 12),
              _WalletTextField(
                controller: _amount,
                label: '金额',
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              _WalletTextField(
                controller: _password,
                label: '支付密码',
                hint: '6位数字',
                keyboardType: TextInputType.number,
                obscureText: true,
              ),
              const SizedBox(height: 22),
              _WalletPrimaryButton(
                text: _busy ? '生成中...' : '生成付款码',
                onPressed: _busy ? null : _create,
              ),
            ] else
              _WalletQrBlock(
                title: '付款金额 ¥${order.amountLabel}',
                subtitle: '收款方扫码后完成支付',
                payload: order.qrPayload,
                expireText: order.expireTime,
              ),
          ],
        ),
      ),
    );
  }
}

class WalletScanPage extends StatefulWidget {
  const WalletScanPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletScanPage> createState() => _WalletScanPageState();
}

class _WalletScanPageState extends State<WalletScanPage> {
  bool _handled = false;

  Future<void> _handle(String raw) async {
    if (_handled) {
      return;
    }
    final token = _walletTokenFromQr(raw);
    if (token.isEmpty) {
      _showWalletMessage(context, '二维码无效');
      return;
    }
    _handled = true;
    try {
      final order = await widget.controller.scanWalletQr(token);
      if (!mounted) {
        return;
      }
      await _push(
        context,
        WalletPayConfirmPage(
          controller: widget.controller,
          order: order,
          qrToken: token,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      _handled = false;
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫一扫'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          final value = barcodes.isEmpty ? '' : (barcodes.first.rawValue ?? '');
          if (value.isNotEmpty) {
            _handle(value);
          }
        },
      ),
    );
  }
}

class WalletPayConfirmPage extends StatefulWidget {
  const WalletPayConfirmPage({
    required this.controller,
    required this.order,
    required this.qrToken,
    super.key,
  });

  final SessionController controller;
  final WalletOrder order;
  final String qrToken;

  @override
  State<WalletPayConfirmPage> createState() => _WalletPayConfirmPageState();
}

class _WalletPayConfirmPageState extends State<WalletPayConfirmPage> {
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await widget.controller.confirmWalletQrPay(
        qrToken: widget.qrToken,
        payPassword: widget.order.orderType == 'pay'
            ? ''
            : _password.text.trim(),
      );
      if (!mounted) {
        return;
      }
      _showWalletMessage(
        context,
        widget.order.orderType == 'pay' ? '收款成功' : '支付成功',
      );
      Navigator.of(context).pop(order);
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPayCode = order.orderType == 'pay';
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(isPayCode ? '确认收款' : '确认付款'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Center(
              child: Text(
                '¥${order.amountLabel}',
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _WalletInfoRow(label: '收款方', value: order.payeeName),
            if (isPayCode) _WalletInfoRow(label: '付款方', value: order.payerName),
            if (order.remark.isNotEmpty)
              _WalletInfoRow(label: '备注', value: order.remark),
            const SizedBox(height: 18),
            if (!isPayCode)
              _WalletTextField(
                controller: _password,
                label: '支付密码',
                hint: '6位数字',
                keyboardType: TextInputType.number,
                obscureText: true,
              ),
            const SizedBox(height: 24),
            _WalletPrimaryButton(
              text: _busy
                  ? (isPayCode ? '收款中...' : '支付中...')
                  : (isPayCode ? '确认收款' : '确认付款'),
              onPressed: _busy ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class WalletRechargePage extends StatefulWidget {
  const WalletRechargePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletRechargePage> createState() => _WalletRechargePageState();
}

class _WalletRechargePageState extends State<WalletRechargePage> {
  final _km = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.rechargeWalletByKm(_km.text.trim());
      if (mounted) {
        _showWalletMessage(context, '充值成功');
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WalletFormScaffold(
      title: '充值',
      children: [
        _WalletTextField(controller: _km, label: '卡密', hint: '输入充值卡密'),
        const SizedBox(height: 22),
        _WalletPrimaryButton(
          text: _busy ? '提交中...' : '确认充值',
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

class WalletWithdrawPage extends StatefulWidget {
  const WalletWithdrawPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletWithdrawPage> createState() => _WalletWithdrawPageState();
}

class _WalletWithdrawPageState extends State<WalletWithdrawPage> {
  final _amount = TextEditingController();
  final _account = TextEditingController();
  final _name = TextEditingController();
  final _remark = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _account.dispose();
    _name.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.withdrawWallet(
        amount: _amount.text.trim(),
        account: _account.text.trim(),
        name: _name.text.trim(),
        remark: _remark.text.trim(),
      );
      if (mounted) {
        _showWalletMessage(context, '提现申请已提交');
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WalletFormScaffold(
      title: '提现',
      children: [
        _WalletTextField(
          controller: _amount,
          label: '金额',
          hint: '0.00',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        _WalletTextField(controller: _name, label: '姓名', hint: '收款人姓名'),
        const SizedBox(height: 12),
        _WalletTextField(controller: _account, label: '账户', hint: '收款账户'),
        const SizedBox(height: 12),
        _WalletTextField(controller: _remark, label: '备注', hint: '选填'),
        const SizedBox(height: 22),
        _WalletPrimaryButton(
          text: _busy ? '提交中...' : '提交提现',
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

class WalletPayPasswordPage extends StatefulWidget {
  const WalletPayPasswordPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletPayPasswordPage> createState() => _WalletPayPasswordPageState();
}

class _WalletPayPasswordPageState extends State<WalletPayPasswordPage> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _password.text.trim();
    if (value != _confirm.text.trim()) {
      _showWalletMessage(context, '两次密码不一致');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.setWalletPayPassword(value);
      if (mounted) {
        _showWalletMessage(context, '设置成功');
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _WalletFormScaffold(
      title: '支付密码',
      children: [
        _WalletTextField(
          controller: _password,
          label: '支付密码',
          hint: '6位数字',
          keyboardType: TextInputType.number,
          obscureText: true,
        ),
        const SizedBox(height: 12),
        _WalletTextField(
          controller: _confirm,
          label: '确认密码',
          hint: '再次输入',
          keyboardType: TextInputType.number,
          obscureText: true,
        ),
        const SizedBox(height: 22),
        _WalletPrimaryButton(
          text: _busy ? '保存中...' : '保存',
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}

class WalletBillsPage extends StatefulWidget {
  const WalletBillsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletBillsPage> createState() => _WalletBillsPageState();
}

class _WalletBillsPageState extends State<WalletBillsPage> {
  String _scene = 'all';
  late Future<List<WalletBill>> _request;

  @override
  void initState() {
    super.initState();
    _request = _load();
  }

  Future<List<WalletBill>> _load() {
    return widget.controller.loadWalletBills(scene: _scene, limit: 50);
  }

  void _setScene(String value) {
    setState(() {
      _scene = value;
      _request = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('账单'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _WalletSceneTabs(value: _scene, onChanged: _setScene),
            Expanded(
              child: FutureBuilder<List<WalletBill>>(
                future: _request,
                builder: (context, snapshot) {
                  final list = snapshot.data ?? const <WalletBill>[];
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      list.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (list.isEmpty) {
                    return const Center(
                      child: Text(
                        '暂无账单',
                        style: TextStyle(color: _mutedColor, fontSize: 14),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _lightBorderColor),
                    itemBuilder: (context, index) {
                      final item = list[index];
                      final income = item.direction == 'income';
                      return ListTile(
                        tileColor: _surfaceColor,
                        title: Text(
                          item.remark.isEmpty ? '余额变动' : item.remark,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          item.time,
                          style: const TextStyle(
                            color: _mutedColor,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Text(
                          item.amountLabel,
                          style: TextStyle(
                            color: income
                                ? const Color(0xff16a34a)
                                : _dangerColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WalletWithdrawRecordsPage extends StatelessWidget {
  const WalletWithdrawRecordsPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('提现记录'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: FutureBuilder<List<WalletWithdrawRecord>>(
          future: controller.loadWalletWithdrawRecords(limit: 50),
          builder: (context, snapshot) {
            final list = snapshot.data ?? const <WalletWithdrawRecord>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                list.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (list.isEmpty) {
              return const Center(
                child: Text(
                  '暂无提现记录',
                  style: TextStyle(color: _mutedColor, fontSize: 14),
                ),
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _lightBorderColor),
              itemBuilder: (context, index) {
                final item = list[index];
                return ListTile(
                  tileColor: _surfaceColor,
                  title: Text('¥${item.amount}'),
                  subtitle: Text(item.createTime),
                  trailing: Text(item.statusName),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _WalletFormScaffold extends StatelessWidget {
  const _WalletFormScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: children,
        ),
      ),
    );
  }
}

class _WalletTextField extends StatelessWidget {
  const _WalletTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: _surfaceColor,
        border: const OutlineInputBorder(
          borderSide: BorderSide(color: _lightBorderColor),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _lightBorderColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _primaryColor),
        ),
      ),
    );
  }
}

class _WalletPrimaryButton extends StatelessWidget {
  const _WalletPrimaryButton({required this.text, required this.onPressed});

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: FilledButton(onPressed: onPressed, child: Text(text)),
    );
  }
}

class _WalletQrBlock extends StatelessWidget {
  const _WalletQrBlock({
    required this.title,
    required this.subtitle,
    required this.payload,
    required this.expireText,
  });

  final String title;
  final String subtitle;
  final String payload;
  final String expireText;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _textColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: _mutedColor, fontSize: 14),
            ),
            const SizedBox(height: 28),
            QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: 230,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              '有效期至 $expireText',
              style: const TextStyle(color: _mutedColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletInfoRow extends StatelessWidget {
  const _WalletInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: _mutedColor, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletSceneTabs extends StatelessWidget {
  const _WalletSceneTabs({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      ('all', '全部'),
      ('income', '收入'),
      ('expense', '支出'),
      ('charge', '充值'),
      ('withdraw', '提现'),
      ('im', '红包转账'),
      ('scan', '扫码'),
    ];
    return ColoredBox(
      color: _surfaceColor,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: tabs
              .map((tab) {
                final selected = value == tab.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(tab.$2),
                    selected: selected,
                    onSelected: (_) => onChanged(tab.$1),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ),
    );
  }
}

String _walletTokenFromQr(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  if (uri != null) {
    final token = uri.queryParameters['token'] ?? '';
    if (token.isNotEmpty) {
      return token;
    }
  }
  if (RegExp(r'^[a-f0-9]{48}$').hasMatch(text)) {
    return text;
  }
  return '';
}

void _showWalletMessage(BuildContext context, String text) {
  final message = text.replaceFirst('Exception: ', '');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
