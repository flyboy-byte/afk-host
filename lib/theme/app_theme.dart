/// App theme for AFK Host.
/// Mimics native macOS grouped form styling.
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // macOS-like colors
  static const background = Color(0xFF1E1E1E);
  static const groupedBackground = Color(0xFF2A2A2A);
  static const separator = Color(0xFF3A3A3A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF98989D);
  static const accent = Color(0xFF0A84FF);
  static const destructive = Color(0xFFFF453A);
  static const success = Color(0xFF32D74B);
  static const warning = Color(0xFFFF9F0A);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.separator,
      primaryColor: AppColors.accent,

      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        surface: AppColors.groupedBackground,
        error: AppColors.destructive,
      ),

      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        bodySmall: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        labelMedium: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.separator,
        thickness: 0.5,
        space: 0.5,
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          backgroundColor: AppColors.accent.withValues(alpha: 0.08),
          side: BorderSide(color: AppColors.accent.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          backgroundColor: AppColors.textSecondary.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accent;
          }
          return AppColors.separator;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
