import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';

abstract final class BimTheme {
  static ThemeData light() {
    const primary = BimColors.primary;
    const border = BimColors.border;
    const fill = BimColors.fill;
    const text = BimColors.textDark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      surface: BimColors.surface,
      error: BimColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: BimColors.background,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _BimPageTransitionsBuilder(),
          TargetPlatform.iOS: _BimPageTransitionsBuilder(),
          TargetPlatform.macOS: _BimPageTransitionsBuilder(),
          TargetPlatform.windows: _BimPageTransitionsBuilder(),
          TargetPlatform.linux: _BimPageTransitionsBuilder(),
        },
      ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: BimColors.surface,
        foregroundColor: text,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: BimColors.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: text,
          fontSize: BimTypography.title,
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          color: BimColors.textDark,
          fontSize: BimTypography.profile,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        titleMedium: TextStyle(
          color: BimColors.text,
          fontSize: BimTypography.title,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
        bodyLarge: TextStyle(
          color: BimColors.text,
          fontSize: BimTypography.bodyLarge,
          fontWeight: FontWeight.w500,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          color: BimColors.text,
          fontSize: BimTypography.body,
          fontWeight: FontWeight.w500,
          height: 1.42,
        ),
        labelMedium: TextStyle(
          color: BimColors.secondaryText,
          fontSize: BimTypography.meta,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          borderSide: BorderSide(color: BimColors.danger),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          ),
          textStyle: const TextStyle(
            fontSize: BimTypography.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size.fromHeight(BimDimensions.touchTarget),
          side: const BorderSide(color: border),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 0.5,
        space: 0.5,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        backgroundColor: BimColors.surface,
        selectedItemColor: primary,
        unselectedItemColor: BimColors.secondaryText,
      ),
      snackBarTheme: const SnackBarThemeData(
        elevation: 0,
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BimColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: BimColors.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
    );
  }
}

class _BimPageTransitionsBuilder extends PageTransitionsBuilder {
  const _BimPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return BimMotion.fadeSlideTransition(animation: animation, child: child);
  }
}
