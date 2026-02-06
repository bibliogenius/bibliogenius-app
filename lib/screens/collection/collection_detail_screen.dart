import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/repositories/copy_repository.dart';
import '../../services/api_service.dart';
import '../../services/collection_export_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/cached_book_cover.dart';
import '../../widgets/premium_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../widgets/genie_app_bar.dart';

class CollectionDetailScreen extends StatefulWidget {
  final Collection collection;

  const CollectionDetailScreen({Key? key, required this.collection})
    : super(key: key);

  @override
  _CollectionDetailScreenState createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  late Future<List<CollectionBook>> _booksFuture;

  @override
  void initState() {
    super.initState();
    _refreshBooks();
  }

  void _refreshBooks() {
    setState(() {
      _booksFuture = Provider.of<CollectionRepository>(context, listen: false)
          .getCollectionBooks(widget.collection.id);
    });
  }

  Future<void> _deleteCollection() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'delete_collection_title'),
        ),
        content: Text(
          TranslationService.translate(context, 'delete_collection_warning'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      try {
        await Provider.of<CollectionRepository>(
          context,
          listen: false,
        ).deleteCollection(widget.collection.id);
        if (mounted) {
          context.pop(); // Go back to list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'error_deleting_collection')}: $e',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _importBooks() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'json', 'txt'],
      );

      if (result != null) {
        final platformFile = result.files.single;
        dynamic fileSource;
        if (platformFile.bytes != null) {
          fileSource = platformFile.bytes;
        } else if (platformFile.path != null) {
          fileSource = platformFile.path;
        } else {
          throw Exception('No file content found');
        }

        if (!mounted) return;

        bool importAsOwned = false;
        final shouldImport = await showDialog<bool>(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: Text(
                    TranslationService.translate(context, 'import_books'),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${TranslationService.translate(context, 'selected_file')} ${platformFile.name}',
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: Text(
                          TranslationService.translate(context, 'status_owned'),
                        ),
                        subtitle: Text(
                          TranslationService.translate(
                            context,
                            'add_to_library_copies',
                          ),
                        ),
                        value: importAsOwned,
                        onChanged: (val) {
                          setState(() => importAsOwned = val ?? false);
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(
                        TranslationService.translate(context, 'cancel'),
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        TranslationService.translate(context, 'import'),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );

        if (shouldImport != true) return;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'importing_books'),
              ),
            ),
          );
        }

        final response = await Provider.of<ApiService>(context, listen: false)
            .importCollectionBooks(
              widget.collection.id,
              fileSource,
              filename: platformFile.name,
              importAsOwned: importAsOwned,
            );

        if (response.statusCode == 200) {
          final data = response.data;
          final imported = data['imported'] ?? 0;
          final errors = data['errors']; // Optional list of errors

          if (mounted) {
            String msg = TranslationService.translate(
              context,
              'books_imported_count',
              params: {'count': imported.toString()},
            );
            if (errors != null && (errors as List).isNotEmpty) {
              msg +=
                  ' ${TranslationService.translate(context, 'books_skipped_count', params: {'count': errors.length.toString()})}';
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
          _refreshBooks();
        } else {
          throw Exception('Failed to import: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_importing_books')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _removeBook(CollectionBook book) async {
    try {
      await Provider.of<CollectionRepository>(
        context,
        listen: false,
      ).removeBookFromCollection(widget.collection.id, book.bookId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${book.title}" ${TranslationService.translate(context, 'removed_from_collection')}',
          ),
        ),
      );
      _refreshBooks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${TranslationService.translate(context, 'error_removing_book')}: $e',
          ),
        ),
      );
    }
  }

  Future<void> _shareCollection() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final exportService = CollectionExportService(apiService);

      await exportService.shareCollection(widget.collection);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'collection_exported'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_sharing_collection')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addBook() async {
    final result = await context.push(
      '/books/add',
      extra: {'collectionId': widget.collection.id},
    );
    if (result == true) {
      _refreshBooks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, // 🌟 Immersive Header
      appBar: GenieAppBar(
        title: widget.collection.name,
        transparent: true, // 🌟 Transparent AppBar
        showQuickActions: false,
        contextualQuickActions: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner, color: Colors.orange),
            title: Text(
              TranslationService.translate(context, 'scan_into_collection') ??
                  'Scan into Collection',
            ),
            onTap: () async {
              Navigator.pop(context);
              await context.push(
                '/scan',
                extra: {
                  'collectionId': widget.collection.id,
                  'collectionName': widget.collection.name,
                  'batch': true,
                },
              );
              _refreshBooks();
            },
          ),
          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.blue),
            title: Text(TranslationService.translate(context, 'import_books')),
            onTap: () {
              Navigator.pop(context);
              _importBooks();
            },
          ),
          ListTile(
            leading: const Icon(Icons.share, color: Colors.green),
            title: Text(
              TranslationService.translate(context, 'action_share') ?? 'Share',
            ),
            onTap: () {
              Navigator.pop(context);
              _shareCollection();
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: Text(
              TranslationService.translate(
                    context,
                    'delete_collection_title',
                  ) ??
                  'Delete Collection',
              style: const TextStyle(color: Colors.red),
            ),
            onTap: () {
              Navigator.pop(context);
              _deleteCollection();
            },
          ),
        ],
        actions: [],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addBook,
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<CollectionBook>>(
        future: _booksFuture,
        builder: (context, snapshot) {
          final books = snapshot.data ?? [];
          final loading = snapshot.connectionState == ConnectionState.waiting;

          // Stats Calculation
          final totalCount = books.length;
          final ownedCount = books.where((b) => b.isOwned).length;
          final wantedCount = totalCount - ownedCount;

          return Column(
            children: [
              // 🎨 Immersive Hero Banner
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF6BB0A9),
                      Color(0xFF5C8C9F),
                    ], // Matches GenieAppBar (Teal/Blue-Grey)
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF5C8C9F).withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                  bottom: 32,
                  left: 16,
                  right: 16,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: 0.1,
                    ), // Glassy background
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Description
                      if (widget.collection.description != null &&
                          widget.collection.description!.isNotEmpty)
                        Text(
                          widget.collection.description!,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.95),
                                height: 1.5,
                                fontSize: 16,
                              ),
                          textAlign: TextAlign.center,
                        ),

                      const SizedBox(height: 24),

                      // ✨ Stats Row
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          _buildStatCard(
                            context,
                            totalCount.toString(),
                            TranslationService.translate(context, 'books'),
                            Icons.library_books,
                            Colors.white,
                          ),
                          if (totalCount > 0) ...[
                            _buildStatCard(
                              context,
                              ownedCount.toString(),
                              TranslationService.translate(
                                context,
                                'status_owned',
                              ),
                              Icons.check_circle,
                              Colors.greenAccent,
                            ),
                            _buildStatCard(
                              context,
                              wantedCount.toString(),
                              TranslationService.translate(
                                context,
                                'status_wanted',
                              ),
                              Icons.bookmark_border,
                              Colors.orangeAccent,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 📚 Book List
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : snapshot.hasError
                    ? Center(
                        child: Text(
                          '${TranslationService.translate(context, 'error')}: ${snapshot.error}',
                        ),
                      )
                    : books.isEmpty
                    ? Center(
                        child: PremiumEmptyState(
                          message:
                              TranslationService.translate(
                                context,
                                'empty_collection',
                              ) ??
                              'Empty Collection',
                          description:
                              TranslationService.translate(
                                context,
                                'collection_empty_state_desc',
                              ) ??
                              'This collection has no books yet.',
                          icon: Icons.bookmark_border,
                          buttonLabel:
                              TranslationService.translate(
                                context,
                                'add_books',
                              ) ??
                              'Add Books',
                          onAction: _addBook,
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(
                          top: 16,
                          left: 16,
                          right: 16,
                          bottom: 100,
                        ),
                        itemCount: books.length,
                        itemBuilder: (context, index) {
                          final book = books[index];
                          return Dismissible(
                            key: Key('collection_book_${book.bookId}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            // ... confirmDismiss logic ...
                            confirmDismiss: (direction) async {
                              return await showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(
                                    TranslationService.translate(
                                      context,
                                      'remove_book_title',
                                    ),
                                  ),
                                  content: Text(
                                    '${TranslationService.translate(context, 'remove_book_confirm')} "${book.title}"',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: Text(
                                        TranslationService.translate(
                                          context,
                                          'cancel',
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                      child: Text(
                                        TranslationService.translate(
                                          context,
                                          'remove',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                            onDismissed: (_) => _removeBook(book),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  // ... existing inkwell ...
                                  onTap: () =>
                                      context.push('/books/${book.bookId}'),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: CachedBookCover(
                                            imageUrl: book.coverUrl,
                                            width: 50,
                                            height: 75,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                book.title,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 15,
                                                      decoration: book.isOwned
                                                          ? null
                                                          : TextDecoration.none,
                                                      color: book.isOwned
                                                          ? null
                                                          : Colors.grey[700],
                                                    ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (book.author != null) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  book.author!,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Colors.grey,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                              // Publisher & Year row
                                              if (book.publisher != null ||
                                                  book.publicationYear !=
                                                      null) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  [
                                                    if (book.publisher != null)
                                                      book.publisher,
                                                    if (book.publicationYear !=
                                                        null)
                                                      '(${book.publicationYear})',
                                                  ].join(' '),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Colors.grey[500],
                                                        fontSize: 11,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        // Status Logic
                                        Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () =>
                                                _toggleBookStatus(book),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: book.isOwned
                                                    ? Colors.green.withValues(
                                                        alpha: 0.1,
                                                      )
                                                    : Colors.orange.withValues(
                                                        alpha: 0.1,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: book.isOwned
                                                      ? Colors.green.withValues(
                                                          alpha: 0.3,
                                                        )
                                                      : Colors.orange
                                                            .withValues(
                                                              alpha: 0.3,
                                                            ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    book.isOwned
                                                        ? Icons.check_circle
                                                        : Icons.bookmark_border,
                                                    size: 14,
                                                    color: book.isOwned
                                                        ? Colors.green
                                                        : Colors.orange,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _toggleBookStatus(CollectionBook book) async {
    try {
      final newStatus = !book.isOwned;
      final api = Provider.of<ApiService>(context, listen: false);
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);

      // 1. Update the book's owned status
      await api.updateBook(book.bookId, {'owned': newStatus});

      // 2. If becoming owned, check/create copy
      if (newStatus) {
        final copies = await copyRepo.getBookCopies(book.bookId);

        if (copies.isEmpty) {
          await copyRepo.createCopy({
            'book_id': book.bookId,
            'library_id': 1, // Default library
            'status': 'available',
            'is_temporary': false,
          });
        }
      } else {
        // If becoming un-owned, delete all existing copies
        try {
          final copies = await copyRepo.getBookCopies(book.bookId);
          for (var copy in copies) {
            if (copy.id != null) {
              await copyRepo.deleteCopy(copy.id!);
            }
          }
        } catch (e) {
          debugPrint('Error deleting copies when un-owning book: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Marked "${book.title}" as ${newStatus ? 'Owned' : 'Wanted'}',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
        _refreshBooks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_updating_status')}: $e',
            ),
          ),
        );
      }
    }
  }
}
