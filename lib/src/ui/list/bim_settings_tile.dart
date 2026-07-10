import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimSettingsTile extends StatelessWidget {
  const BimSettingsTile({
    required this.title,
    this.value = '',
    this.onTap,
    this.tone = BimSettingsTileTone.normal,
    this.showChevron,
    this.valueMaxLines = 1,
    this.minHeight = 58,
    super.key,
  });

  final String title;
  final String value;
  final VoidCallback? onTap;
  final BimSettingsTileTone tone;
  final bool? showChevron;
  final int valueMaxLines;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final danger = tone == BimSettingsTileTone.danger;
    final chevron = showChevron ?? onTap != null;
    final content = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x4,
        vertical: BimSpacing.x4,
      ),
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border(bottom: BorderSide(color: BimColors.borderLight)),
      ),
      child: Row(
        crossAxisAlignment: valueMaxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: value.isEmpty ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: danger ? BimColors.dangerDeep : BimColors.text,
                fontSize: BimTypography.bodyLarge,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(width: BimSpacing.x4),
            Flexible(
              child: Text(
                value,
                maxLines: valueMaxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: BimColors.secondaryText,
                  fontSize: BimTypography.body,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ),
          ],
          if (chevron) ...[
            const SizedBox(width: BimSpacing.x1),
            const Icon(
              Icons.chevron_right,
              color: BimColors.mutedText,
              size: 22,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return content;
    }
    return BimPressable(onTap: onTap, semanticLabel: title, child: content);
  }
}

class BimSettingsSwitchTile extends StatelessWidget {
  const BimSettingsSwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border(bottom: BorderSide(color: BimColors.borderLight)),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: TextStyle(
            color: onChanged == null ? BimColors.mutedText : BimColors.text,
            fontSize: BimTypography.bodyLarge,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        subtitle: subtitle.isEmpty
            ? null
            : Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BimColors.mutedText,
                  fontSize: BimTypography.caption,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
        activeThumbColor: BimColors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: BimSpacing.x4),
      ),
    );
  }
}

enum BimSettingsTileTone { normal, danger }
