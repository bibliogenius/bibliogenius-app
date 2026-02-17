import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/audio_resource.dart';
import '../services/audiobook_service.dart';

/// Provider for managing audio module state and settings.
///
/// This provider:
/// - Manages the audio module enabled/disabled state
/// - Provides WiFi connectivity status for streaming decisions
/// - Caches audiobook search results per book
/// - Coordinates searches across multiple books
///
/// Usage:
/// ```dart
/// // In your main.dart providers
/// ChangeNotifierProvider(create: (_) => AudioProvider()),
///
/// // In your widgets
/// final audioProvider = context.watch<AudioProvider>();
/// if (audioProvider.isEnabled && audioProvider.isWifiConnected) { ... }
/// ```
class AudioProvider extends ChangeNotifier {
  // Must match the key used by ThemeProvider.setAudioEnabled()
  static const String _enabledKey = 'audioEnabled';

  final AudiobookService _service;
  final Connectivity _connectivity;

  bool _isEnabled = false;
  bool _isWifiConnected = false;
  bool _isInitialized = false;

  // Cache of audio resources by bookId (list for multi-language results)
  final Map<int, List<AudioResource>> _audioCache = {};

  // Track ongoing searches to avoid duplicates
  final Set<int> _searchingBookIds = {};

  AudioProvider({AudiobookService? service, Connectivity? connectivity})
    : _service = service ?? AudiobookService(),
      _connectivity = connectivity ?? Connectivity() {
    _initialize();
  }

  // Getters
  bool get isEnabled => _isEnabled;
  bool get isWifiConnected => _isWifiConnected;
  bool get isInitialized => _isInitialized;
  bool get canStream => _isEnabled && _isWifiConnected;

  /// Check if a search is in progress for a specific book
  bool isSearching(int bookId) => _searchingBookIds.contains(bookId);

  /// Get first cached audio resource for a book (retro-compatible)
  AudioResource? getAudioResource(int bookId) =>
      _audioCache[bookId]?.firstOrNull;

  /// Get all cached audio resources for a book
  List<AudioResource> getAudioResources(int bookId) =>
      _audioCache[bookId] ?? [];

  /// Check if we've already searched for a book (regardless of result)
  bool hasSearched(int bookId) => _audioCache.containsKey(bookId);

  /// Initialize provider: load settings and check connectivity
  Future<void> _initialize() async {
    try {
      // Load enabled setting
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_enabledKey) ?? false;

      // Check current connectivity
      await _checkConnectivity();

      // Listen for connectivity changes
      _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioProvider] Initialization error: $e');
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Enable or disable the audio module
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;

    _isEnabled = enabled;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, enabled);
    } catch (e) {
      debugPrint('[AudioProvider] Error saving enabled state: $e');
    }
  }

  /// Toggle the audio module on/off
  Future<void> toggle() => setEnabled(!_isEnabled);

  /// Search for an audiobook for the given book (single language, retro-compatible).
  ///
  /// This method:
  /// - Returns immediately if disabled or already cached
  /// - Searches in background if not cached
  /// - Updates cache and notifies listeners when complete
  ///
  /// [preferredLanguage] filters results to prioritize the user's language.
  Future<AudioResource?> searchAudiobook({
    required int bookId,
    required String title,
    String? author,
    String? preferredLanguage,
    bool forceRefresh = false,
  }) async {
    // Don't search if disabled
    if (!_isEnabled) return null;

    // Return cached result if available (unless force refresh)
    if (!forceRefresh && _audioCache.containsKey(bookId)) {
      return _audioCache[bookId]?.firstOrNull;
    }

    // Don't start duplicate searches
    if (_searchingBookIds.contains(bookId)) {
      return null;
    }

    _searchingBookIds.add(bookId);
    notifyListeners();

    try {
      final result = await _service.searchByTitleAndAuthor(
        bookId: bookId,
        title: title,
        author: author,
        preferredLanguage: preferredLanguage,
      );

      _audioCache[bookId] = result != null ? [result] : [];
      _searchingBookIds.remove(bookId);
      notifyListeners();

      return result;
    } catch (e) {
      debugPrint('[AudioProvider] Search error: $e');
      _audioCache[bookId] = [];
      _searchingBookIds.remove(bookId);
      notifyListeners();
      return null;
    }
  }

  /// Search for audiobooks across multiple languages.
  ///
  /// Returns all matching results (deduplicated by sourceId).
  /// Uses [languages] to search LibriVox per language, Litterature Audio
  /// for French, and always Internet Archive as fallback.
  Future<List<AudioResource>> searchAudiobookMultiLang({
    required int bookId,
    required String title,
    String? author,
    required List<String> languages,
    bool forceRefresh = false,
  }) async {
    if (!_isEnabled) return [];

    if (!forceRefresh && _audioCache.containsKey(bookId)) {
      return _audioCache[bookId] ?? [];
    }

    if (_searchingBookIds.contains(bookId)) {
      return [];
    }

    _searchingBookIds.add(bookId);
    notifyListeners();

    try {
      final results = await _service.searchAllLanguages(
        bookId: bookId,
        title: title,
        author: author,
        languages: languages,
      );

      _audioCache[bookId] = results;
      _searchingBookIds.remove(bookId);
      notifyListeners();

      return results;
    } catch (e) {
      debugPrint('[AudioProvider] Multi-lang search error: $e');
      _audioCache[bookId] = [];
      _searchingBookIds.remove(bookId);
      notifyListeners();
      return [];
    }
  }

  /// Clear cached audio resource for a specific book
  void clearBookCache(int bookId) {
    _audioCache.remove(bookId);
    notifyListeners();
  }

  /// Clear all cached data
  void clearAllCache() {
    _audioCache.clear();
    _service.clearCache();
    notifyListeners();
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isWifiConnected = result.contains(ConnectivityResult.wifi);
    } catch (e) {
      debugPrint('[AudioProvider] Connectivity check error: $e');
      _isWifiConnected = false;
    }
  }

  /// Handle connectivity changes
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasWifi = _isWifiConnected;
    _isWifiConnected = results.contains(ConnectivityResult.wifi);

    if (wasWifi != _isWifiConnected) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Connectivity listener is automatically cleaned up
    super.dispose();
  }
}
