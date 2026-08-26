import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/book_repository.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/hub_directory_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../services/milestone_celebration.dart';
import '../utils/cover_camera_helper.dart';
import '../widgets/cached_book_cover.dart';
import '../providers/theme_provider.dart';
import '../utils/book_status.dart';
import '../models/book.dart';
import '../widgets/genre_chips_selector.dart';
import '../widgets/hierarchical_tag_selector.dart';
import '../models/tag.dart';
import '../widgets/collection_selector.dart';
import '../models/collection.dart';

import '../widgets/app_snack_bar.dart';
import '../widgets/book_complete_animation.dart';
import '../utils/isbn_validator.dart';

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
  late TextEditingController _pageCountController;
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
  TextEditingController?
  _authorAutocompleteController; // Autocomplete's own controller

  String _readingStatus = 'to_read';
  String?
  _originalReadingStatus; // Track original status to detect changes to 'read'

  String? _coverUrl;
  int _coverVersion = 0;
  bool _isEditing = true; // Always start in edit mode
  bool _isSaving = false;
  bool _isFetchingDetails = false;
  String? _lastChecksumWarningIsbn;
  bool _hasChanges = false;

  // Copy availability management
  String _copyStatus = 'available';
  String? _copyId;
  bool _owned = true; // Whether I own this book (controls copy creation)
  bool _private = false; // Whether this book is hidden from network peers
  Set<String> _highlightedFields = {};
  Timer? _highlightTimer;

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
    _pageCountController = TextEditingController(
      text: widget.book.pageCount?.toString() ?? '',
    );
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
      final collectionRepo = Provider.of<CollectionRepository>(
        context,
        listen: false,
      );
      final collections = await collectionRepo.getBookCollections(
        widget.book.id!,
      );
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

    // Initialize status based on the current status mode ; runs in
    // didChangeDependencies so context is available before build, preventing
    // an invalid default if the user is in inventory mode.
    final themeProvider = Provider.of<ThemeProvider>(context);
    final useInventoryStatuses = themeProvider.inventoryStatusesEnabled;

    // Get valid status values for the active mode
    final validStatuses = useInventoryStatuses
        ? librarianStatuses.map((s) => s.value).toList()
        : individualStatuses.map((s) => s.value).toList();

    // Use book status if valid, else default
    // Only set if not already set (to avoid implementation overriding user changes on hot reload/rebuilds)
    if (_originalReadingStatus == null) {
      var status =
          widget.book.readingStatus ?? getDefaultStatus(useInventoryStatuses);
      // Normalize legacy 'wanted' to 'wanting' for backward compatibility
      if (status == 'wanted') status = 'wanting';
      _readingStatus = validStatuses.contains(status)
          ? status
          : getDefaultStatus(useInventoryStatuses);
      _originalReadingStatus = _readingStatus;
      _owned = widget.book.owned;
      _private = widget.book.private;
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
    final isbn = IsbnValidator.clean(
      _isbnController.text,
    ).replaceAll(RegExp(r'[^0-9X]'), '');
    if ((isbn.length == 10 || isbn.length == 13) && !_isFetchingDetails) {
      if (!IsbnValidator.isValid(isbn) && isbn != _lastChecksumWarningIsbn) {
        _lastChecksumWarningIsbn = isbn;
        AppSnackBar.info(
          context,
          TranslationService.translate(context, 'isbn_checksum_warning'),
        );
      }
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
        final filled = <String>{};
        setState(() {
          if (_titleController.text.isEmpty &&
              (bookData['title'] ?? '').isNotEmpty) {
            _titleController.text = bookData['title']!;
            filled.add('title');
          }

          // Handle authors in fetch details (only if none set yet)
          if (_authors.isEmpty) {
            if (bookData['authors'] != null && bookData['authors'] is List) {
              _authors = List<String>.from(bookData['authors']);
              filled.add('author');
            } else if (bookData['author'] != null) {
              _authors = [bookData['author']];
              filled.add('author');
            }
            _authorController.text = _authors.join(', ');
          }

          if (_publisherController.text.isEmpty &&
              (bookData['publisher'] ?? '').isNotEmpty) {
            _publisherController.text = bookData['publisher']!;
            filled.add('publisher');
          }
          if (_yearController.text.isEmpty && bookData['year'] != null) {
            _yearController.text = bookData['year'].toString();
            filled.add('year');
          }
          if (_summaryController.text.isEmpty &&
              (bookData['summary'] ?? '').isNotEmpty) {
            _summaryController.text = bookData['summary']!;
            filled.add('summary');
          }
          if (_pageCountController.text.isEmpty &&
              bookData['page_count'] != null) {
            _pageCountController.text = bookData['page_count'].toString();
            filled.add('pageCount');
          }

          _highlightedFields = filled;
        });

        // Clear highlights after 2.5s
        _highlightTimer?.cancel();
        _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _highlightedFields = {});
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
    _pageCountController.dispose();
    _startedDateController.dispose();
    _finishedDateController.dispose();
    _priceController.dispose();
    _tagsController.dispose();
    // Dispose FocusNodes
    _titleFocusNode.dispose();
    _authorFocusNode.dispose();
    _highlightTimer?.cancel();
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

  /// Take a reading date back off the book.
  ///
  /// Neither reading date is mandatory: a book can be "read" without one, and
  /// the date picker has no way to answer "no date", so clearing has to be its
  /// own control.
  void _clearDate(TextEditingController controller) {
    setState(() => controller.clear());
  }

  /// A reading date: read-only text opened by the calendar picker, with a
  /// clear button once a date is set.
  Widget _buildReadingDateField(
    TextEditingController controller, {
    required String keyPrefix,
  }) {
    // No explicit color: the decoration theme owns the suffix icon tint,
    // including its focused and error states.
    const calendarIcon = Icon(Icons.calendar_today);
    return TextFormField(
      key: Key('${keyPrefix}_date_field'),
      // Display-only mirror of `controller`, which holds the ISO value.
      controller: TextEditingController(
        text: _formatDateForDisplay(controller.text),
      ),
      readOnly: true,
      onTap: () => _selectDate(context, controller),
      decoration: _buildInputDecoration(
        hint: TranslationService.translate(context, 'select_date'),
        suffixIcon: controller.text.isEmpty
            ? calendarIcon
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('${keyPrefix}_date_clear'),
                    icon: const Icon(Icons.close),
                    tooltip: TranslationService.translate(context, 'clear'),
                    onPressed: () => _clearDate(controller),
                  ),
                  calendarIcon,
                  const SizedBox(width: 12),
                ],
              ),
      ),
    );
  }

  Future<void> _saveBook() async {
    // Force the IME to commit any pending composition before we read the
    // text controllers. Without this, on iOS/Android the user can tap
    // Save while the keyboard still holds an uncommitted suggestion, and
    // `_authorAutocompleteController.text` reads as empty.
    FocusManager.instance.primaryFocus?.unfocus();

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

    // Sync authors: capture any pending text in the Autocomplete field
    final pendingAuthor = _authorAutocompleteController?.text.trim() ?? '';
    if (pendingAuthor.isNotEmpty && !_authors.contains(pendingAuthor)) {
      setState(() {
        _authors.add(pendingAuthor);
        _authorAutocompleteController?.clear();
      });
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
      'isbn': IsbnValidator.clean(_isbnController.text),
      'summary': _summaryController.text,
      'page_count': int.tryParse(_pageCountController.text),
      'reading_status': _readingStatus,
      'cover_url': _coverUrl,
      'author': _authors.isNotEmpty
          ? _authors.join(', ')
          : '', // _authors is the source of truth
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
      'private': _private,
      'price': _priceController.text.isNotEmpty
          ? double.tryParse(_priceController.text.replaceAll(',', '.'))
          : null, // Price for Bookseller profile
      'digital_formats': _selectedDigitalFormats,
    };

    try {
      if (widget.book.id == null) {
        throw Exception("Book ID is missing");
      }
      final levelsBefore = await MilestoneCelebration.snapshot();
      await bookRepo.updateBook(widget.book.id!, bookData);
      if (mounted) {
        context.read<HubDirectoryProvider>()
          ..markCatalogDirty()
          ..syncCatalogIfDirty();

        // Celebrate any cap crossed by this edit (e.g. Cataloguer when tagging a
        // book, or Reader when changing its status to "read").
        MilestoneCelebration.celebrate(context, levelsBefore);
      }

      // If not owned anymore, delete all copies.
      // If owned and copy exists, update its status.
      // If owned and no copy exists, create one.
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
      } else {
        // Owned but no copy exists yet - create one
        final newCopy = await copyRepo.createCopy({
          'book_id': widget.book.id!,
          'status': _copyStatus,
        });
        _copyId = newCopy.id;
      }

      // Update collections
      if (widget.book.id != null) {
        final collectionRepo = Provider.of<CollectionRepository>(
          context,
          listen: false,
        );
        await collectionRepo.updateBookCollections(
          widget.book.id!,
          _selectedCollections.map((c) => c.id).toList(),
        );
      }

      if (mounted) {
        // A saved edit (fields and collection membership) must stale the
        // recommendation caches like any other catalogue mutation; series
        // membership feeds the external discovery lookups (ADR-060).
        context.read<BookRefreshNotifier>().refresh();
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
            _pageCountController.text = updatedBook.pageCount?.toString() ?? '';
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
        // Popping with `true` only refreshes the list the user came back to.
        // Every other cache keyed on the catalogue (recommendations,
        // favorites) listens on the notifier instead, and a deletion that
        // skipped it left the deleted book in the suggestion surfaces.
        context.read<BookRefreshNotifier>().refresh();
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

  Widget _buildEditMode() {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'edit_book_title')),
        // Back button
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: TranslationService.translate(context, 'back'),
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
          const SizedBox(width: 8),
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
                : ElevatedButton.icon(
                    onPressed: _isFetchingDetails ? null : _saveBook,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      TranslationService.translate(context, 'save_changes') ??
                          'Save',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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

              // Title
              _buildLabel(
                TranslationService.translate(context, 'title_label'),
                icon: Icons.auto_stories,
              ),
              TextFormField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                textInputAction: TextInputAction.next,
                decoration: _buildInputDecoration(
                  hint: TranslationService.translate(
                    context,
                    'enter_book_title',
                  ),
                  fieldKey: 'title',
                ),
                validator: (value) => value == null || value.isEmpty
                    ? TranslationService.translate(context, 'enter_title_error')
                    : null,
              ),
              _buildSectionDivider(),

              // Author
              _buildLabel(
                TranslationService.translate(context, 'author_label') ??
                    'Author',
                helperText: TranslationService.translate(
                  context,
                  'author_helper',
                ),
                icon: Icons.person_outline,
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
                      _authorAutocompleteController = textEditingController;
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: _buildInputDecoration(
                          hint: _authors.isNotEmpty
                              ? TranslationService.translate(
                                      context,
                                      'author_hint_add',
                                    ) ??
                                    'Add another author...'
                              : TranslationService.translate(
                                      context,
                                      'enter_author',
                                    ) ??
                                    'Enter author name',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: TranslationService.translate(
                              context,
                              'tooltip_add_author',
                            ),
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
              if (_authors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _authors.map((author) {
                      return Chip(
                        label: Text(author),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          setState(() {
                            _authors.remove(author);
                            _authorController.text = _authors.join(', ');
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              _buildSectionDivider(),

              // ISBN
              _buildLabel(
                TranslationService.translate(context, 'isbn_label'),
                icon: Icons.qr_code,
              ),
              TextFormField(
                controller: _isbnController,
                textInputAction: TextInputAction.next,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  letterSpacing: 2.0,
                ),
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
              _buildSectionDivider(),

              // Cover
              _buildCoverSection(),
              _buildSectionDivider(),

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
                          icon: Icons.business,
                        ),
                        TextFormField(
                          controller: _publisherController,
                          textInputAction: TextInputAction.next,
                          decoration: _buildInputDecoration(
                            hint: TranslationService.translate(
                              context,
                              'publisher_hint',
                            ),
                            fieldKey: 'publisher',
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
                          icon: Icons.calendar_today,
                        ),
                        TextFormField(
                          controller: _yearController,
                          textInputAction: TextInputAction.next,
                          decoration: _buildInputDecoration(
                            hint: TranslationService.translate(
                              context,
                              'year_hint',
                            ),
                            fieldKey: 'year',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              _buildSectionDivider(),

              // Summary
              _buildLabel(
                TranslationService.translate(context, 'summary_label'),
                icon: Icons.notes,
              ),
              TextFormField(
                controller: _summaryController,
                decoration: _buildInputDecoration(
                  hint: TranslationService.translate(context, 'summary_hint'),
                  fieldKey: 'summary',
                ),
                maxLines: 4,
              ),
              _buildSectionDivider(),

              // Page count
              _buildLabel(
                TranslationService.translate(context, 'page_count_label'),
                icon: Icons.menu_book_outlined,
              ),
              TextFormField(
                controller: _pageCountController,
                textInputAction: TextInputAction.done,
                decoration: _buildInputDecoration(
                  hint: TranslationService.translate(
                    context,
                    'page_count_hint',
                  ),
                  fieldKey: 'pageCount',
                ),
                keyboardType: TextInputType.number,
              ),

              // Price field (Bookseller profile only)
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  if (!themeProvider.hasCommerce)
                    return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionDivider(),
                      _buildLabel(
                        TranslationService.translate(context, 'price_label') ??
                            'Price (EUR)',
                        icon: Icons.sell_outlined,
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
                    ],
                  );
                },
              ),
              _buildSectionDivider(),

              // Ownership toggle
              _buildToggleTile(
                activeIcon: Icons.library_books_rounded,
                inactiveIcon: Icons.bookmark_add_outlined,
                titleKey: 'own_this_book',
                subtitleKey: 'own_this_book_hint',
                value: _owned,
                activeColor: Theme.of(context).colorScheme.primary,
                onChanged: (v) => setState(() => _owned = v),
              ),

              // Formats Selection
              Consumer<ThemeProvider>(
                builder: (context, theme, _) {
                  if (!theme.digitalFormatsEnabled)
                    return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionDivider(),
                      _buildLabel(
                        TranslationService.translate(
                              context,
                              'digital_formats_label',
                            ) ??
                            'Formats',
                        helperText: TranslationService.translate(
                          context,
                          'digital_formats_helper',
                        ),
                        icon: Icons.layers_outlined,
                      ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilterChip(
                            label: Text(
                              TranslationService.translate(
                                    context,
                                    'format_paper',
                                  ) ??
                                  'Paper',
                            ),
                            selected: _selectedDigitalFormats.contains('paper'),
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
                          FilterChip(
                            label: Text(
                              TranslationService.translate(
                                    context,
                                    'format_ebook',
                                  ) ??
                                  'Ebook',
                            ),
                            selected: _selectedDigitalFormats.contains('ebook'),
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
                  );
                },
              ),
              _buildSectionDivider(),

              // Status
              _buildLabel(
                TranslationService.translate(context, 'status_label'),
                helperText: TranslationService.translate(
                  context,
                  'status_helper',
                ),
                icon: Icons.flag_outlined,
              ),
              Builder(
                builder: (context) {
                  final themeProvider = Provider.of<ThemeProvider>(context);
                  final useInventoryStatuses =
                      themeProvider.inventoryStatusesEnabled;
                  final statusOptions = getStatusOptions(
                    context,
                    useInventoryStatuses,
                  );

                  if (!statusOptions.any((s) => s.value == _readingStatus)) {
                    statusOptions.add(
                      BookStatus(
                        value: _readingStatus,
                        label: _readingStatus,
                        icon: Icons.help_outline,
                        color: Colors.grey,
                      ),
                    );
                  }

                  // The absence of a status is a chip like any other: it is
                  // what tells the reader why no chip is lit, and the book
                  // sheet has always offered it.
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: statusOptions.map((status) {
                      final isActive = status.value == _readingStatus;
                      return _buildStatusChip(
                        label: status.label,
                        icon: status.icon,
                        color: status.color,
                        isActive: isActive,
                        onTap: () => setState(() {
                          _readingStatus = isActive
                              ? noReadingStatus
                              : status.value;
                        }),
                      );
                    }).toList(),
                  );
                },
              ),

              // Copy Availability Status
              if (_copyId != null) ...[
                _buildSectionDivider(),
                _buildLabel(
                  TranslationService.translate(context, 'availability_label') ??
                      'Availability',
                  helperText: TranslationService.translate(
                    context,
                    'availability_helper',
                  ),
                  icon: Icons.inventory_2_outlined,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildStatusChip(
                      label:
                          TranslationService.translate(
                            context,
                            'availability_available',
                          ) ??
                          'Available',
                      icon: Icons.check_circle,
                      color: Colors.green,
                      isActive: _copyStatus == 'available',
                      onTap: () => setState(() => _copyStatus = 'available'),
                    ),
                    // "Loaned" only makes sense if the lending module is enabled,
                    // unless the copy is already in this state (don't hide the
                    // user's own data).
                    if (Provider.of<ThemeProvider>(
                          context,
                          listen: false,
                        ).canLendBooks ||
                        _copyStatus == 'loaned')
                      _buildStatusChip(
                        label:
                            TranslationService.translate(
                              context,
                              'availability_loaned',
                            ) ??
                            'Lent',
                        icon: Icons.call_made,
                        color: Colors.orange,
                        isActive: _copyStatus == 'loaned',
                        onTap: () => setState(() => _copyStatus = 'loaned'),
                      ),
                    // "Borrowed" only makes sense if the borrowing module is enabled,
                    // unless the copy is already in this state.
                    if (Provider.of<ThemeProvider>(
                          context,
                          listen: false,
                        ).canBorrowBooks ||
                        _copyStatus == 'borrowed')
                      _buildStatusChip(
                        label:
                            TranslationService.translate(
                              context,
                              'availability_borrowed',
                            ) ??
                            'Borrowed',
                        icon: Icons.call_received,
                        color: Colors.purple,
                        isActive: _copyStatus == 'borrowed',
                        onTap: () => setState(() => _copyStatus = 'borrowed'),
                      ),
                    _buildStatusChip(
                      label:
                          TranslationService.translate(
                            context,
                            'availability_lost',
                          ) ??
                          'Lost',
                      icon: Icons.help_outline,
                      color: Colors.red,
                      isActive: _copyStatus == 'lost',
                      onTap: () => setState(() => _copyStatus = 'lost'),
                    ),
                  ],
                ),
              ],

              // Reading Dates (Conditional)
              if (_readingStatus != 'to_read' &&
                  _readingStatus != 'wanting' &&
                  _readingStatus.isNotEmpty) ...[
                _buildSectionDivider(),
                _buildLabel(
                  TranslationService.translate(
                    context,
                    'started_reading_label',
                  ),
                  helperText: TranslationService.translate(
                    context,
                    'started_reading_helper',
                  ),
                  icon: Icons.play_arrow_outlined,
                ),
                _buildReadingDateField(
                  _startedDateController,
                  keyPrefix: 'started_reading',
                ),
              ],

              if (_readingStatus == 'read') ...[
                _buildSectionDivider(),
                _buildLabel(
                  TranslationService.translate(
                    context,
                    'finished_reading_label',
                  ),
                  helperText: TranslationService.translate(
                    context,
                    'finished_reading_helper',
                  ),
                  icon: Icons.check_circle_outline,
                ),
                _buildReadingDateField(
                  _finishedDateController,
                  keyPrefix: 'finished_reading',
                ),
              ],

              // === Section 4: Organization ===
              _buildSectionDivider(),

              // Genres: a closed list of suggestions that file the book on an
              // ordinary shelf under "Genre".
              GenreChipsSelector(
                selectedShelves: _selectedTags,
                onShelvesChanged: (shelves) {
                  setState(() {
                    _selectedTags = shelves;
                    _hasChanges = true;
                  });
                },
              ),
              const SizedBox(height: 16),

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
              _buildSectionDivider(),

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

              // Private toggle
              Consumer<ThemeProvider>(
                builder: (context, theme, _) {
                  if (!theme.allowPrivateBooks) return const SizedBox.shrink();
                  return Column(
                    children: [
                      _buildSectionDivider(),
                      _buildToggleTile(
                        activeIcon: Icons.visibility_off_rounded,
                        inactiveIcon: Icons.visibility_rounded,
                        titleKey: 'book_private',
                        subtitleKey: 'book_private_desc',
                        value: _private,
                        activeColor: Colors.amber.shade700,
                        onChanged: (v) => setState(() => _private = v),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 32),

              // Delete Button
              Center(
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _deleteBook,
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.7),
                  ),
                  label: Text(
                    TranslationService.translate(context, 'delete_book_btn'),
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.7),
                      fontSize: 13,
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

  void _evictCoverFromCache(String? coverUrl) {
    if (coverUrl == null || coverUrl.isEmpty) return;
    if (!coverUrl.startsWith('http')) {
      final fileImage = FileImage(File(coverUrl));
      imageCache.evict(fileImage);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final path = await CoverCameraHelper.takePhotoAndSave(
        bookId: widget.book.id,
      );
      if (path == null || !mounted) return;

      _evictCoverFromCache(_coverUrl);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      await bookRepo.updateBook(widget.book.id!, {'cover_url': path});

      if (!mounted) return;
      context.read<HubDirectoryProvider>()
        ..markCatalogDirty()
        ..syncCatalogIfDirty();
      setState(() {
        _coverUrl = path;
        _coverVersion++;
      });
      _hasChanges = true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'cover_photo_saved') ??
                'Cover photo saved',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[COVER-PHOTO-ERROR] edit._takePhoto: $e\n$st');
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

  Future<void> _pickCoverFromFile() async {
    try {
      final targetPath = await CoverCameraHelper.pickFromGalleryAndSave(
        bookId: widget.book.id,
      );
      if (targetPath == null) return;

      if (!mounted) return;
      _evictCoverFromCache(_coverUrl);
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      await bookRepo.updateBook(widget.book.id!, {'cover_url': targetPath});

      if (!mounted) return;
      context.read<HubDirectoryProvider>()
        ..markCatalogDirty()
        ..syncCatalogIfDirty();
      setState(() {
        _coverUrl = targetPath;
        _coverVersion++;
      });
      _hasChanges = true;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'cover_updated') ??
                'Cover updated',
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('[COVER-PHOTO-ERROR] edit._pickCoverFromFile: $e\n$st');
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

  Widget _buildCoverSection() {
    final hasCover = _coverUrl != null && _coverUrl!.isNotEmpty;
    final theme = Theme.of(context);

    Widget coverImage = hasCover
        ? _coverUrl!.startsWith('/')
              ? Image.file(
                  File(_coverUrl!),
                  key: ValueKey('$_coverUrl\_$_coverVersion'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
                )
              : CachedBookCover(
                  key: ValueKey('$_coverUrl\_$_coverVersion'),
                  imageUrl: _coverUrl!,
                  fit: BoxFit.cover,
                  placeholder: _buildCoverPlaceholder(),
                  errorWidget: _buildCoverPlaceholder(),
                  semanticLabel: _titleController.text.isNotEmpty
                      ? _titleController.text
                      : null,
                )
        : _buildCoverPlaceholder();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover thumbnail with shadow
        Container(
          width: 72,
          height: 108,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: coverImage,
          ),
        ),
        const SizedBox(width: 16),
        // Action buttons
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                TranslationService.translate(context, 'cover_label') ?? 'Cover',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (CoverCameraHelper.isCameraAvailable)
                    _buildCoverAction(
                      icon: Icons.camera_alt_outlined,
                      label:
                          TranslationService.translate(
                            context,
                            'cover_take_photo_short',
                          ) ??
                          'Photo',
                      onTap: _takePhoto,
                    ),
                  _buildCoverAction(
                    icon: Icons.photo_library_outlined,
                    label:
                        TranslationService.translate(
                          context,
                          'cover_choose_short',
                        ) ??
                        'Gallery',
                    onTap: _pickCoverFromFile,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.menu_book_rounded,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        size: 28,
      ),
    );
  }

  Widget _buildCoverAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String label, {String? helperText, IconData? icon}) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Padding(
      key: ValueKey('$_labelKeyPrefix$label'),
      padding: const EdgeInsets.only(top: 5, bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Icon(
                icon,
                size: 20,
                color: accentColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color.lerp(accentColor, Colors.black, 0.25),
                  ),
                ),
                if (helperText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    helperText,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _labelKeyPrefix = '_formLabel_';

  Widget _buildSectionDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DottedLinePainter(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color : theme.dividerColor,
              width: isActive ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? color : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : theme.colorScheme.onSurface,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData activeIcon,
    required IconData inactiveIcon,
    required String titleKey,
    required String subtitleKey,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      toggled: value,
      label: TranslationService.translate(context, titleKey),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: value
                  ? activeColor.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value
                    ? activeColor.withValues(alpha: 0.4)
                    : theme.dividerColor,
              ),
            ),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    value ? activeIcon : inactiveIcon,
                    key: ValueKey(value),
                    color: value
                        ? activeColor
                        : theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TranslationService.translate(context, titleKey),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        TranslationService.translate(context, subtitleKey),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color?.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: activeColor.withValues(alpha: 0.5),
                  activeThumbColor: activeColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    String? hint,
    Widget? suffixIcon,
    String? fieldKey,
  }) {
    final isHighlighted =
        fieldKey != null && _highlightedFields.contains(fieldKey);
    final borderColor = isHighlighted
        ? Colors.green
        : Theme.of(context).colorScheme.outline;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade600),
      suffixIcon: isHighlighted
          ? const Icon(
              Icons.check_circle_outline,
              color: Colors.green,
              size: 20,
            )
          : suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: borderColor,
          width: isHighlighted ? 1.5 : 1.0,
        ),
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

class _DottedLinePainter extends CustomPainter {
  final Color color;

  _DottedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    const dashWidth = 5.0;
    const dashSpace = 5.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DottedLinePainter oldDelegate) =>
      color != oldDelegate.color;
}
