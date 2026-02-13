import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/book.dart';
import '../models/contact.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/copy_repository.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';
import 'scan_screen.dart';

/// Screen for borrowing a book from a contact.
/// Provides ISBN scanning, manual entry, and title search with autocomplete.
class BorrowBookScreen extends StatefulWidget {
  final Contact contact;

  const BorrowBookScreen({super.key, required this.contact});

  @override
  State<BorrowBookScreen> createState() => _BorrowBookScreenState();
}

class _BorrowBookScreenState extends State<BorrowBookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _isbnController = TextEditingController();
  final _titleFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isSearching = false;
  bool _isSelectingSuggestion = false; // Flag to prevent onChanged loop
  Map<String, dynamic>? _foundBook;
  Book? _existingBook; // Set when ISBN already exists in library
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  String? _errorMessage;

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _isbnController.dispose();
    _titleFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _scanIsbn() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScanScreen()),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _isbnController.text = result;
        _errorMessage = null;
      });
      await _lookupByIsbn(result);
    }
  }

  Future<void> _lookupByIsbn(String isbn) async {
    if (isbn.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _existingBook = null;
    });

    try {
      // Check if this ISBN already exists in library
      final bookRepo = Provider.of<BookRepository>(context, listen: false);
      final existing = await bookRepo.findBookByIsbn(isbn);
      if (!mounted) return;
      if (existing != null) {
        _isSelectingSuggestion = true;
        setState(() {
          _existingBook = existing;
          _titleController.text = existing.title;
          _authorController.text = existing.author ?? '';
          _isLoading = false;
        });
        _isSelectingSuggestion = false;
        return;
      }

      final api = Provider.of<ApiService>(context, listen: false);
      final bookData = await api.lookupBook(
        isbn,
        locale: Localizations.localeOf(context),
      );

      if (!mounted) return;

      if (bookData != null) {
        _isSelectingSuggestion = true;
        setState(() {
          _foundBook = bookData;
          _titleController.text = bookData['title'] ?? '';
          _authorController.text = _extractAuthor(bookData);
          _isLoading = false;
        });
        _isSelectingSuggestion = false;
      } else {
        setState(() {
          _foundBook = null;
          _isLoading = false;
          _errorMessage = TranslationService.translate(context, 'book_not_found');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  String _extractAuthor(Map<String, dynamic> bookData) {
    if (bookData['authors'] != null && bookData['authors'] is List) {
      final authors = bookData['authors'] as List;
      return authors.map((a) => a.toString()).join(', ');
    }
    return bookData['author']?.toString() ?? '';
  }

  void _onTitleChanged(String value) {
    // Skip if we're programmatically setting text from a suggestion
    if (_isSelectingSuggestion) return;

    if (value.length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;

      setState(() => _isSearching = true);

      try {
        final api = Provider.of<ApiService>(context, listen: false);
        final results = await api.searchBooks(
          query: value,
          lang: Localizations.localeOf(context).languageCode,
          autocomplete: true,
        );

        if (mounted) {
          setState(() {
            _suggestions = results.take(5).toList();
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _suggestions = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  void _selectSuggestion(Map<String, dynamic> book) {
    _isSelectingSuggestion = true; // Prevent onChanged from triggering search
    setState(() {
      _foundBook = book;
      _titleController.text = book['title'] ?? '';
      _authorController.text = _extractAuthor(book);
      _isbnController.text = book['isbn'] ?? book['isbn13'] ?? '';
      _suggestions = [];
    });
    _isSelectingSuggestion = false;
    // Remove focus from title field
    FocusScope.of(context).unfocus();
  }

  Future<void> _borrowBook() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final api = Provider.of<ApiService>(context, listen: false);

      // 1. Reuse existing book if detected during ISBN lookup
      int? bookId = _existingBook?.id;

      // 2. Otherwise create a new book
      if (bookId == null) {
        final isbn = _isbnController.text.trim();
        final bookData = {
          'title': _titleController.text,
          'author': _authorController.text.isEmpty ? null : _authorController.text,
          'isbn': isbn.isEmpty ? null : isbn,
          'cover': _foundBook?['cover'],
          'publisher': _foundBook?['publisher'],
          'year': _foundBook?['year'],
          'owned': false,
        };

        final bookResponse = await api.createBook(bookData);

        if (bookResponse.data is Map) {
          bookId = bookResponse.data['id'] ?? bookResponse.data['book']?['id'];
        }

        if (bookId == null) {
          throw Exception('Failed to get book ID from response');
        }
      }

      // 3. Create temporary copy with borrowed status
      // The copy tracks who we borrowed from in the notes field
      final borrowedFrom = TranslationService.translate(context, 'borrowed_from');
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      await copyRepo.createCopy({
        'book_id': bookId,
        'status': 'borrowed',
        'is_temporary': true,
        'notes': '$borrowedFrom: ${widget.contact.displayName} (ID: ${widget.contact.id})',
        'acquisition_date': DateTime.now().toIso8601String().split('T')[0],
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'book_borrowed_success')} ${widget.contact.displayName}',
            ),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(true); // Return success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TranslationService.translate(context, 'error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'borrow_book_title')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Contact info card
              _buildContactCard(theme),
              const SizedBox(height: 24),

              // Scan button - prominent
              _buildScanButton(theme),
              const SizedBox(height: 16),

              // OR divider
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      TranslationService.translate(context, 'or_manual_entry'),
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),

              // ISBN field - simplified without setState in onChanged
              TextFormField(
                controller: _isbnController,
                decoration: InputDecoration(
                  labelText: 'ISBN',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.numbers),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: () => _lookupByIsbn(_isbnController.text),
                  ),
                ),
                keyboardType: TextInputType.number,
                onFieldSubmitted: (value) => _lookupByIsbn(value),
              ),
              const SizedBox(height: 16),

              // Title field - simplified without autocomplete for now
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(context, 'title_label'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.book),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return TranslationService.translate(context, 'title_required');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Author field
              _buildAuthorField(),
              const SizedBox(height: 24),

              // Book preview if found
              if (_foundBook != null) _buildBookPreview(theme),

              // Existing book alert
              if (_existingBook != null) _buildExistingBookAlert(theme),

              // Error message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Borrow button
              _buildBorrowButton(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(
                Icons.person,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslationService.translate(context, 'borrowing_from'),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    widget.contact.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton(ThemeData theme) {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _scanIsbn,
      icon: const Icon(Icons.qr_code_scanner, size: 28),
      label: Text(
        TranslationService.translate(context, 'scan_isbn_barcode'),
        style: const TextStyle(fontSize: 16),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildIsbnField() {
    return TextFormField(
      controller: _isbnController,
      decoration: InputDecoration(
        labelText: 'ISBN',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.numbers),
        suffixIcon: _isbnController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _lookupByIsbn(_isbnController.text),
              )
            : null,
      ),
      keyboardType: TextInputType.number,
      onChanged: (value) {
        setState(() {}); // Update suffixIcon visibility
      },
      onFieldSubmitted: (value) => _lookupByIsbn(value),
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      decoration: InputDecoration(
        labelText: TranslationService.translate(context, 'title_label'),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.book),
        suffixIcon: _isSearching
            ? const SizedBox(
                width: 20,
                height: 20,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      onChanged: _onTitleChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return TranslationService.translate(context, 'title_required');
        }
        return null;
      },
    );
  }

  Widget _buildSuggestionsList(ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _suggestions.map((book) {
          final title = book['title'] ?? '';
          final author = _extractAuthor(book);
          final cover = book['cover'] as String?;

          return ListTile(
            leading: cover != null && cover.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      cover,
                      width: 40,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 40,
                        height: 56,
                        color: Colors.grey[300],
                        child: const Icon(Icons.book, size: 20),
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.book, size: 20),
                  ),
            title: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[600]),
            ),
            onTap: () => _selectSuggestion(book),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAuthorField() {
    return TextFormField(
      controller: _authorController,
      decoration: InputDecoration(
        labelText: TranslationService.translate(context, 'author_label'),
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person_outline),
      ),
    );
  }

  Widget _buildBookPreview(ThemeData theme) {
    final cover = _foundBook?['cover'] as String?;
    final publisher = _foundBook?['publisher'] as String?;
    final year = _foundBook?['year']?.toString();

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            if (cover != null && cover.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  cover,
                  width: 60,
                  height: 90,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 60,
                    height: 90,
                    color: Colors.grey[300],
                    child: const Icon(Icons.book, size: 32),
                  ),
                ),
              )
            else
              Container(
                width: 60,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.book, size: 32),
              ),
            const SizedBox(width: 16),
            // Book info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        TranslationService.translate(context, 'book_found'),
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _titleController.text,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_authorController.text.isNotEmpty)
                    Text(
                      _authorController.text,
                      style: TextStyle(color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (publisher != null || year != null)
                    Text(
                      [publisher, year].whereType<String>().join(' - '),
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExistingBookAlert(ThemeData theme) {
    return Container(
      key: const Key('existingBookAlert'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.translate(context, 'isbn_already_exists'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_existingBook!.title}${_existingBook!.author != null ? ' — ${_existingBook!.author}' : ''}',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  TranslationService.translate(context, 'borrow_copy_added_to_existing'),
                  style: TextStyle(color: Colors.blue[700], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorrowButton(ThemeData theme) {
    return FilledButton.icon(
      onPressed: _isLoading ? null : _borrowBook,
      icon: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.library_add),
      label: Text(
        TranslationService.translate(context, 'confirm_borrow'),
        style: const TextStyle(fontSize: 16),
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: Colors.teal,
      ),
    );
  }
}
