import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../widgets/bookshelf_view.dart';

import '../widgets/app_drawer.dart';
import '../services/wizard_service.dart';

class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  bool _isLoading = true;
  bool _isShelfView = true;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _viewKey = GlobalKey();
  final GlobalKey _scanKey = GlobalKey();
  final GlobalKey _externalSearchKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchBooks();
    // Trigger background sync
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<SyncService>(context, listen: false).syncAllPeers();
      _checkWizard();
    });
  }

  Future<void> _checkWizard() async {
    final hasSeen = await WizardService.hasSeenBooksWizard();
    if (!hasSeen && mounted) {
      WizardService.showBooksTutorial(
        context: context,
        addKey: _addKey,
        searchKey: _searchKey,
        viewKey: _viewKey,
        scanKey: _scanKey,
        externalSearchKey: _externalSearchKey,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterBooks(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredBooks = _books;
      });
      return;
    }
    setState(() {
      _filteredBooks = _books.where((book) {
        final title = book.title.toLowerCase();
        final author = book.author?.toLowerCase() ?? '';
        final isbn = book.isbn?.toLowerCase() ?? '';
        final q = query.toLowerCase();
        return title.contains(q) || author.contains(q) || isbn.contains(q);
      }).toList();
    });
  }

  Future<void> _fetchBooks() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final booksRes = await apiService.getBooks();
      final configRes = await apiService.getLibraryConfig();

      if (booksRes.statusCode == 200 && configRes.statusCode == 200) {
        final List<dynamic> data = booksRes.data['books'];
        final config = configRes.data;
        final showBorrowed = config['show_borrowed_books'] == true;

        setState(() {
          _books = data.map((json) => Book.fromJson(json)).where((book) {
            if (showBorrowed) return true;
            return book.readingStatus != 'borrowed';
          }).toList();
          _filteredBooks = _books;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Handle error
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
      appBar: GenieAppBar(
        title: _isSearching ? TranslationService.translate(context, 'search_books') : TranslationService.translate(context, 'my_library_title'),
        actions: [
          IconButton(
            key: _searchKey,
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchController.clear();
                  _filterBooks('');
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          if (!_isSearching) ...[
            IconButton(
              key: _viewKey,
              icon: Icon(_isShelfView ? Icons.list : Icons.grid_view),
              onPressed: () {
                setState(() {
                  _isShelfView = !_isShelfView;
                });
              },
            ),
            IconButton(
              key: _scanKey,
              icon: const Icon(Icons.camera_alt),
              onPressed: () {
                context.push('/scan');
              },
            ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchBooks),
            IconButton(
              key: _externalSearchKey,
              icon: const Icon(Icons.public),
              tooltip: TranslationService.translate(context, 'btn_search_online'),
              onPressed: () {
                context.push('/search/external');
              },
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isShelfView
          ? BookshelfView(books: _filteredBooks, onBookTap: _navigateToEditBook)
          : ListView.separated(
              itemCount: _filteredBooks.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final book = _filteredBooks[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    width: 40,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.grey[200],
                      image: book.coverUrl != null
                          ? DecorationImage(
                              image: NetworkImage(book.coverUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: book.coverUrl == null
                        ? const Icon(Icons.book, color: Colors.grey, size: 20)
                        : null,
                  ),
                  title: Text(
                    book.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        book.publisher ?? 'Unknown Publisher',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (book.readingStatus != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          book.readingStatus!.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (context) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.edit),
                                title: Text(TranslationService.translate(context, 'menu_edit')),
                                onTap: () {
                                  Navigator.pop(context);
                                  _navigateToEditBook(book);
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.library_books),
                                title: Text(TranslationService.translate(context, 'menu_manage_copies')),
                                onTap: () {
                                  Navigator.pop(context);
                                  context.push(
                                    '/books/${book.id}/copies',
                                    extra: {'bookId': book.id, 'bookTitle': book.title},
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  onTap: () => _navigateToEditBook(book),
                );
              },
            ),

      floatingActionButton: FloatingActionButton(
        key: _addKey,
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
