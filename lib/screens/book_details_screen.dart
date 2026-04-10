import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../utils/cover_camera_helper.dart';

import '../audio/audio_module.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../data/repositories/loan_repository.dart';
import '../models/book.dart';
import '../models/collection.dart';
import '../models/contact.dart';
import '../models/copy.dart';
import '../models/cover_candidate.dart';
import '../models/book_note.dart';
import '../providers/book_note_provider.dart' show BookNoteProvider, maxNoteContentLength;
import '../providers/book_refresh_notifier.dart';
import '../widgets/book_note_tile.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../utils/book_status.dart';
import '../widgets/cached_book_cover.dart';
import '../widgets/plus_one_animation.dart';
import '../widgets/cover_picker_dialog.dart';
import '../widgets/loan_dialog.dart';
import '../widgets/metadata_refresh_dialog.dart';
import '../widgets/speech_note_button.dart';
import '../widgets/star_rating_widget.dart';
import 'record_sale_screen.dart';

class BookDetailsScreen extends StatefulWidget {
  final Book? book;
  final int bookId;

  const BookDetailsScreen({super.key, this.book, required this.bookId});

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  Book? _book;
  List<Copy> _copies = [];
  List<Collection> _collections = [];
  bool _isLoadingCopies = true;
  bool _isLoadingBook = false;
  bool _hasChanges = false;
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
  }

  Future<void> _fetchCopies() async {
    if (!mounted) return;
    try {
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      final copies = await copyRepo.getBookCopies(widget.bookId);
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
    final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
    try {
      final copiesFuture = copyRepo.getBookCopies(widget.bookId);
      final collectionsFuture = collectionRepo.getBookCollections(widget.bookId);

      // Always fetch fresh book data from DB to get latest changes (e.g. rating)
      final bookFuture = bookRepo.getBook(widget.bookId);

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
          if (_perBookDurationEnabled) {
            _bookLoanDurationDays =
                await ffi.getBookLoanDuration(widget.bookId);
          }
        }
      } catch (e) {
        debugPrint('Error loading loan settings: $e');
      }

      if (mounted) {
        setState(() {
          _book = freshBook;
          _isLoadingBook = false;
          _copies = copies;
          _collections = collections;
          _isLoadingCopies = false;
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
          SnackBar(content: Text('${TranslationService.translate(context, 'error')}: $e')),
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
          SnackBar(content: Text('${TranslationService.translate(context, 'error')}: $e')),
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
      imageCache.evict(CachedNetworkImageProvider(coverUrl,
          cacheManager: BookCoverCacheManager.instance));
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
                      context, hasCover ? 'cover_change' : 'cover_add') ??
                  (hasCover ? 'Change cover' : 'Add a cover'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (hasIsbn)
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(
                    TranslationService.translate(context, 'cover_search_online') ??
                        'Search online'),
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
                        'Take a photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _takeCoverPhoto(book);
                },
              ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(
                  TranslationService.translate(context, 'cover_choose_file') ??
                      'Choose from files'),
              onTap: () {
                Navigator.pop(ctx);
                _pickCoverFromFile(book);
              },
            ),
            if (hasCover)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
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
        TranslationService.translate(context, 'cover_found') ??
            'Cover found!';
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                      strokeWidth: 2, color: Colors.white),
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
            book.title, book.author,
            enableGoogle: googleBooksEnabled);

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
        messenger.showSnackBar(
          SnackBar(content: Text(notFoundText)),
        );
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
          setState(() { _book = _book!.copyWithCoverUrl(newUrl); _coverVersion++; });
        }
        _fetchBookDetails(forceRefresh: true);
        messenger.showSnackBar(
          SnackBar(content: Text(foundText)),
        );
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
          setState(() { _book = _book!.copyWithCoverUrl(selectedUrl); _coverVersion++; });
        }
        _fetchBookDetails(forceRefresh: true);
        messenger.showSnackBar(
          SnackBar(content: Text(updatedText)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
        setState(() { _book = _book!.copyWithCoverUrl(path); _coverVersion++; });
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
    } catch (e) {
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final pickedFile = result.files.first;
      if (pickedFile.path == null) return;

      final appDir = await getApplicationSupportDirectory();
      final coversDir = Directory('${appDir.path}/covers');
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }

      final extension = pickedFile.extension ?? 'jpg';
      final targetPath = '${coversDir.path}/${book.id}.$extension';

      final sourceFile = File(pickedFile.path!);
      await sourceFile.copy(targetPath);

      if (!mounted) return;
      _evictCoverFromCache(_book?.coverUrl);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      await bookRepo.updateBook(book.id!, {'cover_url': targetPath});
      _hasChanges = true;
      if (mounted) {
        setState(() { _book = _book!.copyWithCoverUrl(targetPath); _coverVersion++; });
      }
      _fetchBookDetails(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  TranslationService.translate(context, 'cover_updated') ??
                      'Cover updated')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
        setState(() { _book = _book!.copyWithCoverUrl(null); _coverVersion++; });
      }
      _fetchBookDetails(forceRefresh: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  TranslationService.translate(context, 'cover_removed') ??
                      'Cover removed')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
                    const SizedBox(height: 24),
                    _buildActionButtons(context, book),
                    const SizedBox(height: 32),
                    _buildMetadataGrid(context, book),
                    const SizedBox(height: 16),
                    // Audio module section (decoupled - only shows if enabled)
                    if (book.id != null)
                      AudioSection(
                        bookId: book.id!,
                        bookTitle: book.title,
                        bookAuthor: book.author,
                        bookLanguage: book.language,
                        userLanguages:
                            context.read<ThemeProvider>().userLanguages,
                      ),
                    const SizedBox(height: 32),
                    if (book.summary != null && book.summary!.isNotEmpty) ...[
                      Text(
                        TranslationService.translate(context, 'book_summary') ??
                            'Summary',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
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
                      _BookNotesSection(bookId: book.id!, bookTitle: book.title),
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
                                  context, 'book_private'),
                            ),
                            subtitle: Text(
                              TranslationService.translate(
                                  context, 'book_private_desc'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            value: book.private,
                            onChanged: (value) => _togglePrivate(value),
                          ),
                        );
                      },
                    ),
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
        background: ExcludeSemantics(child: Stack(
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
                child: Container(
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
              ),
              ),
            ),
          ],
        )),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Book book) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: Theme.of(context).textTheme.titleLarge?.color,
          ),
        ),
        if (book.author != null) ...[
          const SizedBox(height: 8),
          Text(
            book.author!,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, Book book) {
    final isReading = book.readingStatus == 'reading';
    final isToRead =
        book.readingStatus == 'to_read' || book.readingStatus == null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Tooltip(
                message:
                    TranslationService.translate(context, 'menu_edit') ??
                    'Edit Book',
                child: ElevatedButton.icon(
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
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    TranslationService.translate(context, 'menu_edit') ??
                        'Edit',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                  onPressed: () {
                    if (_book == null) return;
                    context.push(
                      '/books/${_book!.id}/copies',
                      extra: {'bookId': _book!.id, 'bookTitle': _book!.title},
                    );
                  },
                  icon: Badge(
                    label: Text('${_copies.length}'),
                    isLabelVisible: _copies.length > 1,
                    child: const Icon(Icons.library_books_outlined),
                  ),
                  label: Text(
                    TranslationService.translate(
                          context,
                          'menu_copies_short',
                        ) ??
                        'Copies',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  key: const Key('manageCopiesButton'),
                ),
              ),
            ),
            if (book.isbn != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: TranslationService.translate(
                        context, 'refresh_metadata_title') ??
                    'Update Book Info',
                child: IconButton(
                  onPressed:
                      _isRefreshing ? null : () => _refreshMetadata(context),
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  key: const Key('refreshMetadataButton'),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Tooltip(
              message:
                  TranslationService.translate(context, 'menu_delete') ??
                  'Delete Book',
              child: IconButton(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.deepOrange,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.deepOrange.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                      TranslationService.translate(
                        context,
                        'add_copy_title',
                      ) ??
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
        // Per-book loan duration - only visible when per-book customization is enabled
        if (_perBookDurationEnabled && book.owned) ...[
          const SizedBox(height: 12),
          _buildPerBookLoanDuration(context),
        ],
        // Lend book button - only visible when there are available copies and book is owned
        if (_hasAvailableCopies && book.owned) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _lendBook(context),
              icon: const Icon(Icons.handshake_outlined),
              label: Text(
                TranslationService.translate(context, 'lend_book_btn') ??
                    'Lend this book',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.purple,
                side: const BorderSide(color: Colors.purple),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        // Return lent book button - only visible when there are lent copies
        if (_hasLentCopies) ...[
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
        // Borrow from friend button - only visible when book is NOT owned and has no borrowed copies
        if (!book.owned && !_hasBorrowedCopies) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _borrowBook(context),
              icon: const Icon(Icons.arrow_downward),
              label: Text(
                TranslationService.translate(
                      context,
                      'borrow_from_contact_btn',
                    ) ??
                    'Borrow from a contact',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: const BorderSide(color: Colors.teal),
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
      ],
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (TranslationService.translate(context, 'status_label') ?? 'Status').toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildStatusChip(context, book),
                  ],
                ),
              ),
            ],
          ),
          // Rating section
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (TranslationService.translate(context, 'rating_label') ??
                              'MY RATING')
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    StarRatingWidget(
                      rating: book.userRating,
                      onRatingChanged: _updateRating,
                      size: 32,
                    ),
                  ],
                ),
              ),
              if (book.pageCount != null) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (TranslationService.translate(context, 'page_count_label') ??
                                'PAGES')
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${book.pageCount}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ],
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
          if (book.subjects != null && book.subjects!.isNotEmpty) ...[
            const Divider(height: 32),
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.local_offer_outlined,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (TranslationService.translate(context, 'tags') ??
                                'TAGS')
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: book.subjects!.asMap().entries.map((entry) {
                      final index = entry.key;
                      final subject = entry.value;
                      // Cycle through colors for visual variety
                      final colors = [
                        Colors.blue,
                        Colors.teal,
                        Colors.purple,
                        Colors.orange,
                        Colors.pink,
                        Colors.indigo,
                      ];
                      final chipColor = colors[index % colors.length];

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            context.go(
                              Uri(
                                path: '/books',
                                queryParameters: {'tag': subject},
                              ).toString(),
                            );
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  chipColor.withValues(alpha: 0.15),
                                  chipColor.withValues(alpha: 0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: chipColor.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tag, size: 14, color: chipColor),
                                const SizedBox(width: 4),
                                Text(
                                  subject,
                                  style: TextStyle(
                                    color: chipColor.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
          if (_collections.isNotEmpty) ...[
            const Divider(height: 32),
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.collections_bookmark_outlined,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        TranslationService.translate(context, 'collections_label')
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: _collections.asMap().entries.map((entry) {
                      final index = entry.key;
                      final collection = entry.value;
                      final colors = [
                        Colors.amber,
                        Colors.deepPurple,
                        Colors.cyan,
                        Colors.red,
                        Colors.green,
                        Colors.brown,
                      ];
                      final chipColor = colors[index % colors.length];

                      return Semantics(
                        button: true,
                        label: collection.name,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              context.go('/collections/${collection.id}');
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    chipColor.withValues(alpha: 0.15),
                                    chipColor.withValues(alpha: 0.08),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: chipColor.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.collections_bookmark, size: 14, color: chipColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    collection.name,
                                    style: TextStyle(
                                      color: chipColor.shade700,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
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
      themeProvider.isLibrarian,
    );
    final color = statusObj?.color ?? Colors.grey;
    final icon = statusObj?.icon ?? Icons.help_outline;
    final label = statusObj?.label ?? _translateStatus(context, book.readingStatus);

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
    final isLibrarian = themeProvider.isLibrarian;
    final statusOptions = getStatusOptions(context, isLibrarian);
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
                TranslationService.translate(context, 'status_label') ?? 'Status',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...statusOptions.map((status) {
              final isSelected = status.value == currentStatus;
              return ListTile(
                leading: Icon(status.icon, color: status.color),
                title: Text(
                  status.label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

    if (selected == null || !context.mounted || selected == currentStatus) return;

    // Statuses that need a date picker
    if (selected == 'reading' || selected == 'read') {
      final title = selected == 'reading'
          ? TranslationService.translate(context, 'start_reading') ?? 'Start Reading'
          : TranslationService.translate(context, 'mark_as_read') ?? 'Mark as Read';
      await _showStatusChangeOptions(context, selected, title, stayOnScreen: true);
    } else {
      await _updateStatusDirectly(context, selected);
    }
  }

  Future<void> _updateStatusDirectly(BuildContext context, String newStatus) async {
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
              TranslationService.translate(context, 'status_updated') ?? 'Status updated',
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
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.grey[600],
            ),
          ),
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
      TranslationService.translate(context, 'mark_as_read') ??
          'Mark as Read',
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
        // If we have a date, set it. If we chose 'none', we might want to explicity set it to null
        // OR just omit it? If we omit it, previous value remains.
        // If the user explicitly chose 'No Date', they likely want to clear it or set it empty.
        // But the API might not support clearing if we just omit.
        // Let's send the date if we have it. If 'none', we explicitly send null?
        // The backend logic: `if let Some(started_at) = book_data.started_reading_at`.
        // To clear it, we might need to send `null` in JSON.
        // Dart `toIso8601String()` is only for non-null.
        // Let's check api_service.dart again. It takes Map<String, dynamic>.
        // JSON `null` is valid.
        updateData['started_reading_at'] = selectedDate?.toIso8601String();
      } else if (newStatus == 'read') {
        updateData['finished_reading_at'] = selectedDate?.toIso8601String();
      }

      await bookRepo.updateBook(_book!.id!, updateData);

      if (context.mounted) {
        // Celebrate marking as read with a subtle animation
        if (newStatus == 'read' && previousStatus != 'read') {
          PlusOneAnimation.show(context, text: '\u2713');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'status_updated') ??
                  'Status updated',
            ),
          ),
        );

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
      final metadata =
          await apiService.lookupBookMetadata(book.isbn!, lang: locale);

      if (!mounted) return;

      if (metadata == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(
                      context, 'refresh_metadata_not_found') ??
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
                      context, 'refresh_metadata_no_changes') ??
                  'No new data found',
            ),
          ),
        );
        return;
      }

      final selectedUpdates = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => MetadataRefreshDialog(
          currentBook: book,
          fetchedMetadata: metadata,
        ),
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
                        context, 'refresh_metadata_applied') ??
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
          // Navigate back to list and refresh
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
    final daysLabel =
        TranslationService.translate(context, 'loan_duration_days_suffix');
    final hintText = TranslationService.translate(
            context, 'loan_duration_book_default_hint')
        .replaceAll('%d', '$_defaultLoanDurationDays');

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
                        context, 'loan_duration_book_custom'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (_bookLoanDurationDays == null)
                    Text(
                      hintText,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                ],
              ),
            ),
            if (_bookLoanDurationDays != null) ...[
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                tooltip: '-1',
                onPressed: _bookLoanDurationDays! > 1
                    ? () => _setBookLoanDuration(_bookLoanDurationDays! - 1)
                    : null,
              ),
              Text(
                '$_bookLoanDurationDays $daysLabel',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: '+1',
                onPressed: _bookLoanDurationDays! < 365
                    ? () => _setBookLoanDuration(_bookLoanDurationDays! + 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: TranslationService.translate(
                    context, 'tooltip_clear_book_loan_duration'),
                onPressed: () => _setBookLoanDuration(null),
              ),
            ] else
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: TranslationService.translate(
                    context, 'loan_duration_book_custom'),
                onPressed: () =>
                    _setBookLoanDuration(_defaultLoanDurationDays),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setBookLoanDuration(int? days) async {
    setState(() => _bookLoanDurationDays = days);
    try {
      final ffi = FfiService();
      await ffi.setBookLoanDuration(widget.bookId, days);
    } catch (e) {
      debugPrint('Error setting book loan duration: $e');
    }
  }

  Future<void> _lendBook(BuildContext context) async {
    final selectedContact = await showDialog<Contact>(
      context: context,
      builder: (context) => const LoanDialog(),
    );

    if (selectedContact == null || !context.mounted) return;

    final copyRepo = Provider.of<CopyRepository>(context, listen: false);
    final loanRepo = Provider.of<LoanRepository>(context, listen: false);
    try {
      if (_book == null) return;
      // 1. Get existing copies for this book
      final copies = await copyRepo.getBookCopies(_book!.id!);

      int copyId;

      if (copies.isEmpty) {
        // 2. Create a copy if none exists
        final newCopy = await copyRepo.createCopy({
          'book_id': _book!.id,
          // library_id resolved by backend
          'status': 'available',
          'is_temporary': false,
        });
        copyId = newCopy.id!;
      } else {
        // Find an available copy
        final availableCopy = copies.firstWhere(
          (c) => c.status == 'available',
          orElse: () => copies.first,
        );
        copyId = availableCopy.id!;
      }

      // 3. Calculate due date from effective loan duration
      int durationDays = _defaultLoanDurationDays;
      try {
        final ffi = FfiService();
        if (ffi.isInitialized) {
          durationDays = await ffi.getEffectiveLoanDuration(_book!.id!);
        }
      } catch (_) {}
      final now = DateTime.now();
      final dueDate = now.add(Duration(days: durationDays));

      // 4. Create the loan with correct fields
      await loanRepo.createLoan({
        'copy_id': copyId,
        'contact_id': selectedContact.id,
        // library_id resolved by backend
        'loan_date': now.toIso8601String().split('T')[0],
        'due_date': dueDate.toIso8601String().split('T')[0],
      });

      // 5. Update copy status to 'lent'
      await copyRepo.updateCopy(copyId, {'status': 'loaned'});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'book_lent_to') ?? 'Book lent to'} ${selectedContact.fullName}',
            ),
          ),
        );
        // Refresh the book details from API
        _fetchBookDetails();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_lending_book') ?? 'Error lending book'}: $e',
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
            (r) =>
                r['book_isbn'] == isbn &&
                r['status'] == 'accepted',
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
        final matchingLoans =
            loans.where((l) => l.copyId == lentCopy.id).toList();
        if (matchingLoans.isNotEmpty) {
          await loanRepo.returnLoan(matchingLoans.first.id);
        }
        await copyRepo.updateCopy(lentCopy.id!, {'status': 'available'});
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
      if (_book == null) return;

      // 1. Fetch contacts, annotating with has_book if the book has an ISBN.
      final contactsList = await contactRepo.getContacts(
        bookIsbn: _book?.isbn,
      );

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
      final sorted = [...contactsList]..sort((a, b) {
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
                            color: Theme.of(
                              dialogContext,
                            ).colorScheme.primary,
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

      // 3. Create a copy with 'borrowed' status
      final borrowedFromLabel =
          TranslationService.translate(context, 'borrowed_from_label') ??
          'Borrowed from';
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      await copyRepo.createCopy({
        'book_id': _book!.id,
        // library_id resolved by backend
        'status': 'borrowed',
        'is_temporary': false,
        'notes': '$borrowedFromLabel ${selectedContact.fullName}',
      });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? '')),
      );
    }
  }

  /// Give back a borrowed book - removes the borrowed copy
  Future<void> _giveBackBook(BuildContext context) async {
    if (_book == null) return;

    // Find the borrowed copy
    final borrowedCopies =
        _copies.where((c) => c.status == 'borrowed').toList();
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

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // Notify lender via P2P (E2EE or plaintext) and clean up locally
      await api.returnBorrowedBook(copyId: borrowedCopy.id!);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_returned_success'),
            ),
            backgroundColor: Colors.green,
          ),
        );
        // Backend deleted the borrowed copy (and the book if no remaining copies).
        // Navigate back - the book is no longer in the user's library.
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
  final int bookId;
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
    final success = await context
        .read<BookNoteProvider>()
        .createNote(content: content, page: page);
    if (success && mounted) {
      _contentController.clear();
      _pageController.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _editNote(BookNote note) async {
    final contentCtrl = TextEditingController(text: note.content);
    final pageCtrl =
        TextEditingController(text: note.page?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'edit_note'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              maxLength: maxNoteContentLength,
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                    context, 'add_note_placeholder'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pageCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                    context, 'note_page_label'),
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
            // Section header
            Semantics(
              header: true,
              child: Text(
                t(context, 'notes_section_title'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
                          horizontal: 4, vertical: 10),
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
                          horizontal: 12, vertical: 10),
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
              ...provider.notes.take(_previewLimit).map(
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
                    child: Text(
                      t(context, 'view_all_notes'),
                    ),
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
