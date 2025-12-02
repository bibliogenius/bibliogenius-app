import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';

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
      final response = await api.searchOpenLibrary(
        title: _titleController.text,
        author: _authorController.text,
        subject: _subjectController.text,
      );

      if (response.statusCode == 200) {
        final docs = response.data['docs'] as List<dynamic>;
        setState(() {
          _searchResults = docs.map((doc) => doc as Map<String, dynamic>).toList();
        });
      }
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
      
      // Map Open Library doc to our Book model structure
      final bookData = {
        'title': doc['title'],
        'author': doc['author_name'] != null ? (doc['author_name'] as List).first.toString() : null,
        'publication_year': doc['publish_year'] != null ? (doc['publish_year'] as List).first as int : null,
        'publisher': doc['publisher'] != null ? (doc['publisher'] as List).first.toString() : null,
        'isbn': doc['isbn'] != null ? (doc['isbn'] as List).first.toString() : null,
        'summary': null, // Search API doesn't return summary usually
        'reading_status': 'to_read',
        'cover_url': doc['cover_i'] != null ? 'https://covers.openlibrary.org/b/id/${doc['cover_i']}-L.jpg' : null,
      };

      await api.createBook(bookData);
      
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
    return Scaffold(
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
                      labelText: TranslationService.translate(context, 'title_label'),
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
                    decoration: const InputDecoration(
                      labelText: TranslationService.translate(context, 'subject_label'),
                      prefixIcon: Icon(Icons.category),
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
                final doc = _searchResults[index];
                final coverId = doc['cover_i'];
                final coverUrl = coverId != null 
                    ? 'https://covers.openlibrary.org/b/id/$coverId-S.jpg' 
                    : null;

                return ListTile(
                  leading: coverUrl != null
                      ? Image.network(coverUrl, width: 40, fit: BoxFit.cover)
                      : const Icon(Icons.book),
                  title: Text(doc['title'] ?? TranslationService.translate(context, 'unknown_title')),
                  subtitle: Text(
                    doc['author_name'] != null 
                        ? (doc['author_name'] as List).join(', ') 
                        : TranslationService.translate(context, 'unknown_author')
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _addBook(doc),
                    tooltip: TranslationService.translate(context, 'add_to_library_tooltip'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
