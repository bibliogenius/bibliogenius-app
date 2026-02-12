/// BiblioGenius Theme System - Base Interface
///
/// Defines the contract for all themes in the modular theme architecture.
/// Inspired by Drupal's theme system.

import 'package:flutter/material.dart';

/// Base interface for all BiblioGenius themes
abstract class AppTheme {
  /// Unique identifier for the theme (e.g., 'sorbonne', 'minimal')
  String get id;

  /// Displayed name in theme selector
  String get displayName;

  /// Short description of the theme
  String get description;

  /// Primary color for preview in theme selector
  Color get previewColor;

  /// Secondary color for two-tone preview (defaults to previewColor)
  Color get previewSecondaryColor => previewColor;

  /// Optional asset path for theme preview image
  String? get previewAsset => null;

  /// Whether this theme supports dark mode
  bool get supportsDarkMode => false;

  /// Build the ThemeData for this theme
  ///
  /// [accentColor] - Optional accent color override from user preferences
  ThemeData buildTheme({Color? accentColor});

  /// Build the dark mode ThemeData (if supported)
  ///
  /// Returns null if dark mode is not supported
  ThemeData? buildDarkTheme({Color? accentColor}) => null;

  /// Optional custom widgets/decorations specific to this theme
  ///
  /// Themes like "Sorbonne" can provide custom shelf widgets, card styles, etc.
  ThemeWidgets? get customWidgets => null;
}

/// Container for custom theme-specific widget builders
class ThemeWidgets {
  /// Custom shelf decoration (for bookshelf-style themes)
  final BoxDecoration? shelfDecoration;

  /// Custom card decoration
  final BoxDecoration? cardDecoration;

  /// Custom background decoration (for immersive themes)
  final BoxDecoration? backgroundDecoration;

  /// Light overlay decoration (e.g., candle glow for Sorbonne)
  final BoxDecoration? lightOverlay;

  const ThemeWidgets({
    this.shelfDecoration,
    this.cardDecoration,
    this.backgroundDecoration,
    this.lightOverlay,
  });
}
