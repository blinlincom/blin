import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/breakpoints.dart';

/// Keeps task-focused pages readable on tablets and desktop without changing
/// the full-width phone layout.
class BimContentViewport extends StatelessWidget {
  const BimContentViewport({
    required this.child,
    this.maxWidth = 720,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: alignment,
            child: SizedBox(
              width: math.min(maxWidth, constraints.maxWidth),
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : null,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class BimPagePadding extends StatelessWidget {
  const BimPagePadding({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: BimBreakpoints.horizontalPadding(context),
      ),
      child: child,
    );
  }
}
