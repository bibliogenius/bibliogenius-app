import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/hub_directory_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../services/ffi_service.dart';
import '../../services/translation_service.dart';
import '../../utils/settings_search.dart';

/// What the settings page loads once on open and its sections share: the
/// library config and user info, the search-source preferences, the relay
/// connection and the text fields they fill.
///
/// The page owns it and hands it to its sections through [SettingsScope]. A
/// section mutates the fields it owns and rebuilds itself with `setState`;
/// [load] and [autoConnectRelay] notify, since they finish on their own time.
class SettingsData extends ChangeNotifier {
  bool isLoading = true;
  Map<String, dynamic>? config;
  Map<String, dynamic>? userInfo;
  Map<String, dynamic>? userStatus;
  final Map<String, bool> searchPrefs = {};
  String googleBooksApiKey = '';
  // Reveal state for the Google Books API key field (replaces a nested
  // ExpansionTile that crashed layout; see the search sources section).
  bool showGoogleAdvanced = false;
  final apiKeyController = TextEditingController();
  // Relay Hub state
  String? relayMailboxUuid;
  bool relayConnected = false;
  bool relayLoading = false;
  final relayUrlController = TextEditingController();
  // Hub directory website controller. The contact card has its own widget
  // (ContactCardFields), which owns its controllers.
  final hubWebsiteController = TextEditingController();

  ApiService? _api;
  ThemeProvider? _theme;
  HubDirectoryProvider? _hub;
  bool _disposed = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Loads everything the page shows. [hub] receives the relay credentials
  /// when remote reachability connects the relay on the way.
  Future<void> load(
    ApiService api,
    ThemeProvider theme,
    HubDirectoryProvider hub,
  ) async {
    _api = api;
    _theme = theme;
    _hub = hub;

    isLoading = true;
    _notify();

    try {
      // Fetch Config
      final configRes = await api.getLibraryConfig();
      if (configRes.statusCode == 200) {
        config = configRes.data;
        // Library name is managed by ThemeProvider (SharedPreferences + FFI).
        // Profile type is no longer synced — module toggles drive UI now.
      }

      // Fetch User Info
      final meRes = await api.getMe();
      if (meRes.statusCode == 200) {
        userInfo = meRes.data;
      }

      // Fetch User Status for search preferences
      final statusRes = await api.getUserStatus();
      if (statusRes.statusCode == 200) {
        userStatus = statusRes.data;
        if (userStatus != null && userStatus!['config'] != null) {
          final config = userStatus!['config'];
          if (config['fallback_preferences'] != null) {
            final prefs = config['fallback_preferences'] as Map;
            prefs.forEach((key, value) {
              if (value is bool) {
                searchPrefs[key.toString()] = value;
              }
            });
          }
          if (config['api_keys'] != null && config['api_keys'] is Map) {
            final apiKeys = config['api_keys'] as Map;
            googleBooksApiKey = apiKeys['google_books']?.toString() ?? '';
            apiKeyController.text = googleBooksApiKey;
            if (googleBooksApiKey.isNotEmpty) showGoogleAdvanced = true;
          }
        }
      }

      // FFI mode: getUserStatus is mapped from gamification_get_status, which
      // does not carry search preferences. Hydrate them from a dedicated FFI
      // call so the toggles reflect the persisted state on screen open.
      if (api.useFfi) {
        try {
          final settings = await FfiService().getSearchSettings();
          settings.fallbackPreferences.forEach((key, value) {
            searchPrefs[key] = value;
          });
          final googleKey = settings.apiKeys['google_books'] ?? '';
          if (googleKey.isNotEmpty) {
            googleBooksApiKey = googleKey;
            apiKeyController.text = googleKey;
            showGoogleAdvanced = true;
          }
        } catch (e) {
          debugPrint('FFI getSearchSettings failed: $e');
        }
      }

      // Load relay config (may have been auto-configured at startup)
      try {
        final relayRes = await api.getRelayConfig();
        if (relayRes.statusCode == 200 &&
            relayRes.data is Map &&
            relayRes.data['relay_url'] != null) {
          relayConnected = true;
          relayMailboxUuid = relayRes.data['mailbox_uuid'] as String?;
          relayUrlController.text = relayRes.data['relay_url'] as String? ?? '';
        } else {
          relayUrlController.text = ApiService.hubUrl;
          // Auto-connect relay if remote reachable is enabled but not yet connected
          if (theme.remoteReachableEnabled) {
            _connectRelay(api, hub);
          }
        }
      } catch (_) {
        relayUrlController.text = ApiService.hubUrl;
      }

      // Loan settings are loaded by the modules section.

      isLoading = false;
      _notify();
    } catch (e) {
      debugPrint('Error fetching settings: $e');
      isLoading = false;
      _notify();
    }
  }

  /// Loads again with what the last [load] was given.
  Future<void> reload() async {
    final api = _api, theme = _theme, hub = _hub;
    if (api == null || theme == null || hub == null) return;
    await load(api, theme, hub);
  }

  /// Auto-connect relay when remote reachable is enabled.
  Future<void> autoConnectRelay(BuildContext context) => _connectRelay(
    Provider.of<ApiService>(context, listen: false),
    context.read<HubDirectoryProvider>(),
  );

  Future<void> _connectRelay(ApiService api, HubDirectoryProvider hub) async {
    if (relayConnected) return;
    final url = kReleaseMode
        ? ApiService.hubUrl
        : (relayUrlController.text.trim().isNotEmpty
              ? relayUrlController.text.trim()
              : ApiService.hubUrl);
    try {
      final res = await api.setupRelay(relayUrl: url);
      if (_disposed) return;
      if (res.statusCode == 200 && res.data is Map) {
        relayConnected = true;
        relayMailboxUuid = res.data['mailbox_uuid'] as String?;
        relayUrlController.text = url;
        _notify();
        // Publish new relay credentials to hub so peers can reach this mailbox.
        await hub.ensureRelayPublished();
      }
    } catch (e) {
      debugPrint('Auto-connect relay failed: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    apiKeyController.dispose();
    relayUrlController.dispose();
    hubWebsiteController.dispose();
    super.dispose();
  }
}

/// Hands the page's [SettingsData] and the current search query to its
/// sections, including those shown in a capability bottom sheet (which sits
/// outside the page's subtree and gets its own scope).
class SettingsScope extends InheritedNotifier<SettingsData> {
  const SettingsScope({
    super.key,
    required SettingsData data,
    required this.query,
    required super.child,
  }) : super(notifier: data);

  /// The settings search query, empty when not searching.
  final String query;

  @override
  bool updateShouldNotify(SettingsScope oldWidget) =>
      oldWidget.query != query || oldWidget.notifier != notifier;
}

/// The page's [SettingsData], for reads and writes. Does not rebuild the
/// caller when it changes: see [watchSettingsData].
SettingsData settingsDataOf(BuildContext context) =>
    context.getInheritedWidgetOfExactType<SettingsScope>()!.notifier!;

/// The page's [SettingsData], rebuilding the caller when it notifies.
SettingsData watchSettingsData(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<SettingsScope>()!.notifier!;

String _query(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<SettingsScope>()?.query ?? '';

/// Whether any of the given i18n keys' translated text (or its hidden
/// synonyms) matches the search query. Always true when not searching.
bool settingsMatches(BuildContext context, List<String> keys) {
  final query = _query(context);
  if (query.isEmpty) return true;
  for (final key in keys) {
    if (settingsKeyMatches(
      key: key,
      label: TranslationService.translate(context, key),
      query: query,
    )) {
      return true;
    }
  }
  return false;
}

/// Whether the settings search box holds a query.
bool settingsIsSearching(BuildContext context) => _query(context).isNotEmpty;
