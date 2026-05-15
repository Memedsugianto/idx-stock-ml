import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF3C50E0);
  static const primaryLight = Color(0xFFEEF2FF);
  static const success = Color(0xFF10B981);
  static const danger = Color(0xFFEF4444);
  static const sidebarBg = Color(0xFFFFFFFF);
  static const pageBg = Color(0xFFF1F5F9);
  static const cardBg = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFF64748B);
  static const border = Color(0xFFE2E8F0);
}

ThemeData buildDashboardTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.pageBg,
    cardTheme: CardThemeData(
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cardBg,
      foregroundColor: Color(0xFF0F172A),
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
  );
}
