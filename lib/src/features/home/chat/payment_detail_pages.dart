part of 'package:bim/src/features/home/home_page.dart';

class _RedPacketDetailPage extends StatefulWidget {
  const _RedPacketDetailPage({
    required this.controller,
    required this.redPacketId,
    required this.group,
    required this.onReceive,
  });

  final SessionController controller;
  final String redPacketId;
  final bool group;
  final Future<void> Function() onReceive;

  @override
  State<_RedPacketDetailPage> createState() => _RedPacketDetailPageState();
}

class _RedPacketDetailPageState extends State<_RedPacketDetailPage> {
  late Future<Map<String, Object?>> _request;
  bool _receiving = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _request = _load();
  }

  Future<Map<String, Object?>> _load() async {
    final result = await widget.controller.redPacketDetail(widget.redPacketId);
    return _asObjectMap(result['red_packet']);
  }

  Future<void> _receive() async {
    if (_receiving) {
      return;
    }
    setState(() {
      _receiving = true;
      _message = '';
    });
    try {
      await widget.onReceive();
      if (!mounted) {
        return;
      }
      setState(() => _request = _load());
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _receiving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        backgroundColor: _pageColor,
        elevation: 0,
        foregroundColor: _textColor,
        title: const Text('红包详情'),
      ),
      body: FutureBuilder<Map<String, Object?>>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError) {
            return _PaymentErrorView(
              text: snapshot.error.toString(),
              onRetry: () => setState(() => _request = _load()),
            );
          }
          final detail = snapshot.data ?? const {};
          return _RedPacketDetailBody(
            detail: detail,
            receiving: _receiving,
            message: _message,
            onReceive: _receive,
          );
        },
      ),
    );
  }
}

class _TransferDetailPage extends StatefulWidget {
  const _TransferDetailPage({
    required this.controller,
    required this.transferId,
    required this.onReceive,
  });

  final SessionController controller;
  final String transferId;
  final Future<void> Function() onReceive;

  @override
  State<_TransferDetailPage> createState() => _TransferDetailPageState();
}

class _TransferDetailPageState extends State<_TransferDetailPage> {
  late Future<Map<String, Object?>> _request;
  bool _receiving = false;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _request = _load();
  }

  Future<Map<String, Object?>> _load() async {
    final result = await widget.controller.transferDetail(widget.transferId);
    return _asObjectMap(result['transfer']);
  }

  Future<void> _receive() async {
    if (_receiving) {
      return;
    }
    setState(() {
      _receiving = true;
      _message = '';
    });
    try {
      await widget.onReceive();
      if (!mounted) {
        return;
      }
      setState(() => _request = _load());
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _receiving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageColor,
      appBar: AppBar(
        backgroundColor: _pageColor,
        elevation: 0,
        foregroundColor: _textColor,
        title: const Text('转账详情'),
      ),
      body: FutureBuilder<Map<String, Object?>>(
        future: _request,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          if (snapshot.hasError) {
            return _PaymentErrorView(
              text: snapshot.error.toString(),
              onRetry: () => setState(() => _request = _load()),
            );
          }
          final detail = snapshot.data ?? const {};
          return _TransferDetailBody(
            detail: detail,
            receiving: _receiving,
            message: _message,
            onReceive: _receive,
          );
        },
      ),
    );
  }
}

class _RedPacketDetailBody extends StatelessWidget {
  const _RedPacketDetailBody({
    required this.detail,
    required this.receiving,
    required this.message,
    required this.onReceive,
  });

  final Map<String, Object?> detail;
  final bool receiving;
  final String message;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final sender = _asObjectMap(detail['sender']);
    final senderName = _displayNameFromMap(sender, fallback: '对方');
    final remark = _value(detail, ['remark'], fallback: '恭喜发财，大吉大利');
    final amount = _paymentAmount(detail);
    final canReceive = _boolish(detail['can_receive']);
    final receivedByMe = _boolish(detail['received_by_me']);
    final receives = detail['receives'] is List
        ? detail['receives'] as List
        : const [];
    return ListView(
      padding: EdgeInsets.fromLTRB(
        18,
        14,
        18,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _PaymentHero(
          color: BimColors.redPacket,
          icon: Icons.redeem,
          title: '$senderName的红包',
          subtitle: remark,
          amount: receivedByMe || _boolish(detail['is_sender']) ? amount : '',
          status: _value(detail, ['status_name'], fallback: '待领取'),
        ),
        if (canReceive)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _PaymentPrimaryButton(
              text: receiving ? '领取中' : '领取红包',
              loading: receiving,
              onPressed: receiving ? null : onReceive,
            ),
          ),
        if (message.isNotEmpty) _PaymentInlineMessage(text: message),
        const SizedBox(height: 16),
        _PaymentSection(
          children: [
            _PaymentRow(
              label: '交易单号',
              value: _value(detail, ['transaction_no']),
            ),
            _PaymentRow(label: '红包类型', value: _redPacketTypeLabel(detail)),
            _PaymentRow(
              label: '领取情况',
              value:
                  '${_value(detail, ['receive_count'], fallback: '0')}/${_value(detail, ['quantity'], fallback: '1')}',
            ),
            _PaymentRow(label: '创建时间', value: _value(detail, ['create_time'])),
            _PaymentRow(label: '过期时间', value: _value(detail, ['expire_time'])),
          ],
        ),
        if (receives.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SectionHeader(text: '领取记录'),
          const SizedBox(height: 8),
          _PaymentSection(
            children: [
              for (final row in receives) _ReceiveRow(row: _asObjectMap(row)),
            ],
          ),
        ],
      ],
    );
  }
}

class _TransferDetailBody extends StatelessWidget {
  const _TransferDetailBody({
    required this.detail,
    required this.receiving,
    required this.message,
    required this.onReceive,
  });

  final Map<String, Object?> detail;
  final bool receiving;
  final String message;
  final VoidCallback onReceive;

  @override
  Widget build(BuildContext context) {
    final sender = _asObjectMap(detail['sender']);
    final receiver = _asObjectMap(detail['receiver']);
    final canReceive = _boolish(detail['can_receive']);
    return ListView(
      padding: EdgeInsets.fromLTRB(
        18,
        14,
        18,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _PaymentHero(
          color: BimColors.transfer,
          icon: Icons.payments_outlined,
          title: '转账',
          subtitle: _value(detail, ['status_name'], fallback: '待收款'),
          amount: _paymentAmount(detail),
          status: _value(detail, ['status_name'], fallback: '待收款'),
        ),
        if (canReceive)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _PaymentPrimaryButton(
              text: receiving ? '收款中' : '确认收款',
              loading: receiving,
              onPressed: receiving ? null : onReceive,
            ),
          ),
        if (message.isNotEmpty) _PaymentInlineMessage(text: message),
        const SizedBox(height: 16),
        _PaymentSection(
          children: [
            _PaymentRow(
              label: '付款方',
              value: _displayNameFromMap(sender, fallback: '对方'),
            ),
            _PaymentRow(
              label: '收款方',
              value: _displayNameFromMap(receiver, fallback: '对方'),
            ),
            _PaymentRow(
              label: '交易单号',
              value: _value(detail, ['transaction_no']),
            ),
            _PaymentRow(label: '创建时间', value: _value(detail, ['create_time'])),
            _PaymentRow(label: '收款时间', value: _value(detail, ['receive_time'])),
            _PaymentRow(label: '退回时间', value: _value(detail, ['refund_time'])),
            _PaymentRow(label: '过期时间', value: _value(detail, ['expire_time'])),
          ],
        ),
      ],
    );
  }
}

class _PaymentHero extends StatelessWidget {
  const _PaymentHero({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final String amount;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _lightBorderColor),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textColor,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _secondaryTextColor,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
          if (amount.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              amount,
              style: const TextStyle(
                color: _textColor,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            status,
            style: const TextStyle(
              color: _mutedColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentSection extends StatelessWidget {
  const _PaymentSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _lightBorderColor),
      ),
      child: Column(children: children),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: _mutedColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiveRow extends StatelessWidget {
  const _ReceiveRow({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final receiver = _asObjectMap(row['receiver']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _Avatar(
            label: _displayNameFromMap(receiver, fallback: '用户'),
            imageUrl: _value(receiver, ['avatar', 'usertx']),
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayNameFromMap(receiver, fallback: '用户'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _value(row, ['create_time']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _mutedColor, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _paymentAmount(row),
            style: const TextStyle(
              color: _textColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentPrimaryButton extends StatelessWidget {
  const _PaymentPrimaryButton({
    required this.text,
    required this.loading,
    required this.onPressed,
  });

  final String text;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(text),
      ),
    );
  }
}

class _PaymentInlineMessage extends StatelessWidget {
  const _PaymentInlineMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _dangerColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PaymentErrorView extends StatelessWidget {
  const _PaymentErrorView({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _secondaryTextColor, fontSize: 14),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

String _redPacketTypeLabel(Map<String, Object?> detail) {
  return switch (_value(detail, ['packet_type']).toLowerCase()) {
    'luck' => '拼手气红包',
    'specified' => '专属红包',
    _ => '普通红包',
  };
}

String _displayNameFromMap(
  Map<String, Object?> source, {
  String fallback = '',
}) {
  return _value(source, [
    'display_name',
    'nickname',
    'username',
    'name',
  ], fallback: fallback);
}

bool _boolish(Object? value) {
  if (value is bool) {
    return value;
  }
  final text = value?.toString().trim().toLowerCase() ?? '';
  return text == '1' || text == 'true' || text == 'yes';
}
