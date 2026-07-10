import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class BimNoticeBanner extends StatelessWidget {
  const BimNoticeBanner({
    required this.text,
    this.tone = BimNoticeTone.info,
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final String text;
  final BimNoticeTone tone;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = _toneColors(tone);
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.symmetric(
        horizontal: BimSpacing.x3,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(BimRadius.sm),
      ),
      child: Text(
        text,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.foreground,
          fontSize: BimTypography.meta,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  _BimNoticeColors _toneColors(BimNoticeTone tone) {
    return switch (tone) {
      BimNoticeTone.success => const _BimNoticeColors(
        foreground: Color(0xff166534),
        background: Color(0xfff0fdf4),
        border: Color(0xffbbf7d0),
      ),
      BimNoticeTone.error => const _BimNoticeColors(
        foreground: BimColors.dangerDeep,
        background: Color(0xfffff2f2),
        border: Color(0xffffd6d6),
      ),
      BimNoticeTone.warning => const _BimNoticeColors(
        foreground: Color(0xff92400e),
        background: Color(0xfffffbeb),
        border: Color(0xfffde68a),
      ),
      BimNoticeTone.info => const _BimNoticeColors(
        foreground: BimColors.primary,
        background: BimColors.primaryWeak,
        border: Color(0xffd7e7ff),
      ),
    };
  }
}

enum BimNoticeTone { info, success, warning, error }

class _BimNoticeColors {
  const _BimNoticeColors({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;
}
