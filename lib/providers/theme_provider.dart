import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/avatars.dart';
import '../models/avatar_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/mdns_service.dart';
import '../themes/base/theme_registry.dart';

class ThemeProvider with ChangeNotifier {
  Color _bannerColor = Colors.blue;
  bool _isSetupComplete = false;

  Color get bannerColor => _bannerColor;
  bool get isSetupComplete => _isSetupComplete;
  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  String _themeStyle = 'default';
  String get themeStyle => _themeStyle;

  double _textScaleFactor = 1.0;
  double get textScaleFactor => _textScaleFactor;

  String _currentAvatarId = 'individual';
  String get currentAvatarId => _currentAvatarId;

  AvatarConfig? _avatarConfig;
  AvatarConfig? get avatarConfig => _avatarConfig;

  // Currency
  // Currency
  String _currency = 'EUR';
  String get currency => _currency;

  // Username
  String _username = 'Lecteur';
  String get username => _username;

  // Profile type: kept for backend compatibility, but no longer used for UI decisions
  String _profileType = 'individual';
  String get profileType => _profileType;

  // Simplified mode: replaces the old 'kid' profile type
  // When enabled, shows a simplified UI for young readers
  bool _simplifiedMode = false;
  bool get simplifiedMode => _simplifiedMode;

  // Computed getters - now based on modules, not profile type
  bool get isLibrarian =>
      _profileType == 'librarian' || _profileType == 'professional';
  bool get isBookseller => _commerceEnabled; // Now based on commerce module
  bool get isKid => _simplifiedMode; // Now based on simplified mode toggle
  bool get hasReadingStatus => !_commerceEnabled; // Readers have reading status

  // Commerce module (bookseller features: pricing, sales, inventory)
  bool _commerceEnabled = false;
  bool get commerceEnabled => _commerceEnabled;
  bool get hasCommerce => _commerceEnabled; // Commerce module (pricing) active
  bool get hasSales => _commerceEnabled; // Sales/transactions module active

  // Network Discovery (mDNS): allows user to disable local network visibility
  // Disabled by default for privacy (opt-in)
  bool _networkDiscoveryEnabled = false;
  bool get networkDiscoveryEnabled => _networkDiscoveryEnabled;
  bool get hasLoans =>
      !_commerceEnabled; // Loans disabled when commerce is enabled

  // Borrowing capability: disabled by default for librarians (they lend, not borrow)
  // Also disabled for booksellers (they sell, not borrow)
  bool _canBorrowBooks = true;
  bool get canBorrowBooks => _canBorrowBooks;

  // Gamification: disabled by default for librarians and booksellers
  bool _gamificationEnabled = true;
  bool get gamificationEnabled => _gamificationEnabled;

  // Edition Browser: allows grouping search results by work with swipeable editions
  bool _editionBrowserEnabled = true;
  bool get editionBrowserEnabled => _editionBrowserEnabled;

  // Digital Formats Module
  bool _digitalFormatsEnabled = false;
  bool get digitalFormatsEnabled => _digitalFormatsEnabled;

  // Audio Module
  bool _audioEnabled = false;
  bool get audioEnabled => _audioEnabled;

  // MCP Integration
  bool _mcpEnabled = false;
  bool get mcpEnabled => _mcpEnabled;

  // Network Module (Alias for network discovery for UI consistency)
  bool get networkEnabled => _networkDiscoveryEnabled;

  // Peer Offline Caching: allows viewing cached peer libraries when they're offline
  // Disabled by default for privacy (peer's books are cached locally)
  bool _peerOfflineCachingEnabled = false;
  bool get peerOfflineCachingEnabled => _peerOfflineCachingEnabled;

  // Allow Library Caching: allows others to cache YOUR library for offline viewing
  // Disabled by default for privacy (your book list stored on others' devices)
  bool _allowLibraryCaching = false;
  bool get allowLibraryCaching => _allowLibraryCaching;

  // Connection Validation: require approval before new peers can access library
  // Disabled by default (open access)
  bool _connectionValidationEnabled = false;
  bool get connectionValidationEnabled => _connectionValidationEnabled;

  // Network Gamification: compare progress with connected peers
  // Disabled by default (opt-in)
  bool _networkGamificationEnabled = false;
  bool get networkGamificationEnabled => _networkGamificationEnabled;

  // Share Gamification Stats: allow peers to see your gamification progress
  // Disabled by default for privacy
  bool _shareGamificationStats = false;
  bool get shareGamificationStats => _shareGamificationStats;

  ThemeData get themeData {
    // Initialize registry if needed
    ThemeRegistry.initialize();

    // Get theme from registry, fallback to default
    final theme = ThemeRegistry.get(_themeStyle) ?? ThemeRegistry.defaultTheme;
    return theme.buildTheme(accentColor: _bannerColor);
  }

  /// Normalize profile type values to handle legacy formats
  /// Maps old values like 'individual_reader' to current valid values
  String _normalizeProfileType(String profileType) {
    // Map old/legacy values to new values
    const Map<String, String> legacyMapping = {
      'individual_reader': 'individual',
      'professional': 'librarian',
    };

    // Check if it's a legacy value that needs mapping
    if (legacyMapping.containsKey(profileType)) {
      return legacyMapping[profileType]!;
    }

    // Validate it's a known current value
    const validTypes = {'individual', 'librarian', 'kid', 'bookseller'};
    if (validTypes.contains(profileType)) {
      return profileType;
    }

    // Default fallback if unknown value
    debugPrint(
      '⚠️ Unknown profile type: $profileType, defaulting to individual',
    );
    return 'individual';
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('bannerColor');
    if (colorValue != null) {
      _bannerColor = Color(colorValue);
    }
    _isSetupComplete = prefs.getBool('isSetupComplete') ?? false;
    _themeStyle = prefs.getString('themeStyle') ?? 'default';
    _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.0;

    // Load username
    String? storedUsername = prefs.getString('username');
    if (storedUsername == null) {
      // Try fallback from AuthService if not in Prefs
      storedUsername = await AuthService().getUsername();
    }

    // Default to 'Lecteur' if missing or 'offline_user'
    if (storedUsername == null || storedUsername == 'offline_user') {
      _username = 'Lecteur';
    } else {
      _username = storedUsername;
    }

    final languageCode = prefs.getString('languageCode');
    if (languageCode != null) {
      _locale = Locale(languageCode);
    } else {
      // Auto-detect system language on first launch
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final supportedLanguages = ['en', 'fr', 'es', 'de'];
      if (supportedLanguages.contains(systemLocale.languageCode)) {
        _locale = Locale(systemLocale.languageCode);
      } else {
        _locale = const Locale('en'); // Fallback to English
      }
    }

    _currentAvatarId = prefs.getString('avatarId') ?? 'individual';
    _currency = prefs.getString('currency') ?? 'EUR';

    // Load and normalize profile type to handle legacy values
    String rawProfileType = prefs.getString('profileType') ?? 'individual';
    _profileType = _normalizeProfileType(rawProfileType);

    // If normalized value differs from stored value, update SharedPreferences
    if (_profileType != rawProfileType) {
      await prefs.setString('profileType', _profileType);
      debugPrint(
        '✅ Migrated legacy profile type: $rawProfileType → $_profileType',
      );
    }

    // Load borrowing capability setting (default based on profile type)
    final savedCanBorrow = prefs.getBool('canBorrowBooks');
    if (savedCanBorrow != null) {
      _canBorrowBooks = savedCanBorrow;
    } else {
      // Default: disabled for librarians (they lend, not borrow), enabled for others
      // Default: disabled for librarians (they lend, not borrow), enabled for others
      _canBorrowBooks = !isLibrarian;
    }

    _commerceEnabled = prefs.getBool('commerceEnabled') ?? false;
    // Default to false (opt-in) for privacy
    _networkDiscoveryEnabled =
        prefs.getBool('networkDiscoveryEnabled') ?? false;
    // Default to false (opt-in) for privacy - caches peer's library locally
    _peerOfflineCachingEnabled =
        prefs.getBool('peerOfflineCachingEnabled') ?? false;
    _allowLibraryCaching = prefs.getBool('allowLibraryCaching') ?? false;
    _connectionValidationEnabled =
        prefs.getBool('connectionValidationEnabled') ?? false;
    _networkGamificationEnabled =
        prefs.getBool('networkGamificationEnabled') ?? false;
    _shareGamificationStats =
        prefs.getBool('shareGamificationStats') ?? false;
    _collectionsEnabled = prefs.getBool('collectionsEnabled') ?? false;
    _quotesEnabled = prefs.getBool('quotesEnabled') ?? true;
    _editionBrowserEnabled = prefs.getBool('editionBrowserEnabled') ?? true;
    _digitalFormatsEnabled = prefs.getBool('digitalFormatsEnabled') ?? false;
    _audioEnabled = prefs.getBool('audioEnabled') ?? false;
    _mcpEnabled = prefs.getBool('mcpEnabled') ?? false;
    _simplifiedMode = prefs.getBool('simplifiedMode') ?? false;

    // Load gamification setting (default based on profile type)
    final savedGamification = prefs.getBool('gamificationEnabled');
    if (savedGamification != null) {
      _gamificationEnabled = savedGamification;
    } else {
      // Default: disabled for librarians, enabled for others
      _gamificationEnabled = !isLibrarian;
    }

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

    _libraryName = prefs.getString('libraryName') ?? 'My Library';

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

  Future<void> setUsername(String name, {ApiService? apiService}) async {
    if (_username == name) return;
    _username = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', name);
    notifyListeners();

    // Persist to AuthService for security/auth purposes
    try {
      await AuthService().saveUsername(name);
    } catch (e) {
      debugPrint('Error saving username to AuthService: $e');
    }

    if (apiService != null) {
      try {
        await apiService.updateProfile(data: {'username': name});
      } catch (e) {
        debugPrint('Error syncing username: $e');
      }
    }
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

  Future<void> setTextScaleFactor(double factor) async {
    _textScaleFactor = factor.clamp(0.85, 1.4);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('textScaleFactor', _textScaleFactor);
    notifyListeners();
  }

  Future<void> setCanBorrowBooks(bool enabled) async {
    _canBorrowBooks = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('canBorrowBooks', enabled);
    notifyListeners();
  }

  Future<void> setGamificationEnabled(bool enabled) async {
    _gamificationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gamificationEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setEditionBrowserEnabled(bool enabled) async {
    _editionBrowserEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('editionBrowserEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', currency);
    notifyListeners();
  }

  Future<void> setProfileType(String type, {ApiService? apiService}) async {
    final bool wasBookseller = _profileType == 'bookseller';
    _profileType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profileType', type);

    // Reset borrowing capability to profile-based default if not explicitly set
    final savedCanBorrow = prefs.getBool('canBorrowBooks');
    if (savedCanBorrow == null) {
      _canBorrowBooks = !isLibrarian;
    }

    // Auto-enable commerce module only if switching TO bookseller for the first time
    if (type == 'bookseller' && !wasBookseller) {
      _commerceEnabled = true;
      await prefs.setBool('commerceEnabled', true);
    }

    notifyListeners();

    if (apiService != null) {
      try {
        await apiService.updateProfile(
          data: {
            'profile_type': type,
            'avatar_config': _avatarConfig?.toJson(),
          },
        );
      } catch (e) {
        debugPrint('Error syncing profile type: $e');
      }
    }
  }

  Future<void> setAvatarConfig(
    AvatarConfig config, {
    ApiService? apiService,
  }) async {
    _avatarConfig = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('avatarConfig', jsonEncode(config.toJson()));
    notifyListeners();

    if (apiService != null) {
      try {
        await apiService.updateProfile(
          data: {
            'profile_type': _profileType,
            'avatar_config': config.toJson(),
          },
        );
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
      orElse: () => availableAvatars.first,
    );
    await setBannerColor(avatar.themeColor);

    notifyListeners();
  }

  /// Complete setup and apply all settings in one batch to avoid multiple rebuilds
  Future<void> completeSetupWithSettings({
    required String profileType,
    required AvatarConfig avatarConfig,
    required String libraryName,
    ApiService? apiService,
  }) async {
    // Apply all settings without notifying listeners individually
    _profileType = profileType;
    _avatarConfig = avatarConfig;
    _libraryName = libraryName;
    _isSetupComplete = true;

    // Auto-enable commerce module for bookseller profile
    if (profileType == 'bookseller') {
      _commerceEnabled = true;
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profileType', profileType);
    await prefs.setString('avatarConfig', jsonEncode(avatarConfig.toJson()));
    await prefs.setString('libraryName', libraryName);
    await prefs.setBool('isSetupComplete', true);
    // Save commerce enabled state for bookseller
    if (profileType == 'bookseller') {
      await prefs.setBool('commerceEnabled', true);
    }

    // Sync with backend if ApiService provided
    if (apiService != null) {
      try {
        await apiService.updateProfile(
          data: {
            'profile_type': profileType,
            'avatar_config': avatarConfig.toJson(),
          },
        );
      } catch (e) {
        debugPrint('Error syncing profile during setup: $e');
      }
    }

    // Single notification at the end
    notifyListeners();
  }

  Future<void> completeSetup() async {
    _isSetupComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isSetupComplete', true);
    notifyListeners();
  }

  /// Initialize defaults for first launch (skip setup wizard).
  /// Call this once during app startup if setup is not complete.
  Future<void> initializeDefaults() async {
    if (_isSetupComplete) return; // Already setup

    final prefs = await SharedPreferences.getInstance();

    // Auto-detect language from device
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    final supportedLanguages = ['en', 'fr', 'es', 'de'];
    if (supportedLanguages.contains(systemLocale.languageCode)) {
      _locale = Locale(systemLocale.languageCode);
      await prefs.setString('languageCode', systemLocale.languageCode);
    } else {
      _locale = const Locale('en');
      await prefs.setString('languageCode', 'en');
    }

    // Set sensible defaults
    _libraryName = 'My Library';
    await prefs.setString('libraryName', _libraryName);

    _profileType = 'individual';
    await prefs.setString('profileType', _profileType);

    _avatarConfig = AvatarConfig.defaultConfig;
    await prefs.setString('avatarConfig', jsonEncode(_avatarConfig!.toJson()));

    // Mark setup as complete
    _isSetupComplete = true;
    await prefs.setBool('isSetupComplete', true);

    debugPrint('✅ ThemeProvider: Initialized defaults (setup skipped)');
    notifyListeners();
  }

  Future<void> resetSetup() async {
    _isSetupComplete = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('isSetupComplete');
    resetSetupState();
    notifyListeners();
  }

  // Library Name
  String _libraryName = 'My Library';
  String get libraryName => _libraryName;

  Future<void> setLibraryName(String name, {ApiService? apiService}) async {
    if (_libraryName == name) return;
    _libraryName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('libraryName', name);
    notifyListeners();

    // Sync with backend if ApiService provided
    if (apiService != null) {
      try {
        // We only update the name here, keeping other fields as is usually requires fetching them first
        // But for this simplified call, we assume the caller handles full update or we just update local state
        // In this architecture, usually screens call API then update Provider.
        // We'll leave the API call to the caller (ProfileScreen/Dashboard) for now to avoid circular dependencies or incomplete data updates.
      } catch (e) {
        debugPrint('Error syncing library name: $e');
      }
    }
  }

  // Setup Wizard State
  int _setupStep = 0;
  int get setupStep => _setupStep;
  String _setupLibraryName = '';
  String get setupLibraryName => _setupLibraryName;
  String _setupProfileType = 'individual';
  String get setupProfileType => _setupProfileType;
  AvatarConfig _setupAvatarConfig = AvatarConfig.defaultConfig;
  AvatarConfig get setupAvatarConfig => _setupAvatarConfig;
  bool _setupImportDemo = false;
  bool get setupImportDemo => _setupImportDemo;

  void setSetupStep(int step) {
    _setupStep = step;
    notifyListeners();
  }

  void setSetupLibraryName(String name) {
    _setupLibraryName = name;
    notifyListeners();
  }

  void setSetupProfileType(String type) {
    _setupProfileType = type;
    notifyListeners();
  }

  void setSetupAvatarConfig(AvatarConfig config) {
    _setupAvatarConfig = config;
    notifyListeners();
  }

  void setSetupImportDemo(bool import) {
    _setupImportDemo = import;
    notifyListeners();
  }

  void resetSetupState() {
    _setupStep = 0;
    _setupLibraryName = '';
    _setupProfileType = 'individual';
    _setupAvatarConfig = AvatarConfig.defaultConfig;
    _setupImportDemo = false;
    notifyListeners();
  }

  Future<void> setCommerceEnabled(bool enabled) async {
    _commerceEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('commerceEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setSimplifiedMode(bool enabled) async {
    _simplifiedMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('simplifiedMode', enabled);
    notifyListeners();
  }

  /// Apply a preset configuration that enables/disables multiple modules at once
  Future<void> applyPreset(String presetName) async {
    switch (presetName) {
      case 'reader':
        // Reader preset: gamification, quotes, collections, audio
        await setGamificationEnabled(true);
        await setQuotesEnabled(true);
        await setCollectionsEnabled(true);
        await setAudioEnabled(true);
        await setCommerceEnabled(false);
        break;
      case 'librarian':
        // Librarian preset: collections, network, no gamification
        await setGamificationEnabled(false);
        await setQuotesEnabled(false);
        await setCollectionsEnabled(true);
        await setNetworkEnabled(true);
        await setCommerceEnabled(false);
        break;
      case 'bookseller':
        // Bookseller preset: commerce, collections, no gamification
        await setCommerceEnabled(true);
        await setCollectionsEnabled(true);
        await setGamificationEnabled(false);
        await setQuotesEnabled(false);
        await setAudioEnabled(false);
        break;
    }
    notifyListeners();
  }

  Future<void> setNetworkDiscoveryEnabled(
    bool enabled, {
    String? libraryId,
    int? port,
  }) async {
    _networkDiscoveryEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('networkDiscoveryEnabled', enabled);
    notifyListeners();

    if (enabled) {
      if (libraryId != null && port != null) {
        try {
          await MdnsService.startAnnouncing(
            _libraryName.isNotEmpty ? _libraryName : 'BiblioGenius Library',
            port,
            libraryId: libraryId,
          );
          await MdnsService.startDiscovery();
        } catch (e) {
          debugPrint('Error starting mDNS from settings: $e');
        }
      } else {
        debugPrint(
          'Cannot start mDNS: libraryId or port missing in setNetworkDiscoveryEnabled',
        );
      }
    } else {
      try {
        await MdnsService.stop();
      } catch (e) {
        debugPrint('Error stopping mDNS: $e');
      }
    }
  }

  /// Enable/disable peer offline caching
  /// When enabled, peer library catalogs are cached locally for offline viewing
  /// Privacy note: This stores the peer's book list on the user's device
  Future<void> setPeerOfflineCachingEnabled(bool enabled) async {
    _peerOfflineCachingEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('peerOfflineCachingEnabled', enabled);
    notifyListeners();
  }

  /// Enable/disable others caching your library
  /// When enabled, your library catalog can be cached by your peers
  /// Privacy note: This allows your book list to be stored on your peers' devices
  Future<void> setAllowLibraryCaching(bool enabled) async {
    _allowLibraryCaching = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allowLibraryCaching', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  /// Enable/disable connection validation
  /// When enabled, new peers must be approved before they can access your library
  /// When toggled OFF, all pending peers are auto-approved
  Future<void> setConnectionValidationEnabled(bool enabled) async {
    _connectionValidationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('connectionValidationEnabled', enabled);
    await _updateEnabledModules();
    if (!enabled) {
      // Auto-approve all pending peers when disabling validation
      try {
        final apiService = ApiService(AuthService());
        await apiService.autoApproveAllPeers();
      } catch (e) {
        debugPrint('Error auto-approving peers: $e');
      }
    }
    notifyListeners();
  }

  /// Enable/disable network gamification leaderboard
  Future<void> setNetworkGamificationEnabled(bool enabled) async {
    _networkGamificationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('networkGamificationEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  /// Enable/disable sharing gamification stats with peers
  Future<void> setShareGamificationStats(bool enabled) async {
    _shareGamificationStats = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shareGamificationStats', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  // Collections Module
  bool _collectionsEnabled = false;
  bool get collectionsEnabled => _collectionsEnabled;

  Future<void> setCollectionsEnabled(bool enabled) async {
    _collectionsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('collectionsEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  // Daily Quotes Module
  bool _quotesEnabled = true;
  bool get quotesEnabled => _quotesEnabled;

  Future<void> setQuotesEnabled(bool enabled) async {
    _quotesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quotesEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setDigitalFormatsEnabled(bool enabled) async {
    _digitalFormatsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('digitalFormatsEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setAudioEnabled(bool enabled) async {
    _audioEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('audioEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setMcpEnabled(bool enabled) async {
    _mcpEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mcpEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  // Alias for UI consistency - fetches required parameters for mDNS
  Future<void> setNetworkEnabled(bool enabled) async {
    if (enabled) {
      // Fetch libraryId required for mDNS announcing
      try {
        final authService = AuthService();
        final libraryUuid = await authService.getOrCreateLibraryUuid();
        await setNetworkDiscoveryEnabled(
          enabled,
          libraryId: libraryUuid,
          port: ApiService.httpPort,
        );
      } catch (e) {
        debugPrint('Error enabling network module: $e');
        // Still save the preference so UI stays in sync
        await setNetworkDiscoveryEnabled(enabled);
      }
    } else {
      // Disabling doesn't need parameters
      await setNetworkDiscoveryEnabled(enabled);
    }
    await _updateEnabledModules();
  }

  /// Collects all module states and syncs with the backend
  Future<void> _updateEnabledModules() async {
    final apiService = ApiService(AuthService());
    final List<String> enabledModules = [];

    if (networkEnabled) enabledModules.add('network');
    if (gamificationEnabled) enabledModules.add('gamification');
    if (collectionsEnabled) enabledModules.add('collections');
    if (quotesEnabled) enabledModules.add('quotes');
    if (editionBrowserEnabled) enabledModules.add('edition_browser');
    if (digitalFormatsEnabled) enabledModules.add('digital_formats');
    if (audioEnabled) enabledModules.add('audio');
    if (mcpEnabled) enabledModules.add('mcp');
    if (peerOfflineCachingEnabled) enabledModules.add('peer_offline_caching');
    if (allowLibraryCaching) enabledModules.add('allow_library_caching');
    if (connectionValidationEnabled) {
      enabledModules.add('connection_validation');
    }
    if (commerceEnabled) enabledModules.add('commerce');
    if (networkGamificationEnabled) {
      enabledModules.add('network_gamification');
    }
    if (shareGamificationStats) {
      enabledModules.add('share_gamification_stats');
    }

    try {
      await apiService.updateProfile(data: {'enabled_modules': enabledModules});
      debugPrint('✅ Synced enabled modules: $enabledModules');
    } catch (e) {
      debugPrint('Error syncing enabled modules: $e');
    }
  }
}
