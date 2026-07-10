import 'package:flutter/material.dart';

import '../../design/motion.dart';

class BimReveal extends StatelessWidget {
  const BimReveal({
    required this.child,
    this.visible = true,
    this.offset = const Offset(0, 10),
    super.key,
  });

  final Widget child;
  final bool visible;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: visible ? 1 : 0, end: visible ? 1 : 0),
      duration: BimMotion.normal,
      curve: BimMotion.curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(offset.dx * (1 - value), offset.dy * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
