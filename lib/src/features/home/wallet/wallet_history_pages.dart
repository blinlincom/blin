part of 'package:bim/src/features/home/home_page.dart';

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
    return BimScaffold(
      topBar: const BimTopBar(title: '账单'),
      body: BimContentViewport(
        maxWidth: 760,
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
                    return const BimLoadingState(label: '正在加载账单');
                  }
                  if (list.isEmpty) {
                    return const BimEmptyState(title: '暂无账单');
                  }
                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: _lightBorderColor),
                    itemBuilder: (context, index) {
                      final item = list[index];
                      final income = item.direction == 'income';
                      return BimListTile(
                        minHeight: 64,
                        showDivider: false,
                        leading: _WalletBillIcon(
                          income: income,
                          scene: item.scene,
                        ),
                        title: item.targetName.isNotEmpty
                            ? item.targetName
                            : (item.sceneName.isEmpty
                                  ? '余额变动'
                                  : item.sceneName),
                        subtitle: [
                          if (item.sceneName.isNotEmpty) item.sceneName,
                          if (item.time.isNotEmpty) item.time,
                        ].join('  '),
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
    return BimScaffold(
      topBar: const BimTopBar(title: '账单详情'),
      body: BimContentViewport(
        maxWidth: 680,
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
    return BimScaffold(
      topBar: const BimTopBar(title: '提现记录'),
      body: BimContentViewport(
        maxWidth: 760,
        child: FutureBuilder<List<WalletWithdrawRecord>>(
          future: controller.loadWalletWithdrawRecords(limit: 50),
          builder: (context, snapshot) {
            final list = snapshot.data ?? const <WalletWithdrawRecord>[];
            if (snapshot.connectionState == ConnectionState.waiting &&
                list.isEmpty) {
              return const BimLoadingState(label: '正在加载提现记录');
            }
            if (list.isEmpty) {
              return const BimEmptyState(title: '暂无提现记录');
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _lightBorderColor),
              itemBuilder: (context, index) {
                final item = list[index];
                return BimListTile(
                  minHeight: 60,
                  showDivider: false,
                  title: '¥${item.amount}',
                  subtitle: item.createTime,
                  trailing: Text(
                    item.statusName,
                    style: const TextStyle(
                      color: BimColors.secondaryText,
                      fontSize: BimTypography.meta,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
    return BimScaffold(
      topBar: BimTopBar(title: title),
      body: BimContentViewport(
        maxWidth: 680,
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
        BimButton(
          label: buttonText,
          onPressed: onPressed,
          icon: Icons.verified_outlined,
          kind: BimButtonKind.secondary,
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

class _WalletQrPanel extends StatelessWidget {
  const _WalletQrPanel({
    required this.order,
    required this.title,
    required this.subtitle,
    this.loading = false,
    this.errorText = '',
    this.onRetry,
  });

  final WalletOrder? order;
  final String title;
  final String subtitle;
  final bool loading;
  final String errorText;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final current = order;
    final payload = current?.qrPayload ?? '';
    return Container(
      decoration: BoxDecoration(
        color: BimColors.surface,
        border: Border.all(color: BimColors.borderLight),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
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
            const SizedBox(height: BimSpacing.x5),
            LayoutBuilder(
              builder: (context, constraints) {
                final codeSize = min(
                  constraints.maxWidth - 20,
                  280.0,
                ).clamp(210.0, 280.0);
                return Container(
                  width: codeSize,
                  height: codeSize,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: BimColors.border),
                    borderRadius: BorderRadius.circular(BimRadius.sm),
                  ),
                  child: loading
                      ? const CircularProgressIndicator(strokeWidth: 2.4)
                      : errorText.isNotEmpty || payload.isEmpty
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.qr_code_2,
                              color: BimColors.mutedText,
                              size: 46,
                            ),
                            const SizedBox(height: BimSpacing.x3),
                            Text(
                              errorText.isEmpty ? '收款码暂不可用' : errorText,
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: BimColors.secondaryText,
                                fontSize: BimTypography.meta,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (onRetry != null) ...[
                              const SizedBox(height: BimSpacing.x3),
                              TextButton.icon(
                                onPressed: onRetry,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('重新生成'),
                              ),
                            ],
                          ],
                        )
                      : QrImageView(
                          data: payload,
                          version: QrVersions.auto,
                          size: codeSize - 20,
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
                );
              },
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
      BimSegmentOption(value: 'all', label: '全部'),
      BimSegmentOption(value: 'income', label: '收入'),
      BimSegmentOption(value: 'expense', label: '支出'),
      BimSegmentOption(value: 'charge', label: '充值'),
      BimSegmentOption(value: 'withdraw', label: '提现'),
      BimSegmentOption(value: 'im', label: '红包转账'),
      BimSegmentOption(value: 'scan', label: '扫码'),
    ];
    return BimSegmentedControl<String>(
      options: tabs,
      selected: value,
      onChanged: onChanged,
      scrollable: true,
      height: 38,
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

bool _walletAmountPositive(String value) {
  final normalized = value.replaceAll(',', '').replaceAll('¥', '').trim();
  return (double.tryParse(normalized) ?? 0) > 0;
}

Future<void> _showWalletFreezeDetails(
  BuildContext context,
  WalletBalance balance,
) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: _surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      final records = balance.freezeRecords;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '钱包限制详情',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            _WalletInfoRow(
              label: '钱包状态',
              value: balance.walletStatusName.isEmpty
                  ? (balance.walletStatus == 1 ? '正常' : '受限')
                  : balance.walletStatusName,
            ),
            _WalletInfoRow(
              label: '冻结余额',
              value: '¥${balance.frozenBalanceLabel}',
            ),
            if (balance.walletLockReason.isNotEmpty)
              _WalletInfoRow(label: '锁定原因', value: balance.walletLockReason),
            if (balance.freezeReason.isNotEmpty)
              _WalletInfoRow(label: '冻结原因', value: balance.freezeReason),
            if (records.isNotEmpty) ...[
              const Divider(height: 24),
              for (final item in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '${item.amountLabel}  ${item.reason.isEmpty ? '未填写原因' : item.reason}',
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}

void _showWalletMessage(BuildContext context, String text) {
  final message = text.replaceFirst('Exception: ', '');
  showBimSnackBar(context, message);
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
