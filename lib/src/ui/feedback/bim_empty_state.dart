import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../button/bim_button.dart';

class BimEmptyState extends StatelessWidget {
  const BimEmptyState({
    required this.title,
    this.message = '',
    this.icon,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BimSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: BimColors.mutedText, size: 38),
              const SizedBox(height: 14),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: BimColors.text,
                fontSize: BimTypography.body,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: BimColors.secondaryText,
                  fontSize: BimTypography.meta,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
            if ((actionLabel ?? '').isNotEmpty && onAction != null) ...[
              const SizedBox(height: 18),
              BimButton(
                label: actionLabel!,
                onPressed: onAction,
                kind: BimButtonKind.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
