import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/tokens.dart';

class BimSegmentOption<T> {
  const BimSegmentOption({required this.value, required this.label});

  final T value;
  final String label;
}

class BimSegmentedControl<T> extends StatelessWidget {
  const BimSegmentedControl({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.scrollable = false,
    this.height = BimDimensions.touchTarget,
    super.key,
  });

  final List<BimSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool scrollable;
  final double height;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final option in options)
        _BimSegmentButton<T>(
          option: option,
          selected: option.value == selected,
          onChanged: onChanged,
          height: height,
          expanded: !scrollable,
        ),
    ];
    final row = Row(
      mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
      children: scrollable
          ? [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: BimSpacing.x2),
                children[i],
              ],
            ]
          : [for (final child in children) Expanded(child: child)],
    );
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: BimColors.fill,
        borderRadius: BorderRadius.circular(BimRadius.md),
      ),
      child: Padding(padding: const EdgeInsets.all(3), child: row),
    );
    if (!scrollable) {
      return content;
    }
    return ColoredBox(
      color: BimColors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: BimSpacing.x4,
          vertical: 10,
        ),
        child: content,
      ),
    );
  }
}

class _BimSegmentButton<T> extends StatelessWidget {
  const _BimSegmentButton({
    required this.option,
    required this.selected,
    required this.onChanged,
    required this.height,
    required this.expanded,
  });

  final BimSegmentOption<T> option;
  final bool selected;
  final ValueChanged<T> onChanged;
  final double height;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedContainer(
      duration: BimMotion.fast,
      curve: BimMotion.curve,
      height: height,
      constraints: BoxConstraints(minWidth: expanded ? 0 : 72),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: BimSpacing.x3),
      decoration: BoxDecoration(
        color: selected ? BimColors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(BimRadius.sm),
        border: selected ? Border.all(color: BimColors.borderLight) : null,
      ),
      child: Text(
        option.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected ? BimColors.primary : BimColors.secondaryText,
          fontSize: BimTypography.meta,
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
    final wrapped = selected
        ? child
        : BimPressable(
            onTap: () => onChanged(option.value),
            semanticLabel: option.label,
            child: child,
          );
    return Semantics(button: true, selected: selected, child: wrapped);
  }
}
