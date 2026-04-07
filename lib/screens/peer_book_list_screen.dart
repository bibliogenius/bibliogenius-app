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
import '../models/hub_directory.dart';
import '../widgets/bookshelf_view.dart';
import '../widgets/shimmer_loading.dart';
import '../services/translation_service.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../services/mdns_service.dart';
import '../utils/app_constants.dart';

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
  bool _isShelfView = true;
  bool _isPeerOnline = true;
  String? _lastSynced;
  bool _isSyncing = false;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  /// Background refresh state (cache-first pattern)
  bool _isRefreshing = false;

  /// IDs of books that are "new" (first_seen_at within threshold)
  Set<int> _newBookIds = {};

  /// Relay sync state (ADR-012)
  bool _isRelayLoading = false;
  int _relayBooksLoaded = 0;
  int _relayBooksTotal = 0;
  Timer? _pollTimer;
  bool _pollRequestInFlight = false;

  /// Hub catalog fallback: true when books come from hub (limited metadata)
  bool _isHubOnly = false;

  /// Hub contact info (decrypted)
  String? _decryptedContact;
  HubProfile? _hubProfile;

  /// ISBNs with a pending outgoing borrow request (to disable the borrow button)
  Set<String> _pendingBorrowIsbns = {};

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
    super.dispose();
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
          !widget.nodeId!.startsWith('peer_') &&
          p.libraryId == widget.nodeId) {
        _lanUrl = 'http://${p.host}:${p.port}';
        _lanUrlTrusted = true;
        if (kDebugMode) debugPrint('mDNS: resolved relay peer via LAN (by UUID)');
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
      if (kDebugMode) debugPrint('mDNS: LAN candidate by name (pending validation)');
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
    final url = _lanUrl ?? (widget.peerUrl.startsWith('relay://') ? null : widget.peerUrl);
    if (url == null) return null;

    final uuid = await api.fetchPeerLibraryUuid(url);
    if (uuid != null && uuid.isNotEmpty) {
      if (kDebugMode) debugPrint('Backfill: resolved library_uuid');
      // Persist so this lookup never has to happen again
      if (widget.peerId > 0) {
        api.updatePeerUrl(widget.peerId, url, libraryUuid: uuid).then((_) {
          if (kDebugMode) debugPrint('Backfill: library_uuid persisted');
        }).onError((e, _) {
          if (kDebugMode) debugPrint('Backfill: failed to persist library_uuid: $e');
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
                _newBookIds = _extractNewBookIds(booksData);
                _books =
                    booksData.map((json) => Book.fromJson(json)).toList();
                _filteredBooks = _isSearching && _searchController.text.isNotEmpty
                    ? _books.where((b) => _matchesSearch(b, _searchController.text)).toList()
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
      if (nodeId == null || nodeId.startsWith('peer_')) {
        final resolved = await _backfillLibraryUuid();
        if (resolved != null) {
          _resolvedNodeId = resolved;
          nodeId = resolved;
          debugPrint('Hub catalog: backfilled nodeId=$nodeId from peer config');
        }
      }

      if (nodeId != null && !nodeId.startsWith('peer_')) {
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
        final hasWifi = connectivity.contains(ConnectivityResult.wifi) ||
            connectivity.contains(ConnectivityResult.ethernet);
        if (!hasWifi) {
          debugPrint('Not on WiFi/ethernet - skipping LAN connectivity check');
          isOnline = false;
        } else {
          isOnline = await api.checkPeerConnectivity(
            url,
            timeoutMs: 2000,
          );
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
          if (hubFuture == null && validNodeId != null && !validNodeId.startsWith('peer_')) {
            hubFuture = _books.isNotEmpty
                ? _refreshFromHubCatalog()
                : _loadHubCatalog();
          }
        }
      }

      // Persist LAN URL upgrade in background (so future opens are fast)
      if (isOnline && _lanUrl != null && _lanUrlTrusted && widget.peerId > 0) {
        debugPrint('Persisting LAN URL upgrade: ${widget.peerUrl} → $_lanUrl');
        api.updatePeerUrl(widget.peerId, _lanUrl!, libraryUuid: _resolvedNodeId).then((_) {
          debugPrint('LAN URL persisted successfully');
        }).catchError((e) {
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
            if (total != null && total == _books.length) {
              // Library unchanged — stop refreshing
              debugPrint('Peer library unchanged ($total books), skipping full refresh');
              setState(() => _isRefreshing = false);
            } else {
              // Library changed — full background refresh
              debugPrint('Peer library changed (cached=${_books.length}, remote total=$total), refreshing');
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
              _newBookIds = _extractNewBookIds(parsed.booksData);
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

            // Cache first page
            if (_offlineCachingEnabled && widget.peerId > 0) {
              api.cachePeerBooks(widget.peerId, _books).catchError((e) {
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
        if (mounted) setState(() { _isRefreshing = false; _isLoading = false; });
        // Cache/hub data displayed, but it may be stale. When offline with
        // relay credentials, trigger a background relay sync so peers get
        // fresh books even when not on the same WiFi (ADR-012 fallback).
        if (!isOnline && widget.hasRelayCredentials) {
          _tryRelaySync();
        }
        return;
      }

      // 6. No data yet — try relay if available
      if (!widget.hasRelayCredentials) {
        if (mounted) setState(() { _isLoading = false; _isRefreshing = false; });
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
      final total = (data['total'] as int?) ?? booksData.length;
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
    if (data is Map) return data['total'] as int?;
    if (data is List) return data.length;
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
      final newBooks =
          parsed.booksData.map((json) => Book.fromJson(json)).toList();
      final newIds = _extractNewBookIds(parsed.booksData);

      setState(() {
        _books.addAll(newBooks);
        _newBookIds.addAll(newIds);
        _filteredBooks = _isSearching
            ? _books
                .where(
                  (b) => _matchesSearch(b, _searchController.text),
                )
                .toList()
            : _books;
        _currentPage = nextPage;
        _hasMorePages = parsed.hasMore;
        _allBooksLoaded = !parsed.hasMore;
        _isLoadingMore = false;
      });

      // Update cache with growing book list
      if (_offlineCachingEnabled && widget.peerId > 0) {
        api.cachePeerBooks(widget.peerId, _books).catchError((_) {});
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

  /// Full background refresh: fetch all pages and replace current data.
  Future<void> _fullBackgroundRefresh(ApiService api) async {
    try {
      final allBooks = <Book>[];
      final allNewIds = <int>{};
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
        allNewIds.addAll(_extractNewBookIds(parsed.booksData));
        hasMore = parsed.hasMore;
        page++;
      }

      if (mounted) {
        setState(() {
          _books = allBooks;
          _newBookIds = allNewIds;
          _filteredBooks = _books;
          _totalBooks = allBooks.length;
          _hasMorePages = false;
          _allBooksLoaded = true;
          _currentPage = page - 1;
          _isRefreshing = false;
          _isHubOnly = false;
        });

        if (_offlineCachingEnabled && widget.peerId > 0) {
          api.cachePeerBooks(widget.peerId, _books).catchError((_) {});
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

  /// Extract IDs of books whose first_seen_at is within the new-badge threshold
  /// from the raw JSON list (peer_book models include first_seen_at).
  Set<int> _extractNewBookIds(List<dynamic> booksData) {
    final now = DateTime.now();
    final ids = <int>{};
    for (final json in booksData) {
      if (json is Map) {
        final firstSeen = json['first_seen_at'] as String?;
        if (firstSeen == null) continue;
        final parsed = DateTime.tryParse(firstSeen);
        if (parsed != null &&
            now.difference(parsed).inDays < AppConstants.newBadgeDays) {
          final id = json['id'] as int?;
          if (id != null) ids.add(id);
        }
      }
    }
    return ids;
  }

  /// Refresh from hub catalog: if the peer pushed updates to the hub while
  /// offline, detect new books and merge them into the displayed list.
  /// Unlike _loadHubCatalog (full fallback), this enriches the existing
  /// cache/list with any books present in the hub but missing locally.
  Future<void> _refreshFromHubCatalog() async {
    final nodeId = _effectiveNodeId;
    if (nodeId == null || nodeId.startsWith('peer_')) return;
    try {
      final ffi = FfiService();
      final entries = await ffi.hubDirectoryGetCatalog(nodeId);
      if (!mounted || entries.isEmpty) return;

      // Hub catalog is an enrichment layer — it may lag behind the cache
      // (peer added books but hasn't pushed to hub yet).  So we only ADD
      // new books and UPDATE metadata for known books.  We never REMOVE
      // books based on hub — only live P2P or relay sync are authoritative
      // for deletions.

      final knownIsbns = <String, Book>{};
      for (final b in _books) {
        if (b.isbn != null && b.isbn!.isNotEmpty) knownIsbns[b.isbn!] = b;
      }

      bool changed = false;
      final updatedBooks = List<Book>.from(_books);

      for (final e in entries) {
        if (e.isbn.isEmpty) continue;
        final existing = knownIsbns[e.isbn];
        if (existing != null) {
          // Update title/author if hub has newer metadata
          final newTitle = e.title.isNotEmpty ? e.title : existing.title;
          final newAuthor = (e.author?.isNotEmpty == true) ? e.author : existing.author;
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
          updatedBooks.add(Book(
            title: e.title,
            author: e.author,
            isbn: e.isbn,
            coverUrl: e.coverUrl,
          ));
          changed = true;
        }
      }

      if (!changed) {
        debugPrint('Hub catalog: no changes (${entries.length} entries, ${_books.length} books)');
        if (_newBookIds.isNotEmpty) {
          setState(() => _newBookIds = {});
        }
        return;
      }

      debugPrint('Hub catalog: enriched to ${updatedBooks.length} books (was ${_books.length})');

      setState(() {
        _books = updatedBooks;
        _filteredBooks = _isSearching && _searchController.text.isNotEmpty
            ? _books.where((b) => _matchesSearch(b, _searchController.text)).toList()
            : _books;
        _newBookIds = {};
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
    if (nodeId == null || nodeId.startsWith('peer_')) return;
    try {
      final ffi = FfiService();
      debugPrint('Hub catalog: fetching for $nodeId');
      final entries = await ffi.hubDirectoryGetCatalog(nodeId);
      debugPrint('Hub catalog: got ${entries.length} entries');
      if (!mounted || entries.isEmpty) return;
      // Don't override if live/cached data arrived while we were fetching
      if (_books.isNotEmpty) {
        debugPrint('Hub catalog: skipped (live data already loaded: ${_books.length} books)');
        return;
      }

      final books = entries.map((e) => Book(
        title: e.title,
        author: e.author,
        isbn: e.isbn.isNotEmpty ? e.isbn : null,
        coverUrl: e.coverUrl,
      )).toList();

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
  Future<void> _tryRelaySync() async {
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
        final remoteUuid = manifest['library_uuid'] as String?;
        if (remoteUuid != null && remoteUuid != _effectiveNodeId) {
          debugPrint(
            'Relay: peer library_uuid updated: '
            '$_effectiveNodeId -> $remoteUuid',
          );
          _resolvedNodeId = remoteUuid;
          // Trigger hub catalog refresh with corrected nodeId
          _refreshFromHubCatalog();
        }

        // Skip re-fetch if catalog is unchanged (hash match)
        final newHash = manifest['catalog_hash'] as String?;
        if (newHash != null && _books.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final cachedHash =
              prefs.getString('peer_catalog_hash_${widget.peerId}');
          if (newHash == cachedHash) {
            debugPrint(
              'Relay: catalog unchanged (hash match), skipping re-fetch',
            );
            if (mounted) setState(() => _isRelayLoading = false);
            return;
          }
        }
        await _fetchRelayPages(api, manifest);
      } else {
        // manifest returned null (202 relay_pending) - start polling
        debugPrint('Relay: manifest pending, starting adaptive polling');
        _startAdaptivePolling();
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
    final totalBooks = manifest['total_books'] as int? ?? 0;
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
            (json) =>
                Book.fromJson(json is Map<String, dynamic> ? json : {}),
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
        page = await api.requestPeerPage(
          widget.peerId,
          cursor: cursor,
        );
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

      final books = (page['books'] as List?)
              ?.map(
                (json) =>
                    Book.fromJson(json is Map<String, dynamic> ? json : {}),
              )
              .toList() ??
          [];

      allBooks.addAll(books);

      if (mounted) {
        setState(() {
          _books = List.from(allBooks);
          _filteredBooks = _books;
          _relayBooksLoaded = allBooks.length;
          _isLoading = false;
          _isHubOnly = false;
        });
      }

      // Check if there are more pages
      final nextCursor = page['next_cursor'];
      if (nextCursor == null || books.isEmpty) break;
      cursor = nextCursor is int ? nextCursor : null;
      if (cursor == null) break;
    }

    // Save relay-fetched books to local cache for instant display next visit
    if (_offlineCachingEnabled && allBooks.isNotEmpty) {
      api.cachePeerBooks(widget.peerId, allBooks).then((_) {
        if (kDebugMode) debugPrint('Cached ${allBooks.length} books for peer');
      }).catchError((e) {
        if (kDebugMode) debugPrint('Failed to cache books: $e');
      });
    }

    // Save catalog hash for diff check on next visit
    final catalogHash = manifest['catalog_hash'] as String?;
    if (catalogHash != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'peer_catalog_hash_${widget.peerId}',
        catalogHash,
      );
    }

    if (mounted) {
      setState(() => _isRelayLoading = false);
    }
  }

  /// Adaptive polling: poll relay every 5s, retry manifest after each poll.
  /// When the relay response arrives, continues with page fetching.
  /// Gives up after 3 minutes (ADR-012).
  /// Uses _pollRequestInFlight guard to prevent concurrent requests that
  /// would flood the relay with different correlation IDs.
  /// Circuit breaker: stops immediately on 502 (peer unreachable).
  void _startAdaptivePolling() {
    _pollTimer?.cancel();
    _pollRequestInFlight = false;
    final api = Provider.of<ApiService>(context, listen: false);
    int pollCount = 0;
    const maxPolls = 36; // 36 * 5s = 3 minutes

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_pollRequestInFlight) {
        debugPrint('Relay: skipping poll tick (previous request still in flight)');
        return;
      }

      pollCount++;
      if (pollCount > maxPolls || !mounted) {
        timer.cancel();
        if (mounted) {
          debugPrint('Relay: polling timed out after ${pollCount * 5}s');
          setState(() => _isRelayLoading = false);
        }
        return;
      }

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

          debugPrint('Relay: manifest received after ${pollCount * 5}s');
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
        final label =
            TranslationService.translate(context, 'synced_minutes_ago');
        final v = age.inMinutes.toString();
        return label.replaceAll('%d', v).replaceAll('{count}', v);
      } else if (age.inHours < 24) {
        final label =
            TranslationService.translate(context, 'synced_hours_ago');
        final v = age.inHours.toString();
        return label.replaceAll('%d', v).replaceAll('{count}', v);
      } else {
        final label =
            TranslationService.translate(context, 'synced_days_ago');
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
    // Sort: new books first, then alphabetical
    if (_newBookIds.isNotEmpty) {
      result.sort((a, b) {
        final aNew = _newBookIds.contains(a.id);
        final bNew = _newBookIds.contains(b.id);
        if (aNew != bNew) return aNew ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    }
    setState(() => _filteredBooks = result);
  }

  Future<void> _syncBooks({bool showFeedback = true}) async {
    if (_isSyncing) return;

    // Re-resolve mDNS in case WiFi state changed since init
    _tryResolveLanUrl();

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
                _newBookIds = _extractNewBookIds(booksData);
                _books = booksData.map((json) => Book.fromJson(json)).toList();
                _filteredBooks = _isSearching && _searchController.text.isNotEmpty
                    ? _books.where((b) => _matchesSearch(b, _searchController.text)).toList()
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
      if (nodeId != null && !nodeId.startsWith('peer_')) {
        await _refreshFromHubCatalog();
        if (mounted) {
          setState(() => _isSyncing = false);
          if (showFeedback) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  TranslationService.translate(context, 'library_synced'),
                ),
              ),
            );
          }
        }
        return;
      }
      // No hub — fall back to relay sync (ADR-012)
      if (mounted) setState(() => _isSyncing = false);
      _tryRelaySync();
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                    context,
                    'syncing_via_relay',
                  ),
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
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
        _newBookIds = _extractNewBookIds(parsed.booksData);
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
        api.syncPeer(_effectiveUrl).then((_) {
          debugPrint('Background cache sync completed');
        }).catchError((e) {
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
      final res = await api.getOutgoingRequests();
      final requests = res.data as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _pendingBorrowIsbns = requests
              .where((r) => r['status'] == 'pending')
              .map((r) => r['book_isbn']?.toString() ?? '')
              .where((isbn) => isbn.isNotEmpty)
              .toSet();
        });
      }
    } catch (_) {
      // Non-blocking: if we can't load, just don't disable any button
    }
  }

  bool _hasPendingRequest(Book book) {
    final isbn = book.isbn;
    return isbn != null && isbn.isNotEmpty && _pendingBorrowIsbns.contains(isbn);
  }

  bool _hasNoCopiesAvailable(Book book) {
    return book.availableCopies != null && book.availableCopies == 0;
  }

  bool _canBorrow(Book book) {
    // Can't borrow a book the peer doesn't own (e.g. they borrowed it themselves)
    // For hub catalog books, owned defaults to true (unknown = allow request,
    // server auto-rejects if no available copy).
    if (!book.owned) return false;
    return !_hasPendingRequest(book) && !_hasNoCopiesAvailable(book);
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
      final response = await api.requestBookByUrl(widget.peerUrl, isbn ?? "", book.title);
      if (!mounted) return;
      final data = response.data;
      // Check lender's response status
      if (data is Map && data['status'] == 'rejected') {
        // Remove from pending since the request was rejected
        if (isbn != null && isbn.isNotEmpty) {
          setState(() => _pendingBorrowIsbns.remove(isbn));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'borrow_request_rejected_no_copy'),
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
              "${TranslationService.translate(context, 'error_sending_request')}: $e",
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
                label: Text(
                  TranslationService.translate(context, 'retry'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubContactBar() {
    final hasWebsite =
        _hubProfile?.website != null && _hubProfile!.website!.isNotEmpty;
    final hasContact =
        _decryptedContact != null && _decryptedContact!.isNotEmpty;
    if (!hasWebsite && !hasContact) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasWebsite)
            _buildWebsiteRow(_hubProfile!.website!, cs),
          if (hasWebsite && hasContact)
            const SizedBox(height: 6),
          if (hasContact)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.lock_outlined,
                      size: 15, color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _decryptedContact!,
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
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
            Icon(Icons.language, size: 15,
                color: cs.onPrimaryContainer.withValues(alpha: 0.7)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                uri.toString(),
                style: TextStyle(
                  fontSize: 13,
                  color: cs.primary,
                ),
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
        : _isRelayLoading || _isHubOnly
            ? Icons.cloud_queue
            : Icons.cloud_off;
    final channelLabel = _isPeerOnline
        ? 'Wi-Fi'
        : _isRelayLoading
            ? 'Relay'
            : _isHubOnly
                ? 'Hub'
                : 'Offline';
    final subtleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);

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
              _isRelayLoading
                  ? '${TranslationService.translate(context, 'syncing_via_relay')}...'
                  : _formatStaleness(),
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
            )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: TranslationService.translate(context, 'peer_library_search_hint'),
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
                      child: Text(widget.peerName)),
                  if (widget.caption != null && widget.caption!.isNotEmpty)
                    Text(
                      widget.caption!,
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
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
                icon: (_isSyncing || _isRelayLoading || _isRefreshing)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync),
                tooltip:
                    TranslationService.translate(context, 'sync_library'),
                onPressed:
                    (_isSyncing || _isRelayLoading || _isRefreshing)
                        ? null
                        : () => _syncBooks(),
              ),
            ),
          if (!_isSearching)
            IconButton(
              icon: Icon(_isShelfView ? Icons.list : Icons.grid_view),
              tooltip: TranslationService.translate(context, 'toggle_view'),
              onPressed: () {
                setState(() {
                  _isShelfView = !_isShelfView;
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
                    // Sync status bar (includes channel indicator)
                    // Hub contact info bar
                    _buildHubContactBar(),
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
                    // Book list
                    Expanded(
                      child: _filteredBooks.isEmpty
                          ? _isRelayLoading
                              ? BookshelfSkeleton(
                                  message:
                                      TranslationService.translate(
                                        context,
                                        'connecting_via_relay',
                                      ),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
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
                                        notification.metrics.maxScrollExtent - 200) {
                                  _loadMoreBooks();
                                }
                                return false;
                              },
                              child: _isShelfView
                                  ? BookshelfView(
                                      books: _filteredBooks,
                                      onBookTap: (book) => _showBookDetails(book),
                                      newBookIds: _newBookIds,
                                      footer: _hasMorePages
                                          ? _isLoadingMore
                                              ? const Padding(
                                                  padding: EdgeInsets.all(16),
                                                  child: Center(child: CircularProgressIndicator()),
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
                                    )
                                  : ListView.separated(
                                      itemCount: _filteredBooks.length + (_hasMorePages ? 1 : 0),
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
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 8,
                                          ),
                                          leading: Container(
                                            width: 40,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              color: Colors.grey[200],
                                              image: book.coverUrl != null
                                                  ? DecorationImage(
                                                      image: NetworkImage(
                                                        book.coverUrl!,
                                                      ),
                                                      fit: BoxFit.cover,
                                                    )
                                                  : null,
                                            ),
                                            child: book.coverUrl == null
                                                ? const Icon(
                                                    Icons.book,
                                                    color: Colors.grey,
                                                    size: 20,
                                                  )
                                                : null,
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
                                              if (_newBookIds
                                                  .contains(book.id)) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
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
                                                            context, 'badge_new')
                                                        .toUpperCase(),
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
                                              color: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.color,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          trailing: ElevatedButton(
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
                                          ),
                                          onTap: () => _showBookDetails(book),
                                        );
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[200],
                    image: book.largeCoverUrl != null
                        ? DecorationImage(
                            image: NetworkImage(book.largeCoverUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: book.largeCoverUrl == null
                      ? const Icon(
                          Icons.book,
                          size: 50,
                          color: Colors.grey,
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                book.title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  book.author ?? 'Unknown Author',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 24),
              if (book.summary != null && book.summary!.isNotEmpty) ...[
                Text(
                  TranslationService.translate(
                    context,
                    'book_summary',
                  ),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  book.summary!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _canBorrow(book)
                      ? () {
                          Navigator.pop(context);
                          _requestBorrow(book);
                        }
                      : null,
                  icon: Icon(_canBorrow(book)
                      ? Icons.bookmark_add
                      : _hasPendingRequest(book)
                          ? Icons.hourglass_top
                          : Icons.block),
                  label: Text(
                    _hasPendingRequest(book)
                        ? TranslationService.translate(
                            context,
                            'borrow_pending',
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
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
