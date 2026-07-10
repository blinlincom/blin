import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import 'bim_notice_banner.dart';

void showBimSnackBar(
  BuildContext context,
  String message, {
  BimNoticeTone tone = BimNoticeTone.info,
  Duration duration = const Duration(seconds: 2),
}) {
  final text = message.trim();
  if (text.isEmpty) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(
          BimSpacing.x4,
          0,
          BimSpacing.x4,
          BimSpacing.x5,
        ),
        elevation: 0,
        duration: duration,
        backgroundColor: _snackBackground(tone),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BimRadius.sm),
        ),
        content: Row(
          children: [
            Icon(_snackIcon(tone), size: 18, color: Colors.white),
            const SizedBox(width: BimSpacing.x2),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: BimTypography.body,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}

Color _snackBackground(BimNoticeTone tone) {
  return switch (tone) {
    BimNoticeTone.success => const Color(0xff166534),
    BimNoticeTone.error => const Color(0xffb42318),
    BimNoticeTone.warning => const Color(0xff92400e),
    BimNoticeTone.info => const Color(0xff1f2329),
  };
}

IconData _snackIcon(BimNoticeTone tone) {
  return switch (tone) {
    BimNoticeTone.success => Icons.check_circle_outline,
    BimNoticeTone.error => Icons.error_outline,
    BimNoticeTone.warning => Icons.info_outline,
    BimNoticeTone.info => Icons.info_outline,
  };
}
