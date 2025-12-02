import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/avatars.dart';
import '../models/avatar_config.dart';
import '../services/api_service.dart';

class ThemeProvider with ChangeNotifier {
  Color _bannerColor = Colors.blue;
  bool _isSetupComplete = false;

  Color get bannerColor => _bannerColor;
  bool get isSetupComplete => _isSetupComplete;
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  String _themeStyle = 'default';
  String get themeStyle => _themeStyle;

  String _currentAvatarId = 'individual';
  String get currentAvatarId => _currentAvatarId;
  
  AvatarConfig? _avatarConfig;
  AvatarConfig? get avatarConfig => _avatarConfig;
  
  // Profile type: 'librarian', 'individual', or 'kid'
  String _profileType = 'individual';
  String get profileType => _profileType;
  bool get isLibrarian => _profileType == 'librarian' || _profileType == 'professional';
  bool get isKid => _profileType == 'kid';
  bool get hasReadingStatus => _profileType == 'individual' || _profileType == 'kid';

  ThemeData get themeData {
    final brightness = ThemeData.estimateBrightnessForColor(_bannerColor);
    final foregroundColor = brightness == Brightness.dark ? Colors.white : Colors.black;

    if (_themeStyle == 'minimal') {
      // POC Theme Colors
      const bgBody = Color(0xFFFDFBF7); // Warm cream
      const bgCard = Colors.white;
      const textMain = Color(0xFF44403C); // Stone 700
      const textMuted = Color(0xFF78716C); // Stone 500
      const border = Color(0xFFE7E5E4); // Stone 200
      final primary = _bannerColor; // Use user-selected color

      return ThemeData(
        primaryColor: primary,
        useMaterial3: true,
        scaffoldBackgroundColor: bgBody,
        fontFamily: 'Inter', // Will fallback if not available
        appBarTheme: const AppBarTheme(
          backgroundColor: bgBody,
          foregroundColor: textMain,
          elevation: 0,
          iconTheme: IconThemeData(color: textMain),
          titleTextStyle: TextStyle(
            color: textMain,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          background: bgBody,
          surface: bgCard,
          onBackground: textMain,
          onSurface: textMain,
          outline: border,
        ),
        cardTheme: CardThemeData(
          color: bgCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 16),
        ),
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: textMain),
          bodyMedium: TextStyle(color: textMain),
          titleLarge: TextStyle(
            color: textMain,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          titleMedium: TextStyle(
            color: textMain,
            fontWeight: FontWeight.w700,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: bgCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      );
    }

    // Default Theme (Colorful but with POC aesthetics)
    // POC Theme Colors
    const bgBody = Color(0xFFFDFBF7); // Warm cream
    const bgCard = Colors.white;
    const textMain = Color(0xFF44403C); // Stone 700
    const border = Color(0xFFE7E5E4); // Stone 200

    return ThemeData(
      primaryColor: _bannerColor,
      useMaterial3: true,
      scaffoldBackgroundColor: bgBody,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        backgroundColor: _bannerColor,
        foregroundColor: foregroundColor,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: foregroundColor,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: _bannerColor,
        primary: _bannerColor,
        background: bgBody,
        surface: bgCard,
        onBackground: textMain,
        onSurface: textMain,
        outline: border,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.only(bottom: 16),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textMain),
        bodyMedium: TextStyle(color: textMain),
        titleLarge: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleMedium: TextStyle(
          color: textMain,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _bannerColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _bannerColor, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('bannerColor');
    if (colorValue != null) {
      _bannerColor = Color(colorValue);
    }
    _isSetupComplete = prefs.getBool('isSetupComplete') ?? false;
    _themeStyle = prefs.getString('themeStyle') ?? 'default';
    
    final languageCode = prefs.getString('languageCode');
    if (languageCode != null) {
      _locale = Locale(languageCode);
    }
    
    _currentAvatarId = prefs.getString('avatarId') ?? 'individual';
    _profileType = prefs.getString('profileType') ?? 'individual';
    
    final avatarConfigJson = prefs.getString('avatarConfig');
    if (avatarConfigJson != null) {
      try {
        _avatarConfig = AvatarConfig.fromJson(jsonDecode(avatarConfigJson));
      } catch (e) {
        debugPrint('Error loading avatar config: $e');
      }
    } else {
      _avatarConfig = AvatarConfig.defaultConfig;
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

  Future<void> setThemeStyle(String style) async {
    _themeStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeStyle', style);
    notifyListeners();
  }

  Future<void> setProfileType(String type, {ApiService? apiService}) async {
    _profileType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profileType', type);
    notifyListeners();
    
    if (apiService != null) {
      try {
        await apiService.updateProfile(profileType: type, avatarConfig: _avatarConfig?.toJson());
      } catch (e) {
        debugPrint('Error syncing profile type: $e');
      }
    }
  }
  
  Future<void> setAvatarConfig(AvatarConfig config, {ApiService? apiService}) async {
    _avatarConfig = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatarConfig', jsonEncode(config.toJson()));
    notifyListeners();
    
    if (apiService != null) {
      try {
        await apiService.updateProfile(profileType: _profileType, avatarConfig: config.toJson());
      } catch (e) {
        debugPrint('Error syncing avatar config: $e');
      }
    }
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
    notifyListeners();
  }

  Future<void> setAvatarId(String avatarId) async {
    _currentAvatarId = avatarId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatarId', avatarId);
    
    // Auto-set theme color based on avatar
    final avatar = availableAvatars.firstWhere(
      (a) => a.id == avatarId, 
      orElse: () => availableAvatars.first
    );
    await setBannerColor(avatar.themeColor);

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
