import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:provider/provider.dart';
import '../data/repositories/book_repository.dart';
import '../providers/hub_directory_provider.dart';
import '../data/repositories/copy_repository.dart';
import '../services/translation_service.dart';
import '../services/api_service.dart';
import '../utils/isbn_validator.dart';
import '../utils/book_url_helper.dart';
import '../models/book.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/flash_message_provider.dart';

/// Scan screen with optional batch mode and pre-selected destination.
///
/// In batch mode, books are added directly with the pre-selected shelf/collection
/// and the scanner continues for the next book.
class ScanScreen extends StatefulWidget {
  final String? preSelectedShelfId;
  final String? preSelectedShelfName;
  final String? preSelectedCollectionId;
  final String? preSelectedCollectionName;
  final bool batchMode;

  const ScanScreen({
    super.key,
    this.preSelectedShelfId,
    this.preSelectedShelfName,
    this.preSelectedCollectionId,
    this.preSelectedCollectionName,
    this.batchMode = false,
    this.scannerBuilder,
    this.controller,
  });

  final Widget Function(
    BuildContext,
    MobileScannerController,
    void Function(BarcodeCapture),
  )?
  scannerBuilder;
  final MobileScannerController? controller;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final MobileScannerController controller;

  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        MobileScannerController(
          autoStart: false,
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        );

    // Start camera when view is visible only after frame is rendered
    // to avoid immediate permission denial errors on some platforms
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        controller.start();
      }
    });

    // Check connectivity to show offline banner
    BookUrlHelper.isOnline().then((online) {
      if (mounted) setState(() => _isOffline = !online);
    });
  }

  bool _isScanning = true;
  bool _isTorchOn = false;
  bool _isOffline = false;
  String? _lastScannedIsbn; // Prevent duplicate navigation for same ISBN

  // Batch mode state
  int _batchCount = 0;
  String? _lastAddedTitle;
  bool _isProcessingBatch = false;
  bool _isCommitting = false;
  double _commitProgress = 0.0;
  final List<_BatchedBook> _batchedBooks = [];
  final Set<String> _batchedIsbns = {};

  @override
  void dispose() {
    // Only dispose if we created it (or just dispose always if the controller handles multiple disposes gracefully?
    // Usually standard practice: if passed from outside, don't dispose. But here it's "optional overrides default".
    // If widget.controller is provided, we might assume ownership or not.
    // For safety in production (where it's null), we MUST dispose.
    // In test (where it's provided), we might mock dispose.
    // Let's dispose it. MobileScannerController.dispose() is idempotent usually?
    controller.dispose();
    super.dispose();
  }

  DateTime? _lastInvalidScanTime;

  String get _destinationLabel {
    if (widget.preSelectedShelfName != null) {
      return widget.preSelectedShelfName!;
    } else if (widget.preSelectedCollectionName != null) {
      return widget.preSelectedCollectionName!;
    }
    return '';
  }

  bool get _hasDestination =>
      widget.preSelectedShelfId != null ||
      widget.preSelectedCollectionId != null;

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    bool foundValid = false;

    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue != null && IsbnValidator.isValid(rawValue)) {
        // Skip if we already scanned this ISBN (prevents rapid duplicate scans)
        if (rawValue == _lastScannedIsbn) return;

        foundValid = true;
        _lastScannedIsbn = rawValue; // Remember this ISBN

        // Haptic feedback
        HapticFeedback.lightImpact();

        if (widget.batchMode) {
          // Batch mode: add book directly and continue scanning
          _handleBatchScan(rawValue);
        } else {
          // Normal mode: return ISBN to previous screen
          setState(() {
            _isScanning = false;
          });
          if (mounted) {
            context.pop(rawValue);
          }
        }
        return;
      }
    }

    // Feedback for invalid barcodes (debounced)
    if (!foundValid && barcodes.isNotEmpty) {
      final now = DateTime.now();
      if (_lastInvalidScanTime == null ||
          now.difference(_lastInvalidScanTime!) > const Duration(seconds: 3)) {
        _lastInvalidScanTime = now;
        _showInvalidBarcodeDialog();
      }
    }
  }

  Future<void> _handleBatchScan(String isbn) async {
    if (_isProcessingBatch || _isCommitting) return;

    // Prevent duplicate ISBNs within the same batch session
    if (_batchedIsbns.contains(isbn)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'batch_scan_duplicate'),
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isScanning = true);
      }
      return;
    }

    setState(() {
      _isScanning = false;
      _isProcessingBatch = true;
    });

    try {
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      final api = Provider.of<ApiService>(context, listen: false);

      String? bookTitle;
      String? bookCoverUrl;
      Map<String, dynamic>? bookPayload;

      // 1. Check if book already exists in library
      Book? existingBook = await bookRepo.findBookByIsbn(isbn);

      if (existingBook != null) {
        bookTitle = existingBook.title;
        bookCoverUrl = existingBook.coverUrl;

        // Ask the user: add a copy or skip?
        if (mounted) setState(() => _isProcessingBatch = false);
        if (!mounted) return;
        final action = await _showExistingBookDialog(existingBook);
        if (action != _ExistingBookAction.addCopy) {
          return; // finally block re-enables scanning
        }
      } else {
        // 2. Not found locally, lookup metadata (needs network)
        final isOnline = await BookUrlHelper.isOnline();
        if (mounted) setState(() => _isOffline = !isOnline);

        final bookData = await api.lookupBook(
          isbn,
          locale: Localizations.localeOf(context),
        );

        if (bookData != null) {
          bookTitle = bookData['title'] ?? 'Unknown Title';
          bookCoverUrl = bookData['cover_url'] as String?;

          // Build payload for deferred creation
          bookPayload = {
            'title': bookTitle,
            'author': bookData['authors'] != null
                ? (bookData['authors'] as List).join(', ')
                : bookData['author'] ?? '',
            'isbn': isbn,
            'publisher': bookData['publisher'],
            'publication_year': bookData['year'],
            'cover_url': bookData['cover_url'],
            'summary': bookData['summary'],
            'reading_status': 'to_read',
            if (widget.preSelectedShelfId != null)
              'subjects': [widget.preSelectedShelfId],
          };
        } else {
          // Book not found in metadata sources
          if (mounted) {
            if (_isOffline) {
              await _showOfflineDialog(isbn);
            } else {
              await _showBookNotFoundDialog(isbn);
            }
          }
          return;
        }
      }

      // 3. Cache the book locally (no DB write yet)
      _batchedIsbns.add(isbn);
      setState(() {
        _batchCount++;
        _lastAddedTitle = bookTitle ?? isbn;
        _lastScannedIsbn = isbn;
        _batchedBooks.add(
          _BatchedBook(
            isbn: isbn,
            title: bookTitle ?? isbn,
            coverUrl: bookCoverUrl,
            bookPayload: bookPayload,
            existingBook: existingBook,
          ),
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${bookTitle ?? isbn}'),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      debugPrint('Batch scan error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _isScanning = true;
          _isProcessingBatch = false;
        });
      }
    }
  }

  /// Persist all cached books to the database. Called when user taps "Done".
  Future<void> _commitBatchedBooks() async {
    if (_batchedBooks.isEmpty) {
      context.pop(false);
      return;
    }

    setState(() {
      _isScanning = false;
      _isCommitting = true;
      _commitProgress = 0.0;
    });

    controller.stop();

    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final copyRepo = Provider.of<CopyRepository>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);

    int successCount = 0;
    int errorCount = 0;

    for (int i = 0; i < _batchedBooks.length; i++) {
      final book = _batchedBooks[i];

      try {
        if (book.isNew) {
          final createdBook = await bookRepo.createBook(book.bookPayload!);
          final bookId = createdBook.id;

          if (bookId != null && widget.preSelectedCollectionId != null) {
            try {
              await api.addBookToCollection(
                widget.preSelectedCollectionId!.toString(),
                bookId,
              );
            } catch (e) {
              debugPrint('Error adding to collection: $e');
            }
          }
        } else if (book.existingBook != null) {
          final existing = book.existingBook!;
          final bookId = existing.id;

          // Add shelf tag if pre-selected
          if (widget.preSelectedShelfId != null && bookId != null) {
            final currentSubjects = existing.subjects ?? <String>[];
            if (!currentSubjects.contains(widget.preSelectedShelfId)) {
              final newSubjects = List<String>.from(currentSubjects)
                ..add(widget.preSelectedShelfId!);
              await bookRepo.updateBook(bookId, {'subjects': newSubjects});
            }
          }

          // Add to collection if specified
          if (bookId != null && widget.preSelectedCollectionId != null) {
            try {
              await api.addBookToCollection(
                widget.preSelectedCollectionId!.toString(),
                bookId,
              );
            } catch (e) {
              debugPrint('Error adding to collection: $e');
            }
          }

          // Create additional copy for existing owned books
          if (existing.owned) {
            await copyRepo.createCopy({
              'book_id': bookId,
              'status': 'available',
            });
          }
        }

        successCount++;
      } catch (e) {
        errorCount++;
        debugPrint('Error committing book "${book.title}": $e');
      }

      if (mounted) {
        setState(() {
          _commitProgress = (i + 1) / _batchedBooks.length;
        });
      }
    }

    if (successCount > 0 && mounted) {
      context.read<HubDirectoryProvider>().markCatalogDirty();
      context.read<BookRefreshNotifier>().refresh();
      context.read<FlashMessageProvider>().markHasBooks();
    }

    if (mounted) {
      if (errorCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'batch_scan_result')}: '
              '$successCount ✓, $errorCount ✗',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      context.pop(successCount > 0);
    }
  }

  Future<bool> _showDiscardConfirmation() async {
    final count = _batchedBooks.length;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'batch_scan_discard_title'),
        ),
        content: Text(
          '$count ${TranslationService.translate(context, 'batch_scan_discard_message')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              TranslationService.translate(context, 'batch_scan_discard'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<_ExistingBookAction> _showExistingBookDialog(Book book) async {
    final result = await showDialog<_ExistingBookAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                TranslationService.translate(
                  context,
                  'batch_scan_existing_title',
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (book.coverUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      book.coverUrl!,
                      width: 50,
                      height: 70,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const SizedBox(width: 50, height: 70),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    book.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(
                context,
                'batch_scan_existing_message',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _ExistingBookAction.skip),
            child: Text(
              TranslationService.translate(context, 'batch_scan_skip'),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, _ExistingBookAction.addCopy),
            icon: const Icon(Icons.add),
            label: Text(
              TranslationService.translate(context, 'batch_scan_add_copy'),
            ),
          ),
        ],
      ),
    );
    return result ?? _ExistingBookAction.skip;
  }

  void _removeFromBatch(int index) {
    final book = _batchedBooks[index];
    setState(() {
      _batchedBooks.removeAt(index);
      _batchedIsbns.remove(book.isbn);
      _batchCount = _batchedBooks.length;
      _lastAddedTitle = _batchedBooks.isNotEmpty
          ? _batchedBooks.last.title
          : null;
    });
  }

  void _showBookEditSheet(int startIndex, {bool reviewMode = false}) {
    int currentIndex = startIndex;
    bool shouldCommitOnClose = false;
    final titleCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    final publisherCtrl = TextEditingController();
    final yearCtrl = TextEditingController();

    void loadBook(int index) {
      final book = _batchedBooks[index];
      if (book.isNew) {
        titleCtrl.text = book.bookPayload?['title'] ?? '';
        authorCtrl.text = book.bookPayload?['author'] ?? '';
        publisherCtrl.text = book.bookPayload?['publisher'] ?? '';
        yearCtrl.text = book.bookPayload?['publication_year']?.toString() ?? '';
      } else {
        titleCtrl.text = book.title;
        authorCtrl.text = book.existingBook?.author ?? '';
        publisherCtrl.text = book.existingBook?.publisher ?? '';
        yearCtrl.text = book.existingBook?.publicationYear?.toString() ?? '';
      }
    }

    void saveBook(int index) {
      if (index >= _batchedBooks.length) return;
      final book = _batchedBooks[index];
      if (book.isNew && book.bookPayload != null) {
        book.bookPayload!['title'] = titleCtrl.text;
        book.bookPayload!['author'] = authorCtrl.text;
        book.bookPayload!['publisher'] = publisherCtrl.text.isEmpty
            ? null
            : publisherCtrl.text;
        final yearText = yearCtrl.text;
        book.bookPayload!['publication_year'] = yearText.isEmpty
            ? null
            : int.tryParse(yearText);
        book.title = titleCtrl.text.isNotEmpty ? titleCtrl.text : book.isbn;
      }
      setState(() {});
    }

    loadBook(currentIndex);

    // Pause scanning while editing
    setState(() => _isScanning = false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final book = _batchedBooks[currentIndex];
          final isFirst = currentIndex == 0;
          final isLast = currentIndex == _batchedBooks.length - 1;
          final isEditable = book.isNew;

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.75,
            decoration: BoxDecoration(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      if (_batchedBooks.length > 1)
                        Text(
                          '${currentIndex + 1}/${_batchedBooks.length}',
                          style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          saveBook(currentIndex);
                          Navigator.pop(ctx);
                        },
                      ),
                    ],
                  ),
                ),
                // Form content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom,
                    ),
                    child: ListView(
                      children: [
                        // Cover + ISBN row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: book.coverUrl != null
                                  ? Image.network(
                                      book.coverUrl!,
                                      width: 70,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _coverPlaceholder(),
                                    )
                                  : _coverPlaceholder(),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ISBN: ${book.isbn}',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (!isEditable)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade50,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          TranslationService.translate(
                                            context,
                                            'batch_scan_existing_title',
                                          ),
                                          style: TextStyle(
                                            color: Colors.blue.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // Editable fields for new books
                        if (isEditable) ...[
                          TextField(
                            controller: titleCtrl,
                            decoration: InputDecoration(
                              labelText: TranslationService.translate(
                                context,
                                'title_label',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: authorCtrl,
                            decoration: InputDecoration(
                              labelText: TranslationService.translate(
                                context,
                                'author_label',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: publisherCtrl,
                            decoration: InputDecoration(
                              labelText: TranslationService.translate(
                                context,
                                'publisher_label',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: yearCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: TranslationService.translate(
                                context,
                                'year_label',
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ] else ...[
                          // Read-only info for existing books
                          Text(
                            book.title,
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                          if (book.existingBook?.author != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                book.existingBook!.author!,
                                style: Theme.of(ctx).textTheme.bodyLarge,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Prev/Next navigation (review mode)
                if (reviewMode)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          if (!isFirst)
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.arrow_back),
                                label: Text(
                                  TranslationService.translate(
                                    context,
                                    'batch_scan_prev',
                                  ),
                                ),
                                onPressed: () {
                                  saveBook(currentIndex);
                                  currentIndex--;
                                  loadBook(currentIndex);
                                  setSheetState(() {});
                                },
                              ),
                            )
                          else
                            const Expanded(child: SizedBox()),
                          const SizedBox(width: 12),
                          if (!isLast)
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.arrow_forward),
                                label: Text(
                                  TranslationService.translate(
                                    context,
                                    'batch_scan_next',
                                  ),
                                ),
                                onPressed: () {
                                  saveBook(currentIndex);
                                  currentIndex++;
                                  loadBook(currentIndex);
                                  setSheetState(() {});
                                },
                              ),
                            )
                          else
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.save),
                                label: Text(
                                  '${TranslationService.translate(context, 'batch_scan_save')} '
                                  '(${_batchedBooks.length})',
                                ),
                                onPressed: () {
                                  saveBook(currentIndex);
                                  shouldCommitOnClose = true;
                                  Navigator.pop(ctx);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      // Do NOT dispose controllers here: the modal's widget tree may still
      // reference them during its closing animation (~300ms). They are local
      // variables and will be garbage collected once the closure is released.
      if (shouldCommitOnClose) {
        _commitBatchedBooks();
      } else if (mounted && !_isCommitting) {
        setState(() => _isScanning = true);
      }
    });
  }

  Widget _coverPlaceholder() {
    return Container(
      width: 70,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.book, size: 32),
    );
  }

  Future<void> _showBookNotFoundDialog(String isbn) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Colors.orange),
            const SizedBox(width: 8),
            Text(TranslationService.translate(context, 'book_not_found')),
          ],
        ),
        content: Text('ISBN: $isbn'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              // Navigate to add book screen with ISBN and pre-selected destination
              final extra = {
                'isbn': isbn,
                if (widget.preSelectedShelfId != null)
                  'shelfId': widget.preSelectedShelfId,
                if (widget.preSelectedCollectionId != null)
                  'collectionId': widget.preSelectedCollectionId,
              };
              context.push('/books/add', extra: extra);
            },
            icon: const Icon(Icons.edit),
            label: Text(
              TranslationService.translate(context, 'add_book_manually'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOfflineDialog(String isbn) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.wifi_off, color: Colors.orange),
            const SizedBox(width: 8),
            Text(TranslationService.translate(context, 'scan_offline_title')),
          ],
        ),
        content: Text(
          '${TranslationService.translate(context, 'scan_offline_message')}'
          '\n\nISBN: $isbn',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              final extra = {
                'isbn': isbn,
                if (widget.preSelectedShelfId != null)
                  'shelfId': widget.preSelectedShelfId,
                if (widget.preSelectedCollectionId != null)
                  'collectionId': widget.preSelectedCollectionId,
              };
              context.push('/books/add', extra: extra);
            },
            icon: const Icon(Icons.edit),
            label: Text(
              TranslationService.translate(context, 'add_book_manually'),
            ),
          ),
        ],
      ),
    );
  }

  void _showInvalidBarcodeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                TranslationService.translate(context, 'invalid_isbn_scanned'),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          TranslationService.translate(context, 'scan_instruction'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showIsbnInputDialog();
            },
            icon: const Icon(Icons.keyboard),
            label: Text(
              TranslationService.translate(context, 'enter_isbn_manually'),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/books/add');
            },
            icon: const Icon(Icons.edit),
            label: Text(
              TranslationService.translate(context, 'add_book_manually'),
            ),
          ),
        ],
      ),
    );
  }

  void _showIsbnInputDialog() {
    final isbnController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'enter_isbn_manually'),
        ),
        content: TextField(
          controller: isbnController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'ISBN',
            hintText: '978...',
            prefixIcon: const Icon(Icons.book),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              Navigator.pop(ctx);
              if (widget.batchMode) {
                _handleBatchScan(value);
              } else {
                context.push('/books/add', extra: {'isbn': value});
              }
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (isbnController.text.isNotEmpty) {
                final text = isbnController.text;
                Navigator.pop(ctx);
                if (widget.batchMode) {
                  _handleBatchScan(text);
                } else {
                  context.push('/books/add', extra: {'isbn': text});
                }
              }
            },
            child: Text(TranslationService.translate(context, 'confirm')),
          ),
        ],
      ),
    ).then((_) => isbnController.dispose());
  }

  Widget _buildPlaceholder(String title) {
    return Container(
      width: 58,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade700,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(4),
      child: Center(
        child: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 11),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanWindow = Rect.fromCenter(
      center: MediaQuery.of(context).size.center(Offset.zero),
      width: 280,
      height: 150,
    );

    return PopScope(
      canPop: !widget.batchMode || (_batchedBooks.isEmpty && !_isCommitting),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isCommitting) return;
        if (_batchedBooks.isNotEmpty) {
          final shouldDiscard = await _showDiscardConfirmation();
          if (shouldDiscard && mounted) {
            Navigator.of(context).pop(false);
          }
        }
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(
            widget.batchMode
                ? TranslationService.translate(context, 'batch_scan_title')
                : TranslationService.translate(context, 'scan_isbn_title'),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
              tooltip: TranslationService.translate(
                context,
                'tooltip_toggle_flashlight',
              ),
              onPressed: () {
                setState(() {
                  _isTorchOn = !_isTorchOn;
                });
                controller.toggleTorch();
              },
            ),
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: () => controller.switchCamera(),
              tooltip: TranslationService.translate(context, 'switch_camera'),
            ),
          ],
        ),
        body: Stack(
          children: [
            widget.scannerBuilder?.call(context, controller, _onDetect) ??
                MobileScanner(
                  controller: controller,
                  // fit: BoxFit.cover, // Ensure it covers screen
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) {
                    return Center(
                      child: Text(
                        'Error: ${error.errorCode}',
                        style: const TextStyle(color: Colors.red),
                      ),
                    );
                  },
                ),

            CustomPaint(
              painter: ScannerOverlayPainter(scanWindow),
              child: Container(),
            ),

            // Offline warning banner
            if (_isOffline)
              Positioned(
                top: 90,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade800.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          TranslationService.translate(
                            context,
                            'scan_offline_banner',
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Batch mode: scanned covers side panel (Gleeph-style)
            if (widget.batchMode && _batchedBooks.isNotEmpty)
              Positioned(
                left: 0,
                top: _isOffline ? 140 : 100,
                bottom: 160,
                width: 70,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    reverse: true,
                    itemCount: _batchedBooks.length,
                    itemBuilder: (context, index) {
                      final book = _batchedBooks[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: GestureDetector(
                          onTap: () => _showBookEditSheet(index),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: book.coverUrl != null
                                    ? Image.network(
                                        book.coverUrl!,
                                        width: 58,
                                        height: 80,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            _buildPlaceholder(book.title),
                                      )
                                    : _buildPlaceholder(book.title),
                              ),
                              Positioned(
                                top: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: () => _removeFromBatch(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.only(
                                        topRight: Radius.circular(4),
                                        bottomLeft: Radius.circular(8),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Batch mode: destination indicator at top
            if (widget.batchMode && _hasDestination)
              Positioned(
                top: _isOffline ? 140 : 100,
                left: 80,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.preSelectedShelfId != null
                            ? Icons.folder
                            : Icons.collections_bookmark,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _destinationLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Processing indicator (single book lookup)
            if (_isProcessingBatch)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),

            // Commit progress overlay (saving all books)
            if (_isCommitting)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: Colors.white,
                          value: _commitProgress,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${TranslationService.translate(context, 'batch_scan_saving')} '
                          '${(_commitProgress * _batchedBooks.length).ceil()}/${_batchedBooks.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Scan instruction
            Positioned(
              bottom: widget.batchMode ? 190 : 80,
              left: 20,
              right: 20,
              child: Text(
                TranslationService.translate(context, 'scan_instruction'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: [
                    Shadow(
                      offset: Offset(1, 1),
                      blurRadius: 2,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ),

            // Batch mode: counter and last added
            if (widget.batchMode)
              Positioned(
                bottom: 135,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_lastAddedTitle != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _lastAddedTitle!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 4),
                      Text(
                        '$_batchCount ${TranslationService.translate(context, 'books_added')}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Review button
            if (widget.batchMode && _batchedBooks.isNotEmpty)
              Positioned(
                bottom: 78,
                left: 50,
                right: 50,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.checklist, size: 18),
                  label: Text(
                    TranslationService.translate(context, 'batch_scan_review'),
                  ),
                  onPressed: _isCommitting
                      ? null
                      : () => _showBookEditSheet(0, reviewMode: true),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.9),
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: const BorderSide(color: Colors.white70),
                  ),
                ),
              ),

            // Bottom button
            Positioned(
              bottom: 30,
              left: 50,
              right: 50,
              child: widget.batchMode
                  ? ElevatedButton.icon(
                      icon: Icon(
                        _batchedBooks.isEmpty ? Icons.close : Icons.save,
                      ),
                      label: Text(
                        _batchedBooks.isEmpty
                            ? TranslationService.translate(context, 'done')
                            : '${TranslationService.translate(context, 'batch_scan_save')} (${_batchedBooks.length})',
                      ),
                      onPressed: _isCommitting
                          ? null
                          : () {
                              if (_batchedBooks.isEmpty) {
                                context.pop(false);
                              } else {
                                _commitBatchedBooks();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () {
                        context.push('/books/add');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.keyboard),
                          const SizedBox(width: 8),
                          Text(
                            TranslationService.translate(
                                  context,
                                  'btn_enter_manually',
                                ) ??
                                'Enter Manually',
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
}

class _BatchedBook {
  final String isbn;
  String title;
  final String? coverUrl;
  Map<String, dynamic>? bookPayload; // non-null for new books
  final Book? existingBook; // non-null for books already in library

  _BatchedBook({
    required this.isbn,
    required this.title,
    this.coverUrl,
    this.bookPayload,
    this.existingBook,
  });

  bool get isNew => bookPayload != null;
}

enum _ExistingBookAction { skip, addCopy }

class ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;

  ScannerOverlayPainter(this.scanWindow);

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, const Radius.circular(12)),
      );

    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut;

    // To create the hole, we need to use a layer composite or path difference.
    // Simpler approach for standard overlay:
    // Draw semi-transparent background everywhere EXCEPT the hole.

    // Actually, simple path operation:
    final backgroundWithHole = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(backgroundWithHole, Paint()..color = Colors.black54);

    // Draw border around the scan window
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(12)),
      borderPaint,
    );

    // Draw red line in center
    final linePaint = Paint()
      ..color = Colors.red.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawLine(
      Offset(scanWindow.left + 20, scanWindow.center.dy),
      Offset(scanWindow.right - 20, scanWindow.center.dy),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
