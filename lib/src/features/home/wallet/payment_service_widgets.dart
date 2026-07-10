part of 'package:bim/src/features/home/home_page.dart';

class _PaymentServiceHeader extends StatelessWidget {
  const _PaymentServiceHeader({
    required this.title,
    required this.searching,
    required this.searchController,
    required this.onBack,
    required this.onSearch,
    required this.onSettings,
  });

  final String title;
  final bool searching;
  final TextEditingController searchController;
  final VoidCallback onBack;
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: searching ? 98 : 54,
      color: _paymentServiceBackground,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                const SizedBox(width: 4),
                _PaymentHeaderIconButton(
                  icon: Icons.arrow_back_ios_new,
                  label: '返回',
                  onTap: onBack,
                ),
                Expanded(
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
                _PaymentHeaderIconButton(
                  icon: searching ? Icons.close : Icons.search,
                  label: searching ? '关闭搜索' : '搜索',
                  onTap: onSearch,
                ),
                _PaymentHeaderIconButton(
                  icon: Icons.settings_outlined,
                  label: '设置',
                  onTap: onSettings,
                ),
                const SizedBox(width: 4),
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
                    hintText: '搜索相关通知',
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

class _ServiceAccountMessageCard extends StatelessWidget {
  const _ServiceAccountMessageCard({
    required this.item,
    required this.serviceName,
    required this.serviceAvatar,
  });

  final Map<String, Object?> item;
  final String serviceName;
  final String serviceAvatar;

  @override
  Widget build(BuildContext context) {
    final payload = _asObjectMap(item['payload']);
    final title = _value(
      payload,
      ['title', 'summary_title'],
      fallback: _messageSenderName(item) == '成员'
          ? serviceName
          : _messageSenderName(item),
    );
    final text = _messageContentText(item, payload).trim();
    final content = text.isEmpty ? '服务通知' : text;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: _paymentServiceContentMaxWidth,
        ),
        child: Material(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(_paymentServiceCardRadius),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(
                  label: title,
                  imageUrl: serviceAvatar.isNotEmpty
                      ? serviceAvatar
                      : _messageSenderAvatarUrl(item),
                  size: 34,
                  color: _primaryColor,
                  icon: Icons.verified_user_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _paymentServiceText,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        content,
                        style: const TextStyle(
                          color: _secondaryTextColor,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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
    required this.menus,
    required this.onMenuTap,
  });

  final List<Map<String, Object?>> menus;
  final ValueChanged<Map<String, Object?>> onMenuTap;

  @override
  Widget build(BuildContext context) {
    final visibleMenus = menus
        .where((item) => _serviceMenuLabel(item).isNotEmpty)
        .toList(growable: false);
    if (visibleMenus.isEmpty) {
      return const SizedBox.shrink();
    }
    return ColoredBox(
      color: _surfaceColor,
      child: SafeArea(
        top: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            color: _surfaceColor,
            border: Border(
              top: BorderSide(color: Color(0xffdddddd), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: _PaymentServiceMenuButton(
                  icon: Icons.apps,
                  label: '服务',
                  showText: false,
                  onTap: () => onMenuTap(visibleMenus.first),
                ),
              ),
              const _PaymentServiceVerticalDivider(),
              Expanded(
                child: visibleMenus.length <= 3
                    ? Row(
                        children: [
                          for (
                            var index = 0;
                            index < visibleMenus.length;
                            index++
                          )
                            Expanded(
                              child: Row(
                                children: [
                                  if (index > 0)
                                    const _PaymentServiceVerticalDivider(),
                                  Expanded(
                                    child: _PaymentServiceMenuButton(
                                      label: _serviceMenuLabel(
                                        visibleMenus[index],
                                      ),
                                      onTap: () =>
                                          onMenuTap(visibleMenus[index]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        itemCount: visibleMenus.length,
                        separatorBuilder: (_, __) =>
                            const _PaymentServiceVerticalDivider(),
                        itemBuilder: (context, index) {
                          final item = visibleMenus[index];
                          return SizedBox(
                            width: 108,
                            child: _PaymentServiceMenuButton(
                              label: _serviceMenuLabel(item),
                              onTap: () => onMenuTap(item),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
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
    return Container(width: 0.5, height: 24, color: BimColors.border);
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
    return BimEmptyState(
      title: '加载失败',
      message: message.replaceFirst('Exception: ', ''),
      icon: Icons.refresh,
      actionLabel: '重试',
      onAction: onRetry,
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
    this.actionText = '',
    this.onAction,
  });

  final String title;
  final String amount;
  final List<_PaymentServiceDetailRowData> rows;
  final String actionText;
  final VoidCallback? onAction;

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
              color: BimColors.border,
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
          if (actionText.isNotEmpty && onAction != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(onPressed: onAction, child: Text(actionText)),
            ),
          ],
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
