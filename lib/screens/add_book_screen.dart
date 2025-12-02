import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/book_status.dart';
import '../services/open_library_service.dart';
import '../models/book.dart';

class AddBookScreen extends StatefulWidget {
  final String? isbn;
  const AddBookScreen({super.key, this.isbn});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _openLibraryService = OpenLibraryService();
  final _titleController = TextEditingController();
  final _publisherController = TextEditingController();
  final _publicationYearController = TextEditingController();
  final _isbnController = TextEditingController();
  final _summaryController = TextEditingController();
  final _authorController = TextEditingController();
  String _readingStatus = 'to_read';
  String? _coverUrl;
  bool _isFetchingDetails = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.isbn != null) {
      _isbnController.text = widget.isbn!;
      _fetchBookDetails(widget.isbn!);
    }
    _isbnController.addListener(_onIsbnChanged);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _publicationYearController.dispose();
    _isbnController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _onIsbnChanged() {
    final isbn = _isbnController.text.replaceAll(RegExp(r'[^0-9X]'), '');
    if ((isbn.length == 10 || isbn.length == 13) && !_isFetchingDetails) {
      _fetchBookDetails(isbn);
    }
  }

  Future<void> _fetchBookDetails(String isbn) async {
    setState(() => _isFetchingDetails = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final bookData = await api.fetchOpenLibraryBook(isbn);
      
      if (bookData != null && mounted) {
        setState(() {
          if (_titleController.text.isEmpty) _titleController.text = bookData['title'] ?? '';
          if (_authorController.text.isEmpty) _authorController.text = bookData['author'] ?? '';
          if (_publisherController.text.isEmpty) _publisherController.text = bookData['publisher'] ?? '';
          if (_publicationYearController.text.isEmpty) _publicationYearController.text = bookData['year']?.toString() ?? '';
          if (_summaryController.text.isEmpty) _summaryController.text = bookData['summary'] ?? '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.translate(context, 'book_details_found'))),
        );
      }
    } catch (e) {
      debugPrint('Error fetching ISBN: $e');
    } finally {
      if (mounted) setState(() => _isFetchingDetails = false);
    }
  }

  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final apiService = Provider.of<ApiService>(context, listen: false);
    final book = Book(
      title: _titleController.text,
      author: _authorController.text,
      publisher: _publisherController.text,
      publicationYear: int.tryParse(_publicationYearController.text),
      isbn: _isbnController.text,
      readingStatus: _readingStatus,
      summary: _summaryController.text,
      coverUrl: _coverUrl,
    );

    try {
      await apiService.createBook(book.toJson());
      if (mounted) {
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_saving_book')}: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'add_book_title')),
        actions: [
          TextButton.icon(
            onPressed: () => context.push('/search/external'),
            icon: const Icon(Icons.search, color: Colors.white),
            label: Text(TranslationService.translate(context, 'btn_search_online'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24.0),
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.library_add, size: 32, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Text(
                  TranslationService.translate(context, 'add_new_book'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            // Title
            _buildLabel(TranslationService.translate(context, 'title_label')),
            LayoutBuilder(
              builder: (context, constraints) {
                return RawAutocomplete<OpenLibraryBook>(
                  textEditingController: _titleController,
                  focusNode: FocusNode(),
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    return _openLibraryService.searchBooks(textEditingValue.text);
                  },
                  displayStringForOption: (OpenLibraryBook option) => option.title,
                  onSelected: (OpenLibraryBook selection) {
                    setState(() {
                      _authorController.text = selection.author;
                      if (selection.isbn != null) _isbnController.text = selection.isbn!;
                      if (selection.publisher != null) _publisherController.text = selection.publisher!;
                      if (selection.year != null) _publicationYearController.text = selection.year.toString();
                      if (selection.coverUrl != null) _coverUrl = selection.coverUrl;
                    });
                  },
                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                    return TextFormField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: _buildInputDecoration(
                        hint: TranslationService.translate(context, 'enter_book_title'),
                        suffixIcon: const Icon(Icons.search),
                      ),
                      validator: (value) => value == null || value.isEmpty ? TranslationService.translate(context, 'enter_title_error') : null,
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
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
                              return ListTile(
                                leading: option.coverUrl != null
                                    ? Image.network(option.coverUrl!, width: 40, errorBuilder: (_,__,___) => const Icon(Icons.book))
                                    : const Icon(Icons.book),
                                title: Text(option.title),
                                subtitle: Text(option.author),
                                onTap: () => onSelected(option),
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
            TextFormField(
              controller: _authorController,
              decoration: _buildInputDecoration(hint: TranslationService.translate(context, 'author_hint')),
            ),
            const SizedBox(height: 24),

            // ISBN
            _buildLabel(TranslationService.translate(context, 'isbn_label')),
            TextFormField(
              controller: _isbnController,
              decoration: _buildInputDecoration(
                hint: TranslationService.translate(context, 'enter_isbn_autofill'),
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
                        onPressed: () => _fetchBookDetails(_isbnController.text),
                        tooltip: TranslationService.translate(context, 'lookup_isbn'),
                      ),
              ),
              keyboardType: TextInputType.number,
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
                      _buildLabel(TranslationService.translate(context, 'publisher_label')),
                      TextFormField(
                        controller: _publisherController,
                        decoration: _buildInputDecoration(hint: TranslationService.translate(context, 'publisher_hint')),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLabel(TranslationService.translate(context, 'year_label')),
                      TextFormField(
                        controller: _publicationYearController,
                        decoration: _buildInputDecoration(hint: TranslationService.translate(context, 'year_hint')),
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
              controller: _summaryController,
              decoration: _buildInputDecoration(hint: TranslationService.translate(context, 'summary_hint')),
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            // Status
            _buildLabel(TranslationService.translate(context, 'status_label')),
            Builder(
              builder: (context) {
                final themeProvider = Provider.of<ThemeProvider>(context);
                final isLibrarian = themeProvider.isLibrarian;
                final statusOptions = getStatusOptions(context, isLibrarian);
                
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
                  onChanged: (value) => setState(() => _readingStatus = value!),
                );
              },
            ),
            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveBook,
                icon: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
                label: Text(_isSaving ? TranslationService.translate(context, 'saving') : TranslationService.translate(context, 'save_book')),
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
