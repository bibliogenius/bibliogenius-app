/// BiblioGenius Default Theme
///
/// The classic BiblioGenius look: warm, inviting with customizable accent color.
/// Features a green sidebar for an organic, library-inspired feel.

import 'package:flutter/material.dart';

import '../../utils/accessible_color.dart';
import '../base/theme_interface.dart';

class DefaultTheme extends AppTheme {
  @override
  String get id => 'default';

  @override
  String get displayName => 'BiblioGenius Classic';

  @override
  String get description => 'Warm, inviting design with organic green sidebar';

  @override
  Color get previewColor => const Color(0xFF4CAF50); // Green preview

  // Theme color constants
  static const _tealLight = Color(
    0xFF3D8B83,
  ); // Accessible teal (>= 4.5:1 on white)
  static const _tealDark = Color(
    0xFF3A7186,
  ); // Accessible dark teal (>= 5.0:1 on white)
  static const _headerBlue = Color(0xFF6366F1); // Keep blue for buttons

  @override
  ThemeData buildTheme({Color? accentColor}) {
    final bannerColor = accentColor ?? _headerBlue;
    // Which of black or white sits on the accent stays Flutter's call, so a
    // filled button keeps the look the reader knows. Flipping it by measured
    // ratio would have been more correct in the abstract and turned every
    // white icon on a mid-tone accent black, which is not a contrast fix
    // anyone asked for.
    final brightness = ThemeData.estimateBrightnessForColor(bannerColor);
    final foregroundColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    // POC Theme Colors
    const bgBody = Color(0xFFFDFBF7); // Warm cream
    const bgCard = Colors.white;
    const textMain = Color(0xFF44403C); // Stone 700
    const border = Color(0xFFE7E5E4); // Stone 200

    // The contrast is bought on the surface instead: deepen the accent just
    // enough that the foreground above already clears AA. Eight of the two
    // dozen avatar accents need it, the rest come back untouched.
    //
    // Every filled use takes this one value. Applying it to a single button
    // theme left `FilledButton`, which fills from `colorScheme.primary`, at
    // the ratio that started this, and put two shades of the accent on the
    // same screen next to the floating action button.
    final accentSurface = shiftUntilReadable(bannerColor, foregroundColor);

    final accentInk = inkOn(bgBody, bannerColor);
    // A border is a UI component, not text: WCAG asks 3:1 of it.
    final accentBorder = inkOn(bgCard, bannerColor, minimumRatio: 3);

    return ThemeData(
      primaryColor: accentSurface,
      useMaterial3: true,
      scaffoldBackgroundColor: bgBody,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor: _tealDark, // Use teal for app bar background fallback
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      // Sidebar: Reset background, set active indicator to Teal
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: null, // Reset to default (transparent/surface)
        selectedIconTheme: const IconThemeData(color: _tealDark, size: 24),
        unselectedIconTheme: const IconThemeData(
          color: Color(0xFF757575),
          size: 24,
        ), // Grey 600
        selectedLabelTextStyle: const TextStyle(
          color: _tealDark,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: Color(0xFF757575), // Grey 600 for better contrast
          fontWeight: FontWeight.w500,
          fontSize: 11,
        ),
        indicatorColor: _tealLight.withAlpha(
          50,
        ), // Semi-transparent teal for active item bg
        useIndicator: true,
      ),
      // FAB uses primary color (Blue), so no override needed or explicit blue
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentSurface,
        foregroundColor: foregroundColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: bannerColor,
        primary: accentSurface,
        // `FilledButton` and friends read this rather than any button theme.
        // Left to `fromSeed` it came back white on a pale accent, which is how
        // an amber button shipped its label at 1.6:1.
        onPrimary: foregroundColor,
        secondary: _tealLight, // Teal as secondary

        surface: bgCard,
        onSurface: textMain,
        outline: border,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(16),
        ),
        margin: const EdgeInsets.only(bottom: 16),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textMain, fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(color: textMain, fontSize: 14, height: 1.5),
        bodySmall: TextStyle(
          color: Color(
            0xFF696462,
          ), // Stone 600 - accessible on cream bg (>= 5.5:1)
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        titleLarge: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w800,
          fontSize: 22,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        labelLarge: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          letterSpacing: 0.3,
        ),
      ),
      // Both write with the accent rather than fill with it, so they take the
      // ink variant. Left to `colorScheme.primary` they would inherit the
      // value calibrated to carry a foreground, which lands just under the bar
      // when it becomes the foreground itself.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentInk),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: accentInk),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentSurface,
          foregroundColor: foregroundColor,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accentBorder, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        labelStyle: const TextStyle(color: textMain, fontSize: 14),
        floatingLabelStyle: TextStyle(
          color: accentInk,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      ),
      // Switch theme with better contrast for OFF state
      switchTheme: SwitchThemeData(
        // Switched on, the thumb used to take the accent and the track the
        // same accent at half opacity, leaving the thumb 2.0:1 against the
        // rail it slides on. Material fills the track and rides a light thumb
        // on it, which is also what makes the position readable at a glance.
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? foregroundColor
              : const Color(0xFFF5F5F5), // Very light grey instead of white
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accentSurface
              : const Color(0xFFE0E0E0), // Light grey track
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : const Color(0xFFBDBDBD), // Grey border for OFF state
        ),
      ),
    );
  }
}
