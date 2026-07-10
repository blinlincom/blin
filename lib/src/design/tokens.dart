import 'package:flutter/material.dart';

/// BIM visual source of truth.
///
/// These tokens are intentionally conservative: BIM is a high-frequency IM and
/// wallet app, so hierarchy, readability and stable motion matter more than
/// decorative effects.
abstract final class BimColors {
  static const primary = Color(0xff1677ff);
  static const primaryPressed = Color(0xff0f5fcc);
  static const primaryWeak = Color(0xffeef5ff);
  static const background = Color(0xfff5f6f8);
  static const chatBackground = Color(0xfff7f8fa);
  static const surface = Color(0xffffffff);
  static const surfaceElevated = Color(0xfffbfcfd);
  static const fill = Color(0xfff4f5f7);
  static const fillPressed = Color(0xffeceef2);
  static const border = Color(0xffe7e8ec);
  static const borderLight = Color(0xfff0f1f4);
  static const text = Color(0xff202124);
  static const textDark = Color(0xff111827);
  static const secondaryText = Color(0xff6f7785);
  static const mutedText = Color(0xff9aa0aa);
  static const success = Color(0xff34c759);
  static const online = Color(0xff55c875);
  static const ack = Color(0xff42c977);
  static const warning = Color(0xffffb020);
  static const danger = Color(0xffdc2626);
  static const dangerDeep = Color(0xffa40000);
  static const redPacket = Color(0xffff543c);
  static const transfer = Color(0xffff8a00);
  static const mineBubble = Color(0xffdff6d8);
  static const scrim = Color(0x66000000);
}

abstract final class BimRadius {
  static const none = 0.0;
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 10.0;
  static const brand = 12.0;
  static const pill = 999.0;
}

abstract final class BimSpacing {
  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 24.0;
  static const x8 = 32.0;
}

abstract final class BimTypography {
  static const caption = 12.0;
  static const meta = 13.0;
  static const body = 15.0;
  static const bodyLarge = 16.0;
  static const title = 17.0;
  static const profile = 20.0;
  static const section = 22.0;
  static const authTitle = 34.0;
}

abstract final class BimDimensions {
  static const menuRow = 52.0;
  static const contactRow = 56.0;
  static const conversationRow = 72.0;
  static const appBar = 50.0;
  static const chatHeader = 58.0;
  static const composerControl = 42.0;
  static const chatToolsPanel = 328.0;
  static const chatToolsPanelMax = 348.0;
  static const toolIcon = 54.0;
  static const avatarSm = 32.0;
  static const avatarMd = 42.0;
  static const avatarLg = 56.0;
  static const touchTarget = 44.0;
}

abstract final class BimOpacity {
  static const pressed = 0.72;
  static const disabled = 0.42;
  static const divider = 0.72;
}
