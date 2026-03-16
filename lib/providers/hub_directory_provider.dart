import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/hub_directory.dart';
import '../services/auth_service.dart';
import '../services/device_service.dart';
import '../services/ffi_service.dart';
import '../src/rust/api/frb.dart' as frb;

/// Page size for directory listing.
const int _kPageSize = 20;

/// State manager for the public hub directory feature (ADR-015).
///
/// Responsibilities:
/// - Local config (is_listed, requires_approval, accept_from)
/// - Directory browsing with pagination
/// - Follow/unfollow actions
/// - Incoming follow request management (approve / reject / block)
/// - Pending request count for badge display
/// - Hub-mediated borrow requests (ADR-018)
/// SharedPreferences key for the experimental hub directory toggle.
const String _kHubEnabledKey = 'hub_directory_enabled';

/// SharedPreferences key for the local contact info (plaintext, never sent to hub).
const String _kContactInfoKey = 'hub_contact_info';

/// SharedPreferences key for the local website URL (sent plaintext to hub profile).
const String _kWebsiteKey = 'hub_website';

/// SharedPreferences key for user-defined follow display names (JSON map).
const String _kFollowNamesKey = 'hub_follow_custom_names';

class HubDirectoryProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();
  final DeviceService _deviceService = DeviceService();

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

  // ── Experimental toggle ─────────────────────────────────────────────────

  bool _hubEnabled = false;

  /// Whether the hub directory feature is enabled by the user.
  bool get isHubEnabled => _hubEnabled;

  /// Load the toggle state from SharedPreferences. Call at app start.
  Future<void> loadHubEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    _hubEnabled = prefs.getBool(_kHubEnabledKey) ?? false;
    notifyListeners();
  }

  /// Enable or disable the hub directory feature.
  Future<void> setHubEnabled(bool value) async {
    _hubEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHubEnabledKey, value);
    notifyListeners();
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
  Future<void> initAndSyncCatalog() async {
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
        syncCatalogIfDirty();
      }
    } catch (e) {
      debugPrint('HubDirectory: initAndSyncCatalog error: $e');
    }
  }

  Future<void> loadConfig() async {
    _configLoading = true;
    _configError = null;
    notifyListeners();

    try {
      final frbConfig = await _ffi.hubDirectoryGetConfig();
      _config =
          frbConfig != null ? DirectoryConfig.fromFrb(frbConfig) : null;
    } catch (e) {
      _configError = e.toString();
      debugPrint('HubDirectoryProvider loadConfig error: $e');
    } finally {
      _configLoading = false;
      notifyListeners();
    }
  }

  /// Re-registers with the current config to ensure the X25519 public key
  /// is published on the hub profile. Call at app start for existing users.
  Future<void> ensureKeysPublished(String displayName) async {
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
    );
    debugPrint('HubDirectoryProvider: ensured X25519 key published');

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
  }) async {
    _configLoading = true;
    _configError = null;
    notifyListeners();

    try {
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
        deviceModel: deviceModel,
        deviceFingerprint: deviceFingerprint,
      );
      final result = await _ffi.hubDirectoryRegister(params);
      if (result != null) {
        _config = DirectoryConfig.fromFrb(result);
        return true;
      }
      return false;
    } catch (e) {
      _configError = e.toString();
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
      final newProfiles = batch.map(HubProfile.fromFrb).toList();
      _profiles.addAll(newProfiles);
      _offset += newProfiles.length;
      _hasMore = newProfiles.length == _kPageSize;
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
      final libraryUuid = await AuthService().getOrCreateLibraryUuid();
      final prefs = await SharedPreferences.getInstance();
      final libraryName = prefs.getString('libraryName') ?? 'My Library';
      final bookCount = await _ffi.countBooks();

      String? x25519Key;
      try {
        x25519Key = await _ffi.getLocalX25519PublicKey();
      } catch (_) {}

      final deviceModel = await _deviceService.getDeviceModel();
      final deviceFingerprint = await _deviceService.getDeviceFingerprint();

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
      );
    } catch (e) {
      debugPrint('HubDirectoryProvider _ensureSilentRegistration error: $e');
      return false;
    }
  }

  /// Auto-register with is_listed=false if not yet registered.
  /// Enables catalog push for known peers without public listing.
  Future<bool> ensureRegistered() async {
    if (isRegistered) return true;
    final ok = await _ensureSilentRegistration();
    if (ok) await loadConfig();
    return ok;
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
  Future<void> syncCatalogIfDirty() async {
    // Push catalog when registered, regardless of isListed.
    // isListed controls discoverability by strangers; catalog push enables
    // browsing by known peers who have the nodeId (via invite link).
    if (!_catalogDirty || !isRegistered) return;
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
