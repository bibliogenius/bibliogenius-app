import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/genie_app_bar.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';

class NetworkSearchScreen extends StatefulWidget {
  const NetworkSearchScreen({super.key});

  @override
  State<NetworkSearchScreen> createState() => _NetworkSearchScreenState();
}

class _NetworkSearchScreenState extends State<NetworkSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);
    
    try {
      // Get all connected peers
      final peersResponse = await apiService.getPeers();
      
      if (peersResponse.statusCode == 200) {
        final List<dynamic> peers = peersResponse.data['peers'] ?? [];
        List<dynamic> allBooks = [];

        // Search in each peer's library
        for (var peer in peers) {
          if (peer['status'] == 'accepted' && peer['url'] != null) {
            try {
              final booksResponse = await apiService.getPeerBooksByUrl(peer['url']);
              if (booksResponse.statusCode == 200) {
                final List<dynamic> books = booksResponse.data['books'] ?? [];
                // Add peer info to each book for display
                for (var book in books) {
                  book['_peer_name'] = peer['name'];
                  book['_peer_id'] = peer['id'];
                  book['_peer_url'] = peer['url'];
                }
                allBooks.addAll(books);
              }
            } catch (e) {
              debugPrint('Error fetching books from peer ${peer['name']}: $e');
            }
          }
        }

        // Filter books based on search query
        final results = allBooks.where((book) {
          final title = (book['title'] ?? '').toString().toLowerCase();
          final author = (book['author'] ?? '').toString().toLowerCase();
          final searchLower = query.toLowerCase();
          return title.contains(searchLower) || author.contains(searchLower);
        }).toList();

        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'search_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _requestBook(dynamic book) async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    
    try {
      await apiService.requestBook(
        book['_peer_id'],
        book['isbn'] ?? '',
        book['title'] ?? 'Unknown',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'request_sent_to')} ${book['_peer_name']}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'connection_error')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'network_search_title'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: TranslationService.translate(context, 'network_search_hint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchResults = [];
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _performSearch,
              onChanged: (value) {
                setState(() {}); // To update clear button visibility
              },
            ),
          ),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _hasSearched
                    ? _searchResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  TranslationService.translate(context, 'network_search_no_results'),
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final book = _searchResults[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ListTile(
                                  leading: const Icon(Icons.book, size: 40),
                                  title: Text(
                                    book['title'] ?? 'Unknown Title',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(book['author'] ?? 'Unknown Author'),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(Icons.library_books, size: 14, color: Theme.of(context).primaryColor),
                                          const SizedBox(width: 4),
                                          Text(
                                            book['_peer_name'] ?? 'Unknown Library',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(context).primaryColor,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: ElevatedButton.icon(
                                    onPressed: () => _requestBook(book),
                                    icon: const Icon(Icons.send, size: 16),
                                    label: Text(TranslationService.translate(context, 'request_book_btn')),
                                  ),
                                ),
                              );
                            },
                          )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              TranslationService.translate(context, 'network_search_prompt'),
                              style: TextStyle(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
