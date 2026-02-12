import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../services/sync_service.dart';
import '../providers/theme_provider.dart';
import '../utils/book_status.dart';
import '../models/book.dart';

import '../services/search_cache.dart';
import '../widgets/plus_one_animation.dart';
import '../widgets/cached_book_cover.dart';
import '../widgets/collection_selector.dart';
import '../widgets/edition_picker_sheet.dart';
import '../models/collection.dart';

class AddBookScreen extends StatefulWidget {
  final String? isbn;
  final String? preSelectedCollectionId;
  final String? preSelectedShelfId;

  const AddBookScreen({
    super.key,
    this.isbn,
    this.preSelectedCollectionId,
    this.preSelectedShelfId,
  });

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final _formKey = GlobalKey<FormState>();

  final _searchCache = SearchCache();
  final _titleController = TextEditingController();
  final _publisherController = TextEditingController();
  final _publicationYearController = TextEditingController();
  final _isbnController = TextEditingController();
  final _summaryController = TextEditingController();
  final _priceController = TextEditingController(); // For Bookseller profile
  final _authorController = TextEditingController();
  String? _readingStatus; // Initialized in didChangeDependencies
  String? _coverUrl;
  List<dynamic>? _authorsData;
  bool _isFetchingDetails = false;
  bool _isSaving = false;
  String? _lastLookedUpIsbn; // Prevent duplicate lookups
  final List<String> _selectedTags = [];
  List<Collection> _selectedCollections = [];
  final List<String> _authors = []; // Multiple authors support
  Book? _duplicateBook; // Existing book with same ISBN
  bool _isDuplicate = false;
  late TextEditingController _tagsController;
  final FocusNode _titleFocusNode = FocusNode();
  List<String> _allAuthors = []; // For autocomplete
  final List<String> _selectedDigitalFormats = ['paper']; // Default to paper
  bool _isOwned = true; // Ownership status
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.isbn != null) {
      _isbnController.text = widget.isbn!;
      _fetchBookDetails(widget.isbn!);
    }
    _isbnController.addListener(_onIsbnChanged);
    _tagsController = TextEditingController();

    // Pre-select shelf/tag
    if (widget.preSelectedShelfId != null) {
      _selectedTags.add(widget.preSelectedShelfId!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAuthors();
      _loadPreSelectedCollection();
    });
  }

  Future<void> _loadPreSelectedCollection() async {
    if (widget.preSelectedCollectionId == null) return;
    try {
      final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
      final collections = await collectionRepo.getCollections();
      try {
        final collection = collections.firstWhere(
          (c) => c.id.toString() == widget.preSelectedCollectionId.toString(),
        );
        if (mounted) {
          setState(() {
            if (!_selectedCollections.any(
              (c) => c.id.toString() == collection.id.toString(),
            )) {
              _selectedCollections.add(collection);
            }
          });
        }
      } catch (_) {
        // Collection not found
      }
    } catch (e) {
      debugPrint('Error loading pre-selected collection: $e');
    }
  }

  Future<void> _loadAuthors() async {
    try {
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      final authors = await bookRepo.getAllAuthors();
      if (mounted) {
        setState(() {
          _allAuthors = authors;
        });
      }
    } catch (e) {
      debugPrint('Error loading authors for autocomplete: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize _readingStatus with correct default based on profile type
    if (_readingStatus == null) {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      _readingStatus = getDefaultStatus(themeProvider.isLibrarian);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _isbnController.removeListener(_onIsbnChanged);
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _publicationYearController.dispose();
    _isbnController.dispose();
    _summaryController.dispose();
    _priceController.dispose();
    // _tagsController is not disposed here because it gets reassigned to the
    // Autocomplete widget's internal controller (in fieldViewBuilder), which
    // Autocomplete manages and disposes itself.
    _titleFocusNode.dispose();
    super.dispose();
  }

  void _onIsbnChanged() {
    if (!mounted || _isSaving) return;
    final isbn = _isbnController.text.replaceAll(RegExp(r'[^0-9X]'), '');

    // Reset last lookup if ISBN changed significantly (not just adding digits)
    if (_lastLookedUpIsbn != null && !isbn.startsWith(_lastLookedUpIsbn!)) {
      _lastLookedUpIsbn = null;
    }

    // Only lookup if valid length, not currently fetching, and not already looked up
    if ((isbn.length == 10 || isbn.length == 13) &&
        !_isFetchingDetails &&
        isbn != _lastLookedUpIsbn) {
      _fetchBookDetails(isbn);
    }
  }

  Future<void> _fetchBookDetails(String isbn) async {
    _lastLookedUpIsbn = isbn; // Prevent duplicate lookups
    if (!mounted) return;
    setState(() => _isFetchingDetails = true);
    try {
      // Check if this ISBN already exists in library
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      final api = Provider.of<ApiService>(context, listen: false);
      final existingBook = await bookRepo.findBookByIsbn(isbn);
      if (!mounted) return;
      if (existingBook != null) {
        setState(() {
          _duplicateBook = existingBook;
          _isDuplicate = true;
          _isFetchingDetails = false;
        });
        return; // Don't fetch external details, show warning instead
      }

      // Reset duplicate state if ISBN changed
      setState(() {
        _duplicateBook = null;
        _isDuplicate = false;
      });

      // Use backend (Inventaire with OpenLibrary cover enrichment)
      final bookData = await api.lookupBook(
        isbn,
        locale: Localizations.localeOf(context),
      );

      if (bookData != null && mounted) {
        setState(() {
          if (_titleController.text.isEmpty)
            _titleController.text = bookData['title'] ?? '';

          // Handle authors - only if user hasn't entered any
          if (_authors.isEmpty && _authorController.text.trim().isEmpty) {
            // Helper to check if author is a placeholder value
            bool isPlaceholderAuthor(String author) {
              final lower = author.toLowerCase().trim();
              return lower == 'unknown author' ||
                  lower == 'auteur inconnu' ||
                  lower == 'autor desconocido' ||
                  lower == 'unbekannter autor' ||
                  lower == 'unknown' ||
                  lower == 'inconnu' ||
                  lower.isEmpty;
            }

            if (bookData['authors'] != null && bookData['authors'] is List) {
              // Handle each author - split if contains comma
              for (final author in bookData['authors']) {
                if (author is String && author.contains(',')) {
                  // Split comma-separated authors into individual entries
                  _authors.addAll(
                    author
                        .split(',')
                        .map((a) => a.trim())
                        .where((a) => a.isNotEmpty && !isPlaceholderAuthor(a)),
                  );
                } else {
                  final authorStr = author.toString().trim();
                  if (!isPlaceholderAuthor(authorStr)) {
                    _authors.add(authorStr);
                  }
                }
              }
            } else if (bookData['author'] != null) {
              final authorStr = bookData['author'].toString();
              if (authorStr.contains(',')) {
                // Split comma-separated authors into individual entries
                _authors.addAll(
                  authorStr
                      .split(',')
                      .map((a) => a.trim())
                      .where((a) => a.isNotEmpty && !isPlaceholderAuthor(a)),
                );
              } else {
                final trimmed = authorStr.trim();
                if (!isPlaceholderAuthor(trimmed)) {
                  _authors.add(trimmed);
                }
              }
            }
            // Also set text controller for fallback/display if needed
            _authorController.text = _authors.join(', ');
          }

          if (_publisherController.text.isEmpty)
            _publisherController.text = bookData['publisher'] ?? '';
          if (_publicationYearController.text.isEmpty)
            _publicationYearController.text =
                bookData['year']?.toString() ?? '';
          if (_summaryController.text.isEmpty)
            _summaryController.text = bookData['summary'] ?? '';
          if (_coverUrl == null && bookData['cover_url'] != null) {
            _coverUrl = bookData['cover_url'];
          }
          if (bookData['authors_data'] != null) {
            _authorsData = bookData['authors_data'];
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_details_found'),
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_not_found') ??
                  'Book not found in database',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching ISBN: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'error_fetching_isbn') ??
                  'Error looking up ISBN. Please enter details manually.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingDetails = false);
    }
  }

  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) return;

    // Check for pending author
    if (_authorController.text.trim().isNotEmpty) {
      final pendingRaw = _authorController.text;
      // Only add if it's not already joined string of all authors (avoid duplication)
      if (pendingRaw != _authors.join(', ')) {
        final pending = pendingRaw.trim();
        if (!_authors.contains(pending)) {
          _authors.add(pending);
        }
      }
    }

    setState(() => _isSaving = true);

    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);
    final book = Book(
      title: _titleController.text,
      author: _authors.isNotEmpty
          ? _authors.join(', ')
          : _authorController.text,
      publisher: _publisherController.text,
      publicationYear: int.tryParse(_publicationYearController.text),
      isbn: _isbnController.text,
      readingStatus: _readingStatus,
      summary: _summaryController.text,
      coverUrl: _coverUrl,
      subjects: _selectedTags.isNotEmpty ? _selectedTags : null,
      price: _priceController.text.isNotEmpty
          ? double.tryParse(_priceController.text)
          : null,
      owned: _isOwned,
      digitalFormats: _selectedDigitalFormats.isNotEmpty
          ? _selectedDigitalFormats
          : null,
    );

    try {
      final createdBook = await bookRepo.createBook(book.toJson());
      final newBookId = createdBook.id;

      // Update collections if any are selected
      if (newBookId != null && _selectedCollections.isNotEmpty) {
        final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
        await collectionRepo.updateBookCollections(
          newBookId,
          _selectedCollections.map((c) => c.id).toList(),
        );
      }

      if (mounted) {
        // Remove listener before clearing to prevent _onIsbnChanged from firing
        _isbnController.removeListener(_onIsbnChanged);
        _debounce?.cancel();

        // Clear all form fields to prevent Android autofill from retaining values
        _titleController.clear();
        _authorController.clear();
        _publisherController.clear();
        _publicationYearController.clear();
        _isbnController.clear();
        _summaryController.clear();
        _priceController.clear();
        _tagsController.clear();

        // Reset all state variables
        _authors.clear();
        _selectedTags.clear();
        _selectedCollections.clear();
        _coverUrl = null;
        _authorsData = null;
        _isDuplicate = false;
        _duplicateBook = null;
        _lastLookedUpIsbn = null;
        _selectedDigitalFormats.clear();

        // Trigger sync with peers in background (dont await to keep UI snappy)
        try {
          Provider.of<SyncService>(context, listen: false).syncAllPeers();
        } catch (e) {
          debugPrint('Failed to trigger background sync: $e');
        }

        // Mario Bros-style +1 animation! 🎮
        PlusOneAnimation.show(context);

        // Small delay to let animation be visible before navigation
        await Future.delayed(const Duration(milliseconds: 400));
        if (mounted) {
          context.pop(newBookId); // Return the new book ID
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_saving_book')}: $e',
            ),
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(TranslationService.translate(context, 'add_book_title')),
        actions: [
          // Online search button - icon only on mobile, with label on desktop
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.travel_explore),
              tooltip: TranslationService.translate(
                context,
                'btn_search_online',
              ),
              onPressed: () async {
                final result = await context.push('/search/external');
                if (result == true && mounted) {
                  // Book was added from external search, pop back with result
                  context.pop(result);
                }
              },
            )
          else
            TextButton.icon(
              onPressed: () async {
                final result = await context.push('/search/external');
                if (result == true && mounted) {
                  // Book was added from external search, pop back with result
                  context.pop(result);
                }
              },
              icon: Icon(
                Icons.travel_explore,
                color: Theme.of(context).appBarTheme.foregroundColor,
              ),
              label: Text(
                TranslationService.translate(context, 'btn_search_online'),
                style: TextStyle(
                  color: Theme.of(context).appBarTheme.foregroundColor,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0, left: 8.0),
            child: _isSaving
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).appBarTheme.foregroundColor,
                      ),
                    ),
                  )
                : isMobile
                // Mobile: shorter button with just "Enregistrer"
                ? TextButton(
                    onPressed: _saveBook,
                    key: const Key('saveBookButton'),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor: Theme.of(
                        context,
                      ).appBarTheme.foregroundColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      TranslationService.translate(context, 'save'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  )
                // Desktop: full button
                : ElevatedButton(
                    onPressed: _saveBook,
                    key: const Key('saveBookButton'),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      elevation: 4,
                      shadowColor: Colors.black26,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              TranslationService.translate(
                                context,
                                'save_book',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            const SizedBox(height: 8),

            // Duplicate ISBN Warning Banner
            if (_isDuplicate && _duplicateBook != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            TranslationService.translate(
                                  context,
                                  'isbn_already_exists',
                                ) ??
                                'This book is already in your collection',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${_duplicateBook!.title}${_duplicateBook!.author != null ? ' - ${_duplicateBook!.author}' : ''}',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              context.push('/books/${_duplicateBook!.id}');
                            },
                            icon: const Icon(Icons.visibility),
                            label: Text(
                              TranslationService.translate(
                                    context,
                                    'view_existing',
                                  ) ??
                                  'View Book',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final copyRepo = Provider.of<CopyRepository>(
                                context,
                                listen: false,
                              );
                              try {
                                await copyRepo.createCopy({
                                  'book_id': _duplicateBook!.id,
                                  'status': 'available',
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        TranslationService.translate(
                                              context,
                                              'copy_added',
                                            ) ??
                                            'Copy added successfully',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  context.pop(_duplicateBook!.id);
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.add),
                            label: Text(
                              TranslationService.translate(
                                    context,
                                    'add_copy',
                                  ) ??
                                  'Add Copy',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Title
            _buildLabel(TranslationService.translate(context, 'title_label')),
            LayoutBuilder(
              builder: (context, constraints) {
                return RawAutocomplete<Map<String, dynamic>>(
                  textEditingController: _titleController,
                  focusNode: _titleFocusNode,
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    if (textEditingValue.text.isEmpty ||
                        textEditingValue.text.length < 3) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }

                    // Check cache first
                    final cached = _searchCache.get(textEditingValue.text);
                    if (cached != null) {
                      return cached;
                    }

                    // Debounce search
                    if (_debounce?.isActive ?? false) _debounce!.cancel();

                    final completer =
                        Completer<Iterable<Map<String, dynamic>>>();
                    _debounce = Timer(const Duration(milliseconds: 500), () async {
                      if (!mounted) {
                        if (!completer.isCompleted) {
                          completer.complete(
                            const Iterable<Map<String, dynamic>>.empty(),
                          );
                        }
                        return;
                      }
                      try {
                        // Use unified search via backend API (respects enabled sources)
                        final api = Provider.of<ApiService>(
                          context,
                          listen: false,
                        );
                        final results = await api.searchBooks(
                          query: textEditingValue.text,
                          lang: Localizations.localeOf(context).languageCode,
                          autocomplete: true,
                        );

                        // Filter out "Independently Published" (POD/self-published reprints)
                        final filteredResults = results.where((book) {
                          final publisher = book['publisher'] as String?;
                          return publisher != 'Independently Published';
                        }).toList();

                        // Cache the results
                        _searchCache.set(
                          textEditingValue.text,
                          filteredResults,
                        );

                        if (!completer.isCompleted) {
                          completer.complete(filteredResults);
                        }
                      } catch (e) {
                        debugPrint('Autocomplete Error: $e');
                        if (!completer.isCompleted) {
                          completer.complete(
                            const Iterable<Map<String, dynamic>>.empty(),
                          );
                        }
                      }
                    });

                    return completer.future;
                  },
                  displayStringForOption: (option) => option['title'] ?? '',
                  onSelected: (Map<String, dynamic> selection) async {
                    // Get current search query
                    final searchQuery = _titleController.text;

                    // Find all editions for this work from cached results
                    final editions = _findEditionsForWork(
                      selection,
                      searchQuery,
                    );

                    if (editions.length > 1) {
                      // Multiple editions found - show picker
                      final selectedEdition = await EditionPickerSheet.show(
                        context: context,
                        title: selection['title'] ?? '',
                        author: selection['author'] as String?,
                        editions: editions,
                      );

                      if (selectedEdition != null && mounted) {
                        _fillFormFromSelection(selectedEdition);
                      }
                    } else {
                      // Single edition - fill form directly
                      _fillFormFromSelection(selection);
                    }
                  },
                  fieldViewBuilder:
                      (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        return TextFormField(
                          controller: textEditingController,
                          key: const Key('titleField'),
                          focusNode: focusNode,
                          decoration: _buildInputDecoration(
                            hint: TranslationService.translate(
                              context,
                              'enter_book_title',
                            ),
                            suffixIcon: const Icon(Icons.search),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? TranslationService.translate(
                                  context,
                                  'enter_title_error',
                                )
                              : null,
                        );
                      },
                  optionsViewBuilder: (context, onSelected, options) {
                    final themeProvider = Provider.of<ThemeProvider>(
                      context,
                      listen: false,
                    );
                    final isJuniorReader = themeProvider.isKid;

                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4.0,
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (BuildContext context, int index) {
                              final option = options.elementAt(index);
                              final cover = option['cover_url'] as String?;
                              final author = option['author'] as String?;
                              final publisher = option['publisher'] as String?;
                              final language = option['language'] as String?;
                              final langLabel = _getLanguageLabel(language);

                              // For adults: show "Author • Publisher • Language"
                              // For kids: show just "Author" (simpler)
                              String subtitle = author ?? '';
                              if (!isJuniorReader) {
                                if (publisher != null && publisher.isNotEmpty) {
                                  if (subtitle.isNotEmpty) {
                                    subtitle += ' • $publisher';
                                  } else {
                                    subtitle = publisher;
                                  }
                                }
                                if (langLabel.isNotEmpty) {
                                  if (subtitle.isNotEmpty) {
                                    subtitle += ' • $langLabel';
                                  } else {
                                    subtitle = langLabel;
                                  }
                                }
                              }

                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4.0,
                                ),
                                child: ListTile(
                                  leading: SizedBox(
                                    width: 40,
                                    height: 60,
                                    child: Stack(
                                      children: [
                                        // 1. Fallback Colored Cover
                                        Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                _getCoverColor(
                                                  option['title'] ?? '',
                                                ),
                                                _getCoverColor(
                                                  option['title'] ?? '',
                                                ).withOpacity(0.7),
                                              ],
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              (option['title'] as String?)
                                                      ?.substring(0, 1)
                                                      .toUpperCase() ??
                                                  '',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 20,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // 2. Image
                                        if (cover != null && cover.isNotEmpty)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: cover,
                                              width: 40,
                                              height: 60,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  const SizedBox.shrink(),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      const SizedBox.shrink(),
                                            ),
                                          ),
                                        // 3. Source Badge
                                        if (option['source'] != null)
                                          Positioned(
                                            bottom: 0,
                                            right: 0,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 2,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: _getSourceColor(
                                                  option['source'],
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.3),
                                                    blurRadius: 2,
                                                    offset: const Offset(0, 1),
                                                  ),
                                                ],
                                              ),
                                              child: Text(
                                                _getSourceLabel(
                                                  option['source'],
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 7,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  title: Text(
                                    option['title'] ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: subtitle.isNotEmpty
                                      ? Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12),
                                        )
                                      : null,
                                  isThreeLine: false,
                                  dense: true,
                                  onTap: () => onSelected(option),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            // Author
            _buildLabel(TranslationService.translate(context, 'author_label')),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                return _allAuthors.where((String option) {
                  return option.toLowerCase().contains(
                    textEditingValue.text.toLowerCase(),
                  );
                });
              },
              fieldViewBuilder:
                  (
                    context,
                    textEditingController,
                    focusNode,
                    onFieldSubmitted,
                  ) {
                    // Keep reference to controller for manual adding
                    if (_authorController != textEditingController) {
                      // If we are replacing the controller, we should copy the text if any
                      // But usually Autocomplete creates its own.
                      // Let's just use the one provided by Autocomplete for the input
                    }
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: _buildInputDecoration(
                        hint: TranslationService.translate(
                          context,
                          'author_hint',
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            if (textEditingController.text.trim().isNotEmpty) {
                              setState(() {
                                final val = textEditingController.text.trim();
                                if (!_authors.contains(val)) {
                                  _authors.add(val);
                                }
                                textEditingController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      onFieldSubmitted: (String value) {
                        final trimmed = value.trim();
                        if (trimmed.isNotEmpty) {
                          setState(() {
                            if (!_authors.contains(trimmed)) {
                              _authors.add(trimmed);
                            }
                            textEditingController.clear();
                          });
                          // Keep focus for next entry
                          focusNode.requestFocus();
                        }
                      },
                    );
                  },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _authors.map((author) {
                return Chip(
                  label: Text(author),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() {
                      _authors.remove(author);
                    });
                  },
                );
              }).toList(),
            ),
            if (_authorsData != null &&
                _authorsData!.isNotEmpty &&
                (_authors.isNotEmpty ||
                    _authorController.text.trim().isNotEmpty)) ...[
              const SizedBox(height: 16),
              ..._authorsData!.map((author) {
                if (author is! Map) return const SizedBox.shrink();
                final name = author['name'] as String? ?? '';
                final bio = author['bio'] as String?;
                final imageUrl = author['image_url'] as String?;
                final birth = author['birth_year'] as String?;
                final death = author['death_year'] as String?;

                String lifeSpan = '';
                if (birth != null) lifeSpan += birth;
                if (death != null) {
                  lifeSpan += ' - $death';
                } else if (birth != null)
                  lifeSpan += ' - Present';

                if (bio == null && imageUrl == null && lifeSpan.isEmpty)
                  return const SizedBox.shrink();

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: CachedNetworkImage(
                                imageUrl: imageUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    const Icon(Icons.person, size: 40),
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (lifeSpan.isNotEmpty)
                                Text(
                                  lifeSpan,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              if (bio != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  bio,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 24),

            const SizedBox(height: 24),

            _buildLabel(TranslationService.translate(context, 'isbn_label')),
            TextFormField(
              key: const Key('isbnField'),
              controller: _isbnController,
              decoration: _buildInputDecoration(
                hint: TranslationService.translate(
                  context,
                  'enter_isbn_autofill',
                ),
                prefixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final result = await context.push<String>('/scan');
                    if (!mounted) return;
                    if (result != null && result.isNotEmpty) {
                      _isbnController.text = result;
                      // _onIsbnChanged listener already triggers _fetchBookDetails,
                      // so no need to call it again here.
                    }
                  },
                  tooltip: TranslationService.translate(
                    context,
                    'scan_isbn_title',
                  ),
                ),
                suffixIcon: _isFetchingDetails
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () =>
                            _fetchBookDetails(_isbnController.text),
                        tooltip: TranslationService.translate(
                          context,
                          'lookup_isbn',
                        ),
                      ),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            if (_coverUrl != null || (_titleController.text.isNotEmpty && !_isFetchingDetails && _isbnController.text.isNotEmpty))
              _buildCoverPreview(),
            const SizedBox(height: 12),

            // Publisher & Year
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(
                        TranslationService.translate(
                          context,
                          'publisher_label',
                        ),
                      ),
                      TextFormField(
                        controller: _publisherController,
                        key: const Key('publisherField'),
                        decoration: _buildInputDecoration(
                          hint: TranslationService.translate(
                            context,
                            'publisher_hint',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(
                        TranslationService.translate(context, 'year_label'),
                      ),
                      TextFormField(
                        controller: _publicationYearController,
                        key: const Key('yearField'),
                        decoration: _buildInputDecoration(
                          hint: TranslationService.translate(
                            context,
                            'year_hint',
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Summary
            _buildLabel(TranslationService.translate(context, 'summary_label')),
            TextFormField(
              key: const Key('summaryField'),
              controller: _summaryController,
              decoration: _buildInputDecoration(
                hint: TranslationService.translate(context, 'summary_hint'),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            // Price field (Bookseller profile only)
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, child) {
                if (!themeProvider.hasCommerce) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel(
                      TranslationService.translate(context, 'price_label'),
                    ),
                    TextFormField(
                      controller: _priceController,
                      decoration: _buildInputDecoration(
                        hint: '0.00',
                      ).copyWith(suffixText: themeProvider.currency),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),

            // Owned Checkbox
            CheckboxListTile(
              title: Text(
                TranslationService.translate(context, 'own_this_book') ??
                    'I own this book',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              subtitle: Text(
                TranslationService.translate(context, 'own_this_book_hint') ??
                    'Uncheck for wishlist items',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              value: _isOwned,
              onChanged: (value) {
                setState(() => _isOwned = value ?? true);
              },
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),

            // Formats Selection (Unified)
            Consumer<ThemeProvider>(
              builder: (context, theme, _) {
                if (!theme.digitalFormatsEnabled)
                  return const SizedBox.shrink();

                return Card(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(
                                context,
                                'digital_formats_label',
                              ) ??
                              'Formats',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            // Paper Chip
                            FilterChip(
                              label: Text(
                                TranslationService.translate(
                                      context,
                                      'format_paper',
                                    ) ??
                                    'Paper',
                              ),
                              selected: _selectedDigitalFormats.contains(
                                'paper',
                              ),
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedDigitalFormats.add('paper');
                                  } else {
                                    _selectedDigitalFormats.remove('paper');
                                  }
                                });
                              },
                              avatar: const Icon(Icons.menu_book, size: 18),
                            ),
                            // Digital Formats
                            FilterChip(
                              label: Text(
                                TranslationService.translate(
                                      context,
                                      'format_ebook',
                                    ) ??
                                    'Ebook',
                              ),
                              selected: _selectedDigitalFormats.contains(
                                'ebook',
                              ),
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedDigitalFormats.add('ebook');
                                  } else {
                                    _selectedDigitalFormats.remove('ebook');
                                  }
                                });
                              },
                              avatar: const Icon(Icons.tablet_mac, size: 18),
                            ),
                            FilterChip(
                              label: Text(
                                TranslationService.translate(
                                      context,
                                      'format_audiobook',
                                    ) ??
                                    'Audiobook',
                              ),
                              selected: _selectedDigitalFormats.contains(
                                'audiobook',
                              ),
                              onSelected: (bool selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedDigitalFormats.add('audiobook');
                                  } else {
                                    _selectedDigitalFormats.remove('audiobook');
                                  }
                                });
                              },
                              avatar: const Icon(Icons.headset, size: 18),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            _buildLabel(TranslationService.translate(context, 'status_label')),
            Builder(
              builder: (context) {
                final themeProvider = Provider.of<ThemeProvider>(
                  context,
                  listen: false,
                );
                final isLibrarian = themeProvider.isLibrarian;
                final statusOptions = getStatusOptions(context, isLibrarian);

                // Ensure current value is valid for this mode
                final validValue =
                    statusOptions.any((s) => s.value == _readingStatus)
                    ? _readingStatus
                    : statusOptions.first.value;
                if (validValue != _readingStatus) {
                  // Update in next frame to avoid setState during build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _readingStatus = validValue);
                  });
                }

                return DropdownButtonFormField<String>(
                  value: validValue,
                  decoration: _buildInputDecoration(),
                  items: statusOptions.map((status) {
                    return DropdownMenuItem<String>(
                      value: status.value,
                      child: Row(
                        children: [
                          Icon(status.icon, size: 20, color: status.color),
                          const SizedBox(width: 12),
                          Text(status.label),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _readingStatus = value),
                );
              },
            ),
            const SizedBox(height: 24),

            // Tags
            _buildLabel(TranslationService.translate(context, 'tags')),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                if (textEditingValue.text == '') {
                  return const Iterable<String>.empty();
                }

                try {
                  final tagRepo = Provider.of<TagRepository>(context, listen: false);
                  final tags = await tagRepo.getTags();
                  final tagNames = tags.map((t) => t.name).toList();

                  return tagNames.where((String option) {
                    return option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        ) &&
                        !_selectedTags.contains(option);
                  });
                } catch (e) {
                  return const Iterable<String>.empty();
                }
              },
              onSelected: (String selection) {
                setState(() {
                  final trimmed = selection.trim();
                  if (trimmed.isNotEmpty && !_selectedTags.contains(trimmed)) {
                    _selectedTags.add(trimmed);
                  }
                  _tagsController.clear();
                });
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                    _tagsController = controller;
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: _buildInputDecoration(
                        hint: TranslationService.translate(
                          context,
                          'add_tag_hint',
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            if (controller.text.trim().isNotEmpty) {
                              setState(() {
                                final val = controller.text.trim();
                                if (!_selectedTags.contains(val)) {
                                  _selectedTags.add(val);
                                }
                                controller.clear();
                              });
                            }
                          },
                        ),
                      ),
                      onFieldSubmitted: (String value) {
                        final trimmed = value.trim();
                        if (trimmed.isNotEmpty) {
                          setState(() {
                            if (!_selectedTags.contains(trimmed)) {
                              _selectedTags.add(trimmed);
                            }
                            controller.clear();
                          });
                          focusNode.requestFocus();
                        }
                      },
                    );
                  },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedTags.map((tag) {
                return Chip(
                  label: Text(tag),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() {
                      _selectedTags.remove(tag);
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Collections
            CollectionSelector(
              selectedCollections: _selectedCollections,
              onChanged: (collections) {
                setState(() {
                  _selectedCollections = collections;
                });
              },
            ),
            const SizedBox(height: 32),

            // Save Button moved to AppBar
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPreview() {
    final hasCover = _coverUrl != null && _coverUrl!.isNotEmpty;
    final borderColor = hasCover ? Colors.green : Colors.grey;
    final bgColor = hasCover ? Colors.green.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              height: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: hasCover
                    ? CachedBookCover(
                        imageUrl: _coverUrl!,
                        fit: BoxFit.cover,
                        placeholder: Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.image, color: Colors.grey),
                        ),
                        errorWidget: Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_not_supported, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasCover
                    ? TranslationService.translate(context, 'cover_found') ?? 'Cover found!'
                    : TranslationService.translate(context, 'no_cover_available') ?? 'No cover',
                style: TextStyle(
                  color: hasCover ? Colors.green.shade700 : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Theme.of(context).textTheme.bodyLarge?.color,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    String? hint,
    Widget? suffixIcon,
    Widget? prefixIcon,
  }) {
    final borderColor = Theme.of(context).colorScheme.outline;
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
      filled: true,
      fillColor: null, // Uses theme InputDecorationTheme
    );
  }

  Color _getSourceColor(String source) {
    if (source.contains('Inventaire')) return Colors.green;
    if (source.toLowerCase().contains('bnf')) return Colors.orange;
    if (source.contains('Google')) return Colors.red;
    return Colors.blue;
  }

  String _getSourceLabel(String source) {
    if (source.contains('Inventaire')) return 'INV';
    if (source.toLowerCase().contains('bnf')) return 'BNF';
    if (source.contains('Google')) return 'GB';
    return 'OL';
  }

  String _getLanguageLabel(String? langCode) {
    if (langCode == null || langCode.isEmpty) return '';
    final code = langCode.toLowerCase();
    const langMap = {
      'fr': 'FR',
      'fre': 'FR',
      'fra': 'FR',
      'french': 'FR',
      'en': 'EN',
      'eng': 'EN',
      'english': 'EN',
      'es': 'ES',
      'spa': 'ES',
      'spanish': 'ES',
      'de': 'DE',
      'ger': 'DE',
      'deu': 'DE',
      'german': 'DE',
      'it': 'IT',
      'ita': 'IT',
      'italian': 'IT',
      'pt': 'PT',
      'por': 'PT',
      'portuguese': 'PT',
      'nl': 'NL',
      'dut': 'NL',
      'nld': 'NL',
      'dutch': 'NL',
      'ru': 'RU',
      'rus': 'RU',
      'russian': 'RU',
      'ja': 'JA',
      'jpn': 'JA',
      'japanese': 'JA',
      'zh': 'ZH',
      'chi': 'ZH',
      'zho': 'ZH',
      'chinese': 'ZH',
    };
    return langMap[code] ??
        code.toUpperCase().substring(0, min(2, code.length));
  }

  /// Normalize a title for grouping by work (title + author)
  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Fill form fields from a selected book/edition
  void _fillFormFromSelection(Map<String, dynamic> selection) {
    setState(() {
      if (selection['title'] != null) {
        _titleController.text = selection['title'];
      }

      // Handle authors
      if (selection['authors'] != null && selection['authors'] is List) {
        _authors.clear();
        final list = selection['authors'] as List;
        _authors.addAll(list.map((e) => e.toString()));
        _authorController.text = _authors.join(', ');
      } else if (selection['author'] != null) {
        _authorController.text = selection['author'];
        _authors.clear();
        _authors.add(selection['author']);
      }

      if (selection['isbn'] != null) {
        _isbnController.text = selection['isbn'];
      }
      if (selection['publisher'] != null) {
        _publisherController.text = selection['publisher'];
      }
      if (selection['publication_year'] != null) {
        _publicationYearController.text = selection['publication_year']
            .toString();
      }
      if (selection['summary'] != null) {
        _summaryController.text = selection['summary'];
      }
      if (selection['cover_url'] != null) {
        _coverUrl = selection['cover_url'];
      }
    });
  }

  /// Find all editions for a work from cached results
  List<Map<String, dynamic>> _findEditionsForWork(
    Map<String, dynamic> selectedWork,
    String searchQuery,
  ) {
    // Get cached results for this query
    final cachedResults = _searchCache.get(searchQuery);
    if (cachedResults == null) return [selectedWork];

    final selectedTitle = _normalizeTitle(selectedWork['title'] ?? '');
    final selectedAuthor =
        (selectedWork['author'] as String?)?.toLowerCase().trim() ?? '';

    // Find all editions with matching title and author
    final editions = cachedResults.where((book) {
      final bookTitle = _normalizeTitle(book['title'] ?? '');
      final bookAuthor =
          (book['author'] as String?)?.toLowerCase().trim() ?? '';

      // Match by normalized title (author can be slightly different)
      if (bookTitle != selectedTitle) return false;

      // If both have authors, they should be similar
      if (selectedAuthor.isNotEmpty && bookAuthor.isNotEmpty) {
        // Check if one contains the other (handles "John Smith" vs "Smith, John")
        return bookAuthor.contains(selectedAuthor.split(' ').first) ||
            selectedAuthor.contains(bookAuthor.split(' ').first);
      }

      return true;
    }).toList();

    // If no matches found, return just the selected work
    return editions.isEmpty ? [selectedWork] : editions;
  }

  Color _getCoverColor(String title) {
    if (title.isEmpty) return Colors.grey;
    final random = Random(title.hashCode);
    return Color.fromARGB(
      255,
      random.nextInt(200),
      random.nextInt(200),
      random.nextInt(200),
    );
  }
}
