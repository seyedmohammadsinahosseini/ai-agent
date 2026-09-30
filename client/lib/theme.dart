import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern, clean SaaS-style dark theme (Linear/Notion-esque) rather than a
/// raw "hacker terminal" look — this app should feel like a polished product.
class AppColors {
  static const bg = Color(0xFF0B0D12);
  static const surface = Color(0xFF13161D);
  static const surfaceElevated = Color(0xFF1A1E27);
  static const surfaceHighlight = Color(0xFF20242F);
  static const border = Color(0xFF272B36);
  static const borderSubtle = Color(0xFF1E212B);

  static const textPrimary = Color(0xFFEDEEF2);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textMuted = Color(0xFF6B7280);

  static const accent = Color(0xFF6C8CFF);
  static const accentSoft = Color(0xFF6C8CFF);

  static const planColor = Color(0xFF6C8CFF);
  static const buildColor = Color(0xFFFF9F5A);

  static const safe = Color(0xFF3DDC97);
  static const confirm = Color(0xFFF5C542);
  static const dangerous = Color(0xFFFF7A59);
  static const blocked = Color(0xFFFF5C5C);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.buildColor,
      surface: AppColors.surface,
      error: AppColors.blocked,
    ),
  );

  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerColor: AppColors.border,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceElevated,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
      hintStyle: const TextStyle(color: AppColors.textMuted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surfaceHighlight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
    ),
  );
}

TextStyle monoStyle({double fontSize = 13, Color? color, FontWeight? fontWeight}) {
  return GoogleFonts.jetBrainsMono(
    fontSize: fontSize,
    color: color ?? AppColors.textPrimary,
    fontWeight: fontWeight,
  );
}
