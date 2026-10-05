import 'package:flutter/material.dart';

abstract final class HealthPalColors {
  static const background = Color(0xFFF5F5FA);
  static const ink = Color(0xFF191A24);
  static const secondary = Color(0xFF626575);
  static const blue = Color(0xFF0069E8);
  static const input = Color(0xFFF7F8FC);
  static const border = Color(0xFFE5E7EF);
}

final ThemeData healthPalTheme = _buildTheme();

ThemeData _buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: HealthPalColors.blue,
      primary: HealthPalColors.blue,
      surface: Colors.white,
      error: const Color(0xFFB3263A),
    ),
    scaffoldBackgroundColor: HealthPalColors.background,
    visualDensity: VisualDensity.standard,
  );
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: HealthPalColors.ink,
      displayColor: HealthPalColors.ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HealthPalColors.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      hintStyle: const TextStyle(
        fontSize: 14,
        color: HealthPalColors.secondary,
      ),
      prefixIconColor: HealthPalColors.secondary,
      suffixIconColor: HealthPalColors.secondary,
      border: border(HealthPalColors.border),
      enabledBorder: border(HealthPalColors.border),
      focusedBorder: border(HealthPalColors.blue, 1.5),
      errorBorder: border(base.colorScheme.error),
      focusedErrorBorder: border(base.colorScheme.error, 1.5),
      errorMaxLines: 3,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
  );
}
