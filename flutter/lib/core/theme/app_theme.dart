import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const background = Color(0xFF0D1730);
  const surface = Color(0xFF17284B);
  const accent = Color(0xFF29A0F0);
  const border = Color(0xFF2B4472);
  const text = Color(0xFFF3F7FF);
  const muted = Color(0xFFA4B6D9);

  final scheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: accent,
        surface: surface,
        outline: border,
        onSurface: text,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    cardTheme: CardThemeData(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: border),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF1A2D56),
      labelStyle: const TextStyle(color: muted),
      hintStyle: const TextStyle(color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accent, width: 1.4),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: accent,
        foregroundColor: text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: text,
        fontSize: 38,
        fontWeight: FontWeight.w800,
      ),
      headlineMedium: TextStyle(
        color: text,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        color: text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(color: text),
      bodyMedium: TextStyle(color: muted),
    ),
  );
}
