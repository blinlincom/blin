import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class BimTopBar extends StatelessWidget implements PreferredSizeWidget {
  const BimTopBar({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.centerTitle = true,
    this.backgroundColor = BimColors.surface,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final bool centerTitle;
  final Color backgroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(BimDimensions.appBar);

  @override
  Widget build(BuildContext context) {
    final titleWidget = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: BimColors.textDark,
            fontSize: BimTypography.title,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        if ((subtitle ?? '').isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: BimColors.secondaryText,
              fontSize: BimTypography.caption,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ],
    );
    return AppBar(
      toolbarHeight: BimDimensions.appBar,
      backgroundColor: backgroundColor,
      foregroundColor: BimColors.textDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle,
      leading: leading,
      title: titleWidget,
      actions: actions,
    );
  }
}
