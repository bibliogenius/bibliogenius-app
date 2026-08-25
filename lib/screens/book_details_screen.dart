import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../utils/borrowed_copy_payload.dart';
import '../utils/cover_camera_helper.dart';
import '../utils/loan_return_feedback.dart';
import '../utils/returned_book.dart';

import '../audio/audio_module.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../data/repositories/loan_repository.dart';
import '../models/book.dart';
import '../models/collection.dart';
import '../models/contact.dart';
import '../models/loan_recipient.dart';
import '../models/copy.dart';
import '../models/loan.dart';
import '../models/cover_candidate.dart';
import '../models/book_note.dart';
import '../providers/book_note_provider.dart'
    show BookNoteProvider, maxNoteContentLength;
import '../providers/book_refresh_notifier.dart';
import '../providers/favorites_provider.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/favorite_ribbon.dart';
import '../widgets/reading_completion_suggestions.dart';
import '../widgets/book_note_tile.dart';
import '../widgets/book_recommendations_section.dart';
import '../widgets/author_links.dart';
import '../widgets/book_series_discovery_card.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../utils/collection_display.dart';
import '../utils/book_status.dart';
import '../widgets/cached_book_cover.dart';
import '../widgets/series_frieze_widget.dart';
import '../widgets/plus_one_animation.dart';
import '../services/milestone_celebration.dart';
import '../widgets/cover_picker_dialog.dart';
import '../widgets/loan_dialog.dart';
import '../widgets/metadata_refresh_dialog.dart';
import '../widgets/speech_note_button.dart';
import '../widgets/book_rating_row.dart';
import '../widgets/wishlist_availability_card.dart';
import '../widgets/wishlist_seeker_card.dart';
import 'record_sale_screen.dart';

class BookDetailsScreen extends StatefulWidget {
  final Book? book;

  /// Book reference from the route: the uuid for migrated callers, or a legacy
  /// integer local id (as a string) from callers that do not yet carry the
  /// uuid (loans, statistics, peers). [_fetchBookDetails] resolves either form.
  final String bookId;

  const BookDetailsScreen({super.key, this.book, required this.bookId});

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  Book? _book;
  List<Copy> _copies = [];
  List<Collection> _collections = [];

  /// Individual author names the library knows, used to split this book's
  /// flattened `author` string into separately linkable people (ADR-061
  /// section 7, decision A3). Empty until loaded, which simply means the
  /// whole string stays one link.
  Set<String> _authorVocabulary = const {};
  List<Loan> _activeLoans = [];
  Map<String, String?> _loanContactNotes = {};
  bool _isLoadingCopies = true;
  bool _isLoadingBook = false;
  bool _hasChanges = false;

  /// Set on the transition into "read", cleared on leaving the page. Gates
  /// the ADR-062 R5 block, which must answer the MOMENT a book is finished
  /// and never simply sit on every finished book's page.
  bool _justFinishedReading = false;
  int _coverVersion = 0;
  bool _isRefreshing = false;
  // Per-book loan duration
  bool _perBookDurationEnabled = false;
  int? _bookLoanDurationDays;
  int _defaultLoanDurationDays = 21;

  @override
  void initState() {
    super.initState();
    if (widget.book != null) {
      _book = widget.book;
      // _fetchBookDetails already fetches copies — no need for separate _fetchCopies()
      _fetchBookDetails();
    } else {
      _isLoadingBook = true;
      _fetchBookDetails();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAuthorVocabulary());
    // Warm the favorite set so the toggle renders its real state (ADR-064).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FavoritesProvider>().ensureLoaded();
    });
  }

  /// The library's individual author names, memoised provider-side, so this
  /// costs a library pass AND a derivation only on the first surface that
  /// asks after a catalogue mutation (ADR-061 section 4).
  Future<void> _loadAuthorVocabulary() async {
    if (!mounted) return;
    final vocabulary = await context
        .read<RecommendationProvider>()
        .authorVocabulary();
    if (!mounted) return;
    setState(() => _authorVocabulary = vocabulary);
  }

  Future<void> _fetchCopies() async {
    if (!mounted) return;
    final bookUuid = _book?.id;
    if (bookUuid == null) return;
    try {
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      final copies = await copyRepo.getBookCopies(bookUuid);
      if (mounted) {
        setState(() {
          _copies = copies;
          _isLoadingCopies = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching copies: $e');
      if (mounted) setState(() => _isLoadingCopies = false);
    }
  }

  Future<void> _fetchBookDetails({bool forceRefresh = false}) async {
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final copyRepo = Provider.of<CopyRepository>(context, listen: false);
    final collectionRepo = Provider.of<CollectionRepository>(
      context,
      listen: false,
    );
    final loanRepo = Provider.of<LoanRepository>(context, listen: false);
    try {
      // Re-fetch the book to pick up the latest changes (rating, status…). The
      // route addresses it by uuid.
      final bookFuture = bookRepo.getBook(widget.bookId);

      // Book-scoped sub-resources are keyed by the book uuid. When the book was
      // passed via extra (card tap) its uuid is already known, so fan the
      // sub-resources out in parallel with the re-fetch; on a deep link, resolve
      // the book first to learn it.
      final bookUuid = widget.book?.id ?? (await bookFuture).id;

      final copiesFuture = bookUuid != null
          ? copyRepo.getBookCopies(bookUuid)
          : Future<List<Copy>>.value(<Copy>[]);
      final collectionsFuture = bookUuid != null
          ? collectionRepo.getBookCollections(bookUuid)
          : Future<List<Collection>>.value(<Collection>[]);

      // Start loan fetch in parallel — filtered after copies are known
      final loansFuture = loanRepo.getLoans(status: 'active');

      final copies = await copiesFuture;
      final collections = await collectionsFuture;
      final freshBook = await bookFuture;

      // Load loan settings for per-book duration
      try {
        final ffi = FfiService();
        if (ffi.isInitialized) {
          final settings = await ffi.getLoanSettings();
          _perBookDurationEnabled = settings.perBookDurationEnabled;
          _defaultLoanDurationDays = settings.defaultLoanDurationDays;
          if (_perBookDurationEnabled && bookUuid != null) {
            _bookLoanDurationDays = await ffi.getBookLoanDuration(bookUuid);
          }
        }
      } catch (e) {
        debugPrint('Error loading loan settings: $e');
      }

      // Filter active loans to copies belonging to this book
      List<Loan> activeLoans = [];
      try {
        final allActive = await loansFuture;
        final copyIds = copies.map((c) => c.id).whereType<String>().toSet();
        activeLoans = allActive
            .where((l) => copyIds.contains(l.copyId))
            .toList();
      } catch (e) {
        debugPrint('Error fetching active loans: $e');
      }

      // Fetch contact notes for each active loan (shown as subtitle on loan row)
      final contactNotes = <String, String?>{};
      if (activeLoans.isNotEmpty) {
        final contactRepo = Provider.of<ContactRepository>(
          context,
          listen: false,
        );
        await Future.wait(
          activeLoans.map((loan) async {
            try {
              final contact = await contactRepo.getContact(loan.contactId);
              if (contact.notes?.isNotEmpty == true) {
                contactNotes[loan.contactId] = contact.notes;
              }
            } catch (_) {}
          }),
        );
      }

      if (mounted) {
        setState(() {
          _book = freshBook;
          _isLoadingBook = false;
          _copies = copies;
          _collections = collections;
          _isLoadingCopies = false;
          _activeLoans = activeLoans;
          _loanContactNotes = contactNotes;
        });
      }
    } catch (e) {
      debugPrint('Error fetching book details: $e');
      if (mounted) {
        setState(() {
          _isLoadingBook = false;
          _isLoadingCopies = false;
        });
      }
    }
  }
  // ... existing methods ...

  bool get _hasAvailableCopies {
    if (_copies.isEmpty) return false;
    return _copies.any((copy) => copy.status == 'available');
  }

  bool get _hasLentCopies {
    if (_copies.isEmpty) return false;
    return _copies.any((copy) => copy.status == 'loaned');
  }

  bool get _hasBorrowedCopies {
    if (_copies.isEmpty) return false;
    return _copies.any((copy) => copy.status == 'borrowed');
  }

  bool get _deleteBlocked => _hasLentCopies || _hasBorrowedCopies;

  String _deleteDisabledTooltip(BuildContext context) {
    if (_hasLentCopies) {
      return TranslationService.translate(
            context,
            'delete_disabled_lent_tooltip',
          ) ??
          'Mark the loaned copy as returned before deleting.';
    }
    if (_hasBorrowedCopies) {
      return TranslationService.translate(
            context,
            'delete_disabled_borrowed_tooltip',
          ) ??
          'Return the borrowed copy before deleting.';
    }
    return '';
  }

  Future<void> _quickAddCopy() async {
    if (_book == null || _book!.id == null) return;
    final copyRepo = Provider.of<CopyRepository>(context, listen: false);
    try {
      await copyRepo.createCopy({
        'book_id': _book!.id,
        'status': 'available',
        'is_temporary': false,
      });
      await _fetchCopies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _quickRemoveCopy() async {
    if (_copies.length <= 1) return;
    // Remove the last available copy (prefer removing available over loaned/borrowed)
    final target = _copies.lastWhere(
      (c) => c.status == 'available',
      orElse: () => _copies.last,
    );
    if (target.id == null) return;
    final copyRepo = Provider.of<CopyRepository>(context, listen: false);
    try {
      await copyRepo.deleteCopy(target.id!);
      await _fetchCopies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateRating(int? newRating) async {
    if (_book == null || _book!.id == null) return;
    final previousRating = _book!.userRating;
    // Optimistic UI update
    setState(() {
      _book = _book!.copyWithRating(newRating);
    });
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      await bookRepo.updateBook(_book!.id!, {
        'title': _book!.title,
        'user_rating': newRating,
      });
    } catch (e) {
      // Revert on error
      if (mounted) {
        setState(() {
          _book = _book!.copyWithRating(previousRating);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_updating_rating')}: $e',
            ),
          ),
        );
      }
    }
  }

  // ============ Navigation ============

  /// Shared back-navigation logic: notify library of changes and pop.
  void _navigateBack() {
    if (_hasChanges) {
      // Evict the current cover from Flutter's image cache so the library
      // reloads the (possibly overwritten) file instead of showing a stale
      // cached bitmap.
      _evictCoverFromCache(_book?.coverUrl);
      context.read<BookRefreshNotifier>().refresh();
    }
    Navigator.of(context).pop(_hasChanges);
  }

  // ============ Cover management ============

  /// Evict old cover image from Flutter's image cache so it doesn't persist
  void _evictCoverFromCache(String? coverUrl) {
    if (coverUrl == null || coverUrl.isEmpty) return;
    if (coverUrl.startsWith('http')) {
      // Network image: evict from disk cache and in-memory image cache
      BookCoverCacheManager.instance.removeFile(coverUrl);
      imageCache.evict(
        CachedNetworkImageProvider(
          coverUrl,
          cacheManager: BookCoverCacheManager.instance,
        ),
      );
    } else {
      // Local file: evict from Flutter's image cache
      final fileImage = FileImage(File(coverUrl));
      imageCache.evict(fileImage);
    }
  }

  void _showCoverOptions(BuildContext context, Book book) {
    final bool hasCover = book.hasPersistedCover;
    final bool hasIsbn = book.isbn != null && book.isbn!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              TranslationService.translate(
                    context,
                    hasCover ? 'cover_change' : 'cover_add',
                  ) ??
                  (hasCover ? 'Change cover' : 'Add a cover'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (hasIsbn)
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(
                  TranslationService.translate(
                        context,
                        'cover_search_online',
                      ) ??
                      'Search online',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _searchCoverOnline(book);
                },
              )
            else
              ListTile(
                leading: Icon(Icons.search, color: Colors.grey[400]),
                title: Text(
                  TranslationService.translate(context, 'cover_no_isbn') ??
                      'Add an ISBN to search online',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              ),
            if (CoverCameraHelper.isCameraAvailable)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: Text(
                  TranslationService.translate(context, 'cover_take_photo') ??
                      'Take a photo',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _takeCoverPhoto(book);
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(
                TranslationService.translate(context, 'cover_choose_file') ??
                    'Choose from files',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickCoverFromFile(book);
              },
            ),
            if (hasCover)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  TranslationService.translate(context, 'cover_remove') ??
                      'Remove cover',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeCover(book);
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _searchCoverOnline(Book book) async {
    if (book.id == null || !mounted) return;

    final apiService = Provider.of<ApiService>(context, listen: false);
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);

    // Pre-capture translated strings before async gaps
    final searchingText =
        TranslationService.translate(context, 'cover_searching') ??
        'Searching for cover...';
    final searchingByTitleText =
        TranslationService.translate(context, 'cover_searching_by_title') ??
        'Searching by title...';
    final notFoundText =
        TranslationService.translate(context, 'cover_not_found') ??
        'No cover found';
    final foundText =
        TranslationService.translate(context, 'cover_found') ?? 'Cover found!';
    final updatedText =
        TranslationService.translate(context, 'cover_updated') ??
        'Cover updated';

    // Show searching snackbar
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(searchingText),
          ],
        ),
        duration: const Duration(seconds: 20),
      ),
    );

    try {
      List<CoverCandidate> candidates = [];

      // Step 1: ISBN-based parallel search (all sources at once)
      if (book.isbn != null && book.isbn!.isNotEmpty) {
        candidates = await apiService.searchAllCoversForBook(book.isbn!);
      }

      if (!mounted) return;

      final isbnResultCount = candidates.length;

      // Step 2: If ISBN gave < 2 results, also try title search
      if (candidates.length < 2) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(searchingByTitleText),
              ],
            ),
            duration: const Duration(seconds: 15),
          ),
        );

        bool googleBooksEnabled = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          final fallbackStr = prefs.getString('ffi_fallback_preferences');
          if (fallbackStr != null) {
            final fallbackPrefs =
                jsonDecode(fallbackStr) as Map<String, dynamic>;
            if (fallbackPrefs.containsKey('google_books')) {
              googleBooksEnabled = fallbackPrefs['google_books'] == true;
            }
          }
        } catch (_) {}

        final titleCandidates = await apiService.searchAllCoversByTitle(
          book.title,
          book.author,
          enableGoogle: googleBooksEnabled,
        );

        if (!mounted) return;

        // Merge: add title candidates not already found by ISBN
        final existingUrls = candidates.map((c) => c.url).toSet();
        for (final tc in titleCandidates) {
          if (!existingUrls.contains(tc.url)) {
            candidates.add(tc);
          }
        }
      }

      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      if (candidates.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(notFoundText)));
        return;
      }

      // Single result from ISBN search: auto-apply (high confidence)
      // Only auto-apply if the result came from the ISBN search itself,
      // not from the title fallback (lower confidence).
      if (candidates.length == 1 && isbnResultCount == 1) {
        final newUrl = candidates.first.url;
        _evictCoverFromCache(_book?.coverUrl);
        await bookRepo.updateBook(book.id!, {'cover_url': newUrl});
        _hasChanges = true;
        if (mounted) {
          context.read<HubDirectoryProvider>()
            ..markCatalogDirty()
            ..syncCatalogIfDirty();
          setState(() {
            _book = _book!.copyWithCoverUrl(newUrl);
            _coverVersion++;
          });
        }
        _fetchBookDetails(forceRefresh: true);
        messenger.showSnackBar(SnackBar(content: Text(foundText)));
        return;
      }

      // Multiple results: show carousel picker
      final selectedUrl = await CoverPickerDialog.show(
        context: context,
        candidates: candidates,
        bookTitle: book.title,
      );

      if (!mounted) return;
      if (selectedUrl != null) {
        _evictCoverFromCache(_book?.coverUrl);
        await bookRepo.updateBook(book.id!, {'cover_url': selectedUrl});
        _hasChanges = true;
        if (mounted) {
          context.read<HubDirectoryProvider>()
            ..markCatalogDirty()
            ..syncCatalogIfDirty();
          setState(() {
            _book = _book!.copyWithCoverUrl(selectedUrl);
            _coverVersion++;
          });
        }
        _fetchBookDetails(forceRefresh: true);
        messenger.showSnackBar(SnackBar(content: Text(updatedText)));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _takeCoverPhoto(Book book) async {
    if (book.id == null) return;

    try {
      final path = await CoverCameraHelper.takePhotoAndSave(bookId: book.id);
      if (path == null || !mounted) return;

      _evictCoverFromCache(_book?.coverUrl);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      await bookRepo.updateBook(book.id!, {'cover_url': path});
      _hasChanges = true;
      if (mounted) {
        context.read<HubDirectoryProvider>()
          ..markCatalogDirty()
          ..syncCatalogIfDirty();
        setState(() {
          _book = _book!.copyWithCoverUrl(path);
          _coverVersion++;
        });
      }
      _fetchBookDetails(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'cover_photo_saved') ??
                  'Cover photo saved',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[COVER-PHOTO-ERROR] details._takeCoverPhoto: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'cover_photo_error') ??
                'Could not take photo',
          ),
        ),
      );
    }
  }

  Future<void> _pickCoverFromFile(Book book) async {
    if (book.id == null) return;

    try {
      final targetPath = await CoverCameraHelper.pickFromGalleryAndSave(
        bookId: book.id,
      );
      if (targetPath == null) return;

      if (!mounted) return;
      _evictCoverFromCache(_book?.coverUrl);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      await bookRepo.updateBook(book.id!, {'cover_url': targetPath});
      _hasChanges = true;
      if (mounted) {
        context.read<HubDirectoryProvider>()
          ..markCatalogDirty()
          ..syncCatalogIfDirty();
        setState(() {
          _book = _book!.copyWithCoverUrl(targetPath);
          _coverVersion++;
        });
      }
      _fetchBookDetails(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'cover_updated') ??
                  'Cover updated',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _removeCover(Book book) async {
    if (book.id == null) return;

    try {
      // Delete local file if applicable
      if (book.hasPersistedCover &&
          book.coverUrl != null &&
          !book.coverUrl!.startsWith('http')) {
        final file = File(book.coverUrl!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Evict from network cache if applicable
      if (book.hasPersistedCover &&
          book.coverUrl != null &&
          book.coverUrl!.startsWith('http')) {
        await BookCoverCacheManager.instance.removeFile(book.coverUrl!);
      }

      if (!mounted) return;
      _evictCoverFromCache(_book?.coverUrl);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      await bookRepo.updateBook(book.id!, {'cover_url': null});
      _hasChanges = true;
      if (mounted) {
        context.read<HubDirectoryProvider>()
          ..markCatalogDirty()
          ..syncCatalogIfDirty();
        setState(() {
          _book = _book!.copyWithCoverUrl(null);
          _coverVersion++;
        });
      }
      _fetchBookDetails(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'cover_removed') ??
                  'Cover removed',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Guaranteed non-null here
    final book = _book!;

    // Use large cover URL if available, otherwise fallback
    final coverUrl = book.largeCoverUrl ?? book.coverUrl;

    return WillPopScope(
      onWillPop: () async {
        _navigateBack();
        return false;
      },
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, book, coverUrl),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, book),
                    _buildTaxonomyRow(context, book),
                    const SizedBox(height: 24),
                    _buildActionButtons(context, book),
                    const SizedBox(height: 32),
                    // The "just finished" moment (ADR-062 R5): the page's
                    // own "You might also like" section, PROMOTED here and
                    // reframed, not a second block. Placed under the control
                    // the reader just used, because down at its usual spot
                    // it repeats the failure of the toast link it replaces,
                    // present but unseen.
                    if (_justFinishedReading)
                      ReadingCompletionSuggestions(
                        key: ValueKey('continue-with-${book.id}'),
                        book: book,
                      ),
                    // "Available from" card for wanted books. Renders nothing
                    // when the shared wishlist join returns no provider.
                    if (book.readingStatus == 'wanting')
                      WishlistAvailabilityCard(
                        key: ValueKey('wishlist-availability-${book.isbn}'),
                        book: book,
                      ),
                    // Inverse direction, for owned books: who wants this
                    // one? Renders nothing when no peer broadcast a wish.
                    if (book.owned)
                      WishlistSeekerCard(
                        key: ValueKey('wishlist-seekers-${book.isbn}'),
                        book: book,
                      ),
                    _buildMetadataGrid(context, book),
                    const SizedBox(height: 16),
                    // Series frieze(s): one ordered reading-order timeline per
                    // series-typed collection this book belongs to. Non-series
                    // books produce an empty loop here, so no extra render cost.
                    for (final series in _collections.where((c) => c.isSeries))
                      SeriesFriezeWidget(
                        collection: series,
                        currentBookId: book.id ?? '',
                      ),
                    // "Complete the series" (ADR-061): the lowest missing
                    // ordinal, in the series context the frieze just set,
                    // rather than orphaned at the bottom of the page under a
                    // carousel that answers a different question. Renders
                    // nothing outside a series, or on a cold discovery cache.
                    BookSeriesDiscoveryCard(
                      key: ValueKey('series-discovery-${book.id}'),
                      seriesCollectionIds: [
                        for (final series in _collections.where(
                          (c) => c.isSeries,
                        ))
                          series.id,
                      ],
                    ),
                    // Audio module section (decoupled - only shows if enabled)
                    if (book.id != null)
                      AudioSection(
                        bookId: book.id!,
                        bookTitle: book.title,
                        bookAuthor: book.author,
                        bookLanguage: book.language,
                        userLanguages: context
                            .read<ThemeProvider>()
                            .userLanguages,
                      ),
                    const SizedBox(height: 32),
                    if (book.summary != null && book.summary!.isNotEmpty) ...[
                      Semantics(
                        header: true,
                        child: Text(
                          TranslationService.translate(
                                context,
                                'book_summary',
                              ) ??
                              'Summary',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        book.summary!,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                    // Reading notes section
                    if (book.id != null)
                      _BookNotesSection(
                        bookId: book.id!,
                        bookTitle: book.title,
                      ),
                    // Private book toggle - at the bottom of the page
                    Consumer<ThemeProvider>(
                      builder: (context, theme, _) {
                        if (!theme.allowPrivateBooks)
                          return const SizedBox.shrink();
                        return Card(
                          child: SwitchListTile(
                            secondary: Icon(
                              book.private
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: book.private
                                  ? Theme.of(context).colorScheme.error
                                  : null,
                            ),
                            title: Text(
                              TranslationService.translate(
                                context,
                                'book_private',
                              ),
                            ),
                            subtitle: Text(
                              TranslationService.translate(
                                context,
                                'book_private_desc',
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            value: book.private,
                            onChanged: (value) => _togglePrivate(value),
                          ),
                        );
                      },
                    ),
                    // "You might also like" closes the page: local-library
                    // books similar to this one (ADR-059). Lazy,
                    // non-blocking, renders nothing below 2 suggestions.
                    // Suppressed while promoted to the top of the page by
                    // the just-finished moment: one place or the other,
                    // never both (ADR-062 R5).
                    if (book.id != null && !_justFinishedReading) ...[
                      const SizedBox(height: 32),
                      BookRecommendationsSection(
                        key: ValueKey('recommendations-${book.id}'),
                        book: book,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _generateRandomColor(String seed) {
    final hash = seed.hashCode;
    final colors = [
      Colors.blue.shade800,
      Colors.red.shade800,
      Colors.green.shade800,
      Colors.purple.shade800,
      Colors.orange.shade800,
      Colors.teal.shade800,
      Colors.indigo.shade800,
      Colors.brown.shade800,
    ];
    return colors[hash.abs() % colors.length];
  }

  Widget _buildCoverUploadWarningBadge(BuildContext context) {
    final label = TranslationService.translate(
      context,
      'cover_upload_pending_tooltip',
    );
    return Positioned(
      top: 8,
      right: 8,
      child: Semantics(
        label: label,
        child: Tooltip(
          message: label,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackCover(Book book) {
    final color = _generateRandomColor(
      book.title + (book.id?.toString() ?? ''),
    );

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: color,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.6)],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  offset: Offset(0, 1),
                  blurRadius: 2,
                ),
              ],
            ),
          ),
          if (book.author != null) ...[
            const SizedBox(height: 4),
            Text(
              book.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Icon(
            Icons.auto_stories,
            color: Colors.white.withValues(alpha: 0.2),
            size: 32,
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, Book book, String? coverUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SliverAppBar(
      expandedHeight: 400.0,
      pinned: true,
      stretch: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isDark ? Colors.black45 : Colors.black26,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
        tooltip: TranslationService.translate(context, 'back'),
        onPressed: _navigateBack,
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: ExcludeSemantics(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Layer 0: Fallback (always rendered at bottom)
              _buildFallbackCover(book),

              // Layer 1: Network Image (if available)
              if (coverUrl != null && coverUrl.isNotEmpty)
                CachedBookCover(
                  key: ValueKey('bg_$_coverVersion'),
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                  placeholder: const SizedBox.shrink(),
                  errorWidget: const SizedBox.shrink(),
                  semanticLabel: book.title,
                ),

              // Layer 2: Blur Effect (applied on top of fallback or image)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: Colors.black.withValues(alpha: 0.4)),
              ),

              // Hero Image — tap to add/change cover
              Center(
                child: GestureDetector(
                  onTap: () => _showCoverOptions(context, book),
                  child: Hero(
                    tag: 'book_cover_${book.id}',
                    child: SizedBox(
                      width: 200,
                      height: 300,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 200,
                            height: 300,
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                              borderRadius: BorderRadius.circular(
                                8,
                              ), // Book-like rounded corners
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Fallback always at bottom
                                  _buildFallbackCover(book),
                                  // Image on top
                                  if (coverUrl != null && coverUrl.isNotEmpty)
                                    CachedBookCover(
                                      key: ValueKey('hero_$_coverVersion'),
                                      imageUrl: coverUrl,
                                      fit: BoxFit.cover,
                                      placeholder: const SizedBox.shrink(),
                                      errorWidget: const SizedBox.shrink(),
                                      semanticLabel: book.title,
                                    ),
                                ],
                              ),
                            ),
                          ),
                          // Owner-only badge: surfaces a pending hub cover upload
                          // failure so the user knows peers may still see the
                          // stale / fallback cover until the next sync retries.
                          if (book.hubCoverUploadFailedAt != null)
                            _buildCoverUploadWarningBadge(context),
                        ],
                      ),
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

  Widget _buildHeader(BuildContext context, Book book) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            book.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
        ),
        if (book.author != null) ...[
          const SizedBox(height: 8),
          // Each author name routes to its own page (ADR-061). The
          // vocabulary decides whether the comma in this string separates
          // two people or belongs to one inverted name.
          AuthorLinks(
            flattenedAuthor: book.author!,
            vocabulary: _authorVocabulary,
          ),
        ],
      ],
    );
  }

  /// Compact "at a glance" row under the author: reading status followed by the
  /// book's shelves and collections as small pills. This surfaces the same data
  /// that used to live in three separate labelled sections lower down, so the
  /// page reads faster without duplicating information.
  Widget _buildTaxonomyRow(BuildContext context, Book book) {
    const shelfColors = [
      Colors.blue,
      Colors.teal,
      Colors.purple,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
    ];
    const collectionColors = [
      Colors.amber,
      Colors.deepPurple,
      Colors.cyan,
      Colors.red,
      Colors.green,
      Colors.brown,
    ];
    // Keep the header light: only a handful of taxonomy pills, the rest folds
    // into a "+N" indicator (the full list stays editable from the edit screen).
    const maxTaxonomyPills = 6;

    final subjects = book.subjects ?? const <String>[];
    final chips = <Widget>[_buildStatusChip(context, book)];
    var shown = 0;

    for (var i = 0; i < subjects.length && shown < maxTaxonomyPills; i++) {
      final subject = subjects[i];
      final color = shelfColors[i % shelfColors.length];
      chips.add(
        _taxonomyPill(
          icon: Icons.tag,
          label: subject,
          color: color,
          onTap: () => context.go(
            Uri(path: '/books', queryParameters: {'tag': subject}).toString(),
          ),
        ),
      );
      shown++;
    }

    for (var i = 0; i < _collections.length && shown < maxTaxonomyPills; i++) {
      final collection = _collections[i];
      final color = collectionColors[i % collectionColors.length];
      chips.add(
        _taxonomyPill(
          icon: Icons.collections_bookmark_outlined,
          label: collectionDisplayName(context, collection),
          color: color,
          onTap: () =>
              context.push('/collections/${collection.id}', extra: collection),
        ),
      );
      shown++;
    }

    final remaining = subjects.length + _collections.length - shown;
    if (remaining > 0) {
      chips.add(
        _taxonomyPill(
          icon: Icons.more_horiz,
          label: '+$remaining',
          color: Colors.blueGrey,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }

  /// Small rounded pill used by [_buildTaxonomyRow] for shelves and collections.
  Widget _taxonomyPill({
    required IconData icon,
    required String label,
    required MaterialColor color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoanStatusSection(BuildContext context) {
    if (_activeLoans.isEmpty) return const SizedBox.shrink();

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final canBorrow = themeProvider.canBorrowBooks;
    final canLend = themeProvider.canLendBooks;

    final rows = <Widget>[];
    for (final loan in _activeLoans) {
      final copyIndex = _copies.indexWhere((c) => c.id == loan.copyId);
      if (copyIndex == -1) continue;
      final copy = _copies[copyIndex];
      final isOutgoing = copy.status == 'loaned';
      // Hide outgoing rows when lending is off, incoming rows when borrowing is off
      if (isOutgoing && !canLend) continue;
      if (!isOutgoing && !canBorrow) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(
        _buildLoanRow(
          context,
          loan,
          isOutgoing: isOutgoing,
          copyNumber: _copies.length > 1 ? copyIndex + 1 : null,
          notes: _loanContactNotes[loan.contactId],
        ),
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [const SizedBox(height: 12), ...rows],
    );
  }

  Widget _buildLoanRow(
    BuildContext context,
    Loan loan, {
    required bool isOutgoing,
    int? copyNumber,
    String? notes,
  }) {
    final cs = Theme.of(context).colorScheme;
    final dueDate = DateTime.tryParse(loan.dueDate);
    final daysLeft = dueDate?.difference(DateTime.now()).inDays;
    final isOverdue = daysLeft != null && daysLeft < 0;
    final accentColor = isOutgoing ? const Color(0xFFE67E22) : cs.tertiary;
    final dateColor = _loanDateColor(daysLeft, cs);

    final directionLabel = isOutgoing
        ? TranslationService.translate(context, 'lent_to') ?? 'Lent to'
        : TranslationService.translate(context, 'borrowed_from') ??
              'Borrowed from';

    final copyPrefix = copyNumber != null
        ? '${TranslationService.translate(context, 'copy_number') ?? 'Copy #'}$copyNumber · '
        : '';
    final titleText = '$copyPrefix$directionLabel ${loan.contactName}';

    final dateLabel =
        TranslationService.translate(context, 'due_date_label') ?? 'Due date';
    final dateText = dueDate != null
        ? '$dateLabel : ${_formatLoanDate(context, dueDate)}'
        : '';
    final overdueLabel =
        TranslationService.translate(context, 'loan_overdue') ?? 'Overdue';
    final semanticsLabel =
        '$titleText${notes != null ? '. $notes' : ''}. $dateText'
        '${isOverdue ? '. $overdueLabel' : ''}';

    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(
              isOutgoing ? Icons.arrow_outward : Icons.arrow_downward,
              size: 16,
              color: accentColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (notes != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      notes,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (dateText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.event_outlined, size: 13, color: dateColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            dateText,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: dateColor),
                          ),
                        ),
                        if (isOverdue) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cs.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: cs.error.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              overdueLabel,
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(color: cs.error),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Color _loanDateColor(int? daysLeft, ColorScheme cs) {
    if (daysLeft == null) return cs.onSurfaceVariant;
    if (daysLeft <= 3) return cs.error;
    if (daysLeft <= 7) return const Color(0xFFE67E22);
    return const Color(0xFF27AE60);
  }

  String _formatLoanDate(BuildContext context, DateTime date) {
    try {
      final locale = Localizations.localeOf(context).toString();
      return DateFormat.yMMMd(locale).format(date);
    } catch (_) {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildActionButtons(BuildContext context, Book book) {
    final isReading = book.readingStatus == 'reading';
    final isToRead =
        book.readingStatus == 'to_read' || book.readingStatus == null;
    final loanModules = Provider.of<ThemeProvider>(context, listen: false);
    final canLend = loanModules.canLendBooks;
    final canBorrow = loanModules.canBorrowBooks;

    return Column(
      children: [
        // --- Primary loan / borrow CTAs (filled, at the top) ---
        // Each state keeps its own accent color so the current action reads at
        // a glance; the four states can stack when a title has mixed copies.
        // Lend book button - available copies, owned, lending module enabled.
        if (_hasAvailableCopies && book.owned && canLend) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _lendBook(context),
              icon: const Icon(Icons.handshake_outlined),
              label: Text(
                TranslationService.translate(context, 'lend_book_btn') ??
                    'Lend this book',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        // Return lent book button - lent copies + lending module enabled.
        if (_hasLentCopies && canLend) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _returnBook(context),
              icon: const Icon(Icons.assignment_return_outlined),
              label: Text(
                TranslationService.translate(context, 'return_book_btn') ??
                    'Return this book',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        // Borrow from a contact - not owned, no borrowed copy yet, module on.
        if (!book.owned && !_hasBorrowedCopies && canBorrow) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _borrowBook(context),
              icon: const Icon(Icons.arrow_downward),
              label: Text(
                TranslationService.translate(
                      context,
                      'borrow_from_contact_btn',
                    ) ??
                    'Borrow from a contact',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        if (_hasBorrowedCopies) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _giveBackBook(context),
              icon: const Icon(Icons.keyboard_return_outlined),
              label: Text(
                TranslationService.translate(context, 'give_back_book_btn'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        // Sell book button - only visible if bookseller profile
        if (Provider.of<ThemeProvider>(context).isBookseller &&
            _hasAvailableCopies &&
            book.owned) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _sellBook(context),
              icon: const Icon(Icons.sell_outlined),
              label: Text(
                TranslationService.translate(context, 'sell_book_btn'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        // --- Favorite + Edit + Copies (secondary, outlined) ---
        const SizedBox(height: 12),
        Row(
          children: [
            if (book.id != null) ...[
              _buildFavoriteToggle(context, book),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Tooltip(
                message:
                    TranslationService.translate(context, 'menu_edit') ??
                    'Edit Book',
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (_book == null) return;
                    final result = await context.push(
                      '/books/${_book!.id}/edit',
                      extra: _book,
                    );
                    if (result == true && context.mounted) {
                      // Evict old cover so refreshed data shows new image
                      _evictCoverFromCache(_book?.coverUrl);
                      // Refresh book data but STAY on the screen
                      await _fetchBookDetails(forceRefresh: true);
                      // Mark that we have changes so we can return true later
                      setState(() {
                        _hasChanges = true;
                        _coverVersion++;
                      });
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(
                    TranslationService.translate(context, 'menu_edit') ??
                        'Edit',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  key: const Key('editBookButton'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Tooltip(
                message:
                    TranslationService.translate(
                      context,
                      'menu_manage_copies',
                    ) ??
                    'Manage Copies',
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (_book == null) return;
                    await context.push(
                      '/books/${_book!.id}/copies',
                      extra: {'bookTitle': _book!.title},
                    );
                    if (!mounted) return;
                    await _fetchCopies();
                  },
                  icon: Badge(
                    label: Text('${_copies.length}'),
                    isLabelVisible: _copies.length > 1,
                    child: const Icon(Icons.library_books_outlined, size: 18),
                  ),
                  label: Text(
                    TranslationService.translate(
                          context,
                          'menu_copies_short',
                        ) ??
                        'Copies',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  key: const Key('manageCopiesButton'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (book.isbn != null) ...[
              TextButton.icon(
                onPressed: _isRefreshing
                    ? null
                    : () => _refreshMetadata(context),
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_outlined, size: 15),
                label: Text(
                  TranslationService.translate(
                        context,
                        'refresh_metadata_title',
                      ) ??
                      'Update',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                  textStyle: Theme.of(context).textTheme.labelSmall,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                key: const Key('refreshMetadataButton'),
              ),
              const SizedBox(width: 4),
            ],
            Tooltip(
              message: _deleteBlocked ? _deleteDisabledTooltip(context) : '',
              child: TextButton.icon(
                onPressed: _deleteBlocked
                    ? null
                    : () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline, size: 15),
                label: Text(
                  TranslationService.translate(context, 'menu_delete') ??
                      'Delete',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.deepOrange,
                  textStyle: Theme.of(context).textTheme.labelSmall,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                key: const Key('deleteBookButton'),
              ),
            ),
          ],
        ),
        if (_copies.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Tooltip(
                  message:
                      TranslationService.translate(
                        context,
                        'delete_copy_title',
                      ) ??
                      'Remove Copy',
                  child: IconButton.outlined(
                    onPressed: _quickRemoveCopy,
                    icon: const Icon(Icons.remove, size: 16),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '${_copies.length} ${(TranslationService.translate(context, 'menu_copies_short') ?? 'copies').toLowerCase()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: Tooltip(
                  message:
                      TranslationService.translate(context, 'add_copy_title') ??
                      'Add Copy',
                  child: IconButton.outlined(
                    onPressed: _quickAddCopy,
                    icon: const Icon(Icons.add, size: 16),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
        _buildLoanStatusSection(context),
        // Per-book loan duration - only visible when per-book customization is enabled
        if (_perBookDurationEnabled && book.owned) ...[
          const SizedBox(height: 12),
          _buildPerBookLoanDuration(context),
        ],
      ],
    );
  }

  /// The favorite toggle (ADR-064): a square outlined control carrying the
  /// star-bookmark glyph, outline when off, filled when on. The glyph is
  /// the marker's own drawing so the vocabulary stays strict (star
  /// bookmark = favorite, heart = wished).
  Widget _buildFavoriteToggle(BuildContext context, Book book) {
    return Selector<FavoritesProvider, bool>(
      selector: (_, favorites) => favorites.isFavorite(book.id),
      builder: (context, isFavorite, _) {
        final label = TranslationService.translate(
          context,
          isFavorite ? 'favorite_toggle_remove' : 'favorite_toggle_add',
        );
        return Semantics(
          button: true,
          label: label,
          child: Tooltip(
            message: label,
            excludeFromSemantics: true,
            child: OutlinedButton(
              key: const Key('favoriteToggleButton'),
              onPressed: () => _toggleFavorite(book),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: EdgeInsets.zero,
                side: BorderSide(
                  color: isFavorite
                      ? favoriteRibbonTeal
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: FavoriteRibbonIcon(active: isFavorite, size: 26),
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleFavorite(Book book) async {
    final bookId = book.id;
    if (bookId == null) return;
    final favorites = context.read<FavoritesProvider>();

    try {
      // One-shot adoption (ADR-064): before the first marking creates the
      // typed collection, offer to adopt a pre-existing manual "favorites"
      // collection. Declining is remembered; the question never returns.
      if (!favorites.isFavorite(bookId)) {
        final candidate = await favorites.adoptionCandidate();
        if (candidate != null && mounted) {
          final adopt = await _showFavoritesAdoptionDialog(candidate);
          if (adopt == true) {
            await favorites.adopt(candidate);
          } else {
            await favorites.declineAdoption();
          }
          // The adopted collection may already contain this book: only
          // toggle when it is still unmarked.
          if (favorites.isFavorite(bookId)) {
            if (mounted) {
              AppSnackBar.success(
                context,
                TranslationService.translate(context, 'favorite_added'),
              );
            }
            return;
          }
        }
      }

      final isNowFavorite = await favorites.toggle(bookId);
      if (!mounted) return;
      AppSnackBar.success(
        context,
        TranslationService.translate(
          context,
          isNowFavorite ? 'favorite_added' : 'favorite_removed',
        ),
      );
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      if (!mounted) return;
      AppSnackBar.error(
        context,
        TranslationService.translate(context, 'favorite_toggle_error'),
      );
    }
  }

  Future<bool?> _showFavoritesAdoptionDialog(Collection candidate) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          TranslationService.translate(
            dialogContext,
            'favorites_adopt_title',
          ),
        ),
        content: Text(
          TranslationService.translate(
            dialogContext,
            'favorites_adopt_body',
            params: {
              // Display-name mapping: a recovered sentinel-named candidate
              // must read "Favoris", never its technical name.
              'name': collectionDisplayName(dialogContext, candidate),
              'count': '${candidate.totalBooks}',
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              TranslationService.translate(
                dialogContext,
                'favorites_adopt_decline',
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              TranslationService.translate(
                dialogContext,
                'favorites_adopt_accept',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePrivate(bool value) async {
    if (_book == null || _book!.id == null) return;
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      await bookRepo.updateBook(_book!.id!, {
        'title': _book!.title,
        'private': value,
      });
      _hasChanges = true;
      await _fetchBookDetails(forceRefresh: true);
    } catch (e) {
      debugPrint('Error toggling private: $e');
    }
  }

  Future<void> _sellBook(BuildContext context) async {
    // Check copies
    final availableCopies = _copies
        .where((c) => c.status == 'available')
        .toList();
    if (availableCopies.isEmpty) return;

    Copy selectedCopy;
    if (availableCopies.length == 1) {
      selectedCopy = availableCopies.first;
    } else {
      // Show dialog to pick copy
      final picked = await showDialog<Copy>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(TranslationService.translate(context, 'select_copy')),
          children: availableCopies
              .map(
                (c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text(
                    '${TranslationService.translate(context, 'copy_label')} #${c.id}',
                  ),
                ),
              )
              .toList(),
        ),
      );
      if (picked == null) return;
      selectedCopy = picked;
    }

    final copy = selectedCopy;

    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordSaleScreen(copy: copy, book: _book),
      ),
    );

    if (result == true) {
      _fetchCopies();
    }
  }

  Widget _buildMetadataGrid(BuildContext context, Book book) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildMetadataItem(
                context,
                TranslationService.translate(context, 'year_label'),
                book.publicationYear?.toString() ?? '-',
              ),
              _buildMetadataItem(
                context,
                TranslationService.translate(context, 'publisher_label'),
                book.publisher ?? '-',
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              _buildMetadataItem(context, 'ISBN', book.isbn ?? '-'),
              // Reading status now lives in the taxonomy row under the author.
              const Expanded(child: SizedBox()),
            ],
          ),
          // Rating section
          const Divider(height: 32),
          BookRatingRow(
            rating: book.userRating,
            pageCount: book.pageCount,
            onRatingChanged: _updateRating,
          ),
          if (Provider.of<ThemeProvider>(context).isBookseller) ...[
            () {
              // Get all copy prices that are set and greater than zero
              final copyPrices = _copies
                  .where((c) => c.price != null && c.price! > 0)
                  .map((c) => c.price!)
                  .toList();

              String? priceString;
              final currency = Provider.of<ThemeProvider>(context).currency;

              if (copyPrices.isEmpty) {
                // No copy has a non-zero price set
                // Show book price only if it's set and greater than zero
                if (book.price != null && book.price! > 0) {
                  priceString = '${book.price!.toStringAsFixed(2)} $currency';
                }
              } else {
                // At least one copy has a valid price > 0
                final uniquePrices = copyPrices.toSet().toList();
                uniquePrices.sort();
                if (uniquePrices.length == 1) {
                  priceString =
                      '${uniquePrices.first.toStringAsFixed(2)} $currency';
                } else {
                  priceString =
                      '${uniquePrices.first.toStringAsFixed(2)} - ${uniquePrices.last.toStringAsFixed(2)} $currency';
                }
              }

              if (priceString == null) return const SizedBox.shrink();

              return Column(
                children: [
                  const Divider(height: 32),
                  Row(
                    children: [
                      _buildMetadataItem(
                        context,
                        TranslationService.translate(context, 'price'),
                        priceString,
                      ),
                    ],
                  ),
                ],
              );
            }(),
          ],
          if ((book.readingStatus == 'reading' ||
                  book.readingStatus == 'read') &&
              book.startedReadingAt != null) ...[
            const Divider(height: 32),
            Row(
              children: [
                _buildMetadataItem(
                  context,
                  TranslationService.translate(context, 'started_on') ??
                      'Started',
                  _formatDate(book.startedReadingAt!),
                ),
              ],
            ),
          ],
          if (book.readingStatus == 'read' &&
              book.finishedReadingAt != null) ...[
            const Divider(height: 32),
            Row(
              children: [
                _buildMetadataItem(
                  context,
                  TranslationService.translate(context, 'finished_on') ??
                      'Finished',
                  _formatDate(book.finishedReadingAt!),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(BuildContext context, Book book) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final statusObj = getStatusFromValue(
      context,
      book.readingStatus ?? '',
      themeProvider.inventoryStatusesEnabled,
    );
    final color = statusObj?.color ?? Colors.grey;
    final icon = statusObj?.icon ?? Icons.help_outline;
    final label =
        statusObj?.label ?? _translateStatus(context, book.readingStatus);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showStatusPicker(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 18, color: color),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showStatusPicker(BuildContext context) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final useInventoryStatuses = themeProvider.inventoryStatusesEnabled;
    final statusOptions = getStatusOptions(context, useInventoryStatuses);
    final currentStatus = _book?.readingStatus ?? '';

    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                TranslationService.translate(context, 'status_label') ??
                    'Status',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...statusOptions.map((status) {
              final isSelected = status.value == currentStatus;
              return ListTile(
                leading: Icon(status.icon, color: status.color),
                title: Text(
                  status.label,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle, color: status.color)
                    : null,
                onTap: () => Navigator.pop(ctx, status.value),
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selected == null || !context.mounted || selected == currentStatus)
      return;

    // Statuses that need a date picker
    if (selected == 'reading' || selected == 'read') {
      final title = selected == 'reading'
          ? TranslationService.translate(context, 'start_reading') ??
                'Start Reading'
          : TranslationService.translate(context, 'mark_as_read') ??
                'Mark as Read';
      await _showStatusChangeOptions(
        context,
        selected,
        title,
        stayOnScreen: true,
      );
    } else {
      await _updateStatusDirectly(context, selected);
    }
  }

  Future<void> _updateStatusDirectly(
    BuildContext context,
    String newStatus,
  ) async {
    if (_book == null || _book!.id == null) return;
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      await bookRepo.updateBook(_book!.id!, {
        'title': _book!.title,
        'reading_status': newStatus,
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'status_updated') ??
                  'Status updated',
            ),
          ),
        );
        await _fetchBookDetails(forceRefresh: true);
        _hasChanges = true;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_updating_status')}: $e',
            ),
          ),
        );
      }
    }
  }

  String _translateStatus(BuildContext context, String? status) {
    if (status == 'read')
      return TranslationService.translate(context, 'reading_status_read') ??
          'Read';
    if (status == 'reading')
      return TranslationService.translate(context, 'reading_status_reading') ??
          'Reading';
    if (status == 'to_read')
      return TranslationService.translate(context, 'reading_status_to_read') ??
          'To Read';
    if (status == 'wanting')
      return TranslationService.translate(context, 'reading_status_wanting') ??
          'Wanted';
    if (status == 'owned')
      return TranslationService.translate(context, 'owned_status') ??
          'In Collection';
    if (status == 'loaned')
      return TranslationService.translate(context, 'availability_loaned') ??
          'Loaned';
    if (status == 'borrowed')
      return TranslationService.translate(context, 'borrowed_status') ??
          'Borrowed';
    return status?.replaceAll('_', ' ').toUpperCase() ?? '-';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildMetadataItem(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: bookMetadataCaptionStyle),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _startReading(BuildContext context) async {
    if (_book == null) return;
    await _showStatusChangeOptions(
      context,
      'reading',
      TranslationService.translate(context, 'start_reading') ?? 'Start Reading',
    );
  }

  Future<void> _markAsFinished(BuildContext context) async {
    if (_book == null) return;
    await _showStatusChangeOptions(
      context,
      'read',
      TranslationService.translate(context, 'mark_as_finished') ??
          'Mark as Finished',
    );
  }

  Future<void> _markAsRead(BuildContext context) async {
    if (_book == null) return;
    await _showStatusChangeOptions(
      context,
      'read',
      TranslationService.translate(context, 'mark_as_read') ?? 'Mark as Read',
    );
  }

  Future<void> _showStatusChangeOptions(
    BuildContext context,
    String newStatus,
    String title, {
    bool stayOnScreen = false,
  }) async {
    final previousStatus = _book?.readingStatus;
    final option = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: Text(
                TranslationService.translate(
                      context,
                      'date_select_option_today',
                    ) ??
                    'Today',
              ),
              onTap: () => Navigator.pop(context, 'today'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(
                TranslationService.translate(
                      context,
                      'date_select_option_pick',
                    ) ??
                    'Pick a date',
              ),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                TranslationService.translate(
                      context,
                      'date_select_option_none',
                    ) ??
                    'No date',
              ),
              onTap: () => Navigator.pop(context, 'none'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (option == null || !context.mounted) return;

    DateTime? selectedDate;
    final now = DateTime.now();

    if (option == 'today') {
      selectedDate = now;
    } else if (option == 'pick') {
      selectedDate = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(1900),
        lastDate: now,
      );
      if (selectedDate == null) return; // User cancelled picker
    } else {
      selectedDate = null;
    }

    if (!context.mounted) return;

    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      final Map<String, dynamic> updateData = {
        'title': _book!.title,
        'reading_status': newStatus,
      };

      if (newStatus == 'reading') {
        // "No date" sends an explicit null, which the update path turns into
        // a cleared column: neither reading date is mandatory.
        updateData['started_reading_at'] = selectedDate?.toIso8601String();
      } else if (newStatus == 'read') {
        updateData['finished_reading_at'] = selectedDate?.toIso8601String();
      }

      final levelsBefore = await MilestoneCelebration.snapshot();
      await bookRepo.updateBook(_book!.id!, updateData);

      if (context.mounted) {
        // Celebrate marking as read with a subtle animation
        if (newStatus == 'read' && previousStatus != 'read') {
          PlusOneAnimation.show(context, text: '\u2713');
        }

        // Celebrate any Reader cap crossed by finishing this book.
        MilestoneCelebration.celebrate(context, levelsBefore);

        // Finishing a book is the one moment a reader naturally asks
        // "what next?", so the feedback they already get carries one way
        // there (ADR-062 R5). Null unless this is the transition into
        // "read" and the suggestion floors pass.
        AppSnackBar.success(
          context,
          TranslationService.translate(context, 'status_updated'),
        );
        // The toast confirms the save and leaves; the block below answers
        // "what next?" and stays until the reader does (ADR-062 R5).
        if (newStatus == 'read' && previousStatus != 'read') {
          setState(() => _justFinishedReading = true);
        }

        if (stayOnScreen) {
          await _fetchBookDetails(forceRefresh: true);
          _hasChanges = true;
        } else {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_updating_status')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _refreshMetadata(BuildContext context) async {
    final book = _book;
    if (book == null || book.isbn == null || book.id == null) return;

    setState(() => _isRefreshing = true);

    // Also refresh audiobook search
    context.read<AudioProvider>().clearBookCache(book.id!);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final locale = Localizations.localeOf(context).languageCode;
      final metadata = await apiService.lookupBookMetadata(
        book.isbn!,
        lang: locale,
      );

      if (!mounted) return;

      if (metadata == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                    context,
                    'refresh_metadata_not_found',
                  ) ??
                  'No data found for this ISBN',
            ),
          ),
        );
        return;
      }

      // Check if there are any differences worth showing
      final hasAnyDiff = metadata.entries.any((e) {
        final fetched = e.value;
        if (fetched == null || fetched.isEmpty) return false;
        return true;
      });

      if (!hasAnyDiff) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                    context,
                    'refresh_metadata_no_changes',
                  ) ??
                  'No new data found',
            ),
          ),
        );
        return;
      }

      final selectedUpdates = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) =>
            MetadataRefreshDialog(currentBook: book, fetchedMetadata: metadata),
      );

      if (!mounted) return;

      if (selectedUpdates != null && selectedUpdates.isNotEmpty) {
        final bookRepo = Provider.of<BookRepository>(context, listen: false);
        await bookRepo.updateBook(book.id!, selectedUpdates);
        await _fetchBookDetails(forceRefresh: true);
        _hasChanges = true;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(
                      context,
                      'refresh_metadata_applied',
                    ) ??
                    'Info updated',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${TranslationService.translate(context, 'refresh_metadata_error') ?? 'Error refreshing info'}: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'delete_book_title') ??
              'Delete Book',
        ),
        content: Text(
          TranslationService.translate(context, 'delete_book_confirm') ??
              'Are you sure you want to delete this book?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              TranslationService.translate(context, 'cancel') ?? 'Cancel',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              TranslationService.translate(context, 'delete') ?? 'Delete',
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      try {
        if (_book == null) return;
        await bookRepo.deleteBook(_book!.id!);
        if (context.mounted) {
          context.read<HubDirectoryProvider>().markCatalogDirty();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'book_deleted') ??
                    'Book deleted',
              ),
            ),
          );
          context.read<BookRefreshNotifier>().refresh();
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'error_deleting_book')}: $e',
              ),
            ),
          );
        }
      }
    }
  }

  Widget _buildPerBookLoanDuration(BuildContext context) {
    final daysLabel = TranslationService.translate(
      context,
      'loan_duration_days_suffix',
    );
    final hintText = TranslationService.translate(
      context,
      'loan_duration_book_default_hint',
    ).replaceAll('%d', '$_defaultLoanDurationDays');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.timer_outlined, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(
                      context,
                      'loan_duration_book_custom',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_bookLoanDurationDays == null)
                    Text(
                      hintText,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
            if (_bookLoanDurationDays != null) ...[
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                tooltip: TranslationService.translate(
                  context,
                  'decrease_by_one',
                ),
                onPressed: _bookLoanDurationDays! > 1
                    ? () => _setBookLoanDuration(_bookLoanDurationDays! - 1)
                    : null,
              ),
              Text(
                '$_bookLoanDurationDays $daysLabel',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: TranslationService.translate(
                  context,
                  'increase_by_one',
                ),
                onPressed: _bookLoanDurationDays! < 365
                    ? () => _setBookLoanDuration(_bookLoanDurationDays! + 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: TranslationService.translate(
                  context,
                  'tooltip_clear_book_loan_duration',
                ),
                onPressed: () => _setBookLoanDuration(null),
              ),
            ] else
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: TranslationService.translate(
                  context,
                  'loan_duration_book_custom',
                ),
                onPressed: () => _setBookLoanDuration(_defaultLoanDurationDays),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setBookLoanDuration(int? days) async {
    final bookUuid = _book?.id;
    if (bookUuid == null) return;
    setState(() => _bookLoanDurationDays = days);
    try {
      final ffi = FfiService();
      await ffi.setBookLoanDuration(bookUuid, days);
    } catch (e) {
      debugPrint('Error setting book loan duration: $e');
    }
  }

  Future<void> _lendBook(BuildContext context) async {
    final recipient = await showDialog<LoanRecipient>(
      context: context,
      builder: (context) => const LoanDialog(),
    );

    if (recipient == null || !context.mounted || _book == null) return;

    try {
      switch (recipient) {
        case PeerRecipient(:final peerId):
          // Peer flow: Rust handles everything (contact, copy, loan, notification)
          final api = Provider.of<ApiService>(context, listen: false);
          final response = await api.offerLoanToPeer(
            peerId,
            bookId: _book!.id,
            isbn: _book!.isbn,
          );
          if (context.mounted) {
            if (response.statusCode == 409) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    TranslationService.translate(
                      context,
                      'no_available_copies',
                    ),
                  ),
                ),
              );
              return;
            }
            final notified =
                response.data is Map &&
                response.data['notification_sent'] == true;
            final suffix = notified
                ? ''
                : ' (${TranslationService.translate(context, 'loan_notification_pending')})';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${TranslationService.translate(context, 'book_lent_to')} ${recipient.displayName}$suffix',
                ),
              ),
            );
            _fetchBookDetails();
          }

        case ContactRecipient(:final contact):
          // Manual contact flow: create loan locally
          final copyRepo = Provider.of<CopyRepository>(context, listen: false);
          final loanRepo = Provider.of<LoanRepository>(context, listen: false);

          final copies = await copyRepo.getBookCopies(_book!.id!);
          if (copies.isEmpty) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    TranslationService.translate(
                      context,
                      'no_available_copies',
                    ),
                  ),
                ),
              );
            }
            return;
          }

          final availableCopy = copies.firstWhere(
            (c) => c.status == 'available',
            orElse: () => copies.first,
          );

          int durationDays = _defaultLoanDurationDays;
          try {
            final ffi = FfiService();
            if (ffi.isInitialized) {
              durationDays = await ffi.getEffectiveLoanDuration(_book!.id!);
            }
          } catch (_) {}
          final now = DateTime.now();
          final dueDate = now.add(Duration(days: durationDays));

          final levelsBefore = await MilestoneCelebration.snapshot();
          await loanRepo.createLoan({
            'copy_id': availableCopy.id,
            'contact_id': contact.id,
            'loan_date': now.toIso8601String().split('T')[0],
            'due_date': dueDate.toIso8601String().split('T')[0],
          });

          if (context.mounted) {
            // Celebrate any Lender cap crossed by this loan.
            MilestoneCelebration.celebrate(context, levelsBefore);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${TranslationService.translate(context, 'book_lent_to')} ${contact.fullName}',
                ),
              ),
            );
            _fetchBookDetails();
          }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_lending_book')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _returnBook(BuildContext context) async {
    final copyRepo = Provider.of<CopyRepository>(context, listen: false);
    final loanRepo = Provider.of<LoanRepository>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);

    try {
      if (_book == null) return;
      final copies = await copyRepo.getBookCopies(_book!.id!);
      if (copies.isEmpty) {
        throw Exception('No copy found for this book');
      }

      var lentCopies = copies.where((c) => c.status == 'loaned').toList();
      if (lentCopies.isEmpty) {
        lentCopies = copies.where((c) => c.status == 'borrowed').toList();
      }
      if (lentCopies.isEmpty) {
        throw Exception('No lent copy found for this book');
      }

      // Try P2P return: find matching incoming p2p_request for this book
      bool p2pHandled = false;
      final isbn = _book!.isbn;
      if (isbn != null && isbn.isNotEmpty) {
        try {
          final inRes = await api.getIncomingRequests();
          final requests = inRes.data as List? ?? [];
          final matching = requests.firstWhere(
            (r) => r['book_isbn'] == isbn && r['status'] == 'accepted',
            orElse: () => null,
          );
          if (matching != null) {
            await api.updateRequestStatus(matching['id'], 'returned');
            p2pHandled = true;
          }
        } catch (_) {
          // P2P lookup failed — fall through to local-only return
        }
      }

      // Fallback: local-only return (non-P2P loans or if P2P lookup failed)
      if (!p2pHandled) {
        final lentCopy = lentCopies.first;
        final loans = await loanRepo.getLoans(status: 'active');
        final matchingLoans = loans
            .where((l) => l.copyId == lentCopy.id)
            .toList();
        final loanUuid = matchingLoans.isNotEmpty
            ? matchingLoans.first.id
            : null;
        if (loanUuid != null) {
          await loanRepo.returnLoan(loanUuid);
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_returned'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _fetchBookDetails();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_returning_book') ?? 'Error returning book'}: $e',
            ),
          ),
        );
      }
    }
  }

  /// Borrow a book from a contact - creates a copy with 'borrowed' status
  Future<void> _borrowBook(BuildContext context) async {
    final contactRepo = Provider.of<ContactRepository>(context, listen: false);

    try {
      final bookId = _book?.id;
      if (bookId == null) return;

      // 1. Fetch contacts, annotating with has_book if the book has an ISBN.
      final contactsList = await contactRepo.getContacts(bookIsbn: _book?.isbn);

      if (contactsList.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(
                      context,
                      'no_contacts_to_borrow',
                    ) ??
                    'Add contacts first to track who you borrowed from',
              ),
            ),
          );
        }
        return;
      }

      // Sort: contacts who have the book first, then alphabetically within each group.
      final sorted = [...contactsList]
        ..sort((a, b) {
          final aHas = a.hasBook == true;
          final bHas = b.hasBook == true;
          if (aHas != bHas) return aHas ? -1 : 1;
          return a.displayName.compareTo(b.displayName);
        });

      // 2. Show contact picker dialog
      if (!context.mounted) return;
      final selectedContact = await showDialog<Contact>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            TranslationService.translate(dialogContext, 'select_lender') ??
                'Who are you borrowing from?',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sorted.length,
              itemBuilder: (_, index) {
                final contact = sorted[index];
                final hasBook = contact.hasBook == true;
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(contact.displayName),
                  subtitle: hasBook
                      ? Text(
                          TranslationService.translate(
                                dialogContext,
                                'contact_has_book',
                              ) ??
                              'Has this book',
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.primary,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  onTap: () => Navigator.pop(dialogContext, contact),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                TranslationService.translate(dialogContext, 'cancel') ??
                    'Cancel',
              ),
            ),
          ],
        ),
      );

      if (selectedContact == null) return;

      // 3. Create a copy with 'borrowed' status.
      // ADR-034: send structured loan metadata; the backend stores it on
      // typed columns and the reader renders it via TranslationService.
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      await copyRepo.createCopy(
        contactLoanCopyPayload(
          bookId: bookId,
          lenderDisplayName: selectedContact.fullName,
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'book_borrowed_from') ?? 'Borrowed from'} ${selectedContact.fullName}',
            ),
          ),
        );
        _fetchBookDetails();
      }
    } catch (e) {
      if (!context.mounted) return;
      final isBorrowSetup = e.toString().contains('BORROW_SETUP');
      final msg = isBorrowSetup
          ? TranslationService.translate(
              context,
              'error_borrow_setup_incomplete',
            )
          : TranslationService.translate(context, 'error_borrowing_book');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg ?? '')));
    }
  }

  /// Give back a borrowed book - removes the borrowed copy
  Future<void> _giveBackBook(BuildContext context) async {
    if (_book == null) return;

    // Find the borrowed copy
    final borrowedCopies = _copies
        .where((c) => c.status == 'borrowed')
        .toList();
    if (borrowedCopies.isEmpty) return;
    final borrowedCopy = borrowedCopies.first;

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'confirm_return_title'),
        ),
        content: Text(
          TranslationService.translate(context, 'confirm_return_borrowed'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TranslationService.translate(context, 'confirm')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Captured before the call: the backend deletes the borrowed copy, so this is
    // the only reliable view of what the book had.
    final book = _book!;
    final copiesBeforeReturn = List<Copy>.from(_copies);

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // Notify lender via P2P (E2EE or plaintext) and clean up locally
      final lenderNotified = await api.returnBorrowedBook(
        copyId: borrowedCopy.id!,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(returnOutcomeSnackBar(context, lenderNotified));

      // The backend deleted the borrowed copy and kept the book, which now reads
      // as not owned. Offer to remove it, never do it unasked.
      if (canOfferToRemove(book, copiesBeforeReturn)) {
        final remove = await askToRemoveReturnedBook(context, book);
        if (remove && context.mounted) {
          // `deleteBook` reports failure through the status code rather than an
          // exception: leaving the screen on a 500 would claim a removal that
          // never happened.
          final response = await api.deleteBook(book.id!);
          if (response.statusCode != 200 && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  TranslationService.translate(context, 'error_deleting_book'),
                ),
              ),
            );
          }
        }
      }

      if (context.mounted) {
        context.read<BookRefreshNotifier>().refresh();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_giving_back_book') ?? 'Error giving back book'}: $e',
            ),
          ),
        );
      }
    }
  }
}

/// Inline section showing the latest reading notes on the book detail page.
class _BookNotesSection extends StatefulWidget {
  final String bookId;
  final String bookTitle;

  const _BookNotesSection({required this.bookId, required this.bookTitle});

  @override
  State<_BookNotesSection> createState() => _BookNotesSectionState();
}

class _BookNotesSectionState extends State<_BookNotesSection> {
  final _contentController = TextEditingController();
  final _pageController = TextEditingController();
  static const _previewLimit = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookNoteProvider>().loadNotes(widget.bookId);
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    final page = int.tryParse(_pageController.text.trim());
    final success = await context.read<BookNoteProvider>().createNote(
      content: content,
      page: page,
    );
    if (success && mounted) {
      _contentController.clear();
      _pageController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _editNote(BookNote note) async {
    final contentCtrl = TextEditingController(text: note.content);
    final pageCtrl = TextEditingController(text: note.page?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(context, 'edit_note')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              maxLength: maxNoteContentLength,
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                  context,
                  'add_note_placeholder',
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pageCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                  context,
                  'note_page_label',
                ),
                prefixIcon: const Icon(Icons.bookmark_outline, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final newContent = contentCtrl.text.trim();
      if (newContent.isEmpty) return;
      await context.read<BookNoteProvider>().updateNote(
        id: note.id,
        content: newContent,
        page: int.tryParse(pageCtrl.text.trim()),
      );
    }
    contentCtrl.dispose();
    pageCtrl.dispose();
  }

  Future<void> _deleteNote(BookNote note) async {
    await context.read<BookNoteProvider>().deleteNote(note.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = TranslationService.translate;
    final theme = Theme.of(context);

    return Consumer<BookNoteProvider>(
      builder: (context, provider, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header: icon + title in the primary color, matching the
            // series frise header so the fiche's section labels read alike.
            Semantics(
              header: true,
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      t(context, 'notes_section_title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              t(
                context,
                context.watch<ThemeProvider>().speechToTextEnabled
                    ? 'notes_section_hint_speech'
                    : 'notes_section_hint',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withAlpha(120),
              ),
            ),
            const SizedBox(height: 12),
            // Quick add bar
            Row(
              children: [
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _pageController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'p.',
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.bookmark_outline,
                        size: 16,
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 0,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withAlpha(60),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withAlpha(60),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _contentController,
                    textInputAction: TextInputAction.send,
                    maxLength: maxNoteContentLength,
                    onSubmitted: (_) => _addNote(),
                    decoration: InputDecoration(
                      hintText: t(context, 'add_note_placeholder'),
                      hintStyle: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withAlpha(100),
                      ),
                      isDense: true,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withAlpha(60),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: theme.colorScheme.outline.withAlpha(60),
                        ),
                      ),
                    ),
                  ),
                ),
                if (context.watch<ThemeProvider>().speechToTextEnabled)
                  SpeechNoteButton(controller: _contentController),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _addNote,
                  icon: const Icon(Icons.send, size: 20),
                  tooltip: t(context, 'tooltip_add_note'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Notes preview
            if (provider.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (provider.notes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  t(context, 'no_notes_yet'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withAlpha(128),
                  ),
                ),
              )
            else ...[
              ...provider.notes
                  .take(_previewLimit)
                  .map(
                    (note) => BookNoteTile(
                      note: note,
                      onEdit: () => _editNote(note),
                      onDelete: () => _deleteNote(note),
                    ),
                  ),
              if (provider.notes.length > _previewLimit)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push(
                      '/books/${widget.bookId}/notes',
                      extra: {'bookTitle': widget.bookTitle},
                    ),
                    child: Text(t(context, 'view_all_notes')),
                  ),
                ),
            ],
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
