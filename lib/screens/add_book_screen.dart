import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../models/book.dart';

class AddBookScreen extends StatefulWidget {
  final String? isbn;
  const AddBookScreen({super.key, this.isbn});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final _titleController = TextEditingController();
  final _publisherController = TextEditingController();
  final _publicationYearController = TextEditingController();
  final _isbnController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.isbn != null) {
      _isbnController.text = widget.isbn!;
    }
  }

  Future<void> _saveBook() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final book = Book(
      title: _titleController.text,
      publisher: _publisherController.text,
      publicationYear: int.tryParse(_publicationYearController.text),
      isbn: _isbnController.text,
    );

    try {
      await apiService.createBook(book.toJson());
      if (mounted) {
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving book: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Book')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: _publisherController,
              decoration: const InputDecoration(labelText: 'Publisher'),
            ),
            TextField(
              controller: _publicationYearController,
              decoration: const InputDecoration(labelText: 'Publication Year'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: _isbnController,
              decoration: const InputDecoration(
                labelText: 'ISBN',
                hintText: 'Scanner coming soon!',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveBook,
              child: const Text('Save Book'),
            ),
          ],
        ),
      ),
    );
  }
}
