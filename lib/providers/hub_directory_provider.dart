import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_config.dart';
import '../models/hub_directory.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../src/rust/api/frb.dart' show FrbNudgeEvent, subscribeRelayNudges;

/// Page size for directory listing.
const int _kPageSize = 20;

/// Max retry attempts for relay credential publishing.
const int _kRelayPublishMaxAttempts = 3;

/// Delay between relay publish retries.
const Duration _kRelayPublishRetryDelay = Duration(seconds: 5);

/// Cooldown before retrying relay publish from periodic sync (avoids hammering
/// the hub when the network is persistently down).
const Duration _kRelayPublishCooldown = Duration(seconds: 90);

/// State manager for the public hub directory feature (ADR-015).
///
/// Responsibilities:
/// - Local config (is_listed, requires_approval, accept_from)
/// - Directory browsing with pagination
/// - Follow/unfollow actions
/// - Incoming follow request management (approve / reject / block)
/// - Pending request count for badge display
/// - Hub-mediated borrow requests (ADR-018)
/// SharedPreferences key for the hub directory toggle.
const String _kHubEnabledKey = 'hub_directory_enabled';

/// SharedPreferences key: set to true once the user has dismissed the
/// first-time explanation banner in the Discover tab.
const String _kDirectoryOnboardingSeenKey = 'hub_directory_onboarding_seen';

/// SharedPreferences key for the local contact info (plaintext, never sent to hub).
const String _kContactInfoKey = 'hub_contact_info';

/// SharedPreferences key for the local website URL (sent plaintext to hub profile).
const String _kWebsiteKey = 'hub_website';

/// SharedPreferences key for user-defined follow display names (JSON map).
const String _kFollowNamesKey = 'hub_follow_custom_names';

class HubDirectoryProvider extends ChangeNotifier {
  final FfiService _ffi;
  final DeviceService _deviceService;
  final AuthService _authService;

  /// Retry delay between relay publish attempts. Override in tests.
  @visibleForTesting
  Duration relayRetryDelay = _kRelayPublishRetryDelay;

  /// Cooldown between periodic relay publish retry cycles. Override in tests.
  @visibleForTesting
  Duration relayCooldown = _kRelayPublishCooldown;

  HubDirectoryProvider({
    FfiService? ffi,
    DeviceService? deviceService,
    AuthService? authService,
  })  : _ffi = ffi ?? FfiService(),
        _deviceService = deviceService ?? DeviceService(),
        _authService = authService ?? AuthService();

  // ── Custom follow display names ──────────────────────────────────────────

  Map<String, String> _customFollowNames = {};

  /// Load user-defined follow display names from SharedPreferences.
  Future<void> loadCustomFollowNames() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFollowNamesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _customFollowNames = Map<String, String>.from(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      } catch (_) {
        _customFollowNames = {};
      }
    }
  }

  /// Save a custom display name for a hub follow (by node ID).
  Future<void> setFollowDisplayName(String nodeId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      _customFollowNames.remove(nodeId);
    } else {
      _customFollowNames[nodeId] = trimmed;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFollowNamesKey, jsonEncode(_customFollowNames));
    notifyListeners();
  }

  /// Get the user-defined custom name for a follow, if any.
  String? customFollowName(String nodeId) => _customFollowNames[nodeId];

  // ── Toggle & onboarding ─────────────────────────────────────────────────

  bool _hubEnabled = false;

  /// Whether the hub directory feature is enabled by the user.
  bool get isHubEnabled => _hubEnabled;

  /// True once the user has dismissed the first-time onboarding banner.
  bool _directoryOnboardingSeen = true;

  bool get isDirectoryOnboardingSeen => _directoryOnboardingSeen;

  // ── Relay nudge subscription ────────────────────────────────────────────

  StreamSubscription<FrbNudgeEvent>? _nudgeSub;

  // ── Load toggle + onboarding state ─────────────────────────────────────

  /// Load the toggle state from SharedPreferences. Call at app start.
  Future<void> loadHubEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _hubEnabled = prefs.getBool(_kHubEnabledKey) ?? false;
    _directoryOnboardingSeen =
        prefs.getBool(_kDirectoryOnboardingSeenKey) ?? false;
    notifyListeners();
  }

  /// Enable or disable the hub directory feature.
  Future<void> setHubEnabled(bool value) async {
    _hubEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHubEnabledKey, value);
    notifyListeners();
  }

  /// Called when the user dismisses the first-time Discover banner.
  Future<void> markDirectoryOnboardingSeen() async {
    _directoryOnboardingSeen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDirectoryOnboardingSeenKey, true);
    notifyListeners();
  }

  /// Subscribe to relay nudges so directory data refreshes in near-real-time.
  ///
  /// Called once after [initAndSyncCatalog] succeeds. Each nudge triggers a
  /// lightweight refresh of pending follow requests and incoming borrow
  /// requests (the two time-sensitive lists). Does NOT re-fetch the catalog
  /// or full directory listing (those are user-driven).
  void _subscribeNudgeStream() {
    _nudgeSub?.cancel();
    try {
      _nudgeSub = subscribeRelayNudges().listen(
        _onNudgeEvent,
        onError: (Object e) {
          debugPrint('HubDirectoryProvider: nudge stream error: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider: failed to subscribe to nudge stream: $e');
    }
  }

  void _onNudgeEvent(FrbNudgeEvent _) {
    if (!_hubEnabled || !isRegistered) return;
    // Silently refresh the two lists that carry incoming actions.
    loadPendingRequests();
    _silentRefreshIncomingBorrow();
  }

  Future<void> _silentRefreshIncomingBorrow() async {
    try {
      final raw = await _ffi.hubDirectoryIncomingBorrowRequests();
      _incomingHubRequests = raw;
      notifyListeners();
    } catch (e) {
      debugPrint('HubDirectoryProvider: silent borrow refresh error: $e');
    }
  }

  @override
  void dispose() {
    _nudgeSub?.cancel();
    _catalogSyncDebounce?.cancel();
    _contactSyncDebounce?.cancel();
    super.dispose();
  }

  // ── Local contact info ─────────────────────────────────────────────────

  String _contactInfo = '';

  String get contactInfo => _contactInfo;

  Future<void> loadContactInfo() async {
    final prefs = await SharedPreferences.getInstance();
    _contactInfo = prefs.getString(_kContactInfoKey) ?? '';
    notifyListeners();
  }

  Timer? _contactSyncDebounce;

  Future<void> setContactInfo(String value) async {
    _contactInfo = _sanitizeContact(value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kContactInfoKey, _contactInfo);
    notifyListeners();

    // Debounce: sync encrypted blobs to followers 3s after last edit
    _contactSyncDebounce?.cancel();
    _contactSyncDebounce = Timer(const Duration(seconds: 3), () {
      syncContactToFollowers();
    });
  }

  // ── Local website URL ───────────────────────────────────────────────────

  String _websiteUrl = '';

  String get websiteUrl => _websiteUrl;

  Future<void> loadWebsite() async {
    final prefs = await SharedPreferences.getInstance();
    _websiteUrl = prefs.getString(_kWebsiteKey) ?? '';
    notifyListeners();
  }

  Future<void> setWebsite(String value) async {
    _websiteUrl = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebsiteKey, value);
    notifyListeners();
  }

  // ── Config ───────────────────────────────────────────────────────────────

  DirectoryConfig? _config;
  bool _configLoading = false;
  String? _configError;

  // ── 401 back-off state ──────────────────────────────────────────────────
  int _consecutive401Count = 0;
  DateTime? _last401At;

  /// Cooldown durations for consecutive 401 failures: 1 min, 5 min, 15 min.
  static const _cooldown401Minutes = [1, 5, 15];

  /// True when a recent 401 failure means we should wait before retrying.
  bool get _isIn401Cooldown {
    if (_consecutive401Count == 0 || _last401At == null) return false;
    final idx = (_consecutive401Count - 1).clamp(0, _cooldown401Minutes.length - 1);
    final cooldown = Duration(minutes: _cooldown401Minutes[idx]);
    return DateTime.now().difference(_last401At!) < cooldown;
  }

  /// Number of consecutive 401 failures (exposed for UI/dialog decisions).
  int get consecutive401Count => _consecutive401Count;

  // ── Keychain backup/recovery state ──────────────────────────────────────
  bool _keychainBackupPending = false;

  /// True when the current config was recovered from Keychain (not from
  /// a fresh hub registration).  If the first hub call after recovery returns
  /// 401, we purge both config + Keychain and retry immediately without
  /// incrementing the backoff counter.
  bool _tokenRecoveredFromKeychain = false;

  /// Attempts to back up the hub write_token to Keychain.
  /// Returns true on success, false on failure (logged, never throws).
  Future<bool> _tryBackupWriteToken() async {
    try {
      final token = await _ffi.hubDirectoryExportWriteToken();
      if (token == null) return false;
      await _authService.saveHubWriteToken(token);
      return true;
    } catch (e) {
      debugPrint(
        'HubDirectoryProvider: write_token Keychain backup FAILED: $e. '
        'Will retry on next profile update.',
      );
      return false;
    }
  }

  /// Backs up the hub recovery_code to Keychain if available.
  /// The recovery_code is the ONLY way to reclaim a profile when the
  /// write_token is invalidated, so we must not lose it on config purges.
  Future<void> _tryBackupRecoveryCode() async {
    try {
      final code = await _ffi.hubDirectoryGetRecoveryCode();
      if (code != null && code.isNotEmpty) {
        await _authService.saveHubRecoveryCode(code);
      }
    } catch (e) {
      debugPrint('HubDirectoryProvider: recovery_code Keychain backup FAILED: $e');
    }
  }

  DirectoryConfig? get config => _config;
  bool get configLoading => _configLoading;
  String? get configError => _configError;
  bool get isRegistered => _config != null;
  bool get isListed => _config?.isListed ?? false;

  // ── Directory listing ─────────────────────────────────────────────────────

  List<HubProfile> _profiles = [];
  bool _listLoading = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _listError;
  String? _searchQuery;

  List<HubProfile> get profiles => _profiles;
  bool get listLoading => _listLoading;
  bool get hasMore => _hasMore;
  String? get listError => _listError;
  String? get searchQuery => _searchQuery;

  // ── Follow relationships ──────────────────────────────────────────────────

  List<HubFollow> _following = [];
  List<HubFollow> _followers = [];
  List<HubFollow> _pendingRequests = [];

  List<HubFollow> get following => _following;
  List<HubFollow> get followers => _followers;
  List<HubFollow> get pendingRequests => _pendingRequests;

  /// Number of pending incoming follow requests - used for badge.
  int get pendingCount => _pendingRequests.length;

  // ── Relay publish state ─────────────────────────────────────────────────

  /// Whether relay credentials have been successfully published to the hub.
  bool _relayPublished = false;

  /// Timestamp of the last relay publish attempt (success or failure).
  /// Used to enforce [_kRelayPublishCooldown] between periodic retries.
  DateTime? _lastRelayAttempt;

  // ── Hub borrow requests (ADR-018) ──────────────────────────────────────

  List<frb.FrbHubBorrowRequest> _incomingHubRequests = [];
  List<frb.FrbHubBorrowRequest> _outgoingHubRequests = [];

  /// IDs of hub borrow requests dismissed locally (non-pending, can't cancel on Hub).
  final Set<int> _dismissedHubRequestIds = {};

  List<frb.FrbHubBorrowRequest> get incomingHubRequests =>
      _incomingHubRequests.where((r) => !_dismissedHubRequestIds.contains(r.id.toInt())).toList();
  List<frb.FrbHubBorrowRequest> get outgoingHubRequests =>
      _outgoingHubRequests.where((r) => !_dismissedHubRequestIds.contains(r.id.toInt())).toList();

  /// Number of pending incoming hub borrow requests - used for badge.
  int get pendingHubBorrowCount =>
      _incomingHubRequests.where((r) => r.status == 'pending').length;

  // ── Name cache ──────────────────────────────────────────────────────────

  /// nodeId -> display name, populated lazily from hub profile lookups.
  final Map<String, String> _nameCache = {};

  /// nodeId -> parsed AvatarConfig, populated alongside _nameCache.
  final Map<String, AvatarConfig> _avatarCache = {};

  /// Re-fetch a single node's display name from the hub and update the cache.
  Future<void> refreshName(String nodeId) async {
    try {
      final profile = await _ffi.hubDirectoryGetProfile(nodeId);
      if (profile != null) {
        _nameCache[nodeId] = profile.displayName;
        _cacheAvatar(nodeId, profile.avatarConfig);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('HubDirectoryProvider refreshName($nodeId): $e');
    }
  }

  /// Clear the auto-resolved name cache so the next [loadFollowing] re-fetches
  /// all names from the hub. Does NOT clear user-custom names.
  void invalidateNameCache() {
    _nameCache.clear();
    _avatarCache.clear();
  }

  /// Parse and cache an avatar_config JSON string for a node.
  void _cacheAvatar(String nodeId, String? avatarConfigJson) {
    if (avatarConfigJson == null || avatarConfigJson.isEmpty) return;
    try {
      final parsed = AvatarConfig.fromJson(
        jsonDecode(avatarConfigJson) as Map<String, dynamic>,
      );
      _avatarCache[nodeId] = parsed;
    } catch (_) {}
  }

  /// Returns the cached hub avatar for [nodeId], if available.
  AvatarConfig? avatarConfigFor(String nodeId) => _avatarCache[nodeId];

  // ── Catalog sync ────────────────────────────────────────────────────────

  /// True when the local book list has changed since the last catalog push.
  bool _catalogDirty = true;

  bool get catalogDirty => _catalogDirty;

  /// Debounce timer for auto-pushing catalog after book changes.
  Timer? _catalogSyncDebounce;

  // ── Action state ──────────────────────────────────────────────────────────

  /// Node IDs currently being processed (per-item loading).
  final Set<String> _busyNodes = {};
  String? _actionError;

  bool isBusy(String nodeId) => _busyNodes.contains(nodeId);
  bool get actionInProgress => _busyNodes.isNotEmpty;
  String? get actionError => _actionError;

  // ---------------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------------

  /// Load the local config from SQLite. Call once at app start / settings open.
  /// Load config, auto-register if needed, push catalog.
  /// Called at app startup so the catalog is always available for known peers.
  /// Re-entrant safe: concurrent callers are ignored (not queued).
  bool _initSyncing = false;

  Future<void> initAndSyncCatalog() async {
    if (_initSyncing) {
      debugPrint('HubDirectory: initAndSyncCatalog already running, skip');
      return;
    }
    _initSyncing = true;
    try {
      debugPrint('HubDirectory: initAndSyncCatalog starting');
      await loadConfig();
      debugPrint('HubDirectory: config loaded, isRegistered=$isRegistered');
      if (!isRegistered) {
        debugPrint('HubDirectory: not registered, auto-registering...');
        await ensureRegistered();
        debugPrint('HubDirectory: after ensureRegistered, isRegistered=$isRegistered');
      }
      if (isRegistered) {
        // Ensure relay credentials are published on the hub profile.
        // Fixes ~50% of installs where relay was missing due to race condition
        // or ensureKeysPublished overwriting without relay params.
        await ensureRelayPublished();
        syncCatalogIfDirty();
        // Start listening for relay nudges so incoming follow/borrow events
        // refresh instantly instead of waiting for the next polling cycle.
        _subscribeNudgeStream();
      }
    } catch (e) {
      debugPrint('HubDirectory: initAndSyncCatalog error: $e');
    } finally {
      _initSyncing = false;
    }
  }

  /// Re-registers with relay credentials if the local relay config is available.
  /// This repairs hub profiles that were registered without relay (race condition
  /// at first launch or ensureKeysPublished overwrite).
  /// All profile fields are passed to avoid hub overwriting them with null
  /// (hub uses array_key_exists for device_model, relay_url, etc.).
  ///
  /// Retries up to [_kRelayPublishMaxAttempts] times with a delay between
  /// attempts to handle transient network failures (5G, tunnel, etc.).
  Future<void> ensureRelayPublished() async {
    if (_config == null) return;
    // Read relay credentials upfront to check availability.
    final initialRelay = await _getRelayCredentials();
    if (initialRelay.relayUrl == null) {
      if (kDebugMode) debugPrint('HubDirectory: no local relay config, skip relay publish');
      return;
    }

    _lastRelayAttempt = DateTime.now();
    for (var attempt = 1; attempt <= _kRelayPublishMaxAttempts; attempt++) {
      // Re-read credentials and profile data on each attempt so that a
      // concurrent settings change (user connects a new relay mid-retry)
      // is picked up immediately instead of publishing stale values.
      final relay = await _getRelayCredentials();
      if (relay.relayUrl == null) return; // relay removed between attempts
      final cfg = _config!;
      final prefs = await SharedPreferences.getInstance();
      final libraryName = prefs.getString('libraryName') ??
          TranslationService.translateByLocale(
              prefs.getString('languageCode') ?? 'en', 'my_library_title');
      final bookCount = await _ffi.countBooks();
      String? x25519Key;
      try {
        x25519Key = await _ffi.getLocalX25519PublicKey();
      } catch (_) {}
      final deviceModel = await _deviceService.getDeviceModel();
      final deviceFingerprint = await _deviceService.getDeviceFingerprint();
      final appVersion = await _deviceService.getAppVersion();

      if (kDebugMode) {
        debugPrint('HubDirectory: publishing relay credentials to hub '
            '(attempt $attempt/$_kRelayPublishMaxAttempts)');
      }
      final ok = await register(
        nodeId: cfg.nodeId,
        displayName: libraryName,
        bookCount: bookCount,
        isListed: cfg.isListed,
        requiresApproval: cfg.requiresApproval,
        acceptFrom: cfg.acceptFrom,
        allowBorrowing: cfg.allowBorrowing,
        x25519PublicKey: x25519Key,
        deviceModel: deviceModel,
        deviceFingerprint: deviceFingerprint,
        appVersion: appVersion,
        relayUrl: relay.relayUrl,
        relayMailboxId: relay.mailboxId,
        relayWriteToken: relay.writeToken,
      );
      if (ok) {
        _relayPublished = true;
        debugPrint('HubDirectory: relay credentials published successfully');
        return;
      }
      // 401 = auth problem, retrying won't help (and would triple-penalize
      // the consecutive401Count backoff counter).
      if (_configError != null && _configError!.contains('Hub error 401:')) {
        debugPrint('HubDirectory: relay publish got 401, aborting retries');
        return;
      }
      // Don't delay after the last failed attempt
      if (attempt < _kRelayPublishMaxAttempts) {
        debugPrint('HubDirectory: relay publish failed, retrying in '
            '${relayRetryDelay.inSeconds}s...');
        await Future.delayed(relayRetryDelay);
      }
    }
    debugPrint('HubDirectory: relay publish failed after '
        '$_kRelayPublishMaxAttempts attempts, will retry on next catalog sync');
  }

  Future<void> loadConfig() async {
    _configLoading = true;
    _configError = null;
    notifyListeners();

    try {
      var frbConfig = await _ffi.hubDirectoryGetConfig();
      // Post-reinstall recovery: SQLite is gone but Keychain survives (iOS).
      // Restore the write_token so the next register() can authenticate.
      frbConfig ??= await _tryRecoverFromKeychain();
      _config =
          frbConfig != null ? DirectoryConfig.fromFrb(frbConfig) : null;

      // Backfill: existing users registered before the Keychain-backup fix
      // may have a recovery_code in SQLite but not in Keychain.  Copy it
      // over on first run so future purges don't lose it.
      if (_config != null) {
        final keychainCode = await _authService.getHubRecoveryCode();
        if (keychainCode == null || keychainCode.isEmpty) {
          await _tryBackupRecoveryCode();
        }
      }
    } catch (e) {
      _configError = e.toString();
      debugPrint('HubDirectoryProvider loadConfig error: $e');
    } finally {
      _configLoading = false;
      notifyListeners();
    }
  }

  /// Attempts to restore hub config from Keychain after a reinstall.
  /// Returns the restored config if successful, null otherwise.
  Future<frb.FrbDirectoryConfig?> _tryRecoverFromKeychain() async {
    try {
      final writeToken = await _authService.getHubWriteToken();
      if (writeToken == null) return null;

      final nodeId = await _authService.getOrCreateLibraryUuid();
      final ok = await _ffi.hubDirectoryImportWriteToken(
        nodeId: nodeId,
        writeToken: writeToken,
      );
      if (!ok) return null;

      debugPrint('HubDirectoryProvider: recovered write_token from Keychain');
      _tokenRecoveredFromKeychain = true;
      return await _ffi.hubDirectoryGetConfig();
    } catch (e) {
      debugPrint('HubDirectoryProvider: Keychain recovery failed: $e');
      return null;
    }
  }

  /// Read the local avatar config JSON string from SharedPreferences.
  Future<String?> _getLocalAvatarConfigJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('avatarConfig');
  }

  /// Read relay credentials from local SQLite (single source of truth).
  /// Returns (relayUrl, mailboxId, writeToken), all nullable.
  Future<({String? relayUrl, String? mailboxId, String? writeToken})>
      _getRelayCredentials() async {
    try {
      final relayConfig = await _ffi.getRelayConfig();
      if (relayConfig != null) {
        return (
          relayUrl: relayConfig.relayUrl,
          mailboxId: relayConfig.mailboxUuid,
          writeToken: relayConfig.writeToken,
        );
      }
    } catch (_) {}
    return (relayUrl: null, mailboxId: null, writeToken: null);
  }

  /// Re-registers with the current config to ensure the X25519 public key
  /// and relay credentials are published on the hub profile.
  Future<void> ensureKeysPublished(String displayName) async {
    if (!_hubEnabled) return;
    if (_config == null) {
      debugPrint('[CONTACT-SYNC] ensureKeysPublished: config is null, skip');
      return;
    }
    final cfg = _config!;

    String? x25519Key;
    try {
      x25519Key = await _ffi.getLocalX25519PublicKey();
    } catch (_) {}
    if (x25519Key == null || x25519Key.isEmpty) {
      debugPrint('[CONTACT-SYNC] ensureKeysPublished: no local X25519 key, skip');
      return;
    }
    debugPrint('[CONTACT-SYNC] ensureKeysPublished: key=${x25519Key.substring(0, 8)}..., registering');

    final bookCount = await _ffi.countBooks();
    final deviceModel = await _deviceService.getDeviceModel();
    final deviceFingerprint = await _deviceService.getDeviceFingerprint();
    final appVersion = await _deviceService.getAppVersion();
    final relay = await _getRelayCredentials();
    await register(
      nodeId: cfg.nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: cfg.isListed,
      requiresApproval: cfg.requiresApproval,
      acceptFrom: cfg.acceptFrom,
      allowBorrowing: cfg.allowBorrowing,
      x25519PublicKey: x25519Key,
      website: _websiteUrl.isNotEmpty ? _websiteUrl : null,
      deviceModel: deviceModel,
      deviceFingerprint: deviceFingerprint,
      appVersion: appVersion,
      relayUrl: relay.relayUrl,
      relayMailboxId: relay.mailboxId,
      relayWriteToken: relay.writeToken,
    );
    if (relay.relayUrl != null) _relayPublished = true;
    if (kDebugMode) debugPrint('HubDirectoryProvider: ensured keys + relay published');

    // Now that our key is on the hub, sync contact blobs to followers
    if (_contactInfo.isNotEmpty) {
      await syncContactToFollowers();
    }
  }

  /// Whether borrowing is enabled in the current config.
  bool get allowBorrowing => _config?.allowBorrowing ?? true;

  Future<bool> register({
    required String nodeId,
    required String displayName,
    required int bookCount,
    required bool isListed,
    required bool requiresApproval,
    required String acceptFrom,
    required bool allowBorrowing,
    String? description,
    String? locationCountry,
    String? x25519PublicKey,
    String? website,
    String? deviceModel,
    String? deviceFingerprint,
    String? appVersion,
    String? relayUrl,
    String? relayMailboxId,
    String? relayWriteToken,
    String? avatarConfig,
  }) async {
    _configLoading = true;
    _configError = null;
    notifyListeners();

    // Retry a previously failed Keychain backup before making a new hub call.
    if (_keychainBackupPending) {
      if (await _tryBackupWriteToken()) {
        _keychainBackupPending = false;
        debugPrint('HubDirectoryProvider: pending Keychain backup succeeded');
      }
    }

    // Build params before try/catch so they're accessible in the 401 retry.
    final effectiveModel = deviceModel ?? await _deviceService.getDeviceModel();
    final effectiveFp = deviceFingerprint ?? await _deviceService.getDeviceFingerprint();
    final effectiveAppVersion = appVersion ?? await _deviceService.getAppVersion();
    final effectiveAvatar = avatarConfig ?? await _getLocalAvatarConfigJson();

    final params = frb.FrbRegisterParams(
      nodeId: nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: isListed,
      requiresApproval: requiresApproval,
      acceptFrom: acceptFrom,
      allowBorrowing: allowBorrowing,
      description: description,
      locationCountry: locationCountry,
      x25519PublicKey: x25519PublicKey,
      website: website,
      deviceModel: effectiveModel,
      deviceFingerprint: effectiveFp,
      appVersion: effectiveAppVersion,
      relayUrl: relayUrl,
      relayMailboxId: relayMailboxId,
      relayWriteToken: relayWriteToken,
      avatarConfig: effectiveAvatar,
    );

    try {
      final result = await _ffi.hubDirectoryRegister(params);
      if (result != null) {
        _config = DirectoryConfig.fromFrb(result);
        // Registration succeeded: reset 401 back-off and recovery state.
        _consecutive401Count = 0;
        _last401At = null;
        _tokenRecoveredFromKeychain = false;
        // Back up write_token to Keychain for reinstall recovery.
        _keychainBackupPending = !await _tryBackupWriteToken();
        await _tryBackupRecoveryCode();
        return true;
      }
      return false;
    } catch (e) {
      _configError = e.toString();
      // 401 recovery: the stored write_token is invalid on the hub.
      // Purge stale config + Keychain, then retry fresh (without auth).
      if (e.toString().contains('Hub error 401:')) {
        // Allow immediate retry on first 401, or when the token was
        // recovered from Keychain (likely stale after a config purge).
        final shouldRetry =
            _consecutive401Count == 0 || _tokenRecoveredFromKeychain;
        if (shouldRetry) {
          // Before purging, try to reclaim the profile with the stored
          // recovery_code. This preserves the node_id and profile on the hub,
          // which is the only way if the hub already knows our node_id.
          final nodeId = _config?.nodeId ?? params.nodeId;
          // Try SQLite first, fall back to Keychain (config may have been purged).
          final recoveryCode = await _ffi.hubDirectoryGetRecoveryCode() ??
              await _authService.getHubRecoveryCode();
          if (recoveryCode != null && recoveryCode.isNotEmpty) {
            debugPrint(
              'HubDirectoryProvider: 401 detected, attempting recovery with stored code',
            );
            try {
              final recovered = await _ffi.hubDirectoryRecover(
                nodeId: nodeId,
                recoveryCode: recoveryCode,
              );
              if (recovered != null) {
                _config = DirectoryConfig.fromFrb(recovered);
                _consecutive401Count = 0;
                _last401At = null;
                _tokenRecoveredFromKeychain = false;
                _keychainBackupPending = !await _tryBackupWriteToken();
        await _tryBackupRecoveryCode();
                _configError = null;
                debugPrint('HubDirectoryProvider: 401 recovery via recovery_code succeeded');
                return true;
              }
            } catch (recoverErr) {
              debugPrint(
                'HubDirectoryProvider: recovery_code attempt failed: $recoverErr',
              );
              // Fall through to purge+retry
            }
          }

          debugPrint(
            'HubDirectoryProvider: 401 detected, purging stale config '
            'and retrying fresh registration'
            '${_tokenRecoveredFromKeychain ? ' (Keychain recovery)' : ''}',
          );
          await _ffi.hubDirectoryPurgeConfig();
          await _authService.deleteHubWriteToken();
          _config = null;
          _tokenRecoveredFromKeychain = false;
          // Retry once: without local config, Rust sends no Bearer token
          // and the hub issues a fresh write_token.
          try {
            final retryResult = await _ffi.hubDirectoryRegister(params);
            if (retryResult != null) {
              _config = DirectoryConfig.fromFrb(retryResult);
              _consecutive401Count = 0;
              _last401At = null;
              _keychainBackupPending = !await _tryBackupWriteToken();
        await _tryBackupRecoveryCode();
              _configError = null;
              debugPrint('HubDirectoryProvider: 401 recovery succeeded');
              return true;
            }
          } catch (retryErr) {
            debugPrint(
              'HubDirectoryProvider: 401 recovery retry failed: $retryErr',
            );
          }
        }
        _consecutive401Count++;
        _last401At = DateTime.now();
        debugPrint(
          'HubDirectoryProvider: 401 failure #$_consecutive401Count, '
          'next retry after ${_cooldown401Minutes[(_consecutive401Count - 1).clamp(0, _cooldown401Minutes.length - 1)]} min',
        );
      }
      debugPrint('HubDirectoryProvider register error: $e');
      return false;
    } finally {
      _configLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Directory listing
  // ---------------------------------------------------------------------------

  /// Load the first page of the directory. Resets existing results.
  Future<void> loadDirectory({String? search}) async {
    _profiles = [];
    _offset = 0;
    _hasMore = true;
    _listError = null;
    _searchQuery = (search != null && search.trim().isNotEmpty) ? search.trim() : null;
    await _fetchNextPage();
  }

  /// Load the next page (infinite scroll).
  Future<void> loadMoreDirectory() async {
    if (_listLoading || !_hasMore) return;
    await _fetchNextPage();
  }

  Future<void> _fetchNextPage() async {
    _listLoading = true;
    _listError = null;
    notifyListeners();

    try {
      final batch = await _ffi.hubDirectoryList(
        limit: _kPageSize,
        offset: _offset,
        search: _searchQuery,
      );
      final ownNodeId = _config?.nodeId;
      final rawCount = batch.length;
      final newProfiles = batch
          .map(HubProfile.fromFrb)
          .where((p) => p.nodeId != ownNodeId)
          .toList();
      _profiles.addAll(newProfiles);
      // Offset and hasMore are based on the raw (server-side) count so that
      // filtering our own profile does not cause premature pagination stop.
      _offset += rawCount;
      _hasMore = rawCount == _kPageSize;
    } catch (e) {
      _listError = e.toString();
      debugPrint('HubDirectoryProvider _fetchNextPage error: $e');
    } finally {
      _listLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Follow / unfollow
  // ---------------------------------------------------------------------------

  /// Register silently with is_listed=false to obtain a write_token
  /// without appearing in the public directory. This allows following
  /// other libraries without being listed.
  Future<bool> _ensureSilentRegistration() async {
    try {
      final libraryUuid = await _authService.getOrCreateLibraryUuid();
      final prefs = await SharedPreferences.getInstance();
      final libraryName = prefs.getString('libraryName') ??
          TranslationService.translateByLocale(
              prefs.getString('languageCode') ?? 'en', 'my_library_title');
      final bookCount = await _ffi.countBooks();

      String? x25519Key;
      try {
        x25519Key = await _ffi.getLocalX25519PublicKey();
      } catch (_) {}

      final deviceModel = await _deviceService.getDeviceModel();
      final deviceFingerprint = await _deviceService.getDeviceFingerprint();
      final appVersion = await _deviceService.getAppVersion();

      final relay = await _getRelayCredentials();

      return await register(
        nodeId: libraryUuid,
        displayName: libraryName,
        bookCount: bookCount,
        isListed: false,
        requiresApproval: false,
        acceptFrom: 'anyone',
        allowBorrowing: false,
        x25519PublicKey: x25519Key,
        deviceModel: deviceModel,
        deviceFingerprint: deviceFingerprint,
        appVersion: appVersion,
        relayUrl: relay.relayUrl,
        relayMailboxId: relay.mailboxId,
        relayWriteToken: relay.writeToken,
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider _ensureSilentRegistration error: $e');
      return false;
    }
  }

  /// Auto-register with is_listed=false if not yet registered.
  /// Enables catalog push for known peers without public listing.
  /// Skips silently when in 401 cooldown to avoid hammering the hub.
  Future<bool> ensureRegistered() async {
    if (isRegistered) return true;
    if (_isIn401Cooldown) {
      debugPrint('HubDirectory: ensureRegistered skipped (401 cooldown)');
      return false;
    }
    final ok = await _ensureSilentRegistration();
    if (ok) await loadConfig();
    return ok;
  }

  /// Enable the hub directory feature AND publish the library publicly.
  ///
  /// Designed for the "Appear in the directory" CTA banner in the Discover
  /// tab, where a browsing user can opt in without going through Settings.
  ///
  /// Steps (atomic from the user's perspective):
  ///  1. [setHubEnabled](true) — unlocks hub features locally.
  ///  2. Register on the hub with `isListed: true` (re-uses 401 recovery).
  ///  3. Publish relay credentials so followers can reach us.
  ///  4. Push the ISBN catalog so new followers see books immediately.
  ///  5. Subscribe to the relay nudge stream for real-time updates.
  ///
  /// Returns `true` when the hub register succeeded. Catalog push + relay
  /// publish happen best-effort on success (same pattern as
  /// [initAndSyncCatalog]) — they retry automatically via the existing
  /// sync cycle if they fail.
  Future<bool> enableAndPublish({
    required String displayName,
    String? locationCountry,
  }) async {
    // Flip the local flag first so even if register() hits the network
    // cooldown, the UI reflects the user's intent immediately.
    await setHubEnabled(true);

    final nodeId =
        _config?.nodeId ?? await _authService.getOrCreateLibraryUuid();
    final bookCount = await _ffi.countBooks();

    String? x25519PublicKey;
    try {
      x25519PublicKey = await _ffi.getLocalX25519PublicKey();
    } catch (_) {}

    final relay = await _getRelayCredentials();
    final deviceModel = await _deviceService.getDeviceModel();
    final deviceFingerprint = await _deviceService.getDeviceFingerprint();
    final appVersion = await _deviceService.getAppVersion();

    final trimmedCountry = locationCountry?.trim();

    final ok = await register(
      nodeId: nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: true,
      requiresApproval: _config?.requiresApproval ?? false,
      acceptFrom: _config?.acceptFrom ?? 'everyone',
      allowBorrowing: _config?.allowBorrowing ?? true,
      locationCountry:
          (trimmedCountry != null && trimmedCountry.isNotEmpty)
              ? trimmedCountry
              : null,
      x25519PublicKey: x25519PublicKey,
      website: _websiteUrl.isNotEmpty ? _websiteUrl : null,
      deviceModel: deviceModel,
      deviceFingerprint: deviceFingerprint,
      appVersion: appVersion,
      relayUrl: relay.relayUrl,
      relayMailboxId: relay.mailboxId,
      relayWriteToken: relay.writeToken,
    );

    if (ok) {
      if (relay.relayUrl != null) _relayPublished = true;
      // Push the catalog so new followers can browse immediately.
      // Await so the CTA loading indicator stays visible until the
      // library is fully discoverable.
      await syncCatalog();
      // Subscribe to relay nudges for real-time follow/borrow events.
      _subscribeNudgeStream();
    }
    return ok;
  }

  /// Returns the locally stored recovery code for display in settings.
  Future<String?> getRecoveryCode() async {
    return await _ffi.hubDirectoryGetRecoveryCode();
  }

  /// Formats a raw 12-char recovery code as XXXX-XXXX-XXXX for display.
  static String formatRecoveryCode(String code) {
    final clean = code.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    if (clean.length != 12) return clean;
    return '${clean.substring(0, 4)}-${clean.substring(4, 8)}-${clean.substring(8, 12)}';
  }

  /// Recovers a hub profile using a one-time recovery code.
  /// On success: reloads config, resets 401 state, backs up token to Keychain.
  Future<bool> recoverWithCode(String nodeId, String recoveryCode) async {
    _configLoading = true;
    _configError = null;
    notifyListeners();

    try {
      final result = await _ffi.hubDirectoryRecover(
        nodeId: nodeId,
        recoveryCode: recoveryCode,
      );
      if (result != null) {
        _config = DirectoryConfig.fromFrb(result);
        _consecutive401Count = 0;
        _last401At = null;
        _tokenRecoveredFromKeychain = false;
        _keychainBackupPending = !await _tryBackupWriteToken();
        await _tryBackupRecoveryCode();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _configError = e.toString();
      debugPrint('HubDirectoryProvider recoverWithCode error: $e');
      return false;
    } finally {
      _configLoading = false;
      notifyListeners();
    }
  }

  /// Follow (or request to follow) a library identified by [nodeId].
  /// Updates the following list on success.
  Future<bool> follow(String nodeId) async {
    _busyNodes.add(nodeId);
    _actionError = null;
    notifyListeners();

    try {
      // Auto-register with is_listed=false if not yet registered
      if (_config == null) {
        final ok = await _ensureSilentRegistration();
        if (!ok) {
          _actionError = 'Registration failed';
          return false;
        }
      }

      final result = await _ffi.hubDirectoryFollow(nodeId);
      if (result != null) {
        await loadFollowing();
        return true;
      }
      _actionError = 'Follow request failed';
      debugPrint('HubDirectoryProvider follow: result was null for $nodeId');
      return false;
    } catch (e) {
      _actionError = e.toString();
      debugPrint('HubDirectoryProvider follow error: $e');
      return false;
    } finally {
      _busyNodes.remove(nodeId);
      notifyListeners();
    }
  }

  /// Unfollow a library identified by [nodeId].
  Future<bool> unfollow(String nodeId) async {
    _busyNodes.add(nodeId);
    _actionError = null;
    notifyListeners();

    try {
      final ok = await _ffi.hubDirectoryUnfollow(nodeId);
      if (ok) await loadFollowing();
      return ok;
    } catch (e) {
      _actionError = e.toString();
      debugPrint('HubDirectoryProvider unfollow error: $e');
      return false;
    } finally {
      _busyNodes.remove(nodeId);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Follow relationships
  // ---------------------------------------------------------------------------

  Future<void> loadFollowing() async {
    try {
      final raw = await _ffi.hubDirectoryListFollowing();
      _following = raw.map(HubFollow.fromFrb).toList();
      debugPrint('[CONTACT-READ] loadFollowing: ${_following.length} follows');
      for (final f in _following) {
        debugPrint('[CONTACT-READ]   follow id=${f.id} node=${f.followedNodeId.substring(0, 8)}... '
            'contact=${f.encryptedContact != null ? "${f.encryptedContact!.length}ch" : "null"}');
      }
      _resolveNames(
        _following.map((f) => f.followedNodeId).toList(),
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider loadFollowing error: $e');
    }
    notifyListeners();
  }

  Future<void> loadFollowers() async {
    try {
      final raw = await _ffi.hubDirectoryListFollowers();
      _followers = raw.map(HubFollow.fromFrb).toList();
      _resolveNames(
        _followers.map((f) => f.followerNodeId).toList(),
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider loadFollowers error: $e');
    }
    notifyListeners();
  }

  /// Load pending incoming follow requests (badge count).
  Future<void> loadPendingRequests() async {
    try {
      final raw = await _ffi.hubDirectoryPendingRequests();
      _pendingRequests = raw.map(HubFollow.fromFrb).toList();
      _resolveNames(
        _pendingRequests.map((f) => f.followerNodeId).toList(),
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider loadPendingRequests error: $e');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Incoming request resolution
  // ---------------------------------------------------------------------------

  /// Approve or reject an incoming follow request.
  ///
  /// [resolution]: "approve", "reject", or "block"
  /// Approve or reject an incoming follow request.
  ///
  /// [resolution]: "approve", "reject", or "block"
  /// [encryptedContact]: optional sealed blob to attach when approving
  Future<bool> resolveFollow(int followId, String resolution, {String? encryptedContact}) async {
    final key = 'resolve_$followId';
    _busyNodes.add(key);
    _actionError = null;
    notifyListeners();

    try {
      final result =
          await _ffi.hubDirectoryResolveFollow(followId, resolution, encryptedContact: encryptedContact);
      if (result != null) {
        // Refresh pending list and followers after resolution.
        await Future.wait([loadPendingRequests(), loadFollowers()]);
        return true;
      }
      return false;
    } catch (e) {
      _actionError = e.toString();
      debugPrint('HubDirectoryProvider resolveFollow error: $e');
      return false;
    } finally {
      _busyNodes.remove(key);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Catalog sync
  // ---------------------------------------------------------------------------

  /// Mark the catalog as needing a push to the hub.
  /// Call this after a book is added or deleted.
  /// Automatically triggers a debounced push (5s) so followers see
  /// the updated catalog without waiting for an app resume cycle.
  void markCatalogDirty() {
    _catalogDirty = true;
    _catalogSyncDebounce?.cancel();
    _catalogSyncDebounce = Timer(const Duration(seconds: 5), () {
      syncCatalogIfDirty();
    });
  }

  /// Push the full ISBN catalog to the hub.
  /// Returns the number of ISBNs pushed, or -1 on error.
  Future<int> syncCatalog() async {
    if (!isRegistered) return 0;
    try {
      final count = await _ffi.hubDirectorySyncCatalog();
      if (count >= 0) _catalogDirty = false;
      debugPrint('HubDirectoryProvider syncCatalog: pushed $count ISBNs');
      return count;
    } catch (e) {
      debugPrint('HubDirectoryProvider syncCatalog error: $e');
      return -1;
    }
  }

  /// Push catalog only if dirty and registered. Intended for lifecycle hooks.
  /// Also retries relay credential publishing if it failed at startup.
  Future<void> syncCatalogIfDirty() async {
    // Push catalog when registered, regardless of isListed.
    // isListed controls discoverability by strangers; catalog push enables
    // browsing by known peers who have the nodeId (via invite link).
    if (!isRegistered) return;

    // Retry relay publish if it failed during startup (network instability).
    // Enforces a cooldown to avoid hammering the hub every 30s.
    if (!_relayPublished) {
      final last = _lastRelayAttempt;
      if (last == null ||
          DateTime.now().difference(last) >= relayCooldown) {
        await ensureRelayPublished();
      }
    }

    if (!_catalogDirty) return;
    await syncCatalog();
  }

  // ---------------------------------------------------------------------------
  // Hub borrow requests (ADR-018)
  // ---------------------------------------------------------------------------

  /// Create a borrow request via the hub.
  /// Throws on error so the caller can show the error message.
  Future<bool> createBorrowRequest(
    String lenderNodeId,
    String isbn,
    String bookTitle,
  ) async {
    try {
      await _ffi.hubDirectoryCreateBorrowRequest(
        lenderNodeId,
        isbn,
        bookTitle,
      );
      return true;
    } catch (e) {
      debugPrint('HubDirectoryProvider createBorrowRequest error: $e');
      rethrow;
    }
  }

  /// Load incoming hub borrow requests (as lender).
  Future<void> loadIncomingHubRequests() async {
    try {
      _incomingHubRequests =
          await _ffi.hubDirectoryIncomingBorrowRequests();
    } catch (e) {
      debugPrint('HubDirectoryProvider loadIncomingHubRequests error: $e');
    }
    notifyListeners();
  }

  /// Load outgoing hub borrow requests (as requester).
  Future<void> loadOutgoingHubRequests() async {
    try {
      _outgoingHubRequests =
          await _ffi.hubDirectoryOutgoingBorrowRequests();
    } catch (e) {
      debugPrint('HubDirectoryProvider loadOutgoingHubRequests error: $e');
    }
    notifyListeners();
  }

  /// Accept or reject a hub borrow request.
  Future<bool> resolveHubBorrowRequest(int requestId, String resolution) async {
    final key = 'hub_borrow_$requestId';
    _busyNodes.add(key);
    _actionError = null;
    notifyListeners();

    try {
      await _ffi.hubDirectoryResolveBorrowRequest(requestId, resolution);
      await loadIncomingHubRequests();
      return true;
    } catch (e) {
      _actionError = e.toString();
      debugPrint('HubDirectoryProvider resolveHubBorrowRequest error: $e');
      return false;
    } finally {
      _busyNodes.remove(key);
      notifyListeners();
    }
  }

  /// Cancel or dismiss a hub borrow request.
  /// Tries to cancel on the Hub first (pending requests only).
  /// If the Hub rejects (e.g. already accepted), dismisses locally instead.
  Future<bool> cancelHubBorrowRequest(int requestId) async {
    final key = 'hub_borrow_$requestId';
    _busyNodes.add(key);
    _actionError = null;
    notifyListeners();

    try {
      await _ffi.hubDirectoryCancelBorrowRequest(requestId);
      await loadOutgoingHubRequests();
      return true;
    } catch (e) {
      // Hub rejects cancel for non-pending requests - dismiss locally
      debugPrint('HubDirectoryProvider cancelHubBorrowRequest: $e - dismissing locally');
      _dismissedHubRequestIds.add(requestId);
      return true;
    } finally {
      _busyNodes.remove(key);
      notifyListeners();
    }
  }

  /// Dismiss a hub borrow request locally (incoming or outgoing, any status).
  void dismissHubRequest(int requestId) {
    _dismissedHubRequestIds.add(requestId);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // E2EE contact sharing
  // ---------------------------------------------------------------------------

  /// Seal the local contact info for a specific follower.
  /// Returns the base64-encoded sealed blob, or null on error.
  Future<String?> sealContactFor(String recipientX25519Hex) async {
    if (_contactInfo.isEmpty || recipientX25519Hex.isEmpty) return null;
    try {
      return await _ffi.sealBlob(recipientX25519Hex, _contactInfo);
    } catch (e) {
      debugPrint('HubDirectoryProvider sealContactFor error: $e');
      return null;
    }
  }

  /// Decrypt a sealed contact blob received from a followed library.
  Future<String?> openContact(String sealedBase64) async {
    try {
      return await _ffi.openBlob(sealedBase64);
    } catch (e) {
      debugPrint('HubDirectoryProvider openContact error: $e');
      return null;
    }
  }

  /// Re-seal contact info for all active followers and push to hub.
  /// Call this after the user changes their contact info.
  Future<void> syncContactToFollowers() async {
    if (_contactInfo.isEmpty) {
      debugPrint('[CONTACT-SYNC] skip: contactInfo is empty');
      return;
    }
    debugPrint('[CONTACT-SYNC] starting, contact="${_contactInfo.substring(0, _contactInfo.length.clamp(0, 30))}..."');
    try {
      final followersList = await _ffi.hubDirectoryListFollowers();
      final followers = followersList.map(HubFollow.fromFrb).toList();
      debugPrint('[CONTACT-SYNC] ${followers.length} followers total, '
          '${followers.where((f) => f.isActive).length} active');

      final followIds = <int>[];
      final blobs = <String>[];

      for (final f in followers) {
        if (!f.isActive) {
          debugPrint('[CONTACT-SYNC] follower ${f.followerNodeId.substring(0, 8)}... status=${f.status}, skipping');
          continue;
        }
        final key = f.followerX25519PublicKey;
        if (key == null || key.isEmpty) {
          debugPrint('[CONTACT-SYNC] follower ${f.followerNodeId.substring(0, 8)}... has NO x25519 key, skipping');
          continue;
        }
        debugPrint('[CONTACT-SYNC] follower ${f.followerNodeId.substring(0, 8)}... has key ${key.substring(0, 8)}..., sealing');
        final blob = await sealContactFor(key);
        if (blob != null) {
          followIds.add(f.id);
          blobs.add(blob);
          debugPrint('[CONTACT-SYNC] sealed blob for follow_id=${f.id}, blob len=${blob.length}');
        } else {
          debugPrint('[CONTACT-SYNC] sealContactFor returned null for follower ${f.followerNodeId.substring(0, 8)}...');
        }
      }

      if (followIds.isNotEmpty) {
        debugPrint('[CONTACT-SYNC] pushing ${followIds.length} blobs to hub...');
        await _ffi.hubDirectorySyncContacts(followIds, blobs);
        debugPrint('[CONTACT-SYNC] push done');
      } else {
        debugPrint('[CONTACT-SYNC] no blobs to push (0 eligible followers with keys)');
      }
    } catch (e) {
      debugPrint('[CONTACT-SYNC] ERROR: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the follow status for [nodeId] from the local cache, or null.
  String? followStatusFor(String nodeId) {
    try {
      return _following
          .firstWhere((f) => f.followedNodeId == nodeId)
          .status;
    } catch (_) {
      return null;
    }
  }

  /// Returns the HubFollow for [nodeId] from the local cache, or null.
  HubFollow? followFor(String nodeId) {
    try {
      return _following.firstWhere((f) => f.followedNodeId == nodeId);
    } catch (_) {
      return null;
    }
  }

  /// Resolves a node ID to a display name.
  /// Priority: user custom name > name cache > directory profiles.
  String? displayNameFor(String nodeId) {
    final custom = _customFollowNames[nodeId];
    if (custom != null) return custom;
    final cached = _nameCache[nodeId];
    if (cached != null) return cached;
    try {
      final name = _profiles
          .firstWhere((p) => p.nodeId == nodeId)
          .displayName;
      _nameCache[nodeId] = name;
      return name;
    } catch (_) {
      return null;
    }
  }

  /// Fetches display names for [nodeIds] not already cached.
  /// Runs in the background and calls notifyListeners when done.
  void _resolveNames(List<String> nodeIds) {
    final unknown = nodeIds
        .where((id) => !_nameCache.containsKey(id))
        .toSet();
    if (unknown.isEmpty) return;

    // Fire-and-forget: fetch each profile and update cache.
    for (final id in unknown) {
      _ffi.hubDirectoryGetProfile(id).then((profile) {
        if (profile != null) {
          _nameCache[id] = profile.displayName;
          _cacheAvatar(id, profile.avatarConfig);
          notifyListeners();
        }
      }).catchError((e) {
        debugPrint('HubDirectoryProvider _resolveNames($id): $e');
      });
    }
  }

  void clearActionError() {
    _actionError = null;
    notifyListeners();
  }

  /// Sanitize contact info: strip HTML tags, control chars, and cap length.
  static String _sanitizeContact(String raw) {
    // Remove HTML tags
    var s = raw.replaceAll(RegExp(r'<[^>]*>'), '');
    // Remove control characters (keep newlines and tabs)
    s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    // Trim and cap at 500 chars
    s = s.trim();
    if (s.length > 500) s = s.substring(0, 500);
    return s;
  }
}
