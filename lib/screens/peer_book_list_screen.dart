import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/book.dart';

class PeerBookListScreen extends StatefulWidget {
  final int peerId;
  final String peerName;

  const PeerBookListScreen({super.key, required this.peerId, required this.peerName});

  @override
  State<PeerBookListScreen> createState() => _PeerBookListScreenState();
}

class _PeerBookListScreenState extends State<PeerBookListScreen> {
  List<Book> _books = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchBooks();
  }

  Future<void> _fetchBooks() async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final res = await api.getPeerBooks(widget.peerId);
      final List<dynamic> data = res.data;
      setState(() {
        _books = data.map((json) => Book.fromJson(json)).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _requestBorrow(Book book) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.requestBook(widget.peerId, book.isbn ?? "", book.title);
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
      appBar: AppBar(title: Text("${widget.peerName}'s Books")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _books.length,
              itemBuilder: (context, index) {
                final book = _books[index];
                return ListTile(
                  title: Text(book.title),
                  subtitle: Text(book.author ?? ""),
                  trailing: ElevatedButton(
                    onPressed: () => _requestBorrow(book),
                    child: const Text("Borrow"),
                  ),
                );
              },
            ),
    );
  }
}
