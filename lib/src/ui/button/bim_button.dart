import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimButton extends StatelessWidget {
  const BimButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = BimButtonKind.primary,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final BimButtonKind kind;
  final bool busy;

  bool get _enabled => onPressed != null && !busy;

  @override
  Widget build(BuildContext context) {
    final foreground = switch (kind) {
      BimButtonKind.primary => Colors.white,
      BimButtonKind.secondary => BimColors.text,
      BimButtonKind.danger => Colors.white,
    };
    final background = switch (kind) {
      BimButtonKind.primary => BimColors.primary,
      BimButtonKind.secondary => BimColors.fill,
      BimButtonKind.danger => BimColors.danger,
    };
    return BimPressable(
      onTap: _enabled ? onPressed : null,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(BimRadius.sm),
          border: kind == BimButtonKind.secondary
              ? Border.all(color: BimColors.border)
              : null,
        ),
        child: AnimatedSwitcher(
          duration: BimMotion.fast,
          child: busy
              ? SizedBox(
                  key: const ValueKey('busy'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: foreground),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: BimTypography.body,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

enum BimButtonKind { primary, secondary, danger }
