part of 'package:bim/src/features/home/home_page.dart';

const _paymentServiceBackground = Color(0xffededed);
const _paymentServiceText = Color(0xff1f1f1f);
const _paymentServiceMuted = Color(0xff8d9199);
const _paymentServiceDivider = Color(0xffebedf0);
const _paymentServiceCardRadius = 8.0;
const _paymentServiceContentMaxWidth = 440.0;

class PaymentServicePage extends StatefulWidget {
  const PaymentServicePage({
    required this.controller,
    required this.title,
    required this.channelId,
    required this.channelType,
    super.key,
  });

  final SessionController controller;
  final String title;
  final String channelId;
  final int channelType;

  @override
  State<PaymentServicePage> createState() => _PaymentServicePageState();
}

class _PaymentServicePageState extends State<PaymentServicePage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription<BusinessImMessageEvent>? _messageSub;
  Future<List<Map<String, Object?>>>? _runningLoad;

  List<Map<String, Object?>> _messages = const [];
  bool _loading = true;
  bool _searching = false;
  String _query = '';
  String _error = '';
  int _messageRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _hydrateCachedMessages();
      unawaited(
        widget.controller.openConversation(
          channelId: widget.channelId,
          channelType: widget.channelType,
        ),
      );
      unawaited(_markVisibleRead('payment_service_updated'));
      unawaited(_loadMessagesIntoState(showLoading: _messages.isEmpty));
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
    _messages = cached;
    _loading = cached.isEmpty;
    _error = '';
    if (cached.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
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
      _scrollToLatest();
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
      return _messages;
    }
    var merged = _messages.isEmpty
        ? <Map<String, Object?>>[]
        : _messages.map((item) => Map<String, Object?>.from(item)).toList();
    for (final item in loaded) {
      merged = _paymentServiceMergeMessages(merged, item, limit: 300);
    }
    return merged;
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

  List<Map<String, Object?>> get _visibleMessages {
    final notices = _messages
        .where(_paymentServiceIsWalletNotice)
        .toList(growable: false);
    if (_query.isEmpty) {
      return notices;
    }
    final query = _query.toLowerCase();
    return notices
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
          ].join(' ').toLowerCase();
          return fields.contains(query);
        })
        .toList(growable: false);
  }

  void _jumpToLatest() {
    if (!mounted || !_scrollController.hasClients) {
      return;
    }
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
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
          child: Column(
            children: [
              _PaymentServiceHeader(
                title: widget.title.isEmpty ? '支付通知' : widget.title,
                searching: _searching,
                searchController: _searchController,
                onBack: () => Navigator.of(context).maybePop(),
                onSearch: _toggleSearch,
                onWallet: _openWalletHome,
              ),
              Expanded(child: _buildBody(messages)),
              _PaymentServiceBottomBar(
                onWallet: _openWalletHome,
                onBills: _openBills,
                onPayReceive: _openPayReceive,
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
          _query.isEmpty ? '暂无支付通知' : '没有找到相关通知',
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_shouldShowPaymentTimeDivider(messages, index))
                _PaymentServiceTimeDivider(
                  text: _paymentServiceTimeLabel(item),
                ),
              _PaymentServiceNoticeCard(
                item: item,
                onTap: () => _showPaymentNoticeDetail(item),
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
      builder: (context) =>
          _PaymentServiceDetailSheet(title: title, amount: amount, rows: rows),
    );
  }
}

class _PaymentServiceHeader extends StatelessWidget {
  const _PaymentServiceHeader({
    required this.title,
    required this.searching,
    required this.searchController,
    required this.onBack,
    required this.onSearch,
    required this.onWallet,
  });

  final String title;
  final bool searching;
  final TextEditingController searchController;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onWallet;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: searching ? 98 : 54,
      color: _paymentServiceBackground,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 4,
                  child: _PaymentHeaderIconButton(
                    icon: Icons.arrow_back_ios_new,
                    label: '返回',
                    onTap: onBack,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 118),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _paymentServiceText,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
                Positioned(
                  right: 52,
                  child: _PaymentHeaderIconButton(
                    icon: searching ? Icons.close : Icons.search,
                    label: searching ? '关闭搜索' : '搜索',
                    onTap: onSearch,
                  ),
                ),
                Positioned(
                  right: 4,
                  child: _PaymentHeaderIconButton(
                    icon: Icons.settings_outlined,
                    label: '钱包',
                    onTap: onWallet,
                  ),
                ),
              ],
            ),
          ),
          if (searching)
            Padding(
              padding: EdgeInsets.fromLTRB(
                _paymentServiceHorizontalPadding(context),
                0,
                _paymentServiceHorizontalPadding(context),
                8,
              ),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _surfaceColor,
                    hintText: '搜索支付通知',
                    hintStyle: const TextStyle(
                      color: _paymentServiceMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: _paymentServiceMuted,
                      size: 19,
                    ),
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: const TextStyle(
                    color: _paymentServiceText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentHeaderIconButton extends StatelessWidget {
  const _PaymentHeaderIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: Colors.black, size: 23),
          ),
        ),
      ),
    );
  }
}

class _PaymentServiceTimeDivider extends StatelessWidget {
  const _PaymentServiceTimeDivider({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xffa5a7ad),
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
    );
  }
}

class _PaymentServiceNoticeCard extends StatelessWidget {
  const _PaymentServiceNoticeCard({required this.item, required this.onTap});

  final Map<String, Object?> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final payload = _asObjectMap(item['payload']);
    final notice = _walletNoticePayload(payload);
    final title = _walletNoticeTitle(payload);
    final actorName = _paymentServiceActorName(notice, payload);
    final actorAvatar = _paymentServiceActorAvatar(notice, item);
    final amount = _paymentServiceAmountText(notice);
    final remark = _paymentServiceRemark(notice);
    final detailLabel = _paymentServiceDetailLabel(notice, payload);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _paymentServiceContentMaxWidth,
        ),
        child: Material(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(_paymentServiceCardRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 14),
                  child: Row(
                    children: [
                      _Avatar(
                        label: actorName.isEmpty ? title : actorName,
                        imageUrl: actorAvatar,
                        size: 34,
                        color: _paymentServiceAccent(notice, payload),
                        icon: actorAvatar.isEmpty
                            ? Icons.account_balance_wallet_outlined
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          actorName.isEmpty ? title : actorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _paymentServiceText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _paymentServiceDivider),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 30, 18, 28),
                  child: Column(
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _paymentServiceText,
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      if (amount.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            amount,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              height: 0.95,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _PaymentServiceDetailLink(label: detailLabel),
                    ],
                  ),
                ),
                if (remark.isNotEmpty)
                  _PaymentServiceRemarkRow(text: remark)
                else
                  const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentServiceDetailLink extends StatelessWidget {
  const _PaymentServiceDetailLink({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _paymentServiceMuted,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: Color(0xffb5b8be), size: 22),
      ],
    );
  }
}

class _PaymentServiceRemarkRow extends StatelessWidget {
  const _PaymentServiceRemarkRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
      child: Column(
        children: [
          const Divider(height: 1, color: _paymentServiceDivider),
          SizedBox(
            height: 54,
            child: Row(
              children: [
                const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.black,
                  size: 21,
                ),
                const SizedBox(width: 10),
                const Text(
                  '留言',
                  style: TextStyle(
                    color: _paymentServiceText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: _paymentServiceMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xffb5b8be),
                  size: 22,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentServiceBottomBar extends StatelessWidget {
  const _PaymentServiceBottomBar({
    required this.onWallet,
    required this.onBills,
    required this.onPayReceive,
  });

  final VoidCallback onWallet;
  final VoidCallback onBills;
  final VoidCallback onPayReceive;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: _surfaceColor,
        border: Border(top: BorderSide(color: Color(0xffdddddd), width: 0.5)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: _PaymentServiceMenuButton(
              icon: Icons.apps,
              label: '支付服务',
              showText: false,
              onTap: onWallet,
            ),
          ),
          const _PaymentServiceVerticalDivider(),
          Expanded(
            child: _PaymentServiceMenuButton(label: '我的账单', onTap: onBills),
          ),
          const _PaymentServiceVerticalDivider(),
          Expanded(
            child: _PaymentServiceMenuButton(label: '支付服务', onTap: onWallet),
          ),
          const _PaymentServiceVerticalDivider(),
          Expanded(
            child: _PaymentServiceMenuButton(label: '收付款', onTap: onPayReceive),
          ),
        ],
      ),
    );
  }
}

class _PaymentServiceMenuButton extends StatelessWidget {
  const _PaymentServiceMenuButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.showText = true,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: icon == null
                ? Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  )
                : Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.6),
                    ),
                    child: Icon(icon, color: Colors.black, size: 21),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PaymentServiceVerticalDivider extends StatelessWidget {
  const _PaymentServiceVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 0.5, height: 24, color: const Color(0xffe0e0e0));
  }
}

class _PaymentServiceErrorState extends StatelessWidget {
  const _PaymentServiceErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message.replaceFirst('Exception: ', ''),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _secondaryTextColor,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _PaymentServiceDetailRowData {
  const _PaymentServiceDetailRowData({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;
}

class _PaymentServiceDetailSheet extends StatelessWidget {
  const _PaymentServiceDetailSheet({
    required this.title,
    required this.amount,
    required this.rows,
  });

  final String title;
  final String amount;
  final List<_PaymentServiceDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xffd4d6dc),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _paymentServiceText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (amount.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              amount,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                height: 1.05,
                letterSpacing: 0,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: _paymentServiceDivider),
              itemBuilder: (context, index) {
                final row = rows[index];
                return _PaymentServiceDetailRow(row: row);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentServiceDetailRow extends StatelessWidget {
  const _PaymentServiceDetailRow({required this.row});

  final _PaymentServiceDetailRowData row;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: row.copyable
          ? () {
              Clipboard.setData(ClipboardData(text: row.value));
              _showWalletMessage(context, '已复制');
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 82,
              child: Text(
                row.label,
                style: const TextStyle(
                  color: _paymentServiceMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                row.value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: _paymentServiceText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
            if (row.copyable) ...[
              const SizedBox(width: 6),
              const Icon(Icons.copy, color: _paymentServiceMuted, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

bool _paymentServiceIsDeleteEvent(String source) {
  return source == 'burn_after_read_cmd' || source == 'recall_cmd';
}

bool _paymentServiceIsWalletNotice(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  return _messageContentType(item) == ChatContentTypes.walletNotice ||
      _value(payload, ['content_type']) == ChatContentTypes.walletNotice ||
      _asObjectMap(payload['wallet_notice']).isNotEmpty;
}

List<Map<String, Object?>> _paymentServiceMergeMessages(
  List<Map<String, Object?>> current,
  Map<String, Object?> incoming, {
  required int limit,
}) {
  final next = current.map((item) => Map<String, Object?>.from(item)).toList();
  final incomingKey = _paymentServiceMessageKey(incoming);
  final index = incomingKey.isEmpty
      ? -1
      : next.indexWhere(
          (item) => _paymentServiceMessageKey(item) == incomingKey,
        );
  if (index >= 0) {
    next[index] = {
      ...next[index],
      ...incoming,
      'payload': {
        ..._asObjectMap(next[index]['payload']),
        ..._asObjectMap(incoming['payload']),
      },
    };
  } else {
    next.add(Map<String, Object?>.from(incoming));
  }
  next.sort(_paymentServiceCompareMessages);
  if (next.length <= limit) {
    return next;
  }
  return next.sublist(next.length - limit);
}

String _paymentServiceMessageKey(Map<String, Object?> item) {
  final payload = _asObjectMap(item['payload']);
  final clientMsgNo = _value(item, [
    'client_msg_no',
  ], fallback: _value(payload, ['client_msg_no']));
  if (clientMsgNo.isNotEmpty) {
    return 'client:$clientMsgNo';
  }
  final messageId = _value(item, [
    'message_id',
    'message_idstr',
    'msg_id',
    'id',
  ], fallback: _value(payload, ['message_id', 'message_idstr', 'msg_id']));
  if (messageId.isNotEmpty) {
    return 'id:$messageId';
  }
  final seq = _intValue(item, ['message_seq']);
  if (seq > 0) {
    return 'seq:$seq';
  }
  return '';
}

int _paymentServiceCompareMessages(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final seqLeft = _intValue(left, ['message_seq']);
  final seqRight = _intValue(right, ['message_seq']);
  if (seqLeft > 0 && seqRight > 0 && seqLeft != seqRight) {
    return seqLeft.compareTo(seqRight);
  }
  final timeLeft = _messageDateTime(left);
  final timeRight = _messageDateTime(right);
  if (timeLeft != null && timeRight != null) {
    return timeLeft.compareTo(timeRight);
  }
  return _value(left, ['timestamp']).compareTo(_value(right, ['timestamp']));
}

bool _shouldShowPaymentTimeDivider(
  List<Map<String, Object?>> messages,
  int index,
) {
  if (index == 0) {
    return true;
  }
  final current = _messageDateTime(messages[index]);
  final previous = _messageDateTime(messages[index - 1]);
  if (current == null || previous == null) {
    return false;
  }
  return current.difference(previous).inMinutes.abs() >= 5;
}

String _paymentServiceTimeLabel(Map<String, Object?> item) {
  final time = _messageDateTime(item);
  if (time == null) {
    return '';
  }
  String two(int value) => value.toString().padLeft(2, '0');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final clock = '${two(time.hour)}:${two(time.minute)}';
  final diff = today.difference(day).inDays;
  if (diff == 0) {
    return clock;
  }
  if (diff == 1) {
    return '昨天 $clock';
  }
  if (time.year == now.year) {
    return '${two(time.month)}-${two(time.day)} $clock';
  }
  return '${time.year}-${two(time.month)}-${two(time.day)} $clock';
}

double _paymentServiceHorizontalPadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 900) {
    return 40;
  }
  if (width >= 600) {
    return 28;
  }
  if (width >= 360) {
    return 20;
  }
  return 14;
}

String _paymentServiceActorName(
  Map<String, Object?> notice,
  Map<String, Object?> payload,
) {
  final actor = _value(notice, [
    'merchant_name',
    'shop_name',
    'target_name',
    'counterparty_name',
    'payee_name',
    'payer_name',
    'receiver_name',
    'sender_name',
    'nickname',
    'username',
  ]);
  if (actor.isNotEmpty) {
    return actor;
  }
  return _value(payload, [
    'merchant_name',
    'target_name',
    'counterparty_name',
    'from_nickname',
    'from_username',
  ]);
}

String _paymentServiceActorAvatar(
  Map<String, Object?> notice,
  Map<String, Object?> item,
) {
  final payload = _asObjectMap(item['payload']);
  final avatar = _value(
    notice,
    [
      'merchant_avatar',
      'target_avatar',
      'counterparty_avatar',
      'payee_avatar',
      'payer_avatar',
      'receiver_avatar',
      'sender_avatar',
      'avatar',
    ],
    fallback: _value(payload, [
      'merchant_avatar',
      'target_avatar',
      'counterparty_avatar',
      'avatar',
    ]),
  );
  if (avatar.isNotEmpty) {
    return _normalizeAvatarUrl(avatar);
  }
  return _messageSenderAvatarUrl(item);
}

String _paymentServiceAmountText(Map<String, Object?> notice) {
  final direct = _value(notice, ['amount_label', 'money_label']);
  if (direct.isNotEmpty) {
    return _paymentServiceCurrencyText(direct);
  }
  final amount = _value(notice, ['amount', 'money', 'fee']);
  if (amount.isEmpty) {
    return '';
  }
  return _paymentServiceCurrencyText(amount);
}

String _paymentServiceCurrencyText(String rawValue) {
  var text = rawValue.trim();
  if (text.isEmpty) {
    return '';
  }
  text = text.replaceFirst(RegExp(r'^(CNY|RMB)\s*', caseSensitive: false), '');
  if (text.startsWith('¥') || text.startsWith('￥')) {
    final value = text.substring(1).trim();
    return value.isEmpty ? '¥' : '¥ $value';
  }
  final parsed = double.tryParse(text.replaceAll(',', ''));
  if (parsed == null) {
    return '¥ $text';
  }
  return '¥ ${parsed.toStringAsFixed(2)}';
}

String _paymentServiceRemark(Map<String, Object?> notice) {
  final value = _value(notice, ['leave_message', 'message', 'remark', 'memo']);
  final summary = _value(notice, ['summary', 'content']);
  if (value.isNotEmpty && value != summary) {
    return value;
  }
  return '';
}

String _paymentServiceDetailLabel(
  Map<String, Object?> notice,
  Map<String, Object?> payload,
) {
  final scene = _walletNoticeScene(payload);
  if (scene.contains('pay') ||
      scene.contains('bill') ||
      scene.contains('scan')) {
    return '账单详情';
  }
  if (_value(notice, ['bill_no']).isNotEmpty) {
    return '账单详情';
  }
  return '交易详情';
}

Color _paymentServiceAccent(
  Map<String, Object?> notice,
  Map<String, Object?> payload,
) {
  final title = _walletNoticeTitle(payload);
  final scene = _walletNoticeScene(payload);
  if (_walletNoticeIsRisk(payload)) {
    return BimColors.danger;
  }
  if (scene == 'scan_collect_success' || title.contains('收款')) {
    return BimColors.primary;
  }
  if (scene.contains('refund') || title.contains('退')) {
    return BimColors.success;
  }
  return BimColors.transfer;
}
