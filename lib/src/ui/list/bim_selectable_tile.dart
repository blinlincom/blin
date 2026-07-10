import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimSelectableTile extends StatelessWidget {
  const BimSelectableTile({
    required this.title,
    required this.selected,
    required this.onChanged,
    this.subtitle = '',
    this.leading,
    this.control = BimSelectableControl.checkmark,
    this.enabled = true,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final BimSelectableControl control;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x4,
        vertical: 9,
      ),
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border(bottom: BorderSide(color: BimColors.borderLight)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BimColors.text,
                    fontSize: BimTypography.body,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BimColors.mutedText,
                      fontSize: BimTypography.caption,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: BimSpacing.x3),
          switch (control) {
            BimSelectableControl.checkbox => Checkbox(
              value: selected,
              onChanged: enabled ? (value) => onChanged(value ?? false) : null,
              activeColor: BimColors.primary,
            ),
            BimSelectableControl.checkmark => _BimSelectionMark(
              selected: selected,
              enabled: enabled,
            ),
          },
        ],
      ),
    );
    return BimPressable(
      onTap: enabled ? () => onChanged(!selected) : null,
      semanticLabel: title,
      child: content,
    );
  }
}

class _BimSelectionMark extends StatelessWidget {
  const _BimSelectionMark({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && selected;
    return AnimatedContainer(
      duration: BimMotion.fast,
      curve: BimMotion.curve,
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? BimColors.primary : BimColors.surface,
        border: Border.all(
          color: active ? BimColors.primary : BimColors.border,
        ),
        shape: BoxShape.circle,
      ),
      child: active
          ? const Icon(Icons.check, color: Colors.white, size: 16)
          : null,
    );
  }
}

enum BimSelectableControl { checkmark, checkbox }
