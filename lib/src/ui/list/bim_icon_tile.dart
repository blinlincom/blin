import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimIconTile extends StatelessWidget {
  const BimIconTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle = '',
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.showDivider = true,
    super.key,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minHeight: BimDimensions.menuRow),
          padding: const EdgeInsets.symmetric(
            horizontal: BimSpacing.x4,
            vertical: BimSpacing.x2,
          ),
          color: BimColors.surface,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: BimSpacing.x3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
              if (trailing != null) ...[
                const SizedBox(width: BimSpacing.x2),
                trailing!,
              ],
              if (showChevron) ...[
                const SizedBox(width: BimSpacing.x1),
                const Icon(
                  Icons.chevron_right,
                  color: BimColors.mutedText,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: BimSpacing.x4),
            child: Divider(height: 0.5),
          ),
      ],
    );
    return BimPressable(onTap: onTap, semanticLabel: title, child: tile);
  }
}
