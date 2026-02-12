import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../utils/book_status.dart';
import '../models/book.dart';
import '../widgets/hierarchical_tag_selector.dart';
import '../models/tag.dart';
import '../widgets/collection_selector.dart';
import '../models/collection.dart';

import '../widgets/book_complete_animation.dart';
import '../utils/global_keys.dart';

class EditBookScreen extends StatefulWidget {
  final Book book;
  final Collection? initialCollection;
  final String? initialSubject;

  const EditBookScreen({
    super.key,
    required this.book,
    this.initialCollection,
    this.initialSubject,
  });

  @override
  State<EditBookScreen> createState() => _EditBookScreenState();
}

class _EditBookScreenState extends State<EditBookScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _publisherController;
  late TextEditingController _yearController;
  late TextEditingController _isbnController;
  late TextEditingController _summaryController;
  late TextEditingController _startedDateController;
  late TextEditingController _finishedDateController;
  late TextEditingController _tagsController; // Add this
  late TextEditingController _priceController; // Price for Bookseller profile
  late Book _book;
  List<String> _selectedTags = []; // Add this
  final List<String> _selectedDigitalFormats = []; // Digital formats
  List<Collection> _selectedCollections = []; // Add this
  List<String> _authors = []; // Multiple authors support
  List<String> _allAuthors = []; // For autocomplete

  String _readingStatus = 'to_read';
  String?
  _originalReadingStatus; // Track original status to detect changes to 'read'

  String? _coverUrl;
  bool _isEditing = true; // Always start in edit mode
  bool _isSaving = false;
  bool _isFetchingDetails = false;
  bool _hasChanges = false;

  // Copy availability management
  String _copyStatus = 'available';
  int? _copyId;
  bool _owned = true; // Whether I own this book (controls copy creation)

  // FocusNodes - must be created once and disposed
  late FocusNode _titleFocusNode;
  late FocusNode _authorFocusNode;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.book.title);
    _authorController = TextEditingController(text: widget.book.author ?? '');

    // Initialize authors list
    if (widget.book.author != null && widget.book.author!.isNotEmpty) {
      _authors = widget.book.author!
          .split(RegExp(r',\s*'))
          .where((s) => s.isNotEmpty)
          .toList();
    }

    // Initialize digital formats
    if (widget.book.digitalFormats != null) {
      _selectedDigitalFormats.addAll(widget.book.digitalFormats!);
    }

    // Initialize FocusNodes
    _titleFocusNode = FocusNode();
    _authorFocusNode = FocusNode();

    _isbnController = TextEditingController(text: widget.book.isbn ?? '');
    _publisherController = TextEditingController(
      text: widget.book.publisher ?? '',
    );
    _yearController = TextEditingController(
      text: widget.book.publicationYear?.toString() ?? '',
    );
    _summaryController = TextEditingController(text: widget.book.summary ?? '');
    _tagsController =
        TextEditingController(); // Initialize tags input controller
    _startedDateController = TextEditingController(
      text: widget.book.startedReadingAt?.toIso8601String().split('T')[0] ?? '',
    );
    _finishedDateController = TextEditingController(
      text:
          widget.book.finishedReadingAt?.toIso8601String().split('T')[0] ?? '',
    );
    _book = widget.book;
    _coverUrl = widget.book.coverUrl;

    // Initialize tags
    _selectedTags = widget.book.subjects != null
        ? List.from(widget.book.subjects!)
        : [];

    // Auto-fill initial subject if provided and not already present
    if (widget.initialSubject != null && widget.initialSubject!.isNotEmpty) {
      if (!_selectedTags.contains(widget.initialSubject)) {
        _selectedTags.add(widget.initialSubject!);
      }
    }

    // Initialize price controller
    _priceController = TextEditingController(
      text: widget.book.price?.toString() ?? '',
    );

    // Get profile type from ThemeProvider after first frame
    // Add listener for ISBN changes
    // Add listener for ISBN changes
    _isbnController.addListener(_onIsbnChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAuthors();
      _loadCollections();
    });
  }

  Future<void> _loadCollections() async {
    // Auto-fill initial collection if provided
    if (widget.initialCollection != null) {
      setState(() {
        if (!_selectedCollections.any(
          (c) => c.id == widget.initialCollection!.id,
        )) {
          _selectedCollections.add(widget.initialCollection!);
        }
      });
    }

    if (widget.book.id == null) return;
    try {
      final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
      final collections = await collectionRepo.getBookCollections(widget.book.id!);
      if (mounted) {
        setState(() {
          // Merge with initial if present, avoiding duplicates
          for (var c in collections) {
            if (!_selectedCollections.any((existing) => existing.id == c.id)) {
              _selectedCollections.add(c);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading collections: $e');
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

    // Initialize status based on profile - doing this here ensures we have context access
    // and it runs before build, preventing the invalid 'to_read' default for librarians
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isLibrarian = themeProvider.isLibrarian;

    // Get valid status values for current profile
    final validStatuses = isLibrarian
        ? librarianStatuses.map((s) => s.value).toList()
        : individualStatuses.map((s) => s.value).toList();

    // Use book status if valid, else default
    // Only set if not already set (to avoid implementation overriding user changes on hot reload/rebuilds)
    if (_originalReadingStatus == null) {
      var status = widget.book.readingStatus ?? getDefaultStatus(isLibrarian);
      // Normalize legacy 'wanted' to 'wanting' for backward compatibility
      if (status == 'wanted') status = 'wanting';
      _readingStatus = validStatuses.contains(status)
          ? status
          : getDefaultStatus(isLibrarian);
      _originalReadingStatus = _readingStatus;
      _owned = widget.book.owned;
      _loadCopyStatus();
    }
  }

  Future<void> _loadCopyStatus() async {
    // ... existing implementation
    if (widget.book.id == null) return;
    try {
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      final copies = await copyRepo.getBookCopies(widget.book.id!);
      if (copies.isNotEmpty) {
        final firstCopy = copies.first;
        setState(() {
          _copyId = firstCopy.id;
          _copyStatus = firstCopy.status;
        });
        debugPrint('📦 Loaded copy: id=$_copyId, status=$_copyStatus');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load copy status: $e');
    }
  }

  void _onIsbnChanged() {
    if (!mounted || _isSaving) return;
    final isbn = _isbnController.text.replaceAll(RegExp(r'[^0-9X]'), '');
    if ((isbn.length == 10 || isbn.length == 13) && !_isFetchingDetails) {
      _fetchBookDetails(isbn);
    }
  }

  Future<void> _fetchBookDetails(String isbn) async {
    setState(() => _isFetchingDetails = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final bookData = await api.lookupBook(
        isbn,
        locale: Localizations.localeOf(context),
      );

      if (bookData != null && mounted) {
        setState(() {
          if (_titleController.text.isEmpty)
            _titleController.text = bookData['title'] ?? '';

          // Handle authors in fetch details
          if (bookData['authors'] != null && bookData['authors'] is List) {
            _authors = List<String>.from(bookData['authors']);
          } else if (bookData['author'] != null) {
            _authors = [bookData['author']];
          }
          _authorController.text = _authors.join(', ');

          if (_publisherController.text.isEmpty)
            _publisherController.text = bookData['publisher'] ?? '';
          if (_yearController.text.isEmpty)
            _yearController.text = bookData['year']?.toString() ?? '';
          if (_summaryController.text.isEmpty)
            _summaryController.text = bookData['summary'] ?? '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_details_found'),
            ),
          ),
        );
      }
    } catch (e) {
      // Ignore errors or show mild warning
      debugPrint('Error fetching ISBN: $e');
    } finally {
      if (mounted) setState(() => _isFetchingDetails = false);
    }
  }

  @override
  void dispose() {
    _isbnController.removeListener(_onIsbnChanged);
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _yearController.dispose();
    _isbnController.dispose();
    _summaryController.dispose();
    _startedDateController.dispose();
    _finishedDateController.dispose();
    _priceController.dispose();
    _tagsController.dispose();
    // Dispose FocusNodes
    _titleFocusNode.dispose();
    _authorFocusNode.dispose();
    super.dispose();
  }

  // ... keeping _selectDate, _formatDateForDisplay ...
  Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    // Parse existing date from controller if present (stored as ISO)
    DateTime? initialDate;
    if (controller.text.isNotEmpty) {
      initialDate = DateTime.tryParse(controller.text);
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        // Store as ISO format for parsing, but display will be human-readable
        controller.text = picked.toIso8601String().split('T')[0];
      });
    }
  }

  String _formatDateForDisplay(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '';
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _saveBook() async {
    // Check for pending tag in the controller that hasn't been added yet
    if (_tagsController.text.trim().isNotEmpty) {
      final pendingTag = _tagsController.text.trim();
      if (!_selectedTags.contains(pendingTag)) {
        setState(() {
          _selectedTags.add(pendingTag);
          _tagsController.clear();
        });
      }
    }

    // Check for pending author
    if (_authorController.text.trim().isNotEmpty) {
      // Only add if explicit add wasn't clicked but text remains
      // Avoid duplicating the joined string if it matches
      if (_authorController.text != _authors.join(', ')) {
        final pending = _authorController.text.trim();
        if (!_authors.contains(pending)) {
          setState(() => _authors.add(pending));
        }
      }
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    // Construct book data map manually for update
    final bookData = {
      'title': _titleController.text,
      'publisher': _publisherController.text,
      'publication_year': int.tryParse(_yearController.text),
      'isbn': _isbnController.text,
      'summary': _summaryController.text,
      'reading_status': _readingStatus,
      'cover_url': _coverUrl,
      'author': _authors.isNotEmpty
          ? _authors.join(', ')
          : _authorController.text, // Use joined authors
      'started_reading_at': _startedDateController.text.isNotEmpty
          ? DateTime.parse(_startedDateController.text).toIso8601String()
          : null,
      'finished_reading_at': _finishedDateController.text.isNotEmpty
          ? DateTime.parse(_finishedDateController.text).toIso8601String()
          : null,
      'subjects': _selectedTags.isEmpty
          ? null
          : _selectedTags, // Ensure null if empty for cleaner JSON
      'owned': _owned,
      'price': _priceController.text.isNotEmpty
          ? double.tryParse(_priceController.text.replaceAll(',', '.'))
          : null, // Price for Bookseller profile
      'digital_formats': _selectedDigitalFormats,
    };

    try {
      if (widget.book.id == null) {
        throw Exception("Book ID is missing");
      }
      await bookRepo.updateBook(widget.book.id!, bookData);

      // If not owned anymore, delete all copies. Otherwise update copy status.
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      if (!_owned) {
        try {
          final copies = await copyRepo.getBookCopies(widget.book.id!);
          for (var copy in copies) {
            if (copy.id != null) {
              await copyRepo.deleteCopy(copy.id!);
            }
          }
        } catch (e) {
          debugPrint('Error cleaning up copies for un-owned book: $e');
        }
      } else if (_copyId != null) {
        await copyRepo.updateCopy(_copyId!, {'status': _copyStatus});
      }

      // Update collections
      if (widget.book.id != null) {
        final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
        await collectionRepo.updateBookCollections(
          widget.book.id!,
          _selectedCollections.map((c) => c.id).toList(),
        );
      }

      if (mounted) {
        // Remove listener before syncing controllers to prevent
        // _onIsbnChanged from firing during setState (nested setState crash)
        _isbnController.removeListener(_onIsbnChanged);

        // Re-fetch the book from API to get confirmed server state
        try {
          final updatedBook = await bookRepo.getBook(widget.book.id!);
          if (!mounted) return;
          setState(() {
            _isSaving = false;
            _isEditing = false; // Return to view mode
            _hasChanges = true; // Mark as changed
            _book = updatedBook;

            // Sync controllers with server data
            _titleController.text = updatedBook.title;
            _authorController.text = updatedBook.author ?? '';
            _isbnController.text = updatedBook.isbn ?? '';
            _publisherController.text = updatedBook.publisher ?? '';
            _yearController.text =
                updatedBook.publicationYear?.toString() ?? '';
            _summaryController.text = updatedBook.summary ?? '';
            _readingStatus = updatedBook.readingStatus ?? 'to_read';
            _coverUrl = updatedBook.coverUrl;
            _selectedTags = updatedBook.subjects ?? [];
            _owned = updatedBook.owned;
            _priceController.text =
                updatedBook.price?.toString() ?? ''; // Sync price

            // Sync authors list
            if (updatedBook.author != null && updatedBook.author!.isNotEmpty) {
              _authors = updatedBook.author!
                  .split(RegExp(r',\s*'))
                  .where((s) => s.isNotEmpty)
                  .toList();
            }
          });
        } catch (e) {
          debugPrint('Error re-fetching book after save: $e');
          // Fallback to local state construction if fetch fails
          setState(() {
            _isSaving = false;
            _isEditing = false;
            _hasChanges = true;
          });
        }

        // 🎉 Book Complete celebration when status changed to "read"
        if (_readingStatus == 'read' && _originalReadingStatus != 'read') {
          BookCompleteCelebration.show(
            context,
            bookTitle: _titleController.text,
            xpEarned: 1, // 1 book = 1 unit of progress in backend
            subtitle: TranslationService.translate(
              context,
              'book_complete_celebration',
            ),
          );
          // Update original status so animation doesn't re-trigger
          _originalReadingStatus = 'read';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_updated'),
            ),
          ),
        );

        // Redirect to previous screen (book details)
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_updating_book')}: $e',
            ),
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteBook() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'delete_book_title')),
        content: Text(
          TranslationService.translate(context, 'delete_book_confirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              TranslationService.translate(context, 'delete_book_btn'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    try {
      await bookRepo.deleteBook(widget.book.id!);
      if (mounted) {
        context.pop(true); // Return true to indicate success (and refresh list)
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_deleting_book')}: $e',
            ),
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  // Tag tree dialog removed - replaced by HierarchicalTagSelector

  @override
  Widget build(BuildContext context) {
    // Only build edit mode, view mode logic is deprecated for this screen
    // as navigation now handles pushing this screen specifically for editing
    return _buildEditMode();
  }

  // Deprecated view mode removed for brevity and correctness

  Widget _buildStatusChip(String? status) {
    Color color;
    String label;
    switch (status) {
      case 'reading':
        color = Colors.blue;
        label = TranslationService.translate(context, 'currently_reading');
        break;
      case 'read':
        color = Colors.green;
        label = TranslationService.translate(context, 'read_status');
        break;
      case 'wanting':
        color = Colors.red;
        label = TranslationService.translate(context, 'wishlist_status');
        break;
      case 'borrowed':
        color = Colors.purple;
        label = TranslationService.translate(context, 'borrowed_label');
        break;
      default:
        color = Colors.grey;
        label = TranslationService.translate(context, 'to_read_status');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildEditMode() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'edit_book_title')),
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  GlobalKeys.rootScaffoldKey.currentState?.openDrawer();
                },
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // Signal back if changes were made
                  Navigator.of(context).pop(_hasChanges);
                },
              ),
        actions: [
          // Online search button for metadata enrichment
          if (isMobile)
            IconButton(
              icon: const Icon(Icons.travel_explore),
              tooltip: TranslationService.translate(
                context,
                'btn_search_online',
              ),
              onPressed: () => context.push('/search/external'),
            )
          else
            TextButton.icon(
              onPressed: () => context.push('/search/external'),
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
            padding: const EdgeInsets.only(right: 16.0),
            child: _isSaving
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                            Theme.of(context).appBarTheme.foregroundColor ??
                            Colors.white,
                      ),
                    ),
                  )
                : TextButton(
                    onPressed: _saveBook,
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      foregroundColor:
                          Theme.of(context).appBarTheme.foregroundColor ??
                          Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      TranslationService.translate(context, 'save_changes') ??
                          'Save',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      // Wrap in WillPopScope to handle system back button too
      body: WillPopScope(
        onWillPop: () async {
          Navigator.of(context).pop(_hasChanges);
          return false;
        },
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              const SizedBox(height: 8),

              // Title - Simple TextFormField (autocomplete not needed for edit, book already exists)
              _buildLabel(TranslationService.translate(context, 'title_label')),
              TextFormField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                decoration: _buildInputDecoration(
                  hint: TranslationService.translate(
                    context,
                    'enter_book_title',
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? TranslationService.translate(context, 'enter_title_error')
                    : null,
              ),
              const SizedBox(height: 24),

              // Author
              _buildLabel(
                TranslationService.translate(context, 'author_label') ??
                    'Author',
              ),
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
                      if (_authorController != textEditingController) {
                        // Sync logic if needed, but usually we just let Autocomplete handle its internal controller
                        // or we could assign it. But existing logic uses _authorController.
                        // Let's just use the one passed here.
                      }
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: _buildInputDecoration(
                          hint:
                              TranslationService.translate(
                                context,
                                'enter_author',
                              ) ??
                              'Enter author name',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add),
                            onPressed: () {
                              if (textEditingController.text
                                  .trim()
                                  .isNotEmpty) {
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
              const SizedBox(height: 24),

              // ISBN
              _buildLabel(TranslationService.translate(context, 'isbn_label')),
              TextFormField(
                controller: _isbnController,
                decoration: _buildInputDecoration(
                  hint: TranslationService.translate(context, 'enter_isbn'),
                  suffixIcon: _isFetchingDetails
                      ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 24),

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
                          controller: _yearController,
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
              _buildLabel(
                TranslationService.translate(context, 'summary_label'),
              ),
              TextFormField(
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
                  if (!themeProvider.hasCommerce)
                    return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(
                        TranslationService.translate(context, 'price_label') ??
                            'Price (EUR)',
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

              // Owned checkbox - controls copy creation

              // Owned checkbox - controls copy creation
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
                value: _owned,
                onChanged: (value) {
                  setState(() => _owned = value ?? true);
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
                                      _selectedDigitalFormats.remove(
                                        'audiobook',
                                      );
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

              // Status
              _buildLabel(
                TranslationService.translate(context, 'status_label'),
              ),
              Builder(
                builder: (context) {
                  final themeProvider = Provider.of<ThemeProvider>(context);
                  final isLibrarian = themeProvider.isLibrarian;
                  final statusOptions = getStatusOptions(context, isLibrarian);

                  // Safety check: ensure current value exists in options
                  if (!statusOptions.any((s) => s.value == _readingStatus)) {
                    // If mismatch, add a temporary option to prevent crash
                    statusOptions.add(
                      BookStatus(
                        value: _readingStatus,
                        label: _readingStatus,
                        icon: Icons.help_outline,
                        color: Colors.grey,
                      ),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    value: _readingStatus,
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
                    onChanged: (value) {
                      setState(() {
                        _readingStatus = value!;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 24),

              // Copy Availability Status
              if (_copyId != null) ...[
                _buildLabel(
                  TranslationService.translate(context, 'availability_label') ??
                      'Availability',
                ),
                DropdownButtonFormField<String>(
                  value: _copyStatus,
                  decoration: _buildInputDecoration(),
                  items: [
                    DropdownMenuItem(
                      value: 'available',
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 20,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            TranslationService.translate(
                                  context,
                                  'availability_available',
                                ) ??
                                'Available',
                          ),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'loaned',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.call_made,
                            size: 20,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            TranslationService.translate(
                                  context,
                                  'availability_loaned',
                                ) ??
                                'Lent',
                          ),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'borrowed',
                      child: Row(
                        children: [
                          Icon(
                            Icons.call_received,
                            size: 20,
                            color: Colors.purple,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            TranslationService.translate(
                                  context,
                                  'availability_borrowed',
                                ) ??
                                'Borrowed',
                          ),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'lost',
                      child: Row(
                        children: [
                          Icon(Icons.help_outline, size: 20, color: Colors.red),
                          const SizedBox(width: 12),
                          Text(
                            TranslationService.translate(
                                  context,
                                  'availability_lost',
                                ) ??
                                'Lost',
                          ),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _copyStatus = value!;
                    });
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Reading Dates (Conditional)
              if (_readingStatus != 'to_read' &&
                  _readingStatus != 'wanting') ...[
                _buildLabel(
                  TranslationService.translate(
                    context,
                    'started_reading_label',
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectDate(context, _startedDateController),
                  child: AbsorbPointer(
                    child: TextFormField(
                      controller: TextEditingController(
                        text: _formatDateForDisplay(
                          _startedDateController.text,
                        ),
                      ),
                      decoration: _buildInputDecoration(
                        hint: TranslationService.translate(
                          context,
                          'select_date',
                        ),
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (_readingStatus == 'read') ...[
                _buildLabel(
                  TranslationService.translate(
                    context,
                    'finished_reading_label',
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectDate(context, _finishedDateController),
                  child: AbsorbPointer(
                    child: TextFormField(
                      controller: TextEditingController(
                        text: _formatDateForDisplay(
                          _finishedDateController.text,
                        ),
                      ),
                      decoration: _buildInputDecoration(
                        hint: TranslationService.translate(
                          context,
                          'select_date',
                        ),
                        suffixIcon: const Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Tags
              HierarchicalTagSelector(
                selectedTags: _selectedTags,
                onTagsChanged: (tags) {
                  setState(() {
                    _selectedTags = tags;
                    _hasChanges = true;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Collections
              CollectionSelector(
                selectedCollections: _selectedCollections,
                onChanged: (collections) {
                  setState(() {
                    _selectedCollections = collections;
                    _hasChanges = true;
                  });
                },
              ),
              const SizedBox(height: 32),

              // Save Button
              // Save Button moved to AppBar
              const SizedBox(height: 16),

              // Delete Button
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _deleteBook,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  label: Text(
                    TranslationService.translate(context, 'delete_book_btn'),
                    style: const TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
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

  InputDecoration _buildInputDecoration({String? hint, Widget? suffixIcon}) {
    final borderColor = Theme.of(context).colorScheme.outline;
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
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
}
