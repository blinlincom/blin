part of 'package:bim/src/features/home/home_page.dart';

class WalletPayReceivePage extends StatefulWidget {
  const WalletPayReceivePage({required this.controller, super.key});

  final SessionController controller;

  @override
  State<WalletPayReceivePage> createState() => _WalletPayReceivePageState();
}

class _WalletPayReceivePageState extends State<WalletPayReceivePage> {
  WalletOrder? _payOrder;
  String _payError = '';
  bool _payLoading = false;
  bool _payUnlocked = false;
  Timer? _payTimer;
  int _paySecondsLeft = 0;

  @override
  void dispose() {
    _payTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPayCode({
    bool showLoading = true,
    bool requirePassword = true,
  }) async {
    var payPassword = '';
    if (requirePassword && !_payUnlocked) {
      payPassword = await _showWalletPayPasswordSheet(context, title: '打开付款码');
      if (payPassword.isEmpty) {
        return;
      }
    }
    if (showLoading && mounted) {
      setState(() {
        _payLoading = true;
        _payError = '';
      });
    }
    try {
      final order = await widget.controller.currentWalletPayCode(
        payPassword: payPassword,
      );
      if (!mounted) {
        return;
      }
      _startPayCountdown(order);
      setState(() {
        _payOrder = order;
        _payError = '';
        _payLoading = false;
        _payUnlocked = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _payTimer?.cancel();
      final errorText = _walletInlineError(error);
      setState(() {
        _payError = errorText;
        _payLoading = false;
        if (errorText.contains('支付密码')) {
          _payUnlocked = false;
          _payOrder = null;
        }
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
        unawaited(_loadPayCode(showLoading: false, requirePassword: false));
        return;
      }
      setState(() => _paySecondsLeft -= 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: '收付款',
        actions: [
          if (_payOrder != null)
            IconButton(
              tooltip: '刷新付款码',
              onPressed: _payLoading
                  ? null
                  : () => _loadPayCode(requirePassword: false),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          BimBreakpoints.horizontalPadding(context),
          BimSpacing.x4,
          BimBreakpoints.horizontalPadding(context),
          BimSpacing.x8,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WalletPaymentCodeSurface(
                  order: _payOrder,
                  secondsLeft: _paySecondsLeft,
                  busy: _payLoading,
                  errorText: _payError,
                  onOpen: _payLoading
                      ? null
                      : () => _loadPayCode(
                          requirePassword: !_payUnlocked || _payOrder == null,
                        ),
                ),
                const SizedBox(height: BimSpacing.x3),
                BimIconTile(
                  icon: Icons.qr_code_rounded,
                  iconColor: BimColors.success,
                  title: '我的收款码',
                  subtitle: '设置收款金额和备注',
                  onTap: () => _push(
                    context,
                    WalletCollectCodePage(controller: widget.controller),
                  ),
                ),
                BimIconTile(
                  icon: Icons.qr_code_scanner,
                  iconColor: BimColors.primary,
                  title: '扫一扫',
                  subtitle: '扫描付款码或收款码',
                  showDivider: false,
                  onTap: () => _push(
                    context,
                    WalletScanPage(controller: widget.controller),
                  ),
                ),
              ],
            ),
          ),
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
  String _error = '';

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
    try {
      final order = await widget.controller.currentWalletCollectCode(
        amount: amount,
        remark: remark,
      );
      if (mounted) {
        setState(() {
          _order = order;
          _error = '';
        });
      }
      return order;
    } catch (error) {
      if (mounted) {
        setState(() => _error = _walletInlineError(error));
      }
      rethrow;
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _error = '';
      _request = _load(
        amount: _amount.text.trim(),
        remark: _remark.text.trim(),
      );
    });
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
        _error = '';
      });
      _showWalletMessage(context, '收款金额已更新');
    } catch (error) {
      if (mounted) {
        setState(() => _error = _walletInlineError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _settingAmount = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: '我的收款码',
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<WalletOrder>(
        future: _request,
        initialData: _order,
        builder: (context, snapshot) {
          final order = snapshot.data;
          final loading =
              snapshot.connectionState == ConnectionState.waiting &&
              order == null;
          return ListView(
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
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _WalletQrPanel(
                        order: order,
                        title: order == null || order.needsAmountInput
                            ? '扫一扫，向我付款'
                            : '收款金额 ¥${order.amountLabel}',
                        subtitle: order == null
                            ? '正在生成收款码'
                            : (order.remark.isEmpty
                                  ? '无需加好友即可向你付款'
                                  : order.remark),
                        loading: loading,
                        errorText: order == null ? _error : '',
                        onRetry: _refresh,
                      ),
                      const BimSectionHeader(text: '收款设置'),
                      Container(
                        padding: const EdgeInsets.all(BimSpacing.x4),
                        decoration: BoxDecoration(
                          color: BimColors.surface,
                          border: Border.all(color: BimColors.borderLight),
                          borderRadius: BorderRadius.circular(BimRadius.sm),
                        ),
                        child: Column(
                          children: [
                            _WalletTextField(
                              controller: _amount,
                              label: '收款金额',
                              hint: '不填则由付款方输入',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                            const SizedBox(height: BimSpacing.x3),
                            _WalletTextField(
                              controller: _remark,
                              label: '收款备注',
                              hint: '选填',
                            ),
                            const SizedBox(height: BimSpacing.x4),
                            BimButton(
                              label: '更新收款码',
                              icon: Icons.check,
                              busy: _settingAmount,
                              onPressed: _settingAmount ? null : _setAmount,
                            ),
                          ],
                        ),
                      ),
                      if (_error.isNotEmpty && order != null) ...[
                        const SizedBox(height: BimSpacing.x3),
                        BimNoticeBanner(
                          text: _error,
                          tone: BimNoticeTone.error,
                        ),
                      ],
                      const SizedBox(height: BimSpacing.x3),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: BimColors.mutedText,
                          ),
                          SizedBox(width: 6),
                          Text(
                            '收款资金将直接进入钱包余额',
                            style: TextStyle(
                              color: BimColors.mutedText,
                              fontSize: BimTypography.caption,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
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
  WalletOrder? _order;
  String _error = '';
  bool _busy = false;
  bool _unlocked = false;
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _createOrRefresh({bool requirePassword = true}) async {
    if (_busy) {
      return;
    }
    var payPassword = '';
    if (requirePassword && !_unlocked) {
      payPassword = await _showWalletPayPasswordSheet(context, title: '打开付款码');
      if (payPassword.isEmpty) {
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final order = await widget.controller.currentWalletPayCode(
        payPassword: payPassword,
      );
      if (!mounted) {
        return;
      }
      _startCountdown(order);
      setState(() {
        _order = order;
        _error = '';
        _unlocked = true;
      });
    } catch (error) {
      if (mounted) {
        final errorText = _walletInlineError(error);
        if (errorText.contains('支付密码')) {
          setState(() {
            _order = null;
            _unlocked = false;
          });
        }
        setState(() => _error = errorText);
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
        _createOrRefresh(requirePassword: false);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return BimScaffold(
      topBar: BimTopBar(
        title: '付款码',
        actions: [
          if (order != null)
            IconButton(
              tooltip: '刷新付款码',
              onPressed: _busy
                  ? null
                  : () => _createOrRefresh(requirePassword: false),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          BimBreakpoints.horizontalPadding(context),
          BimSpacing.x4,
          BimBreakpoints.horizontalPadding(context),
          BimSpacing.x8,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _WalletPaymentCodeSurface(
              order: order,
              secondsLeft: _secondsLeft,
              busy: _busy,
              errorText: _error,
              onOpen: _busy ? null : _createOrRefresh,
            ),
          ),
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
    return BimScaffold(
      topBar: BimTopBar(title: isPayCode ? '发起收款' : '确认付款'),
      body: BimContentViewport(
        maxWidth: 680,
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
