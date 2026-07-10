import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class BimLoadingState extends StatelessWidget {
  const BimLoadingState({this.label = '', this.compact = false, super.key});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? BimSpacing.x3 : BimSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  color: BimColors.secondaryText,
                  fontSize: BimTypography.meta,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
