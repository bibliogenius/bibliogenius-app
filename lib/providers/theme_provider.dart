import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/library_portals.dart';
import '../utils/avatars.dart';
import '../widgets/peer_book_cover_cache_manager.dart';
import '../models/avatar_config.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/ffi_service.dart';
import '../services/mdns_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../services/translation_service.dart';
import '../themes/base/theme_registry.dart';
import '../utils/language_constants.dart';

class ThemeProvider with ChangeNotifier {
  Color _bannerColor = Colors.blue;
  bool _isSetupComplete = false;

  Color get bannerColor => _bannerColor;
  bool get isSetupComplete => _isSetupComplete;
  Locale _locale = const Locale('en');
  Locale get locale => _locale;
  String get localeTag => localeToTag(_locale);

  // User reading languages (multi-select, persisted as JSON in SharedPreferences)
  List<String> _userLanguages = [];
  List<String> get userLanguages => List.unmodifiable(_userLanguages);

  // Delegates to TranslationService.supportedLocales (single source of truth)
  static List<String> get supportedUILanguages =>
      TranslationService.supportedLocales;

  String _themeStyle = 'default';
  String get themeStyle => _themeStyle;

  double _textScaleFactor = 1.05;
  double get textScaleFactor => _textScaleFactor;

  String _currentAvatarId = 'individual';
  String get currentAvatarId => _currentAvatarId;

  AvatarConfig? _avatarConfig;
  AvatarConfig? get avatarConfig => _avatarConfig;

  // Country / market (ISO 3166-1 alpha-2, derived from device locale on first launch)
  String _country = '';
  String get country => _country;

  // Currency
  String _currency = 'EUR';
  String get currency => _currency;

  // Username
  String _username = 'Lecteur';
  String get username => _username;

  // Computed getters - all based on module toggles now (profileType removed).
  bool get isBookseller => _commerceEnabled;
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

  // Lending capability: disabled if the user does not want others to borrow
  // their books. Independent of canBorrowBooks (a librarian lends but does
  // not borrow; a pure reader may want to borrow without lending).
  bool _canLendBooks = true;
  bool get canLendBooks => _canLendBooks;

  // Independent-bookshop suggestions on wanted books' pages. The stored
  // key keeps the card's original "dismissed" polarity (cross = opt out).
  bool _showBookshopFinder = true;
  bool get showBookshopFinder => _showBookshopFinder;

  // Reader-picked bookshop portals (ordered registry ids); empty means
  // "offer the country defaults". Persisted as one JSON string so the
  // backup prefs whitelist (String/int only) can carry it.
  List<String> _myBookshopIds = [];
  List<String> get myBookshopIds => List.unmodifiable(_myBookshopIds);

  // Reader-configured local public library catalogues (wizard-built URL
  // templates). Same one-JSON-String persistence rationale as bookshops.
  List<LocalLibraryPortal> _myLibraryPortals = [];
  List<LocalLibraryPortal> get myLibraryPortals =>
      List.unmodifiable(_myLibraryPortals);

  // Bookshops the reader added by hand through the same witness wizard.
  List<LocalLibraryPortal> _myCustomBookshops = [];
  List<LocalLibraryPortal> get myCustomBookshops =>
      List.unmodifiable(_myCustomBookshops);

  // Discoverability card for the library connection, shown on wanted
  // books until a catalogue is connected or the reader dismisses it.
  /// Whether book pages offer library catalogues at all.
  ///
  /// Named for the intro card it used to gate; that card is gone and the flag
  /// now governs the whole library block of the acquisition sheet, which is
  /// what a reader switching off "library suggestions" was asking for. The
  /// stored key stays `library_intro_dismissed`: it is in the backup
  /// whitelist, and its existing values mean exactly this.
  bool _showLibraryLinks = true;
  bool get showLibraryLinks => _showLibraryLinks;

  // Inventory-style book statuses (available, checked_out, reference_only,
  // missing, damaged, on_order) instead of personal-reading statuses
  // (to_read, reading, read, wanting). Activated by the librarian preset;
  // available as a standalone toggle for users who catalogue their personal
  // collection like an institutional one.
  bool _inventoryStatusesEnabled = false;
  bool get inventoryStatusesEnabled => _inventoryStatusesEnabled;

  // Private books: allows marking individual books as hidden from peers.
  // Disabled for librarian/bookseller (all books must be visible).
  bool _allowPrivateBooks = true;
  bool get allowPrivateBooks => _allowPrivateBooks;

  // Gamification: disabled by default for librarians and booksellers
  bool _gamificationEnabled = true;
  bool get gamificationEnabled => _gamificationEnabled;

  // Games (parent toggle for all mini-games)
  bool _gamesEnabled = true;
  bool get gamesEnabled => _gamesEnabled;

  // Memory Game Module
  bool _memoryGameEnabled = true;
  bool get memoryGameEnabled => _memoryGameEnabled;

  // Sliding Puzzle Module
  bool _slidingPuzzleEnabled = true;
  bool get slidingPuzzleEnabled => _slidingPuzzleEnabled;

  // Hangman Module
  bool _hangmanEnabled = true;
  bool get hangmanEnabled => _hangmanEnabled;

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

  // Speech-to-text for note dictation (opt-in, disabled by default)
  bool _speechToTextEnabled = true;
  bool get speechToTextEnabled => _speechToTextEnabled;

  // Operation Log Viewer (developer tool, disabled by default)
  bool _operationLogViewerEnabled = false;
  bool get operationLogViewerEnabled => _operationLogViewerEnabled;

  // Notifications: global toggle + per category (OFF by default, experimental)
  bool _notificationsEnabled = true;
  bool get notificationsEnabled => _notificationsEnabled;
  bool _notifConnectionsEnabled = true;
  bool get notifConnectionsEnabled => _notifConnectionsEnabled;
  bool _notifLoansEnabled = true;
  bool get notifLoansEnabled => _notifLoansEnabled;
  bool _notifDiscoveriesEnabled = true;
  bool get notifDiscoveriesEnabled => _notifDiscoveriesEnabled;

  // Sync Safety: review incoming changes before applying (ON by default)
  bool _syncSafetyEnabled = true;
  bool get syncSafetyEnabled => _syncSafetyEnabled;

  // Bottom Navigation Bar (mobile only, alternative to drawer)
  bool _bottomNavEnabled = true;
  bool get bottomNavEnabled => _bottomNavEnabled;

  // Peer Offline Caching: allows viewing cached peer libraries when they're offline
  // Enabled by default for better UX (instant display on revisit)
  bool _peerOfflineCachingEnabled = true;
  bool get peerOfflineCachingEnabled => _peerOfflineCachingEnabled;

  // Allow Library Caching: allows others to cache YOUR library for offline viewing
  // Enabled by default for better peer experience
  bool _allowLibraryCaching = true;
  bool get allowLibraryCaching => _allowLibraryCaching;

  // Peer Book Cover Display: when off, peer library views skip cover
  // fetching entirely (forces the colored-spine fallback view) so the user
  // can bound the disk and bandwidth cost of browsing peers.
  bool _peerCoverDisplayEnabled = true;
  bool get peerCoverDisplayEnabled => _peerCoverDisplayEnabled;

  // Peer Book Cover Cache Cap (MB): user-facing maximum disk footprint of
  // the peer cover cache. Allowed values mirror the Settings UI selector:
  // 50 / 100 / 200 / 500. PeerBookCoverCacheManager derives a file-count
  // cap from this and sweeps the directory at startup if real disk usage
  // exceeds the cap by more than 10%.
  int _peerCoverCacheCapMb = 100;
  int get peerCoverCacheCapMb => _peerCoverCacheCapMb;
  static const List<int> peerCoverCacheCapChoicesMb = [50, 100, 200, 500];

  // Remote Reachable: relay-based connectivity for invited contacts
  // Enabled by default (safe: only invited contacts can reach via relay)
  bool _remoteReachableEnabled = true;
  bool get remoteReachableEnabled => _remoteReachableEnabled;

  // Connection Validation: require approval before new peers can access library
  // Disabled by default (open access)
  bool _connectionValidationEnabled = false;
  bool get connectionValidationEnabled => _connectionValidationEnabled;

  // Auto-approve loan requests from approved contacts
  // Disabled by default: owner should validate each borrow request
  bool _autoApproveLoanRequests = false;
  bool get autoApproveLoanRequests => _autoApproveLoanRequests;

  // Network Gamification: compare progress with connected peers
  bool _networkGamificationEnabled = true;
  bool get networkGamificationEnabled => _networkGamificationEnabled;

  // Share Gamification Stats: allow peers to see your gamification progress
  // Disabled by default for privacy
  bool _shareGamificationStats = false;
  bool get shareGamificationStats => _shareGamificationStats;

  // Recently-added carousels: independent for own vs peer library views.
  // Value stored is "hidden" — default false (carousel visible).
  bool _carouselHiddenOwnLib = false;
  bool get carouselHiddenOwnLib => _carouselHiddenOwnLib;

  bool _carouselHiddenPeerLib = false;
  bool get carouselHiddenPeerLib => _carouselHiddenPeerLib;

  // Collapsed state: shows a thin bar with the count instead of the full strip.
  // Not persisted beyond the session — auto-collapse on scroll should not
  // contaminate the next visit.
  bool _carouselCollapsedOwnLib = false;
  bool get carouselCollapsedOwnLib => _carouselCollapsedOwnLib;

  bool _carouselCollapsedPeerLib = false;
  bool get carouselCollapsedPeerLib => _carouselCollapsedPeerLib;

  // Which segment of the library top slot is showing (ADR-062 section 1):
  // false = Activity (the default, nothing ever auto-switches), true = the
  // discovery segment. Session-scoped like the collapsed flags above and
  // for the same reason: a segment remembered forever would silently bury
  // Activity for a reader who looked at suggestions once.
  bool _booksSlotShowsDiscovery = false;
  bool get booksSlotShowsDiscovery => _booksSlotShowsDiscovery;

  // Show View Count: display library view counter on profile
  // Enabled by default (visible on own profile only)
  bool _showViewCount = true;
  bool get showViewCount => _showViewCount;

  ThemeData get themeData {
    // Initialize registry if needed
    ThemeRegistry.initialize();

    // Get theme from registry, fallback to default
    final theme = ThemeRegistry.get(_themeStyle) ?? ThemeRegistry.defaultTheme;
    return theme.buildTheme(accentColor: _bannerColor);
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final colorValue = prefs.getInt('bannerColor');
    if (colorValue != null) {
      _bannerColor = Color(colorValue);
    }
    _isSetupComplete = prefs.getBool('isSetupComplete') ?? false;
    _themeStyle = prefs.getString('themeStyle') ?? 'default';
    _textScaleFactor = prefs.getDouble('textScaleFactor') ?? 1.05;

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
      _locale = parseLocaleTag(languageCode);
    } else {
      // Auto-detect system language on first launch
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
      final systemTag = localeToTag(systemLocale);
      if (supportedUILanguages.contains(systemTag) ||
          supportedUILanguages.contains(systemLocale.languageCode)) {
        _locale = systemLocale;
      } else {
        _locale = const Locale('en'); // Fallback to English
      }
    }

    // Load user reading languages (preserve regional tags like pt-BR)
    final userLangsJson = prefs.getString('userLanguages');
    if (userLangsJson != null) {
      try {
        final decoded = List<String>.from(jsonDecode(userLangsJson));
        // Normalize saved tags to known keys (fixes fr-FR → fr mismatch)
        _userLanguages = decoded.isNotEmpty
            ? decoded.map(normalizeToKnownLanguage).toSet().toList()
            : [normalizeToKnownLanguage(localeToTag(_locale))];
      } catch (e) {
        debugPrint('Error loading userLanguages: $e');
        _userLanguages = [normalizeToKnownLanguage(localeToTag(_locale))];
      }
    } else {
      // First launch: default to UI locale + system locale if different
      final systemTag = normalizeToKnownLanguage(
        localeToTag(WidgetsBinding.instance.platformDispatcher.locale),
      );
      _userLanguages = {
        normalizeToKnownLanguage(localeToTag(_locale)),
        systemTag,
      }.toList();
    }

    // If UI locale is no longer reachable, auto-switch and persist
    if (_ensureLocaleConsistency()) {
      await prefs.setString('languageCode', localeToTag(_locale));
    }

    _currentAvatarId = prefs.getString('avatarId') ?? 'individual';
    _currency = prefs.getString('currency') ?? 'EUR';

    // Load country (derive from device locale on first launch)
    final storedCountry = prefs.getString('country');
    if (storedCountry != null) {
      _country = storedCountry;
    } else {
      final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
      _country = systemLocale.countryCode?.toUpperCase() ?? 'FR';
      await prefs.setString('country', _country);
    }

    // Load borrowing capability setting (default true for fresh installs;
    // existing librarian users keep their saved value, set explicitly via
    // applyPreset('librarian')).
    final savedCanBorrow = prefs.getBool('canBorrowBooks');
    if (savedCanBorrow != null) {
      _canBorrowBooks = savedCanBorrow;
    } else {
      _canBorrowBooks = true;
    }

    // Bookshop suggestions: shown unless explicitly dismissed (cross on
    // the card or settings toggle).
    _showBookshopFinder = prefs.getBool('bookshop_finder_dismissed') != true;

    _showLibraryLinks = prefs.getBool('library_intro_dismissed') != true;

    final storedBookshops = prefs.getString('my_bookshop_ids');
    if (storedBookshops != null) {
      try {
        _myBookshopIds = (jsonDecode(storedBookshops) as List)
            .whereType<String>()
            .toList();
      } catch (_) {
        _myBookshopIds = [];
      }
    }

    final storedLibraries = prefs.getString('my_library_portals');
    if (storedLibraries != null) {
      try {
        _myLibraryPortals = (jsonDecode(storedLibraries) as List)
            .map(LocalLibraryPortal.fromJson)
            .whereType<LocalLibraryPortal>()
            .toList();
      } catch (_) {
        _myLibraryPortals = [];
      }
    }

    final storedCustomShops = prefs.getString('my_custom_bookshops');
    if (storedCustomShops != null) {
      try {
        _myCustomBookshops = (jsonDecode(storedCustomShops) as List)
            .map(LocalLibraryPortal.fromJson)
            .whereType<LocalLibraryPortal>()
            .toList();
      } catch (_) {
        _myCustomBookshops = [];
      }
    }

    // Load lending capability setting. Default true for readers and
    // librarians (they lend); disabled for booksellers (they sell, not lend).
    // Read commerceEnabled directly from prefs because _commerceEnabled is
    // assigned later in this method (see line below); isBookseller would
    // otherwise return false here for a bookseller user without a saved
    // canLendBooks value, leading to the wrong default.
    final savedCanLend = prefs.getBool('canLendBooks');
    if (savedCanLend != null) {
      _canLendBooks = savedCanLend;
    } else {
      final isBooksellerPref = prefs.getBool('commerceEnabled') ?? false;
      _canLendBooks = !isBooksellerPref;
    }

    // Inventory-style statuses. Migrate from the legacy profileType field
    // for existing librarian users so they don't lose their UI on upgrade.
    final savedInventoryStatuses = prefs.getBool('inventoryStatusesEnabled');
    if (savedInventoryStatuses != null) {
      _inventoryStatusesEnabled = savedInventoryStatuses;
    } else {
      // No explicit value yet: derive once from legacy profileType so old
      // librarian installs keep their cataloguing statuses.
      final legacyType = prefs.getString('profileType');
      _inventoryStatusesEnabled =
          legacyType == 'librarian' || legacyType == 'professional';
    }

    // Private books: default true for readers, false for booksellers.
    // Existing librarians preserved via their saved value (applyPreset).
    final savedAllowPrivate = prefs.getBool('allowPrivateBooks');
    if (savedAllowPrivate != null) {
      _allowPrivateBooks = savedAllowPrivate;
    } else {
      final isBooksellerPref = prefs.getBool('commerceEnabled') ?? false;
      _allowPrivateBooks = !isBooksellerPref;
    }

    _commerceEnabled = prefs.getBool('commerceEnabled') ?? false;
    // Default to false (opt-in) for privacy
    _networkDiscoveryEnabled =
        prefs.getBool('networkDiscoveryEnabled') ?? false;
    // Default to true - better UX (instant display of peer libraries on revisit)
    _peerOfflineCachingEnabled =
        prefs.getBool('peerOfflineCachingEnabled') ?? true;
    _allowLibraryCaching = prefs.getBool('allowLibraryCaching') ?? true;
    _peerCoverDisplayEnabled = prefs.getBool('peerCoverDisplayEnabled') ?? true;
    final savedPeerCap = prefs.getInt('peerCoverCacheCapMb') ?? 100;
    // Clamp to the set of values exposed in the Settings selector so a
    // stale or corrupted preference can't leave us with a non-UI-mapable
    // value -- the selector would otherwise render with nothing selected.
    _peerCoverCacheCapMb = peerCoverCacheCapChoicesMb.contains(savedPeerCap)
        ? savedPeerCap
        : 100;
    // Default to true - safe (only invited contacts can reach via relay)
    _remoteReachableEnabled = prefs.getBool('remoteReachableEnabled') ?? true;
    _connectionValidationEnabled =
        prefs.getBool('connectionValidationEnabled') ?? false;
    _autoApproveLoanRequests =
        prefs.getBool('autoApproveLoanRequests') ?? false;
    _networkGamificationEnabled =
        prefs.getBool('networkGamificationEnabled') ?? true;
    _shareGamificationStats = prefs.getBool('shareGamificationStats') ?? false;
    _carouselHiddenOwnLib = prefs.getBool('carousel_hidden_own_lib') ?? false;
    _carouselHiddenPeerLib = prefs.getBool('carousel_hidden_peer_lib') ?? false;
    _showViewCount = prefs.getBool('showViewCount') ?? true;
    _collectionsEnabled = prefs.getBool('collectionsEnabled') ?? false;
    _groupByCollections = prefs.getBool('groupByCollections') ?? true;
    _quotesEnabled = prefs.getBool('quotesEnabled') ?? true;

    _digitalFormatsEnabled = prefs.getBool('digitalFormatsEnabled') ?? false;
    _audioEnabled = prefs.getBool('audioEnabled') ?? false;
    _mcpEnabled = prefs.getBool('mcpEnabled') ?? false;
    _gamesEnabled = prefs.getBool('gamesEnabled') ?? true;
    _memoryGameEnabled = prefs.getBool('memoryGameEnabled') ?? true;
    _slidingPuzzleEnabled = prefs.getBool('slidingPuzzleEnabled') ?? true;
    _hangmanEnabled = prefs.getBool('hangmanEnabled') ?? true;
    _operationLogViewerEnabled =
        prefs.getBool('operationLogViewerEnabled') ?? false;
    // Speech-to-text: disabled for librarians/booksellers (catalog focus, not personal reading)
    final savedSpeechToText = prefs.getBool('speechToTextEnabled');
    if (savedSpeechToText != null) {
      _speechToTextEnabled = savedSpeechToText;
    } else {
      final isBooksellerPref = prefs.getBool('commerceEnabled') ?? false;
      _speechToTextEnabled = !isBooksellerPref;
    }
    _syncSafetyEnabled = prefs.getBool('syncSafetyEnabled') ?? true;
    _bottomNavEnabled = prefs.getBool('bottomNavEnabled') ?? true;
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    _notifConnectionsEnabled = prefs.getBool('notifConnectionsEnabled') ?? true;
    _notifLoansEnabled = prefs.getBool('notifLoansEnabled') ?? true;
    _notifDiscoveriesEnabled = prefs.getBool('notifDiscoveriesEnabled') ?? true;

    // Default true for fresh installs; the librarian preset turns it off
    // explicitly via setGamificationEnabled(false), so existing librarian
    // users keep their saved value.
    final savedGamification = prefs.getBool('gamificationEnabled');
    if (savedGamification != null) {
      _gamificationEnabled = savedGamification;
    } else {
      _gamificationEnabled = true;
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

    await _ensureLibraryTag(prefs);
    _libraryNameCustomized = prefs.getBool('libraryNameCustomized') ?? false;
    final storedName = prefs.getString('libraryName');
    if (storedName == null || storedName.isEmpty) {
      // First launch: use localized default with tag
      _libraryName = localizedDefaultName;
      await prefs.setString('libraryName', _libraryName);
    } else if (storedName == 'My Library' && !_libraryNameCustomized) {
      // Migration: replace hardcoded English default with localized name + tag
      _libraryName = localizedDefaultName;
      await prefs.setString('libraryName', _libraryName);
    } else {
      _libraryName = storedName;
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

  /// Push the current Dart-side module flags to the Rust backend.
  ///
  /// `_updateEnabledModules()` was only invoked on toggle, so users who
  /// never touched a Settings switch had an empty list in the DB — which
  /// caused `/api/public-stats-bundle` to return null for every game
  /// (hangman, memory, puzzle) and gamification sharing.
  ///
  /// Call this from `main.dart` AFTER the FFI HTTP server is confirmed
  /// running, otherwise `updateProfile` falls through to its fake-success
  /// path (server unavailable) and nothing is persisted.
  Future<void> syncEnabledModulesToBackend() async {
    await _updateEnabledModules();
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

  Future<void> setShowBookshopFinder(bool enabled) async {
    _showBookshopFinder = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bookshop_finder_dismissed', !enabled);
    notifyListeners();
  }

  Future<void> setShowLibraryLinks(bool enabled) async {
    _showLibraryLinks = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('library_intro_dismissed', !enabled);
    notifyListeners();
  }

  Future<void> addMyBookshop(String id) async {
    if (_myBookshopIds.contains(id)) return;
    _myBookshopIds = [..._myBookshopIds, id];
    await _persistMyBookshops();
  }

  Future<void> removeMyBookshop(String id) async {
    _myBookshopIds = _myBookshopIds.where((e) => e != id).toList();
    await _persistMyBookshops();
  }

  Future<void> _persistMyBookshops() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_bookshop_ids', jsonEncode(_myBookshopIds));
    notifyListeners();
  }

  Future<void> addMyLibraryPortal(LocalLibraryPortal portal) async {
    if (_myLibraryPortals.any((p) => p.urlTemplate == portal.urlTemplate)) {
      return;
    }
    _myLibraryPortals = [..._myLibraryPortals, portal];
    await _persistMyLibraryPortals();
  }

  Future<void> removeMyLibraryPortal(String urlTemplate) async {
    _myLibraryPortals = _myLibraryPortals
        .where((p) => p.urlTemplate != urlTemplate)
        .toList();
    await _persistMyLibraryPortals();
  }

  Future<void> _persistMyLibraryPortals() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'my_library_portals',
      jsonEncode([for (final p in _myLibraryPortals) p.toJson()]),
    );
    notifyListeners();
  }

  Future<void> addMyCustomBookshop(LocalLibraryPortal portal) async {
    if (_myCustomBookshops.any((p) => p.urlTemplate == portal.urlTemplate)) {
      return;
    }
    _myCustomBookshops = [..._myCustomBookshops, portal];
    await _persistMyCustomBookshops();
  }

  Future<void> removeMyCustomBookshop(String urlTemplate) async {
    _myCustomBookshops = _myCustomBookshops
        .where((p) => p.urlTemplate != urlTemplate)
        .toList();
    await _persistMyCustomBookshops();
  }

  Future<void> _persistMyCustomBookshops() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'my_custom_bookshops',
      jsonEncode([for (final p in _myCustomBookshops) p.toJson()]),
    );
    notifyListeners();
  }

  Future<void> setCanLendBooks(bool enabled) async {
    _canLendBooks = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('canLendBooks', enabled);
    notifyListeners();
  }

  Future<void> setInventoryStatusesEnabled(bool enabled) async {
    _inventoryStatusesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('inventoryStatusesEnabled', enabled);
    notifyListeners();
  }

  Future<void> setAllowPrivateBooks(bool enabled) async {
    _allowPrivateBooks = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allowPrivateBooks', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setGamificationEnabled(bool enabled) async {
    _gamificationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gamificationEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setGamesEnabled(bool enabled) async {
    _gamesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('gamesEnabled', enabled);
    if (!enabled) {
      _memoryGameEnabled = false;
      _slidingPuzzleEnabled = false;
      _hangmanEnabled = false;
      await prefs.setBool('memoryGameEnabled', false);
      await prefs.setBool('slidingPuzzleEnabled', false);
      await prefs.setBool('hangmanEnabled', false);
    } else {
      _memoryGameEnabled = true;
      _slidingPuzzleEnabled = true;
      _hangmanEnabled = true;
      await prefs.setBool('memoryGameEnabled', true);
      await prefs.setBool('slidingPuzzleEnabled', true);
      await prefs.setBool('hangmanEnabled', true);
    }
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setMemoryGameEnabled(bool enabled) async {
    _memoryGameEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('memoryGameEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setSlidingPuzzleEnabled(bool enabled) async {
    _slidingPuzzleEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('slidingPuzzleEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setHangmanEnabled(bool enabled) async {
    _hangmanEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hangmanEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setOperationLogViewerEnabled(bool enabled) async {
    _operationLogViewerEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('operationLogViewerEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setSpeechToTextEnabled(bool enabled) async {
    _speechToTextEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('speechToTextEnabled', enabled);
    notifyListeners();
  }

  Future<void> setSyncSafetyEnabled(bool enabled) async {
    _syncSafetyEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('syncSafetyEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  Future<void> setBottomNavEnabled(bool enabled) async {
    _bottomNavEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bottomNavEnabled', enabled);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', enabled);
    notifyListeners();
  }

  Future<void> setNotifConnectionsEnabled(bool enabled) async {
    _notifConnectionsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifConnectionsEnabled', enabled);
    notifyListeners();
  }

  Future<void> setNotifLoansEnabled(bool enabled) async {
    _notifLoansEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifLoansEnabled', enabled);
    notifyListeners();
  }

  Future<void> setNotifDiscoveriesEnabled(bool enabled) async {
    _notifDiscoveriesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifDiscoveriesEnabled', enabled);
    notifyListeners();
  }

  Future<void> setCountry(String country) async {
    _country = country.toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('country', _country);
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    _currency = currency;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', currency);
    notifyListeners();
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
          data: {'avatar_config': config.toJson()},
        );
      } catch (e) {
        debugPrint('Error syncing avatar config: $e');
      }
    }
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', localeToTag(locale));
    notifyListeners();
  }

  /// Set locale synchronously without persisting. For tests only.
  @visibleForTesting
  void setLocaleSync(Locale locale) {
    _locale = locale;
  }

  Future<void> setUserLanguages(List<String> langs) async {
    if (langs.isEmpty) return;
    _userLanguages = langs.toSet().toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userLanguages', jsonEncode(_userLanguages));
    if (_ensureLocaleConsistency()) {
      await prefs.setString('languageCode', localeToTag(_locale));
    }
    notifyListeners();
  }

  /// Ensures the current UI locale is a supported UI language.
  /// Reading languages and UI language are independent concerns.
  /// Checks both the full tag (e.g. 'pt-BR') and the base language ('pt').
  /// Returns true if the locale was changed (caller should persist).
  bool _ensureLocaleConsistency() {
    final tag = localeToTag(_locale);
    if (supportedUILanguages.contains(tag) ||
        supportedUILanguages.contains(_locale.languageCode)) {
      return false;
    }
    _locale = const Locale('en');
    return true;
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

  Future<void> completeSetup() async {
    _isSetupComplete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isSetupComplete', true);
    notifyListeners();

    // Emit welcome notification (idempotent: fires at most once per install)
    try {
      await frb.emitWelcomeNotification();
    } catch (e) {
      debugPrint('Welcome notification failed (non-blocking): $e');
    }
  }

  /// Initialize defaults for first launch (skip setup wizard).
  /// Call this once during app startup if setup is not complete.
  Future<void> initializeDefaults() async {
    if (_isSetupComplete) return; // Already setup

    final prefs = await SharedPreferences.getInstance();

    // Auto-detect language from device
    final systemLocale = WidgetsBinding.instance.platformDispatcher.locale;
    if (supportedUILanguages.contains(systemLocale.languageCode)) {
      _locale = Locale(systemLocale.languageCode);
      await prefs.setString('languageCode', systemLocale.languageCode);
    } else {
      _locale = const Locale('en');
      await prefs.setString('languageCode', 'en');
    }

    // Ensure unique tag exists for this install
    await _ensureLibraryTag(prefs);

    // Set sensible defaults -- preserve existing name if already customized
    // (e.g. device name was set earlier in main() before this runs again)
    final existingName = prefs.getString('libraryName');
    if (existingName == null ||
        existingName.isEmpty ||
        existingName == 'My Library') {
      _libraryName = localizedDefaultName;
      await prefs.setString('libraryName', _libraryName);
    } else {
      _libraryName = existingName;
    }

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
    _libraryNameCustomized = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    // Regenerate tag after clear, then set localized default
    _libraryTag = generateTag();
    await prefs.setString('libraryTag', _libraryTag!);
    _libraryName = localizedDefaultName;
    // Reset in-memory state to defaults
    _gamificationEnabled = true;
    _quotesEnabled = true;
    _collectionsEnabled = false;
    _groupByCollections = true;
    _gamesEnabled = true;
    _memoryGameEnabled = true;
    _slidingPuzzleEnabled = true;
    _hangmanEnabled = true;
    _commerceEnabled = false;
    _audioEnabled = false;
    _networkDiscoveryEnabled = false;
    _networkGamificationEnabled = false;
    _canBorrowBooks = true;
    _allowPrivateBooks = true;
    _syncSafetyEnabled = true;
    _notificationsEnabled = true;
    _notifConnectionsEnabled = true;
    _notifLoansEnabled = true;
    _notifDiscoveriesEnabled = true;
    _operationLogViewerEnabled = false;
    _speechToTextEnabled = true;
    _bottomNavEnabled = true;
    notifyListeners();
  }

  // Library Name
  String _libraryName = '';
  String get libraryName =>
      _libraryName.isNotEmpty ? _libraryName : localizedDefaultName;

  bool _libraryNameCustomized = false;
  bool get libraryNameCustomized => _libraryNameCustomized;

  // Unique tag per install (4 chars, generated once, persisted)
  String? _libraryTag;
  String? get libraryTag => _libraryTag;

  /// Single source of truth for generating a default library name.
  /// Without [deviceName]: "Ma Bibliotheque #A7K2"
  /// With [deviceName]:    "Bibliotheque de iPhone #A7K2"
  String buildDefaultLibraryName({String? deviceName}) {
    final lang = _locale.languageCode;
    final String base;
    if (deviceName != null && deviceName.isNotEmpty) {
      final template = TranslationService.translateByLocale(
        lang,
        'library_of_device',
      );
      base = template.replaceAll('%s', deviceName);
    } else {
      base = TranslationService.translateByLocale(lang, 'my_library_title');
    }
    return _libraryTag != null ? '$base #$_libraryTag' : base;
  }

  /// Shortcut: default name without device name.
  String get localizedDefaultName => buildDefaultLibraryName();

  /// Generate a 4-char tag (uppercase letters + digits, no ambiguous O/0/I/1/L).
  static String generateTag() {
    const chars = 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        4,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  /// Load or create the unique library tag from SharedPreferences.
  Future<void> _ensureLibraryTag(SharedPreferences prefs) async {
    _libraryTag = prefs.getString('libraryTag');
    if (_libraryTag == null) {
      _libraryTag = generateTag();
      await prefs.setString('libraryTag', _libraryTag!);
    }
  }

  /// Mark the library name as explicitly chosen by the user.
  Future<void> markLibraryNameCustomized() async {
    _libraryNameCustomized = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('libraryNameCustomized', true);
  }

  Future<void> setLibraryName(
    String name, {
    ApiService? apiService,
    bool userInitiated = false,
  }) async {
    if (_libraryName == name) return;
    _libraryName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('libraryName', name);
    if (userInitiated) {
      await markLibraryNameCustomized();
    }
    notifyListeners();

    // Sync with Rust backend so /api/config returns the updated name
    try {
      await FfiService().updateLibraryName(name);
    } catch (e) {
      debugPrint('Error syncing library name to backend: $e');
    }
  }

  Future<void> setCommerceEnabled(bool enabled) async {
    _commerceEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('commerceEnabled', enabled);
    await _updateEnabledModules();
    notifyListeners();
  }

  /// Test seam for the Reader-preset favorites seeding (ADR-064): the FFI
  /// call needs a native backend, which widget tests do not have.
  @visibleForTesting
  static Future<bool> Function()? seedFavoritesOverride;

  /// Apply a preset configuration that enables/disables multiple modules at once
  Future<void> applyPreset(String presetName) async {
    switch (presetName) {
      case 'reader':
        // Reader preset: personal reading flow (to_read/reading/read/...)
        await setGamificationEnabled(true);
        await setQuotesEnabled(true);
        await setCollectionsEnabled(true);
        await setAudioEnabled(true);
        await setCommerceEnabled(false);
        await setCanBorrowBooks(true);
        await setCanLendBooks(true);
        await setAllowPrivateBooks(true);
        await setShowBookshopFinder(true);
        await setInventoryStatusesEnabled(false);
        // Seed the favorites collection (ADR-064). ONLY here: selecting the
        // Reader profile is the one explicit gesture that pre-creates it;
        // startup and migrations never do. The eligibility gate (no typed
        // collection, no favorites-like collection or shelf) lives
        // Rust-side, so applying the preset twice stays a no-op.
        await (seedFavoritesOverride?.call() ??
            FfiService().seedFavoritesCollection());
        break;
      case 'librarian':
        // Librarian preset: cataloguing flow (available/checked_out/...)
        await setGamificationEnabled(false);
        await setQuotesEnabled(false);
        await setCollectionsEnabled(true);
        await setNetworkEnabled(true);
        await setCommerceEnabled(false);
        await setCanBorrowBooks(false);
        await setCanLendBooks(true);
        await setAllowPrivateBooks(false);
        await setInventoryStatusesEnabled(true);
        await setShowBookshopFinder(false);
        break;
      case 'bookseller':
        // Bookseller preset: commerce flow (personal-reading statuses
        // preserved — pre-existing behavior; they sell, do not catalogue
        // an institutional collection).
        await setCommerceEnabled(true);
        await setCollectionsEnabled(true);
        await setGamificationEnabled(false);
        await setQuotesEnabled(false);
        await setAudioEnabled(false);
        await setCanBorrowBooks(false);
        await setCanLendBooks(false);
        await setAllowPrivateBooks(false);
        await setInventoryStatusesEnabled(false);
        await setShowBookshopFinder(false);
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

    // Auto-enable caching when activating network
    if (enabled && !_peerOfflineCachingEnabled) {
      _peerOfflineCachingEnabled = true;
      await prefs.setBool('peerOfflineCachingEnabled', true);
    }
    if (enabled && !_allowLibraryCaching) {
      _allowLibraryCaching = true;
      await prefs.setBool('allowLibraryCaching', true);
    }

    notifyListeners();

    if (enabled) {
      if (libraryId != null && port != null) {
        try {
          await MdnsService.startAnnouncing(
            libraryName,
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

  /// Enable/disable remote reachability via relay
  /// When enabled, invited contacts can reach you on any network (4G, 5G, WiFi)
  /// Safe by default: only people with your invite link can contact you
  Future<void> setRemoteReachableEnabled(bool enabled) async {
    _remoteReachableEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remoteReachableEnabled', enabled);

    // Auto-enable caching when activating remote reachability
    if (enabled && !_peerOfflineCachingEnabled) {
      _peerOfflineCachingEnabled = true;
      await prefs.setBool('peerOfflineCachingEnabled', true);
    }
    if (enabled && !_allowLibraryCaching) {
      _allowLibraryCaching = true;
      await prefs.setBool('allowLibraryCaching', true);
    }

    notifyListeners();
  }

  Future<void> setCarouselHiddenOwnLib(bool hidden) async {
    _carouselHiddenOwnLib = hidden;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('carousel_hidden_own_lib', hidden);
    notifyListeners();
  }

  Future<void> setCarouselHiddenPeerLib(bool hidden) async {
    _carouselHiddenPeerLib = hidden;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('carousel_hidden_peer_lib', hidden);
    notifyListeners();
  }

  void setCarouselCollapsedOwnLib(bool collapsed) {
    if (_carouselCollapsedOwnLib == collapsed) return;
    _carouselCollapsedOwnLib = collapsed;
    notifyListeners();
  }

  void setCarouselCollapsedPeerLib(bool collapsed) {
    if (_carouselCollapsedPeerLib == collapsed) return;
    _carouselCollapsedPeerLib = collapsed;
    notifyListeners();
  }

  void setBooksSlotShowsDiscovery(bool showsDiscovery) {
    if (_booksSlotShowsDiscovery == showsDiscovery) return;
    _booksSlotShowsDiscovery = showsDiscovery;
    notifyListeners();
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

  /// Toggle peer cover display. When disabled, peer library views fall back
  /// to the colored-spine shelf layout: no CachedNetworkImage is built, so
  /// no fetch leaves the device and no file is written to disk. The cache
  /// cap and Clear button stay available -- the user may still want to
  /// manage previously accumulated covers.
  Future<void> setPeerCoverDisplayEnabled(bool enabled) async {
    _peerCoverDisplayEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('peerCoverDisplayEnabled', enabled);
    notifyListeners();
  }

  /// Update the peer cover cache cap (MB). Silently rejects values outside
  /// [peerCoverCacheCapChoicesMb] so the UI selector is the single source
  /// of truth for legal values. Also reconfigures the cache manager so the
  /// new cap takes effect immediately, including the disk sweep that
  /// protects against under-estimated average cover sizes.
  Future<void> setPeerCoverCacheCapMb(int capMb) async {
    if (!peerCoverCacheCapChoicesMb.contains(capMb)) return;
    if (_peerCoverCacheCapMb == capMb) return;
    _peerCoverCacheCapMb = capMb;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('peerCoverCacheCapMb', capMb);
    await PeerBookCoverCacheManager.configure(capMb: capMb);
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

  /// Enable/disable auto-approve loan requests
  /// When enabled, loan requests from approved contacts are instantly accepted
  Future<void> setAutoApproveLoanRequests(bool enabled) async {
    _autoApproveLoanRequests = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoApproveLoanRequests', enabled);
    await _updateEnabledModules();
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

  Future<void> setShowViewCount(bool enabled) async {
    _showViewCount = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('showViewCount', enabled);
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

  // Group library by collection (display setting)
  bool _groupByCollections = true;
  bool get groupByCollections => _groupByCollections;

  Future<void> setGroupByCollections(bool enabled) async {
    _groupByCollections = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('groupByCollections', enabled);
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

    if (digitalFormatsEnabled) enabledModules.add('digital_formats');
    if (audioEnabled) enabledModules.add('audio');
    if (mcpEnabled) enabledModules.add('mcp');
    if (peerOfflineCachingEnabled) enabledModules.add('peer_offline_caching');
    if (allowLibraryCaching) enabledModules.add('allow_library_caching');
    if (connectionValidationEnabled) {
      enabledModules.add('connection_validation');
    }
    if (autoApproveLoanRequests) {
      enabledModules.add('auto_approve_loans');
    }
    if (commerceEnabled) enabledModules.add('commerce');
    if (gamesEnabled) enabledModules.add('games');
    if (memoryGameEnabled) enabledModules.add('memory_game');
    if (slidingPuzzleEnabled) enabledModules.add('sliding_puzzle');
    if (hangmanEnabled) enabledModules.add('hangman');
    if (networkGamificationEnabled) {
      enabledModules.add('network_gamification');
    }
    if (shareGamificationStats) {
      enabledModules.add('share_gamification_stats');
    }
    if (operationLogViewerEnabled) {
      enabledModules.add('operation_log_viewer');
    }
    if (syncSafetyEnabled) {
      enabledModules.add('sync_safety');
    }
    if (allowPrivateBooks) {
      enabledModules.add('allow_private_books');
    }

    // Preserve search-source flags owned by the Settings screen, NOT by
    // ThemeProvider. `enabled_modules` is a single column shared by two
    // concerns: ThemeProvider feature toggles (above) and the external-search
    // source preferences (`enable_google_books`, `disable_fallback:<provider>`).
    // updateProfile replaces the whole column, so without re-appending these
    // the startup sync wipes the user's Google Books opt-in every launch.
    // Re-derive them from the persisted state (the inverse of the backend's
    // own modules<->preferences mapping) so both concerns coexist.
    try {
      final settings = await FfiService().getSearchSettings();
      settings.fallbackPreferences.forEach((provider, enabled) {
        if (provider == 'google_books') {
          if (enabled) enabledModules.add('enable_google_books');
        } else if (!enabled) {
          enabledModules.add('disable_fallback:$provider');
        }
      });
    } catch (e) {
      // Non-fatal: if we cannot read them, fall through rather than risk
      // sending a list that wipes settings on a transient read failure.
      debugPrint('Could not preserve search-source flags, skipping sync: $e');
      return;
    }

    try {
      await apiService.updateProfile(data: {'enabled_modules': enabledModules});
      debugPrint('✅ Synced enabled modules: $enabledModules');
    } catch (e) {
      debugPrint('Error syncing enabled modules: $e');
    }
  }
}
