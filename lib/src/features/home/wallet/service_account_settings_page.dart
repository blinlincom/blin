part of 'package:bim/src/features/home/home_page.dart';

class ServiceAccountSettingsPage extends StatefulWidget {
  const ServiceAccountSettingsPage({
    required this.controller,
    required this.serviceAccount,
    super.key,
  });

  final SessionController controller;
  final Map<String, Object?> serviceAccount;

  @override
  State<ServiceAccountSettingsPage> createState() =>
      _ServiceAccountSettingsPageState();
}

class _ServiceAccountSettingsPageState
    extends State<ServiceAccountSettingsPage> {
  late Map<String, Object?> _serviceAccount;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _serviceAccount = Map<String, Object?>.from(widget.serviceAccount);
  }

  int get _serviceId => int.tryParse(_serviceAccountId(_serviceAccount)) ?? 0;
  bool get _muted => _boolValue(_serviceAccount['muted']);
  bool get _pinned => _boolValue(_serviceAccount['pinned']);
  bool get _following =>
      !_serviceAccount.containsKey('following') ||
      _boolValue(_serviceAccount['following']);

  Future<void> _update({bool? muted, bool? pinned, bool? following}) async {
    if (_busy || _serviceId <= 0) {
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await widget.controller.updateServiceAccountSettings(
        serviceId: _serviceId,
        muted: muted,
        pinned: pinned,
        following: following,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _serviceAccount = {..._serviceAccount, ...updated};
        _busy = false;
      });
      _showWalletMessage(context, '设置已更新');
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _showWalletMessage(context, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _serviceAccountName(_serviceAccount);
    final subtitle = _serviceAccountSubtitle(_serviceAccount);
    return BimScaffold(
      topBar: const BimTopBar(title: '服务号设置'),
      body: BimContentViewport(
        maxWidth: 680,
        child: ListView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Container(
              color: _surfaceColor,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              child: Row(
                children: [
                  _Avatar(
                    label: name,
                    imageUrl: _serviceAccountAvatar(_serviceAccount),
                    size: 52,
                    color: _primaryColor,
                    icon: Icons.verified_user_outlined,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _mutedColor,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _ServiceAccountSwitchTile(
              title: '消息免打扰',
              value: _muted,
              enabled: !_busy && _serviceId > 0 && _following,
              onChanged: (value) => _update(muted: value),
            ),
            _ServiceAccountSwitchTile(
              title: '置顶服务号',
              value: _pinned,
              enabled: !_busy && _serviceId > 0 && _following,
              onChanged: (value) => _update(pinned: value),
            ),
            if (_serviceAccountAllowUnfollow(_serviceAccount) &&
                _following) ...[
              const SizedBox(height: 10),
              _ServiceAccountActionTile(
                title: '不再关注',
                color: _dangerColor,
                enabled: !_busy && _serviceId > 0,
                onTap: () => _update(following: false),
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceAccountSwitchTile extends StatelessWidget {
  const _ServiceAccountSwitchTile({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return BimSettingsSwitchTile(
      title: title,
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

class _ServiceAccountActionTile extends StatelessWidget {
  const _ServiceAccountActionTile({
    required this.title,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  final String title;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceColor,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          height: 52,
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                color: enabled ? color : _mutedColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const List<Map<String, Object?>> _defaultPaymentServiceMenus = [
  {'name': '我的账单', 'action_type': 'wallet_bills', 'action_value': ''},
  {'name': '支付服务', 'action_type': 'wallet_home', 'action_value': ''},
  {'name': '收付款', 'action_type': 'wallet_pay_receive', 'action_value': ''},
];

List<Map<String, Object?>> _serviceMenuList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .where((item) => _serviceMenuLabel(item).isNotEmpty)
        .toList(growable: false);
  }
  return const [];
}

String _serviceMenuLabel(Map<String, Object?> item) {
  return _value(item, ['name', 'title', 'label']);
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

List<Map<String, Object?>> _paymentServiceSortedMessages(
  Iterable<Map<String, Object?>> messages,
) {
  final next = messages
      .map((item) => Map<String, Object?>.from(item))
      .toList(growable: false);
  next.sort(_paymentServiceCompareMessages);
  return next;
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
  final timeLeft = _messageDateTime(left);
  final timeRight = _messageDateTime(right);
  if (timeLeft != null && timeRight != null) {
    final result = timeLeft.compareTo(timeRight);
    if (result != 0) {
      return result;
    }
  }
  final epochLeft = _paymentServiceSortEpoch(left);
  final epochRight = _paymentServiceSortEpoch(right);
  if (epochLeft > 0 && epochRight > 0 && epochLeft != epochRight) {
    return epochLeft.compareTo(epochRight);
  }
  final seqLeft = _intValue(left, ['message_seq']);
  final seqRight = _intValue(right, ['message_seq']);
  if (seqLeft > 0 && seqRight > 0 && seqLeft != seqRight) {
    return seqLeft.compareTo(seqRight);
  }
  final timestampResult = _value(left, [
    'timestamp',
  ]).compareTo(_value(right, ['timestamp']));
  if (timestampResult != 0) {
    return timestampResult;
  }
  return _paymentServiceMessageKey(
    left,
  ).compareTo(_paymentServiceMessageKey(right));
}

int _paymentServiceSortEpoch(Map<String, Object?> item) {
  final timestamp = _value(item, [
    'timestamp',
    'client_timestamp',
    'send_time',
    'created_at',
    'create_time',
  ]);
  if (timestamp.isEmpty) {
    return 0;
  }
  final numeric = int.tryParse(timestamp);
  if (numeric != null) {
    return numeric > 9999999999 ? numeric : numeric * 1000;
  }
  return DateTime.tryParse(timestamp)?.millisecondsSinceEpoch ?? 0;
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
