import 'package:flutter/widgets.dart';

abstract final class BimBreakpoints {
  static const compact = 0.0;
  static const medium = 600.0;
  static const expanded = 840.0;
  static const desktop = 1024.0;

  static bool isMedium(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= medium;
  }

  static bool isExpanded(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= expanded;
  }

  static double horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktop) {
      return 32;
    }
    if (width >= medium) {
      return 24;
    }
    return 16;
  }

  static double contentMaxWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= desktop) {
      return 720;
    }
    if (width >= medium) {
      return 640;
    }
    return double.infinity;
  }
}
