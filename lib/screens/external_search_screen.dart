import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import 'package:go_router/go_router.dart';

class ExternalSearchScreen extends StatefulWidget {
  const ExternalSearchScreen({super.key});

  @override
  State<ExternalSearchScreen> createState() => _ExternalSearchScreenState();
}

class _ExternalSearchScreenState extends State<ExternalSearchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _subjectController = TextEditingController();
  
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _error;
  bool _booksAdded = false;

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_titleController.text.isEmpty && 
        _authorController.text.isEmpty && 
        _subjectController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TranslationService.translate(context, 'enter_search_term'))),
      );
      return;
    }

    setState(() {
      _isSearching = true;
      _error = null;
      _searchResults = [];
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // Use unified search (Inventaire + OpenLibrary)
      final results = await api.searchBooks(
        title: _titleController.text,
        author: _authorController.text,
        subject: _subjectController.text,
      );

      setState(() {
        _searchResults = results;
      });
    } catch (e) {
      setState(() {
        _error = '${TranslationService.translate(context, 'search_failed')}: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _addBook(Map<String, dynamic> doc) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      
      // Map unified search result (Book DTO) to create payload
      final bookData = {
        'title': doc['title'],
        'author': doc['author'], // Already a string in DTO
        // publication_year is int in DTO
        'publication_year': doc['publication_year'], 
        'publisher': doc['publisher'],
        'isbn': doc['isbn'],
        'summary': doc['summary'],
        'reading_status': 'to_read',
        'cover_url': doc['cover_url'],
      };

      await api.createBook(bookData);
    
    // Mark as modified so we can refresh the list on return
    _booksAdded = true;
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${doc['title']}" ${TranslationService.translate(context, 'added_to_library')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'failed_add_book')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        context.pop(_booksAdded);
      },
      child: Scaffold(
        appBar: GenieAppBar(
          title: TranslationService.translate(context, 'external_search_title'),
        ),
        body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: TranslationService.translate(context, 'search_title_label'),
                      prefixIcon: const Icon(Icons.book),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _authorController,
                    decoration: InputDecoration(
                      labelText: TranslationService.translate(context, 'author_label'),
                      prefixIcon: const Icon(Icons.person),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _subjectController,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: TranslationService.translate(context, 'subject_label'),
                      prefixIcon: const Icon(Icons.category),
                    ),
                    onFieldSubmitted: (_) => _search(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSearching ? null : _search,
                      icon: _isSearching 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                      label: Text(TranslationService.translate(context, 'search_open_library')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final book = _searchResults[index];
                final hasCover = book['cover_url'] != null;

                return ListTile(
                  leading: hasCover
                      ? Image.network(
                          book['cover_url'],
                          width: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.book),
                        )
                      : const Icon(Icons.book),
                  title: Text(book['title'] ?? TranslationService.translate(context, 'unknown_title')),
                  subtitle: Text(
                    book['author'] ?? TranslationService.translate(context, 'unknown_author'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _addBook(book),
                  ),
                  onTap: () {
                     // Show details?
                  },
                );
              },
            ),
          ),
        ],
      ),
    ));
  }
}
