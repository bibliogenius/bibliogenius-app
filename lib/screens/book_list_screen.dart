import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../models/book.dart';
import '../widgets/bookshelf_view.dart';

class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  List<Book> _books = [];
  bool _isLoading = true;
  bool _isShelfView = true;

  @override
  void initState() {
    super.initState();
    _fetchBooks();
    // Trigger background sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SyncService>(context, listen: false).syncAllPeers();
    });
  }


  Future<void> _fetchBooks() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final response = await apiService.getBooks();
      if (response.statusCode == 200) {
        final List<dynamic> data =
            response.data['books']; // Extract books array
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

  Future<void> _navigateToEditBook(Book book) async {
    final result = await context.push('/books/${book.id}/edit', extra: book);
    if (result == true) {
      _fetchBooks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Library'),
        actions: [
          IconButton(
            icon: Icon(_isShelfView ? Icons.list : Icons.grid_view),
            onPressed: () {
              setState(() {
                _isShelfView = !_isShelfView;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.camera_alt),
            onPressed: () {
              context.push('/scan');
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchBooks),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isShelfView
          ? BookshelfView(books: _books, onBookTap: _navigateToEditBook)
          : ListView.builder(
              itemCount: _books.length,
              itemBuilder: (context, index) {
                final book = _books[index];
                return ListTile(
                  title: Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.publisher ?? 'Unknown Publisher'),
                      const SizedBox(height: 4),
                      if (book.readingStatus != null)
                        Chip(
                          label: Text(
                            book.readingStatus!.replaceAll('_', ' ').toUpperCase(),
                            style: const TextStyle(fontSize: 10),
                          ),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  leading: GestureDetector(
                    onTap: () => _navigateToEditBook(book),
                    child: const Icon(Icons.edit),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.library_books),
                    onPressed: () {
                      context.push(
                        '/books/${book.id}/copies',
                        extra: {'bookId': book.id, 'bookTitle': book.title},
                      );
                    },
                  ),
                );
              },
            ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
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
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('P2P Connection'),
              onTap: () {
                Navigator.pop(context);
                context.push('/p2p');
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync),
              title: const Text('Network Libraries'),
              onTap: () {
                Navigator.pop(context);
                context.push('/peers');
              },
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Borrow Requests'),
              onTap: () {
                Navigator.pop(context);
                context.push('/requests');
              },
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.pop(context);
                context.push('/profile');
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
