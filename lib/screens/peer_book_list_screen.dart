import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/book.dart';
import '../widgets/bookshelf_view.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';

class PeerBookListScreen extends StatefulWidget {
  final int peerId; // Keep for compatibility
  final String peerName;
  final String peerUrl; // Add URL

  const PeerBookListScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerUrl,
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

  @override
  void initState() {
    super.initState();
    _loadCachedBooksFirst();
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  /// Load books: fetch live when online, fall back to cache when offline
  Future<void> _loadCachedBooksFirst() async {
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      // 1. Check connectivity first (quick 3s timeout)
      debugPrint('Checking connectivity for ${widget.peerUrl}');
      final isOnline = await api.checkPeerConnectivity(
        widget.peerUrl,
        timeoutMs: 3000,
      );

      if (!mounted) return;
      setState(() => _isPeerOnline = isOnline);

      // 2. If ONLINE: fetch books directly from peer (no caching consent needed)
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
          });

          debugPrint('Loaded ${_books.length} books live from peer');

          // Background sync to update cache (if peer allows caching)
          if (_offlineCachingEnabled) {
            api.syncPeer(widget.peerUrl).then((_) {
              debugPrint('Background cache sync completed');
            }).catchError((e) {
              debugPrint('Background cache sync failed: $e');
            });
          }
          return;
        } catch (e) {
          debugPrint('Live fetch failed, falling back to cache: $e');
          // Fall through to cache logic below
        }
      }

      // 3. If offline and caching disabled, stop here - show offline message
      if (!isOnline && !_offlineCachingEnabled) {
        debugPrint('Peer offline and caching disabled - showing offline view');
        setState(() => _isLoading = false);
        return;
      }

      // 4. Load cached books (offline + caching enabled, or live fetch failed)
      debugPrint('Loading cached books for ${widget.peerUrl}');
      final cachedRes = await api.getCachedPeerBooks(widget.peerUrl);

      if (mounted) {
        final data = cachedRes.data;
        List<dynamic> booksData = data['books'] ?? [];

        setState(() {
          _books = booksData.map((json) => Book.fromJson(json)).toList();
          _filteredBooks = _books;
          _lastSynced = data['last_synced'];
          _isLoading = false;
        });

        debugPrint(
          'Loaded ${_books.length} cached books, last_synced: $_lastSynced',
        );
      }
    } catch (e) {
      debugPrint('Error loading books: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Determine if auto-sync should occur based on staleness
  bool _shouldAutoSync() {
    // Always sync if no books cached
    if (_books.isEmpty) return true;

    // Sync if never synced
    if (_lastSynced == null) return true;

    try {
      final syncTime = DateTime.parse(_lastSynced!);
      final age = DateTime.now().difference(syncTime);
      return age.inHours >= 1; // Auto-sync if older than 1 hour
    } catch (_) {
      return true;
    }
  }

  /// Format staleness for display
  String _formatStaleness() {
    if (_lastSynced == null) {
      return TranslationService.translate(context, 'never_synced') ??
          'Never synced';
    }

    try {
      final syncTime = DateTime.parse(_lastSynced!);
      final age = DateTime.now().difference(syncTime);

      if (age.inMinutes < 1) {
        return TranslationService.translate(context, 'synced_just_now') ??
            'Synced just now';
      } else if (age.inMinutes < 60) {
        final label =
            TranslationService.translate(context, 'synced_minutes_ago') ??
                'Synced %d min ago';
        return label.replaceAll('%d', age.inMinutes.toString());
      } else if (age.inHours < 24) {
        final label =
            TranslationService.translate(context, 'synced_hours_ago') ??
                'Synced %dh ago';
        return label.replaceAll('%d', age.inHours.toString());
      } else {
        final label =
            TranslationService.translate(context, 'synced_days_ago') ??
                'Synced %d days ago';
        return label.replaceAll('%d', age.inDays.toString());
      }
    } catch (_) {
      return _lastSynced ?? '';
    }
  }

  void _filterBooks(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredBooks = _books;
      });
      return;
    }
    setState(() {
      _filteredBooks = _books.where((book) {
        final title = book.title.toLowerCase();
        final author = book.author?.toLowerCase() ?? '';
        final isbn = book.isbn?.toLowerCase() ?? '';
        final q = query.toLowerCase();
        return title.contains(q) || author.contains(q) || isbn.contains(q);
      }).toList();
    });
  }

  Future<void> _syncBooks({bool showFeedback = true}) async {
    if (_isSyncing) return;

    // Check if peer is online before attempting sync
    if (!_isPeerOnline) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                    context,
                    'peer_offline_cannot_sync',
                  ) ??
                  'Peer is offline, cannot sync',
            ),
            backgroundColor: Colors.orange,
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
              TranslationService.translate(context, 'library_synced') ??
                  'Library refreshed',
            ),
          ),
        );
      }

      // Background sync to update cache (if peer allows caching)
      if (_offlineCachingEnabled) {
        api.syncPeer(widget.peerUrl).then((_) {
          debugPrint('Background cache sync completed');
        }).catchError((e) {
          debugPrint('Background cache sync failed (peer may not allow caching): $e');
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

  Future<void> _requestBorrow(Book book) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.requestBookByUrl(widget.peerUrl, book.isbn ?? "", book.title);
      if (mounted) {
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

  /// Full-page view shown when peer is offline and caching is disabled
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
              TranslationService.translate(context, 'peer_offline') ??
                  'Offline',
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
                  ) ??
                  'This library is currently unavailable. The contact must be online to view their books.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: () => _loadCachedBooksFirst(),
              icon: const Icon(Icons.refresh),
              label: Text(
                TranslationService.translate(context, 'retry') ?? 'Retry',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStalenessBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color:
          _isPeerOnline
              ? Colors.green.withOpacity(0.1)
              : Colors.orange.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            _isPeerOnline ? Icons.cloud_done : Icons.cloud_off,
            size: 16,
            color: _isPeerOnline ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isPeerOnline
                  ? _formatStaleness()
                  : '${TranslationService.translate(context, 'peer_offline') ?? 'Offline'} - ${_formatStaleness()}',
              style: TextStyle(
                fontSize: 12,
                color: _isPeerOnline ? Colors.green[700] : Colors.orange[700],
              ),
            ),
          ),
          if (!_isPeerOnline)
            Text(
              TranslationService.translate(context, 'showing_cached') ??
                  'Showing cached',
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
        title:
            _isSearching
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
                : FittedBox(fit: BoxFit.scaleDown, child: Text(widget.peerName)),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
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
              builder:
                  (context) => IconButton(
                    icon:
                        _isSyncing
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
                    onPressed: _isSyncing ? null : () => _syncBooks(),
                  ),
            ),
          if (!_isSearching)
            IconButton(
              icon: Icon(_isShelfView ? Icons.list : Icons.grid_view),
              onPressed: () {
                setState(() {
                  _isShelfView = !_isShelfView;
                });
              },
            ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              // If peer offline and caching disabled, show offline message
              : (!_isPeerOnline && !_offlineCachingEnabled)
              ? _buildOfflineNotAvailableView()
              : Column(
                children: [
                  // Staleness indicator bar
                  _buildStalenessBar(),
                  // Book list
                  Expanded(
                    child:
                        _filteredBooks.isEmpty
                            ? Center(
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
                                    onPressed:
                                        _isPeerOnline
                                            ? () => _syncBooks()
                                            : null,
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
                                          ) ??
                                          'Peer is offline',
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
                            )
                            : ListView.separated(
                              itemCount: _filteredBooks.length,
                              separatorBuilder:
                                  (context, index) => const Divider(
                                    height: 1,
                                    indent: 16,
                                    endIndent: 16,
                                  ),
                              itemBuilder: (context, index) {
                                final book = _filteredBooks[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    width: 40,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.grey[200],
                                      image:
                                          book.coverUrl != null
                                              ? DecorationImage(
                                                image: NetworkImage(
                                                  book.coverUrl!,
                                                ),
                                                fit: BoxFit.cover,
                                              )
                                              : null,
                                    ),
                                    child:
                                        book.coverUrl == null
                                            ? const Icon(
                                              Icons.book,
                                              color: Colors.grey,
                                              size: 20,
                                            )
                                            : null,
                                  ),
                                  title: Text(
                                    book.title,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    book.author ?? 'Unknown Author',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.color,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () => _requestBorrow(book),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      TranslationService.translate(
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
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.5,
            maxChildSize: 0.95,
            expand: false,
            builder:
                (context, scrollController) => SingleChildScrollView(
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
                            image:
                                book.largeCoverUrl != null
                                    ? DecorationImage(
                                      image: NetworkImage(book.largeCoverUrl!),
                                      fit: BoxFit.cover,
                                    )
                                    : null,
                          ),
                          child:
                              book.largeCoverUrl == null
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
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          book.author ?? 'Unknown Author',
                          style: Theme.of(context).textTheme.titleMedium
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
                          style: Theme.of(context).textTheme.titleMedium
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
                          onPressed: () {
                            Navigator.pop(context);
                            _requestBorrow(book);
                          },
                          icon: const Icon(Icons.bookmark_add),
                          label: Text(
                            TranslationService.translate(
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
