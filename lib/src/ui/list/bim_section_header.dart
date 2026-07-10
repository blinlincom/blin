import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class BimSectionHeader extends StatelessWidget {
  const BimSectionHeader({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x4),
      color: BimColors.background,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: BimColors.secondaryText,
          fontSize: BimTypography.caption,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

class BimInlineEmptyRow extends StatelessWidget {
  const BimInlineEmptyRow({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x4,
        vertical: 18,
      ),
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border(bottom: BorderSide(color: BimColors.borderLight)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: BimColors.mutedText,
          fontSize: BimTypography.body,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
