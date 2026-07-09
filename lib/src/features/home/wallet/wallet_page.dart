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
                if (!balance.securityBound ||
                    !balance.payPasswordSet ||
                    balance.payPasswordLocked)
                  _WalletSecurityNotice(balance: balance),
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
                  icon: Icons.verified_user_outlined,
                  iconColor: const Color(0xff0f766e),
                  title: '账号安全',
                  subtitle: balance.securityBound ? '已绑定安全验证方式' : '绑定手机号或邮箱',
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
    return ColoredBox(
      color: _surfaceColor,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xfffffbeb),
          border: Border.all(color: const Color(0xfffde68a)),
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

class WalletPayReceivePage extends StatefulWidget {
  const WalletPayReceivePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletPayReceivePage> createState() => _WalletPayReceivePageState();
}

class _WalletPayReceivePageState extends State<WalletPayReceivePage> {
  final _amount = TextEditingController();
  final _remark = TextEditingController();
  WalletOrder? _payOrder;
  WalletOrder? _collectOrder;
  String _payError = '';
  String _collectError = '';
  bool _payLoading = true;
  bool _collectLoading = true;
  bool _settingCollectAmount = false;
  Timer? _payTimer;
  int _paySecondsLeft = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPayCode(showLoading: false));
    unawaited(_loadCollectCode(showLoading: false));
  }

  @override
  void dispose() {
    _payTimer?.cancel();
    _amount.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _loadPayCode({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _payLoading = true;
        _payError = '';
      });
    }
    try {
      final order = await widget.controller.currentWalletPayCode();
      if (!mounted) {
        return;
      }
      _startPayCountdown(order);
      setState(() {
        _payOrder = order;
        _payError = '';
        _payLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _payTimer?.cancel();
      setState(() {
        _payError = _walletInlineError(error);
        _payLoading = false;
      });
    }
  }

  Future<void> _loadCollectCode({
    String amount = '',
    String remark = '',
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _collectLoading = true;
        _collectError = '';
      });
    }
    try {
      final order = await widget.controller.currentWalletCollectCode(
        amount: amount,
        remark: remark,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _collectOrder = order;
        _collectError = '';
        _collectLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _collectError = _walletInlineError(error);
        _collectLoading = false;
      });
    }
  }

  void _startPayCountdown(WalletOrder order) {
    _payTimer?.cancel();
    _paySecondsLeft = order.expireSeconds;
    if (_paySecondsLeft <= 0) {
      return;
    }
    _payTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_paySecondsLeft <= 1) {
        timer.cancel();
        unawaited(_loadPayCode(showLoading: false));
        return;
      }
      setState(() => _paySecondsLeft -= 1);
    });
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadPayCode(),
      _loadCollectCode(
        amount: _amount.text.trim(),
        remark: _remark.text.trim(),
      ),
    ]);
  }

  Future<void> _setCollectAmount() async {
    if (_settingCollectAmount) {
      return;
    }
    setState(() => _settingCollectAmount = true);
    await _loadCollectCode(
      amount: _amount.text.trim(),
      remark: _remark.text.trim(),
    );
    if (mounted) {
      setState(() => _settingCollectAmount = false);
      if (_collectError.isEmpty) {
        _showWalletMessage(context, '收款码已更新');
      }
    }
  }

  String get _paySubtitle {
    if (_payError.isNotEmpty) {
      return '付款码生成失败';
    }
    if (_payOrder == null) {
      return '正在生成付款码';
    }
    return _paySecondsLeft > 0 ? '${_paySecondsLeft}s 后自动刷新' : '短时有效，自动刷新';
  }

  String get _collectTitle {
    final order = _collectOrder;
    if (order == null || order.needsAmountInput) {
      return '我的收款码';
    }
    return '收款金额 ¥${order.amountLabel}';
  }

  String get _collectSubtitle {
    if (_collectError.isNotEmpty) {
      return '收款码生成失败';
    }
    final order = _collectOrder;
    if (order == null) {
      return '正在生成收款码';
    }
    return order.remark.isEmpty ? '扫一扫，向我付款' : order.remark;
  }

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
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: (_payLoading || _collectLoading) ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 28),
          children: [
            _WalletQrPanel(
              order: _payOrder,
              title: '付款码',
              subtitle: _paySubtitle,
              loading: _payLoading,
              showBarcode: true,
              errorText: _payError,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextButton.icon(
                onPressed: _payLoading ? null : () => _loadPayCode(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新付款码'),
              ),
            ),
            const _GroupGap(),
            _WalletQrPanel(
              order: _collectOrder,
              title: _collectTitle,
              subtitle: _collectSubtitle,
              loading: _collectLoading,
              errorText: _collectError,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WalletTextField(
                    controller: _amount,
                    label: '设置金额',
                    hint: '不填则由付款方输入',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _WalletTextField(
                    controller: _remark,
                    label: '备注',
                    hint: '选填',
                  ),
                  const SizedBox(height: 18),
                  _WalletPrimaryButton(
                    text: _settingCollectAmount ? '更新中...' : '设置收款金额',
                    onPressed: _settingCollectAmount ? null : _setCollectAmount,
                  ),
                ],
              ),
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
  Future<WalletOrder>? _request;
  WalletOrder? _order;
  bool _settingAmount = false;

  @override
  void initState() {
    super.initState();
    _request = _load();
  }

  void dispose() {
    _amount.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<WalletOrder> _load({String amount = '', String remark = ''}) async {
    final order = await widget.controller.currentWalletCollectCode(
      amount: amount,
      remark: remark,
    );
    if (mounted) {
      setState(() => _order = order);
    }
    return order;
  }

  Future<void> _refresh() async {
    setState(() => _request = _load());
  }

  Future<void> _setAmount() async {
    if (_settingAmount) {
      return;
    }
    setState(() => _settingAmount = true);
    try {
      final order = await widget.controller.currentWalletCollectCode(
        amount: _amount.text.trim(),
        remark: _remark.text.trim(),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _order = order;
        _request = Future.value(order);
      });
      _showWalletMessage(context, '收款金额已更新');
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _settingAmount = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('收款码'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<WalletOrder>(
          future: _request,
          initialData: _order,
          builder: (context, snapshot) {
            final order = snapshot.data;
            final loading =
                snapshot.connectionState == ConnectionState.waiting &&
                order == null;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                _WalletQrPanel(
                  order: order,
                  title: order == null || order.needsAmountInput
                      ? '向我付款'
                      : '收款金额 ¥${order.amountLabel}',
                  subtitle: order == null
                      ? '正在生成收款码'
                      : (order.remark.isEmpty ? '扫一扫，向我付款' : order.remark),
                  loading: loading,
                ),
                const SizedBox(height: 14),
                _WalletTextField(
                  controller: _amount,
                  label: '设置金额',
                  hint: '不填则由付款方输入',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                _WalletTextField(controller: _remark, label: '备注', hint: '选填'),
                const SizedBox(height: 18),
                _WalletPrimaryButton(
                  text: _settingAmount ? '更新中...' : '设置金额',
                  onPressed: _settingAmount ? null : _setAmount,
                ),
              ],
            );
          },
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
  Future<WalletOrder>? _request;
  WalletOrder? _order;
  bool _busy = false;
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _createOrRefresh() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await widget.controller.currentWalletPayCode();
      if (!mounted) {
        return;
      }
      _startCountdown(order);
      setState(() {
        _order = order;
        _request = Future.value(order);
      });
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

  void _startCountdown(WalletOrder order) {
    _timer?.cancel();
    _secondsLeft = order.expireSeconds;
    if (_secondsLeft <= 0) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        _createOrRefresh();
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
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
        actions: [
          if (order != null)
            IconButton(
              tooltip: '刷新',
              onPressed: _busy ? null : _createOrRefresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            if (order == null) ...[
              _WalletPayCodeIntro(),
              const SizedBox(height: 22),
              _WalletPrimaryButton(
                text: _busy ? '生成中...' : '打开付款码',
                onPressed: _busy ? null : _createOrRefresh,
              ),
            ] else
              FutureBuilder<WalletOrder>(
                future: _request,
                initialData: order,
                builder: (context, snapshot) {
                  final current = snapshot.data ?? order;
                  return _WalletQrPanel(
                    order: current,
                    title: '付款码',
                    subtitle: _secondsLeft > 0
                        ? '${_secondsLeft}s 后自动刷新'
                        : '短时有效，自动刷新',
                    loading: _busy && current.qrPayload.isEmpty,
                    showBarcode: true,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class WalletScanPage extends StatelessWidget {
  const WalletScanPage({required this.controller, super.key});

  final SessionController controller;

  @override
  Widget build(BuildContext context) =>
      FriendQrScannerPage(controller: controller);
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
  final _amount = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
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
        amount: widget.order.needsAmountInput ? _amount.text.trim() : '',
      );
      if (!mounted) {
        return;
      }
      _showWalletMessage(
        context,
        widget.order.orderType == 'pay' ? '已向付款方发起确认' : '支付成功',
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
    final targetName = isPayCode ? order.payerName : order.payeeName;
    final targetAvatar = isPayCode ? order.payerAvatar : order.payeeAvatar;
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: Text(isPayCode ? '发起收款' : '确认付款'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            _WalletConfirmHeader(
              title: isPayCode ? '向付款方发起确认' : '付款给对方',
              name: targetName,
              avatar: targetAvatar,
            ),
            const SizedBox(height: 22),
            if (order.needsAmountInput)
              _WalletTextField(
                controller: _amount,
                label: '金额',
                hint: '0.00',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              )
            else
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
            _WalletInfoRow(label: '交易类型', value: isPayCode ? '付款码收款' : '扫码付款'),
            if (targetName.isNotEmpty)
              _WalletInfoRow(
                label: isPayCode ? '付款方' : '收款方',
                value: targetName,
              ),
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
                  ? (isPayCode ? '发起中...' : '支付中...')
                  : (isPayCode ? '发起收款确认' : '确认付款'),
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

class WalletSecurityPage extends StatefulWidget {
  const WalletSecurityPage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletSecurityPage> createState() => _WalletSecurityPageState();
}

class _WalletSecurityPageState extends State<WalletSecurityPage> {
  final _mobile = TextEditingController();
  final _mobileCode = TextEditingController();
  final _email = TextEditingController();
  final _emailCode = TextEditingController();
  final _captcha = TextEditingController();
  UserSecurityInfo? _info;
  _WalletSecurityEditMode _editMode = _WalletSecurityEditMode.none;
  bool _loading = true;
  bool _busy = false;
  bool _sendingMobile = false;
  bool _sendingEmail = false;
  int _captchaRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mobile.dispose();
    _mobileCode.dispose();
    _email.dispose();
    _emailCode.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await widget.controller.loadUserSecurityInfo();
      if (mounted) {
        setState(() {
          _info = info;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        _showWalletMessage(context, error.toString());
      }
    }
  }

  void _refreshCaptcha() {
    setState(() {
      _captcha.clear();
      _captchaRevision++;
    });
  }

  void _startEdit(_WalletSecurityEditMode mode) {
    final info = _info ?? const UserSecurityInfo();
    setState(() {
      _editMode = _editMode == mode ? _WalletSecurityEditMode.none : mode;
      _captcha.clear();
      _mobileCode.clear();
      _emailCode.clear();
      _captchaRevision++;
      if (mode == _WalletSecurityEditMode.mobile && info.mobileBound) {
        _mobile.text = info.mobile;
      }
      if (mode == _WalletSecurityEditMode.email && info.emailBound) {
        _email.text = info.email;
      }
    });
  }

  void _closeEdit() {
    setState(() {
      _editMode = _WalletSecurityEditMode.none;
      _captcha.clear();
      _mobileCode.clear();
      _emailCode.clear();
      _captchaRevision++;
    });
  }

  String _captchaValue() {
    final value = _captcha.text.trim();
    if (value.isEmpty) {
      _showWalletMessage(context, '请先输入图片验证码');
    }
    return value;
  }

  Future<void> _sendMobileCode() async {
    final mobile = _mobile.text.trim();
    if (mobile.isEmpty) {
      _showWalletMessage(context, '请输入手机号');
      return;
    }
    final captcha = _captchaValue();
    if (captcha.isEmpty) {
      return;
    }
    setState(() => _sendingMobile = true);
    try {
      await widget.controller.sendMobileBindCode(
        mobile: mobile,
        captcha: captcha,
      );
      if (mounted) {
        _showWalletMessage(context, '验证码已发送');
        _refreshCaptcha();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
        _refreshCaptcha();
      }
    } finally {
      if (mounted) {
        setState(() => _sendingMobile = false);
      }
    }
  }

  Future<void> _confirmMobile() async {
    final mobile = _mobile.text.trim();
    final code = _mobileCode.text.trim();
    if (mobile.isEmpty || code.isEmpty) {
      _showWalletMessage(context, '请输入手机号和验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final info = await widget.controller.confirmMobileBind(
        mobile: mobile,
        code: code,
      );
      if (mounted) {
        setState(() {
          _info = info;
          _mobileCode.clear();
          _editMode = _WalletSecurityEditMode.none;
        });
        _showWalletMessage(context, '手机号已绑定');
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

  Future<void> _sendEmailCode() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _showWalletMessage(context, '请输入邮箱');
      return;
    }
    final captcha = _captchaValue();
    if (captcha.isEmpty) {
      return;
    }
    setState(() => _sendingEmail = true);
    try {
      await widget.controller.sendEmailBindCode(email: email, captcha: captcha);
      if (mounted) {
        _showWalletMessage(context, '验证码已发送');
        _refreshCaptcha();
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
        _refreshCaptcha();
      }
    } finally {
      if (mounted) {
        setState(() => _sendingEmail = false);
      }
    }
  }

  Future<void> _confirmEmail() async {
    final email = _email.text.trim();
    final code = _emailCode.text.trim();
    if (email.isEmpty || code.isEmpty) {
      _showWalletMessage(context, '请输入邮箱和验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final info = await widget.controller.confirmEmailBind(
        email: email,
        code: code,
      );
      if (mounted) {
        setState(() {
          _info = info;
          _emailCode.clear();
          _editMode = _WalletSecurityEditMode.none;
        });
        _showWalletMessage(context, '邮箱已绑定');
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
    final info = _info ?? const UserSecurityInfo();
    return _WalletFormScaffold(
      title: '账号安全',
      children: [
        if (_loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          _WalletPlainNotice(
            icon: info.securityBound
                ? Icons.verified_user_outlined
                : Icons.info_outline,
            text: info.securityBound ? '已绑定安全验证方式' : '请至少绑定手机号或邮箱后再设置支付密码',
            color: info.securityBound
                ? const Color(0xff166534)
                : const Color(0xffb45309),
            background: info.securityBound
                ? const Color(0xfff0fdf4)
                : const Color(0xfffffbeb),
            border: info.securityBound
                ? const Color(0xffbbf7d0)
                : const Color(0xfffde68a),
          ),
        const SizedBox(height: 16),
        _WalletSecurityStatusRow(
          label: '手机号',
          value: info.mobileBound ? info.mobile : '未绑定',
          actionText: info.mobileBound ? '更换' : '绑定',
          selected: _editMode == _WalletSecurityEditMode.mobile,
          onTap: _loading
              ? null
              : () => _startEdit(_WalletSecurityEditMode.mobile),
        ),
        const SizedBox(height: 10),
        _WalletSecurityStatusRow(
          label: '邮箱',
          value: info.emailBound ? info.email : '未绑定',
          actionText: info.emailBound ? '更换' : '绑定',
          selected: _editMode == _WalletSecurityEditMode.email,
          onTap: _loading
              ? null
              : () => _startEdit(_WalletSecurityEditMode.email),
        ),
        if (_editMode != _WalletSecurityEditMode.none) ...[
          const SizedBox(height: 18),
          _WalletSecurityEditPanel(
            title: _editMode == _WalletSecurityEditMode.mobile
                ? (info.mobileBound ? '更换手机号' : '绑定手机号')
                : (info.emailBound ? '更换邮箱' : '绑定邮箱'),
            onClose: _closeEdit,
            children: [
              _WalletImageCaptchaInput(
                controller: _captcha,
                revision: _captchaRevision,
                loader: widget.controller.loadImageCaptcha,
                onRefresh: _refreshCaptcha,
              ),
              const SizedBox(height: 12),
              if (_editMode == _WalletSecurityEditMode.mobile) ...[
                _WalletTextField(
                  controller: _mobile,
                  label: '手机号',
                  hint: '请输入手机号',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                _WalletCodeSendField(
                  controller: _mobileCode,
                  label: '短信验证码',
                  hint: '请输入验证码',
                  buttonText: _sendingMobile ? '发送中...' : '获取短信验证码',
                  onPressed: _sendingMobile || _busy ? null : _sendMobileCode,
                ),
                const SizedBox(height: 12),
                _WalletPrimaryButton(
                  text: _busy ? '保存中...' : '保存手机号',
                  onPressed: _busy ? null : _confirmMobile,
                ),
              ] else ...[
                _WalletTextField(
                  controller: _email,
                  label: '邮箱',
                  hint: '请输入邮箱',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                _WalletCodeSendField(
                  controller: _emailCode,
                  label: '邮箱验证码',
                  hint: '请输入验证码',
                  buttonText: _sendingEmail ? '发送中...' : '获取邮箱验证码',
                  onPressed: _sendingEmail || _busy ? null : _sendEmailCode,
                ),
                const SizedBox(height: 12),
                _WalletPrimaryButton(
                  text: _busy ? '保存中...' : '保存邮箱',
                  onPressed: _busy ? null : _confirmEmail,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

enum _WalletSecurityEditMode { none, mobile, email }

class _WalletSecurityStatusRow extends StatelessWidget {
  const _WalletSecurityStatusRow({
    required this.label,
    required this.value,
    required this.actionText,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final String actionText;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Icon(
                label == '手机号'
                    ? Icons.phone_iphone_outlined
                    : Icons.email_outlined,
                color: selected ? _primaryColor : _secondaryTextColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryTextColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                actionText,
                style: TextStyle(
                  color: selected ? _primaryColor : _secondaryTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                selected ? Icons.keyboard_arrow_up : Icons.chevron_right,
                color: selected ? _primaryColor : _mutedColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletSecurityEditPanel extends StatelessWidget {
  const _WalletSecurityEditPanel({
    required this.title,
    required this.onClose,
    required this.children,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '收起',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 20),
                  color: _secondaryTextColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _WalletImageCaptchaInput extends StatefulWidget {
  const _WalletImageCaptchaInput({
    required this.controller,
    required this.revision,
    required this.loader,
    required this.onRefresh,
  });

  final TextEditingController controller;
  final int revision;
  final Future<ImageCaptcha> Function({required int type}) loader;
  final VoidCallback onRefresh;

  @override
  State<_WalletImageCaptchaInput> createState() =>
      _WalletImageCaptchaInputState();
}

class _WalletImageCaptchaInputState extends State<_WalletImageCaptchaInput> {
  late Future<ImageCaptcha> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loader(type: 3);
  }

  @override
  void didUpdateWidget(covariant _WalletImageCaptchaInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) {
      _future = widget.loader(type: 3);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _WalletTextField(
            controller: widget.controller,
            label: '图片验证码',
            hint: '请输入图片验证码',
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(width: 10),
        FutureBuilder<ImageCaptcha>(
          future: _future,
          builder: (context, snapshot) {
            final captcha = snapshot.data;
            return InkWell(
              onTap: widget.onRefresh,
              child: Container(
                width: 112,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  border: Border.all(color: _lightBorderColor),
                ),
                child: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _WalletCaptchaPreview(captcha: captcha),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WalletCaptchaPreview extends StatelessWidget {
  const _WalletCaptchaPreview({required this.captcha});

  final ImageCaptcha? captcha;

  @override
  Widget build(BuildContext context) {
    final image = captcha?.image.trim() ?? '';
    if (image.isEmpty) {
      return const Icon(Icons.refresh, color: _mutedColor, size: 20);
    }
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(image, fit: BoxFit.cover);
    }
    final raw = image.contains(',') ? image.split(',').last : image;
    try {
      return Image.memory(base64Decode(raw), fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.refresh, color: _mutedColor, size: 20);
    }
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
  final _code = TextEditingController();
  final _captcha = TextEditingController();
  bool _busy = false;
  bool _sendingCode = false;
  WalletBalance? _balance;
  String _method = '';
  int _captchaRevision = 0;

  @override
  void initState() {
    super.initState();
    _balance = widget.controller.walletBalance;
    final methods = _balance?.securityMethods ?? const <WalletSecurityMethod>[];
    if (methods.isNotEmpty) {
      _method = methods.first.method;
    }
    _loadBalance();
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final balance = await widget.controller.loadWalletBalance(refresh: true);
      if (!mounted) {
        return;
      }
      setState(() {
        _balance = balance;
        if (_method.isEmpty && balance.securityMethods.isNotEmpty) {
          _method = balance.securityMethods.first.method;
        }
      });
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    }
  }

  Future<void> _sendCode() async {
    if (_method.isEmpty) {
      _showWalletMessage(context, '请先绑定手机号、邮箱或安全验证方式');
      return;
    }
    final captcha = _captcha.text.trim();
    if (captcha.isEmpty) {
      _showWalletMessage(context, '请先输入图片验证码');
      return;
    }
    setState(() => _sendingCode = true);
    try {
      await widget.controller.sendWalletPayPasswordCode(
        verificationMethod: _method,
        captcha: captcha,
      );
      if (mounted) {
        _showWalletMessage(context, '验证码已发送');
        setState(() {
          _captcha.clear();
          _captchaRevision++;
        });
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
        setState(() {
          _captcha.clear();
          _captchaRevision++;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _sendingCode = false);
      }
    }
  }

  Future<void> _submit() async {
    final value = _password.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(value)) {
      _showWalletMessage(context, '支付密码必须是6位数字');
      return;
    }
    if (value != _confirm.text.trim()) {
      _showWalletMessage(context, '两次密码不一致');
      return;
    }
    final code = _code.text.trim();
    if (code.isEmpty) {
      _showWalletMessage(context, '请输入验证码');
      return;
    }
    if (_method.isEmpty) {
      _showWalletMessage(context, '请先绑定手机号、邮箱或安全验证方式');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.controller.setWalletPayPassword(
        password: value,
        verificationMethod: _method,
        verifyCode: code,
      );
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
    final balance = _balance ?? widget.controller.walletBalance;
    final methods = balance?.securityMethods ?? const <WalletSecurityMethod>[];
    final canSet = methods.isNotEmpty && balance?.payPasswordLocked != true;
    return _WalletFormScaffold(
      title: '支付密码',
      children: [
        _WalletPayPasswordSecurityPanel(
          balance: balance,
          selectedMethod: _method,
          onChanged: methods.isEmpty
              ? null
              : (value) => setState(() => _method = value),
        ),
        if (methods.isEmpty) ...[
          const SizedBox(height: 12),
          _WalletPrimaryButton(
            text: '去绑定安全验证',
            onPressed: () => _push(
              context,
              WalletSecurityPage(controller: widget.controller),
            ).then((_) => _loadBalance()),
          ),
        ],
        const SizedBox(height: 14),
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
        const SizedBox(height: 12),
        _WalletImageCaptchaInput(
          controller: _captcha,
          revision: _captchaRevision,
          loader: widget.controller.loadImageCaptcha,
          onRefresh: () {
            setState(() {
              _captcha.clear();
              _captchaRevision++;
            });
          },
        ),
        const SizedBox(height: 12),
        _WalletCodeSendField(
          controller: _code,
          label: '验证码',
          hint: '安全验证码',
          buttonText: _sendingCode ? '发送中...' : '获取安全验证码',
          onPressed: canSet && !_sendingCode ? _sendCode : null,
        ),
        const SizedBox(height: 22),
        _WalletPrimaryButton(
          text: _busy ? '保存中...' : '保存',
          onPressed: canSet && !_busy ? _submit : null,
        ),
      ],
    );
  }
}

class _WalletPayPasswordSecurityPanel extends StatelessWidget {
  const _WalletPayPasswordSecurityPanel({
    required this.balance,
    required this.selectedMethod,
    required this.onChanged,
  });

  final WalletBalance? balance;
  final String selectedMethod;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final methods = balance?.securityMethods ?? const <WalletSecurityMethod>[];
    if (methods.isEmpty) {
      return const _WalletPlainNotice(
        icon: Icons.info_outline,
        text: '请先绑定手机号、邮箱或安全验证方式',
        color: Color(0xffb45309),
        background: Color(0xfffffbeb),
        border: Color(0xfffde68a),
      );
    }
    final value = methods.any((item) => item.method == selectedMethod)
        ? selectedMethod
        : methods.first.method;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: value,
          decoration: const InputDecoration(
            labelText: '安全验证',
            filled: true,
            fillColor: _surfaceColor,
            border: OutlineInputBorder(
              borderSide: BorderSide(color: _lightBorderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _lightBorderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _primaryColor),
            ),
          ),
          items: [
            for (final method in methods)
              DropdownMenuItem<String>(
                value: method.method,
                child: Text(
                  '${method.label}${method.target.isEmpty ? '' : ' ${method.target}'}',
                ),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (value) {
                  if (value != null) {
                    onChanged!(value);
                  }
                },
        ),
        if (balance?.payPasswordLocked == true) ...[
          const SizedBox(height: 10),
          const _WalletPlainNotice(
            icon: Icons.lock_outline,
            text: '支付密码已锁定，请联系管理员解锁',
            color: Color(0xff991b1b),
            background: Color(0xfffef2f2),
            border: Color(0xfffecaca),
          ),
        ],
      ],
    );
  }
}

class _WalletPlainNotice extends StatelessWidget {
  const _WalletPlainNotice({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
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
                        leading: _WalletBillIcon(
                          income: income,
                          scene: item.scene,
                        ),
                        title: Text(
                          item.targetName.isNotEmpty
                              ? item.targetName
                              : (item.sceneName.isEmpty
                                    ? '余额变动'
                                    : item.sceneName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          [
                            if (item.sceneName.isNotEmpty) item.sceneName,
                            if (item.time.isNotEmpty) item.time,
                          ].join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                        onTap: () => _push(
                          context,
                          WalletBillDetailPage(
                            controller: widget.controller,
                            bill: item,
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

class WalletBillDetailPage extends StatefulWidget {
  const WalletBillDetailPage({
    required this.controller,
    required this.bill,
    super.key,
  });

  final SessionController controller;
  final WalletBill bill;

  @override
  State<WalletBillDetailPage> createState() => _WalletBillDetailPageState();
}

class _WalletBillDetailPageState extends State<WalletBillDetailPage> {
  late Future<WalletBill> _request;

  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadWalletBillDetail(widget.bill.id);
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.bill;
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        title: const Text('账单详情'),
        backgroundColor: _surfaceColor,
        foregroundColor: _textColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: FutureBuilder<WalletBill>(
          future: _request,
          initialData: initial,
          builder: (context, snapshot) {
            final bill = snapshot.data ?? initial;
            final income = bill.direction == 'income';
            return ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 24),
              children: [
                ColoredBox(
                  color: _surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
                    child: Column(
                      children: [
                        _WalletBillIcon(
                          income: income,
                          scene: bill.scene,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          bill.sceneName.isEmpty ? '余额变动' : bill.sceneName,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          bill.amountLabel,
                          style: TextStyle(
                            color: income
                                ? const Color(0xff16a34a)
                                : _textColor,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          bill.statusName.isEmpty ? '交易成功' : bill.statusName,
                          style: const TextStyle(
                            color: _secondaryTextColor,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const _GroupGap(),
                _WalletDetailRow(
                  label: '交易对象',
                  value: bill.targetName.isEmpty ? '-' : bill.targetName,
                ),
                _WalletDetailRow(
                  label: '交易类型',
                  value: bill.sceneName.isEmpty ? '余额变动' : bill.sceneName,
                ),
                _WalletDetailRow(label: '收支方向', value: bill.directionName),
                if (bill.remark.isNotEmpty)
                  _WalletDetailRow(label: '备注', value: bill.remark),
                const _GroupGap(),
                _WalletDetailRow(
                  label: '账单单号',
                  value: bill.billNo.isEmpty ? 'BILL${bill.id}' : bill.billNo,
                  copyable: true,
                ),
                if (bill.orderNo.isNotEmpty)
                  _WalletDetailRow(
                    label: '交易单号',
                    value: bill.orderNo,
                    copyable: true,
                  ),
                _WalletDetailRow(label: '创建时间', value: bill.time),
              ],
            );
          },
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

class _WalletCodeSendField extends StatelessWidget {
  const _WalletCodeSendField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.buttonText,
    required this.onPressed,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String buttonText;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WalletTextField(
          controller: controller,
          label: label,
          hint: hint,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.verified_outlined, size: 18),
            label: Text(buttonText),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primaryColor,
              disabledForegroundColor: _mutedColor,
              side: const BorderSide(color: _primaryColor),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BimRadius.sm),
              ),
            ),
          ),
        ),
      ],
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

class _WalletPayCodeIntro extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.qr_code_2, color: _primaryColor, size: 34),
            SizedBox(height: 14),
            Text(
              '付款码',
              style: TextStyle(
                color: _textColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '出示给商户扫码，金额由商户输入，付款方确认后完成付款。',
              style: TextStyle(
                color: _secondaryTextColor,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletQrPanel extends StatelessWidget {
  const _WalletQrPanel({
    required this.order,
    required this.title,
    required this.subtitle,
    this.loading = false,
    this.showBarcode = false,
    this.errorText = '',
  });

  final WalletOrder? order;
  final String title;
  final String subtitle;
  final bool loading;
  final bool showBarcode;
  final String errorText;

  @override
  Widget build(BuildContext context) {
    final current = order;
    final payload = current?.qrPayload ?? '';
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _mutedColor, fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (showBarcode && current != null)
              _WalletBarcode(
                value: current.barPayload.isEmpty
                    ? current.qrToken
                    : current.barPayload,
              ),
            if (showBarcode) const SizedBox(height: 18),
            Container(
              width: 246,
              height: 246,
              alignment: Alignment.center,
              color: Colors.white,
              child: errorText.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: _mutedColor,
                            size: 30,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            errorText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _mutedColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    )
                  : loading || payload.isEmpty
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : QrImageView(
                      data: payload,
                      version: QrVersions.auto,
                      size: 226,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
            ),
            if ((current?.expireTime ?? '').isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                '有效期至 ${current!.expireTime}',
                style: const TextStyle(color: _mutedColor, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletBarcode extends StatelessWidget {
  const _WalletBarcode({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final text = value.isEmpty ? '000000000000000000' : value;
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 74,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: bw.BarcodeWidget(
            barcode: bw.Barcode.code128(),
            data: text,
            drawText: false,
            color: Colors.black,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          text.length > 22 ? '${text.substring(0, 22)}...' : text,
          style: const TextStyle(
            color: _mutedColor,
            fontSize: 12,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _WalletConfirmHeader extends StatelessWidget {
  const _WalletConfirmHeader({
    required this.title,
    required this.name,
    required this.avatar,
  });

  final String title;
  final String name;
  final String avatar;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surfaceColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          children: [
            _Avatar(
              label: name.isEmpty ? title : name,
              imageUrl: avatar,
              size: 52,
              color: _primaryColor,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(color: _mutedColor, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              name.isEmpty ? '-' : name,
              style: const TextStyle(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
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

class _WalletDetailRow extends StatelessWidget {
  const _WalletDetailRow({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceColor,
      child: InkWell(
        onTap: copyable && value.isNotEmpty
            ? () {
                Clipboard.setData(ClipboardData(text: value));
                _showWalletMessage(context, '已复制');
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 86,
                child: Text(
                  label,
                  style: const TextStyle(color: _mutedColor, fontSize: 14),
                ),
              ),
              Expanded(
                child: Text(
                  value.isEmpty ? '-' : value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WalletBillIcon extends StatelessWidget {
  const _WalletBillIcon({
    required this.income,
    required this.scene,
    this.size = 40,
  });

  final bool income;
  final String scene;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = switch (scene) {
      '7' => Icons.outbox_outlined,
      '8' => Icons.add_card_outlined,
      '9' => Icons.chat_bubble_outline,
      '11' => Icons.qr_code_2,
      _ => Icons.account_balance_wallet_outlined,
    };
    final color = income ? const Color(0xff16a34a) : _dangerColor;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color, size: size * 0.52),
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

String _walletInlineError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  return text.isEmpty ? '操作失败，请稍后再试' : text;
}

Future<String> _showWalletPayPasswordSheet(
  BuildContext context, {
  required String title,
  String amountLabel = '',
}) async {
  final controller = TextEditingController();
  var errorText = '';
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: _surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              22 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xffd4d6dc),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (amountLabel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    amountLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _WalletTextField(
                  controller: controller,
                  label: '支付密码',
                  hint: '6位数字',
                  keyboardType: TextInputType.number,
                  obscureText: true,
                ),
                if (errorText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorText,
                    style: const TextStyle(
                      color: BimColors.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _WalletPrimaryButton(
                  text: '确认',
                  onPressed: () {
                    final password = controller.text.trim();
                    if (!RegExp(r'^\d{6}$').hasMatch(password)) {
                      setModalState(() => errorText = '请输入6位支付密码');
                      return;
                    }
                    Navigator.of(context).pop(password);
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
  controller.dispose();
  return result ?? '';
}
