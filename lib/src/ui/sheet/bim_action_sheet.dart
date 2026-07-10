import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimActionSheet extends StatelessWidget {
  const BimActionSheet({
    required this.children,
    this.title,
    this.footer,
    super.key,
  });

  final String? title;
  final List<Widget> children;
  final Widget? footer;

  static Future<T?> show<T>({
    required BuildContext context,
    required List<Widget> children,
    String? title,
    Widget? footer,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: BimColors.surface,
      builder: (_) =>
          BimActionSheet(title: title, footer: footer, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPadding(
      duration: BimMotion.normal,
      curve: BimMotion.curve,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
            if ((title ?? '').isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                title!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: BimColors.textDark,
                  fontSize: BimTypography.title,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
            if (footer != null) ...[const SizedBox(height: 12), footer!],
          ],
        ),
      ),
    );
  }
}

class BimActionSheetItem extends StatelessWidget {
  const BimActionSheetItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? BimColors.danger : BimColors.text;
    return BimPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x2),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: BimSpacing.x3),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: BimTypography.bodyLarge,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
