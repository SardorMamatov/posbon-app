import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF061310);
  static const Color surface = Color(0xFF0D1D19);
  static const Color secondarySurface = Color(0xFF142723);
  static const Color mutedSurface = Color(0xFF1C322D);
  static const Color outline = Color(0xFF23453D);
  static const Color accent = Color(0xFF63D5B0);
  static const Color description = Color(0xFF9BB3AC);
  static const Color danger = Color(0xFFFF7A7A);
  static const Color warning = Color(0xFFFFD27A);
}

ThemeData buildPosbonTheme() {
  const textTheme = TextTheme(
    headlineLarge: TextStyle(
      color: Colors.white,
      fontSize: 28,
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: TextStyle(
      color: Colors.white,
      fontSize: 24,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: TextStyle(
      color: Colors.white,
      fontSize: 14,
    ),
    bodyMedium: TextStyle(
      color: AppColors.description,
      fontSize: 14,
    ),
  );

  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: textTheme,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.surface,
    ),
    splashFactory: NoSplash.splashFactory,
  );
}
