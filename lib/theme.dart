import 'package:flutter/material.dart';

class CodeKeyTheme {
  static const background = Color(0xFF050912);
  static const surface = Color(0xFF0C1322);
  static const surfaceHigh = Color(0xFF121B2E);
  static const border = Color(0xFF26334B);
  static const primary = Color(0xFF7657FF);
  static const secondary = Color(0xFF286BFF);
  static const success = Color(0xFF20D578);
  static const warning = Color(0xFFFFC857);
  static const danger = Color(0xFFFF5D73);
  static const muted = Color(0xFF94A0B8);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      surface: surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme.copyWith(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: danger,
      ),
      scaffoldBackgroundColor: background,
      fontFamily: 'sans-serif',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.6),
        titleLarge: TextStyle(fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(height: 1.45),
        bodyMedium: TextStyle(height: 1.45),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh.withValues(alpha: 0.78),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
      ),
      dividerColor: border,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static const actionGradient = LinearGradient(
    colors: [Color(0xFF8A4FFF), Color(0xFF315CFF)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}
