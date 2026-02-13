// BiblioGenius Dark Theme
//
// Modern dark mode with neon cyan accents.
// Clean, techy aesthetic with high contrast and sans-serif typography.

import 'package:flutter/material.dart';
import '../base/theme_interface.dart';

/// Color palette for Dark theme (Modern Neon)
class DarkColors {
  DarkColors._();

  // Backgrounds (slate tones)
  static const bg = Color(0xFF0F172A); // Slate 900
  static const surface = Color(0xFF1E293B); // Slate 800
  static const elevated = Color(0xFF334155); // Slate 700

  // Text
  static const textPrimary = Color(0xFFF8FAFC); // Slate 50 (near-white)
  static const textSecondary = Color(0xFF94A3B8); // Slate 400
  static const textMuted = Color(0xFF64748B); // Slate 500

  // Accent — Neon Cyan
  static const cyan = Color(0xFF06B6D4); // Cyan 500
  static const cyanLight = Color(0xFF22D3EE); // Cyan 400
  static const cyanDark = Color(0xFF0891B2); // Cyan 600

  // Borders
  static const border = Color(0xFF334155); // Slate 700
  static const borderSubtle = Color(0xFF1E293B); // Slate 800

  // Semantic
  static const error = Color(0xFFEF4444); // Red 500
  static const success = Color(0xFF10B981); // Emerald 500
}

class DarkTheme extends AppTheme {
  @override
  String get id => 'dark';

  @override
  String get displayName => 'Dark';

  @override
  String get description => 'Modern dark mode with neon cyan accents';

  @override
  Color get previewColor => DarkColors.cyan;

  @override
  Color get previewSecondaryColor => DarkColors.bg;

  @override
  String? get previewAsset => null;

  @override
  ThemeData buildTheme({Color? accentColor}) {
    return ThemeData(
      primaryColor: DarkColors.cyan,
      useMaterial3: true,
      scaffoldBackgroundColor: DarkColors.bg,
      brightness: Brightness.dark,

      appBarTheme: const AppBarTheme(
        backgroundColor: DarkColors.bg,
        foregroundColor: DarkColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: DarkColors.cyan, size: 22),
        actionsIconTheme: IconThemeData(color: DarkColors.cyan, size: 22),
      ),

      colorScheme: ColorScheme.fromSeed(
        seedColor: DarkColors.cyan,
        brightness: Brightness.dark,
        primary: DarkColors.cyan,
        secondary: DarkColors.cyanDark,
        surface: DarkColors.surface,
        onPrimary: DarkColors.bg,
        onSecondary: DarkColors.textPrimary,
        onSurface: DarkColors.textPrimary,
        outline: DarkColors.border,
        error: DarkColors.error,
      ),

      cardTheme: CardThemeData(
        color: DarkColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DarkColors.border, width: 1),
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.only(bottom: 12),
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
          height: 1.1,
        ),
        displayMedium: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.2,
        ),
        headlineLarge: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        headlineMedium: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: TextStyle(
          color: DarkColors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 14,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          color: DarkColors.textSecondary,
          fontSize: 12,
          height: 1.4,
        ),
        labelLarge: TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(
          color: DarkColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DarkColors.cyan,
          foregroundColor: DarkColors.bg,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DarkColors.cyan,
          side: const BorderSide(color: DarkColors.border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DarkColors.cyan,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DarkColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DarkColors.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DarkColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DarkColors.cyan, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DarkColors.error, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: const TextStyle(color: DarkColors.textMuted),
        labelStyle: const TextStyle(color: DarkColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: DarkColors.cyan),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),

      dividerTheme: const DividerThemeData(
        color: DarkColors.border,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: DarkColors.surface,
        side: const BorderSide(color: DarkColors.border, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: const TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: DarkColors.bg,
        selectedItemColor: DarkColors.cyan,
        unselectedItemColor: DarkColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: DarkColors.cyan,
        foregroundColor: DarkColors.bg,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: DarkColors.cyan,
        textColor: DarkColors.textPrimary,
        minLeadingWidth: 28,
        dense: true,
      ),

      iconTheme: const IconThemeData(color: DarkColors.cyan, size: 22),

      dialogTheme: DialogThemeData(
        backgroundColor: DarkColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          side: BorderSide(
            color: DarkColors.border.withValues(alpha: 0.5),
          ),
        ),
        titleTextStyle: const TextStyle(
          color: DarkColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: DarkColors.textSecondary,
          fontSize: 15,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: DarkColors.surface,
        modalBackgroundColor: DarkColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(
            color: DarkColors.border.withValues(alpha: 0.5),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DarkColors.cyan
              : DarkColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DarkColors.cyan.withValues(alpha: 0.3)
              : DarkColors.elevated,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : DarkColors.textMuted,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? DarkColors.cyan
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(DarkColors.bg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: const BorderSide(color: DarkColors.border, width: 1.5),
      ),
    );
  }
}
