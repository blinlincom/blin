import 'package:flutter/material.dart';

abstract final class BimMotion {
  static const instant = Duration(milliseconds: 80);
  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 320);

  static const reverseFast = Duration(milliseconds: 120);
  static const reverseNormal = Duration(milliseconds: 180);

  static const curve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;
  static const emphasized = Curves.easeOutQuart;

  static Widget fadeSlideTransition({
    required Animation<double> animation,
    required Widget child,
    Offset begin = const Offset(0.04, 0),
  }) {
    final curved = CurvedAnimation(parent: animation, curve: curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}

class BimPressable extends StatefulWidget {
  const BimPressable({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<BimPressable> createState() => _BimPressableState();
}

class _BimPressableState extends State<BimPressable> {
  bool _pressed = false;

  bool get _enabled =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  @override
  Widget build(BuildContext context) {
    final content = AnimatedScale(
      scale: _pressed && _enabled ? 0.985 : 1,
      duration: BimMotion.fast,
      curve: BimMotion.curve,
      child: AnimatedOpacity(
        opacity: _enabled ? 1 : 0.42,
        duration: BimMotion.fast,
        curve: BimMotion.curve,
        child: widget.child,
      ),
    );
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: _enabled ? widget.onTap : null,
        onLongPress: _enabled ? widget.onLongPress : null,
        onLongPressUp: _enabled ? () => setState(() => _pressed = false) : null,
        child: content,
      ),
    );
  }
}
