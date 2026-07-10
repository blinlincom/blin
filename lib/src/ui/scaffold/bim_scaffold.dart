import 'package:flutter/material.dart';

import '../../design/tokens.dart';

class BimScaffold extends StatelessWidget {
  const BimScaffold({
    required this.body,
    this.backgroundColor = BimColors.background,
    this.topBar,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset,
    super.key,
  });

  final Widget body;
  final Color backgroundColor;
  final PreferredSizeWidget? topBar;
  final Widget? bottomNavigationBar;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: topBar,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(child: body),
    );
  }
}
