import 'package:flutter/material.dart';

/// Colours from the original design, with larger type and touch targets for
/// older users.
abstract final class AppColors {
  static const primary = Color(0xFF2E86C1);
  static const primaryLight = Color(0xFF5DADE2);
  static const background = Color(0xFFF5F8FA);
  static const danger = Color(0xFFE5484D);
  static const warning = Color(0xFFF5A524);
  static const success = Color(0xFF2E9E6B);
  static const muted = Color(0xFF8A94A6);
}

abstract final class AppTheme {
  static const _font = 'Tajawal';

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.primaryLight,
      error: AppColors.danger,
      surface: Colors.white,
    ),
    scaffold: AppColors.background,
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      error: AppColors.danger,
    ),
  );

  static ThemeData _build(ColorScheme scheme, {Color? scaffold}) {
    final base = ThemeData(
      colorScheme: scheme,
      fontFamily: _font,
      scaffoldBackgroundColor: scaffold ?? scheme.surface,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme.apply(fontFamily: _font);
    return base.copyWith(
      textTheme: text.copyWith(
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 17),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 16),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: const TextStyle(
          fontFamily: _font,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ).copyWith(color: scheme.onPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.brightness == Brightness.light
            ? Colors.white
            : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 54),
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.brightness == Brightness.light
            ? Colors.white
            : scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontFamily: _font,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
