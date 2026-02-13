/// BiblioGenius Theme Registry
///
/// Central registry for discovering and managing available themes.
/// Themes register themselves at app startup.

import 'package:flutter/material.dart';
import 'theme_interface.dart';
import '../default/default_theme.dart';
import '../minimal/minimal_theme.dart';
import '../dark/dark_theme.dart';

class ThemeRegistry {
  static final Map<String, AppTheme> _themes = {};
  static bool _initialized = false;

  /// Initialize all built-in themes
  static void initialize() {
    if (_initialized) return;

    register(DefaultTheme());
    register(MinimalTheme());
    register(DarkTheme());

    _initialized = true;
    debugPrint('ThemeRegistry: Initialized with ${_themes.length} themes');
  }

  /// Register a theme
  static void register(AppTheme theme) {
    _themes[theme.id] = theme;
    debugPrint('ThemeRegistry: Registered theme "${theme.id}"');
  }

  /// Get a theme by ID
  static AppTheme? get(String id) => _themes[id];

  /// Get all available themes
  static List<AppTheme> get all => _themes.values.toList();

  /// Get the default theme (fallback)
  static AppTheme get defaultTheme {
    if (!_initialized) initialize();
    return _themes['default'] ?? _themes.values.first;
  }

  /// Get theme IDs for dropdowns/selectors
  static List<String> get availableIds => _themes.keys.toList();

  /// Check if a theme exists
  static bool exists(String id) => _themes.containsKey(id);
}
