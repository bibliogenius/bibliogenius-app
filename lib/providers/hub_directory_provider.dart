import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/avatar_config.dart';
import '../models/hub_directory.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/city_repository.dart';
import '../services/device_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../src/rust/api/frb.dart' show FrbNudgeEvent, subscribeRelayNudges;

/// Page size for directory listing.
const int _kPageSize = 20;

/// Visible cap for the "libraries in your city" banner. The probe fetches
/// `cap + 1` so the UI can switch from a precise count ("7 libraries") to a
/// saturated label ("10+ libraries") without paying for a second request.
/// Bounded payload keeps the per-app-start cost tiny on slow networks
/// (perf policy: low-end devices, intermittent connectivity).
const int _kSameCityCap = 10;

/// Max retry attempts for relay credential publishing.
const int _kRelayPublishMaxAttempts = 3;

/// Delay between relay publish retries.
const Duration _kRelayPublishRetryDelay = Duration(seconds: 5);

/// Cooldown before retrying relay publish from periodic sync (avoids hammering
/// the hub when the network is persistently down).
const Duration _kRelayPublishCooldown = Duration(seconds: 90);

/// SharedPreferences key: epoch milliseconds of the last successful catalog
/// push to the hub. Drives the keep-alive re-push (see
/// [_kCatalogKeepAliveInterval]) so a static catalog never silently expires
/// under the hub's TTL.
const String _kLastCatalogPushKey = 'hub_last_catalog_push_ms';

/// Re-push the catalog when the last push is older than this, even if nothing
/// changed locally. Kept well under the hub's 7-day catalog TTL so a stable
/// library is refreshed before its hub copy is pruned (otherwise the directory
/// fallback goes empty for peers that cannot reach us live). The hub dedupes
/// by hash, so an unchanged re-push is near-free.
const Duration _kCatalogKeepAliveInterval = Duration(days: 4);

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

/// SharedPreferences key: display_name the user picked while the hub config
/// was not yet loaded (or the hub push failed). Consumed on the next
/// successful [initAndSyncCatalog] so the hub profile catches up.
const String _kPendingDisplayNameKey = 'hub_pending_display_name';

/// SharedPreferences key: location_country the user picked while the hub
/// config was not yet loaded (or the hub push failed). Consumed on the next
/// successful [initAndSyncCatalog] so the hub profile catches up.
const String _kPendingLocationCountryKey = 'hub_pending_location_country';

/// SharedPreferences key: pending location_city_id update (ADR-035 Phase 1).
/// Empty string means the user requested a clear (push NULL), a non-empty
/// integer string means the user picked that GeoNames id. Missing key means
/// no pending action. Replayed by [initAndSyncCatalog] on the next
/// successful sync, exactly like [_kPendingLocationCountryKey].
const String _kPendingLocationCityIdKey = 'hub_pending_location_city_id';

/// SharedPreferences key: opt-in toggle "Partager ma ville" (ADR-035 §3).
/// Distinct from [_kHubEnabledKey] and from `_config.isListed`: a user can
/// be listed in the directory by country only, without sharing their city.
/// Default OFF, including for users already listed.
const String _kShareCityKey = 'hub_share_city';

/// SharedPreferences key: GeoNames id the user picked locally. This is the
/// app's display truth ("your current city: Paris") and what is sent on the
/// next [syncLocationCityId]. The hub mirror lives in `library_profiles.
/// location_city_id`. We do NOT re-fetch it from the hub at app start -
/// the picker writes here and the network is updated as a side effect.
const String _kLocalLocationCityIdKey = 'hub_local_location_city_id';

/// SharedPreferences key: alpha-2 country code that the picker resolved for
/// [_kLocalLocationCityIdKey]. Denormalized on purpose: the country is a
/// property of the city, but storing it locally lets the cold-start
/// remediation pass derive the (city, country) pair without requiring the
/// CityRepository to have already loaded the right country file. Cleared
/// in lockstep with the city id so the two never drift.
const String _kLocalLocationCityCountryKey = 'hub_local_location_city_country';

/// SharedPreferences key: country code (alpha-2) the user implicitly selected
/// by picking their city. Stored alongside [_kPendingLocationCityIdKey] so
/// [_consumePendingLocationCityId] can replay both fields in the same hub
/// register call. Distinct from [_kPendingLocationCountryKey] which is the
/// independent country picker pending state. Empty / absent: replay falls
/// back to a CityRepository lookup.
const String _kPendingLocationCityCountryKey =
    'hub_pending_location_city_country';

/// SharedPreferences keys: snapshot of the last successful (cityId, country)
/// pair pushed to the hub. Used by the init-time remediation pass to detect
/// drift (e.g. legacy installs that registered city without country) and
/// re-push exactly once until the hub state matches the local intent.
const String _kLastPushedLocationCityIdKey = 'hub_last_pushed_location_city_id';
const String _kLastPushedLocationCityCountryKey =
    'hub_last_pushed_location_city_country';

/// Pluggable city lookup so tests can stub the resolution without bringing
/// the full [CityRepository] (which depends on disk + network). Production
/// uses [CityRepository.shared().lookupById].
typedef CityLookup = Future<CityRecord?> Function(int id, {String? country});

class HubDirectoryProvider extends ChangeNotifier {
  final FfiService _ffi;
  final DeviceService _deviceService;
  final AuthService _authService;
  final CityLookup _lookupCity;
  // Optional: when present, ensureRelayPublished will fall back to creating
  // a local relay mailbox if none exists yet. Production wires it via
  // main.dart; tests can leave it null.
  final ApiService? _apiService;

  /// Retry delay between relay publish attempts. Override in tests.
  @visibleForTesting
  Duration relayRetryDelay = _kRelayPublishRetryDelay;

  /// Cooldown between periodic relay publish retry cycles. Override in tests.
  @visibleForTesting
  Duration relayCooldown = _kRelayPublishCooldown;

  /// Keep-alive threshold for re-pushing an unchanged catalog. Override in
  /// tests to avoid waiting days of wall-clock time.
  @visibleForTesting
  Duration catalogKeepAliveInterval = _kCatalogKeepAliveInterval;

  HubDirectoryProvider({
    FfiService? ffi,
    DeviceService? deviceService,
    AuthService? authService,
    CityLookup? lookupCity,
    ApiService? apiService,
  }) : _ffi = ffi ?? FfiService(),
       _deviceService = deviceService ?? DeviceService(),
       _authService = authService ?? AuthService(),
       _lookupCity = lookupCity ?? CityRepository.shared().lookupById,
       _apiService = apiService;

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
      debugPrint(
        'HubDirectoryProvider: failed to subscribe to nudge stream: $e',
      );
    }
  }

  Future<void> _onNudgeEvent(FrbNudgeEvent _) async {
    if (!_hubEnabled || !isRegistered) return;
    // A hub nudge is generic - we cannot tell whether it was caused by an
    // incoming follow request, an incoming borrow, or an update to our own
    // follows (e.g. another library just approved our pending request). Refresh
    // all three lightweight lists so every state transition surfaces without a
    // manual pull-to-refresh. Each list is a single GET, cheap, idempotent.
    _silentRefreshIncomingBorrow();
    await Future.wait([loadPendingRequests(), loadFollowing()]);
    // ADR-053: a nudge may be the follow request of a freshly paired peer;
    // reconciling here approves it immediately instead of at next cold start.
    // The follow lists were refreshed just above, so the reconciliation
    // reuses them instead of re-fetching (refreshLists: false).
    unawaited(reconcilePairedPeerFollows(refreshLists: false));
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

  // ── Share-city toggle (ADR-035 §3) ──────────────────────────────────────

  bool _shareCity = false;

  /// Whether the user has opted in to share their city in the directory.
  /// Distinct from [isHubEnabled] / `_config.isListed`: false means the
  /// profile may still appear publicly with country-only granularity.
  bool get isShareCityEnabled => _shareCity;

  /// Load the share-city toggle from SharedPreferences. Call at app start.
  Future<void> loadShareCity() async {
    final prefs = await SharedPreferences.getInstance();
    _shareCity = prefs.getBool(_kShareCityKey) ?? false;
    notifyListeners();
  }

  /// Persist the share-city toggle. Does NOT push the change to the hub -
  /// callers must follow up with [syncLocationCityId] (passing the picked
  /// id when enabling, `null` when disabling) so the hub state matches the
  /// local intent. Splitting the two concerns keeps this setter cheap and
  /// lets the picker UI sequence "save id then mirror to hub" in one step.
  Future<void> setShareCity(bool value) async {
    _shareCity = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShareCityKey, value);
    notifyListeners();
  }

  // ── Locally picked city id (display state) ──────────────────────────────

  int? _localCityId;

  /// The GeoNames id the user picked in the settings picker. Used to render
  /// the current selection without re-fetching from the hub. `null` means
  /// the user has not picked one yet (fresh install) or has cleared it.
  int? get localCityId => _localCityId;

  Future<void> loadLocalCityId() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_kLocalLocationCityIdKey);
    _localCityId = (raw != null && raw > 0) ? raw : null;
    notifyListeners();
  }

  /// Persist the locally picked city id. Pass `null` to clear it. The
  /// optional [country] is the alpha-2 code that the picker resolved
  /// alongside the city - it has no separate local storage (the city is
  /// the single source of truth) but it is forwarded to
  /// [syncLocationCityId] / the pending storage so the hub upsert never
  /// drops the country when it gets a new city.
  ///
  /// Re-runs the same-city highlight probe so the banner count and the
  /// "Voir" CTA stay in sync with the new city (or clear when the user
  /// removes their city).
  Future<void> setLocalCityId(int? id, {String? country}) async {
    _localCityId = (id != null && id > 0) ? id : null;
    final prefs = await SharedPreferences.getInstance();
    if (_localCityId == null) {
      await prefs.remove(_kLocalLocationCityIdKey);
      await prefs.remove(_kLocalLocationCityCountryKey);
    } else {
      await prefs.setInt(_kLocalLocationCityIdKey, _localCityId!);
      final trimmedCountry = country?.trim();
      if (trimmedCountry != null && trimmedCountry.isNotEmpty) {
        await prefs.setString(
          _kLocalLocationCityCountryKey,
          trimmedCountry.toUpperCase(),
        );
      }
      // Intentionally do NOT remove the country key when [country] is
      // null: the previously stored value is the best hint we have for
      // the cold-start remediation pass, and the city/country pair is
      // never updated to a contradicting one (cities never move).
    }
    notifyListeners();
    await loadSameCityHighlight();
    // Note: this method intentionally does NOT push to the hub. The caller
    // (settings city picker) follows up with [syncLocationCityId] passing
    // the same [country] so a single user gesture results in a single
    // hub upsert that carries both fields.
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
    final idx = (_consecutive401Count - 1).clamp(
      0,
      _cooldown401Minutes.length - 1,
    );
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
      debugPrint(
        'HubDirectoryProvider: recovery_code Keychain backup FAILED: $e',
      );
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
  String? _filterCountry;
  int? _filterCityId;

  List<HubProfile> get profiles => _profiles;
  bool get listLoading => _listLoading;
  bool get hasMore => _hasMore;
  String? get listError => _listError;
  String? get searchQuery => _searchQuery;

  /// Active country filter (ISO 3166-1 alpha-2). `null` = no filter.
  String? get filterCountry => _filterCountry;

  /// Active city filter (GeoNames id). `null` = no filter.
  int? get filterCityId => _filterCityId;

  /// True when at least one location filter is active. Used by the network
  /// screen to render the "clear filter" chip and the contextual empty state.
  bool get hasActiveLocationFilter =>
      _filterCountry != null || _filterCityId != null;

  // ── Same-city highlight (banner) ────────────────────────────────────────

  /// Up to `_kSameCityCap` profiles located in the user own city. Populated
  /// by [loadSameCityHighlight], excluding the user own profile so the count
  /// never gets inflated by self.
  List<HubProfile> _sameCityProfiles = const [];

  /// True when the same-city probe returned more than `_kSameCityCap`
  /// matches (the `+1` sentinel of the fetch), so the UI switches its
  /// label from "X libraries" to "10+ libraries".
  bool _sameCityHasMore = false;

  List<HubProfile> get sameCityProfiles => _sameCityProfiles;

  bool get sameCityHasMore => _sameCityHasMore;

  /// Visible count for the banner: the post-self-filter profile count,
  /// capped at `_kSameCityCap`. Returns `null` when the user has not picked
  /// a city yet, so the UI can short-circuit rendering.
  int? get sameCityCount {
    if (_localCityId == null) return null;
    final visible = _sameCityProfiles.length;
    return visible > _kSameCityCap ? _kSameCityCap : visible;
  }

  /// Country code of the first same-city profile, used by the "Voir" CTA
  /// to apply the existing country+city filter pair (mirrors how the city
  /// picker calls [loadDirectory]). Derived from the probe response so we
  /// avoid carrying a second source of truth alongside [_localCityId].
  String? get sameCityCountryHint => _sameCityProfiles.isEmpty
      ? null
      : _sameCityProfiles.first.locationCountry;

  /// Banner visibility rule. Hidden when:
  /// - The user has not picked a city (legacy / fresh install).
  /// - No peer matches the user city (lone library in town).
  /// - The location filter is already targeting that city (the banner
  ///   would just duplicate the active-filter chip).
  bool get shouldShowSameCityBanner {
    if (_localCityId == null) return false;
    if (_sameCityProfiles.isEmpty) return false;
    if (_filterCityId == _localCityId) return false;
    return true;
  }

  /// Probe the hub for libraries in the user own city. Exposes a small
  /// preview slice (`_kSameCityCap` + 1) used purely to feed the banner -
  /// the main directory list stays driven by [loadDirectory] / pagination.
  ///
  /// Idempotent and silent: a hub blip clears the slice instead of
  /// surfacing an error, so the banner just disappears until the next
  /// successful refresh.
  Future<void> loadSameCityHighlight() async {
    final cityId = _localCityId;
    if (cityId == null) {
      if (_sameCityProfiles.isNotEmpty || _sameCityHasMore) {
        _sameCityProfiles = const [];
        _sameCityHasMore = false;
        notifyListeners();
      }
      return;
    }

    try {
      final batch = await _ffi.hubDirectoryList(
        limit: _kSameCityCap + 1,
        offset: 0,
        cityId: cityId,
      );
      final ownNodeId = _config?.nodeId;
      final filtered = batch
          .map(HubProfile.fromFrb)
          .where((p) => p.nodeId != ownNodeId)
          .toList(growable: false);
      _sameCityHasMore = filtered.length > _kSameCityCap;
      _sameCityProfiles = _sameCityHasMore
          ? filtered.sublist(0, _kSameCityCap)
          : filtered;
      notifyListeners();
    } catch (e) {
      // Transient errors (network blip, hub mid-write during a cross-device
      // sync, etc.) must NOT clear the last-known-good state - that caused
      // the banner to flicker between iPhone / Mac while one peer was still
      // syncing. The state stays on the most recent successful response
      // until the next successful response replaces it. A genuinely empty
      // hub answer (peer left the directory) is a *successful* response
      // and goes through the path above, where it correctly clears.
      debugPrint('HubDirectoryProvider loadSameCityHighlight error: $e');
    }
  }

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

  List<frb.FrbHubBorrowRequest> get incomingHubRequests => _incomingHubRequests
      .where((r) => !_dismissedHubRequestIds.contains(r.id.toInt()))
      .toList();
  List<frb.FrbHubBorrowRequest> get outgoingHubRequests => _outgoingHubRequests
      .where((r) => !_dismissedHubRequestIds.contains(r.id.toInt()))
      .toList();

  /// Number of pending incoming hub borrow requests - used for badge.
  int get pendingHubBorrowCount =>
      _incomingHubRequests.where((r) => r.status == 'pending').length;

  // ── Name cache ──────────────────────────────────────────────────────────

  /// nodeId -> display name, populated lazily from hub profile lookups.
  final Map<String, String> _nameCache = {};

  /// nodeId -> parsed AvatarConfig, populated alongside _nameCache.
  final Map<String, AvatarConfig> _avatarCache = {};

  /// Negative cache: nodeId -> timestamp of last 404 from the hub. Stops the
  /// directory hammer when a peer has been purged and the local follow row
  /// has not been pruned yet. Production logs showed 116 lookups in a few
  /// days for a single ghost nodeId before this gate. Mirrors the pattern
  /// in audiobook_service._notFoundCache.
  final Map<String, DateTime> _notFoundCache = {};

  /// TTL of the negative cache. Aligned with ADR-032's relay retry window
  /// for consistency: a peer absent from the hub now is presumed absent for
  /// the next hour.
  static const Duration _kNotFoundCacheTtl = Duration(hours: 1);

  /// True if [nodeId] is currently in the negative cache and the entry has
  /// not expired. Side effect: drops expired entries on read.
  bool _isCachedNotFound(String nodeId) {
    final stamped = _notFoundCache[nodeId];
    if (stamped == null) return false;
    if (DateTime.now().difference(stamped) >= _kNotFoundCacheTtl) {
      _notFoundCache.remove(nodeId);
      return false;
    }
    return true;
  }

  /// Re-fetch a single node's display name from the hub and update the cache.
  Future<void> refreshName(String nodeId) async {
    if (_isCachedNotFound(nodeId)) return;
    try {
      final profile = await _ffi.hubDirectoryGetProfile(nodeId);
      if (profile != null) {
        _nameCache[nodeId] = profile.displayName;
        _notFoundCache.remove(nodeId);
        _cacheAvatar(nodeId, profile.avatarConfig);
        notifyListeners();
      }
    } catch (e) {
      if (e.toString().contains('Hub error 404')) {
        _notFoundCache[nodeId] = DateTime.now();
      }
      debugPrint('HubDirectoryProvider refreshName($nodeId): $e');
    }
  }

  /// Clear the auto-resolved name cache so the next [loadFollowing] re-fetches
  /// all names from the hub. Does NOT clear user-custom names.
  void invalidateNameCache() {
    _nameCache.clear();
    _avatarCache.clear();
    // Drop the negative cache too: a manual refresh signals the user wants
    // to retry every name, including previously-not-found ones.
    _notFoundCache.clear();
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

  /// Busy key of an in-flight [resolveFollow]. Kept next to the getter so the
  /// key format lives in one place only.
  String _resolveFollowKey(int followId) => 'resolve_$followId';

  /// True while [resolveFollow] is in flight for this request, so the UI can
  /// disable its approve/reject/block affordances instead of firing twice.
  bool isResolvingFollow(int followId) => isBusy(_resolveFollowKey(followId));

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
      // Local UI state lives in SharedPreferences and is independent of the
      // hub config. Load eagerly so consumers reading from the provider on
      // a cold start (e.g. network screen empty-state CTA) see the real
      // values even before settings_screen has been opened.
      await Future.wait([loadShareCity(), loadLocalCityId()]);
      await loadConfig();
      debugPrint('HubDirectory: config loaded, isRegistered=$isRegistered');
      if (!isRegistered) {
        debugPrint('HubDirectory: not registered, auto-registering...');
        await ensureRegistered();
        debugPrint(
          'HubDirectory: after ensureRegistered, isRegistered=$isRegistered',
        );
      }
      if (isRegistered) {
        // Ensure relay credentials are published on the hub profile.
        // Fixes ~50% of installs where relay was missing due to race condition
        // or ensureKeysPublished overwriting without relay params.
        await ensureRelayPublished();
        // Replay a rename that happened before config was available
        // (flash library name editor on first run).
        await _consumePendingDisplayName();
        // Replay a country change deferred while the hub was unreachable.
        await _consumePendingLocationCountry();
        // Same replay for a deferred city pick / clear (ADR-035 Phase 1).
        await _consumePendingLocationCityId();
        // Heal pre-fix installs where the city was pushed without its
        // country, leaving the hub-stored country NULL and silently
        // excluding the profile from country+city directory filters.
        await ensureLocationCityCountryConsistency();
        syncCatalogIfDirty();
        // Start listening for relay nudges so incoming follow/borrow events
        // refresh instantly instead of waiting for the next polling cycle.
        _subscribeNudgeStream();
        // ADR-053: make sure every accepted paired peer holds (and grants)
        // hub catalog access, so the offline fallback survives
        // requires_approval on either side. Fire-and-forget: errors are
        // logged inside and the next trigger retries.
        unawaited(reconcilePairedPeerFollows());
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
    var initialRelay = await _getRelayCredentials();
    if (initialRelay.relayUrl == null) {
      // Backfill missing-mailbox profiles: main.dart's bootstrap setup runs
      // once at boot and silently fails on transient network errors, leaving
      // some installs stuck without a relay. Retry here when the FFI server
      // is reliably up and the user opted into remote reachability.
      final created = await _ensureLocalRelaySetup();
      if (created) {
        initialRelay = await _getRelayCredentials();
      }
      if (initialRelay.relayUrl == null) {
        if (kDebugMode)
          debugPrint('HubDirectory: no local relay config, skip relay publish');
        return;
      }
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
      final libraryName =
          prefs.getString('libraryName') ??
          TranslationService.translateByLocale(
            prefs.getString('languageCode') ?? 'en',
            'my_library_title',
          );
      final bookCount = await _ffi.countBooks();
      String? x25519Key;
      try {
        x25519Key = await _ffi.getLocalX25519PublicKey();
      } catch (_) {}
      final deviceModel = await _deviceService.getDeviceModel();
      final deviceFingerprint = await _deviceService.getDeviceFingerprint();
      final appVersion = await _deviceService.getAppVersion();
      final loc = await _currentLocationForRegister();

      if (kDebugMode) {
        debugPrint(
          'HubDirectory: publishing relay credentials to hub '
          '(attempt $attempt/$_kRelayPublishMaxAttempts)',
        );
      }
      final ok = await register(
        nodeId: cfg.nodeId,
        displayName: libraryName,
        bookCount: bookCount,
        isListed: cfg.isListed,
        requiresApproval: cfg.requiresApproval,
        acceptFrom: cfg.acceptFrom,
        allowBorrowing: cfg.allowBorrowing,
        // Re-assert location: this method runs on every cold start (and
        // on retry) - omitting cityId would silently wipe the user's city
        // each time, which production logs caught as the root cause of
        // the disappearing same-city banner.
        locationCountry: loc.country,
        locationCityId: loc.cityId,
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
        debugPrint(
          'HubDirectory: relay publish failed, retrying in '
          '${relayRetryDelay.inSeconds}s...',
        );
        await Future.delayed(relayRetryDelay);
      }
    }
    debugPrint(
      'HubDirectory: relay publish failed after '
      '$_kRelayPublishMaxAttempts attempts, will retry on next catalog sync',
    );
  }

  // ---------------------------------------------------------------------------
  // Display name sync
  // ---------------------------------------------------------------------------

  /// Push a new library [displayName] to the hub profile.
  ///
  /// Safe to call before the hub config is loaded: in that case
  /// [ensureRegistered] is triggered first so the hub knows about this node.
  /// If the hub cannot be reached (offline, 401 cooldown, etc.), the desired
  /// name is persisted in SharedPreferences and replayed on the next
  /// successful [initAndSyncCatalog] cycle.
  Future<bool> syncDisplayName(String displayName) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return false;

    if (_config == null) {
      // Config not yet hydrated (e.g. flash rename fires before
      // initAndSyncCatalog completes): try to register silently now.
      await ensureRegistered();
    }

    if (_config == null) {
      await _storePendingDisplayName(trimmed);
      debugPrint('HubDirectory: displayName sync deferred (no config yet)');
      return false;
    }

    final ok = await _pushDisplayName(trimmed);
    if (ok) {
      await _clearPendingDisplayName();
    } else {
      await _storePendingDisplayName(trimmed);
    }
    return ok;
  }

  /// Internal push used by [syncDisplayName] and by the pending-rename replay.
  /// Requires [_config] to be non-null. Passes all device/relay fields so the
  /// hub does not overwrite them with null (same pattern as
  /// [ensureRelayPublished]). locationCountry is intentionally omitted: the
  /// hub preserves absent fields, so we don't need a ThemeProvider dependency.
  Future<bool> _pushDisplayName(String displayName) async {
    final cfg = _config;
    if (cfg == null) return false;

    final bookCount = await _ffi.countBooks();
    String? x25519Key;
    try {
      x25519Key = await _ffi.getLocalX25519PublicKey();
    } catch (_) {}
    final deviceModel = await _deviceService.getDeviceModel();
    final deviceFingerprint = await _deviceService.getDeviceFingerprint();
    final appVersion = await _deviceService.getAppVersion();
    final relay = await _getRelayCredentials();
    final loc = await _currentLocationForRegister();

    return register(
      nodeId: cfg.nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: cfg.isListed,
      requiresApproval: cfg.requiresApproval,
      acceptFrom: cfg.acceptFrom,
      allowBorrowing: cfg.allowBorrowing,
      // Re-assert location: the Rust serializer always emits cityId, so
      // omitting it here would wipe the user's city on the hub on every
      // rename. Country is preserved when null (Rust omits null country).
      locationCountry: loc.country,
      locationCityId: loc.cityId,
      x25519PublicKey: x25519Key,
      deviceModel: deviceModel,
      deviceFingerprint: deviceFingerprint,
      appVersion: appVersion,
      relayUrl: relay.relayUrl,
      relayMailboxId: relay.mailboxId,
      relayWriteToken: relay.writeToken,
    );
  }

  Future<void> _storePendingDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingDisplayNameKey, name);
  }

  Future<void> _clearPendingDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingDisplayNameKey);
  }

  Future<String?> _getPendingDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingDisplayNameKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  /// Replay a pending rename if the user renamed the library before the hub
  /// config was available. Called from [initAndSyncCatalog] once registration
  /// is confirmed.
  Future<void> _consumePendingDisplayName() async {
    if (_config == null) return;
    final pending = await _getPendingDisplayName();
    if (pending == null) return;
    debugPrint('HubDirectory: replaying pending displayName "$pending"');
    final ok = await _pushDisplayName(pending);
    if (ok) await _clearPendingDisplayName();
  }

  // ---------------------------------------------------------------------------
  // Location country sync
  // ---------------------------------------------------------------------------

  /// Push a new [locationCountry] (ISO 3166-1 alpha-2) to the hub profile.
  ///
  /// Mirrors [syncDisplayName]: safe to call before the hub config is loaded
  /// (silent registration is triggered first), and offline failures are
  /// persisted in SharedPreferences so the next successful
  /// [initAndSyncCatalog] cycle replays them.
  Future<bool> syncLocationCountry(String locationCountry) async {
    final trimmed = locationCountry.trim().toUpperCase();
    if (trimmed.isEmpty) return false;

    if (_config == null) {
      await ensureRegistered();
    }

    if (_config == null) {
      await _storePendingLocationCountry(trimmed);
      debugPrint('HubDirectory: locationCountry sync deferred (no config yet)');
      return false;
    }

    final ok = await _pushLocationCountry(trimmed);
    if (ok) {
      await _clearPendingLocationCountry();
    } else {
      await _storePendingLocationCountry(trimmed);
    }
    return ok;
  }

  /// Internal push used by [syncLocationCountry] and the pending replay.
  /// Requires [_config] to be non-null. Passes all device/relay fields so the
  /// hub does not overwrite them with null (same pattern as
  /// [_pushDisplayName]). The displayName is pulled from SharedPreferences
  /// because [register] requires it; if the user renamed the library while
  /// the hub was offline, the pending displayName flag will catch up
  /// independently on the next sync.
  Future<bool> _pushLocationCountry(String locationCountry) async {
    final cfg = _config;
    if (cfg == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final displayName =
        prefs.getString('libraryName') ??
        TranslationService.translateByLocale(
          prefs.getString('languageCode') ?? 'en',
          'my_library_title',
        );
    final bookCount = await _ffi.countBooks();
    String? x25519Key;
    try {
      x25519Key = await _ffi.getLocalX25519PublicKey();
    } catch (_) {}
    final deviceModel = await _deviceService.getDeviceModel();
    final deviceFingerprint = await _deviceService.getDeviceFingerprint();
    final appVersion = await _deviceService.getAppVersion();
    final relay = await _getRelayCredentials();

    final loc = await _currentLocationForRegister();
    return register(
      nodeId: cfg.nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: cfg.isListed,
      requiresApproval: cfg.requiresApproval,
      acceptFrom: cfg.acceptFrom,
      allowBorrowing: cfg.allowBorrowing,
      // Caller's [locationCountry] wins (this method exists to set it).
      locationCountry: locationCountry,
      // Re-assert local cityId to avoid wiping it on a country-only update.
      locationCityId: loc.cityId,
      x25519PublicKey: x25519Key,
      deviceModel: deviceModel,
      deviceFingerprint: deviceFingerprint,
      appVersion: appVersion,
      relayUrl: relay.relayUrl,
      relayMailboxId: relay.mailboxId,
      relayWriteToken: relay.writeToken,
    );
  }

  Future<void> _storePendingLocationCountry(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingLocationCountryKey, code);
  }

  Future<void> _clearPendingLocationCountry() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingLocationCountryKey);
  }

  Future<String?> _getPendingLocationCountry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingLocationCountryKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw;
  }

  Future<void> _consumePendingLocationCountry() async {
    if (_config == null) return;
    final pending = await _getPendingLocationCountry();
    if (pending == null) return;
    debugPrint('HubDirectory: replaying pending locationCountry "$pending"');
    final ok = await _pushLocationCountry(pending);
    if (ok) await _clearPendingLocationCountry();
  }

  // ---------------------------------------------------------------------------
  // Location city id sync (ADR-035 Phase 1)
  // ---------------------------------------------------------------------------

  /// Push a new [cityId] (GeoNames id) to the hub profile, or `null` to
  /// clear the previously stored value (when the user toggles off
  /// "Partager ma ville"). When [cityId] is non-null the alpha-2 [country]
  /// code travels along: a city implies its country, so the hub upsert
  /// must carry both to avoid leaving `location_country` NULL on the hub
  /// (which would silently exclude the profile from any country+city
  /// directory filter). When [country] is omitted it is resolved through
  /// the injected [_lookupCity]; if that lookup also fails the city is
  /// pushed alone (legacy behavior, hub preserves whatever country was
  /// previously stored).
  ///
  /// Mirrors [syncLocationCountry]: safe to call before the hub config is
  /// loaded, offline failures persist in SharedPreferences for replay on
  /// the next [initAndSyncCatalog] cycle.
  Future<bool> syncLocationCityId(int? cityId, {String? country}) async {
    final resolvedCountry = await _resolveCityCountry(cityId, country);

    if (_config == null) {
      await ensureRegistered();
    }

    if (_config == null) {
      await _storePendingLocationCityId(cityId, resolvedCountry);
      debugPrint('HubDirectory: locationCityId sync deferred (no config yet)');
      return false;
    }

    final ok = await _pushLocationCityId(cityId, country: resolvedCountry);
    if (ok) {
      await _clearPendingLocationCityId();
      await _recordLastPushedLocationCity(cityId, resolvedCountry);
    } else {
      await _storePendingLocationCityId(cityId, resolvedCountry);
    }
    return ok;
  }

  /// Reads the locally persisted `(cityId, country)` so any cross-cutting
  /// `register()` caller (relay republish, rename, country picker, etc.)
  /// can re-assert the full location state on every push.
  ///
  /// This is REQUIRED because the Rust serializer always emits
  /// `location_city_id` in the JSON body (ADR-035 §8 clear-on-toggle): a
  /// `register()` call that omits the field sends `location_city_id=null`
  /// to the hub, silently wiping the stored value. Production logs showed
  /// 6+ register_or_update calls per cold-start cycle (relay publish,
  /// rename retry, etc.) each one wiping the city the previous user
  /// gesture had just set. Without this helper the same-city banner
  /// converged for milliseconds and then went blank.
  Future<({int? cityId, String? country})> _currentLocationForRegister() async {
    final cityId = _localCityId;
    if (cityId == null) {
      return (cityId: null, country: null);
    }
    final prefs = await SharedPreferences.getInstance();
    final hint = prefs.getString(_kLocalLocationCityCountryKey);
    final country = await _resolveCityCountry(cityId, hint);
    return (cityId: cityId, country: country);
  }

  /// Best-effort country derivation for a [cityId]. Returns the explicit
  /// [override] uppercased when provided, otherwise looks up the city in
  /// the local GeoNames cache. Returns `null` when:
  /// - `cityId` is null (caller is clearing the city),
  /// - or the lookup fails (country file not yet downloaded). The caller
  ///   then pushes city alone, leaving the hub-stored country intact.
  Future<String?> _resolveCityCountry(int? cityId, String? override) async {
    final trimmed = override?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed.toUpperCase();
    }
    if (cityId == null) return null;
    try {
      final record = await _lookupCity(cityId);
      return record?.country.toUpperCase();
    } catch (e) {
      debugPrint('HubDirectory: city country lookup failed: $e');
      return null;
    }
  }

  /// Internal push used by [syncLocationCityId] and the pending replay.
  /// Same defensive shape as [_pushLocationCountry]: pulls the display
  /// name from prefs and re-emits all device/relay fields so the hub does
  /// not blank them on a profile update that only meant to change the city.
  Future<bool> _pushLocationCityId(int? cityId, {String? country}) async {
    final cfg = _config;
    if (cfg == null) return false;

    final prefs = await SharedPreferences.getInstance();
    final displayName =
        prefs.getString('libraryName') ??
        TranslationService.translateByLocale(
          prefs.getString('languageCode') ?? 'en',
          'my_library_title',
        );
    final bookCount = await _ffi.countBooks();
    String? x25519Key;
    try {
      x25519Key = await _ffi.getLocalX25519PublicKey();
    } catch (_) {}
    final deviceModel = await _deviceService.getDeviceModel();
    final deviceFingerprint = await _deviceService.getDeviceFingerprint();
    final appVersion = await _deviceService.getAppVersion();
    final relay = await _getRelayCredentials();

    return register(
      nodeId: cfg.nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: cfg.isListed,
      requiresApproval: cfg.requiresApproval,
      acceptFrom: cfg.acceptFrom,
      allowBorrowing: cfg.allowBorrowing,
      // null country is omitted from the JSON body by the Rust serializer
      // (hub_directory_service::build_register_body), so the previously
      // stored hub country survives a city-only push or a city clear.
      locationCountry: country,
      locationCityId: cityId,
      x25519PublicKey: x25519Key,
      deviceModel: deviceModel,
      deviceFingerprint: deviceFingerprint,
      appVersion: appVersion,
      relayUrl: relay.relayUrl,
      relayMailboxId: relay.mailboxId,
      relayWriteToken: relay.writeToken,
    );
  }

  Future<void> _storePendingLocationCityId(int? cityId, String? country) async {
    final prefs = await SharedPreferences.getInstance();
    // Empty string encodes the explicit "clear my city" intent so we can
    // distinguish it from "no pending action" (key absent). GeoNames ids
    // are always positive so there is no collision with a real value.
    await prefs.setString(
      _kPendingLocationCityIdKey,
      cityId == null ? '' : cityId.toString(),
    );
    // Persist the country alongside the city so the next replay re-pushes
    // the same pair. Skip on city-clear: the country is preserved hub-side
    // independently of the toggle, so we never want to overwrite it from
    // a deferred clear.
    if (cityId != null && country != null && country.isNotEmpty) {
      await prefs.setString(_kPendingLocationCityCountryKey, country);
    } else {
      await prefs.remove(_kPendingLocationCityCountryKey);
    }
  }

  Future<void> _clearPendingLocationCityId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingLocationCityIdKey);
    await prefs.remove(_kPendingLocationCityCountryKey);
  }

  /// Returns a `(hasPending, cityId, country)` triple: hasPending=false
  /// when the key is absent (no replay needed), hasPending=true with
  /// cityId=null when the user requested a clear, hasPending=true with a
  /// positive id otherwise. The country is the explicit pair stored at
  /// pick time (or `null` for legacy installs that pended pre-fix - the
  /// caller falls back to a fresh CityRepository lookup in that case).
  Future<({bool hasPending, int? cityId, String? country})>
  _getPendingLocationCityId() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_kPendingLocationCityIdKey)) {
      return (hasPending: false, cityId: null, country: null);
    }
    final raw = prefs.getString(_kPendingLocationCityIdKey) ?? '';
    final country = prefs.getString(_kPendingLocationCityCountryKey);
    if (raw.isEmpty) {
      return (hasPending: true, cityId: null, country: null);
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      // Corrupt value: drop it so we don't loop on bad data.
      await prefs.remove(_kPendingLocationCityIdKey);
      await prefs.remove(_kPendingLocationCityCountryKey);
      return (hasPending: false, cityId: null, country: null);
    }
    return (hasPending: true, cityId: parsed, country: country);
  }

  Future<void> _consumePendingLocationCityId() async {
    if (_config == null) return;
    final pending = await _getPendingLocationCityId();
    if (!pending.hasPending) return;
    final country = await _resolveCityCountry(pending.cityId, pending.country);
    debugPrint(
      'HubDirectory: replaying pending locationCityId '
      '${pending.cityId ?? "<clear>"} country=${country ?? "<unknown>"}',
    );
    final ok = await _pushLocationCityId(pending.cityId, country: country);
    if (ok) {
      await _clearPendingLocationCityId();
      await _recordLastPushedLocationCity(pending.cityId, country);
    }
  }

  /// Snapshots the most recent successful `(cityId, country)` push so the
  /// init-time remediation pass can detect drift on the next cold start
  /// and avoid paying a redundant register() round-trip when nothing
  /// changed (perf policy: intermittent network).
  Future<void> _recordLastPushedLocationCity(
    int? cityId,
    String? country,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (cityId == null) {
      await prefs.remove(_kLastPushedLocationCityIdKey);
      await prefs.remove(_kLastPushedLocationCityCountryKey);
      return;
    }
    await prefs.setInt(_kLastPushedLocationCityIdKey, cityId);
    if (country != null && country.isNotEmpty) {
      await prefs.setString(_kLastPushedLocationCityCountryKey, country);
    } else {
      await prefs.remove(_kLastPushedLocationCityCountryKey);
    }
  }

  /// Init-time remediation: re-pushes (cityId, country) if the hub may be
  /// out of sync with local state (e.g. legacy install that pushed city
  /// alone before this fix shipped, or a snapshot mismatch from a cleared
  /// SharedPreferences). Skipped when:
  /// - the user has no city set,
  /// - the country cannot be derived from the local city DB,
  /// - the snapshot already matches local state.
  /// Idempotent: subsequent cold starts find the snapshot aligned and
  /// short-circuit before any hub call.
  /// Returns true when a remediation push was actually attempted (drift
  /// detected). Visible for tests so the unit suite can assert "skipped"
  /// vs "pushed" precisely - just counting register calls is no longer
  /// sufficient now that every cross-cutting register caller also carries
  /// the cityId for state preservation.
  @visibleForTesting
  Future<bool> ensureLocationCityCountryConsistency() async {
    if (_config == null) return false;
    final cityId = _localCityId;
    if (cityId == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final hint = prefs.getString(_kLocalLocationCityCountryKey);
    final country = await _resolveCityCountry(cityId, hint);
    if (country == null) {
      // Without a derivable country, pushing city alone would just
      // recreate the bug we are trying to fix. Skip until the next cold
      // start, by which time the country file may have been downloaded.
      return false;
    }
    final lastCity = prefs.getInt(_kLastPushedLocationCityIdKey);
    final lastCountry = prefs.getString(_kLastPushedLocationCityCountryKey);
    if (lastCity == cityId && lastCountry == country) return false;
    debugPrint(
      'HubDirectory: location remediation: pushing cityId=$cityId country=$country',
    );
    final ok = await _pushLocationCityId(cityId, country: country);
    if (ok) {
      await _recordLastPushedLocationCity(cityId, country);
    }
    return true;
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
      _config = frbConfig != null ? DirectoryConfig.fromFrb(frbConfig) : null;

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

  /// Create a local relay mailbox if one is missing and the user has
  /// remote-reachable enabled. Idempotent: callers must check
  /// [_getRelayCredentials] beforehand to avoid creating a second mailbox
  /// (which would orphan the previous one).
  Future<bool> _ensureLocalRelaySetup() async {
    final api = _apiService;
    if (api == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final remoteEnabled = prefs.getBool('remoteReachableEnabled') ?? true;
    if (!remoteEnabled) return false;
    try {
      final res = await api.setupRelay(relayUrl: ApiService.hubUrl);
      final ok =
          res.statusCode == 200 &&
          res.data is Map &&
          (res.data as Map)['mailbox_uuid'] != null;
      debugPrint(
        'HubDirectory: local relay auto-setup '
        '${ok ? "succeeded" : "non-OK status=${res.statusCode}"}',
      );
      return ok;
    } catch (e) {
      debugPrint('HubDirectory: local relay auto-setup failed: $e');
      return false;
    }
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
      debugPrint(
        '[CONTACT-SYNC] ensureKeysPublished: no local X25519 key, skip',
      );
      return;
    }
    debugPrint(
      '[CONTACT-SYNC] ensureKeysPublished: key=${x25519Key.substring(0, 8)}..., registering',
    );

    final bookCount = await _ffi.countBooks();
    final deviceModel = await _deviceService.getDeviceModel();
    final deviceFingerprint = await _deviceService.getDeviceFingerprint();
    final appVersion = await _deviceService.getAppVersion();
    final relay = await _getRelayCredentials();
    final loc = await _currentLocationForRegister();
    await register(
      nodeId: cfg.nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: cfg.isListed,
      requiresApproval: cfg.requiresApproval,
      acceptFrom: cfg.acceptFrom,
      allowBorrowing: cfg.allowBorrowing,
      // Re-assert location: this path republishes keys/relay and would
      // otherwise wipe the user's city on every contact-sync flow.
      locationCountry: loc.country,
      locationCityId: loc.cityId,
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
    if (kDebugMode)
      debugPrint('HubDirectoryProvider: ensured keys + relay published');

    // Now that our key is on the hub, sync contact blobs to followers
    if (_contactInfo.isNotEmpty) {
      await syncContactToFollowers();
    }
  }

  /// Whether borrowing is enabled in the current config.
  bool get allowBorrowing => _config?.allowBorrowing ?? true;

  /// Registers or updates the public profile on the hub.
  ///
  /// [bookCount] is no longer what the hub stores: the Rust side derives the
  /// public number from the catalog it pushes, so the library header can never
  /// announce books a follower cannot see. The parameter is kept because the
  /// FFI struct still carries the field.
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
    int? locationCityId,
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
    final effectiveFp =
        deviceFingerprint ?? await _deviceService.getDeviceFingerprint();
    final effectiveAppVersion =
        appVersion ?? await _deviceService.getAppVersion();
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
      locationCityId: locationCityId,
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
          final recoveryCode =
              await _ffi.hubDirectoryGetRecoveryCode() ??
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
                debugPrint(
                  'HubDirectoryProvider: 401 recovery via recovery_code succeeded',
                );
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
  ///
  /// ADR-035 Phase 2: passing [country] and/or [cityId] activates the
  /// location filter. Both default to keeping the current filter values
  /// so a search-only refresh does not silently drop them; pass
  /// `clearLocationFilter: true` to wipe both at once.
  Future<void> loadDirectory({
    String? search,
    String? country,
    int? cityId,
    bool clearLocationFilter = false,
  }) async {
    _profiles = [];
    _offset = 0;
    _hasMore = true;
    _listError = null;
    _searchQuery = (search != null && search.trim().isNotEmpty)
        ? search.trim()
        : null;
    if (clearLocationFilter) {
      _filterCountry = null;
      _filterCityId = null;
    } else {
      if (country != null) {
        final trimmed = country.trim().toUpperCase();
        _filterCountry = trimmed.isEmpty ? null : trimmed;
      }
      if (cityId != null) {
        // 0 / negative is the explicit "drop city filter" sentinel; the
        // caller can keep country alone by passing `cityId: 0`.
        _filterCityId = cityId > 0 ? cityId : null;
      }
    }
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
        country: _filterCountry,
        cityId: _filterCityId,
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
      final libraryName =
          prefs.getString('libraryName') ??
          TranslationService.translateByLocale(
            prefs.getString('languageCode') ?? 'en',
            'my_library_title',
          );
      final bookCount = await _ffi.countBooks();

      String? x25519Key;
      try {
        x25519Key = await _ffi.getLocalX25519PublicKey();
      } catch (_) {}

      final deviceModel = await _deviceService.getDeviceModel();
      final deviceFingerprint = await _deviceService.getDeviceFingerprint();
      final appVersion = await _deviceService.getAppVersion();

      final relay = await _getRelayCredentials();
      final loc = await _currentLocationForRegister();

      return await register(
        nodeId: libraryUuid,
        displayName: libraryName,
        bookCount: bookCount,
        isListed: false,
        requiresApproval: false,
        acceptFrom: 'anyone',
        allowBorrowing: false,
        // Silent re-registration must not blank the city: a user who set
        // it via Settings before a config-purge / Keychain recovery would
        // otherwise lose it on the next silent re-register.
        locationCountry: loc.country,
        locationCityId: loc.cityId,
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
  ///  1. [setHubEnabled](true) - unlocks hub features locally.
  ///  2. Register on the hub with `isListed: true` (re-uses 401 recovery).
  ///  3. Publish relay credentials so followers can reach us.
  ///  4. Push the ISBN catalog so new followers see books immediately.
  ///  5. Subscribe to the relay nudge stream for real-time updates.
  ///
  /// Returns `true` when the hub register succeeded. Catalog push + relay
  /// publish happen best-effort on success (same pattern as
  /// [initAndSyncCatalog]) - they retry automatically via the existing
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

    // Privacy-first defaults for a FIRST publication (no existing config):
    //   - requiresApproval = true   → catalog access is opt-in per follower
    //   - allowBorrowing   = false  → no unsolicited physical-loan requests
    // If the user has already configured the library (e.g. from Settings),
    // preserve their choice instead of forcing the defaults back on.
    final requiresApproval = _config?.requiresApproval ?? true;
    final allowBorrowing = _config?.allowBorrowing ?? false;

    final loc = await _currentLocationForRegister();
    final ok = await register(
      nodeId: nodeId,
      displayName: displayName,
      bookCount: bookCount,
      isListed: true,
      requiresApproval: requiresApproval,
      acceptFrom: _config?.acceptFrom ?? 'everyone',
      allowBorrowing: allowBorrowing,
      // Caller's [locationCountry] wins (publish flow may declare a fresh
      // country); fall back to the country derived from the local city
      // when the caller did not specify one.
      locationCountry: (trimmedCountry != null && trimmedCountry.isNotEmpty)
          ? trimmedCountry
          : loc.country,
      // Re-assert local cityId so publishing the library does not blank a
      // city that the user already picked from Settings.
      locationCityId: loc.cityId,
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

  // NOTE: the manual "reclaim with recovery code" flow was removed with its
  // UI (the code is internal-only now); recovery via the stored code lives in
  // the automatic 401 self-heal above.

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
        debugPrint(
          '[CONTACT-READ]   follow id=${f.id} node=${f.followedNodeId.substring(0, 8)}... '
          'contact=${f.encryptedContact != null ? "${f.encryptedContact!.length}ch" : "null"}',
        );
      }
      _resolveNames(_following.map((f) => f.followedNodeId).toList());
    } catch (e) {
      debugPrint('HubDirectoryProvider loadFollowing error: $e');
    }
    notifyListeners();
  }

  Future<void> loadFollowers() async {
    try {
      final raw = await _ffi.hubDirectoryListFollowers();
      _followers = raw.map(HubFollow.fromFrb).toList();
      _resolveNames(_followers.map((f) => f.followerNodeId).toList());
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
      _resolveNames(_pendingRequests.map((f) => f.followerNodeId).toList());
    } catch (e) {
      debugPrint('HubDirectoryProvider loadPendingRequests error: $e');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Paired-peer follow reconciliation (ADR-053)
  // ---------------------------------------------------------------------------

  /// Guard against overlapping reconciliation runs (startup + nudge bursts).
  bool _reconcilingFollows = false;

  /// nodeIds an auto-follow was already sent for in this session, so a peer
  /// that has not approved yet is not re-requested on every nudge.
  final Set<String> _autoFollowRequested = {};

  /// ADR-053: materialize P2P pairings as mutual hub follows.
  ///
  /// A paired peer already holds far stronger privileges than a follower
  /// (live catalog sync, loans, E2EE messaging), yet the hub's catalog
  /// endpoint only understands follows: when either side publishes in the
  /// public directory with requires_approval, the other side's offline
  /// hub-catalog fallback dies with a 403. This reconciliation:
  ///   1. follows every accepted paired peer not already followed,
  ///   2. approves pending incoming follow requests from accepted paired
  ///      peers, attaching the sealed contact blob like a manual approval.
  /// Runs at startup, after accepting a pairing, and on relay nudges;
  /// no-ops quickly when there is nothing to do.
  ///
  /// [refreshLists] - when true (default), re-fetches the following and
  /// pending lists from the hub before reconciling. Pass false only when the
  /// caller just refreshed them itself (the nudge handler does), to avoid
  /// duplicate GETs on every nudge.
  Future<void> reconcilePairedPeerFollows({bool refreshLists = true}) async {
    if (_reconcilingFollows) return;
    if (!isRegistered) return;
    final api = _apiService;
    if (api == null) return;

    _reconcilingFollows = true;
    try {
      final pairedUuids = await _acceptedPairedPeerUuids(api);
      if (pairedUuids.isEmpty) return;

      if (refreshLists) {
        await Future.wait([loadFollowing(), loadPendingRequests()]);
      }

      // 1. Outgoing: follow paired peers we do not follow yet.
      final followed = _following.map((f) => f.followedNodeId).toSet();
      for (final uuid in pairedUuids) {
        if (followed.contains(uuid)) continue;
        if (!_autoFollowRequested.add(uuid)) continue;
        debugPrint('[ADR-053] auto-follow paired peer $uuid');
        final ok = await follow(uuid);
        if (!ok) {
          // Transient failure (hub down, network): allow the next trigger
          // (nudge or startup) to retry instead of blocking until restart.
          _autoFollowRequested.remove(uuid);
          debugPrint(
            '[ADR-053] auto-follow failed for $uuid '
            '(${_actionError ?? "unknown"})',
          );
        }
      }

      // 2. Incoming: approve pending requests from paired peers. The pending
      // list was refreshed above (or by the nudge handler); our own outgoing
      // follows in step 1 cannot have changed it.
      final fromPaired = _pendingRequests
          .where((f) => pairedUuids.contains(f.followerNodeId))
          .toList();
      for (final req in fromPaired) {
        String? blob;
        final key = req.followerX25519PublicKey;
        if (key != null && key.isNotEmpty) {
          blob = await sealContactFor(key);
        }
        debugPrint(
          '[ADR-053] auto-approve follow ${req.id} from paired peer '
          '${req.followerNodeId}',
        );
        await resolveFollow(req.id, 'approve', encryptedContact: blob);
      }
    } catch (e) {
      debugPrint('[ADR-053] reconcilePairedPeerFollows error: $e');
    } finally {
      _reconcilingFollows = false;
    }
  }

  /// Library uuids of accepted paired peers, excluding self and placeholder
  /// ids (peer rows created before the uuid handshake completed).
  Future<Set<String>> _acceptedPairedPeerUuids(ApiService api) async {
    final uuids = <String>{};
    try {
      final res = await api.getPeers();
      final data = res.data;
      final list = (data is Map ? data['data'] : data) as List? ?? const [];
      for (final raw in list) {
        if (raw is! Map) continue;
        final status = raw['connection_status'] as String? ?? 'accepted';
        if (status != 'accepted') continue;
        final uuid = raw['library_uuid'] as String?;
        if (uuid == null || uuid.isEmpty) continue;
        if (FfiService.isPlaceholderNodeId(uuid)) continue;
        if (uuid == _config?.nodeId) continue;
        uuids.add(uuid);
      }
    } catch (e) {
      debugPrint('[ADR-053] getPeers failed during reconcile: $e');
    }
    return uuids;
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
  Future<bool> resolveFollow(
    int followId,
    String resolution, {
    String? encryptedContact,
  }) async {
    final key = _resolveFollowKey(followId);
    _busyNodes.add(key);
    _actionError = null;
    notifyListeners();

    try {
      final result = await _ffi.hubDirectoryResolveFollow(
        followId,
        resolution,
        encryptedContact: encryptedContact,
      );
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
      if (count >= 0) {
        _catalogDirty = false;
        await _recordCatalogPush();
      }
      debugPrint('HubDirectoryProvider syncCatalog: pushed $count ISBNs');
      return count;
    } catch (e) {
      debugPrint('HubDirectoryProvider syncCatalog error: $e');
      return -1;
    }
  }

  /// Persist the wall-clock time of a successful catalog push so the keep-alive
  /// check ([_isHubCatalogStale]) can re-push before the hub TTL prunes us.
  Future<void> _recordCatalogPush() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kLastCatalogPushKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// True when the hub copy of our catalog is going stale and should be
  /// re-pushed even though nothing changed locally. A missing timestamp counts
  /// as stale so the very first lifecycle hook establishes the baseline.
  Future<bool> _isHubCatalogStale() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMs = prefs.getInt(_kLastCatalogPushKey);
    if (lastMs == null) return true;
    final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
    return DateTime.now().difference(last) >= catalogKeepAliveInterval;
  }

  /// Push catalog on lifecycle hooks (startup / app resume).
  ///
  /// Pushes when the local catalog changed since the last push, OR as a
  /// keep-alive when the hub copy is going stale (so a library that never
  /// changes is not pruned by the hub TTL, which would leave the directory
  /// fallback empty for peers that cannot reach us live). Also retries relay
  /// credential publishing if it failed at startup.
  Future<void> syncCatalogIfDirty() async {
    // Push catalog when registered, regardless of isListed.
    // isListed controls discoverability by strangers; catalog push enables
    // browsing by known peers who have the nodeId (via invite link).
    if (!isRegistered) return;

    // Retry relay publish if it failed during startup (network instability).
    // Enforces a cooldown to avoid hammering the hub every 30s.
    if (!_relayPublished) {
      final last = _lastRelayAttempt;
      if (last == null || DateTime.now().difference(last) >= relayCooldown) {
        await ensureRelayPublished();
      }
    }

    // A local change always wins: push immediately and refresh the timestamp.
    if (_catalogDirty) {
      await syncCatalog();
      return;
    }

    // Nothing changed locally: re-push only if the hub copy is going stale.
    // syncCatalog() dedupes by hash on the hub side, so this is near-free.
    if (await _isHubCatalogStale()) {
      debugPrint('HubDirectory: catalog stale, keep-alive re-push');
      await syncCatalog();
    }
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
      await _ffi.hubDirectoryCreateBorrowRequest(lenderNodeId, isbn, bookTitle);
      return true;
    } catch (e) {
      debugPrint('HubDirectoryProvider createBorrowRequest error: $e');
      rethrow;
    }
  }

  /// Load incoming hub borrow requests (as lender).
  Future<void> loadIncomingHubRequests() async {
    try {
      _incomingHubRequests = await _ffi.hubDirectoryIncomingBorrowRequests();
    } catch (e) {
      debugPrint('HubDirectoryProvider loadIncomingHubRequests error: $e');
    }
    notifyListeners();
  }

  /// Load outgoing hub borrow requests (as requester).
  Future<void> loadOutgoingHubRequests() async {
    try {
      _outgoingHubRequests = await _ffi.hubDirectoryOutgoingBorrowRequests();
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
      debugPrint(
        'HubDirectoryProvider cancelHubBorrowRequest: $e - dismissing locally',
      );
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
    debugPrint(
      '[CONTACT-SYNC] starting, contact="${_contactInfo.substring(0, _contactInfo.length.clamp(0, 30))}..."',
    );
    try {
      final followersList = await _ffi.hubDirectoryListFollowers();
      final followers = followersList.map(HubFollow.fromFrb).toList();
      debugPrint(
        '[CONTACT-SYNC] ${followers.length} followers total, '
        '${followers.where((f) => f.isActive).length} active',
      );

      final followIds = <int>[];
      final blobs = <String>[];

      for (final f in followers) {
        if (!f.isActive) {
          debugPrint(
            '[CONTACT-SYNC] follower ${f.followerNodeId.substring(0, 8)}... status=${f.status}, skipping',
          );
          continue;
        }
        final key = f.followerX25519PublicKey;
        if (key == null || key.isEmpty) {
          debugPrint(
            '[CONTACT-SYNC] follower ${f.followerNodeId.substring(0, 8)}... has NO x25519 key, skipping',
          );
          continue;
        }
        debugPrint(
          '[CONTACT-SYNC] follower ${f.followerNodeId.substring(0, 8)}... has key ${key.substring(0, 8)}..., sealing',
        );
        final blob = await sealContactFor(key);
        if (blob != null) {
          followIds.add(f.id);
          blobs.add(blob);
          debugPrint(
            '[CONTACT-SYNC] sealed blob for follow_id=${f.id}, blob len=${blob.length}',
          );
        } else {
          debugPrint(
            '[CONTACT-SYNC] sealContactFor returned null for follower ${f.followerNodeId.substring(0, 8)}...',
          );
        }
      }

      if (followIds.isNotEmpty) {
        debugPrint(
          '[CONTACT-SYNC] pushing ${followIds.length} blobs to hub...',
        );
        await _ffi.hubDirectorySyncContacts(followIds, blobs);
        debugPrint('[CONTACT-SYNC] push done');
      } else {
        debugPrint(
          '[CONTACT-SYNC] no blobs to push (0 eligible followers with keys)',
        );
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
      return _following.firstWhere((f) => f.followedNodeId == nodeId).status;
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

  /// True when [nodeId] has an incoming pending follow request to us
  /// (= this library is waiting for our approval). Used by the Discover
  /// tab to surface a "wants to follow you" marker on their card.
  bool hasIncomingFollowRequestFrom(String nodeId) {
    return _pendingRequests.any((f) => f.followerNodeId == nodeId);
  }

  /// Resolves a node ID to a display name.
  /// Priority: user custom name > name cache > directory profiles.
  String? displayNameFor(String nodeId) {
    final custom = _customFollowNames[nodeId];
    if (custom != null) return custom;
    final cached = _nameCache[nodeId];
    if (cached != null) return cached;
    try {
      final name = _profiles.firstWhere((p) => p.nodeId == nodeId).displayName;
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
        .where((id) => !_nameCache.containsKey(id) && !_isCachedNotFound(id))
        .toSet();
    if (unknown.isEmpty) return;

    // Fire-and-forget: fetch each profile and update cache.
    for (final id in unknown) {
      _ffi
          .hubDirectoryGetProfile(id)
          .then((profile) {
            if (profile != null) {
              _nameCache[id] = profile.displayName;
              _notFoundCache.remove(id);
              _cacheAvatar(id, profile.avatarConfig);
              notifyListeners();
            }
          })
          .catchError((e) {
            if (e.toString().contains('Hub error 404')) {
              _notFoundCache[id] = DateTime.now();
            }
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
