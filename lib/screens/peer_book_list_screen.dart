import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/book.dart';
import '../widgets/bookshelf_view.dart';

class PeerBookListScreen extends StatefulWidget {
  final int peerId; // Keep for compatibility
  final String peerName;
  final String peerUrl; // Add URL

  const PeerBookListScreen({
    super.key, 
    required this.peerId, 
    required this.peerName,
    required this.peerUrl,
  });

  @override
  State<PeerBookListScreen> createState() => _PeerBookListScreenState();
}

class _PeerBookListScreenState extends State<PeerBookListScreen> {
  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  bool _isLoading = true;
  bool _isShelfView = true;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fetchBooks();
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
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final res = await api.getPeerBooksByUrl(widget.peerUrl);
      final List<dynamic> data = res.data;
      
      if (mounted) {
        setState(() {
          _books = data.map((json) => Book.fromJson(json)).toList();
          _filteredBooks = _books;
          _isLoading = false;
        });

        // Auto-sync if empty
        if (_books.isEmpty) {
          _syncBooks();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _syncBooks() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.syncPeer(widget.peerUrl);
      // Re-fetch after sync
      final res = await api.getPeerBooksByUrl(widget.peerUrl);
      final List<dynamic> data = res.data;
      
      if (mounted) {
        setState(() {
          _books = data.map((json) => Book.fromJson(json)).toList();
          _filteredBooks = _books;
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Library synced successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    }
  }

  Future<void> _requestBorrow(Book book) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.requestBookByUrl(widget.peerUrl, book.isbn ?? "", book.title);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Request sent!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to send request: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search books...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: _filterBooks,
              )
            : Text("${widget.peerName}'s Books"),
        actions: [
          IconButton(
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
          if (!_isSearching)
            IconButton(
              icon: Icon(_isShelfView ? Icons.list : Icons.grid_view),
              onPressed: () {
                setState(() {
                  _isShelfView = !_isShelfView;
                });
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredBooks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.library_books_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        "No books found",
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _syncBooks,
                        icon: const Icon(Icons.sync),
                        label: const Text("Sync Library"),
                      ),
                    ],
                  ),
                )
              : _isShelfView
                  ? BookshelfView(
                      books: _filteredBooks,
                      onBookTap: (book) => _showBookDetails(book),
                    )
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
                          subtitle: Text(
                            book.author ?? 'Unknown Author',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: ElevatedButton(
                            onPressed: () => _requestBorrow(book),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text("Borrow"),
                          ),
                          onTap: () => _showBookDetails(book),
                        );
                      },
                    ),
    );
  }

  void _showBookDetails(Book book) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 100,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[200],
                    image: book.largeCoverUrl != null
                        ? DecorationImage(
                            image: NetworkImage(book.largeCoverUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: book.largeCoverUrl == null
                      ? const Icon(Icons.book, size: 50, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                book.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  book.author ?? 'Unknown Author',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ),
              const SizedBox(height: 24),
              if (book.summary != null) ...[
                Text(
                  "Summary",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  book.summary!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _requestBorrow(book);
                  },
                  icon: const Icon(Icons.bookmark_add),
                  label: const Text("Request to Borrow"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
