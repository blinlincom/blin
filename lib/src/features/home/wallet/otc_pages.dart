part of 'package:bim/src/features/home/home_page.dart';

class OtcHomePage extends StatefulWidget {
  const OtcHomePage({required this.controller, super.key});
  final SessionController controller;
  @override
  State<OtcHomePage> createState() => _OtcHomePageState();
}

class _OtcHomePageState extends State<OtcHomePage> {
  String _side = 'buy';
  late Future<OtcConfig> _config;
  late Future<List<OtcAd>> _ads;

  @override
  void initState() {
    super.initState();
    _config = widget.controller.loadOtcConfig();
    _ads = widget.controller.loadOtcAds('sell');
  }

  void _changeSide(String value) {
    if (_side == value) return;
    setState(() {
      _side = value;
      _ads = widget.controller.loadOtcAds(value == 'buy' ? 'sell' : 'buy');
    });
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: '买卖币',
        actions: [
          IconButton(
            tooltip: '订单',
            onPressed: () =>
                _push(context, OtcOrdersPage(controller: widget.controller)),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: FutureBuilder<OtcConfig>(
        future: _config,
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const BimLoadingState(label: '正在加载交易市场');
          final config = snapshot.data!;
          if (!config.enabled)
            return const BimEmptyState(
              title: '交易市场暂未开放',
              message: '开放后可在这里买卖数字资产',
            );
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  BimBreakpoints.horizontalPadding(context),
                  BimSpacing.x3,
                  BimBreakpoints.horizontalPadding(context),
                  BimSpacing.x2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: BimSegmentedControl<String>(
                        selected: _side,
                        options: const [
                          BimSegmentOption(value: 'buy', label: '买币'),
                          BimSegmentOption(value: 'sell', label: '卖币'),
                        ],
                        onChanged: _changeSide,
                      ),
                    ),
                    const SizedBox(width: BimSpacing.x3),
                    IconButton(
                      tooltip: '交易管理',
                      onPressed: () => _push(
                        context,
                        OtcManagementPage(
                          controller: widget.controller,
                          config: config,
                        ),
                      ),
                      icon: const Icon(Icons.tune_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: FutureBuilder<List<OtcAd>>(
                  future: _ads,
                  builder: (context, adSnapshot) {
                    if (!adSnapshot.hasData)
                      return const BimLoadingState(label: '正在获取报价');
                    final ads = adSnapshot.data!;
                    if (ads.isEmpty)
                      return BimEmptyState(
                        title: _side == 'buy' ? '暂无卖币广告' : '暂无收币广告',
                        message: '可以稍后刷新查看',
                      );
                    return RefreshIndicator(
                      onRefresh: () async {
                        final next = widget.controller.loadOtcAds(
                          _side == 'buy' ? 'sell' : 'buy',
                        );
                        setState(() => _ads = next);
                        await next;
                      },
                      child: ListView.separated(
                        padding: EdgeInsets.only(
                          bottom:
                              MediaQuery.paddingOf(context).bottom +
                              BimSpacing.x4,
                        ),
                        itemCount: ads.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: BimSpacing.x4),
                        itemBuilder: (context, index) => _OtcAdTile(
                          ad: ads[index],
                          actionLabel: _side == 'buy' ? '购买' : '出售',
                          onTap: () => _openOrder(context, ads[index]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openOrder(BuildContext context, OtcAd ad) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _OtcOrderSheet(controller: widget.controller, ad: ad, side: _side),
    );
  }
}

class _OtcAdTile extends StatelessWidget {
  const _OtcAdTile({
    required this.ad,
    required this.actionLabel,
    required this.onTap,
  });
  final OtcAd ad;
  final String actionLabel;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final merchant = ad.merchant;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x4,
        vertical: BimSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${merchant['name'] ?? '认证商家'}',
                  style: const TextStyle(
                    fontSize: BimTypography.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${merchant['completed_orders'] ?? 0} 单 · 好评 ${merchant['positive_rate'] ?? '0.00'}%',
                style: const TextStyle(
                  color: BimColors.secondaryText,
                  fontSize: BimTypography.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: BimSpacing.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '¥ ${ad.price}',
                  style: const TextStyle(
                    color: BimColors.primary,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                width: 84,
                child: BimButton(label: actionLabel, onPressed: onTap),
              ),
            ],
          ),
          const SizedBox(height: BimSpacing.x2),
          Text(
            '限额 ¥${ad.minFiat} - ¥${ad.maxFiat}  ·  ${ad.availableAsset} ${ad.symbol} ${ad.networkCode}',
            style: const TextStyle(
              color: BimColors.secondaryText,
              fontSize: BimTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _OtcOrderSheet extends StatefulWidget {
  const _OtcOrderSheet({
    required this.controller,
    required this.ad,
    required this.side,
  });
  final SessionController controller;
  final OtcAd ad;
  final String side;
  @override
  State<_OtcOrderSheet> createState() => _OtcOrderSheetState();
}

class _OtcOrderSheetState extends State<_OtcOrderSheet> {
  final _amount = TextEditingController();
  bool _busy = false;
  late Future<List<Object>> _options;
  Map<String, Object?>? _address;
  Map<String, Object?>? _payment;

  @override
  void initState() {
    super.initState();
    _options = Future.wait<Object>([
      widget.controller.loadOtcAddresses(),
      widget.controller.loadOtcPaymentMethods(),
    ]);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        BimSpacing.x5,
        BimSpacing.x4,
        BimSpacing.x5,
        MediaQuery.viewInsetsOf(context).bottom + BimSpacing.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.side == 'buy'
                ? '购买 ${widget.ad.symbol}'
                : '出售 ${widget.ad.symbol}',
            style: const TextStyle(
              fontSize: BimTypography.title,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: BimSpacing.x2),
          Text(
            '参考单价 ¥${widget.ad.price} · 限额 ¥${widget.ad.minFiat} - ¥${widget.ad.maxFiat}',
            style: const TextStyle(color: BimColors.secondaryText),
          ),
          const SizedBox(height: BimSpacing.x5),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '交易金额',
              prefixText: '¥ ',
            ),
          ),
          const SizedBox(height: BimSpacing.x4),
          FutureBuilder<List<Object>>(
            future: _options,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const BimLoadingState(label: '正在读取交易资料', compact: true);
              }
              final addresses = snapshot.data![0] as List<Map<String, Object?>>;
              final payments = snapshot.data![1] as List<Map<String, Object?>>;
              _address ??= addresses.isEmpty ? null : addresses.first;
              _payment ??= payments.isEmpty ? null : payments.first;
              return Column(
                children: [
                  _OtcOptionRow(
                    label: '收币地址',
                    value: _address?['address']?.toString() ?? '未绑定',
                    onTap: addresses.isEmpty
                        ? null
                        : () => _selectMap(
                            '选择收币地址',
                            addresses,
                            (value) => setState(() => _address = value),
                          ),
                  ),
                  _OtcOptionRow(
                    label: '收款方式',
                    value: _payment?['account_no_masked']?.toString() ?? '未绑定',
                    onTap: payments.isEmpty
                        ? null
                        : () => _selectMap(
                            '选择收款方式',
                            payments,
                            (value) => setState(() => _payment = value),
                          ),
                  ),
                  if (addresses.isEmpty || payments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: BimSpacing.x3),
                      child: BimNoticeBanner(
                        text: '请先在交易管理中绑定收币地址和实名收款方式。',
                        tone: BimNoticeTone.warning,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: BimSpacing.x3),
          const BimNoticeBanner(text: '数字资产由平台托管，确认法币到账前不要放币。'),
          const SizedBox(height: BimSpacing.x4),
          BimButton(
            label: _busy ? '提交中' : '确认下单',
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final value = double.tryParse(_amount.text.trim());
    if (value == null || value <= 0) {
      showBimSnackBar(context, '请输入正确的交易金额', tone: BimNoticeTone.error);
      return;
    }
    if (_address == null || _payment == null) {
      showBimSnackBar(context, '请先绑定并选择交易资料', tone: BimNoticeTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final order = await widget.controller.createOtcOrder(
        adId: widget.ad.id,
        side: widget.side,
        fiatAmount: _amount.text.trim(),
        addressId: int.tryParse('${_address!['id']}') ?? 0,
        paymentMethodId: int.tryParse('${_payment!['id']}') ?? 0,
      );
      if (!mounted) return;
      Navigator.pop(context);
      showBimSnackBar(
        context,
        '订单 ${order.orderNo} 已创建',
        tone: BimNoticeTone.success,
      );
    } catch (error) {
      if (mounted)
        showBimSnackBar(context, error.toString(), tone: BimNoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectMap(
    String title,
    List<Map<String, Object?>> items,
    ValueChanged<Map<String, Object?>> onSelected,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(BimSpacing.x4),
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: BimTypography.bodyLarge,
                ),
              ),
            ),
            for (final item in items)
              ListTile(
                title: Text('${item['label'] ?? item['account_name'] ?? ''}'),
                subtitle: Text(
                  '${item['address'] ?? item['account_no_masked'] ?? ''}',
                ),
                onTap: () {
                  onSelected(item);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _OtcOptionRow extends StatelessWidget {
  const _OtcOptionRow({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: onTap == null
        ? const Icon(Icons.warning_amber_rounded, color: BimColors.warning)
        : const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

class OtcOrdersPage extends StatefulWidget {
  const OtcOrdersPage({required this.controller, super.key});
  final SessionController controller;
  @override
  State<OtcOrdersPage> createState() => _OtcOrdersPageState();
}

class _OtcOrdersPageState extends State<OtcOrdersPage> {
  late Future<List<OtcOrder>> _request;
  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadOtcOrders();
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: const BimTopBar(title: 'OTC 订单'),
    body: FutureBuilder<List<OtcOrder>>(
      future: _request,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const BimLoadingState(label: '正在加载订单');
        final list = snapshot.data!;
        if (list.isEmpty)
          return const BimEmptyState(
            title: '暂无订单',
            message: '完成买币或卖币下单后会显示在这里',
          );
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: BimSpacing.x4),
          itemBuilder: (context, index) {
            final item = list[index];
            return ListTile(
              title: Text(
                '${item.side == 'buy' ? '买入' : '卖出'} ${item.assetAmount}',
              ),
              subtitle: Text('${item.orderNo}\n${item.expireTime}'),
              isThreeLine: true,
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '¥${item.fiatAmount}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    item.statusName,
                    style: const TextStyle(
                      color: BimColors.secondaryText,
                      fontSize: BimTypography.caption,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

class OtcManagementPage extends StatelessWidget {
  const OtcManagementPage({
    required this.controller,
    required this.config,
    super.key,
  });
  final SessionController controller;
  final OtcConfig config;
  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: const BimTopBar(title: '交易管理'),
    body: ListView(
      children: [
        BimSettingsTile(
          title: '数字资产地址',
          value: 'TRC20、ERC20',
          onTap: () => _push(
            context,
            OtcAddressPage(controller: controller, assets: config.assets),
          ),
        ),
        BimSettingsTile(
          title: '收款方式',
          value: '支付宝、微信、银行卡',
          onTap: () =>
              _push(context, OtcPaymentMethodsPage(controller: controller)),
        ),
        BimSettingsTile(
          title: '商家中心',
          value:
              '${config.merchant['status_name'] ?? '申请认证商家'} · ¥${config.merchantDeposit}',
          onTap: () => _push(
            context,
            OtcMerchantPage(controller: controller, config: config),
          ),
        ),
        const BimNoticeBanner(
          text: '请确认收付款账户实名一致。OTC 交易存在价格波动与欺诈风险，请勿在订单之外私下交易。',
        ),
      ],
    ),
  );
}

class OtcAddressPage extends StatefulWidget {
  const OtcAddressPage({
    required this.controller,
    required this.assets,
    super.key,
  });
  final SessionController controller;
  final List<OtcAsset> assets;
  @override
  State<OtcAddressPage> createState() => _OtcAddressPageState();
}

class _OtcAddressPageState extends State<OtcAddressPage> {
  late Future<List<Map<String, Object?>>> _request;
  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadOtcAddresses();
  }

  Future<void> _add() async {
    if (widget.assets.isEmpty) return;
    final asset = widget.assets.first;
    if (asset.networks.isEmpty) return;
    final network = asset.networks.first;
    final address = TextEditingController();
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加 ${network.code} 地址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            TextField(
              controller: address,
              decoration: const InputDecoration(labelText: '收币地址'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.saveOtcAddress(
        assetId: asset.id,
        networkId: network.id,
        label: label.text.trim(),
        address: address.text.trim(),
      );
      if (!mounted) return;
      setState(() => _request = widget.controller.loadOtcAddresses());
      showBimSnackBar(context, '地址已保存', tone: BimNoticeTone.success);
    } catch (error) {
      if (mounted)
        showBimSnackBar(context, error.toString(), tone: BimNoticeTone.error);
    }
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: BimTopBar(
      title: '数字资产地址',
      actions: [
        IconButton(
          tooltip: '添加地址',
          onPressed: _add,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _request,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const BimLoadingState(label: '正在加载地址');
        final list = snapshot.data!;
        if (list.isEmpty)
          return BimEmptyState(
            title: '暂无收币地址',
            message: '添加与交易网络一致的地址',
            actionLabel: '添加地址',
            onAction: _add,
          );
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: BimSpacing.x4),
          itemBuilder: (context, index) {
            final item = list[index];
            return ListTile(
              title: Text('${item['label'] ?? item['network_code'] ?? ''}'),
              subtitle: Text('${item['address'] ?? ''}', maxLines: 2),
              trailing: Text(
                '${item['network_code'] ?? ''}',
                style: const TextStyle(color: BimColors.secondaryText),
              ),
            );
          },
        );
      },
    ),
  );
}

class OtcPaymentMethodsPage extends StatefulWidget {
  const OtcPaymentMethodsPage({required this.controller, super.key});
  final SessionController controller;
  @override
  State<OtcPaymentMethodsPage> createState() => _OtcPaymentMethodsPageState();
}

class _OtcPaymentMethodsPageState extends State<OtcPaymentMethodsPage> {
  late Future<List<Map<String, Object?>>> _request;
  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadOtcPaymentMethods();
  }

  Future<void> _add() async {
    String type = 'alipay';
    final name = TextEditingController();
    final account = TextEditingController();
    final bank = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('添加收款方式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'alipay', child: Text('支付宝')),
                  DropdownMenuItem(value: 'wechat', child: Text('微信')),
                  DropdownMenuItem(value: 'bank', child: Text('银行卡')),
                ],
                onChanged: (value) => setLocal(() => type = value ?? type),
              ),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '实名姓名'),
              ),
              TextField(
                controller: account,
                decoration: const InputDecoration(labelText: '账号或卡号'),
              ),
              if (type == 'bank')
                TextField(
                  controller: bank,
                  decoration: const InputDecoration(labelText: '开户银行'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.saveOtcPaymentMethod(
        type: type,
        name: name.text.trim(),
        account: account.text.trim(),
        bankName: bank.text.trim(),
      );
      if (!mounted) return;
      setState(() => _request = widget.controller.loadOtcPaymentMethods());
      showBimSnackBar(context, '收款方式已保存', tone: BimNoticeTone.success);
    } catch (error) {
      if (mounted)
        showBimSnackBar(context, error.toString(), tone: BimNoticeTone.error);
    }
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: BimTopBar(
      title: '收款方式',
      actions: [
        IconButton(
          tooltip: '添加收款方式',
          onPressed: _add,
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _request,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const BimLoadingState(label: '正在加载收款方式');
        final list = snapshot.data!;
        if (list.isEmpty)
          return BimEmptyState(
            title: '暂无收款方式',
            message: '绑定本人实名支付宝、微信或银行卡',
            actionLabel: '添加',
            onAction: _add,
          );
        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: BimSpacing.x4),
          itemBuilder: (context, index) {
            final item = list[index];
            return ListTile(
              title: Text('${item['account_name'] ?? ''}'),
              subtitle: Text('${item['account_no_masked'] ?? ''}'),
              trailing: Text(
                _paymentMethodLabel('${item['method_type'] ?? ''}'),
              ),
            );
          },
        );
      },
    ),
  );
}

class OtcMerchantPage extends StatefulWidget {
  const OtcMerchantPage({
    required this.controller,
    required this.config,
    super.key,
  });
  final SessionController controller;
  final OtcConfig config;
  @override
  State<OtcMerchantPage> createState() => _OtcMerchantPageState();
}

class _OtcMerchantPageState extends State<OtcMerchantPage> {
  late Map<String, Object?> _merchant;
  @override
  void initState() {
    super.initState();
    _merchant = Map<String, Object?>.from(widget.config.merchant);
  }

  @override
  Widget build(BuildContext context) {
    final applied = _merchant['applied'] == true;
    final paid = double.tryParse('${_merchant['deposit_amount'] ?? '0'}') ?? 0;
    final required = double.tryParse(widget.config.merchantDeposit) ?? 0;
    return BimScaffold(
      topBar: const BimTopBar(title: '商家中心'),
      body: ListView(
        padding: const EdgeInsets.all(BimSpacing.x4),
        children: [
          Text(
            applied ? '${_merchant['status_name'] ?? '审核中'}' : '认证商家',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: BimSpacing.x2),
          Text(
            '保证金 ¥${widget.config.merchantDeposit} · 已缴 ¥${paid.toStringAsFixed(2)}',
            style: const TextStyle(color: BimColors.secondaryText),
          ),
          const SizedBox(height: BimSpacing.x5),
          if (!applied)
            BimButton(
              label: '提交商家申请',
              onPressed: () async {
                try {
                  final result = await widget.controller.applyOtcMerchant();
                  if (context.mounted) {
                    setState(() => _merchant = result);
                    showBimSnackBar(
                      context,
                      '申请已提交',
                      tone: BimNoticeTone.success,
                    );
                  }
                } catch (error) {
                  if (context.mounted)
                    showBimSnackBar(
                      context,
                      error.toString(),
                      tone: BimNoticeTone.error,
                    );
                }
              },
            ),
          if (applied && paid < required)
            BimButton(label: '缴纳保证金', onPressed: _payDeposit),
          const SizedBox(height: BimSpacing.x4),
          const BimNoticeBanner(
            text: '商家必须使用本人实名收付款方式，不得诱导用户离开平台交易。违规可能冻结保证金和交易权限。',
            tone: BimNoticeTone.warning,
          ),
        ],
      ),
    );
  }

  Future<void> _payDeposit() async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('验证支付密码'),
        content: TextField(
          controller: password,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '支付密码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认缴纳'),
          ),
        ],
      ),
    );
    if (ok != true) {
      password.dispose();
      return;
    }
    try {
      final result = await widget.controller.payOtcMerchantDeposit(
        password.text,
      );
      password.clear();
      password.dispose();
      if (!mounted) return;
      setState(() => _merchant = result);
      showBimSnackBar(context, '保证金缴纳成功', tone: BimNoticeTone.success);
    } catch (error) {
      password.clear();
      password.dispose();
      if (mounted)
        showBimSnackBar(context, error.toString(), tone: BimNoticeTone.error);
    }
  }
}

String _paymentMethodLabel(String type) => switch (type) {
  'alipay' => '支付宝',
  'wechat' => '微信',
  'bank' => '银行卡',
  _ => '收款方式',
};
