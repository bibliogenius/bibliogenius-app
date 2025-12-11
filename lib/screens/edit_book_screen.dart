import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';
import '../utils/book_status.dart';
import '../services/open_library_service.dart';
import '../models/book.dart';
import '../models/contact.dart';
import '../widgets/loan_dialog.dart';

class EditBookScreen extends StatefulWidget {
  final Book book;

  const EditBookScreen({super.key, required this.book});

  @override
  State<EditBookScreen> createState() => _EditBookScreenState();
}

class _EditBookScreenState extends State<EditBookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _openLibraryService = OpenLibraryService();
  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _publisherController;
  late TextEditingController _yearController;
  late TextEditingController _isbnController;
  late TextEditingController _summaryController;
  late TextEditingController _startedDateController;
  late TextEditingController _finishedDateController;
  late TextEditingController _tagsController; // Add this
  late Book _book;
  List<String> _selectedTags = []; // Add this
  String _readingStatus = 'to_read';
  String? _coverUrl;
  bool _isEditing = true; // Always start in edit mode
  bool _isSaving = false;
  bool _isFetchingDetails = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.book.title);
    _authorController = TextEditingController(text: widget.book.author ?? '');
    _isbnController = TextEditingController(text: widget.book.isbn ?? '');
    _publisherController = TextEditingController(text: widget.book.publisher ?? '');
    _yearController = TextEditingController(text: widget.book.publicationYear?.toString() ?? '');
    _summaryController = TextEditingController(text: widget.book.summary ?? '');
    _startedDateController = TextEditingController(
      text: widget.book.startedReadingAt?.toIso8601String().split('T')[0] ?? '',
    );
    _finishedDateController = TextEditingController(
      text: widget.book.finishedReadingAt?.toIso8601String().split('T')[0] ?? '',
    );
    _book = widget.book;
    _coverUrl = widget.book.coverUrl;
    
    // Initialize tags
    _selectedTags = widget.book.subjects != null 
        ? List.from(widget.book.subjects!) 
        : [];
    
    // Get profile type from ThemeProvider after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final isLibrarian = themeProvider.isLibrarian;
      setState(() {
        _readingStatus = widget.book.readingStatus ?? getDefaultStatus(isLibrarian);
      });
    });

    // Add listener for ISBN changes
    _isbnController.addListener(_onIsbnChanged);
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
      final bookData = await api.lookupBook(isbn);
      
      if (bookData != null && mounted) {
        setState(() {
          if (_titleController.text.isEmpty) _titleController.text = bookData['title'] ?? '';
          if (_publisherController.text.isEmpty) _publisherController.text = bookData['publisher'] ?? '';
          if (_yearController.text.isEmpty) _yearController.text = bookData['year']?.toString() ?? '';
          if (_summaryController.text.isEmpty) _summaryController.text = bookData['summary'] ?? '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.translate(context, 'book_details_found'))),
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
    _titleController.dispose();
    _authorController.dispose();
    _publisherController.dispose();
    _yearController.dispose();
    _isbnController.dispose();
    _isbnController.dispose();
    _summaryController.dispose();
    _startedDateController.dispose();
    _finishedDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        controller.text = picked.toIso8601String().split('T')[0];
      });
    }
  }

  Future<void> _saveBook() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final apiService = Provider.of<ApiService>(context, listen: false);
    final bookData = {
      'title': _titleController.text,
      'publisher': _publisherController.text,
      'publication_year': int.tryParse(_yearController.text),
      'isbn': _isbnController.text,
      'summary': _summaryController.text,
      'reading_status': _readingStatus,
      'cover_url': _coverUrl,
      'started_reading_at': _startedDateController.text.isNotEmpty 
          ? DateTime.parse(_startedDateController.text).toIso8601String() 
          : null,
      'finished_reading_at': _finishedDateController.text.isNotEmpty 
          ? DateTime.parse(_finishedDateController.text).toIso8601String() 
          : null,
      'subjects': _selectedTags,
    };

    try {
      await apiService.updateBook(widget.book.id!, bookData);
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isEditing = false; // Return to view mode
          _hasChanges = true; // Mark as changed
          
          // Update local book state including dates
          DateTime? startedAt = _startedDateController.text.isNotEmpty 
              ? DateTime.tryParse(_startedDateController.text) 
              : null;
          DateTime? finishedAt = _finishedDateController.text.isNotEmpty 
              ? DateTime.tryParse(_finishedDateController.text) 
              : null;

          _book = Book(
            id: widget.book.id,
            title: _titleController.text,
            author: _authorController.text.isNotEmpty ? _authorController.text : widget.book.author,
            isbn: _isbnController.text,
            publisher: _publisherController.text,
            publicationYear: int.tryParse(_yearController.text),
            summary: _summaryController.text,
            readingStatus: _readingStatus,
            coverUrl: _coverUrl,
            startedReadingAt: startedAt,
            finishedReadingAt: finishedAt,
            subjects: _selectedTags,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.translate(context, 'book_updated'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${TranslationService.translate(context, 'error_updating_book')}: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteBook() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'delete_book_title')),
        content: Text(TranslationService.translate(context, 'delete_book_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(TranslationService.translate(context, 'delete_book_btn'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);

    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      await apiService.deleteBook(widget.book.id!);
      if (mounted) {
        context.pop(true); // Return true to indicate success (and refresh list)
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_deleting_book')}: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

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
      case 'wanted':
        color = Colors.orange;
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
    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'edit_book_title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Signal back if changes were made
            Navigator.of(context).pop(_hasChanges); 
          },
        ),
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
            // Header
            Row(
              children: [
                Icon(Icons.edit_note, size: 32, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Text(
                  TranslationService.translate(context, 'edit_book_details'),
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
                      if (selection.year != null) _yearController.text = selection.year.toString();
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
                      validator: (value) => value == null || value.isEmpty
                          ? TranslationService.translate(context, 'enter_title_error')
                          : null,
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
                        controller: _yearController,
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
                  onChanged: (value) {
                    setState(() {
                      _readingStatus = value!;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 24),

            // Reading Dates (Conditional)
            if (_readingStatus != 'to_read' && _readingStatus != 'wanted') ...[
              _buildLabel(TranslationService.translate(context, 'started_reading_label')),
              TextFormField(
                controller: _startedDateController,
                decoration: _buildInputDecoration(
                  hint: TranslationService.translate(context, 'select_date'),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () => _selectDate(context, _startedDateController),
              ),
              const SizedBox(height: 24),
            ],

            if (_readingStatus == 'read') ...[
              _buildLabel(TranslationService.translate(context, 'finished_reading_label')),
              TextFormField(
                controller: _finishedDateController,
                decoration: _buildInputDecoration(
                  hint: TranslationService.translate(context, 'select_date'),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () => _selectDate(context, _finishedDateController),
              ),
              const SizedBox(height: 24),
              const SizedBox(height: 24),
            ],

            // Tags
            _buildLabel(TranslationService.translate(context, 'tags')),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) async {
                if (textEditingValue.text == '') {
                  return const Iterable<String>.empty();
                }
                
                // Fetch tags from backend or filter local list if we had one
                try {
                  final api = Provider.of<ApiService>(context, listen: false);
                  final tags = await api.getTags();
                  final tagNames = tags.map((t) => t.name).toList();
                  
                  return tagNames.where((String option) {
                    return option.toLowerCase().contains(textEditingValue.text.toLowerCase()) && 
                          !_selectedTags.contains(option);
                  });
                } catch (e) {
                   return const Iterable<String>.empty();
                }
              },
              onSelected: (String selection) {
                setState(() {
                  _selectedTags.add(selection);
                  _tagsController.clear();
                });
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                _tagsController = controller; // Keep reference to clear it
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: _buildInputDecoration(
                    hint: TranslationService.translate(context, 'add_tag_hint'),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        if (controller.text.isNotEmpty) {
                          setState(() {
                             if (!_selectedTags.contains(controller.text)) {
                               _selectedTags.add(controller.text);
                             }
                             controller.clear();
                          });
                        }
                      },
                    ),
                  ),
                  onFieldSubmitted: (String value) {
                     if (value.isNotEmpty) {
                        setState(() {
                           if (!_selectedTags.contains(value)) {
                             _selectedTags.add(value);
                           }
                           controller.clear();
                        });
                        focusNode.requestFocus(); // Keep focus to add more
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
            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveBook,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save),
                label: Text(_isSaving ? TranslationService.translate(context, 'saving_changes') : TranslationService.translate(context, 'save_changes')),
                style: ElevatedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Delete Button
            SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _deleteBook,
                icon: const Icon(Icons.delete, color: Colors.red),
                label: Text(TranslationService.translate(context, 'delete_book_btn'), style: const TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
