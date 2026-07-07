import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_config.dart';
import '../core/design_tokens.dart';
import '../features/auth/auth_page.dart';
import '../features/home/home_page.dart';
import 'session_controller.dart';

class BimApp extends StatefulWidget {
  const BimApp({required this.controller, super.key});

  final SessionController controller;

  @override
  State<BimApp> createState() => _BimAppState();
}

class _BimAppState extends State<BimApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.coldStart();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.appLifecycleChanged(state);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: _root(),
        );
      },
    );
  }

  Widget _root() {
    if (widget.controller.isLoggedIn) {
      return HomePage(controller: widget.controller);
    }
    return AuthPage(controller: widget.controller);
  }

  ThemeData _theme() {
    const black = BimColors.textDark;
    const blue = BimColors.primary;
    const border = BimColors.border;
    const fill = BimColors.fill;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: blue,
        brightness: Brightness.light,
        primary: blue,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: BimColors.background,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: black,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: BimColors.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          color: black,
          fontSize: BimTypography.title,
          fontWeight: FontWeight.w700,
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
          borderSide: BorderSide(color: blue, width: 1.4),
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
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          ),
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(
            fontSize: BimTypography.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          ),
          minimumSize: const Size.fromHeight(BimDimensions.touchTarget),
          side: const BorderSide(color: border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(BimRadius.sm)),
          ),
          foregroundColor: blue,
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: blue,
        unselectedItemColor: BimColors.secondaryText,
      ),
      snackBarTheme: const SnackBarThemeData(
        elevation: 0,
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }
}
