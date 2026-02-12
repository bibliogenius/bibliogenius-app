import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:provider/provider.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../services/translation_service.dart';
import '../services/api_service.dart';
import '../utils/isbn_validator.dart';
import '../models/book.dart';

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
  }

  bool _isScanning = true;
  bool _isTorchOn = false;
  String? _lastScannedIsbn; // Prevent duplicate navigation for same ISBN

  // Batch mode state
  int _batchCount = 0;
  String? _lastAddedTitle;
  bool _isProcessingBatch = false;
  final List<_BatchedBook> _batchedBooks = [];

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
    if (_isProcessingBatch) return;

    setState(() {
      _isScanning = false;
      _isProcessingBatch = true;
    });

    try {
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      final api = Provider.of<ApiService>(context, listen: false);

      int? bookId;
      String? bookTitle;
      String? bookCoverUrl;

      // 1. Check if book already exists in library
      // This "findBookByIsbn" might be slow if library is huge, but safe for now.
      Book? existingBook = await bookRepo.findBookByIsbn(isbn);

      if (existingBook != null) {
        bookId = existingBook.id;
        bookTitle = existingBook.title;
        bookCoverUrl = existingBook.coverUrl;

        // If shelf (tag) is pre-selected, ensure book has it
        if (widget.preSelectedShelfId != null && bookId != null) {
          final currentSubjects = existingBook.subjects ?? <String>[];
          if (!currentSubjects.contains(widget.preSelectedShelfId)) {
            final newSubjects = List<String>.from(currentSubjects)
              ..add(widget.preSelectedShelfId!);
            await bookRepo.updateBook(bookId, {'subjects': newSubjects});
          }
        }
      } else {
        // 2. Not found locally, lookup metadata
        final bookData = await api.lookupBook(
          isbn,
          locale: Localizations.localeOf(context),
        );

        if (bookData != null) {
          bookTitle = bookData['title'] ?? 'Unknown Title';

          // Create the book
          final bookPayload = {
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

          final createdBook = await bookRepo.createBook(bookPayload);
          bookId = createdBook.id;
          bookCoverUrl = bookData['cover_url'] as String?;
        } else {
          // Book not found in metadata sources
          if (mounted) await _showBookNotFoundDialog(isbn);
          return; // Stop here, don't show success snackbar
        }
      }

      // 3. Add to collection if specified
      if (bookId != null) {
        if (widget.preSelectedCollectionId != null) {
          try {
            // Use addBookToCollection to append, not replace!
            await api.addBookToCollection(
              widget.preSelectedCollectionId!.toString(),
              bookId,
            );
          } catch (e) {
            // Ignore if already in collection or other minor error,
            // but log it.
            debugPrint('Error adding to collection: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Erreur ajout collection: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
      } else {
        // Book ID is null!
        throw Exception("Impossible de créer ou récupérer le livre (ID null)");
      }

      // 4. Create copy for EXISTING OWNED books only
      // New books already have a copy created by the backend when owned=true.
      // For existing books, we create an additional copy only if book is owned
      // (user may have multiple physical copies of books they own).
      if (existingBook != null && existingBook.owned) {
        final copyRepo = Provider.of<CopyRepository>(context, listen: false);
        await copyRepo.createCopy({'book_id': bookId, 'status': 'available'});
      }

      setState(() {
        _batchCount++;
        _lastAddedTitle = bookTitle ?? isbn;
        _lastScannedIsbn = isbn;
        _batchedBooks.add(_BatchedBook(
          title: bookTitle ?? isbn,
          coverUrl: bookCoverUrl,
        ));
      });

      // Show success feedback
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
      // Re-enable scanning after a short delay
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() {
          _isScanning = true;
          _isProcessingBatch = false;
        });
      }
    }
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

    return Scaffold(
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
            tooltip:
                TranslationService.translate(context, 'switch_camera') ??
                'Switch Camera',
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

          // Batch mode: scanned covers side panel (Gleeph-style)
          if (widget.batchMode && _batchedBooks.isNotEmpty)
            Positioned(
              left: 0,
              top: 100,
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
                      child: ClipRRect(
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
                    );
                  },
                ),
              ),
            ),

          // Batch mode: destination indicator at top
          if (widget.batchMode && _hasDestination)
            Positioned(
              top: 100,
              left: 80,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.9),
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

          // Processing indicator
          if (_isProcessingBatch)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),

          // Scan instruction
          Positioned(
            bottom: widget.batchMode ? 140 : 80,
            left: 20,
            right: 20,
            child: Text(
              TranslationService.translate(context, 'scan_instruction') ??
                  'Align barcode within the frame',
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
              bottom: 90,
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
                      '$_batchCount ${TranslationService.translate(context, 'books_added') ?? 'livres ajoutés'}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
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
                    icon: const Icon(Icons.done),
                    label: Text(
                      TranslationService.translate(context, 'done') ??
                          'Terminé',
                    ),
                    onPressed: () => context.pop(_batchCount > 0),
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
    );
  }
}

class _BatchedBook {
  final String title;
  final String? coverUrl;
  const _BatchedBook({required this.title, this.coverUrl});
}

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
