import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../models/book.dart';

class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  List<Book> _books = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBooks();
  }

  Future<void> _fetchBooks() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final response = await apiService.getBooks();
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['books']; // Extract books array
        setState(() {
          _books = data.map((json) => Book.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error (offline mode logic would go here)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBooks,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _books.length,
              itemBuilder: (context, index) {
                final book = _books[index];
                return ListTile(
                  title: Text(book.title),
                  subtitle: Text(book.publisher ?? 'Unknown Publisher'),
                  leading: GestureDetector(
                    onTap: () async {
                      final result = await context.push('/books/${book.id}/edit', extra: book);
                      if (result == true) {
                        _fetchBooks();
                      }
                    },
                    child: const Icon(Icons.edit),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.library_books),
                    onPressed: () {
                      context.push('/books/${book.id}/copies', extra: {
                        'bookId': book.id,
                        'bookTitle': book.title,
                      });
                    },
                  ),
                );
              },
            ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'BiblioGenius',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.book),
              title: const Text('Books'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.contacts),
              title: const Text('Contacts'),
              onTap: () {
                Navigator.pop(context);
                context.push('/contacts');
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await context.push('/books/add');
          if (result == true) {
            _fetchBooks(); // Refresh if book was added
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
