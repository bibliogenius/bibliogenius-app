import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/repositories/copy_repository.dart';
import '../../services/api_service.dart';
import '../../services/collection_export_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/cached_book_cover.dart';
import '../../widgets/configurable_action_card.dart';
import '../../widgets/premium_empty_state.dart';
import 'collection_delete_dialog.dart';
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
      _booksFuture = Provider.of<CollectionRepository>(
        context,
        listen: false,
      ).getCollectionBooks(widget.collection.id);
    });
  }

  Future<void> _deleteCollection() async {
    final repo = Provider.of<CollectionRepository>(context, listen: false);
    final outcome = await confirmCollectionDeletion(
      context,
      repo,
      widget.collection.id,
    );
    if (outcome == CollectionDeleteOutcome.cancelled) return;
    if (!mounted) return;

    try {
      if (outcome == CollectionDeleteOutcome.withBooks) {
        await repo.deleteCollectionWithBooks(widget.collection.id);
      } else {
        await repo.deleteCollection(widget.collection.id);
      }
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error_deleting_collection')}: $e',
        );
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
          AppSnackBar.loading(
            context,
            TranslationService.translate(context, 'importing_books'),
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
            AppSnackBar.success(context, msg);
          }
          _refreshBooks();
        } else {
          throw Exception('Failed to import: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error_importing_books')}: $e',
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

      AppSnackBar.success(
        context,
        '"${book.title}" ${TranslationService.translate(context, 'removed_from_collection')}',
      );
      _refreshBooks();
    } catch (e) {
      AppSnackBar.error(
        context,
        '${TranslationService.translate(context, 'error_removing_book')}: $e',
      );
    }
  }

  Future<void> _shareCollection() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final exportService = CollectionExportService(apiService);

      await exportService.shareCollection(widget.collection);

      if (mounted) {
        AppSnackBar.success(
          context,
          TranslationService.translate(context, 'collection_exported'),
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error_sharing_collection')}: $e',
        );
      }
    }
  }

  Future<void> _addBook() async {
    final result = await context.push(
      '/books/add',
      extra: {
        'collectionId': widget.collection.id,
        'collectionName': widget.collection.name,
      },
    );
    if (result != null) {
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
        preSelectedCollectionId: widget.collection.id,
        preSelectedCollectionName: widget.collection.name,
        destinationName: widget.collection.name,
        thirdSlotOverride: Builder(
          builder: (sheetContext) {
            return QuickActionCard(
              icon: Icons.document_scanner_outlined,
              color: Colors.deepOrange,
              label: TranslationService.translate(
                sheetContext,
                'quick_batch_scan',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
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
            );
          },
        ),
        contextualQuickActions: [
          Builder(
            builder: (sheetContext) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: QuickActionCard(
                          icon: Icons.upload_file,
                          color: Colors.blue,
                          label: TranslationService.translate(
                            sheetContext,
                            'import_books',
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _importBooks();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: QuickActionCard(
                          icon: Icons.share,
                          color: Colors.green,
                          label: TranslationService.translate(
                            sheetContext,
                            'action_share',
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _shareCollection();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: QuickActionCard(
                          icon: Icons.delete,
                          color: Colors.red,
                          label: TranslationService.translate(
                            sheetContext,
                            'delete_collection_title',
                          ),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _deleteCollection();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
        actions: [],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'collection_detail_fab',
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
              // Header Banner
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6BB0A9), Color(0xFF5C8C9F)],
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
                  bottom: 16,
                  left: 16,
                  right: 16,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.collection.description != null &&
                          widget.collection.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            widget.collection.description!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  height: 1.4,
                                ),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                context,
                                totalCount.toString(),
                                TranslationService.translate(context, 'books'),
                                Icons.library_books,
                                Colors.white,
                              ),
                            ),
                            if (totalCount > 0) ...[
                              VerticalDivider(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1,
                                thickness: 1,
                              ),
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  ownedCount.toString(),
                                  TranslationService.translate(
                                    context,
                                    'status_owned',
                                  ),
                                  Icons.check_circle,
                                  Colors.greenAccent,
                                ),
                              ),
                              VerticalDivider(
                                color: Colors.white.withValues(alpha: 0.2),
                                width: 1,
                                thickness: 1,
                              ),
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  wantedCount.toString(),
                                  TranslationService.translate(
                                    context,
                                    'status_wanted',
                                  ),
                                  Icons.bookmark_border,
                                  Colors.orangeAccent,
                                ),
                              ),
                            ],
                          ],
                        ),
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
                                            semanticLabel:
                                                book.author != null &&
                                                    book.author!.isNotEmpty
                                                ? '${book.title}, ${book.author}'
                                                : book.title,
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
                                        // Status badge with label
                                        GestureDetector(
                                          onTap: () => _toggleBookStatus(book),
                                          child: Tooltip(
                                            message: book.isOwned
                                                ? TranslationService.translate(
                                                    context,
                                                    'status_owned',
                                                  )
                                                : TranslationService.translate(
                                                    context,
                                                    'status_wanted',
                                                  ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
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
                                                mainAxisSize: MainAxisSize.min,
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
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    book.isOwned
                                                        ? TranslationService.translate(
                                                            context,
                                                            'status_owned',
                                                          )
                                                        : TranslationService.translate(
                                                            context,
                                                            'status_wanted',
                                                          ),
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: book.isOwned
                                                          ? Colors.green
                                                          : Colors.orange,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        // Remove from collection button
                                        PopupMenuButton<String>(
                                          icon: Icon(
                                            Icons.more_vert,
                                            size: 20,
                                            color: Colors.grey[400],
                                          ),
                                          tooltip: '',
                                          padding: EdgeInsets.zero,
                                          onSelected: (value) {
                                            if (value == 'remove') {
                                              _confirmAndRemoveBook(book);
                                            } else if (value == 'toggle') {
                                              _toggleBookStatus(book);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem<String>(
                                              value: 'toggle',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    book.isOwned
                                                        ? Icons.bookmark_border
                                                        : Icons.check_circle,
                                                    size: 18,
                                                    color: book.isOwned
                                                        ? Colors.orange
                                                        : Colors.green,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    book.isOwned
                                                        ? TranslationService.translate(
                                                            context,
                                                            'status_wanted',
                                                          )
                                                        : TranslationService.translate(
                                                            context,
                                                            'status_owned',
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'remove',
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.remove_circle_outline,
                                                    size: 18,
                                                    color: Colors.red,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    TranslationService.translate(
                                                      context,
                                                      'remove_from_collection',
                                                    ),
                                                    style: const TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
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
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _confirmAndRemoveBook(CollectionBook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(context, 'remove_book_title')),
        content: Text(
          '${TranslationService.translate(context, 'remove_book_confirm')} "${book.title}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'remove')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _removeBook(book);
    }
  }

  Future<void> _toggleBookStatus(CollectionBook book) async {
    try {
      final newStatus = !book.isOwned;
      final api = Provider.of<ApiService>(context, listen: false);
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);

      // 1. Update the book's owned status. CollectionBook.bookId is the book's
      // uuid (cross-device identity), which addresses the update directly.
      await api.updateBook(book.bookId, {'owned': newStatus});

      // 2. If becoming owned, check/create copy
      if (newStatus) {
        final copies = await copyRepo.getBookCopies(book.bookId);

        if (copies.isEmpty) {
          await copyRepo.createCopy({
            'book_id': book.bookId,
            // library_id resolved by backend
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
        final statusMsg = newStatus
            ? TranslationService.translate(context, 'marked_as_owned')
            : TranslationService.translate(context, 'marked_as_wanted');
        AppSnackBar.success(
          context,
          '"${book.title}" - $statusMsg',
          duration: const Duration(seconds: 1),
        );
        _refreshBooks();
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error_updating_status')}: $e',
        );
      }
    }
  }
}
