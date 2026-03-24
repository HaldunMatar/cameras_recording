import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Palette ──────────────────────────────────────────────────────────────────

class AppColors {
  static const bg0    = Color(0xFF080A0E);
  static const bg1    = Color(0xFF0D1017);
  static const bg2    = Color(0xFF121620);
  static const bg3    = Color(0xFF181D28);
  static const border  = Color(0x12FFFFFF);
  static const border2 = Color(0x20FFFFFF);
  static const text    = Color(0xFFD8DCE8);
  static const text2   = Color(0xFF7A8299);
  static const text3   = Color(0xFF454E63);
  static const red     = Color(0xFFE63950);
  static const red2    = Color(0xFFFF6B35);
  static const green   = Color(0xFF1DE9A0);
  static const blue    = Color(0xFF3D8EF0);
}

// ─── Theme ────────────────────────────────────────────────────────────────────

class AppTheme {
  static ThemeData get dark {
    const cs = ColorScheme(
      brightness:        Brightness.dark,
      primary:           AppColors.red,
      onPrimary:         Colors.white,
      secondary:         AppColors.blue,
      onSecondary:       Colors.white,
      error:             AppColors.red,
      onError:           Colors.white,
      surface:           AppColors.bg2,
      onSurface:         AppColors.text,
      background:        AppColors.bg0,
      onBackground:      AppColors.text,
      surfaceVariant:    AppColors.bg3,
      onSurfaceVariant:  AppColors.text2,
      outline:           AppColors.border,
      outlineVariant:    AppColors.border2,
    );

    return ThemeData(
      useMaterial3:             true,
      colorScheme:              cs,
      scaffoldBackgroundColor:  AppColors.bg0,
      fontFamily:               'Roboto',
      appBarTheme: const AppBarTheme(
        backgroundColor:        AppColors.bg1,
        foregroundColor:        AppColors.text,
        elevation:              0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:             Colors.transparent,
          statusBarIconBrightness:    Brightness.light,
          systemNavigationBarColor:   AppColors.bg1,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor:  AppColors.bg1,
        indicatorColor:   AppColors.red.withOpacity(0.15),
        labelTextStyle: MaterialStateProperty.resolveWith((s) {
          final active = s.contains(MaterialState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.red : AppColors.text3,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((s) {
          final active = s.contains(MaterialState.selected);
          return IconThemeData(
            color: active ? AppColors.red : AppColors.text3,
            size: 22,
          );
        }),
      ),
      // cardTheme: CardTheme(
      //   color:        AppColors.bg1,
      //   elevation:    0,
      //   shape: RoundedRectangleBorder(
      //     borderRadius: BorderRadius.circular(14),
      //     side: const BorderSide(color: AppColors.border),
      //   ),
      // ),
      dividerColor:   AppColors.border,
      // dialogTheme: DialogTheme(
      //   backgroundColor: AppColors.bg2,
      //   shape: RoundedRectangleBorder(
      //     borderRadius: BorderRadius.circular(16),
      //     side: const BorderSide(color: AppColors.border2),
      //   ),
      // ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:    AppColors.bg2,
        contentTextStyle:   const TextStyle(color: AppColors.text, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:            true,
        fillColor:         AppColors.bg1,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.text2, fontSize: 13),
        hintStyle:  const TextStyle(color: AppColors.text3, fontSize: 13),
      ),
    );
  }
}
