part of 'package:bim/src/features/home/home_page.dart';

const _paymentServiceBackground = BimColors.serviceBackground;
const _paymentServiceText = BimColors.text;
const _paymentServiceMuted = BimColors.secondaryText;
const _paymentServiceDivider = BimColors.borderLight;
const _paymentServiceCardRadius = 8.0;
const _paymentServiceContentMaxWidth = 440.0;

class PaymentServicePage extends StatefulWidget {
  const PaymentServicePage({
    required this.controller,
    required this.title,
    required this.channelId,
    required this.channelType,
    this.serviceAccount = const {},
    this.initialClientMsgNo = '',
    super.key,
  });

  final SessionController controller;
  final String title;
  final String channelId;
  final int channelType;
  final Map<String, Object?> serviceAccount;
  final String initialClientMsgNo;

  @override
  State<PaymentServicePage> createState() => _PaymentServicePageState();
}

class _PaymentServicePageState extends State<PaymentServicePage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  StreamSubscription<BusinessImMessageEvent>? _messageSub;
  Future<List<Map<String, Object?>>>? _runningLoad;

  List<Map<String, Object?>> _messages = const [];
  bool _loading = true;
  bool _searching = false;
  String _query = '';
  String _error = '';
  int _messageRevision = 0;
  Map<String, Object?> _serviceAccount = const {};
  bool _serviceConfigLoading = false;
  bool _initialTargetHandled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _serviceAccount = Map<String, Object?>.from(widget.serviceAccount);
    _messageRevision = _currentMessageRevision();
    _hydrateCachedMessages();
    widget.controller.addListener(_onControllerChanged);
    _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
    _searchController.addListener(_onSearchChanged);
    unawaited(
      widget.controller.openConversation(
        channelId: widget.channelId,
        channelType: widget.channelType,
      ),
    );
    unawaited(_markVisibleRead('open_payment_service'));
    unawaited(_loadMessagesIntoState(showLoading: _messages.isEmpty));
    unawaited(_loadServiceAccountConfig());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_markVisibleRead('payment_service_resumed'));
    }
  }

  @override
  void didUpdateWidget(covariant PaymentServicePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.channelId != widget.channelId ||
        oldWidget.channelType != widget.channelType) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _messageSub?.cancel();
      widget.controller.addListener(_onControllerChanged);
      _messageSub = widget.controller.messageEvents.listen(_onMessageEvent);
      _messageRevision = _currentMessageRevision();
      _runningLoad = null;
      _serviceAccount = Map<String, Object?>.from(widget.serviceAccount);
      _serviceConfigLoading = false;
      _hydrateCachedMessages();
      _initialTargetHandled = false;
      unawaited(
        widget.controller.openConversation(
          channelId: widget.channelId,
          channelType: widget.channelType,
        ),
      );
      unawaited(_markVisibleRead('payment_service_updated'));
      unawaited(_loadMessagesIntoState(showLoading: _messages.isEmpty));
      unawaited(_loadServiceAccountConfig());
    } else if (oldWidget.initialClientMsgNo != widget.initialClientMsgNo) {
      _initialTargetHandled = false;
      _revealInitialTargetOrLatest();
    } else if (jsonEncode(oldWidget.serviceAccount) !=
        jsonEncode(widget.serviceAccount)) {
      setState(() {
        _serviceAccount = Map<String, Object?>.from(widget.serviceAccount);
      });
      unawaited(_loadServiceAccountConfig());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageSub?.cancel();
    widget.controller.closeConversation(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    widget.controller.removeListener(_onControllerChanged);
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int _currentMessageRevision() {
    return widget.controller.messageVersion(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
  }

  void _hydrateCachedMessages() {
    final cached = widget.controller.cachedLocalMessages(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    _messages = _paymentServiceSortedMessages(cached);
    _loading = cached.isEmpty;
    _error = '';
    if (cached.isNotEmpty) {
      _revealInitialTargetOrLatest();
    }
  }

  void _onSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _query) {
      return;
    }
    setState(() => _query = next);
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final next = _currentMessageRevision();
    if (next == _messageRevision) {
      return;
    }
    final cached = widget.controller.cachedLocalMessages(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    setState(() {
      _messages = _stableLoadedMessages(cached, showLoading: false);
      _messageRevision = next;
      _loading = false;
      _error = '';
    });
    unawaited(_markVisibleRead('payment_service_controller'));
  }

  void _onMessageEvent(BusinessImMessageEvent event) {
    if (!mounted ||
        event.channelId != widget.channelId ||
        event.channelType != widget.channelType) {
      return;
    }
    setState(() {
      if (_paymentServiceIsDeleteEvent(event.source)) {
        final target = _value(event.message, ['client_msg_no']);
        _messages = _messages
            .where((item) => _value(item, ['client_msg_no']) != target)
            .toList(growable: false);
      } else {
        _messages = _paymentServiceMergeMessages(
          _messages,
          event.message,
          limit: 300,
        );
      }
      _messageRevision = _currentMessageRevision();
      _loading = false;
      _error = '';
    });
    unawaited(_markVisibleRead('payment_service_message'));
    _scrollToLatest();
  }

  Future<void> _loadMessagesIntoState({required bool showLoading}) async {
    final running = _runningLoad;
    if (running != null) {
      await running;
      return;
    }
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    final future = widget.controller.loadLocalMessages(
      channelId: widget.channelId,
      channelType: widget.channelType,
    );
    _runningLoad = future;
    try {
      final loaded = await future;
      if (!mounted || !identical(_runningLoad, future)) {
        return;
      }
      setState(() {
        _messages = _stableLoadedMessages(loaded, showLoading: showLoading);
        _messageRevision = _currentMessageRevision();
        _loading = false;
        _error = '';
      });
      _revealInitialTargetOrLatest();
      unawaited(_markVisibleRead('payment_service_loaded'));
    } catch (error, stackTrace) {
      if (!mounted || !identical(_runningLoad, future)) {
        return;
      }
      AppLogger.warn(
        'ui',
        'payment service messages load failed',
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
      setState(() {
        _loading = false;
        _error = _messages.isEmpty ? error.toString() : '';
      });
    } finally {
      if (identical(_runningLoad, future)) {
        _runningLoad = null;
      }
    }
  }

  List<Map<String, Object?>> _stableLoadedMessages(
    List<Map<String, Object?>> loaded, {
    required bool showLoading,
  }) {
    if (loaded.isEmpty && _messages.isNotEmpty && !showLoading) {
      return _paymentServiceSortedMessages(_messages);
    }
    var merged = _messages.isEmpty
        ? <Map<String, Object?>>[]
        : _messages.map((item) => Map<String, Object?>.from(item)).toList();
    for (final item in loaded) {
      merged = _paymentServiceMergeMessages(merged, item, limit: 300);
    }
    return merged;
  }

  void _revealInitialTargetOrLatest() {
    final target = widget.initialClientMsgNo.trim();
    if (_initialTargetHandled || target.isEmpty) {
      _scrollToLatest();
      return;
    }
    _initialTargetHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _messageKeys['client:$target']?.currentContext;
      if (context == null) {
        _scrollToLatest();
        return;
      }
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  Future<void> _markVisibleRead(String source) async {
    try {
      await widget.controller.markConversationVisibleRead(
        channelId: widget.channelId,
        channelType: widget.channelType,
      );
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'payment service visible read failed',
        data: {
          'source': source,
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    }
  }

  Future<void> _loadServiceAccountConfig() async {
    if (_serviceConfigLoading) {
      return;
    }
    _serviceConfigLoading = true;
    try {
      final serviceId = int.tryParse(_serviceAccountId(_serviceAccount)) ?? 0;
      Map<String, Object?> next = const {};
      if (serviceId > 0) {
        next = await widget.controller.loadServiceAccountDetail(serviceId);
      } else {
        final accounts = await widget.controller.loadServiceAccounts();
        next = _findServiceAccountForChannel(accounts);
      }
      if (!mounted || next.isEmpty) {
        return;
      }
      setState(() {
        _serviceAccount = {
          ..._serviceAccount,
          ...next,
          'menus': _serviceMenuList(next['menus']).isNotEmpty
              ? next['menus']
              : _serviceAccount['menus'],
        };
      });
    } catch (error, stackTrace) {
      AppLogger.warn(
        'ui',
        'service account config load failed',
        data: {
          'channel_id': widget.channelId,
          'channel_type': widget.channelType,
          'service_id': _serviceAccountId(_serviceAccount),
          'error': error.toString(),
          'stack': stackTrace.toString(),
        },
      );
    } finally {
      _serviceConfigLoading = false;
    }
  }

  Map<String, Object?> _findServiceAccountForChannel(
    List<Map<String, Object?>> accounts,
  ) {
    for (final account in accounts) {
      if (_serviceAccountChannelId(account) == widget.channelId &&
          _serviceAccountChannelType(account) == widget.channelType) {
        return account;
      }
    }
    return const {};
  }

  List<Map<String, Object?>> get _visibleMessages {
    final notices =
        (_isPaymentServiceAccount
                ? _messages.where(_paymentServiceIsWalletNotice)
                : _messages)
            .toList(growable: false);
    if (_query.isEmpty) {
      return _paymentServiceSortedMessages(notices);
    }
    final query = _query.toLowerCase();
    return _paymentServiceSortedMessages(
      notices
          .where((item) {
            final payload = _asObjectMap(item['payload']);
            final notice = _walletNoticePayload(payload);
            final fields = [
              _walletNoticeTitle(payload),
              _walletNoticeSummary(payload),
              _paymentServiceAmountText(notice),
              _paymentServiceActorName(notice, payload),
              _value(notice, [
                'order_no',
                'bill_no',
                'transaction_no',
                'trade_no',
              ]),
              _value(item, ['content', 'text']),
              _value(payload, ['text', 'content', 'summary', 'title']),
            ].join(' ').toLowerCase();
            return fields.contains(query);
          })
          .toList(growable: false),
    );
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
      }
    });
  }

  void _openWalletHome() {
    unawaited(_push(context, WalletPage(controller: widget.controller)));
  }

  void _openBills() {
    unawaited(_push(context, WalletBillsPage(controller: widget.controller)));
  }

  void _openPayReceive() {
    unawaited(
      _push(context, WalletPayReceivePage(controller: widget.controller)),
    );
  }

  Future<void> _openSettings() async {
    await _push(
      context,
      ServiceAccountSettingsPage(
        controller: widget.controller,
        serviceAccount: _serviceAccount,
      ),
    );
    unawaited(_loadServiceAccountConfig());
  }

  List<Map<String, Object?>> get _serviceMenus {
    final configured = _serviceMenuList(_serviceAccount['menus']);
    if (configured.isNotEmpty) {
      return configured;
    }
    if (_isPaymentServiceAccount) {
      return _defaultPaymentServiceMenus;
    }
    return const [];
  }

  bool get _isPaymentServiceAccount {
    final code = _value(_serviceAccount, ['code']);
    return code == 'payment_service' ||
        widget.title == '支付通知' ||
        _serviceAccountName(_serviceAccount) == '支付通知';
  }

  String get _serviceTitle {
    final name = _serviceAccountName(_serviceAccount);
    if (_serviceAccount.isNotEmpty && name.isNotEmpty && name != '服务号') {
      return name;
    }
    return widget.title.isEmpty ? '支付通知' : widget.title;
  }

  bool get _showServiceMenus {
    return _value(_serviceAccount, ['menu_mode'], fallback: 'menu') != 'none' &&
        _serviceMenus.isNotEmpty;
  }

  void _handleServiceMenu(Map<String, Object?> menu) {
    final actionType = _value(menu, ['action_type', 'type', 'action']);
    final actionValue = _value(menu, ['action_value', 'value', 'url', 'page']);
    switch (actionType) {
      case 'wallet_home':
        _openWalletHome();
        return;
      case 'wallet_bills':
        _openBills();
        return;
      case 'wallet_pay_receive':
        _openPayReceive();
        return;
      case 'scan':
        unawaited(
          _push(context, WalletScanPage(controller: widget.controller)),
        );
        return;
      case 'url':
      case 'page':
        AppLogger.info(
          'ui',
          'service account menu action not opened by client',
          data: {'action_type': actionType, 'action_value': actionValue},
        );
        _showWalletMessage(context, '该功能暂不可用');
        return;
      default:
        _showWalletMessage(context, '该功能暂不可用');
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _visibleMessages;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: _paymentServiceBackground,
        systemNavigationBarColor: _surfaceColor,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: _paymentServiceBackground,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _PaymentServiceHeader(
                title: _serviceTitle,
                searching: _searching,
                searchController: _searchController,
                onBack: () => Navigator.of(context).maybePop(),
                onSearch: _toggleSearch,
                onSettings: () => unawaited(_openSettings()),
              ),
              Expanded(child: _buildBody(messages)),
              if (_showServiceMenus)
                _PaymentServiceBottomBar(
                  menus: _serviceMenus,
                  onMenuTap: _handleServiceMenu,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<Map<String, Object?>> messages) {
    if (_loading && _messages.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (_error.isNotEmpty && _messages.isEmpty) {
      return _PaymentServiceErrorState(
        message: _error,
        onRetry: () => _loadMessagesIntoState(showLoading: true),
      );
    }
    if (messages.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty
              ? (_isPaymentServiceAccount ? '暂无支付通知' : '暂无服务通知')
              : '没有找到相关通知',
          style: const TextStyle(
            color: _paymentServiceMuted,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: _primaryColor,
      onRefresh: () => _loadMessagesIntoState(showLoading: false),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(
          _paymentServiceHorizontalPadding(context),
          16,
          _paymentServiceHorizontalPadding(context),
          20,
        ),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final item = messages[index];
          final messageKey = _paymentServiceMessageKey(item);
          return Column(
            key: messageKey.isEmpty
                ? null
                : _messageKeys.putIfAbsent(messageKey, GlobalKey.new),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_shouldShowPaymentTimeDivider(messages, index))
                _PaymentServiceTimeDivider(
                  text: _paymentServiceTimeLabel(item),
                ),
              if (_paymentServiceIsWalletNotice(item))
                _PaymentServiceNoticeCard(
                  item: item,
                  onTap: () => _showPaymentNoticeDetail(item),
                )
              else
                _ServiceAccountMessageCard(
                  item: item,
                  serviceName: _serviceTitle,
                  serviceAvatar: _serviceAccountAvatar(_serviceAccount),
                ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  void _showPaymentNoticeDetail(Map<String, Object?> item) {
    final payload = _asObjectMap(item['payload']);
    final notice = _walletNoticePayload(payload);
    final title = _walletNoticeTitle(payload);
    final amount = _paymentServiceAmountText(notice);
    final scene = _walletNoticeScene(payload);
    final orderNo = _value(notice, ['order_no']);
    final canConfirmPayCode =
        scene == 'pay_code_confirm_required' && orderNo.isNotEmpty;
    final rows = <_PaymentServiceDetailRowData>[
      _PaymentServiceDetailRowData(
        label: '交易对象',
        value: _paymentServiceActorName(notice, payload),
      ),
      _PaymentServiceDetailRowData(label: '交易类型', value: title),
      _PaymentServiceDetailRowData(
        label: '交易状态',
        value: _value(notice, ['status_name', 'status_text'], fallback: '交易成功'),
      ),
      _PaymentServiceDetailRowData(
        label: '账单单号',
        value: _value(notice, ['bill_no', 'order_no', 'transaction_no']),
        copyable: true,
      ),
      _PaymentServiceDetailRowData(
        label: '交易单号',
        value: _value(notice, ['trade_no', 'payment_no', 'transaction_id']),
        copyable: true,
      ),
      _PaymentServiceDetailRowData(
        label: '交易时间',
        value: _value(notice, [
          'paid_time',
          'created_at',
          'create_time',
          'time',
        ], fallback: _paymentServiceTimeLabel(item)),
      ),
      if (_paymentServiceRemark(notice).isNotEmpty)
        _PaymentServiceDetailRowData(
          label: '留言',
          value: _paymentServiceRemark(notice),
        ),
    ].where((row) => row.value.trim().isNotEmpty).toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surfaceColor,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => _PaymentServiceDetailSheet(
        title: title,
        amount: amount,
        rows: rows,
        actionText: canConfirmPayCode ? '确认付款' : '',
        onAction: canConfirmPayCode
            ? () {
                Navigator.of(context).pop();
                unawaited(_confirmPayCodeOrder(orderNo, amount));
              }
            : null,
      ),
    );
  }

  Future<void> _confirmPayCodeOrder(String orderNo, String amountLabel) async {
    final password = await _showWalletPayPasswordSheet(
      context,
      title: '确认付款',
      amountLabel: amountLabel,
    );
    if (password.isEmpty || !mounted) {
      return;
    }
    try {
      final order = await widget.controller.confirmWalletPayCodeOrder(
        orderNo: orderNo,
        payPassword: password,
      );
      if (!mounted) {
        return;
      }
      _showWalletMessage(context, '支付成功');
      unawaited(_loadMessagesIntoState(showLoading: false));
      unawaited(widget.controller.loadWalletOrderStatus(order.orderNo));
    } catch (error) {
      if (mounted) {
        _showWalletMessage(context, error.toString());
      }
    }
  }
}
