import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider with ChangeNotifier {
  Color _bannerColor = Colors.blue;
  bool _isSetupComplete = false;

  Color get bannerColor => _bannerColor;
  bool get isSetupComplete => _isSetupComplete;
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  ThemeData get themeData {
    final brightness = ThemeData.estimateBrightnessForColor(_bannerColor);
    final foregroundColor = brightness == Brightness.dark ? Colors.white : Colors.black;

    return ThemeData(
      primarySwatch: Colors.blue,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: _bannerColor,
        foregroundColor: foregroundColor,
      ),
      colorScheme: ColorScheme.fromSeed(seedColor: _bannerColor),
    );
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('bannerColor');
    if (colorValue != null) {
      _bannerColor = Color(colorValue);
    }
    _isSetupComplete = prefs.getBool('isSetupComplete') ?? false;
    
    final languageCode = prefs.getString('languageCode');
    if (languageCode != null) {
      _locale = Locale(languageCode);
    }

    // If local pref is false, check with backend (in case it's a new device/browser)
    if (!_isSetupComplete) {
      try {
        // We need ApiService here, but it's not injected. 
        // We'll rely on the caller to check or pass it, or we can't do it here easily without refactoring.
        // Actually, let's just default to false here, and let the UI handle the check.
        // Better yet, let's allow passing an optional checker callback or similar.
        // For now, let's leave it as is and fix it in main.dart or a splash screen.
      } catch (e) {
        // ignore
      }
    }
    notifyListeners();
  }

  Future<void> setBannerColor(Color color) async {
    _bannerColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('bannerColor', color.value);
    notifyListeners();
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
    notifyListeners();
  }

  Future<void> completeSetup() async {
    _isSetupComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isSetupComplete', true);
    notifyListeners();
  }

  Future<void> resetSetup() async {
    _isSetupComplete = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isSetupComplete');
    // Optional: Reset color/lang too?
    // await prefs.remove('bannerColor');
    // await prefs.remove('languageCode');
    notifyListeners();
  }
}
