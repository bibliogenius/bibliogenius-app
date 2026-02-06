import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/copy.dart';
import '../models/contact.dart';
import 'record_sale_screen.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../data/repositories/loan_repository.dart';
import '../services/translation_service.dart';
// Assuming we might want to use common widgets, but for this specific design we want a SliverAppBar
import '../widgets/star_rating_widget.dart';
import '../widgets/loan_dialog.dart';
import '../providers/theme_provider.dart';
import '../audio/audio_module.dart'; // Audio module (decoupled)
import '../widgets/cached_book_cover.dart';

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
  bool _isLoadingCopies = true;
  bool _isLoadingBook = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    if (widget.book != null) {
      _book = widget.book;
      _fetchCopies();
      // Optionally refresh book details in background
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
    try {
      final copiesFuture = copyRepo.getBookCopies(widget.bookId);

      // Fetch book if we don't have it OR if forced refresh is requested
      Future<Book>? bookFuture;
      if (_book == null || forceRefresh) {
        bookFuture = bookRepo.getBook(widget.bookId);
      }

      final copies = await copiesFuture;
      final freshBook = bookFuture != null ? await bookFuture : null;

      if (mounted) {
        setState(() {
          if (freshBook != null) {
            _book = freshBook;
            _isLoadingBook = false;
          }

          _copies = copies;
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

  // ... existing build methods ...

  Future<void> _updateRating(int? newRating) async {
    if (_book == null || _book!.id == null) return;
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      await bookRepo.updateBook(_book!.id!, {
        'title': _book!.title,
        'user_rating': newRating,
      });
      setState(() {
        _book = _book!.copyWithRating(newRating);
      });
    } catch (e) {
      if (mounted) {
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
        Navigator.of(context).pop(_hasChanges);
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
                        // Use app language as preferred audiobook language
                        bookLanguage: Localizations.localeOf(
                          context,
                        ).languageCode,
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
    return SliverAppBar(
      expandedHeight: 400.0,
      pinned: true,
      stretch: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 0: Fallback (always rendered at bottom)
            _buildFallbackCover(book),

            // Layer 1: Network Image (if available)
            if (coverUrl != null && coverUrl.isNotEmpty)
              CachedBookCover(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                placeholder: const SizedBox.shrink(),
                errorWidget: const SizedBox.shrink(),
              ),

            // Layer 2: Blur Effect (applied on top of fallback or image)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.black.withValues(alpha: 0.4)),
            ),

            // Hero Image
            Center(
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
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            placeholder: const SizedBox.shrink(),
                            errorWidget: const SizedBox.shrink(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
                      // Refresh book data but STAY on the screen
                      await _fetchBookDetails(forceRefresh: true);
                      // Mark that we have changes so we can return true later
                      setState(() {
                        // We track this via a member variable which we need to add to the State class
                        // For now, let's just make sure the UI is up to date.
                        // The list screen underneath will naturally refresh if we pop later with true.
                        _hasChanges = true;
                      });
                    }
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    TranslationService.translate(context, 'menu_edit') ??
                        'Edit',
                  ),
                  style: ElevatedButton.styleFrom(
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
                  icon: const Icon(Icons.library_books_outlined),
                  label: Text(
                    TranslationService.translate(
                          context,
                          'menu_manage_copies',
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
            const SizedBox(width: 12),
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
        if (isToRead) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _startReading(context),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(
                TranslationService.translate(context, 'start_reading') ??
                    'Start Reading',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        if (isReading) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _markAsFinished(context),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                TranslationService.translate(context, 'mark_as_finished') ??
                    'Mark as Finished',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
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
              _buildMetadataItem(
                context,
                TranslationService.translate(context, 'status_label') ??
                    'Status',
                _translateStatus(context, book.readingStatus),
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
        ],
      ),
    );
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

  Future<void> _showStatusChangeOptions(
    BuildContext context,
    String newStatus,
    String title,
  ) async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'status_updated') ??
                  'Status updated',
            ),
          ),
        );
        Navigator.of(context).pop(true);
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
          'library_id': 1, // Default library
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

      // 3. Calculate due date (30 days from now)
      final now = DateTime.now();
      final dueDate = now.add(const Duration(days: 30));

      // 4. Create the loan with correct fields
      await loanRepo.createLoan({
        'copy_id': copyId,
        'contact_id': selectedContact.id,
        'library_id': 1, // Default library
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

    try {
      if (_book == null) return;
      // Find copies for this book
      final copies = await copyRepo.getBookCopies(_book!.id!);

      if (copies.isEmpty) {
        throw Exception('No copy found for this book');
      }

      // Get the lent copy - find one with 'loaned' status first
      var lentCopies = copies.where((c) => c.status == 'loaned').toList();
      if (lentCopies.isEmpty) {
        lentCopies = copies.where((c) => c.status == 'borrowed').toList();
      }

      if (lentCopies.isEmpty) {
        throw Exception('No lent copy found for this book');
      }
      final lentCopy = lentCopies.first;

      // Find active loan for this copy
      final loans = await loanRepo.getLoans(status: 'active');

      // Find the loan matching this copy
      final matchingLoans = loans
          .where((l) => l.copyId == lentCopy.id)
          .toList();

      if (matchingLoans.isNotEmpty) {
        // Return the loan
        await loanRepo.returnLoan(matchingLoans.first.id);
      }

      // Update copy status back to 'available'
      await copyRepo.updateCopy(lentCopy.id!, {'status': 'available'});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_returned') ??
                  'Book returned',
            ),
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

      // 1. Fetch contacts to let user pick who they're borrowing from
      final contactsList = await contactRepo.getContacts();

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

      // 2. Show contact picker dialog
      final selectedContact = await showDialog<Contact>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            TranslationService.translate(context, 'select_lender') ??
                'Who are you borrowing from?',
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: contactsList.length,
              itemBuilder: (context, index) {
                final contact = contactsList[index];
                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(contact.displayName),
                  onTap: () => Navigator.pop(context, contact),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                TranslationService.translate(context, 'cancel') ?? 'Cancel',
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
        'library_id': 1,
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_borrowing_book') ?? 'Error borrowing book'}: $e',
            ),
          ),
        );
      }
    }
  }

  /// Give back a borrowed book - removes the borrowed copy
  Future<void> _giveBackBook(BuildContext context) async {
    final copyRepo = Provider.of<CopyRepository>(context, listen: false);

    try {
      if (_book == null) return;

      // Find the borrowed copy
      final borrowedCopies = _copies
          .where((c) => c.status == 'borrowed')
          .toList();
      if (borrowedCopies.isEmpty) {
        throw Exception('No borrowed copy found');
      }
      final borrowedCopy = borrowedCopies.first;

      // Delete the borrowed copy (book was given back, no longer in our possession)
      await copyRepo.deleteCopy(borrowedCopy.id!);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_given_back') ??
                  'Book given back',
            ),
          ),
        );
        _fetchBookDetails();
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
