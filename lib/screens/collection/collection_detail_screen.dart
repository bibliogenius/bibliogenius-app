import '../../models/collection.dart';
import '../../models/collection_book.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/repositories/copy_repository.dart';
import '../../services/api_service.dart';
import '../../services/collection_export_service.dart';
import '../../services/translation_service.dart';
import '../../utils/language_constants.dart';
import '../../widgets/collection_share_sheet.dart';
import '../../utils/collection_display.dart';
import '../../providers/book_refresh_notifier.dart';
import '../../providers/theme_provider.dart';
import '../../utils/book_status.dart';
import '../../utils/ownership_mark.dart';
import '../../utils/series_ordering.dart';
import '../../widgets/app_snack_bar.dart';
import '../../widgets/not_owned_treatment.dart';
import '../../widgets/volume_badge.dart';
import '../../widgets/cached_book_cover.dart';
import '../../widgets/configurable_action_card.dart';
import '../../widgets/premium_empty_state.dart';
import 'collection_delete_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/recommendation_display.dart';
import '../../widgets/genie_app_bar.dart';

/// A readable-on-light variant of a status color: Material swatches drop to
/// their 700 shade (enough contrast for text/icons on a light tinted pill);
/// any non-swatch color is returned unchanged.
Color _readableOnLight(Color color) =>
    color is MaterialColor ? color.shade700 : color;

class CollectionDetailScreen extends StatefulWidget {
  final Collection collection;

  const CollectionDetailScreen({Key? key, required this.collection})
    : super(key: key);

  @override
  _CollectionDetailScreenState createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  late Future<List<CollectionBook>> _booksFuture;

  /// The collection being displayed. Mutable copy of `widget.collection` so a
  /// rename shows on this screen without rebuilding it from a fresh Collection
  /// (the list screen reloads on return and picks the new name up there).
  late Collection _collection;

  /// Whether this collection is a series (ordered reading list). Mutable copy of
  /// `_collection.isSeries` so the toggle can flip it without rebuilding
  /// the whole screen from a fresh Collection.
  late bool _isSeries;

  /// Optimistic ordering applied right after a drag-and-drop, before the backend
  /// round-trip resolves. While set, it is the source of truth for the list so
  /// the reordered row does not snap back or flash a spinner. Cleared by
  /// `_refreshBooks`, which reloads the authoritative order.
  List<CollectionBook>? _localOrder;

  /// Dismissal of the "how ordering works" help card, persisted so it stays
  /// hidden once the user closes it (loaded from SharedPreferences on open).
  bool _seriesHelpDismissed = true;

  static const _seriesHelpDismissedKey = 'series_help_dismissed';

  @override
  void initState() {
    super.initState();
    _collection = widget.collection;
    _isSeries = _collection.isSeries;
    _loadSeriesHelpDismissed();
    _refreshBooks();
  }

  Future<void> _loadSeriesHelpDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_seriesHelpDismissedKey) ?? false;
    if (mounted) setState(() => _seriesHelpDismissed = dismissed);
  }

  Future<void> _dismissSeriesHelp() async {
    setState(() => _seriesHelpDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seriesHelpDismissedKey, true);
  }

  void _refreshBooks() {
    setState(() {
      _localOrder = null;
      _booksFuture = Provider.of<CollectionRepository>(
        context,
        listen: false,
      ).getCollectionBooks(_collection.id);
    });
  }

  /// Persist a drag-and-drop reorder: renumber the volumes 1..N in the new order.
  /// Applies the new order optimistically so the UI stays stable, then writes the
  /// positions to the backend (shared with the book-detail frise).
  Future<void> _reorderVolumes(
    List<CollectionBook> books,
    int oldIndex,
    int newIndex,
  ) async {
    final updated = reorderedSequentialVolumes(books, oldIndex, newIndex);
    // Apply the new order after this frame. Mutating the list synchronously
    // inside onReorder marks the MouseRegion-bearing rows (tooltips, ink hover)
    // dirty while the mouse tracker is mid device-update; a fast drop on desktop
    // then trips a framework assertion (mouse_tracker _debugDuringDeviceUpdate)
    // that breaks the build and blanks the list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _localOrder = updated);
    });

    final repo = Provider.of<CollectionRepository>(context, listen: false);
    try {
      await persistVolumeNumbers(repo, _collection.id, updated, books);
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error')}: $e',
        );
        _refreshBooks();
      }
    }
  }

  Future<void> _toggleSeries(bool value) async {
    final repo = Provider.of<CollectionRepository>(context, listen: false);
    final refresher = context.read<BookRefreshNotifier>();
    // Optimistic flip so the per-volume controls appear immediately.
    setState(() => _isSeries = value);
    try {
      await repo.markCollectionAsSeries(_collection.id, value);
      // Flipping series-ness changes what external discovery derives
      // (ADR-060): stale the recommendation caches like any catalogue
      // mutation.
      refresher.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSeries = !value);
      AppSnackBar.error(
        context,
        '${TranslationService.translate(context, 'error')}: $e',
      );
    }
  }

  /// Prompt for a volume number (empty clears it), then persist and re-sort.
  Future<void> _editVolume(CollectionBook book) async {
    final result = await showVolumeEditor(context, current: book.volumeNumber);
    if (result == null || !mounted) return;

    final repo = Provider.of<CollectionRepository>(context, listen: false);
    try {
      await repo.setBookVolumeNumber(
        _collection.id,
        book.bookId,
        result.volumeNumber,
      );
      if (mounted) _refreshBooks();
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error')}: $e',
        );
      }
    }
  }

  /// Rename the collection from a small dialog.
  ///
  /// Never offered on the favorites collection: its label comes from the i18n
  /// catalogue and not from the stored name (ADR-064), so the write would be
  /// invisible on screen. The Rust side refuses it too, for the callers that
  /// do not go through this screen.
  Future<void> _renameCollection() async {
    final repo = Provider.of<CollectionRepository>(context, listen: false);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameCollectionDialog(initialName: _collection.name),
    );
    if (!mounted) return;
    // Cancelled, emptied, or unchanged: nothing to write.
    if (newName == null || newName.isEmpty || newName == _collection.name) {
      return;
    }

    try {
      await repo.renameCollection(_collection.id, newName);
      if (!mounted) return;
      setState(() {
        _collection = Collection(
          id: _collection.id,
          name: newName,
          description: _collection.description,
          source: _collection.source,
          createdAt: _collection.createdAt,
          updatedAt: DateTime.now().toIso8601String(),
          totalBooks: _collection.totalBooks,
          ownedBooks: _collection.ownedBooks,
        );
      });
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error_renaming_collection')}: $e',
        );
      }
    }
  }

  Future<void> _deleteCollection() async {
    final repo = Provider.of<CollectionRepository>(context, listen: false);
    final refresher = context.read<BookRefreshNotifier>();
    final outcome = await confirmCollectionDeletion(
      context,
      repo,
      _collection.id,
    );
    if (outcome == CollectionDeleteOutcome.cancelled) return;
    if (!mounted) return;

    try {
      if (outcome == CollectionDeleteOutcome.withBooks) {
        await repo.deleteCollectionWithBooks(_collection.id);
      } else {
        await repo.deleteCollection(_collection.id);
      }
      // A deleted series collection must drop its external cards.
      refresher.refresh();
      // The reader has taken their import back; the app takes its own
      // dismissal back too, or the list can never be suggested again.
      if (mounted) await forgetCuratedListDismissal(context, _collection);
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
              _collection.id,
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
    final refresher = context.read<BookRefreshNotifier>();
    try {
      await Provider.of<CollectionRepository>(
        context,
        listen: false,
      ).removeBookFromCollection(_collection.id, book.bookId);
      // Membership drives the series discovery lookups (ADR-060).
      refresher.refresh();

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
      const exportService = CollectionExportService();
      final theme = context.read<ThemeProvider>();

      // The favorites collection stores a technical sentinel name
      // (ADR-064): export the translated display name, never the sentinel.
      var shared = _collection;
      if (shared.isFavorites) {
        shared = Collection(
          id: shared.id,
          name: collectionDisplayName(context, shared),
          description: shared.description,
          source: shared.source,
          createdAt: shared.createdAt,
          updatedAt: shared.updatedAt,
          totalBooks: shared.totalBooks,
          ownedBooks: shared.ownedBooks,
        );
      }

      // Formatted BEFORE the panel opens: it shows the reader what they are
      // about to send, and offers to copy those exact bytes.
      final languages = resolveReaderLanguages(
        theme.locale.languageCode,
        theme.userLanguages,
      );
      // The SAME source the screen lists above, through the repository: a
      // panel that shows what you are about to send must read where the
      // screen reads, or it will promise books the file does not carry.
      final books = await context.read<CollectionRepository>()
          .getCollectionBooks(shared.id);
      final yaml = exportService.exportToYaml(
        shared,
        books,
        // Names the sender in the file. Without it the receiver cannot tell
        // two identically named lists apart: their own "Favoris" and the one
        // they just accepted. The library name is what the invitation sheet
        // already shows, so the two ways of reaching someone agree.
        contributorName: theme.libraryName,
        contentLanguages: languages,
      );
      if (!mounted) return;

      final name = shared.name;
      final message = TranslationService.translate(
            context,
            'collection_share_message',
          )
          .replaceAll('{name}', name)
          .replaceAll('{count}', '${books.length}');

      await showCollectionShareSheet(
        context,
        collectionName: name,
        bookCount: books.length,
        yaml: yaml,
        languages: languages,
        // The failure had to be caught HERE: this closure is invoked from
        // the panel, outside the try/catch below, so a throw from the system
        // share sheet went nowhere and the button just looked inert.
        onShare: (origin) async {
          try {
            await exportService.shareYaml(
              collectionName: name,
              yaml: yaml,
              message: message,
              sharePositionOrigin: origin,
            );
          } catch (e) {
            if (!mounted) return;
            AppSnackBar.error(
              context,
              '${TranslationService.translate(context, 'export_fail')}: $e',
            );
          }
        },
      );
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'export_fail')}: $e',
        );
      }
    }
  }

  Future<void> _addBook() async {
    final result = await context.push(
      '/books/add',
      extra: {
        'collectionId': _collection.id,
        'collectionName': collectionDisplayName(context, _collection),
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
        title: collectionDisplayName(context, _collection),
        transparent: true, // 🌟 Transparent AppBar
        showQuickActions: false,
        preSelectedCollectionId: _collection.id,
        preSelectedCollectionName: collectionDisplayName(context, _collection),
        destinationName: collectionDisplayName(context, _collection),
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
                    'collectionId': _collection.id,
                    'collectionName': collectionDisplayName(
                      context,
                      _collection,
                    ),
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
              // Laid out two per row: a fourth card on a single row is too
              // narrow to read its label on a phone. The rename card is
              // absent on the favorites collection, whose label is
              // translated rather than stored (ADR-064).
              final cards = <Widget>[
                QuickActionCard(
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
                QuickActionCard(
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
                if (!_collection.isFavorites)
                  QuickActionCard(
                    // shade800, not the base swatch: the card paints its icon
                    // on a white circle, where Colors.orange sits at ~2.1:1
                    // and misses the 3:1 that rule A2 asks of an icon.
                    icon: Icons.drive_file_rename_outline,
                    color: Colors.orange.shade800,
                    label: TranslationService.translate(
                      sheetContext,
                      'rename',
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _renameCollection();
                    },
                  ),
                QuickActionCard(
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
              ];

              final rows = <Widget>[];
              for (var i = 0; i < cards.length; i += 2) {
                final right = i + 1 < cards.length ? cards[i + 1] : null;
                if (rows.isNotEmpty) {
                  rows.add(const SizedBox(height: 12));
                }
                rows.add(
                  Row(
                    children: [
                      Expanded(child: cards[i]),
                      const SizedBox(width: 12),
                      // An odd count keeps the last card at half width
                      // rather than stretching it across the row.
                      Expanded(child: right ?? const SizedBox.shrink()),
                    ],
                  ),
                );
              }

              return Column(mainAxisSize: MainAxisSize.min, children: rows);
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
          final books = _localOrder ?? snapshot.data ?? [];
          // While an optimistic reorder is in flight, keep showing the list
          // instead of the loading spinner.
          final loading =
              snapshot.connectionState == ConnectionState.waiting &&
              _localOrder == null;

          // Reading-status vocabulary, built once per rebuild and shared by
          // every row rather than re-translated per teaser.
          final statusByValue = {
            for (final s in getStatusOptions(
              context,
              Provider.of<ThemeProvider>(
                context,
                listen: false,
              ).inventoryStatusesEnabled,
            ))
              s.value: s,
          };

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
                      if (_collection.description != null &&
                          _collection.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _collection.description!,
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
                                  Icons.bookmark_add_outlined,
                                  // Container token: light enough to sit on
                                  // the colored header gradient (ADR-063,
                                  // no more hard-coded orange).
                                  Theme.of(
                                    context,
                                  ).colorScheme.tertiaryContainer,
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

              // Collapsible series section: the on/off switch plus the folded
              // description + ordering help.
              _buildSeriesSection(),

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
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.only(
                          top: 16,
                          left: 16,
                          right: 16,
                          bottom: 100,
                        ),
                        // Dragging is offered only in series mode, via the
                        // explicit handle below; a manual collection keeps a
                        // plain, non-draggable list.
                        buildDefaultDragHandles: false,
                        onReorder: (oldIndex, newIndex) {
                          if (_isSeries) {
                            _reorderVolumes(books, oldIndex, newIndex);
                          }
                        },
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
                                        if (_isSeries) ...[
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: Icon(
                                                Icons.drag_indicator,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.outline,
                                                semanticLabel:
                                                    TranslationService.translate(
                                                      context,
                                                      'series_reorder_handle',
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        _buildCoverWithVolume(book),
                                        const SizedBox(width: 14),
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
                                                      // Theme token, not a
                                                      // hard-coded grey
                                                      // (ADR-063).
                                                      color: book.isOwned
                                                          ? null
                                                          : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
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
                                              _buildReadingStatusChip(
                                                book,
                                                statusByValue,
                                              ),
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
                                            // Wanted state on theme tokens,
                                            // aligned with the shared badge
                                            // vocabulary (ADR-063).
                                            child: Container(
                                              padding: const EdgeInsets.all(7),
                                              decoration: BoxDecoration(
                                                color: book.isOwned
                                                    ? Colors.green.withValues(
                                                        alpha: 0.1,
                                                      )
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .tertiaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: book.isOwned
                                                      ? Colors.green.withValues(
                                                          alpha: 0.3,
                                                        )
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .tertiary
                                                            .withValues(
                                                              alpha: 0.3,
                                                            ),
                                                ),
                                              ),
                                              child: Icon(
                                                book.isOwned
                                                    ? Icons.check_circle
                                                    : Icons
                                                          .bookmark_add_outlined,
                                                size: 16,
                                                color: book.isOwned
                                                    ? Colors.green.shade700
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onTertiaryContainer,
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
                                                        ? Icons
                                                              .bookmark_add_outlined
                                                        : Icons.check_circle,
                                                    size: 18,
                                                    color: book.isOwned
                                                        ? Theme.of(
                                                            context,
                                                          ).colorScheme.tertiary
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

  /// Compact, low-emphasis series toggle. It is an optional setting, so it stays
  /// a slim row (small inline icon + label + switch) rather than a prominent
  /// card. The ordering help appears below only once the collection is actually
  /// a series (and until the user dismisses it).
  Widget _buildSeriesSection() {
    // The series toggle flips `collections.source`, which is the favorites
    // collection's IDENTITY (ADR-064): flipping it silently untypes the
    // collection (raw sentinel name resurfaces, marker and engine signal
    // die). The typed collection simply does not offer the toggle; the
    // Rust side refuses the flip too (defense in depth for HTTP callers).
    if (_collection.isFavorites) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final active = _isSeries;
    final accent = theme.colorScheme.primary;
    return Padding(
      // Symmetric with the book list's 16px top padding so the encart sits
      // balanced between the header banner and the first book.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: active ? accent.withValues(alpha: 0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: SwitchListTile(
              value: _isSeries,
              onChanged: _toggleSeries,
              activeThumbColor: accent,
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              secondary: Icon(
                Icons.auto_stories_outlined,
                size: 22,
                color: active ? accent : theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(
                TranslationService.translate(
                  context,
                  'collection_series_toggle',
                ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (active) _buildSeriesHelp(),
        ],
      ),
    );
  }

  /// Dismissible contextual help explaining how to order the volumes (drag by
  /// the handle, or tap the cover number). Shown only while the collection is a
  /// series and the user has not dismissed it this session.
  Widget _buildSeriesHelp() {
    if (!_isSeries || _seriesHelpDismissed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                TranslationService.translate(context, 'series_help_text'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            InkWell(
              onTap: _dismissSeriesHelp,
              borderRadius: BorderRadius.circular(20),
              child: Tooltip(
                message: TranslationService.translate(context, 'close'),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Small reading-status pill (to read / reading / read / wishlist) for the
  /// teaser, reusing the shared status vocabulary so labels, icons and colors
  /// match the rest of the app. Renders nothing when the status is empty or
  /// outside the known set. [statusByValue] is precomputed once per build so the
  /// status list is not rebuilt and re-translated for every row.
  Widget _buildReadingStatusChip(
    CollectionBook book,
    Map<String, BookStatus> statusByValue,
  ) {
    final value = book.readingStatus;
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    final status = statusByValue[value];
    if (status == null) return const SizedBox.shrink();

    // Darken the status color for text/icon so it meets WCAG AA on the light
    // tinted background; keep the original hue for the fill and border.
    final textColor = _readableOnLight(status.color);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: status.color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 13, color: textColor),
            const SizedBox(width: 4),
            // Flexible so a long label (e.g. "En cours de lecture") ellipsizes
            // inside a narrow teaser instead of overflowing on mobile.
            Flexible(
              child: Text(
                status.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The book cover, with the tappable volume badge overlaid on its top-left
  /// corner in series mode. Overlaying keeps the row compact so the title and
  /// metadata stay readable on a narrow phone.
  Widget _buildCoverWithVolume(CollectionBook book) {
    // Shared not-owned treatment (ADR-063): desaturated cover + badge,
    // replacing this screen's bespoke orange vocabulary.
    final mark = ownershipMarkFromFlags(owned: book.isOwned);
    final cover = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: OwnershipCoverTreatment(
        mark: mark,
        child: CachedBookCover(
          imageUrl: book.coverUrl,
          width: 50,
          height: 75,
          semanticLabel: book.author != null && book.author!.isNotEmpty
              ? '${book.title}, ${book.author}'
              : book.title,
        ),
      ),
    );
    if (!_isSeries && mark == OwnershipMark.none) return cover;
    return Stack(
      children: [
        cover,
        if (_isSeries)
          Positioned(
            top: 2,
            left: 2,
            child: VolumeBadge(
              volumeNumber: book.volumeNumber,
              onTap: () => _editVolume(book),
            ),
          ),
        if (mark != OwnershipMark.none)
          Positioned(
            top: 2,
            right: 2,
            child: OwnershipBadge(mark: mark, iconSize: 10),
          ),
      ],
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

/// The rename dialog, a widget of its own so it owns its text controller.
///
/// A controller created by the caller and disposed right after `showDialog`
/// resolves is still in use by the field while the dialog animates out, which
/// throws "A TextEditingController was used after being disposed" and blanks
/// the frame. Owning it here ties its life to the dialog's.
class _RenameCollectionDialog extends StatefulWidget {
  const _RenameCollectionDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameCollectionDialog> createState() =>
      _RenameCollectionDialogState();
}

class _RenameCollectionDialogState extends State<_RenameCollectionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(TranslationService.translate(context, 'rename_collection')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: TranslationService.translate(context, 'name'),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(TranslationService.translate(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(TranslationService.translate(context, 'rename')),
        ),
      ],
    );
  }
}
