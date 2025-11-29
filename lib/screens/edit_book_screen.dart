import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../models/book.dart';

class EditBookScreen extends StatefulWidget {
  final Book book;

  const EditBookScreen({super.key, required this.book});

  @override
  State<EditBookScreen> createState() => _EditBookScreenState();
}

class _EditBookScreenState extends State<EditBookScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _publisherController;
  late TextEditingController _yearController;
  late TextEditingController _isbnController;
  late TextEditingController _summaryController;
  String _readingStatus = 'to_read';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.book.title);
    _publisherController = TextEditingController(text: widget.book.publisher);
    _yearController = TextEditingController(
      text: widget.book.publicationYear?.toString(),
    );
    _isbnController = TextEditingController(text: widget.book.isbn);
    _summaryController = TextEditingController(text: widget.book.summary);
    _readingStatus = widget.book.readingStatus ?? 'to_read';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _publisherController.dispose();
    _yearController.dispose();
    _isbnController.dispose();
    _summaryController.dispose();
    super.dispose();
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
    };

    try {
      await apiService.updateBook(widget.book.id!, bookData);
      if (mounted) {
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating book: $e')));
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteBook() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Book'),
        content: const Text('Are you sure you want to delete this book?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
          SnackBar(content: Text('Error deleting book: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Book')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.isEmpty
                    ? 'Please enter a title'
                    : null,
              ),
              TextFormField(
                controller: _publisherController,
                decoration: const InputDecoration(labelText: 'Publisher'),
              ),
              TextFormField(
                controller: _yearController,
                decoration: const InputDecoration(
                  labelText: 'Publication Year',
                ),
                keyboardType: TextInputType.number,
              ),
              TextFormField(
                controller: _isbnController,
                decoration: const InputDecoration(labelText: 'ISBN'),
              ),
              TextFormField(
                controller: _summaryController,
                decoration: const InputDecoration(labelText: 'Summary'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _readingStatus,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'to_read', child: Text('To Read')),
                  DropdownMenuItem(value: 'reading', child: Text('Reading')),
                  DropdownMenuItem(value: 'read', child: Text('Read')),
                  DropdownMenuItem(value: 'wanted', child: Text('Wanted')),
                ],
                onChanged: (value) {
                  setState(() {
                    _readingStatus = value!;
                  });
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveBook,
                child: _isSaving
                    ? const CircularProgressIndicator()
                    : const Text('Save Changes'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _isSaving ? null : _deleteBook,
                child: const Text('Delete Book'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
