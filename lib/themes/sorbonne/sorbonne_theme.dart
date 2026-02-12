// BiblioGenius Sorbonne Theme
//
// Immersive "Old Library" ambiance inspired by Sorbonne and Salamanca
// university libraries. Optimized for low-end smartphones.
//
// Design principles:
// - Warm wood and leather tones (Dark Mode)
// - Parchment-style text and accents
// - Subtle 3D effects using shadows and gradients (no heavy GPU operations)
// - Serif typography for classic feel

import 'package:flutter/material.dart';
import '../base/theme_interface.dart';

/// The Sorbonne theme definition

/// Color palette for Sorbonne theme (Deep Vintage Library)
class SorbonneColors {
  SorbonneColors._();

  // Wood tones (Very Dark Base - slightly lightened for visibility)
  static const darkWood = Color(0xFF1A110D); // Dark wood (was 0xFF0D0705)
  static const warmWood = Color(0xFF1A0F0A); // Dark mahogany
  static const leather = Color(0xFF2D1810); // Rich leather brown
  static const lighterWood = Color(0xFF3D2314); // Medium wood highlight

  // Amber/Bronze text and accents (NO LIGHT COLORS)
  static const warmAmber = Color(0xFFC4A35A); // Warm amber (primary text)
  static const burnishedBronze = Color(0xFF8B6914); // Bronze (secondary)
  static const antiqueGold = Color(0xFFB8860B); // Dark goldenrod
  static const copperGlow = Color(0xFF8B4513); // Saddle brown/copper

  // Accent colors
  static const goldLeaf = Color(0xFFAA8C2C); // Muted gold leaf
  static const waxRed = Color(0xFF6B1111); // Deep wax red
  static const deepGreen = Color(0xFF0D2616); // Very dark green

  // Lighting effects
  static const candleGlow = Color(0xFFCC8844); // Warm candle orange
  static const lampBrass = Color(0xFF8B7355); // Brass lamp color
  static const shadowDeep = Color(0xFF000000); // Pure black

  // Legacy aliases for compatibility
  static const parchment = warmAmber;
  static const agedPaper = burnishedBronze;
  static const softGold = antiqueGold;
  static const dullGold = copperGlow;
}

class SorbonneTheme extends AppTheme {
  @override
  String get id => 'sorbonne';

  @override
  String get displayName => 'Sorbonne';

  @override
  String get description =>
      'Immersive "Old Library" ambiance (inspired from Sorbonne and Salamanca university libraries)';

  @override
  Color get previewColor => SorbonneColors.warmAmber;

  @override
  Color get previewSecondaryColor => SorbonneColors.warmWood;

  @override
  String? get previewAsset => 'assets/themes/sorbonne_preview.webp';

  @override
  ThemeWidgets? get customWidgets => ThemeWidgets(
    shelfDecoration: _shelfDecoration,
    cardDecoration: _darkLeatherCardDecoration,
    backgroundDecoration: _backgroundDecoration,
    lightOverlay: _candleLightOverlay,
  );

  /// Wood shelf decoration with 3D-like effect (Darker)
  static BoxDecoration get _shelfDecoration => BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        SorbonneColors.lighterWood,
        SorbonneColors.warmWood,
        SorbonneColors.darkWood,
      ],
      stops: [0.0, 0.4, 1.0],
    ),
    boxShadow: [
      BoxShadow(
        color: SorbonneColors.shadowDeep.withValues(alpha: 0.8),
        offset: const Offset(0, 4),
        blurRadius: 8,
      ),
    ],
  );

  /// Dark Leather/Wood card decoration
  static BoxDecoration get _darkLeatherCardDecoration => BoxDecoration(
    color: SorbonneColors.warmWood,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(
      color: SorbonneColors.agedPaper.withValues(alpha: 0.3),
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: SorbonneColors.shadowDeep.withValues(alpha: 0.5),
        offset: const Offset(2, 3),
        blurRadius: 6,
      ),
    ],
  );

  /// Background decoration with dark wood gradient
  static BoxDecoration get _backgroundDecoration => const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [SorbonneColors.darkWood, SorbonneColors.warmWood],
    ),
  );

  /// Candle light overlay effect
  static BoxDecoration get _candleLightOverlay => BoxDecoration(
    gradient: RadialGradient(
      center: const Alignment(-0.7, -0.3),
      radius: 1.5,
      colors: [
        SorbonneColors.candleGlow.withValues(alpha: 0.1),
        Colors.transparent,
      ],
    ),
  );

  @override
  ThemeData buildTheme({Color? accentColor}) {
    return ThemeData(
      primaryColor: SorbonneColors.warmWood,
      useMaterial3: true,
      scaffoldBackgroundColor: SorbonneColors.darkWood, // Dark background
      fontFamily: 'Georgia', // System serif font for classic feel
      brightness: Brightness.dark, // Signals dark mode to widgets

      appBarTheme: AppBarTheme(
        backgroundColor: SorbonneColors.darkWood,
        foregroundColor: SorbonneColors.agedPaper,
        elevation: 0,
        shadowColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: SorbonneColors.softGold,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
          letterSpacing: 1.0,
        ),
        iconTheme: const IconThemeData(
          color: SorbonneColors.goldLeaf,
          size: 24,
        ),
        actionsIconTheme: const IconThemeData(
          color: SorbonneColors.goldLeaf,
          size: 24,
        ),
      ),

      colorScheme: ColorScheme.fromSeed(
        seedColor: SorbonneColors.warmWood,
        brightness: Brightness.dark,
        primary: SorbonneColors.goldLeaf, // Gold as primary accent
        secondary: SorbonneColors.waxRed,
        surface: SorbonneColors.warmWood, // Cards/Sheets are mahogany
        onPrimary: SorbonneColors.darkWood,
        onSecondary: SorbonneColors.parchment,
        onSurface: SorbonneColors.parchment,
        outline: SorbonneColors.agedPaper.withValues(alpha: 0.3),
      ),

      cardTheme: CardThemeData(
        color: SorbonneColors.warmWood, // Dark cards
        elevation: 4,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: SorbonneColors.agedPaper.withValues(alpha: 0.2),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.only(bottom: 16),
        shadowColor: SorbonneColors.shadowDeep.withValues(alpha: 0.5),
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: SorbonneColors.softGold,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          fontFamily: 'Georgia',
          letterSpacing: 0.5,
        ),
        displayMedium: TextStyle(
          color: SorbonneColors.softGold,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
        ),
        headlineLarge: TextStyle(
          color: SorbonneColors.parchment,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
        ),
        headlineMedium: TextStyle(
          color: SorbonneColors.parchment,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
        ),
        titleLarge: TextStyle(
          color: SorbonneColors.goldLeaf,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
        ),
        titleMedium: TextStyle(
          color: SorbonneColors.parchment,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
        ),
        titleSmall: TextStyle(
          color: SorbonneColors.warmAmber,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          fontFamily: 'Georgia',
        ),
        bodyLarge: TextStyle(
          color: SorbonneColors.parchment,
          fontSize: 16,
          height: 1.6,
          fontFamily: 'Georgia',
        ),
        bodyMedium: TextStyle(
          color: SorbonneColors.parchment,
          fontSize: 14,
          height: 1.5,
          fontFamily: 'Georgia',
        ),
        bodySmall: TextStyle(
          color: SorbonneColors.warmAmber,
          fontSize: 12,
          height: 1.4,
          fontFamily: 'Georgia',
        ),
        labelLarge: TextStyle(
          color: SorbonneColors.softGold,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
        ),
        labelMedium: TextStyle(
          color: SorbonneColors.warmAmber,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamily: 'Georgia',
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SorbonneColors.leather,
          foregroundColor: SorbonneColors.softGold,
          elevation: 4,
          shadowColor: SorbonneColors.shadowDeep.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: SorbonneColors.agedPaper.withValues(alpha: 0.3),
            ),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            fontFamily: 'Georgia',
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SorbonneColors.goldLeaf,
          side: BorderSide(
            color: SorbonneColors.agedPaper.withValues(alpha: 0.5),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor:
              SorbonneColors.goldLeaf, // Changed from waxRed for visibility
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Georgia',
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SorbonneColors.leather.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: SorbonneColors.agedPaper.withValues(alpha: 0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: SorbonneColors.agedPaper.withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: SorbonneColors.goldLeaf,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        // Use simpler TextStyle with inherit: true (default)
        hintStyle: TextStyle(
          color: SorbonneColors.parchment.withValues(alpha: 0.5),
          fontStyle: FontStyle.italic,
        ),
        labelStyle: const TextStyle(color: SorbonneColors.warmAmber),
        floatingLabelStyle: const TextStyle(color: SorbonneColors.goldLeaf),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),

      dividerTheme: DividerThemeData(
        color: SorbonneColors.agedPaper.withValues(alpha: 0.2),
        thickness: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: SorbonneColors.leather,
        side: BorderSide(
          color: SorbonneColors.agedPaper.withValues(alpha: 0.3),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: const TextStyle(
          color: SorbonneColors.parchment,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontFamily: 'Georgia',
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: SorbonneColors.darkWood,
        selectedItemColor: SorbonneColors.softGold,
        unselectedItemColor: SorbonneColors.warmAmber.withValues(alpha: 0.6),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          fontFamily: 'Georgia',
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontFamily: 'Georgia',
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: SorbonneColors.leather,
        foregroundColor: SorbonneColors.softGold,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: SorbonneColors.goldLeaf.withValues(alpha: 0.3),
          ),
        ),
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        iconColor: SorbonneColors.goldLeaf,
        textColor: SorbonneColors.parchment,
        minLeadingWidth: 32,
      ),

      iconTheme: const IconThemeData(color: SorbonneColors.goldLeaf, size: 24),

      dialogTheme: const DialogThemeData(
        backgroundColor: SorbonneColors.warmWood,
        elevation: 16,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: SorbonneColors.goldLeaf, width: 2),
        ),
        titleTextStyle: TextStyle(
          color: SorbonneColors.softGold,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          fontFamily: 'Georgia',
        ),
        contentTextStyle: TextStyle(
          color: SorbonneColors.parchment,
          fontSize: 16,
          fontFamily: 'Georgia',
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: SorbonneColors.warmWood,
        modalBackgroundColor: SorbonneColors.warmWood,
        elevation: 16,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: SorbonneColors.goldLeaf, width: 1),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SorbonneColors.softGold
              : SorbonneColors.warmAmber,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SorbonneColors.leather
              : SorbonneColors.darkWood,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : SorbonneColors.lampBrass, // Brass border for OFF state
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? SorbonneColors.goldLeaf
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(SorbonneColors.darkWood),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: BorderSide(
          color: SorbonneColors.agedPaper.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
    );
  }
}
