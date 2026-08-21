import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/collection_repository.dart';
import '../models/recommendation.dart';
import '../providers/book_refresh_notifier.dart';
import '../providers/recommendation_provider.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/recommendation_display.dart';
import 'app_snack_bar.dart';
import 'cached_book_cover.dart';

/// Pre-import preview sheet for an EXTERNAL suggestion (ADR-060 section
/// 4.6): availability shown before the book exists locally, in the spirit
/// of the curated-list import. Guaranteed minimal action: add to wishlist
/// (`reading_status = 'wanting'`, ISBN dedup on creation). Adding
/// activates the existing provider join, so peer availability surfaces on
/// its own afterwards. Never a dead end: the sheet always offers at least
/// that one action. Procurement links are deliberately excluded (separate
/// scoping chantier).
class ExternalSuggestionSheet extends StatefulWidget {
  const ExternalSuggestionSheet({super.key, required this.suggestion});

  final Recommendation suggestion;

  static Future<void> show(BuildContext context, Recommendation suggestion) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExternalSuggestionSheet(suggestion: suggestion),
    );
  }

  @override
  State<ExternalSuggestionSheet> createState() =>
      _ExternalSuggestionSheetState();
}

class _ExternalSuggestionSheetState extends State<ExternalSuggestionSheet> {
  bool _availableInNetwork = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  /// Fire-and-forget availability probe: who in the network has this ISBN,
  /// before the book exists locally. No result means no line (no empty
  /// state), same doctrine as the curated import screen.
  Future<void> _loadAvailability() async {
    final isbn = widget.suggestion.book.isbn;
    final ffi = FfiService();
    if (isbn == null || isbn.isEmpty || !ffi.isInitialized) return;
    final providers = await ffi.getIsbnProviders([isbn]);
    if (!mounted || providers.isEmpty) return;
    setState(() => _availableInNetwork = true);
  }

  /// The ordinal the card announced, when this suggestion completes a
  /// series. It becomes the new book's volume number so the frieze places
  /// it at the right position instead of appending it.
  int? get _seriesOrdinal {
    for (final reason in widget.suggestion.reasons) {
      if (reason.type != 'series_missing_volume') continue;
      return int.tryParse(reason.params?['ordinal'] ?? reason.value);
    }
    return null;
  }

  /// File a series-lane addition into the LOCAL series collection it
  /// completes (ADR-062 section 11). Unowned wishlist books are already
  /// first-class collection members, and the frieze renders them with its
  /// "wanted" treatment, so this writes into a state the app displays.
  ///
  /// Best-effort by design: the book is created first and kept whatever
  /// happens here. Failing to file must never cost the reader the add.
  Future<void> _fileIntoSeriesCollection(
    CollectionRepository collections,
    String bookId,
  ) async {
    final collectionId = widget.suggestion.seriesCollectionId;
    if (collectionId == null) return;
    try {
      await collections.addBookToCollection(collectionId, bookId);
      await collections.setBookVolumeNumber(
        collectionId,
        bookId,
        _seriesOrdinal,
      );
    } catch (e) {
      debugPrint('ExternalSuggestionSheet: series filing failed: $e');
    }
  }

  /// The created book's uuid, which the create endpoint answers either at
  /// the top level or nested under `book` (the curated-import pattern).
  String? _createdBookId(dynamic data) {
    if (data is Map && data['book'] is Map) {
      final id = data['book']['id'];
      return id is String ? id : null;
    }
    if (data is Map && data['id'] is String) return data['id'] as String;
    return null;
  }

  /// Add to wishlist with ISBN dedup on creation: create first, and when
  /// creation rejects a duplicate, find the existing book instead (the
  /// curated-import pattern).
  Future<void> _addToWishlist() async {
    if (_adding) return;
    setState(() => _adding = true);
    final book = widget.suggestion.book;
    final api = context.read<ApiService>();
    final refresher = context.read<BookRefreshNotifier>();
    final recommendations = context.read<RecommendationProvider>();
    final collections = context.read<CollectionRepository>();
    final externalKey = widget.suggestion.externalKey;

    var added = false;
    var alreadyThere = false;
    String? bookId;
    try {
      final response = await api.createBook({
        if (book.isbn != null) 'isbn': book.isbn,
        'title': book.title,
        'reading_status': 'wanting',
        'owned': false,
        if (book.author != null) 'author': book.author,
        if (book.publicationYear != null)
          'publication_year': book.publicationYear,
        if (book.coverUrl != null) 'cover_url': book.coverUrl,
      });
      if (response.statusCode == 201) {
        added = true;
        bookId = _createdBookId(response.data);
      } else if (book.isbn != null) {
        final existing = await api.findBookByIsbn(book.isbn!);
        alreadyThere = existing != null;
        bookId = existing?.id;
      }
    } catch (e) {
      debugPrint('ExternalSuggestionSheet: wishlist add failed: $e');
    }

    if ((added || alreadyThere) && bookId != null) {
      await _fileIntoSeriesCollection(collections, bookId);
    }

    if (!mounted) return;
    setState(() => _adding = false);
    if (added || alreadyThere) {
      if (externalKey != null) {
        recommendations.hideExternalAfterImport(externalKey);
      }
      refresher.refresh();
      Navigator.of(context).pop();
      AppSnackBar.success(
        context,
        TranslationService.translate(
          context,
          alreadyThere
              ? 'external_suggestion_already_in_library'
              : 'external_suggestion_added',
        ),
      );
    } else {
      AppSnackBar.error(
        context,
        TranslationService.translate(context, 'external_suggestion_add_failed'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.suggestion.book;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final reason = widget.suggestion.reasons.isEmpty
        ? null
        : recommendationReasonLabel(context, widget.suggestion.reasons.first);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 72,
                  height: 108,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
                    color: colorScheme.surfaceContainerHighest,
                  ),
                  child: (book.coverUrl != null && book.coverUrl!.isNotEmpty)
                      ? CachedBookCover(
                          imageUrl: book.coverUrl,
                          fit: BoxFit.cover,
                          semanticLabel: [
                            book.title,
                            if (book.author != null) book.author!,
                          ].join(', '),
                        )
                      : Icon(
                          Icons.menu_book,
                          size: 28,
                          color: colorScheme.onSurfaceVariant,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          book.title,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (book.author != null && book.author!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          book.author!,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (book.publicationYear != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${book.publicationYear}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (reason != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          reason,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_availableInNetwork) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      TranslationService.translate(
                        context,
                        'external_suggestion_available_network',
                      ),
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _adding ? null : _addToWishlist,
                icon: _adding
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.favorite_border),
                label: Text(
                  TranslationService.translate(
                    context,
                    'external_suggestion_add_wishlist',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
