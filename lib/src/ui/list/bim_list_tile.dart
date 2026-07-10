import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimListTile extends StatelessWidget {
  const BimListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.minHeight = BimDimensions.menuRow,
    this.showDivider = true,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double minHeight;
  final bool showDivider;
  final int titleMaxLines;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      color: BimColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x4),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: BimColors.text,
                    fontSize: BimTypography.body,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: subtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: BimColors.secondaryText,
                      fontSize: BimTypography.meta,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: BimSpacing.x4),
            child: Divider(height: 0.5),
          ),
      ],
    );
    if (onTap == null && onLongPress == null) {
      return tile;
    }
    return BimPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: title,
      child: tile,
    );
  }
}
