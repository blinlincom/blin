import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimSearchEntry extends StatelessWidget {
  const BimSearchEntry({
    required this.hintText,
    required this.onTap,
    this.backgroundColor = BimColors.surface,
    super.key,
  });

  final String hintText;
  final VoidCallback onTap;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BimSpacing.x4,
          BimSpacing.x2,
          BimSpacing.x4,
          10,
        ),
        child: BimPressable(
          onTap: onTap,
          semanticLabel: hintText,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x3),
            decoration: BoxDecoration(
              color: BimColors.fill,
              borderRadius: BorderRadius.circular(BimRadius.sm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search, color: BimColors.mutedText, size: 17),
                const SizedBox(width: BimSpacing.x2),
                Text(
                  hintText,
                  style: const TextStyle(
                    color: BimColors.mutedText,
                    fontSize: BimTypography.meta,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
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
