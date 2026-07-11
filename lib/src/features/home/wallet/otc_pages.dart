part of 'package:bim/src/features/home/home_page.dart';

class OtcHomePage extends StatefulWidget {
  const OtcHomePage({required this.controller, super.key});
  final SessionController controller;

  @override
  State<OtcHomePage> createState() => _OtcHomePageState();
}

class _OtcHomePageState extends State<OtcHomePage> {
  String _mode = 'quick';
  String _side = 'buy';
  String _asset = '';
  String _payment = 'all';
  String _fiatAmount = '';
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

  Future<void> _refresh() async {
    final next = widget.controller.loadOtcAds(_side == 'buy' ? 'sell' : 'buy');
    setState(() => _ads = next);
    await next;
  }

  List<OtcAd> _filtered(List<OtcAd> source) {
    return source
        .where((ad) {
          if (_asset.isNotEmpty && ad.symbol != _asset) return false;
          if (_payment != 'all' && !ad.paymentMethods.contains(_payment)) {
            return false;
          }
          final requested = double.tryParse(_fiatAmount) ?? 0;
          if (requested > 0) {
            final minimum = double.tryParse(ad.minFiat) ?? 0;
            final maximum = double.tryParse(ad.maxFiat) ?? 0;
            if (requested < minimum || (maximum > 0 && requested > maximum)) {
              return false;
            }
          }
          return true;
        })
        .toList(growable: false)
      ..sort((left, right) {
        final leftPrice = double.tryParse(left.price) ?? double.infinity;
        final rightPrice = double.tryParse(right.price) ?? double.infinity;
        return _side == 'buy'
            ? leftPrice.compareTo(rightPrice)
            : rightPrice.compareTo(leftPrice);
      });
  }

  @override
  Widget build(BuildContext context) {
    return BimScaffold(
      topBar: BimTopBar(
        title: 'OTC 买卖',
        actions: [
          IconButton(
            tooltip: '订单',
            onPressed: () =>
                _push(context, OtcOrdersPage(controller: widget.controller)),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: '交易管理',
            onPressed: () async {
              final config = await _config;
              if (!context.mounted) return;
              await _push(
                context,
                OtcManagementPage(
                  controller: widget.controller,
                  config: config,
                ),
              );
            },
            icon: const Icon(Icons.manage_accounts_outlined),
          ),
        ],
      ),
      body: FutureBuilder<OtcConfig>(
        future: _config,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const BimLoadingState(label: '正在加载交易市场');
          }
          final config = snapshot.data!;
          if (!config.enabled) {
            return const BimEmptyState(
              title: '交易市场暂未开放',
              message: '开放后可在这里买卖数字资产',
            );
          }
          if (_asset.isEmpty && config.assets.isNotEmpty) {
            _asset = config.assets.first.symbol;
          }
          return FutureBuilder<List<OtcAd>>(
            future: _ads,
            builder: (context, adSnapshot) {
              final source = adSnapshot.data ?? const <OtcAd>[];
              final ads = _filtered(source);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: BimContentViewport(
                        maxWidth: 1040,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            BimBreakpoints.horizontalPadding(context),
                            BimSpacing.x3,
                            BimBreakpoints.horizontalPadding(context),
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _OtcModeTabs(
                                value: _mode,
                                onChanged: (value) =>
                                    setState(() => _mode = value),
                              ),
                              const SizedBox(height: BimSpacing.x4),
                              BimSegmentedControl<String>(
                                selected: _side,
                                options: const [
                                  BimSegmentOption(value: 'buy', label: '买入'),
                                  BimSegmentOption(value: 'sell', label: '卖出'),
                                ],
                                onChanged: _changeSide,
                              ),
                              const SizedBox(height: BimSpacing.x3),
                              _OtcFilterBar(
                                assets: config.assets,
                                asset: _asset,
                                payment: _payment,
                                fiatAmount: _fiatAmount,
                                onAssetChanged: (value) =>
                                    setState(() => _asset = value),
                                onPaymentChanged: (value) =>
                                    setState(() => _payment = value),
                                onAmountChanged: (value) =>
                                    setState(() => _fiatAmount = value),
                              ),
                              const SizedBox(height: BimSpacing.x3),
                              if (_mode == 'quick')
                                _OtcQuickPanel(
                                  side: _side,
                                  asset: _asset,
                                  ads: ads,
                                  onContinue: (ad) => _openOrder(context, ad),
                                )
                              else
                                const _OtcMarketHeading(),
                              const SizedBox(height: BimSpacing.x3),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (adSnapshot.connectionState == ConnectionState.waiting &&
                        !adSnapshot.hasData)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: BimLoadingState(label: '正在获取报价'),
                      )
                    else if (ads.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: BimEmptyState(
                          title: _side == 'buy' ? '暂无可购买报价' : '暂无可出售报价',
                          message: '可调整资产或支付方式后重试',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          BimBreakpoints.horizontalPadding(context),
                          0,
                          BimBreakpoints.horizontalPadding(context),
                          MediaQuery.paddingOf(context).bottom + BimSpacing.x6,
                        ),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.crossAxisExtent >= 820
                                ? 2
                                : 1;
                            if (columns == 1) {
                              return SliverList.separated(
                                itemCount: ads.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) => _OtcAdTile(
                                  ad: ads[index],
                                  actionLabel: _side == 'buy' ? '购买' : '出售',
                                  onTap: () => _openOrder(context, ads[index]),
                                ),
                              );
                            }
                            return SliverGrid.builder(
                              itemCount: ads.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisExtent: 220,
                                    crossAxisSpacing: BimSpacing.x4,
                                    mainAxisSpacing: BimSpacing.x4,
                                  ),
                              itemBuilder: (context, index) => Container(
                                decoration: BoxDecoration(
                                  color: BimColors.surface,
                                  border: Border.all(color: BimColors.border),
                                  borderRadius: BorderRadius.circular(
                                    BimRadius.md,
                                  ),
                                ),
                                child: _OtcAdTile(
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
                ),
              );
            },
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
      backgroundColor: BimColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) =>
          _OtcOrderSheet(controller: widget.controller, ad: ad, side: _side),
    );
  }
}

class _OtcModeTabs extends StatelessWidget {
  const _OtcModeTabs({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final item in const [('quick', '快捷买卖'), ('market', '自选广告')])
        Padding(
          padding: const EdgeInsets.only(right: BimSpacing.x5),
          child: BimPressable(
            onTap: () => onChanged(item.$1),
            semanticLabel: item.$2,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BimSpacing.x2),
              child: Column(
                children: [
                  Text(
                    item.$2,
                    style: TextStyle(
                      color: value == item.$1
                          ? BimColors.textDark
                          : BimColors.secondaryText,
                      fontSize: BimTypography.bodyLarge,
                      fontWeight: value == item.$1
                          ? FontWeight.w800
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 28,
                    height: 3,
                    color: value == item.$1
                        ? BimColors.primary
                        : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

class _OtcFilterBar extends StatelessWidget {
  const _OtcFilterBar({
    required this.assets,
    required this.asset,
    required this.payment,
    required this.fiatAmount,
    required this.onAssetChanged,
    required this.onPaymentChanged,
    required this.onAmountChanged,
  });
  final List<OtcAsset> assets;
  final String asset;
  final String payment;
  final String fiatAmount;
  final ValueChanged<String> onAssetChanged;
  final ValueChanged<String> onPaymentChanged;
  final ValueChanged<String> onAmountChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _OtcPopupFilter(
          label: asset.isEmpty ? '资产' : asset,
          values: {for (final item in assets) item.symbol: item.symbol},
          value: asset,
          onChanged: onAssetChanged,
        ),
        const SizedBox(width: BimSpacing.x2),
        _OtcPopupFilter(
          label: payment == 'all' ? '支付方式' : _paymentMethodLabel(payment),
          values: const {
            'all': '全部支付方式',
            'alipay': '支付宝',
            'wechat': '微信',
            'bank': '银行卡',
          },
          value: payment,
          onChanged: onPaymentChanged,
        ),
        const SizedBox(width: BimSpacing.x2),
        BimPressable(
          onTap: () => _showAmountFilter(context),
          semanticLabel: '按金额筛选',
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x3),
            color: BimColors.fill,
            child: Row(
              children: [
                Text(
                  fiatAmount.isEmpty ? '金额' : '¥$fiatAmount',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(width: BimSpacing.x2),
        Container(
          height: 36,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x3),
          color: BimColors.fill,
          child: const Text(
            'CNY',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  Future<void> _showAmountFilter(BuildContext context) async {
    final controller = TextEditingController(text: fiatAmount);
    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: BimColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Padding(
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
            const Text(
              '交易金额',
              style: TextStyle(
                color: BimColors.textDark,
                fontSize: BimTypography.title,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: BimSpacing.x4),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: '按人民币金额筛选',
                prefixText: '¥ ',
              ),
            ),
            const SizedBox(height: BimSpacing.x4),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, ''),
                    child: const Text('清除'),
                  ),
                ),
                const SizedBox(width: BimSpacing.x3),
                Expanded(
                  flex: 2,
                  child: BimButton(
                    label: '应用',
                    onPressed: () {
                      final value = double.tryParse(controller.text.trim());
                      if (value == null || value <= 0) return;
                      Navigator.pop(context, value.toStringAsFixed(2));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) onAmountChanged(result);
  }
}

class _OtcPopupFilter extends StatelessWidget {
  const _OtcPopupFilter({
    required this.label,
    required this.values,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final Map<String, String> values;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: label,
    initialValue: value,
    onSelected: onChanged,
    itemBuilder: (context) => [
      for (final entry in values.entries)
        PopupMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x3),
      color: BimColors.fill,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    ),
  );
}

class _OtcQuickPanel extends StatelessWidget {
  const _OtcQuickPanel({
    required this.side,
    required this.asset,
    required this.ads,
    required this.onContinue,
  });
  final String side;
  final String asset;
  final List<OtcAd> ads;
  final ValueChanged<OtcAd> onContinue;

  @override
  Widget build(BuildContext context) {
    final best = ads.isEmpty ? null : ads.first;
    return Container(
      padding: const EdgeInsets.all(BimSpacing.x4),
      color: BimColors.primaryWeak,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            color: BimColors.surface,
            child: const Icon(Icons.bolt_outlined, color: BimColors.primary),
          ),
          const SizedBox(width: BimSpacing.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${side == 'buy' ? '快捷买入' : '快捷卖出'} $asset',
                  style: const TextStyle(
                    color: BimColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  best == null
                      ? '当前暂无符合条件的报价'
                      : '从当前认证商家报价中选择，单价 ¥${best.price}',
                  style: const TextStyle(
                    color: BimColors.secondaryText,
                    fontSize: BimTypography.caption,
                  ),
                ),
              ],
            ),
          ),
          if (best != null)
            TextButton(
              onPressed: () => onContinue(best),
              child: const Text('立即交易'),
            ),
        ],
      ),
    );
  }
}

class _OtcMarketHeading extends StatelessWidget {
  const _OtcMarketHeading();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(
        child: Text(
          '认证商家报价',
          style: TextStyle(
            color: BimColors.textDark,
            fontSize: BimTypography.bodyLarge,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Icon(Icons.verified_user_outlined, size: 18, color: BimColors.success),
      SizedBox(width: 4),
      Text(
        '平台托管',
        style: TextStyle(
          color: BimColors.secondaryText,
          fontSize: BimTypography.caption,
        ),
      ),
    ],
  );
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
    final merchantName = '${merchant['name'] ?? '认证商家'}'.trim();
    final completed = int.tryParse('${merchant['completed_orders'] ?? 0}') ?? 0;
    final positive = '${merchant['positive_rate'] ?? ''}'.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x3,
        vertical: BimSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                color: BimColors.primaryWeak,
                child: Text(
                  merchantName.isEmpty ? '商' : merchantName.substring(0, 1),
                  style: const TextStyle(
                    color: BimColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: BimSpacing.x2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            merchantName.isEmpty ? '认证商家' : merchantName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.verified,
                          color: BimColors.success,
                          size: 16,
                        ),
                      ],
                    ),
                    if (completed > 0 || positive.isNotEmpty)
                      Text(
                        [
                          if (completed > 0) '成交 $completed 单',
                          if (positive.isNotEmpty) '好评 $positive%',
                        ].join(' · '),
                        style: const TextStyle(
                          color: BimColors.secondaryText,
                          fontSize: BimTypography.caption,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: BimSpacing.x3),
          Text(
            '¥${ad.price}',
            style: const TextStyle(
              color: BimColors.textDark,
              fontSize: 27,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: BimSpacing.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '限额 ¥${ad.minFiat} - ¥${ad.maxFiat}',
                      style: const TextStyle(
                        color: BimColors.secondaryText,
                        fontSize: BimTypography.caption,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '可交易 ${ad.availableAsset} ${ad.symbol} · ${ad.networkCode}',
                      style: const TextStyle(
                        color: BimColors.secondaryText,
                        fontSize: BimTypography.caption,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: BimSpacing.x2,
                      runSpacing: 4,
                      children: [
                        for (final method in ad.paymentMethods)
                          _OtcPaymentLabel(type: method),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BimSpacing.x3),
              SizedBox(
                width: 82,
                child: BimButton(label: actionLabel, onPressed: onTap),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OtcPaymentLabel extends StatelessWidget {
  const _OtcPaymentLabel({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'alipay' => BimColors.primary,
      'wechat' => BimColors.success,
      'bank' => BimColors.transfer,
      _ => BimColors.secondaryText,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 3, height: 13, color: color),
        const SizedBox(width: 5),
        Text(
          _paymentMethodLabel(type),
          style: const TextStyle(
            color: BimColors.secondaryText,
            fontSize: BimTypography.caption,
          ),
        ),
      ],
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
  late Future<Map<String, Object?>> _options;
  Map<String, Object?>? _address;
  Map<String, Object?>? _payment;

  @override
  void initState() {
    super.initState();
    _options = widget.controller.loadOtcTradeOptions(
      adId: widget.ad.id,
      side: widget.side,
    );
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
          FutureBuilder<Map<String, Object?>>(
            future: _options,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const BimLoadingState(label: '正在读取交易资料', compact: true);
              }
              final addressRaw = snapshot.data!['addresses'];
              final paymentRaw = snapshot.data!['payments'];
              final addresses = addressRaw is List
                  ? addressRaw
                        .map((item) => Map<String, Object?>.from(item as Map))
                        .toList(growable: false)
                  : const <Map<String, Object?>>[];
              final payments = paymentRaw is List
                  ? paymentRaw
                        .map((item) => Map<String, Object?>.from(item as Map))
                        .toList(growable: false)
                  : const <Map<String, Object?>>[];
              _address ??= addresses.isEmpty ? null : addresses.first;
              _payment ??= payments.isEmpty ? null : payments.first;
              return Column(
                children: [
                  _OtcOptionRow(
                    label: '数字资产账户',
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
                    label: '结算方式',
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
                    Padding(
                      padding: const EdgeInsets.only(top: BimSpacing.x3),
                      child: BimNoticeBanner(
                        text: '平台余额或数字资产账户当前不可用，请稍后重试。',
                        tone: BimNoticeTone.warning,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: BimSpacing.x3),
          const BimNoticeBanner(text: '平台余额与数字资产由平台同时托管，订单取消或超时会自动原路退回。'),
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
    final minimum = double.tryParse(widget.ad.minFiat) ?? 0;
    final maximum = double.tryParse(widget.ad.maxFiat) ?? 0;
    final price = double.tryParse(widget.ad.price) ?? 0;
    final available = double.tryParse(widget.ad.availableAsset) ?? 0;
    if (value < minimum || (maximum > 0 && value > maximum)) {
      showBimSnackBar(
        context,
        '交易金额需在 ¥${widget.ad.minFiat} - ¥${widget.ad.maxFiat} 之间',
        tone: BimNoticeTone.warning,
      );
      return;
    }
    if (price <= 0 || available <= 0 || value / price > available) {
      showBimSnackBar(context, '当前广告可交易数量不足', tone: BimNoticeTone.warning);
      return;
    }
    if (_address == null || _payment == null) {
      showBimSnackBar(context, '请先绑定并选择交易资料', tone: BimNoticeTone.warning);
      return;
    }
    final assetAmount = value / price;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.side == 'buy' ? '确认购买' : '确认出售'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OtcConfirmRow(
              label: '交易金额',
              value: '¥${value.toStringAsFixed(2)}',
            ),
            _OtcConfirmRow(label: '参考单价', value: '¥${widget.ad.price}'),
            _OtcConfirmRow(
              label: '预计数量',
              value: '${assetAmount.toStringAsFixed(6)} ${widget.ad.symbol}',
            ),
            _OtcConfirmRow(label: '资产网络', value: widget.ad.networkCode),
            const SizedBox(height: BimSpacing.x3),
            const Text(
              '订单创建后请仅按订单信息完成交易，不接受私下更换账户或脱离平台处理。',
              style: TextStyle(
                color: BimColors.secondaryText,
                fontSize: BimTypography.caption,
                height: 1.45,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回检查'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认下单'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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

class _OtcConfirmRow extends StatelessWidget {
  const _OtcConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: BimSpacing.x2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: BimColors.secondaryText),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
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
  String _scope = 'active';
  late Future<List<OtcOrder>> _request;
  @override
  void initState() {
    super.initState();
    _request = widget.controller.loadOtcOrders();
  }

  bool _ended(OtcOrder item) {
    final text = '${item.status} ${item.statusName}'.toLowerCase();
    return const [
          'completed',
          'cancelled',
          'canceled',
          'expired',
          'closed',
        ].any(text.contains) ||
        text.contains('完成') ||
        text.contains('取消') ||
        text.contains('过期') ||
        text.contains('关闭');
  }

  Future<void> _refresh() async {
    final next = widget.controller.loadOtcOrders();
    setState(() => _request = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => BimScaffold(
    topBar: const BimTopBar(title: '订单'),
    body: FutureBuilder<List<OtcOrder>>(
      future: _request,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const BimLoadingState(label: '正在加载订单');
        }
        final list = snapshot.data!;
        final visible = list
            .where(
              (item) =>
                  _scope == 'all' || (_ended(item) == (_scope == 'ended')),
            )
            .toList(growable: false);
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                BimBreakpoints.horizontalPadding(context),
                BimSpacing.x3,
                BimBreakpoints.horizontalPadding(context),
                BimSpacing.x2,
              ),
              child: BimSegmentedControl<String>(
                selected: _scope,
                options: const [
                  BimSegmentOption(value: 'active', label: '进行中'),
                  BimSegmentOption(value: 'ended', label: '已结束'),
                  BimSegmentOption(value: 'all', label: '全部'),
                ],
                onChanged: (value) => setState(() => _scope = value),
              ),
            ),
            Expanded(
              child: visible.isEmpty
                  ? BimEmptyState(
                      title: _scope == 'active' ? '暂无进行中订单' : '暂无订单',
                      message: '完成买币或卖币下单后会显示在这里',
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          BimBreakpoints.horizontalPadding(context),
                          BimSpacing.x2,
                          BimBreakpoints.horizontalPadding(context),
                          MediaQuery.paddingOf(context).bottom + BimSpacing.x4,
                        ),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) =>
                            _OtcOrderTile(order: visible[index]),
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

class _OtcOrderTile extends StatelessWidget {
  const _OtcOrderTile({required this.order});
  final OtcOrder order;

  @override
  Widget build(BuildContext context) {
    final buying = order.side == 'buy';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BimSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                buying ? '买入' : '卖出',
                style: TextStyle(
                  color: buying ? BimColors.successText : BimColors.danger,
                  fontSize: BimTypography.bodyLarge,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: BimSpacing.x2),
              const Expanded(
                child: Text(
                  '数字资产',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                order.statusName,
                style: const TextStyle(color: BimColors.secondaryText),
              ),
            ],
          ),
          const SizedBox(height: BimSpacing.x2),
          Row(
            children: [
              Expanded(
                child: Text(
                  '单价 ¥${order.price}\n数量 ${order.assetAmount}',
                  style: const TextStyle(
                    color: BimColors.secondaryText,
                    fontSize: BimTypography.caption,
                    height: 1.6,
                  ),
                ),
              ),
              Text(
                '¥${order.fiatAmount}',
                style: const TextStyle(
                  color: BimColors.textDark,
                  fontSize: BimTypography.bodyLarge,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: BimSpacing.x2),
          Text(
            '订单号 ${order.orderNo} · ${order.expireTime}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BimColors.mutedText,
              fontSize: BimTypography.caption,
            ),
          ),
        ],
      ),
    );
  }
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
    final reserved =
        double.tryParse('${_merchant['deposit_ad_reserved'] ?? '0'}') ?? 0;
    final available = (paid - reserved).clamp(0, double.infinity);
    final required = double.tryParse(widget.config.merchantDeposit) ?? 0;
    final approved = applied && _merchant['status'] == 1;
    final status = applied ? '${_merchant['status_name'] ?? '审核中'}' : '未申请';
    return BimScaffold(
      topBar: const BimTopBar(title: '商家中心'),
      body: ListView(
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
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      color: BimColors.primaryWeak,
                      child: const Icon(
                        Icons.storefront_outlined,
                        color: BimColors.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: BimSpacing.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'OTC 认证商家',
                            style: TextStyle(
                              color: BimColors.textDark,
                              fontSize: BimTypography.profile,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            status,
                            style: TextStyle(
                              color: approved
                                  ? BimColors.successText
                                  : BimColors.secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: BimSpacing.x5),
                Container(
                  padding: const EdgeInsets.all(BimSpacing.x4),
                  decoration: BoxDecoration(
                    color: BimColors.surface,
                    border: Border.all(color: BimColors.border),
                    borderRadius: BorderRadius.circular(BimRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '保证金资金看板',
                        style: TextStyle(
                          color: BimColors.textDark,
                          fontSize: BimTypography.bodyLarge,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: BimSpacing.x4),
                      _OtcMerchantMetric(
                        label: '保证金总额',
                        value: '¥${paid.toStringAsFixed(2)}',
                      ),
                      _OtcMerchantMetric(
                        label: '广告占用',
                        value: '¥${reserved.toStringAsFixed(2)}',
                      ),
                      _OtcMerchantMetric(
                        label: '可用保证金',
                        value: '¥${available.toStringAsFixed(2)}',
                        strong: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: BimSpacing.x4),
                Container(
                  decoration: BoxDecoration(
                    color: BimColors.surface,
                    border: Border.all(color: BimColors.border),
                    borderRadius: BorderRadius.circular(BimRadius.md),
                  ),
                  child: Column(
                    children: [
                      BimSettingsTile(
                        title: '收款方式',
                        value: '管理本人实名收款账户',
                        onTap: () => _push(
                          context,
                          OtcPaymentMethodsPage(controller: widget.controller),
                        ),
                      ),
                      const Divider(height: 1),
                      BimSettingsTile(
                        title: '数字资产地址',
                        value: '管理交易网络与地址',
                        onTap: () => _push(
                          context,
                          OtcAddressPage(
                            controller: widget.controller,
                            assets: widget.config.assets,
                          ),
                        ),
                      ),
                      if (approved && paid >= required) ...[
                        const Divider(height: 1),
                        BimSettingsTile(
                          title: '发布广告',
                          value: '创建买入或卖出广告',
                          onTap: () => _push(
                            context,
                            OtcAdComposerPage(
                              controller: widget.controller,
                              config: widget.config,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: BimSpacing.x4),
                if (!applied)
                  BimButton(label: '冻结保证金并申请', onPressed: _applyMerchant),
                if (approved && paid < required)
                  BimButton(label: '缴纳保证金', onPressed: _payDeposit),
                if (applied && !approved)
                  BimNoticeBanner(
                    text: '当前申请状态：$status。审核通过且保证金满足要求后，才可以发布广告。',
                  ),
                const SizedBox(height: BimSpacing.x4),
                const BimNoticeBanner(
                  text: '商家必须使用本人实名收付款方式，不得诱导用户离开平台交易。违规可能冻结保证金和交易权限。',
                  tone: BimNoticeTone.warning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _applyMerchant() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('申请认证商家'),
        content: Text(
          '申请时将从钱包冻结 ¥${widget.config.merchantDeposit} 保证金。审核驳回后将自动退回钱包。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
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
            child: const Text('确认申请'),
          ),
        ],
      ),
    );
    if (ok != true) {
      password.dispose();
      return;
    }
    try {
      final result = await widget.controller.applyOtcMerchant(
        payPassword: password.text,
      );
      password.clear();
      password.dispose();
      if (!mounted) return;
      setState(() => _merchant = result);
      showBimSnackBar(context, '保证金已冻结，申请已提交', tone: BimNoticeTone.success);
    } catch (error) {
      password.clear();
      password.dispose();
      if (mounted)
        showBimSnackBar(context, error.toString(), tone: BimNoticeTone.error);
    }
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

class _OtcMerchantMetric extends StatelessWidget {
  const _OtcMerchantMetric({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: BimSpacing.x2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: BimColors.secondaryText),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: BimColors.textDark,
            fontSize: strong ? BimTypography.bodyLarge : BimTypography.body,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class OtcAdComposerPage extends StatefulWidget {
  const OtcAdComposerPage({
    required this.controller,
    required this.config,
    super.key,
  });
  final SessionController controller;
  final OtcConfig config;
  @override
  State<OtcAdComposerPage> createState() => _OtcAdComposerPageState();
}

class _OtcAdComposerPageState extends State<OtcAdComposerPage> {
  String _side = 'sell';
  late OtcAsset _asset;
  late OtcNetwork _network;
  final _price = TextEditingController();
  final _min = TextEditingController();
  final _max = TextEditingController();
  final _amount = TextEditingController();
  final _terms = TextEditingController();
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _asset = widget.config.assets.first;
    _network = _asset.networks.first;
  }

  @override
  void dispose() {
    _price.dispose();
    _min.dispose();
    _max.dispose();
    _amount.dispose();
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exposure =
        (double.tryParse(_price.text) ?? 0) *
        (double.tryParse(_amount.text) ?? 0);
    return BimScaffold(
      topBar: const BimTopBar(title: '发布广告'),
      body: ListView(
        padding: const EdgeInsets.all(BimSpacing.x4),
        children: [
          BimSegmentedControl<String>(
            selected: _side,
            options: const [
              BimSegmentOption(value: 'sell', label: '卖币广告'),
              BimSegmentOption(value: 'buy', label: '买币广告'),
            ],
            onChanged: (value) => setState(() => _side = value),
          ),
          const SizedBox(height: BimSpacing.x4),
          DropdownButtonFormField<OtcNetwork>(
            initialValue: _network,
            items: [
              for (final network in _asset.networks)
                DropdownMenuItem(
                  value: network,
                  child: Text('${_asset.symbol} · ${network.code}'),
                ),
            ],
            onChanged: (value) => setState(() => _network = value ?? _network),
            decoration: const InputDecoration(labelText: '资产网络'),
          ),
          TextField(
            controller: _price,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '单价',
              prefixText: '¥ ',
            ),
          ),
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '广告数量',
              suffixText: _asset.symbol,
            ),
          ),
          TextField(
            controller: _min,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '单笔最小金额',
              prefixText: '¥ ',
            ),
          ),
          TextField(
            controller: _max,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '单笔最大金额',
              prefixText: '¥ ',
            ),
          ),
          TextField(
            controller: _terms,
            maxLength: 500,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '交易说明'),
          ),
          BimNoticeBanner(
            text:
                '预计广告敞口 ¥${exposure.toStringAsFixed(2)}。提交后将按后台比例占用可用保证金，审核驳回或下架后自动释放。',
          ),
          const SizedBox(height: BimSpacing.x4),
          BimButton(
            label: '提交上架审核',
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await widget.controller.createOtcMerchantAd(
        side: _side,
        assetId: _asset.id,
        networkId: _network.id,
        price: _price.text.trim(),
        minFiat: _min.text.trim(),
        maxFiat: _max.text.trim(),
        availableAsset: _amount.text.trim(),
        paymentMethods: const ['alipay', 'wechat', 'bank'],
        terms: _terms.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      showBimSnackBar(context, '广告已提交审核', tone: BimNoticeTone.success);
    } catch (error) {
      if (mounted)
        showBimSnackBar(context, error.toString(), tone: BimNoticeTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

String _paymentMethodLabel(String type) => switch (type) {
  'alipay' => '支付宝',
  'wechat' => '微信',
  'bank' => '银行卡',
  _ => '收款方式',
};
