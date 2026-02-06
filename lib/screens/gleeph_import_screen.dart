import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../services/api_service.dart';
import '../models/tag.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';

/// Represents a book candidate for import
class GleephBookCandidate {
  final String isbn;
  String? title;
  String? author;
  String? coverUrl;
  String? publisher;
  int? year;
  bool isSelected;
  bool isAlreadyInLibrary;
  bool isLoading;
  bool metadataFailed;

  // Gleeph-specific data
  String? gleephStatus; // Raw status from Gleeph: "J'ai", "Wishlist", "Je lis", "J'ai lu"
  int? gleephRating; // Rating 1-5 from Gleeph

  // Mapped BiblioGenius data
  String? readingStatus; // Mapped status: to_read, reading, read, wanting
  int? userRating; // Converted to 0-10 scale
  bool owned;

  GleephBookCandidate({
    required this.isbn,
    this.title,
    this.author,
    this.coverUrl,
    this.publisher,
    this.year,
    this.isSelected = true,
    this.isAlreadyInLibrary = false,
    this.isLoading = true,
    this.metadataFailed = false,
    this.gleephStatus,
    this.gleephRating,
    this.readingStatus,
    this.userRating,
    this.owned = true,
  });

  /// Map Gleeph status to BiblioGenius reading_status and owned flag
  void mapGleephStatus() {
    switch (gleephStatus?.toLowerCase()) {
      case "j'ai":
      case 'owned':
      case 'possédé':
        readingStatus = 'to_read';
        owned = true;
        break;
      case 'wishlist':
      case 'envie':
      case 'à lire':
        readingStatus = 'wanting';
        owned = false;
        break;
      case 'je lis':
      case 'en cours':
      case 'reading':
        readingStatus = 'reading';
        owned = true;
        break;
      case "j'ai lu":
      case 'lu':
      case 'read':
        readingStatus = 'read';
        owned = true;
        break;
      default:
        // Default: owned but not read yet
        readingStatus = 'to_read';
        owned = true;
    }

    // Convert Gleeph rating (1-5) to BiblioGenius rating (0-10)
    if (gleephRating != null && gleephRating! > 0) {
      userRating = gleephRating! * 2; // 1->2, 2->4, 3->6, 4->8, 5->10
    }
  }
}

class GleephImportScreen extends StatefulWidget {
  const GleephImportScreen({super.key});

  @override
  State<GleephImportScreen> createState() => _GleephImportScreenState();
}

class _GleephImportScreenState extends State<GleephImportScreen> {
  late final WebViewController _controller;

  // States
  bool _isLoadingPage = true;
  bool _isExtracting = false;
  bool _isResolvingMetadata = false;
  bool _isImporting = false;
  String? _currentUrl;
  int _extractionBookCount = 0; // Books found during extraction scrolling

  // Data
  List<GleephBookCandidate> _candidates = [];
  int _resolvedCount = 0;
  int _importProgress = 0;
  int _importSuccessCount = 0;
  int _importSkippedCount = 0;
  int _importErrorCount = 0;
  String? _currentImportingTitle;

  // Shelf and status data
  String? _detectedGleephShelf; // Shelf name detected from Gleeph page
  String _selectedReadingStatus = "À lire"; // Reading status: À lire, Je lis, J'ai lu, Wishlist
  bool _selectedOwned = true; // Whether books are owned (J'ai)
  List<Tag> _availableShelves = []; // BiblioGenius shelves
  String? _selectedShelfName; // Target shelf for import (null = no shelf)
  bool _createNewShelf = false; // Whether to create a new shelf

  // View state
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoadingPage = true;
                _currentUrl = url;
              });
            }
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() {
                _isLoadingPage = false;
              });
              // Get the real URL from JavaScript (SPAs don't update the URL in NavigationDelegate)
              await _updateCurrentUrl();
            }
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse('https://gleeph.com'));

    // Start periodic URL check for SPA navigation
    _startUrlMonitor();
  }

  /// Periodically check the actual URL (for SPA navigation detection)
  void _startUrlMonitor() {
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      await _updateCurrentUrl();
      _startUrlMonitor(); // Continue monitoring
    });
  }

  /// Get the real current URL from the page via JavaScript
  Future<void> _updateCurrentUrl() async {
    try {
      final result = await _controller.runJavaScriptReturningResult('window.location.href');
      String url = result.toString();
      // Clean up the result (remove quotes)
      if (url.startsWith('"') && url.endsWith('"')) {
        url = url.substring(1, url.length - 1);
      }
      if (mounted && url != _currentUrl) {
        setState(() {
          _currentUrl = url;
        });
      }
    } catch (e) {
      // Ignore URL fetch errors
    }
  }

  /// Click "Voir plus" button if present (Gleeph uses this to load more books)
  Future<bool> _clickLoadMore() async {
    try {
      const script = '''
(function() {
  // First, try to find the "VOIR PLUS" button by text content
  var buttons = document.querySelectorAll('button, a, div[role="button"]');
  for (var i = 0; i < buttons.length; i++) {
    var text = (buttons[i].innerText || buttons[i].textContent || '').trim().toLowerCase();
    if (text === 'voir plus' || text === 'load more' || text === 'charger plus') {
      buttons[i].click();
      return "clicked";
    }
  }

  // Fallback: try common selectors
  var selectors = [
    'button[class*="load"]',
    'button[class*="more"]',
    '[class*="load-more"]',
    '[class*="loadmore"]',
    '[class*="voir-plus"]',
    '[class*="voirplus"]',
    'a[class*="load"]',
    '[class*="pagination"] a:last-child'
  ];

  for (var i = 0; i < selectors.length; i++) {
    try {
      var el = document.querySelector(selectors[i]);
      if (el && el.offsetParent !== null) {
        el.click();
        return "clicked";
      }
    } catch(e) {}
  }
  return "none";
})()
''';

      final result = await _controller.runJavaScriptReturningResult(script);
      return result.toString().contains('clicked');
    } catch (e) {
      return false;
    }
  }

  bool get _isOnLibraryPage {
    final url = _currentUrl?.toLowerCase() ?? '';

    // Check various URL patterns used by Gleeph
    return url.contains('/library') ||
        url.contains('/profile') ||
        url.contains('/bibliotheque') ||
        url.contains('/ma-bibliotheque') ||
        url.contains('/user/') ||
        url.contains('/shelf') ||
        url.contains('/etagere') ||
        url.contains('/@') ||  // Profile URLs like gleeph.com/@username
        url.contains('/books') ||
        url.contains('/livres') ||
        url.contains('/collection') ||
        // If on gleeph.com but not on home/login pages, likely on a user page
        (url.contains('gleeph.com') &&
         !url.endsWith('gleeph.com') &&
         !url.endsWith('gleeph.com/') &&
         !url.contains('/login') &&
         !url.contains('/signup') &&
         !url.contains('/register') &&
         !url.contains('/search'));
  }

  int get _newBooksCount =>
      _candidates.where((c) => !c.isAlreadyInLibrary && c.isSelected).length;

  int get _duplicatesCount =>
      _candidates.where((c) => c.isAlreadyInLibrary).length;

  /// Extract ISBNs from the current page using JavaScript
  Future<void> _extractIsbns({bool force = false}) async {
    if (!force && !_isOnLibraryPage) {
      // Show dialog offering to force extraction
      final shouldForce = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Page non reconnue'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cette page ne semble pas être une bibliothèque Gleeph.',
              ),
              const SizedBox(height: 8),
              Text(
                'URL: ${_currentUrl ?? "inconnue"}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              const Text(
                'Voulez-vous quand même tenter l\'extraction ?',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Forcer l\'extraction'),
            ),
          ],
        ),
      );

      if (shouldForce != true) return;
    }

    setState(() {
      _isExtracting = true;
      _candidates = [];
      _showPreview = false;
      _extractionBookCount = 0;
    });

    try {
      // Step 1: Scroll and collect ISBNs incrementally (handles virtualized lists)
      final Set<String> collectedIsbns = {};
      int noNewBooksCount = 0;
      int scrollCount = 0;
      const maxScrolls = 200; // Safety limit for very large libraries
      const maxNoNewBooks = 8; // Stop after 8 scrolls without new books

      // Script to extract ISBNs currently visible in DOM
      const extractVisibleIsbnsScript = '''
(function() {
  var isbns = [];
  var seen = {};

  // Method 1: Links with /ean/ pattern
  var links = document.querySelectorAll('a[href*="/ean/"]');
  for (var i = 0; i < links.length; i++) {
    var href = links[i].href;
    var parts = href.split('/ean/');
    if (parts.length > 1) {
      var ean = parts[1].split('/')[0].split('?')[0];
      // Accept ISBN-13 (13 digits) or ISBN-10 (10 chars, may end with X)
      if (ean && (ean.length === 13 || ean.length === 10) && /^[0-9]+[0-9X]?\$/.test(ean)) {
        if (!seen[ean]) {
          seen[ean] = true;
          isbns.push(ean);
        }
      }
    }
  }

  // Method 2: Links with /isbn/ pattern
  var isbnLinks = document.querySelectorAll('a[href*="/isbn/"]');
  for (var i = 0; i < isbnLinks.length; i++) {
    var href = isbnLinks[i].href;
    var parts = href.split('/isbn/');
    if (parts.length > 1) {
      var isbn = parts[1].split('/')[0].split('?')[0];
      if (isbn && (isbn.length === 13 || isbn.length === 10) && /^[0-9]+[0-9X]?\$/.test(isbn)) {
        if (!seen[isbn]) {
          seen[isbn] = true;
          isbns.push(isbn);
        }
      }
    }
  }

  // Method 2b: Look for ISBN in any URL segment (broader search)
  var allBookLinks = document.querySelectorAll('a[href*="gleeph"]');
  for (var i = 0; i < allBookLinks.length; i++) {
    var href = allBookLinks[i].href;
    // Look for 13-digit or 10-digit sequences in URL
    var matches = href.match(/\\/(97[89][0-9]{10}|[0-9]{9}[0-9X])(\\/|\\?|\$)/);
    if (matches && matches[1]) {
      if (!seen[matches[1]]) {
        seen[matches[1]] = true;
        isbns.push(matches[1]);
      }
    }
  }

  // Method 3: Look for ISBN in data attributes
  var elements = document.querySelectorAll('[data-isbn], [data-ean]');
  for (var i = 0; i < elements.length; i++) {
    var isbn = elements[i].getAttribute('data-isbn') || elements[i].getAttribute('data-ean');
    if (isbn && (isbn.length === 13 || isbn.length === 10) && /^[0-9]+[0-9X]?\$/.test(isbn)) {
      if (!seen[isbn]) {
        seen[isbn] = true;
        isbns.push(isbn);
      }
    }
  }

  // Method 4: Look for ISBN patterns in text (last resort)
  var bookCards = document.querySelectorAll('[class*="book"], [class*="card"], [class*="item"]');
  for (var i = 0; i < bookCards.length; i++) {
    var text = bookCards[i].innerText || '';
    var matches = text.match(/\\b(97[89][0-9]{10}|[0-9]{9}[0-9X])\\b/g);
    if (matches) {
      for (var j = 0; j < matches.length; j++) {
        if (!seen[matches[j]]) {
          seen[matches[j]] = true;
          isbns.push(matches[j]);
        }
      }
    }
  }

  // Debug: count total book-like elements on page
  var allLinks = document.querySelectorAll('a[href*="/ean/"], a[href*="/book/"], a[href*="/livre/"]');
  console.log('Gleeph extraction: found ' + isbns.length + ' ISBNs, ' + allLinks.length + ' book links total');

  return JSON.stringify(isbns);
})()
      ''';

      // Collect ISBNs from initial view
      try {
        final result = await _controller.runJavaScriptReturningResult(extractVisibleIsbnsScript);
        String cleaned = result.toString();
        if (cleaned.startsWith('"')) cleaned = cleaned.substring(1, cleaned.length - 1).replaceAll('\\"', '"');
        final List<dynamic> isbns = jsonDecode(cleaned);
        collectedIsbns.addAll(isbns.cast<String>());
      } catch (e) {
        // Ignore initial extraction errors
      }

      // Strategy: Click "Voir Plus" button repeatedly to load all books
      // Gleeph doesn't use infinite scroll - it uses a "Voir Plus" button
      bool foundMoreBooks = true;
      while (foundMoreBooks && scrollCount < maxScrolls) {
        scrollCount++;
        final previousCount = collectedIsbns.length;

        // Try clicking "Voir Plus" button first
        final clicked = await _clickLoadMore();
        if (clicked) {
          // Wait for new content to load
          await Future.delayed(const Duration(milliseconds: 1500));
        } else {
          // If no button found, scroll down to find it
          try {
            await _controller.runJavaScript('window.scrollTo(0, document.body.scrollHeight)');
          } catch (e) {
            // Ignore scroll errors
          }
          await Future.delayed(const Duration(milliseconds: 500));

          // Try clicking again after scrolling
          final clickedAfterScroll = await _clickLoadMore();
          if (clickedAfterScroll) {
            await Future.delayed(const Duration(milliseconds: 1500));
          }
        }

        // Extract ISBNs from current view and add to collection
        try {
          final result = await _controller.runJavaScriptReturningResult(extractVisibleIsbnsScript);
          String cleaned = result.toString();
          if (cleaned.startsWith('"')) cleaned = cleaned.substring(1, cleaned.length - 1).replaceAll('\\"', '"');
          final List<dynamic> isbns = jsonDecode(cleaned);
          collectedIsbns.addAll(isbns.cast<String>());
        } catch (e) {
          // Ignore extraction errors
        }

        // Check if we found new books
        if (collectedIsbns.length == previousCount) {
          noNewBooksCount++;
          if (noNewBooksCount >= maxNoNewBooks) {
            foundMoreBooks = false;
          }
        } else {
          noNewBooksCount = 0;
        }

        // Update UI with progress
        if (mounted && collectedIsbns.length != _extractionBookCount) {
          setState(() {
            _extractionBookCount = collectedIsbns.length;
          });
        }
      }

      // Scroll back to top
      await _controller.runJavaScript('window.scrollTo(0, 0)');
      await Future.delayed(const Duration(milliseconds: 300));

      // Convert collected ISBNs to list for further processing
      final List<String> isbnList = collectedIsbns.toList();

      // Step 2: Detect shelf name from page
      String? detectedShelf;
      try {
        const shelfDetectScript = '''
(function() {
  var shelfName = null;

  // Try to find shelf name from page title
  var pageTitle = document.querySelector('h1, h2, [class*="shelf-title"], [class*="page-title"], [class*="etagere"]');
  if (pageTitle) {
    var titleText = (pageTitle.innerText || '').trim();
    // Skip status-based titles
    if (!/^(j'ai( lu)?|je lis|wishlist|ma bibliothèque)\$/i.test(titleText)) {
      if (titleText && titleText.length > 0 && titleText.length < 100) {
        shelfName = titleText;
      }
    }
  }

  // Try breadcrumb for shelf name
  if (!shelfName) {
    var breadcrumb = document.querySelector('[class*="breadcrumb"] a:last-child, [class*="path"] span:last-child');
    if (breadcrumb) {
      var crumbText = (breadcrumb.innerText || '').trim();
      if (crumbText && crumbText.length > 0 && crumbText.length < 100) {
        shelfName = crumbText;
      }
    }
  }

  return shelfName || '';
})()
''';
        final shelfResult = await _controller.runJavaScriptReturningResult(shelfDetectScript);
        String shelfStr = shelfResult.toString();
        if (shelfStr.startsWith('"')) shelfStr = shelfStr.substring(1, shelfStr.length - 1);
        if (shelfStr.isNotEmpty) detectedShelf = shelfStr;
      } catch (e) {
        // Ignore shelf detection errors
      }

      if (isbnList.isEmpty) {
        _showSnackBar(
          'Aucun livre trouvé. Assurez-vous d\'être sur votre bibliothèque.',
          isError: true,
        );
        setState(() => _isExtracting = false);
        return;
      }

      // Store detected shelf name
      _detectedGleephShelf = detectedShelf;

      // Create candidates with default status (user can change in preview)
      setState(() {
        _candidates = isbnList.map((isbn) {
          final candidate = GleephBookCandidate(
            isbn: isbn,
            gleephStatus: _selectedReadingStatus,
            owned: _selectedOwned,
          );
          // Apply status mapping based on current selection
          switch (_selectedReadingStatus) {
            case "J'ai lu":
              candidate.readingStatus = 'read';
              break;
            case "Je lis":
              candidate.readingStatus = 'reading';
              break;
            case "Wishlist":
              candidate.readingStatus = 'wanting';
              break;
            default:
              candidate.readingStatus = 'to_read';
          }
          return candidate;
        }).toList();
        _isExtracting = false;
        _isResolvingMetadata = true;
        _resolvedCount = 0;
      });

      // Resolve metadata and check duplicates
      await _resolveAllMetadata();
    } catch (e) {
      _showSnackBar('Erreur lors de l\'extraction: $e', isError: true);
      setState(() => _isExtracting = false);
    }
  }

  /// Resolve metadata for all candidates
  Future<void> _resolveAllMetadata() async {
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);

    // First, get all existing books to check duplicates efficiently
    final existingBooks = await bookRepo.getBooks();
    final existingIsbns = existingBooks
        .where((b) => b.isbn != null)
        .map((b) => b.isbn!.replaceAll(RegExp(r'[^0-9X]'), ''))
        .toSet();

    // Build a map of existing books by ISBN for quick lookup
    final existingBooksMap = <String, Map<String, dynamic>>{};
    for (final book in existingBooks) {
      if (book.isbn != null) {
        final cleanIsbn = book.isbn!.replaceAll(RegExp(r'[^0-9X]'), '');
        existingBooksMap[cleanIsbn] = {
          'title': book.title,
          'author': book.author,
          'cover_url': book.coverUrl,
        };
      }
    }

    // Process candidates in batches of 5 for better UX
    const batchSize = 5;
    for (var i = 0; i < _candidates.length; i += batchSize) {
      final batch = _candidates.skip(i).take(batchSize).toList();

      await Future.wait(
        batch.map((candidate) => _resolveSingleCandidate(api, candidate, existingIsbns, existingBooksMap)),
      );

      if (mounted) {
        setState(() {
          _resolvedCount = (_resolvedCount + batch.length).clamp(0, _candidates.length);
        });
      }
    }

    // Load available shelves from BiblioGenius
    try {
      final tagRepo = Provider.of<TagRepository>(context, listen: false);
      _availableShelves = await tagRepo.getTags();

      // If a shelf was detected from Gleeph, check if it exists in BiblioGenius
      if (_detectedGleephShelf != null) {
        final matchingShelf = _availableShelves.where(
          (s) => s.name.toLowerCase() == _detectedGleephShelf!.toLowerCase()
        ).firstOrNull;

        if (matchingShelf != null) {
          _selectedShelfName = matchingShelf.name;
          _createNewShelf = false;
        } else {
          // Suggest creating new shelf with the detected name
          _selectedShelfName = _detectedGleephShelf;
          _createNewShelf = true;
        }
      }
    } catch (e) {
      // Ignore shelf loading errors
    }

    if (mounted) {
      setState(() {
        _isResolvingMetadata = false;
        _showPreview = true;
      });
    }
  }

  /// Resolve metadata for a single candidate
  Future<void> _resolveSingleCandidate(
    ApiService api,
    GleephBookCandidate candidate,
    Set<String> existingIsbns,
    Map<String, Map<String, dynamic>> existingBooksMap,
  ) async {
    try {
      // Check if already in library
      final cleanIsbn = candidate.isbn.replaceAll(RegExp(r'[^0-9X]'), '');
      if (existingIsbns.contains(cleanIsbn)) {
        candidate.isAlreadyInLibrary = true;
        candidate.isSelected = false;
        candidate.isLoading = false;
        // Fetch metadata from existing library book
        final existingBook = existingBooksMap[cleanIsbn];
        if (existingBook != null) {
          candidate.title = existingBook['title'] as String?;
          candidate.author = existingBook['author'] as String?;
          candidate.coverUrl = existingBook['cover_url'] as String?;
        }
        return;
      }

      // Lookup metadata
      final metadata = await api.lookupBook(candidate.isbn);
      if (metadata != null) {
        candidate.title = metadata['title'];
        candidate.author = metadata['author'];
        candidate.coverUrl = metadata['cover_url'];
        candidate.publisher = metadata['publisher'];
        candidate.year = metadata['year'];
      } else {
        candidate.metadataFailed = true;
        candidate.title = 'ISBN: ${candidate.isbn}';
      }
    } catch (e) {
      candidate.metadataFailed = true;
      candidate.title = 'ISBN: ${candidate.isbn}';
    } finally {
      candidate.isLoading = false;
    }
  }

  /// Start importing selected books
  Future<void> _startImport() async {
    final selectedCandidates =
        _candidates.where((c) => c.isSelected && !c.isAlreadyInLibrary).toList();

    if (selectedCandidates.isEmpty) {
      _showSnackBar('Aucun livre sélectionné pour l\'import.');
      return;
    }

    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importSuccessCount = 0;
      _importSkippedCount = 0;
      _importErrorCount = 0;
    });

    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);

    // Create new shelf if needed
    if (_createNewShelf && _selectedShelfName != null) {
      try {
        final tagRepo = Provider.of<TagRepository>(context, listen: false);
        await tagRepo.createTag(_selectedShelfName!);
        _createNewShelf = false; // Mark as created
      } catch (e) {
        // Continue anyway - books will be imported without shelf
      }
    }

    // Prepare subjects list for books
    final List<String>? subjects = _selectedShelfName != null
        ? [_selectedShelfName!]
        : null;

    for (final candidate in selectedCandidates) {
      if (!mounted) break;

      setState(() {
        _currentImportingTitle = candidate.title ?? candidate.isbn;
      });

      try {
        // Double-check it's not already in library (race condition protection)
        final existing = await bookRepo.findBookByIsbn(candidate.isbn);
        if (existing != null) {
          _importSkippedCount++;
          candidate.isAlreadyInLibrary = true;
        } else {
          // Create the book with mapped status, rating, and shelf
          await bookRepo.createBook({
            'isbn': candidate.isbn,
            'title': candidate.title,
            'author': candidate.author,
            'publisher': candidate.publisher,
            'publication_year': candidate.year,
            'cover_url': candidate.coverUrl,
            'owned': candidate.owned,
            'reading_status': candidate.readingStatus ?? 'to_read',
            if (candidate.userRating != null) 'user_rating': candidate.userRating,
            if (subjects != null) 'subjects': subjects,
          });
          _importSuccessCount++;
        }
      } catch (e) {
        _importErrorCount++;
      }

      if (mounted) {
        setState(() {
          _importProgress++;
        });
      }
    }

    if (mounted) {
      setState(() {
        _isImporting = false;
        _currentImportingTitle = null;
      });
      _showImportResults();
    }
  }

  void _showImportResults() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _importSuccessCount > 0 ? Icons.check_circle : Icons.info,
              color: _importSuccessCount > 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 12),
            const Text('Import terminé'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildResultRow(
              Icons.book,
              Colors.green,
              '$_importSuccessCount livre${_importSuccessCount > 1 ? 's' : ''} importé${_importSuccessCount > 1 ? 's' : ''}',
            ),
            if (_importSkippedCount > 0)
              _buildResultRow(
                Icons.skip_next,
                Colors.orange,
                '$_importSkippedCount déjà présent${_importSkippedCount > 1 ? 's' : ''}',
              ),
            if (_importErrorCount > 0)
              _buildResultRow(
                Icons.error_outline,
                Colors.red,
                '$_importErrorCount erreur${_importErrorCount > 1 ? 's' : ''}',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _showPreview = false;
                _candidates = [];
              });
            },
            child: const Text('Continuer l\'import'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/books');
            },
            child: const Text('Voir ma bibliothèque'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultRow(IconData icon, Color color, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(text),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _toggleSelectAll(bool selectAll) {
    setState(() {
      for (final c in _candidates) {
        if (!c.isAlreadyInLibrary) {
          c.isSelected = selectAll;
        }
      }
    });
  }

  Widget _buildWebViewScreen() {
    return Column(
      children: [
        // Instruction banner
        if (!_isOnLibraryPage && !_isLoadingPage && !_isExtracting)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade400, Colors.orange.shade600],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Comment importer depuis Gleeph :',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Connectez-vous à votre compte Gleeph\n'
                  '2. Accédez à votre bibliothèque\n'
                  '3. Allez dans l\'étagère à importer, filtrez si besoin par statut (J\'ai lu, Je lis...)\n'
                  '4. Cliquez sur "Extraire"',
                  style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tips_and_updates, color: Colors.yellow.shade200, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Astuce : Importez étagère par étagère et sélectionnez le statut correspondant dans l\'écran de prévisualisation.',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Ready banner
        if (_isOnLibraryPage && !_isLoadingPage && !_isExtracting)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade600],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Page bibliothèque détectée !',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Naviguez dans l\'étagère souhaitée puis cliquez sur "Extraire". Vous pourrez ensuite choisir le statut de lecture.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),

        // WebView
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),

              // Extraction overlay
              if (_isExtracting)
                _buildOverlay(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      const Text(
                        'Analyse de la page en cours...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Clic automatique sur "Voir Plus" pour charger tous les livres',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.book, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '$_extractionBookCount livres trouvés',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Metadata resolution overlay
              if (_isResolvingMetadata)
                _buildOverlay(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      const Text(
                        'Récupération des métadonnées...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_resolvedCount / ${_candidates.length} livres analysés',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 200,
                        child: LinearProgressIndicator(
                          value: _candidates.isEmpty
                              ? 0
                              : _resolvedCount / _candidates.length,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverlay({required Widget child}) {
    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: child,
        ),
      ),
    );
  }

  Widget _buildPreviewScreen(ThemeProvider themeProvider) {
    final newBooks = _candidates.where((c) => !c.isAlreadyInLibrary).toList();
    final duplicates = _candidates.where((c) => c.isAlreadyInLibrary).toList();

    return Container(
      decoration: BoxDecoration(
        gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
      ),
      child: Column(
        children: [
          // Summary header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.library_add,
                        color: Colors.green,
                        value: _newBooksCount.toString(),
                        label: 'À importer',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.library_books,
                        color: Colors.orange,
                        value: _duplicatesCount.toString(),
                        label: 'Déjà présents',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Status selector
                _buildStatusSelector(),
                const SizedBox(height: 12),
                // Shelf selector
                _buildShelfSelector(),
                const SizedBox(height: 12),
                // Select all / Deselect all
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _toggleSelectAll(true),
                      icon: const Icon(Icons.check_box, size: 18),
                      label: const Text('Tout sélectionner'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _toggleSelectAll(false),
                      icon: const Icon(Icons.check_box_outline_blank, size: 18),
                      label: const Text('Tout désélectionner'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Books list
          Expanded(
            child: _isImporting
                ? _buildImportingOverlay()
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      // New books section
                      if (newBooks.isNotEmpty) ...[
                        _buildSectionTitle('Nouveaux livres', Icons.add_circle, Colors.green),
                        ...newBooks.map((c) => _buildBookCard(c)),
                        const SizedBox(height: 16),
                      ],

                      // Duplicates section
                      if (duplicates.isNotEmpty) ...[
                        _buildSectionTitle(
                          'Déjà dans votre bibliothèque',
                          Icons.check_circle,
                          Colors.orange,
                        ),
                        ...duplicates.map((c) => _buildBookCard(c, isDuplicate: true)),
                      ],
                    ],
                  ),
          ),

          // Import button
          if (!_isImporting)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _newBooksCount > 0 ? _startImport : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.file_download),
                    label: Text(
                      _newBooksCount > 0
                          ? 'Importer $_newBooksCount livre${_newBooksCount > 1 ? 's' : ''}'
                          : 'Aucun livre à importer',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImportingOverlay() {
    final progress = _candidates.isEmpty
        ? 0.0
        : _importProgress / _candidates.where((c) => c.isSelected && !c.isAlreadyInLibrary).length;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            const Text(
              'Importation en cours...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            if (_currentImportingTitle != null)
              Text(
                _currentImportingTitle!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 16),
            Text(
              '$_importProgress / ${_candidates.where((c) => c.isSelected && !c.isAlreadyInLibrary).length}',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMiniStat(Icons.check, Colors.green, _importSuccessCount),
                const SizedBox(width: 16),
                _buildMiniStat(Icons.skip_next, Colors.orange, _importSkippedCount),
                const SizedBox(width: 16),
                _buildMiniStat(Icons.error_outline, Colors.red, _importErrorCount),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, Color color, int value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 4),
        Text(
          value.toString(),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookCard(GleephBookCandidate candidate, {bool isDuplicate = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isDuplicate
            ? null
            : () {
                setState(() {
                  candidate.isSelected = !candidate.isSelected;
                });
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Checkbox (only for non-duplicates)
              if (!isDuplicate)
                Checkbox(
                  value: candidate.isSelected,
                  onChanged: (value) {
                    setState(() {
                      candidate.isSelected = value ?? false;
                    });
                  },
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.orange.shade400,
                    size: 24,
                  ),
                ),

              // Cover image
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 45,
                  height: 65,
                  child: candidate.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: candidate.coverUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.book, color: Colors.grey),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.book, color: Colors.grey),
                          ),
                        )
                      : Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.book, color: Colors.grey),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Book info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      candidate.title ?? 'Titre inconnu',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isDuplicate ? Colors.grey : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (candidate.author != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        candidate.author!,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDuplicate
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (candidate.metadataFailed) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            size: 14,
                            color: Colors.orange.shade400,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Métadonnées non trouvées',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Display status badges
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (candidate.owned)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2, size: 10, color: Colors.orange.shade700),
                                const SizedBox(width: 3),
                                Text(
                                  "J'ai",
                                  style: TextStyle(fontSize: 9, color: Colors.orange.shade700, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        if (candidate.gleephStatus != null)
                          _buildStatusChip(candidate.gleephStatus!, candidate.readingStatus),
                      ],
                    ),
                  ],
                ),
              ),

              // ISBN badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  candidate.isbn.substring(candidate.isbn.length - 4),
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build status selector widget with ownership toggle and reading status
  Widget _buildStatusSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmark, size: 18, color: Colors.purple.shade600),
              const SizedBox(width: 8),
              Text(
                'Statut des livres',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.purple.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sélectionnez le statut correspondant à la page Gleeph extraite',
            style: TextStyle(
              fontSize: 11,
              color: Colors.purple.shade600,
            ),
          ),
          const SizedBox(height: 12),

          // Ownership toggle (J'ai)
          InkWell(
            onTap: () => _updateOwnership(!_selectedOwned),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _selectedOwned
                    ? Colors.orange.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _selectedOwned
                      ? Colors.orange.withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedOwned ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 20,
                    color: _selectedOwned ? Colors.orange.shade700 : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "J'ai (possédé)",
                    style: TextStyle(
                      fontWeight: _selectedOwned ? FontWeight.w600 : FontWeight.normal,
                      color: _selectedOwned ? Colors.orange.shade700 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '→ Crée une copie',
                    style: TextStyle(
                      fontSize: 11,
                      color: _selectedOwned ? Colors.orange.shade600 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Reading status selector
          Text(
            'Statut de lecture :',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.purple.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildReadingStatusOption("J'ai lu", Icons.check_circle, Colors.green),
              _buildReadingStatusOption("Je lis", Icons.auto_stories, Colors.blue),
              _buildReadingStatusOption("Wishlist", Icons.star_border, Colors.amber),
              _buildReadingStatusOption("À lire", Icons.library_books, Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  void _updateOwnership(bool owned) {
    setState(() {
      _selectedOwned = owned;
      // If selecting Wishlist, typically you don't own it
      // But allow override
      _applyStatusToAllCandidates();
    });
  }

  Widget _buildReadingStatusOption(String label, IconData icon, Color color) {
    final isSelected = _selectedReadingStatus == label;
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : color),
      label: Text(label),
      selected: isSelected,
      selectedColor: color,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: isSelected ? FontWeight.bold : null,
      ),
      onSelected: (_) {
        setState(() {
          _selectedReadingStatus = label;
          // If selecting Wishlist, suggest unchecking "J'ai"
          if (label == "Wishlist" && _selectedOwned) {
            _selectedOwned = false;
          }
          // If selecting other statuses, suggest checking "J'ai"
          if (label != "Wishlist" && !_selectedOwned) {
            _selectedOwned = true;
          }
          _applyStatusToAllCandidates();
        });
      },
    );
  }

  void _applyStatusToAllCandidates() {
    for (final candidate in _candidates) {
      // Map reading status
      switch (_selectedReadingStatus) {
        case "J'ai lu":
          candidate.readingStatus = 'read';
          break;
        case "Je lis":
          candidate.readingStatus = 'reading';
          break;
        case "Wishlist":
          candidate.readingStatus = 'wanting';
          break;
        case "À lire":
        default:
          candidate.readingStatus = 'to_read';
      }
      candidate.owned = _selectedOwned;
      candidate.gleephStatus = _selectedReadingStatus;
    }
  }

  /// Build shelf selector widget
  Widget _buildShelfSelector() {
    final hasDetectedShelf = _detectedGleephShelf != null;
    final shelfExists = _availableShelves.any(
      (s) => s.name.toLowerCase() == _selectedShelfName?.toLowerCase()
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_special, size: 18, color: Colors.blue.shade600),
              const SizedBox(width: 8),
              Text(
                'Étagère de destination',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          if (hasDetectedShelf) ...[
            const SizedBox(height: 4),
            Text(
              'Étagère détectée : $_detectedGleephShelf',
              style: TextStyle(
                fontSize: 12,
                color: Colors.blue.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // No shelf option
              ChoiceChip(
                label: const Text('Aucune'),
                selected: _selectedShelfName == null,
                onSelected: (_) {
                  setState(() {
                    _selectedShelfName = null;
                    _createNewShelf = false;
                  });
                },
              ),
              // Existing shelves
              ..._availableShelves.map((shelf) => ChoiceChip(
                label: Text(shelf.name),
                selected: _selectedShelfName == shelf.name && !_createNewShelf,
                onSelected: (_) {
                  setState(() {
                    _selectedShelfName = shelf.name;
                    _createNewShelf = false;
                  });
                },
              )),
              // Create new shelf option (if detected shelf doesn't exist)
              if (hasDetectedShelf && !shelfExists)
                ChoiceChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text('Créer "$_detectedGleephShelf"'),
                  selected: _createNewShelf,
                  selectedColor: Colors.green.shade100,
                  onSelected: (_) {
                    setState(() {
                      _selectedShelfName = _detectedGleephShelf;
                      _createNewShelf = true;
                    });
                  },
                ),
              // Manual new shelf option
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Nouvelle...'),
                onPressed: () => _showCreateShelfDialog(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Show dialog to create a new shelf
  Future<void> _showCreateShelfDialog() async {
    final controller = TextEditingController(text: _detectedGleephShelf ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle étagère'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nom de l\'étagère',
            hintText: 'Ex: Science-Fiction',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _selectedShelfName = result;
        _createNewShelf = true;
      });
    }
  }

  /// Build a chip showing the Gleeph status with color coding
  Widget _buildStatusChip(String gleephStatus, String? mappedStatus) {
    Color chipColor;
    IconData chipIcon;

    switch (mappedStatus) {
      case 'read':
        chipColor = Colors.green;
        chipIcon = Icons.check_circle;
        break;
      case 'reading':
        chipColor = Colors.blue;
        chipIcon = Icons.auto_stories;
        break;
      case 'wanting':
        chipColor = Colors.purple;
        chipIcon = Icons.bookmark_border;
        break;
      case 'to_read':
      default:
        chipColor = Colors.orange;
        chipIcon = Icons.library_books;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: chipColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chipIcon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(
            gleephStatus,
            style: TextStyle(
              fontSize: 10,
              color: chipColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_showPreview ? 'Prévisualisation' : 'Import Gleeph'),
        leading: IconButton(
          icon: Icon(Icons.adaptive.arrow_back),
          onPressed: () {
            if (_showPreview && !_isImporting) {
              setState(() => _showPreview = false);
            } else if (!_isImporting) {
              context.pop();
            }
          },
        ),
        actions: [
          if (_isLoadingPage && !_showPreview)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
      body: _showPreview
          ? _buildPreviewScreen(themeProvider)
          : _buildWebViewScreen(),
      floatingActionButton: (!_showPreview &&
              !_isExtracting &&
              !_isResolvingMetadata &&
              !_isLoadingPage)
          ? FloatingActionButton.extended(
              onPressed: _extractIsbns,
              backgroundColor: _isOnLibraryPage ? Colors.green : Colors.grey.shade600,
              icon: Icon(_isOnLibraryPage ? Icons.auto_awesome : Icons.help_outline),
              label: Text(_isOnLibraryPage ? 'Extraire' : 'Naviguez d\'abord'),
            )
          : null,
    );
  }
}
