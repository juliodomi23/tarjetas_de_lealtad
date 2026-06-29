import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Color base — sobreescrito en runtime con el valor del backend.
Color brand = const Color(0xFFE23B3B);
const ink = Color(0xFF0F172A); // texto principal (slate-900)
const muted = Color(0xFF64748B); // texto secundario (slate-500)
const line = Color(0xFFE2E8F0); // bordes (slate-200)
const surface = Color(0xFFF6F7FB); // fondo
const success = Color(0xFF16A34A);

// Gradiente de la "tarjeta física".
const cardGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1E2340), Color(0xFF111528)],
);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: brand,
    primary: brand,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: surface,
    textTheme: GoogleFonts.poppinsTextTheme().apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      foregroundColor: ink,
      centerTitle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: muted),
      border: _inputBorder(line),
      enabledBorder: _inputBorder(line),
      focusedBorder: _inputBorder(brand, width: 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color c, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: width),
    );
