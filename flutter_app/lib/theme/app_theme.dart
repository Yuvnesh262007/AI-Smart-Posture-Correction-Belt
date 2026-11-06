import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.forestOlive,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.forestOlive,
      onPrimary: AppColors.cream,
      secondary: AppColors.sageGreen,
      onSecondary: Colors.white,
      surface: AppColors.lightSurface,
      onSurface: AppColors.deepForest,
      error: AppColors.alertCoral,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.lightCanvas,
      dividerColor: AppColors.lightBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.lightCanvas,
        foregroundColor: AppColors.deepForest,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: AppColors.deepForest,
        displayColor: AppColors.deepForest,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.forestOlive,
          foregroundColor: AppColors.cream,
          disabledBackgroundColor: AppColors.softSage,
          disabledForegroundColor: AppColors.deepForest,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forestOlive,
          side: const BorderSide(color: AppColors.lightBorder),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.deepForest,
        contentTextStyle: const TextStyle(color: AppColors.cream),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.sageGreen,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.softSage,
      onPrimary: AppColors.deepForest,
      secondary: AppColors.sageGreen,
      onSecondary: AppColors.deepForest,
      surface: AppColors.darkSurface,
      onSurface: AppColors.cream,
      error: const Color(0xFFE39A8E),
      onError: AppColors.deepForest,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.darkCanvas,
      dividerColor: AppColors.darkBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.darkCanvas,
        foregroundColor: AppColors.cream,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: AppColors.cream,
        displayColor: AppColors.cream,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.softSage,
          foregroundColor: AppColors.deepForest,
          disabledBackgroundColor: AppColors.darkElevated,
          disabledForegroundColor: AppColors.softSage,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cream,
          side: const BorderSide(color: AppColors.darkBorder),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkElevated,
        contentTextStyle: const TextStyle(color: AppColors.cream),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
