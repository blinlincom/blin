part of 'package:bim/src/features/home/home_page.dart';

class _WalletPaymentCodeSurface extends StatelessWidget {
  const _WalletPaymentCodeSurface({
    required this.order,
    required this.secondsLeft,
    required this.busy,
    required this.errorText,
    required this.onOpen,
  });

  final WalletOrder? order;
  final int secondsLeft;
  final bool busy;
  final String errorText;
  final VoidCallback? onOpen;

  bool get _hasCode {
    final current = order;
    return current != null &&
        current.qrPayload.isNotEmpty &&
        (current.barPayload.isNotEmpty || current.qrToken.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BimColors.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 360.0;
          final codeSize = (availableWidth - 64).clamp(208.0, 276.0);
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              BimSpacing.x5,
              BimSpacing.x5,
              BimSpacing.x5,
              BimSpacing.x4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _WalletPaymentCodeHeader(
                  active: _hasCode,
                  busy: busy,
                  failed: errorText.isNotEmpty,
                ),
                const SizedBox(height: BimSpacing.x4),
                const Divider(height: 0.5),
                if (busy && _hasCode)
                  const LinearProgressIndicator(minHeight: 2),
                AnimatedSwitcher(
                  duration: BimMotion.normal,
                  switchInCurve: BimMotion.curve,
                  switchOutCurve: BimMotion.exitCurve,
                  child: errorText.isNotEmpty
                      ? _WalletPaymentCodeError(
                          key: const ValueKey('payment-code-error'),
                          message: errorText,
                          busy: busy,
                          onRetry: onOpen,
                        )
                      : _hasCode
                      ? _WalletPaymentCodeReady(
                          key: const ValueKey('payment-code-ready'),
                          order: order!,
                          secondsLeft: secondsLeft,
                          codeSize: codeSize,
                        )
                      : _WalletPaymentCodeLocked(
                          key: const ValueKey('payment-code-locked'),
                          busy: busy,
                          onOpen: onOpen,
                        ),
                ),
                const SizedBox(height: BimSpacing.x4),
                const _WalletPaymentSecurityNote(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WalletPaymentCodeHeader extends StatelessWidget {
  const _WalletPaymentCodeHeader({
    required this.active,
    required this.busy,
    required this.failed,
  });

  final bool active;
  final bool busy;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final statusText = failed
        ? '需要处理'
        : busy
        ? '正在更新'
        : active
        ? '安全可用'
        : '密码保护';
    final statusColor = failed
        ? BimColors.danger
        : active
        ? BimColors.success
        : BimColors.primary;
    final statusIcon = failed
        ? Icons.error_outline
        : active
        ? Icons.verified_user_outlined
        : Icons.lock_outline;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: BimColors.primaryWeak,
            borderRadius: BorderRadius.circular(BimRadius.md),
          ),
          child: const Icon(
            Icons.qr_code_2,
            color: BimColors.primary,
            size: 25,
          ),
        ),
        const SizedBox(width: BimSpacing.x3),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '付款码',
                style: TextStyle(
                  color: BimColors.textDark,
                  fontSize: BimTypography.profile,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '向商户出示，确认金额后完成付款',
                style: TextStyle(
                  color: BimColors.secondaryText,
                  fontSize: BimTypography.meta,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: BimSpacing.x2),
        Semantics(
          label: '付款码状态$statusText',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 16),
              const SizedBox(width: 4),
              Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: BimTypography.caption,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WalletPaymentCodeLocked extends StatelessWidget {
  const _WalletPaymentCodeLocked({
    required this.busy,
    required this.onOpen,
    super.key,
  });

  final bool busy;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, BimSpacing.x8, 0, BimSpacing.x4),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: BimColors.fill,
              border: Border.all(color: BimColors.border),
              borderRadius: BorderRadius.circular(BimRadius.md),
            ),
            child: const Icon(
              Icons.lock_person_outlined,
              color: BimColors.primary,
              size: 38,
            ),
          ),
          const SizedBox(height: BimSpacing.x4),
          const Text(
            '验证后显示付款码',
            style: TextStyle(
              color: BimColors.textDark,
              fontSize: BimTypography.bodyLarge,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: BimSpacing.x2),
          const Text(
            '付款码涉及资金安全，每次重新登录后需要验证支付密码。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: BimColors.secondaryText,
              fontSize: BimTypography.meta,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          const SizedBox(height: BimSpacing.x5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: BimButton(
              label: '验证并打开付款码',
              icon: Icons.lock_open_outlined,
              busy: busy,
              onPressed: busy ? null : onOpen,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletPaymentCodeError extends StatelessWidget {
  const _WalletPaymentCodeError({
    required this.message,
    required this.busy,
    required this.onRetry,
    super.key,
  });

  final String message;
  final bool busy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, BimSpacing.x6, 0, BimSpacing.x4),
      child: Column(
        children: [
          BimNoticeBanner(text: message, tone: BimNoticeTone.error),
          const SizedBox(height: BimSpacing.x4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: BimButton(
              label: '重新验证',
              icon: Icons.refresh,
              busy: busy,
              onPressed: busy ? null : onRetry,
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletPaymentCodeReady extends StatelessWidget {
  const _WalletPaymentCodeReady({
    required this.order,
    required this.secondsLeft,
    required this.codeSize,
    super.key,
  });

  final WalletOrder order;
  final int secondsLeft;
  final double codeSize;

  @override
  Widget build(BuildContext context) {
    final barcodeValue = order.barPayload.isEmpty
        ? order.qrToken
        : order.barPayload;
    final refreshLabel = secondsLeft > 0 ? '$secondsLeft 秒后自动更新' : '付款码将自动更新';
    return Padding(
      padding: const EdgeInsets.only(top: BimSpacing.x5),
      child: Column(
        children: [
          Semantics(
            label: '付款条形码',
            image: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _WalletBarcode(value: barcodeValue),
            ),
          ),
          const SizedBox(height: BimSpacing.x4),
          Semantics(
            label: '付款二维码',
            image: true,
            child: Container(
              width: codeSize,
              height: codeSize,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(BimSpacing.x2),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: BimColors.border),
                borderRadius: BorderRadius.circular(BimRadius.sm),
              ),
              child: QrImageView(
                data: order.qrPayload,
                version: QrVersions.auto,
                size: codeSize - BimSpacing.x4,
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
          ),
          const SizedBox(height: BimSpacing.x4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.sync, size: 16, color: BimColors.secondaryText),
              const SizedBox(width: 6),
              Text(
                refreshLabel,
                style: const TextStyle(
                  color: BimColors.secondaryText,
                  fontSize: BimTypography.meta,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (order.expireTime.isNotEmpty) ...[
            const SizedBox(height: BimSpacing.x1),
            Text(
              '本次有效期至 ${order.expireTime}',
              style: const TextStyle(
                color: BimColors.mutedText,
                fontSize: BimTypography.caption,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WalletPaymentSecurityNote extends StatelessWidget {
  const _WalletPaymentSecurityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x3,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: BimColors.primaryWeak,
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 18, color: BimColors.primary),
          SizedBox(width: BimSpacing.x2),
          Expanded(
            child: Text(
              '请仅向收款商户出示付款码，不要截图、录屏或转发给他人。',
              style: TextStyle(
                color: BimColors.primary,
                fontSize: BimTypography.meta,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
