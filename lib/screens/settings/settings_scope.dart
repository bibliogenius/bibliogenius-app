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
/// The app provides it, so the section list and a section page stacked on top
/// of it share one copy; the pages hand it to their sections through
/// [SettingsScope]. It outlives the list: the list calls [forgetVisit] when it
/// opens. A section mutates the fields it owns and rebuilds itself with
/// `setState`; [load] and [autoConnectRelay] notify, since they finish on
/// their own time.
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

  /// Bumped when a section page closes; the search results key their sections
  /// with it.
  int resultsGeneration = 0;

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
      // Read once here so the "reachable remotely" switch shows its real
      // state as the section opens (see [remoteReachableShown]).
      await hub.onlineServicesAllowed();

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
          // Auto-connect relay if remote reachable is enabled but not yet
          // connected. Opening the settings is not a choice: the mailbox
          // waits for the online services consent (ADR-073).
          if (theme.remoteReachableEnabled &&
              await hub.onlineServicesAllowed()) {
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

  /// Drops what the last visit loaded or typed, so a new visit starts from
  /// what the backend answers (after a reset, a key no longer stored, a key
  /// typed but not saved). Not part of [load]: a pull-to-refresh keeps the
  /// fields. Leaves [relayLoading] alone, a connection may still be running.
  void forgetVisit() {
    isLoading = true;
    config = null;
    userInfo = null;
    userStatus = null;
    searchPrefs.clear();
    googleBooksApiKey = '';
    showGoogleAdvanced = false;
    apiKeyController.clear();
    relayMailboxUuid = null;
    relayConnected = false;
    relayUrlController.clear();
    hubWebsiteController.clear();
  }

  /// A section page has closed: search results that stayed mounted under it
  /// remount and read what it changed.
  void sectionPageClosed() {
    resultsGeneration++;
    _notify();
  }

  /// Loads again with what the last [load] was given.
  Future<void> reload() async {
    final api = _api, theme = _theme, hub = _hub;
    if (api == null || theme == null || hub == null) return;
    await load(api, theme, hub);
  }

  /// What the "reachable remotely" switch shows. The preference is on by
  /// default, but without the online services consent (ADR-073) no mailbox
  /// exists: the switch then shows off, whatever the stored preference
  /// says. Read from the hub provider, which notifies when a dialog is
  /// accepted anywhere, on this page or another.
  static bool remoteReachableShown(
    ThemeProvider theme,
    HubDirectoryProvider hub,
  ) => theme.remoteReachableEnabled && hub.onlineServicesKnownAllowed;

  /// Connects the relay when the user turns "reachable remotely" on: the
  /// mailbox is created, then the library registered if it was not, since
  /// nothing registers it at startup any more. The switch asks the question
  /// of ADR-073 D2 first; without a consent nothing is sent.
  Future<void> autoConnectRelay(BuildContext context) async {
    final api = Provider.of<ApiService>(context, listen: false);
    final hub = context.read<HubDirectoryProvider>();
    if (!await hub.onlineServicesAllowed()) return;
    await _connectRelay(api, hub);
    if (!hub.isRegistered) await hub.initAndSyncCatalog();
  }

  Future<void> _connectRelay(ApiService api, HubDirectoryProvider hub) async {
    if (relayConnected) return;
    if (await _adoptExistingRelay(api) || _disposed) return;
    final url = kReleaseMode
        ? ApiService.hubUrl
        : (relayUrlController.text.trim().isNotEmpty
              ? relayUrlController.text.trim()
              : ApiService.hubUrl);
    try {
      // Followed by the hub provider: a withdrawal waits for a mailbox
      // on its way, or it would be created after the deletion.
      final res = await hub.trackHubWrite(api.setupRelay(relayUrl: url));
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

  /// Shows as connected a mailbox this page has not seen yet, and says
  /// whether there was one. Accepting the consent dialog elsewhere creates
  /// a mailbox in the background while this page still offers to connect:
  /// setting the relay up again would create a second mailbox and orphan
  /// the first.
  Future<bool> _adoptExistingRelay(ApiService api) async {
    try {
      final existing = await api.getRelayConfig();
      if (_disposed) return false;
      if (existing.statusCode == 200 &&
          existing.data is Map &&
          existing.data['relay_url'] != null) {
        relayConnected = true;
        relayMailboxUuid = existing.data['mailbox_uuid'] as String?;
        relayUrlController.text = existing.data['relay_url'] as String? ?? '';
        _notify();
        return true;
      }
    } catch (_) {
      // No configuration yet.
    }
    return false;
  }

  /// Connects the relay at [url], from the Connect button. Lives here and not
  /// in the Network section so it completes (state, notification, published
  /// credentials) even when the section page is closed or hidden by a search
  /// before the hub answers. Returns null on success, else the error to show.
  Future<String?> connectRelay(
    ApiService api,
    HubDirectoryProvider hub,
    String url,
  ) async {
    relayLoading = true;
    _notify();
    try {
      // The Connect button asks the question of ADR-073 D2 first; without
      // a consent no mailbox is created.
      if (!await hub.onlineServicesAllowed()) return 'Connection failed';
      if (await _adoptExistingRelay(api)) {
        // A mailbox created in the background may not be published yet:
        // peers reach it through the credentials the hub holds.
        await hub.ensureRelayPublished();
        if (!hub.isRegistered) await hub.initAndSyncCatalog();
        return null;
      }
      // Followed by the hub provider: a withdrawal waits for a mailbox
      // on its way, or it would be created after the deletion.
      final res = await hub.trackHubWrite(api.setupRelay(relayUrl: url));
      if (res.statusCode == 200 && res.data is Map) {
        relayConnected = true;
        relayMailboxUuid = res.data['mailbox_uuid'] as String?;
        _notify();
        // Publish new relay credentials to hub so peers can reach this mailbox.
        await hub.ensureRelayPublished();
        // Nothing registers the library at startup any more.
        if (!hub.isRegistered) await hub.initAndSyncCatalog();
        return null;
      }
      return (res.data?['error'] ?? 'Connection failed').toString();
    } catch (e) {
      return e.toString();
    } finally {
      relayLoading = false;
      _notify();
    }
  }

  /// Disconnects the relay, from the Disconnect button; see [connectRelay].
  /// Returns null on success, else the error to show.
  Future<String?> disconnectRelay(ApiService api) async {
    relayLoading = true;
    _notify();
    try {
      await api.disconnectRelay();
      relayConnected = false;
      relayMailboxUuid = null;
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      relayLoading = false;
      _notify();
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

/// Hands the [SettingsData] and the current search query to the sections of a
/// settings page, including those shown in a capability bottom sheet (which
/// sits outside the page's subtree and gets its own scope). A section page
/// has no search: its scope holds an empty query.
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

/// Whether the search query matches [label], a text with no i18n key, or the
/// hidden synonyms registered under [key]. Always true when not searching.
bool settingsMatchesLabel(BuildContext context, String key, String label) =>
    settingsKeyMatches(key: key, label: label, query: _query(context));

/// Whether the settings search box holds a query.
bool settingsIsSearching(BuildContext context) => _query(context).isNotEmpty;
