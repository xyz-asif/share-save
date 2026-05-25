import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ── Backgrounds ─────────────────────────────────────────────
  static const bg          = Color(0xFFFAF0EE); // warm cream
  static const surface     = Color(0xFFFFFFFF);
  static const card        = Color(0xFFFFFFFF);
  static const cardHover   = Color(0xFFFFF5F3);

  // ── Accent (warm coral) ──────────────────────────────────────
  static const accent      = Color(0xFFE05C4B);
  static const accentSoft  = Color(0xFFFF8A78);
  static const accentDim   = Color(0x1AE05C4B); // 10%

  // ── Text ────────────────────────────────────────────────────
  static const textPrimary   = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B6B6B);
  static const textTertiary  = Color(0xFFB8B8B8);

  // ── Structure ────────────────────────────────────────────────
  static const border  = Color(0xFFEDE4E1);
  static const divider = Color(0xFFF5EDEA);
  static const shadow  = Color(0x12000000);

  // ── Status ───────────────────────────────────────────────────
  static const danger  = Color(0xFFFF3B30);
  static const success = Color(0xFF34C759);

  // ── Anchor color palette ─────────────────────────────────────
  static const List<Color> anchorPalette = [
    Color(0xFFE05C4B), // coral
    Color(0xFF5B8AF5), // blue
    Color(0xFF4CAF50), // green
    Color(0xFFFF9500), // orange
    Color(0xFF9B59B6), // purple
    Color(0xFF00BCD4), // teal
    Color(0xFFE91E8C), // pink
    Color(0xFF795548), // brown
  ];
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light();
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.accent,
        surface: AppColors.surface,
        onPrimary: Colors.white,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge: const TextStyle(
            color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w700),
        titleLarge: const TextStyle(
            color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        titleMedium: const TextStyle(
            color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500),
        bodyLarge: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
        bodyMedium: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        bodySmall: const TextStyle(color: AppColors.textTertiary, fontSize: 11),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      dividerColor: AppColors.divider,
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  // Keep dark variant for the share overlay bottom sheet surface
  static ThemeData get shareOverlay => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.transparent,
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      surface: Colors.transparent,
    ),
    textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
    inputDecorationTheme: light.inputDecorationTheme,
  );
}
