import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../models/book.dart';
import '../models/hub_directory.dart';
import '../src/rust/api/frb.dart' show FrbCatalogEntry;
import '../widgets/bookshelf_view.dart';
import '../widgets/book_spine.dart';
import '../widgets/shimmer_loading.dart';
import '../services/translation_service.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
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

  const PeerBookListScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerUrl,
    this.hasRelayCredentials = false,
    this.nodeId,
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

  /// Hub catalog fallback state (hub-only data: title + author + ISBN)
  bool _isHubOnly = false;
  List<FrbCatalogEntry> _hubEntries = [];

  /// Hub contact info (decrypted)
  String? _decryptedContact;
  HubProfile? _hubProfile;

  /// ISBNs with a pending outgoing borrow request (to disable the borrow button)
  Set<String> _pendingBorrowIsbns = {};

  @override
  void initState() {
    super.initState();
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

    // Fetch hub profile for website
    try {
      final frbProfile = await FfiService().hubDirectoryGetProfile(nodeId);
      if (mounted && frbProfile != null) {
        setState(() => _hubProfile = HubProfile.fromFrb(frbProfile));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pollTimer?.cancel();
    super.dispose();
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
                _filteredBooks = _books;
                _lastSynced = data['last_synced'];
                _isLoading = false;
                _isRefreshing = true;
              });
              cacheDisplayed = true;
            }
          }
        } catch (e) {
          debugPrint('Cache load failed: $e');
        }
      }

      // 2. Check connectivity - skip LAN attempt if not on WiFi (avoids 3s timeout)
      debugPrint('Checking connectivity for ${widget.peerUrl}');
      bool isOnline = false;
      if (widget.peerUrl.startsWith('relay://')) {
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
            widget.peerUrl,
            timeoutMs: 2000,
          );
        }
      }

      if (!mounted) return;
      setState(() => _isPeerOnline = isOnline);

      // 3. If ONLINE: fetch live (background refresh if cache was shown)
      if (isOnline) {
        debugPrint('Peer online - fetching books live from ${widget.peerUrl}');
        try {
          final liveRes = await api.getPeerBooksByUrl(widget.peerUrl);

          if (!mounted) return;

          List<dynamic> booksData = [];
          if (liveRes.data is Map && liveRes.data['books'] != null) {
            booksData = liveRes.data['books'];
          } else if (liveRes.data is List) {
            booksData = liveRes.data;
          }

          setState(() {
            _books = booksData.map((json) => Book.fromJson(json)).toList();
            _filteredBooks = _books;
            _isLoading = false;
            _isRefreshing = false;
          });

          debugPrint('Loaded ${_books.length} books live from peer');

          // Cache displayed books locally (avoids redundant re-fetch from syncPeer)
          // Skip caching for unsaved mDNS peers (peerId == 0)
          if (_offlineCachingEnabled && widget.peerId > 0) {
            api.cachePeerBooks(widget.peerId, _books).then((_) {
              debugPrint('Cached ${_books.length} live books for peer ${widget.peerId}');
            }).catchError((e) {
              debugPrint('Failed to cache live books: $e');
            });
          }
          return;
        } catch (e) {
          debugPrint('Live fetch failed: $e');
          // If cache was displayed, stop refreshing indicator
          if (cacheDisplayed && mounted) {
            setState(() => _isRefreshing = false);
            return;
          }
          // Fall through to relay
        }
      }

      // 4. Offline (or live fetch failed without cache) - try relay if available
      if (!widget.hasRelayCredentials) {
        // Peer has no relay - try hub catalog fallback if nodeId is available
        if (widget.nodeId != null && _books.isEmpty) {
          await _loadHubCatalog();
        } else {
        }
        if (mounted) setState(() { _isLoading = false; _isRefreshing = false; });
        return;
      }

      if (cacheDisplayed) {
        // Cache is already shown - try relay in background for updates
        if (mounted) setState(() => _isRefreshing = false);
        _tryRelaySync();
        return;
      }

      // 5. No cache, but relay available - try relay sync (ADR-012)
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

  bool _isEntryNew(FrbCatalogEntry entry) {
    final firstSeen = entry.firstSeenAt;
    if (firstSeen == null) return false;
    final parsed = DateTime.tryParse(firstSeen);
    if (parsed == null) return false;
    return DateTime.now().difference(parsed).inDays < AppConstants.newBadgeDays;
  }

  /// Load hub catalog as a last-resort fallback (title + author + ISBN only).
  /// Displays as BookSpines since we have no covers or full book data.
  Future<void> _loadHubCatalog() async {
    if (widget.nodeId == null) return;
    try {
      final ffi = FfiService();
      final entries = await ffi.hubDirectoryGetCatalog(widget.nodeId!);
      if (!mounted) return;
      if (entries.isNotEmpty) {
        setState(() {
          _isHubOnly = true;
          // Sort: new entries first, then alphabetical by title
          _hubEntries = entries..sort((a, b) {
            final aNew = _isEntryNew(a);
            final bNew = _isEntryNew(b);
            if (aNew != bNew) return aNew ? -1 : 1;
            return a.title.compareTo(b.title);
          });
        });
      }
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
        debugPrint('Cached ${allBooks.length} relay books for peer ${widget.peerId}');
      }).catchError((e) {
        debugPrint('Failed to cache relay books: $e');
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
          debugPrint('Relay: manifest received after ${pollCount * 5}s');
          timer.cancel();
          await _fetchRelayPages(api, manifest);
        }
      } catch (e) {
        debugPrint('Adaptive poll error: $e');
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
        return label.replaceAll('%d', age.inMinutes.toString());
      } else if (age.inHours < 24) {
        final label =
            TranslationService.translate(context, 'synced_hours_ago');
        return label.replaceAll('%d', age.inHours.toString());
      } else {
        final label =
            TranslationService.translate(context, 'synced_days_ago');
        return label.replaceAll('%d', age.inDays.toString());
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

    // Check if peer is online before attempting sync
    if (!_isPeerOnline) {
      // Try relay sync instead (ADR-012)
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
      // Fetch books live from peer (no caching consent required)
      final liveRes = await api.getPeerBooksByUrl(widget.peerUrl);

      if (!mounted) return;

      List<dynamic> booksData = [];
      if (liveRes.data is Map && liveRes.data['books'] != null) {
        booksData = liveRes.data['books'];
      } else if (liveRes.data is List) {
        booksData = liveRes.data;
      }

      setState(() {
        _books = booksData.map((json) => Book.fromJson(json)).toList();
        _filteredBooks = _books;
        _isSyncing = false;
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

      // Background sync to update cache (if peer allows caching)
      if (_offlineCachingEnabled) {
        api.syncPeer(widget.peerUrl).then((_) {
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
    return !_hasPendingRequest(book) && !_hasNoCopiesAvailable(book);
  }

  Future<void> _requestBorrow(Book book) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.requestBookByUrl(widget.peerUrl, book.isbn ?? "", book.title);
      if (mounted) {
        // Add ISBN to pending set to immediately disable the button
        final isbn = book.isbn;
        if (isbn != null && isbn.isNotEmpty) {
          setState(() => _pendingBorrowIsbns.add(isbn));
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'borrow_request_sent'),
            ),
          ),
        );
      }
    } catch (e) {
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

  /// Full-page view shown when peer is offline and no books available
  Widget _buildHubOnlyView() {
    return Column(
      children: [
        // Info banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.indigo.withValues(alpha: 0.08),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.indigo[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TranslationService.translate(context, 'hub_only_hint'),
                  style: TextStyle(fontSize: 13, color: Colors.indigo[600]),
                ),
              ),
            ],
          ),
        ),
        // BookSpine shelf view
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 0,
              runSpacing: 20,
              alignment: WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: _hubEntries.map((entry) {
                final seed = entry.isbn.hashCode;
                final isNew = _isEntryNew(entry);
                return GestureDetector(
                  onTap: () => _showHubEntryDetails(entry),
                  child: BookSpine(
                    title: entry.title,
                    subtitle: entry.author,
                    colorSeed: seed,
                    height: 220 + (seed.abs() % 4) * 12.0,
                    width: 60 + (seed.abs() % 3) * 6.0,
                    showNewBand: isNew,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  void _showHubEntryDetails(FrbCatalogEntry entry) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (entry.author != null) ...[
                const SizedBox(height: 8),
                Text(
                  entry.author!,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'ISBN: ${entry.isbn}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                TranslationService.translate(context, 'hub_only_detail_hint'),
                style: TextStyle(fontSize: 13, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
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
    final isRelay = !_isPeerOnline && _books.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isPeerOnline
          ? Colors.green.withValues(alpha: 0.1)
          : isRelay
              ? Colors.blue.withValues(alpha: 0.1)
              : Colors.orange.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(
            _isPeerOnline
                ? Icons.cloud_done
                : isRelay
                    ? Icons.cloud_sync
                    : Icons.cloud_off,
            size: 16,
            color: _isPeerOnline
                ? Colors.green
                : isRelay
                    ? Colors.blue
                    : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isPeerOnline
                  ? _formatStaleness()
                  : _isRelayLoading
                      ? '${TranslationService.translate(context, 'syncing_via_relay')}...'
                      : '${TranslationService.translate(context, 'peer_offline')} - ${_formatStaleness()}',
              style: TextStyle(
                fontSize: 12,
                color: _isPeerOnline
                    ? Colors.green[700]
                    : isRelay
                        ? Colors.blue[700]
                        : Colors.orange[700],
              ),
            ),
          ),
          if (_isRefreshing)
            Text(
              TranslationService.translate(context, 'refreshing_library'),
              style: TextStyle(fontSize: 12, color: Colors.blue[600]),
            )
          else if (_isRelayLoading && _relayBooksTotal > 0)
            Text(
              '$_relayBooksLoaded/$_relayBooksTotal',
              style: TextStyle(fontSize: 12, color: Colors.blue[600]),
            )
          else if (!_isPeerOnline && _books.isNotEmpty)
            Text(
              TranslationService.translate(context, 'showing_cached'),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
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
                decoration: const InputDecoration(
                  hintText: 'Search books...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: _filterBooks,
              )
            : FittedBox(
                fit: BoxFit.scaleDown, child: Text(widget.peerName)),
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
          // Hub-only fallback: display BookSpines from hub catalog data
          : (_isHubOnly && _hubEntries.isNotEmpty && _books.isEmpty)
              ? _buildHubOnlyView()
          // If peer offline, no books, no caching, and not relay loading
              : (!_isPeerOnline &&
                      !_offlineCachingEnabled &&
                      _books.isEmpty &&
                      !_isRelayLoading)
                  ? _buildOfflineNotAvailableView()
              : Column(
                  children: [
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
                          : _isShelfView
                              ? BookshelfView(
                                  books: _filteredBooks,
                                  onBookTap: (book) => _showBookDetails(book),
                                  newBookIds: _newBookIds,
                                )
                              : ListView.separated(
                                  itemCount: _filteredBooks.length,
                                  separatorBuilder: (context, index) =>
                                      const Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                                  itemBuilder: (context, index) {
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
