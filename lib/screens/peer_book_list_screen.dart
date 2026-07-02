import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../models/book.dart';
import '../utils/cover_url_resolver.dart';
import '../models/hub_directory.dart';
import '../widgets/book_cover_card.dart';
import '../widgets/bookshelf_view.dart';
import '../widgets/hub_location_label.dart';
import '../widgets/cached_book_cover.dart';
import '../widgets/peer_book_cover_cache_manager.dart';
import '../widgets/recently_added_carousel.dart';
import '../widgets/shimmer_loading.dart';
import '../services/translation_service.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../services/mdns_service.dart';
import '../src/rust/api/frb.dart'
    show
        FrbCatalogChangedEvent,
        setPeerDeltaCursor,
        subscribeCatalogChanges,
        tryPeerCatalogDeltaDetailed,
        updatePeerLibraryUuid;

enum _PeerViewMode { coverGrid, shelf, list }

class PeerBookListScreen extends StatefulWidget {
  final int peerId;
  final String peerName;
  final String peerUrl;

  /// Whether this peer has relay credentials (relay_url + mailbox_id).
  /// When false, relay sync is skipped and an offline state is shown instead.
  final bool hasRelayCredentials;

  /// Hub directory node ID for this library. When set and P2P/cache/relay all
  /// fail, the screen falls back to displaying the hub catalog as BookSpines.
  final String? nodeId;

  /// User-defined caption (légende) for this peer, shown as subtitle.
  final String? caption;

  /// Pre-fill search field on open (e.g. from wishlist_match notification).
  final String? initialSearch;

  const PeerBookListScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerUrl,
    this.hasRelayCredentials = false,
    this.nodeId,
    this.caption,
    this.initialSearch,
  });

  @override
  State<PeerBookListScreen> createState() => _PeerBookListScreenState();
}

class _PeerBookListScreenState extends State<PeerBookListScreen> {
  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  bool _isLoading = true;
  _PeerViewMode _viewMode = _PeerViewMode.coverGrid;
  bool _isPeerOnline = true;
  String? _lastSynced;
  bool _isSyncing = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  /// Background refresh state (cache-first pattern)
  bool _isRefreshing = false;

  /// Relay sync state (ADR-012)
  bool _isRelayLoading = false;
  bool _relaySyncDone = false; // true once relay sync completes successfully
  int _relayBooksLoaded = 0;
  int _relayBooksTotal = 0;
  Timer? _pollTimer;
  bool _pollRequestInFlight = false;

  /// Subscription to real-time catalog-change events from the peer (ADR-017).
  StreamSubscription<FrbCatalogChangedEvent>? _catalogChangeSub;

  /// When the peer reports `reset_required:<N>` (ADR-029), we cannot adopt
  /// `N` as the new `peers.last_delta_cursor` before the legacy full-catalog
  /// flow rebuilds the cache (doing so would skip over rows we never applied
  /// and leave a permanent data gap). We stash `N` here on reset_required
  /// receipt and persist it only from the success path of `_fetchRelayPages`.
  /// Scope: in-memory for the current mount. If the user navigates away
  /// before the fallback finishes, we drop the opportunity and the next
  /// visit simply retries the reset cycle (still correct, just one extra
  /// round-trip).
  int? _pendingDeltaCursor;

  /// Hub catalog fallback: true when books come from hub (limited metadata)
  bool _isHubOnly = false;

  /// Hub contact info (decrypted)
  String? _decryptedContact;
  HubProfile? _hubProfile;

  /// ISBNs with a pending outgoing borrow request (to disable the borrow button)
  Set<String> _pendingBorrowIsbns = {};

  /// ISBNs of books currently borrowed from this peer (accepted outgoing request).
  Set<String> _activeBorrowIsbns = {};

  /// ISBNs of books currently lent to this peer (accepted incoming request).
  Set<String> _lendingIsbns = {};

  /// Pagination state for live P2P loading
  int _currentPage = 0;
  int _totalBooks = 0;
  bool _hasMorePages = false;
  bool _isLoadingMore = false;
  bool _allBooksLoaded = false;
  static const int _pageSize = 20;

  /// LAN URL resolved from mDNS (overrides relay:// URL for this session)
  String? _lanUrl;

  /// Node ID resolved from mDNS (overrides peer_XX fallback)
  String? _resolvedNodeId;

  /// True when _lanUrl was resolved by UUID (trusted), false = name match (needs validation)
  bool _lanUrlTrusted = false;

  /// Effective peer URL: mDNS LAN URL if resolved, otherwise saved URL.
  String get _effectiveUrl => _lanUrl ?? widget.peerUrl;

  /// Effective node ID: mDNS libraryId if resolved, otherwise widget.nodeId.
  String? get _effectiveNodeId => _resolvedNodeId ?? widget.nodeId;

  /// Resolves a book's cover URL for peer context.
  ///
  /// Delegates to `CoverUrlResolver.resolveForPeer`, which reads the
  /// raw persisted cover URL (never the OpenLibrary fallback): the peer
  /// is the authoritative source for its covers, so substituting a
  /// third-party image would create visual inconsistency between what
  /// the uploader sees and what the visitor sees.
  String? _resolvePeerCoverUrl(Book book) => CoverUrlResolver.resolveForPeer(
    coverUrl: book.rawCoverUrl,
    bookId: book.id,
    peerUrl: _effectiveUrl,
  );

  /// Evict the cached cover image and force a rebuild so the widget retries.
  Future<void> _reloadCover(Book book) async {
    final url = _resolvePeerCoverUrl(book);
    if (url != null) {
      // Peer covers live in their own cache since the peer cap is
      // user-controlled and must not evict local covers.
      await PeerBookCoverCacheManager.instance.removeFile(url);
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _isSearching = true;
      _searchController.text = widget.initialSearch!;
    }
    _loadCachedBooksFirst();
    _loadHubContactInfo();
    _loadPendingBorrowRequests();
    _subscribeCatalogChanges();
  }

  Future<void> _loadHubContactInfo() async {
    final nodeId = widget.nodeId;
    if (nodeId == null) return;
    final provider = context.read<HubDirectoryProvider>();
    if (!provider.isHubEnabled) return;

    // Decrypt contact blob from follow
    final follow = provider.followFor(nodeId);
    final blob = follow?.encryptedContact;
    if (blob != null && blob.isNotEmpty) {
      final plaintext = await provider.openContact(blob);
      if (mounted && plaintext != null) {
        setState(() => _decryptedContact = plaintext);
      }
    }

    // Fetch hub profile for website and refresh cached display name
    try {
      final frbProfile = await FfiService().hubDirectoryGetProfile(nodeId);
      if (mounted && frbProfile != null) {
        setState(() => _hubProfile = HubProfile.fromFrb(frbProfile));
      }
      // Refresh hub name cache so the network list picks up name changes
      provider.refreshName(nodeId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pollTimer?.cancel();
    _catalogChangeSub?.cancel();
    super.dispose();
  }

  /// Subscribe to real-time catalog-change events from the peer (ADR-017).
  ///
  /// When the Mac adds or removes a book it sends a `catalog_changed` relay
  /// message. The Rust relay poller decrypts it and emits a
  /// [FrbCatalogChangedEvent] on the FRB stream. This method wires that
  /// stream to a re-sync so the iPhone sees the new book within 1-3 s.
  ///
  /// Matching uses both [widget.peerId] (local DB row) and the remote
  /// library UUID so the screen responds correctly regardless of whether
  /// the peer was resolved via mDNS or relay.
  ///
  /// INVARIANT -- do not eagerly fetch peer cover bytes in this handler
  /// or in any catalog-sync code path. Covers must stay lazy: the user
  /// only pays the network + disk cost when a [CachedNetworkImage] is
  /// mounted in the visible grid/list. This is enforced by the peer
  /// cover cache cap (Settings) and the toggle gate in [build]; a
  /// prefetch loop here would bypass both.
  void _subscribeCatalogChanges() {
    _catalogChangeSub?.cancel();
    debugPrint(
      '[DEBUG-CATALOG] _subscribeCatalogChanges WIRED: '
      'widget.peerId=${widget.peerId}, effectiveNodeId="$_effectiveNodeId"',
    );
    _catalogChangeSub = subscribeCatalogChanges().listen(
      (FrbCatalogChangedEvent event) {
        // Match by local peer ID or by library UUID (whichever is available).
        final matchById = widget.peerId > 0 && event.peerId == widget.peerId;
        final resolvedUuid = _effectiveNodeId;
        final matchByUuid =
            resolvedUuid != null &&
            resolvedUuid.isNotEmpty &&
            event.peerLibraryUuid.isNotEmpty &&
            event.peerLibraryUuid == resolvedUuid;

        // DEBUG ADR-029: log every event reaching this listener with the
        // match computation so we can tell whether the event is arriving
        // at all and, if so, why it does (or does not) match the screen.
        debugPrint(
          '[DEBUG-CATALOG] EVENT received: event.peerId=${event.peerId}, '
          'event.uuid="${event.peerLibraryUuid}", '
          'widget.peerId=${widget.peerId}, effectiveNodeId="$resolvedUuid" '
          '-> matchById=$matchById, matchByUuid=$matchByUuid, '
          'isSyncing=$_isSyncing, isRelayLoading=$_isRelayLoading',
        );

        if (!matchById && !matchByUuid) {
          debugPrint('[DEBUG-CATALOG] EVENT DROPPED (no match)');
          return;
        }

        // Guard against redundant syncs: _syncBooks already has its own
        // _isSyncing guard, but checking here avoids even dispatching.
        if (_isSyncing || _isRelayLoading) {
          debugPrint('[DEBUG-CATALOG] EVENT SKIPPED (sync already in flight)');
          return;
        }

        debugPrint(
          'PeerBookList: catalog changed from peer ${event.peerId} '
          '(uuid=${event.peerLibraryUuid}), attempting delta sync (ADR-029)',
        );
        // ADR-029: try the delta path first. On success, peer_books is
        // already up to date on the Rust side — reload the local cache
        // into the UI and skip the legacy manifest+pages round-trip.
        // On failure (reset, old peer, E2EE unavailable, transport error)
        // fall back to `_syncBooks` which runs the ADR-012 full flow.
        _deltaSyncThenReload(event.peerId);
      },
      onError: (Object e) =>
          debugPrint('PeerBookList: catalog change stream error: $e'),
      cancelOnError: false,
    );
  }

  /// ADR-029: call the Rust delta orchestrator. On success, reload the
  /// local `peer_books` cache into the UI without any network round-trip.
  ///
  /// When [fallbackOnFailure] is true (default), a non-applied delta falls
  /// back to the legacy `_syncBooks` flow. Pass `false` for fire-and-forget
  /// background triggers (e.g. screen mount auto-refresh) where stalling on
  /// the legacy flow for an offline peer is undesirable.
  Future<void> _deltaSyncThenReload(
    int peerId, {
    bool fallbackOnFailure = true,
  }) async {
    if (!mounted) return;
    if (peerId <= 0) {
      // Without a local peer row id we cannot drive the delta orchestrator;
      // fall back to the legacy flow straight away.
      if (fallbackOnFailure) _syncBooks(showFeedback: false);
      return;
    }

    String outcome = 'error:unknown';
    try {
      outcome = await tryPeerCatalogDeltaDetailed(peerId: peerId);
    } catch (e) {
      outcome = 'error:threw:$e';
    }
    debugPrint('[DELTA-OUTCOME] peer=$peerId outcome=$outcome');
    final applied = outcome.startsWith('applied:');

    if (!mounted) return;

    // `reset_required` (optionally suffixed `:<N>`) means the peer
    // responded but our saved cursor is older than its retained delta log
    // (log pruned or recreated). The peer is online so the legacy
    // full-catalog sync will succeed quickly: run it even on background
    // triggers, otherwise the UI stays stale until the next manual refresh.
    //
    // When the suffix is present (ADR-029 current_cursor), stash it in
    // `_pendingDeltaCursor`: the legacy `_fetchRelayPages` success path
    // will persist it via `setPeerDeltaCursor`, breaking the reset loop
    // on the next visit. Stashing happens BEFORE triggering the fallback
    // so the value is observable when the fallback completes.
    final resetRequired =
        outcome == 'reset_required' || outcome.startsWith('reset_required:');
    if (resetRequired) {
      final colon = outcome.indexOf(':');
      if (colon > 0) {
        final cursor = int.tryParse(outcome.substring(colon + 1));
        if (cursor != null && cursor > 0) {
          _pendingDeltaCursor = cursor;
          debugPrint(
            '[DELTA-RESET] peer=$peerId stashed pending cursor=$cursor '
            '(will be persisted after successful legacy sync)',
          );
        }
      }
    }
    if (!applied && (fallbackOnFailure || resetRequired)) {
      debugPrint(
        'PeerBookList: delta not applied (outcome=$outcome), running legacy sync',
      );
      _syncBooks(showFeedback: false);
      return;
    }

    if (!applied) {
      debugPrint(
        'PeerBookList: delta not applied (outcome=$outcome), skipping legacy '
        '(background trigger, peer may be offline)',
      );
      return;
    }

    // Reload cache regardless of the `applied` flag. Even when this call
    // returned `false` (cursor ambiguity, timeout, concurrent request), the
    // local `peer_books` table may have been updated by a delta that ran
    // earlier in this session — the orchestrator writes to SQLite before
    // returning — while the UI still holds the stale snapshot from the
    // initial mount-time cache load. Refreshing from SQLite here brings the
    // display back in sync without any extra network cost.
    debugPrint(
      'PeerBookList: reloading from cache (delta applied=$applied, '
      'fallbackOnFailure=$fallbackOnFailure, _books.length=${_books.length})',
    );
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final cachedRes = await api.getCachedPeerBooks(widget.peerUrl);
      if (!mounted) return;
      final data = cachedRes.data;
      final booksData = (data['books'] as List<dynamic>?) ?? [];
      debugPrint(
        '[DEBUG-CATALOG] cache reload: got ${booksData.length} books from '
        'peer_books (previously _books.length=${_books.length})',
      );
      setState(() {
        _books = booksData.map((json) => Book.fromJson(json)).toList();
        _filteredBooks = _isSearching && _searchController.text.isNotEmpty
            ? _books
                  .where((b) => _matchesSearch(b, _searchController.text))
                  .toList()
            : _books;
        _lastSynced = data['last_synced'] as String?;
      });
    } catch (e) {
      debugPrint('PeerBookList: cache reload after delta failed: $e');
      // Cache reload failed — fall back to full sync so the user still
      // sees the update, even if it costs bandwidth. Only trigger the
      // fallback when the caller allows it; background triggers stay
      // quiet on failure.
      if (mounted && fallbackOnFailure) _syncBooks(showFeedback: false);
    }
  }

  /// Try to resolve a LAN URL from mDNS when the saved URL is relay://.
  /// UUID-based matches are trusted immediately. Name-based matches are
  /// stored as candidates and validated after connectivity check by fetching
  /// the peer's /api/config to confirm identity.
  void _tryResolveLanUrl() {
    if (!widget.peerUrl.startsWith('relay://')) return;

    DiscoveredPeer? nameCandidate;

    for (final p in MdnsService.peers) {
      // 1. Match by libraryId (UUID) — trusted, no validation needed
      if (widget.nodeId != null &&
          !FfiService.isPlaceholderNodeId(widget.nodeId!) &&
          p.libraryId == widget.nodeId) {
        _lanUrl = 'http://${p.host}:${p.port}';
        _lanUrlTrusted = true;
        if (kDebugMode)
          debugPrint('mDNS: resolved relay peer via LAN (by UUID)');
        return;
      }
      // 2. Name-based candidate (needs validation)
      if (nameCandidate == null && p.name == widget.peerName) {
        nameCandidate = p;
      }
    }

    // Store name candidate for validation during connectivity check
    if (nameCandidate != null) {
      _lanUrl = 'http://${nameCandidate.host}:${nameCandidate.port}';
      _lanUrlTrusted = false;
      if (nameCandidate.libraryId != null) {
        _resolvedNodeId = nameCandidate.libraryId;
      }
      if (kDebugMode)
        debugPrint('mDNS: LAN candidate by name (pending validation)');
    } else {
      if (kDebugMode) debugPrint('mDNS: no LAN match for relay peer');
    }
  }

  /// Validate a name-matched mDNS candidate by fetching /api/config from the
  /// LAN URL via ApiService. Confirms this is a BiblioGenius peer and captures
  /// the library_uuid for hub catalog and future UUID-based matching.
  Future<bool> _validateLanCandidate(ApiService api, String lanUrl) async {
    final uuid = await api.fetchPeerLibraryUuid(lanUrl);
    if (uuid != null && uuid.isNotEmpty) {
      _resolvedNodeId = uuid;
      _lanUrlTrusted = true;
      if (kDebugMode) debugPrint('mDNS: validated candidate');
      return true;
    }
    // fetchPeerLibraryUuid returned null — peer might be unreachable at
    // /api/config or might be an old version without library_uuid.
    // Since connectivity check already passed, accept the candidate.
    _lanUrlTrusted = true;
    return true;
  }

  /// Try to backfill library_uuid for peers that don't have one yet.
  /// Fetches /api/config from the peer's LAN URL (deterministic, unique).
  /// This handles legacy peers connected before library_uuid was introduced.
  Future<String?> _backfillLibraryUuid() async {
    final api = Provider.of<ApiService>(context, listen: false);
    // Only attempt from LAN URL — relay URLs can't be HTTP-fetched
    final url =
        _lanUrl ??
        (widget.peerUrl.startsWith('relay://') ? null : widget.peerUrl);
    if (url == null) return null;

    final uuid = await api.fetchPeerLibraryUuid(url);
    if (uuid != null && uuid.isNotEmpty) {
      if (kDebugMode) debugPrint('Backfill: resolved library_uuid');
      // Persist so this lookup never has to happen again
      if (widget.peerId > 0) {
        api
            .updatePeerUrl(widget.peerId, url, libraryUuid: uuid)
            .then((_) {
              if (kDebugMode) debugPrint('Backfill: library_uuid persisted');
            })
            .onError((e, _) {
              if (kDebugMode)
                debugPrint('Backfill: failed to persist library_uuid: $e');
            });
      }
      return uuid;
    }
    if (kDebugMode) debugPrint('Backfill: could not resolve library_uuid');
    return null;
  }

  /// Check if offline caching is enabled in settings
  bool get _offlineCachingEnabled {
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      return themeProvider.peerOfflineCachingEnabled;
    } catch (_) {
      return false;
    }
  }

  /// Load books: show cache instantly if available, then refresh in background
  Future<void> _loadCachedBooksFirst() async {
    final api = Provider.of<ApiService>(context, listen: false);
    bool cacheDisplayed = false;

    // 0. Try to resolve a LAN URL from mDNS (relay peers on same WiFi)
    _tryResolveLanUrl();

    try {
      // 1. Try loading from cache FIRST (instant display, no network)
      if (_offlineCachingEnabled) {
        debugPrint('Loading cached books for ${widget.peerUrl}');
        try {
          final cachedRes = await api.getCachedPeerBooks(widget.peerUrl);
          if (mounted) {
            final data = cachedRes.data;
            List<dynamic> booksData = data['books'] ?? [];

            if (booksData.isNotEmpty) {
              setState(() {
                _books = booksData.map((json) => Book.fromJson(json)).toList();
                _filteredBooks =
                    _isSearching && _searchController.text.isNotEmpty
                    ? _books
                          .where(
                            (b) => _matchesSearch(b, _searchController.text),
                          )
                          .toList()
                    : _books;
                _lastSynced = data['last_synced'];
                _isLoading = false;
                _isRefreshing = true;
                _isHubOnly = false;
              });
              cacheDisplayed = true;
            }
          }
        } catch (e) {
          debugPrint('Cache load failed: $e');
        }
      }

      // 2. Hub catalog + connectivity check IN PARALLEL
      //    Hub enriches with new books; connectivity determines if we can go live.
      Future<void>? hubFuture;
      var nodeId = _effectiveNodeId;
      debugPrint('Hub catalog: nodeId=$nodeId, books=${_books.length}');

      // If nodeId is a placeholder (peer_XX), try to backfill from the
      // peer's /api/config (deterministic, no name ambiguity).
      if (nodeId == null || FfiService.isPlaceholderNodeId(nodeId)) {
        final resolved = await _backfillLibraryUuid();
        if (resolved != null) {
          _resolvedNodeId = resolved;
          nodeId = resolved;
          debugPrint('Hub catalog: backfilled nodeId=$nodeId from peer config');
        }
      }

      if (nodeId != null && !FfiService.isPlaceholderNodeId(nodeId)) {
        // Fire-and-forget: hub updates UI via setState when done
        hubFuture = _books.isNotEmpty
            ? _refreshFromHubCatalog()
            : _loadHubCatalog();
      } else {
        debugPrint('Hub catalog: SKIPPED (nodeId=$nodeId)');
      }

      // 3. Check WiFi/LAN connectivity (runs in parallel with hub)
      var url = _effectiveUrl;
      debugPrint('Checking connectivity for $url');
      bool isOnline = false;
      if (url.startsWith('relay://')) {
        isOnline = false;
      } else {
        final connectivity = await Connectivity().checkConnectivity();
        final hasWifi =
            connectivity.contains(ConnectivityResult.wifi) ||
            connectivity.contains(ConnectivityResult.ethernet);
        if (!hasWifi) {
          debugPrint('Not on WiFi/ethernet - skipping LAN connectivity check');
          isOnline = false;
        } else {
          isOnline = await api.checkPeerConnectivity(url, timeoutMs: 2000);
        }
      }

      // Validate name-matched mDNS candidate: fetch /api/config to get UUID
      if (isOnline && _lanUrl != null && !_lanUrlTrusted) {
        final valid = await _validateLanCandidate(api, _lanUrl!);
        if (!valid) {
          // Candidate unreachable or not a BiblioGenius peer — discard
          debugPrint('mDNS: discarding invalid LAN candidate');
          _lanUrl = null;
          _resolvedNodeId = null;
          url = widget.peerUrl;
          isOnline = false;
        } else {
          // Validated — re-trigger hub catalog with the real nodeId
          final validNodeId = _effectiveNodeId;
          if (hubFuture == null &&
              validNodeId != null &&
              !FfiService.isPlaceholderNodeId(validNodeId)) {
            hubFuture = _books.isNotEmpty
                ? _refreshFromHubCatalog()
                : _loadHubCatalog();
          }
        }
      }

      // Persist LAN URL upgrade in background (so future opens are fast)
      if (isOnline && _lanUrl != null && _lanUrlTrusted && widget.peerId > 0) {
        debugPrint('Persisting LAN URL upgrade: ${widget.peerUrl} → $_lanUrl');
        api
            .updatePeerUrl(
              widget.peerId,
              _lanUrl!,
              libraryUuid: _resolvedNodeId,
            )
            .then((_) {
              debugPrint('LAN URL persisted successfully');
            })
            .catchError((e) {
              debugPrint('Failed to persist LAN URL: $e');
            });
      }

      if (!mounted) return;
      setState(() => _isPeerOnline = isOnline);

      // 4. If ONLINE on LAN: fetch live with pagination (full data + covers)
      if (isOnline) {
        debugPrint('Peer online - fetching books live from $url');
        try {
          if (cacheDisplayed || _books.isNotEmpty) {
            // Cache or hub data already shown — quick background check via page 0
            final checkRes = await api.getPeerBooksPage(
              url,
              page: 0,
              limit: _pageSize,
            );
            if (!mounted) return;

            final total = _parsePaginatedTotal(checkRes.data);
            if (total != null && total == _books.length && !cacheDisplayed) {
              // Same count and not a cache-first load — skip.
              // When cache was displayed, always refresh in background to
              // pick up metadata changes (e.g. cover URL transformations).
              debugPrint(
                'Peer library unchanged ($total books), skipping full refresh',
              );
              setState(() => _isRefreshing = false);
            } else {
              // Library changed — full background refresh
              debugPrint(
                'Peer library changed (cached=${_books.length}, remote total=$total), refreshing',
              );
              await _fullBackgroundRefresh(api);
            }
          } else {
            // No cache, no hub data — paginated first page for instant display
            final liveRes = await api.getPeerBooksPage(
              url,
              page: 0,
              limit: _pageSize,
            );
            if (!mounted) return;

            final parsed = _parsePaginatedResponse(liveRes.data);

            setState(() {
              _books = parsed.booksData
                  .map((json) => Book.fromJson(json))
                  .toList();
              _filteredBooks = _books;
              _totalBooks = parsed.total;
              _hasMorePages = parsed.hasMore;
              _currentPage = 0;
              _allBooksLoaded = !parsed.hasMore;
              _isLoading = false;
              _isRefreshing = false;
              _isHubOnly = false;
            });

            debugPrint(
              'Loaded ${_books.length}/${parsed.total} books (page 0, hasMore=${parsed.hasMore})',
            );

            // Cache first page. Only a full snapshot when the whole library
            // fit on this page (no more pages to stream in); otherwise the
            // backend must merge additively so it does not drop the rest.
            if (_offlineCachingEnabled && widget.peerId > 0) {
              api
                  .cachePeerBooks(
                    widget.peerId,
                    _books,
                    isFullSnapshot: _allBooksLoaded,
                  )
                  .catchError((e) {
                    debugPrint('Failed to cache live books: $e');
                  });
            }

            // Load remaining pages in background for complete library
            if (parsed.hasMore) {
              _loadAllRemainingBooks();
            }
          }
          return;
        } catch (e) {
          debugPrint('Live fetch failed: $e');
          // If data was displayed, stop refreshing indicator
          if (_books.isNotEmpty && mounted) {
            setState(() => _isRefreshing = false);
            return;
          }
          // Fall through to relay
        }
      }

      // 5. Offline — wait for hub future before deciding next step
      if (hubFuture != null) {
        await hubFuture;
        if (!mounted) return;
      }
      // Hub may have populated _books — check again
      if (_books.isNotEmpty) {
        if (mounted)
          setState(() {
            _isRefreshing = false;
            _isLoading = false;
          });
        // Peer offline (no LAN) — show cached/hub data immediately, then
        // fire a background delta sync (ADR-029) to catch any
        // `catalog_changed` event that was missed while this screen was
        // not mounted (the broadcast bus drops events with no subscribers,
        // see catalog_events.rs). This is a quiet trigger: no fallback to
        // the legacy manifest flow on failure, so an offline peer does not
        // stall a 90s relay timeout in the background. The appbar refresh
        // button still runs the full ADR-012 flow on demand.
        if (widget.hasRelayCredentials && widget.peerId > 0) {
          unawaited(
            _deltaSyncThenReload(widget.peerId, fallbackOnFailure: false),
          );
        }
        return;
      }

      // 6. No data yet — try relay if available
      if (!widget.hasRelayCredentials) {
        if (mounted)
          setState(() {
            _isLoading = false;
            _isRefreshing = false;
          });
        return;
      }

      setState(() => _isLoading = false);
      _tryRelaySync();
    } catch (e) {
      debugPrint('Error loading books: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  // ── Pagination helpers ──────────────────────────────────────────────

  /// Parse a paginated response: { books, total, has_more } or legacy flat array.
  ({List<dynamic> booksData, int total, bool hasMore}) _parsePaginatedResponse(
    dynamic data,
  ) {
    if (data is Map) {
      final booksData = (data['books'] as List<dynamic>?) ?? [];
      final total = _coerceInt(data['total']) ?? booksData.length;
      final hasMore = (data['has_more'] as bool?) ?? false;
      return (booksData: booksData, total: total, hasMore: hasMore);
    } else if (data is List) {
      // Legacy peer returned flat array (no pagination support)
      return (booksData: data, total: data.length, hasMore: false);
    }
    return (booksData: <dynamic>[], total: 0, hasMore: false);
  }

  /// Extract just the total from a paginated response (for quick cache-vs-live check).
  int? _parsePaginatedTotal(dynamic data) {
    if (data is Map) return _coerceInt(data['total']);
    if (data is List) return data.length;
    return null;
  }

  /// Coerce a paginated envelope count into an int, tolerating numeric strings
  /// (a peer may serialize `total` as "494"). Mirrors [Book] field coercion so a
  /// stray string type never aborts the whole catalogue sync.
  static int? _coerceInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Load the next page of books (infinite scroll).
  Future<void> _loadMoreBooks() async {
    if (_isLoadingMore || !_hasMorePages || !_isPeerOnline) return;

    setState(() => _isLoadingMore = true);
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      final nextPage = _currentPage + 1;
      final res = await api.getPeerBooksPage(
        _effectiveUrl,
        page: nextPage,
        limit: _pageSize,
      );

      if (!mounted) return;

      final parsed = _parsePaginatedResponse(res.data);
      final newBooks = parsed.booksData
          .map((json) => Book.fromJson(json))
          .toList();

      setState(() {
        _books.addAll(newBooks);
        _filteredBooks = _isSearching
            ? _books
                  .where((b) => _matchesSearch(b, _searchController.text))
                  .toList()
            : _books;
        _currentPage = nextPage;
        _hasMorePages = parsed.hasMore;
        _allBooksLoaded = !parsed.hasMore;
        _isLoadingMore = false;
      });

      // Update cache with the growing book list. It is the full catalog only
      // once the last page has been appended (_allBooksLoaded); intermediate
      // pages are additive so the not-yet-loaded tail is preserved.
      if (_offlineCachingEnabled && widget.peerId > 0) {
        api
            .cachePeerBooks(
              widget.peerId,
              _books,
              isFullSnapshot: _allBooksLoaded,
            )
            .catchError((_) {});
      }
    } catch (e) {
      debugPrint('Load more books failed: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// Eagerly load all remaining pages (for search completeness or background refresh).
  Future<void> _loadAllRemainingBooks() async {
    while (_hasMorePages && mounted && _isPeerOnline) {
      await _loadMoreBooks();
    }
  }

  /// Full background refresh: replace current data with a fresh snapshot
  /// of the peer's library.
  ///
  /// Prefers a single delta-aware call when the peer supports it (ADR-028):
  /// one HTTP round trip reconstructs the full catalog and the progress bar
  /// does not restart from zero. Falls back to the paginated proxy loop on
  /// any failure (peer unreachable direct, legacy peer without delta, etc.),
  /// which transparently handles E2EE / relay.
  Future<void> _fullBackgroundRefresh(ApiService api) async {
    // Attempt delta refresh first.
    try {
      final res = await api.getPeerBooksDelta(_effectiveUrl);
      if (!mounted) return;

      final parsed = _parsePaginatedResponse(res.data);
      // Shape must look like a full catalog. A raw list or a map with `books`
      // both work via _parsePaginatedResponse. Defend against a totally
      // empty / malformed body by not trusting a zero-total silently.
      if (parsed.booksData.isNotEmpty || parsed.total == 0) {
        final freshBooks = parsed.booksData
            .map((json) => Book.fromJson(json as Map<String, dynamic>))
            .toList();
        setState(() {
          _books = freshBooks;
          _filteredBooks = _books;
          _totalBooks = freshBooks.length;
          _hasMorePages = false;
          _allBooksLoaded = true;
          _isRefreshing = false;
          _isHubOnly = false;
          // A successful direct fetch proves the peer is reachable, even if
          // an earlier probe marked it offline. Keep the label in sync so
          // the UI does not contradict the data freshly rendered below it.
          _isPeerOnline = true;
        });
        if (_offlineCachingEnabled && widget.peerId > 0) {
          // Full background refresh loaded the entire catalog → snapshot.
          api
              .cachePeerBooks(widget.peerId, _books, isFullSnapshot: true)
              .catchError((_) {});
        }
        debugPrint(
          'Delta refresh OK: ${freshBooks.length} books in one round trip',
        );
        return;
      }
      debugPrint(
        'Delta refresh returned empty body; falling back to paginated',
      );
    } catch (e) {
      debugPrint('Delta refresh failed ($e); falling back to paginated');
    }

    // Fallback: original paginated loop (supports E2EE / relay via proxy).
    try {
      final allBooks = <Book>[];
      int page = 0;
      bool hasMore = true;

      while (hasMore && mounted) {
        final res = await api.getPeerBooksPage(
          _effectiveUrl,
          page: page,
          limit: _pageSize,
        );
        if (!mounted) return;

        final parsed = _parsePaginatedResponse(res.data);
        allBooks.addAll(
          parsed.booksData.map((json) => Book.fromJson(json)).toList(),
        );
        hasMore = parsed.hasMore;
        page++;
      }

      if (mounted) {
        setState(() {
          _books = allBooks;
          _filteredBooks = _books;
          _totalBooks = allBooks.length;
          _hasMorePages = false;
          _allBooksLoaded = true;
          _currentPage = page - 1;
          _isRefreshing = false;
          _isHubOnly = false;
        });

        if (_offlineCachingEnabled && widget.peerId > 0) {
          // Full background refresh loaded the entire catalog → snapshot.
          api
              .cachePeerBooks(widget.peerId, _books, isFullSnapshot: true)
              .catchError((_) {});
        }
      }
    } catch (e) {
      debugPrint('Full background refresh failed: $e');
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  bool _matchesSearch(Book book, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return book.title.toLowerCase().contains(q) ||
        (book.author?.toLowerCase().contains(q) ?? false);
  }

  /// Refresh from hub catalog: if the peer pushed updates to the hub while
  /// offline, detect new books and merge them into the displayed list.
  /// Unlike _loadHubCatalog (full fallback), this enriches the existing
  /// cache/list with any books present in the hub but missing locally.
  Future<void> _refreshFromHubCatalog() async {
    final nodeId = _effectiveNodeId;
    if (nodeId == null || FfiService.isPlaceholderNodeId(nodeId)) return;
    try {
      final ffi = FfiService();
      final entries = await ffi.hubDirectoryGetCatalog(nodeId);
      debugPrint(
        '[DEBUG-CATALOG] hub catalog fetched: ${entries.length} entries '
        '(local _books=${_books.length})',
      );
      if (!mounted || entries.isEmpty) return;

      // Hub catalog is an enrichment layer — it may lag behind the cache
      // (peer added books but hasn't pushed to hub yet).  So we only ADD
      // new books and UPDATE metadata for known books.  We never REMOVE
      // books based on hub — only live P2P or relay sync are authoritative
      // for deletions.

      final knownIsbns = <String, Book>{};
      final knownTitles = <String, Book>{};
      for (final b in _books) {
        if (b.isbn != null && b.isbn!.isNotEmpty) knownIsbns[b.isbn!] = b;
        if (b.title.isNotEmpty) knownTitles[b.title.toLowerCase()] = b;
      }

      bool changed = false;
      final updatedBooks = List<Book>.from(_books);

      for (final e in entries) {
        if (e.isbn.isEmpty && e.title.isEmpty) continue;
        // Match by ISBN first, then by title for no-ISBN books
        final existing = e.isbn.isNotEmpty
            ? knownIsbns[e.isbn]
            : knownTitles[e.title.toLowerCase()];
        if (existing != null) {
          // Update title/author if hub has newer metadata
          final newTitle = e.title.isNotEmpty ? e.title : existing.title;
          final newAuthor = (e.author?.isNotEmpty == true)
              ? e.author
              : existing.author;
          if (newTitle != existing.title || newAuthor != existing.author) {
            final idx = updatedBooks.indexOf(existing);
            if (idx >= 0) {
              updatedBooks[idx] = Book(
                id: existing.id,
                title: newTitle,
                author: newAuthor,
                isbn: existing.isbn,
                coverUrl: e.coverUrl ?? existing.coverUrl,
                summary: existing.summary,
              );
              changed = true;
            }
          }
        } else {
          // New book from hub — not in our current list
          updatedBooks.add(
            Book(
              title: e.title,
              author: e.author,
              isbn: e.isbn.isNotEmpty ? e.isbn : null,
              coverUrl: e.coverUrl,
            ),
          );
          changed = true;
        }
      }

      if (!changed) {
        debugPrint(
          'Hub catalog: no changes (${entries.length} entries, ${_books.length} books)',
        );
        return;
      }

      debugPrint(
        'Hub catalog: enriched to ${updatedBooks.length} books (was ${_books.length})',
      );

      setState(() {
        _books = updatedBooks;
        _filteredBooks = _isSearching && _searchController.text.isNotEmpty
            ? _books
                  .where((b) => _matchesSearch(b, _searchController.text))
                  .toList()
            : _books;
        _lastSynced = DateTime.now().toIso8601String();
        _isRefreshing = false;
      });
    } catch (e) {
      debugPrint('Hub catalog refresh failed: $e');
    }
  }

  /// Load hub catalog and convert entries to Book objects for unified rendering.
  /// Books get covers via explicit cover_url or OpenLibrary ISBN fallback.
  Future<void> _loadHubCatalog() async {
    final nodeId = _effectiveNodeId;
    if (nodeId == null || FfiService.isPlaceholderNodeId(nodeId)) return;
    try {
      final ffi = FfiService();
      debugPrint('Hub catalog: fetching for $nodeId');
      final entries = await ffi.hubDirectoryGetCatalog(nodeId);
      debugPrint('Hub catalog: got ${entries.length} entries');
      if (!mounted || entries.isEmpty) return;
      // Don't override if live/cached data arrived while we were fetching
      if (_books.isNotEmpty) {
        debugPrint(
          'Hub catalog: skipped (live data already loaded: ${_books.length} books)',
        );
        return;
      }

      final books = entries
          .map(
            (e) => Book(
              title: e.title,
              author: e.author,
              isbn: e.isbn.isNotEmpty ? e.isbn : null,
              coverUrl: e.coverUrl,
            ),
          )
          .toList();

      setState(() {
        _books = books;
        _filteredBooks = _books;
        _isHubOnly = true;
        _lastSynced = DateTime.now().toIso8601String();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Hub catalog fallback failed: $e');
    }
  }

  /// Try to sync peer's library via relay (ADR-012).
  /// Uses paginated requests with adaptive polling.
  /// [isManualSync] — true when triggered by the user (sync button),
  /// false when triggered automatically on initial load. Affects the
  /// polling patience: manual gets 3 min, auto gets 60 s.
  Future<void> _tryRelaySync({bool isManualSync = false}) async {
    if (_isRelayLoading) return;
    final api = Provider.of<ApiService>(context, listen: false);

    setState(() => _isRelayLoading = true);

    try {
      // Diagnostic: check local relay status before requesting
      await api.logRelayStatus();

      // 1. Request manifest to get total book count + catalog hash
      final manifest = await api.requestPeerManifest(widget.peerId);

      if (manifest != null && mounted) {
        // Check for peer_unreachable (502) returned as error in manifest
        if (manifest['error'] == 'peer_unreachable') {
          debugPrint(
            'Relay: peer ${widget.peerId} unreachable (mailbox expired), '
            'stopping relay sync',
          );
          if (mounted) setState(() => _isRelayLoading = false);
          return;
        }

        // Update nodeId from manifest if the peer sent their library_uuid.
        // This fixes stale nodeId when the peer was reset/reinstalled.
        //
        // ADR-030: the manifest travels in an E2EE envelope signed by the
        // peer's stable ed25519 key, so `manifest['library_uuid']` is
        // cryptographically bound to the peer identity and safe to adopt.
        // We persist the fresh value to `peers.library_uuid` so later
        // mounts — and the hub-catalog fallback when the peer is offline —
        // see the current identity without waiting for another re-pair.
        final remoteUuid = manifest['library_uuid'] as String?;
        if (remoteUuid != null &&
            remoteUuid.isNotEmpty &&
            remoteUuid != _effectiveNodeId) {
          debugPrint(
            'Relay: peer library_uuid updated: '
            '$_effectiveNodeId -> $remoteUuid',
          );
          _resolvedNodeId = remoteUuid;
          if (widget.peerId > 0) {
            try {
              final changed = await updatePeerLibraryUuid(
                peerId: widget.peerId,
                newUuid: remoteUuid,
              );
              debugPrint(
                '[ADR-030] peer=${widget.peerId} library_uuid persisted '
                '(changed=$changed)',
              );
            } catch (e) {
              // Non-fatal: in-memory _resolvedNodeId still works for this
              // session, we just lose the self-heal across mounts.
              debugPrint(
                '[ADR-030] peer=${widget.peerId} failed to persist '
                'library_uuid: $e',
              );
            }
          }
          // Trigger hub catalog refresh with corrected nodeId
          _refreshFromHubCatalog();
        }

        // Skip re-fetch if catalog is unchanged (hash match)
        final newHash = manifest['catalog_hash'] as String?;
        if (newHash != null && _books.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final cachedHash = prefs.getString(
            'peer_catalog_hash_${widget.peerId}',
          );
          if (newHash == cachedHash) {
            debugPrint(
              'Relay: catalog unchanged (hash match), skipping re-fetch',
            );
            if (mounted) {
              setState(() {
                _isRelayLoading = false;
                _relaySyncDone = true;
              });
            }
            return;
          }
        }
        await _fetchRelayPages(api, manifest);
      } else if (mounted) {
        // manifest returned null (202 relay_pending) - start polling
        debugPrint('Relay: manifest pending, starting adaptive polling');
        _startAdaptivePolling(isManualSync: isManualSync);
      }
    } catch (e) {
      debugPrint('Relay sync failed: $e');
      if (mounted) {
        setState(() => _isRelayLoading = false);
      }
    }
  }

  /// Fetch paginated books from relay once the manifest is available.
  Future<void> _fetchRelayPages(
    ApiService api,
    Map<String, dynamic> manifest,
  ) async {
    final totalBooks = _coerceInt(manifest['total_books']) ?? 0;
    if (mounted) setState(() => _relayBooksTotal = totalBooks);

    if (totalBooks == 0) {
      if (mounted) setState(() => _isRelayLoading = false);
      return;
    }

    // Show preview books from manifest instantly (before pages arrive)
    final previewList = manifest['preview_books'] as List?;
    if (previewList != null && previewList.isNotEmpty && _books.isEmpty) {
      final previewBooks = previewList
          .map(
            (json) => Book.fromJson(json is Map<String, dynamic> ? json : {}),
          )
          .toList();
      if (mounted) {
        setState(() {
          _books = previewBooks;
          _filteredBooks = _books;
          _isLoading = false;
          _isHubOnly = false;
        });
        debugPrint(
          'Relay: showing ${previewBooks.length} preview books from manifest',
        );
      }
    }

    int? cursor;
    List<Book> allBooks = [];
    const maxRetriesPerPage = 2;

    while (mounted) {
      Map<String, dynamic>? page;

      // Try the page request, with retries if relay times out
      for (int attempt = 0; attempt <= maxRetriesPerPage; attempt++) {
        page = await api.requestPeerPage(widget.peerId, cursor: cursor);
        if (page != null) break;

        // Timed out - poll and retry (don't restart from scratch)
        if (attempt < maxRetriesPerPage && mounted) {
          debugPrint(
            'Relay: page cursor=$cursor timed out, retrying '
            '(${attempt + 1}/$maxRetriesPerPage)',
          );
          await api.pollRelayNow();
        }
      }

      if (page == null) {
        // All retries exhausted for this page - stop gracefully
        debugPrint('Relay: page cursor=$cursor failed after retries, stopping');
        break;
      }

      final books =
          (page['books'] as List?)
              ?.map(
                (json) =>
                    Book.fromJson(json is Map<String, dynamic> ? json : {}),
              )
              .toList() ??
          [];

      allBooks.addAll(books);

      final allDone = totalBooks > 0 && allBooks.length >= totalBooks;
      if (mounted) {
        setState(() {
          _books = List.from(allBooks);
          _filteredBooks = _books;
          _relayBooksLoaded = allBooks.length;
          _isLoading = false;
          _isHubOnly = false;
          // Dismiss spinner immediately once all expected books are displayed.
          if (allDone) {
            _isRelayLoading = false;
            _relaySyncDone = true;
          }
        });
      }

      if (allDone) break;

      // Check if there are more pages
      final nextCursor = page['next_cursor'];
      if (nextCursor == null || books.isEmpty) break;
      cursor = nextCursor is int ? nextCursor : null;
      if (cursor == null) break;
    }

    // Save relay-fetched books to local cache for instant display next visit.
    // We `await` the cache write so the ADR-029 reset-recovery save-cursor
    // step below runs ONLY when the cache is actually persisted — persisting
    // the delta cursor on top of an empty/failed cache would leave a
    // permanent data gap (next sync = delta from N returns ~nothing).
    // Only authoritative when we actually received the whole catalog. If a
    // page timed out and the loop broke early, allBooks holds a subset — cache
    // it additively so the missing tail is not pruned from a previous sync.
    final relayFetchComplete = allBooks.length >= totalBooks;
    bool cacheWriteSucceeded = false;
    if (_offlineCachingEnabled && allBooks.isNotEmpty) {
      try {
        await api.cachePeerBooks(
          widget.peerId,
          allBooks,
          isFullSnapshot: relayFetchComplete,
        );
        cacheWriteSucceeded = true;
        if (kDebugMode) debugPrint('Cached ${allBooks.length} books for peer');
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to cache books: $e');
      }
    }

    // Save catalog hash for diff check on next visit
    final catalogHash = manifest['catalog_hash'] as String?;
    if (catalogHash != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('peer_catalog_hash_${widget.peerId}', catalogHash);
    }

    // ADR-029 reset-recovery: if this legacy sync was triggered by a
    // `reset_required:<N>` outcome, advance `peers.last_delta_cursor` to
    // `N` now that the local cache is fully rebuilt. This is the single
    // write point for the pending cursor — doing it before the cache
    // persists would risk a data gap if the cache write failed.
    final pendingCursor = _pendingDeltaCursor;
    if (pendingCursor != null && cacheWriteSucceeded && widget.peerId > 0) {
      try {
        await setPeerDeltaCursor(peerId: widget.peerId, cursor: pendingCursor);
        debugPrint(
          '[DELTA-RESET] peer=${widget.peerId} cursor persisted=$pendingCursor '
          '(reset loop broken, next sync will be a delta)',
        );
      } catch (e) {
        debugPrint(
          '[DELTA-RESET] peer=${widget.peerId} failed to persist cursor '
          '$pendingCursor: $e (next visit will retry the reset cycle)',
        );
      } finally {
        _pendingDeltaCursor = null;
      }
    }

    if (mounted) {
      setState(() {
        _isRelayLoading = false;
        if (allBooks.isNotEmpty) _relaySyncDone = true;
      });
      if (allBooks.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'library_synced'),
            ),
          ),
        );
      }
    }
  }

  /// Adaptive polling: poll relay every 5s, retry manifest after each poll.
  /// When the relay response arrives, continues with page fetching.
  /// Gives up after a wall-clock deadline:
  ///   - manual sync (isManualSync=true):  3 minutes
  ///   - auto on initial load:             1 minute
  /// The shorter auto timeout avoids stalling the UI when the peer app
  /// is simply closed and will never respond via the relay.
  /// Uses _pollRequestInFlight guard to prevent concurrent requests that
  /// would flood the relay with different correlation IDs.
  /// Circuit breaker: stops immediately on 502 (peer unreachable).
  void _startAdaptivePolling({bool isManualSync = false}) {
    if (!mounted) return;
    _pollTimer?.cancel();
    _pollRequestInFlight = false;
    final api = Provider.of<ApiService>(context, listen: false);
    int pollCount = 0;
    // Wall-clock deadline: each requestPeerManifest blocks ~90s on the Rust
    // side, so a tick-count timeout (36 × 5s = "3 min") actually takes ~60 min.
    // Use a real deadline instead.
    final deadline = DateTime.now().add(
      Duration(minutes: isManualSync ? 3 : 1),
    );

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // Check wall-clock deadline on EVERY tick, including skipped ones.
      if (DateTime.now().isAfter(deadline) || !mounted) {
        timer.cancel();
        if (mounted) {
          final elapsed = isManualSync ? 3 : 1;
          debugPrint(
            'Relay: polling timed out after ~${elapsed}min (wall-clock)',
          );
          setState(() => _isRelayLoading = false);
        }
        return;
      }

      if (_pollRequestInFlight) {
        debugPrint(
          'Relay: skipping poll tick (previous request still in flight)',
        );
        return;
      }

      pollCount++;

      _pollRequestInFlight = true;
      try {
        // 1. Tell the backend to check relay inbox
        await api.pollRelayNow();

        // 2. Retry manifest - if the relay response arrived, we get data
        final manifest = await api.requestPeerManifest(widget.peerId);
        if (manifest != null && mounted) {
          // Circuit breaker: peer_unreachable means mailbox expired and
          // credential refresh failed. Stop polling immediately.
          if (manifest['error'] == 'peer_unreachable') {
            debugPrint(
              'Relay: peer ${widget.peerId} unreachable, '
              'stopping adaptive polling at tick $pollCount',
            );
            timer.cancel();
            if (mounted) setState(() => _isRelayLoading = false);
            return;
          }

          debugPrint('Relay: manifest received at poll tick $pollCount');
          timer.cancel();
          // Update stale nodeId if the peer sent their library_uuid
          final remoteUuid = manifest['library_uuid'] as String?;
          if (remoteUuid != null && remoteUuid != _effectiveNodeId) {
            debugPrint(
              'Relay poll: peer library_uuid updated: '
              '$_effectiveNodeId -> $remoteUuid',
            );
            _resolvedNodeId = remoteUuid;
            _refreshFromHubCatalog();
          }
          await _fetchRelayPages(api, manifest);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Adaptive poll error: tick=$pollCount $e');
      } finally {
        _pollRequestInFlight = false;
      }
    });
  }

  /// Format staleness for display
  String _formatStaleness() {
    if (_lastSynced == null) {
      return TranslationService.translate(context, 'never_synced');
    }

    try {
      final syncTime = DateTime.parse(_lastSynced!);
      final age = DateTime.now().difference(syncTime);

      if (age.inMinutes < 1) {
        return TranslationService.translate(context, 'synced_just_now');
      } else if (age.inMinutes < 60) {
        final label = TranslationService.translate(
          context,
          'synced_minutes_ago',
        );
        final v = age.inMinutes.toString();
        return label.replaceAll('%d', v).replaceAll('{count}', v);
      } else if (age.inHours < 24) {
        final label = TranslationService.translate(context, 'synced_hours_ago');
        final v = age.inHours.toString();
        return label.replaceAll('%d', v).replaceAll('{count}', v);
      } else {
        final label = TranslationService.translate(context, 'synced_days_ago');
        final v = age.inDays.toString();
        return label.replaceAll('%d', v).replaceAll('{count}', v);
      }
    } catch (_) {
      return _lastSynced ?? '';
    }
  }

  void _filterBooks(String query) {
    List<Book> result;
    if (query.isEmpty) {
      result = List.of(_books);
    } else {
      final q = query.toLowerCase();
      result = _books.where((book) {
        final title = book.title.toLowerCase();
        final author = book.author?.toLowerCase() ?? '';
        final isbn = book.isbn?.toLowerCase() ?? '';
        return title.contains(q) || author.contains(q) || isbn.contains(q);
      }).toList();
    }
    // Sort aligned with own library: author surname, then full author, then title.
    String getSurname(String? author) {
      if (author == null || author.isEmpty) return '';
      final parts = author.trim().split(RegExp(r'\s+'));
      return parts.last.toLowerCase();
    }

    result.sort((a, b) {
      final surnameCompare = getSurname(
        a.author,
      ).compareTo(getSurname(b.author));
      if (surnameCompare != 0) return surnameCompare;
      final authorCompare = (a.author ?? '').toLowerCase().compareTo(
        (b.author ?? '').toLowerCase(),
      );
      if (authorCompare != 0) return authorCompare;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    setState(() => _filteredBooks = result);
  }

  Future<void> _syncBooks({bool showFeedback = true}) async {
    if (_isSyncing) return;

    // Re-resolve mDNS in case WiFi state changed since init
    _tryResolveLanUrl();

    // Re-check connectivity — _isPeerOnline may be stale (set once at init).
    // A short probe (2s) lets us take the live WiFi path when the peer is now
    // reachable, instead of falling back to the hub-only path and missing
    // books that were added after the last catalog-change notification.
    if (!_isPeerOnline) {
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        final nowOnline = await api.checkPeerConnectivity(
          _effectiveUrl,
          timeoutMs: 2000,
        );
        if (nowOnline && mounted) {
          setState(() => _isPeerOnline = true);
        }
      } catch (_) {
        // Probe failed — peer is still offline, continue with offline path.
      }
    }

    // Check if peer is online before attempting sync
    if (!_isPeerOnline) {
      setState(() => _isSyncing = true);

      // Reload from backend cache first (may have been updated by background sync)
      if (_offlineCachingEnabled) {
        try {
          final api = Provider.of<ApiService>(context, listen: false);
          final cachedRes = await api.getCachedPeerBooks(widget.peerUrl);
          if (mounted) {
            final data = cachedRes.data;
            final booksData = (data['books'] as List<dynamic>?) ?? [];
            if (booksData.isNotEmpty) {
              setState(() {
                _books = booksData.map((json) => Book.fromJson(json)).toList();
                _filteredBooks =
                    _isSearching && _searchController.text.isNotEmpty
                    ? _books
                          .where(
                            (b) => _matchesSearch(b, _searchController.text),
                          )
                          .toList()
                    : _books;
                _lastSynced = data['last_synced'] as String?;
              });
            }
          }
        } catch (e) {
          debugPrint('Cache reload on refresh failed: $e');
        }
      }

      // Then enrich with hub catalog (fast, <1s)
      final nodeId = _effectiveNodeId;
      if (nodeId != null && !FfiService.isPlaceholderNodeId(nodeId)) {
        await _refreshFromHubCatalog();
        if (mounted) {
          setState(() => _isSyncing = false);
          if (showFeedback) {
            // Be honest: the peer is offline, so this only succeeded if the
            // cache + hub enrichment actually produced books. Claiming
            // "synced" on an empty result contradicts the "no books" state
            // the user is looking at.
            final gotBooks = _books.isNotEmpty;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  TranslationService.translate(
                    context,
                    gotBooks ? 'library_synced' : 'peer_offline_cannot_sync',
                  ),
                ),
                backgroundColor: gotBooks
                    ? null
                    : Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
        // For relay-only peers the hub catalog may lag behind real-time changes
        // (the peer notifies us before their hub push completes). Trigger a relay
        // sync so we get the authoritative live list directly from the peer.
        if (widget.peerUrl.startsWith('relay://') &&
            widget.hasRelayCredentials) {
          _tryRelaySync(isManualSync: showFeedback);
        }
        return;
      }
      // No hub — fall back to relay sync (ADR-012)
      if (mounted) setState(() => _isSyncing = false);
      _tryRelaySync(isManualSync: true);
      return;
    }

    setState(() => _isSyncing = true);
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      // Fetch first page quickly, then load remaining in background
      final liveRes = await api.getPeerBooksPage(
        _effectiveUrl,
        page: 0,
        limit: _pageSize,
      );

      if (!mounted) return;

      final parsed = _parsePaginatedResponse(liveRes.data);

      setState(() {
        _books = parsed.booksData.map((json) => Book.fromJson(json)).toList();
        _filteredBooks = _books;
        _totalBooks = parsed.total;
        _hasMorePages = parsed.hasMore;
        _currentPage = 0;
        _allBooksLoaded = !parsed.hasMore;
        _isSyncing = false;
        _isHubOnly = false;
        _lastSynced = DateTime.now().toIso8601String();
      });

      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'library_synced'),
            ),
          ),
        );
      }

      // Load remaining pages in background
      if (parsed.hasMore) {
        _loadAllRemainingBooks();
      }

      // Background sync to update cache (if peer allows caching)
      if (_offlineCachingEnabled) {
        api
            .syncPeer(_effectiveUrl)
            .then((_) {
              debugPrint('Background cache sync completed');
            })
            .catchError((e) {
              debugPrint(
                'Background cache sync failed (peer may not allow caching): $e',
              );
            });
      }
    } catch (e) {
      debugPrint('Sync failed: $e');
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _isPeerOnline = false; // Mark as offline on sync failure
        });
        if (showFeedback) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'sync_failed')}: $e',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _loadPendingBorrowRequests() async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      // Outgoing requests: pending = button shows "Requested", accepted = "Borrowed"
      final outgoing = await api.getOutgoingRequests();
      final outgoingList = outgoing.data as List<dynamic>? ?? [];
      final forThisPeer = outgoingList.where(
        (r) => r['peer_url']?.toString() == widget.peerUrl,
      );

      final pending = forThisPeer
          .where((r) => r['status'] == 'pending')
          .map((r) => r['book_isbn']?.toString() ?? '')
          .where((isbn) => isbn.isNotEmpty)
          .toSet();
      final active = forThisPeer
          .where((r) => r['status'] == 'accepted')
          .map((r) => r['book_isbn']?.toString() ?? '')
          .where((isbn) => isbn.isNotEmpty)
          .toSet();

      // Incoming requests: accepted from this peer = user is lending it to them
      final incoming = await api.getIncomingRequests();
      final incomingList = incoming.data as List<dynamic>? ?? [];
      final lending = incomingList
          .where(
            (r) =>
                r['peer_url']?.toString() == widget.peerUrl &&
                r['status'] == 'accepted',
          )
          .map((r) => r['book_isbn']?.toString() ?? '')
          .where((isbn) => isbn.isNotEmpty)
          .toSet();

      if (mounted) {
        setState(() {
          _pendingBorrowIsbns = pending;
          _activeBorrowIsbns = active;
          _lendingIsbns = lending;
        });
      }
    } catch (_) {
      // Non-blocking: if we can't load, just don't disable any button
    }
  }

  bool _hasPendingRequest(Book book) {
    final isbn = book.isbn;
    return isbn != null &&
        isbn.isNotEmpty &&
        _pendingBorrowIsbns.contains(isbn);
  }

  bool _isActiveBorrow(Book book) {
    final isbn = book.isbn;
    return isbn != null && isbn.isNotEmpty && _activeBorrowIsbns.contains(isbn);
  }

  bool _isLending(Book book) {
    final isbn = book.isbn;
    return isbn != null && isbn.isNotEmpty && _lendingIsbns.contains(isbn);
  }

  bool _hasNoCopiesAvailable(Book book) {
    return book.availableCopies != null && book.availableCopies == 0;
  }

  bool _canBorrow(Book book) {
    // Can't borrow a book the peer doesn't own (e.g. they borrowed it themselves)
    // For hub catalog books, owned defaults to true (unknown = allow request,
    // server auto-rejects if no available copy).
    if (!book.owned) return false;
    return !_hasPendingRequest(book) &&
        !_isActiveBorrow(book) &&
        !_isLending(book) &&
        !_hasNoCopiesAvailable(book);
  }

  Future<void> _requestBorrow(Book book) async {
    // Immediately disable the button to prevent double-tap
    final isbn = book.isbn;
    if (isbn != null && isbn.isNotEmpty) {
      setState(() => _pendingBorrowIsbns.add(isbn));
    }

    final api = Provider.of<ApiService>(context, listen: false);
    try {
      // Use the DB peer URL (not _effectiveUrl which may be a stale mDNS LAN IP).
      // The Rust backend resolves relay:// URLs via E2EE transport.
      final response = await api.requestBookByUrl(
        widget.peerUrl,
        isbn ?? "",
        book.title,
      );
      if (!mounted) return;
      final data = response.data;

      // 409: already borrowing or currently lending this book to the peer.
      if (response.statusCode == 409) {
        final error = data is Map ? data['error']?.toString() : null;
        if (isbn != null && isbn.isNotEmpty) {
          setState(() {
            _pendingBorrowIsbns.remove(isbn);
            // Mark as "on loan" so button stays disabled with the right label
            _lendingIsbns.add(isbn);
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error == 'already_requested'
                  ? TranslationService.translate(context, 'borrow_on_loan')
                  : TranslationService.translate(
                      context,
                      'borrow_request_rejected_no_copy',
                    ),
            ),
          ),
        );
        return;
      }

      // Check lender's response status
      if (data is Map && data['status'] == 'rejected') {
        // Remove from pending since the request was rejected
        if (isbn != null && isbn.isNotEmpty) {
          setState(() => _pendingBorrowIsbns.remove(isbn));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                context,
                'borrow_request_rejected_no_copy',
              ),
            ),
          ),
        );
      } else if (data is Map && data['status'] == 'accepted') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'borrow_request_accepted'),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'borrow_request_sent'),
            ),
          ),
        );
      }
    } catch (e) {
      // Re-enable button on error so user can retry
      if (isbn != null && isbn.isNotEmpty && mounted) {
        setState(() => _pendingBorrowIsbns.remove(isbn));
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'error_sending_request'),
            ),
          ),
        );
      }
    }
  }

  Widget _buildOfflineNotAvailableView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 80, color: Colors.orange[300]),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'peer_offline'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.orange[700],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(
                context,
                'peer_offline_library_unavailable',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            if (!_isRelayLoading)
              OutlinedButton.icon(
                onPressed: () => _loadCachedBooksFirst(),
                icon: const Icon(Icons.refresh),
                label: Text(TranslationService.translate(context, 'retry')),
              ),
          ],
        ),
      ),
    );
  }

  /// Auto-collapse the recently-added carousel when the peer's book list is
  /// scrolled, expand again when scrolled back to the top. Hysteresis
  /// thresholds avoid flicker at the transition.
  bool _handleBodyScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final provider = context.read<ThemeProvider>();
    if (provider.carouselHiddenPeerLib) return false;
    final pixels = notification.metrics.pixels;
    if (pixels > 60) {
      provider.setCarouselCollapsedPeerLib(true);
    } else if (pixels <= 12) {
      provider.setCarouselCollapsedPeerLib(false);
    }
    return false;
  }

  /// Full profile banner: identity row (avatar + name + country + book count)
  /// with optional contact section below a divider.
  /// Only rendered when a hub profile is available for this peer.
  Widget _buildHubProfileBanner() {
    if (_hubProfile == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final onContainer = cs.onPrimaryContainer;
    final onContainerMuted = onContainer.withValues(alpha: 0.7);

    final hasWebsite =
        _hubProfile!.website != null && _hubProfile!.website!.isNotEmpty;
    final hasContact =
        _decryptedContact != null && _decryptedContact!.isNotEmpty;
    final hasContactSection = hasWebsite || hasContact;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity row
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary,
                child: Text(
                  _hubProfile!.displayName.isNotEmpty
                      ? _hubProfile!.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hubProfile!.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onContainer,
                      ),
                    ),
                    if (_hubProfile!.locationCountry != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: HubLocationLabel(
                          country: _hubProfile!.locationCountry,
                          cityId: _hubProfile!.locationCityId,
                          style: TextStyle(
                            fontSize: 12,
                            color: onContainerMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${_totalBooks > 0 ? _totalBooks : _hubProfile!.bookCount}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: onContainer,
                      ),
                    ),
                    Text(
                      TranslationService.translate(context, 'directory_books'),
                      style: TextStyle(fontSize: 11, color: onContainerMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Contact section (website + encrypted contact)
          if (hasContactSection) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Divider(
                height: 1,
                color: onContainer.withValues(alpha: 0.15),
              ),
            ),
            if (hasWebsite)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _buildWebsiteRow(_hubProfile!.website!, cs),
              ),
            if (hasContact)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.lock_outlined,
                      size: 14,
                      color: onContainerMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _decryptedContact!,
                      style: TextStyle(fontSize: 13, color: onContainer),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildWebsiteRow(String url, ColorScheme cs) {
    var s = url.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !uri.host.contains('.')) return const SizedBox.shrink();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => launchUrl(uri, mode: LaunchMode.externalApplication),
        child: Row(
          children: [
            Icon(
              Icons.language,
              size: 15,
              color: cs.onPrimaryContainer.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                uri.toString(),
                style: TextStyle(fontSize: 13, color: cs.primary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStalenessBar() {
    // Hub-only: data from hub directory, not a direct peer connection
    final channelIcon = _isPeerOnline
        ? Icons.wifi
        : _isRelayLoading || _isHubOnly || _relaySyncDone
        ? Icons.cloud_queue
        : Icons.cloud_off;
    final channelLabel = _isPeerOnline
        ? 'Wi-Fi'
        : _isRelayLoading || _relaySyncDone
        ? 'Internet'
        : _isHubOnly
        ? 'Annuaire'
        : 'Offline';
    final subtleColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(channelIcon, size: 14, color: subtleColor),
          const SizedBox(width: 6),
          Text(
            channelLabel,
            style: TextStyle(fontSize: 11, color: subtleColor),
          ),
          const SizedBox(width: 8),
          Text('\u00b7', style: TextStyle(fontSize: 11, color: subtleColor)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _formatStaleness(),
              style: TextStyle(fontSize: 11, color: subtleColor),
            ),
          ),
          if (_isRefreshing)
            Text(
              TranslationService.translate(context, 'refreshing_library'),
              style: TextStyle(fontSize: 11, color: Colors.blue[600]),
            )
          else if (_isRelayLoading && _relayBooksTotal > 0)
            Text(
              '$_relayBooksLoaded/$_relayBooksTotal',
              style: TextStyle(fontSize: 11, color: Colors.blue[600]),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When peer covers are disabled in Settings, force the colored-spine
    // shelf view and hide the view switcher. This is the "data-saver"
    // mode: no cover URL is ever passed to CachedNetworkImage, so no
    // network fetch and no disk write happen. The user's last explicit
    // choice of _viewMode is preserved in State so re-enabling the toggle
    // restores their previous view without resetting anything.
    final peerCoversEnabled = context
        .watch<ThemeProvider>()
        .peerCoverDisplayEnabled;
    final effectiveViewMode = peerCoversEnabled
        ? _viewMode
        : _PeerViewMode.shelf;
    // When the loans module is disabled, hide the borrow CTA in peer libraries:
    // we cannot borrow from them (peers can still borrow from us via their app).
    final canBorrowModule = context.watch<ThemeProvider>().canBorrowBooks;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: TranslationService.translate(
                    context,
                    'peer_library_search_hint',
                  ),
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onChanged: _filterBooks,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(widget.peerName),
                  ),
                  if (widget.caption != null && widget.caption!.isNotEmpty)
                    Text(
                      widget.caption!,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: TranslationService.translate(context, 'search'),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _filterBooks('');
                } else {
                  _isSearching = true;
                  // Eagerly load all remaining books for search completeness
                  if (!_allBooksLoaded && _isPeerOnline) {
                    _loadAllRemainingBooks();
                  }
                }
              });
            },
          ),
          if (!_isSearching)
            Builder(
              builder: (context) => IconButton(
                icon: (_isSyncing || _isRefreshing)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync),
                tooltip: TranslationService.translate(context, 'sync_library'),
                onPressed: (_isSyncing || _isRefreshing)
                    ? null
                    : () => _syncBooks(),
              ),
            ),
          if (!_isSearching && peerCoversEnabled)
            IconButton(
              icon: Icon(switch (_viewMode) {
                _PeerViewMode.coverGrid => Icons.view_module,
                _PeerViewMode.shelf => Icons.view_day,
                _PeerViewMode.list => Icons.view_list,
              }),
              tooltip: TranslationService.translate(context, 'toggle_view'),
              onPressed: () {
                setState(() {
                  _viewMode = switch (_viewMode) {
                    _PeerViewMode.coverGrid => _PeerViewMode.shelf,
                    _PeerViewMode.shelf => _PeerViewMode.list,
                    _PeerViewMode.list => _PeerViewMode.coverGrid,
                  };
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (!_isPeerOnline &&
                !_offlineCachingEnabled &&
                _books.isEmpty &&
                !_isRelayLoading)
          ? _buildOfflineNotAvailableView()
          : Column(
              children: [
                // Hub profile banner (avatar + name + country + book count + contact)
                _buildHubProfileBanner(),
                // Staleness indicator bar
                _buildStalenessBar(),
                // Relay loading progress bar
                if (_isRelayLoading && _relayBooksTotal > 0)
                  LinearProgressIndicator(
                    value: _relayBooksTotal > 0
                        ? _relayBooksLoaded / _relayBooksTotal
                        : null,
                    backgroundColor: Colors.blue.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.blue,
                    ),
                  ),
                RecentlyAddedCarousel(
                  books: _books,
                  scope: RecentlyAddedCarouselScope.peerLib,
                  onBookTap: _showBookDetails,
                ),
                // Book list
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _handleBodyScroll,
                    child: _filteredBooks.isEmpty
                        ? _isRelayLoading
                              ? BookshelfSkeleton(
                                  message: TranslationService.translate(
                                    context,
                                    'connecting_via_relay',
                                  ),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.library_books_outlined,
                                        size: 64,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        TranslationService.translate(
                                          context,
                                          'no_books_found',
                                        ),
                                        style: TextStyle(
                                          fontSize: 18,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      ElevatedButton.icon(
                                        onPressed: () => _syncBooks(),
                                        icon: const Icon(Icons.sync),
                                        label: Text(
                                          TranslationService.translate(
                                            context,
                                            'sync_library',
                                          ),
                                        ),
                                      ),
                                      if (!_isPeerOnline) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          TranslationService.translate(
                                            context,
                                            'peer_offline',
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[700],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollUpdateNotification &&
                                  notification.metrics.pixels >=
                                      notification.metrics.maxScrollExtent -
                                          200) {
                                _loadMoreBooks();
                              }
                              return false;
                            },
                            child: switch (effectiveViewMode) {
                              _PeerViewMode.shelf => BookshelfView(
                                books: _filteredBooks,
                                onBookTap: (book) => _showBookDetails(book),
                                footer: _hasMorePages
                                    ? _isLoadingMore
                                          ? const Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            )
                                          : Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Text(
                                                '${_books.length} / $_totalBooks',
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                    : null,
                              ),
                              _PeerViewMode.coverGrid => GridView.builder(
                                padding: const EdgeInsets.all(16),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 150,
                                      childAspectRatio: 0.65,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                    ),
                                itemCount:
                                    _filteredBooks.length +
                                    (_hasMorePages ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _filteredBooks.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  final book = _filteredBooks[index];
                                  final resolvedBook = book.copyWithCoverUrl(
                                    _resolvePeerCoverUrl(book),
                                  );
                                  return BookCoverCard(
                                    book: resolvedBook,
                                    onTap: () => _showBookDetails(book),
                                    isPeerCover: true,
                                  );
                                },
                              ),
                              _PeerViewMode.list => ListView.separated(
                                itemCount:
                                    _filteredBooks.length +
                                    (_hasMorePages ? 1 : 0),
                                separatorBuilder: (context, index) =>
                                    index < _filteredBooks.length - 1
                                    ? const Divider(
                                        height: 1,
                                        indent: 16,
                                        endIndent: 16,
                                      )
                                    : const SizedBox.shrink(),
                                itemBuilder: (context, index) {
                                  if (index == _filteredBooks.length) {
                                    // Loading indicator at the bottom
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  final book = _filteredBooks[index];
                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: CachedBookCover(
                                      imageUrl: _resolvePeerCoverUrl(book),
                                      width: 40,
                                      height: 60,
                                      borderRadius: BorderRadius.circular(4),
                                      onTapPlaceholder: () =>
                                          _reloadCover(book),
                                      isPeerCover: true,
                                      semanticLabel:
                                          book.author != null &&
                                              book.author!.isNotEmpty
                                          ? '${book.title}, ${book.author}'
                                          : book.title,
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            book.title,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (book.isNew) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFC62828),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              TranslationService.translate(
                                                context,
                                                'badge_new',
                                              ).toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(
                                      book.author ?? 'Unknown Author',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.color,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: canBorrowModule
                                        ? ElevatedButton(
                                            onPressed: _canBorrow(book)
                                                ? () => _requestBorrow(book)
                                                : null,
                                            style: ElevatedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 8,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: Text(
                                              _hasPendingRequest(book)
                                                  ? TranslationService.translate(
                                                      context,
                                                      'borrow_pending',
                                                    )
                                                  : _isActiveBorrow(book)
                                                  ? TranslationService.translate(
                                                      context,
                                                      'borrow_active',
                                                    )
                                                  : _isLending(book)
                                                  ? TranslationService.translate(
                                                      context,
                                                      'borrow_on_loan',
                                                    )
                                                  : _hasNoCopiesAvailable(book)
                                                  ? TranslationService.translate(
                                                      context,
                                                      'borrow_unavailable',
                                                    )
                                                  : TranslationService.translate(
                                                      context,
                                                      'borrow',
                                                    ),
                                            ),
                                          )
                                        : null,
                                    onTap: () => _showBookDetails(book),
                                  );
                                },
                              ),
                            },
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showBookDetails(Book book) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          final closeLabel = TranslationService.translate(context, 'close');
          final canBorrowModule = context.read<ThemeProvider>().canBorrowBooks;
          return Column(
            children: [
              // Pinned header: drag handle + close button (always visible)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: closeLabel,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable content (cover + info + description)
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cover + info row (same layout as hub book detail sheet)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CachedBookCover(
                            imageUrl: _resolvePeerCoverUrl(book),
                            width: 120,
                            height: 180,
                            borderRadius: BorderRadius.circular(8),
                            onTapPlaceholder: () => _reloadCover(book),
                            isPeerCover: true,
                            semanticLabel:
                                book.author != null && book.author!.isNotEmpty
                                ? '${book.title}, ${book.author}'
                                : book.title,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (book.author != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    book.author!,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                                if (book.publisher != null ||
                                    book.publicationYear != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      book.publisher,
                                      book.publicationYear?.toString(),
                                    ].whereType<String>().join(' - '),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                                if (book.isbn != null &&
                                    book.isbn!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'ISBN: ${book.isbn}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (book.summary != null && book.summary!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(book.summary!, style: theme.textTheme.bodyMedium),
                      ],
                    ],
                  ),
                ),
              ),
              // Pinned bottom action bar: borrow CTA always reachable.
              // Hidden entirely when the loans module is disabled in settings.
              if (canBorrowModule)
                Material(
                  elevation: 8,
                  color: theme.colorScheme.surface,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _canBorrow(book)
                              ? () {
                                  Navigator.pop(context);
                                  _requestBorrow(book);
                                }
                              : null,
                          icon: Icon(
                            _canBorrow(book)
                                ? Icons.swap_horiz
                                : _hasPendingRequest(book) ||
                                      _isActiveBorrow(book)
                                ? Icons.hourglass_top
                                : _isLending(book)
                                ? Icons.swap_horiz
                                : Icons.block,
                          ),
                          label: Text(
                            _hasPendingRequest(book)
                                ? TranslationService.translate(
                                    context,
                                    'borrow_pending',
                                  )
                                : _isActiveBorrow(book)
                                ? TranslationService.translate(
                                    context,
                                    'borrow_active',
                                  )
                                : _isLending(book)
                                ? TranslationService.translate(
                                    context,
                                    'borrow_on_loan',
                                  )
                                : _hasNoCopiesAvailable(book)
                                ? TranslationService.translate(
                                    context,
                                    'borrow_unavailable',
                                  )
                                : TranslationService.translate(
                                    context,
                                    'request_to_borrow',
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
