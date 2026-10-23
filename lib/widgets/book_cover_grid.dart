import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SliverGridRegularTileLayout;
import '../models/book.dart';
import '../services/translation_service.dart';
import '../utils/book_status.dart';
import 'book_cover_card.dart';
import 'selectable_book_tile.dart';

/// Whether the "new" band differentiates anything: when every book is new
/// (fresh import, brand new library), tagging them all is pure noise.
///
/// Evaluate it on the FULL library, never on a filtered or searched subset:
/// a search that isolates one fresh book is an all-new list, and the band
/// must survive there.
bool newBadgeIsInformative(List<Book> books) => books.any((b) => !b.isNew);

/// Sections of the grid when it is grouped by reading status, in display
/// order. Books in any other status (none, abandoned, wished...) fall into a
/// trailing "other" section.
const List<String> coverGridStatusGroups = ['reading', 'to_read', 'read'];

/// Rows shown per status section when grouped; "see all" opens the rest.
const int coverGridRowsPerStatus = 2;

/// Whether the covers grid splits into reading-status sections. Only while
/// browsing the whole library: under a status filter, a search or a shelf
/// the truncated sections would hide results, selection mode acts on the
/// whole list ("select all"), and inventory statuses replace the reading
/// ones, so every book would land in "other".
bool shouldGroupByReadingStatus({
  required bool enabled,
  required bool inventoryStatuses,
  required bool selecting,
  required bool statusFiltered,
  required bool searching,
  required bool shelfFiltered,
}) =>
    enabled &&
    !inventoryStatuses &&
    !selecting &&
    !statusFiltered &&
    !searching &&
    !shelfFiltered;

/// Splits [books] into the reading-status sections, keeping their order and
/// dropping the empty ones. The key is the status, null for the "other"
/// section.
List<MapEntry<String?, List<Book>>> groupBooksByReadingStatus(
  List<Book> books,
) {
  final groups = <String?, List<Book>>{
    for (final status in coverGridStatusGroups) status: <Book>[],
    null: <Book>[],
  };
  for (final book in books) {
    final status = book.readingStatus;
    groups[coverGridStatusGroups.contains(status) ? status : null]!.add(book);
  }
  return groups.entries.where((e) => e.value.isNotEmpty).toList();
}

class BookCoverGrid extends StatelessWidget {
  final List<Book> books;
  final Function(Book) onBookTap;
  final void Function(Book book, String newStatus)? onStatusChanged;

  /// Already-translated wishlist availability labels, keyed by ISBN.
  /// Only the wishlist filter passes this; books without an entry render
  /// no badge.
  final Map<String, String>? availabilityLabels;

  /// Whether new books wear the band. Callers that display a FILTERED subset
  /// must pass [newBadgeIsInformative] of the full library; when null, the
  /// grid falls back to evaluating its own (assumed complete) list.
  final bool? showNewBadge;

  /// Favorite book ids (ADR-064), one set per screen from the
  /// FavoritesProvider cache. Null renders no ribbon (peer grids, tests).
  final Set<String>? favoriteIds;

  /// Ids of the selected books while the grid is in selection mode; null
  /// (the default) outside it. In selection mode a tap toggles the book
  /// through [onBookTap] instead of opening it.
  final Set<String>? selectedIds;

  /// Long press on a book outside selection mode (enters it). Null disables
  /// the gesture.
  final void Function(Book book)? onBookLongPress;

  /// Maximum width of a cover; the grid fits as many columns as it allows.
  final double maxCoverExtent;

  /// Splits the grid into titled sections by reading status (see
  /// [groupBooksByReadingStatus]). Each status section shows at most
  /// [coverGridRowsPerStatus] rows; the "other" section is shown in full.
  final bool groupByReadingStatus;

  /// "See all" link beside each status section title, given the status to
  /// filter on. Null hides the links.
  final void Function(String status)? onSeeAllStatus;

  /// Number of books the "See all" link of a status section opens. The
  /// status filter may reach books the section leaves out (read but not
  /// owned), so the link names its own count when it differs from the
  /// section's. Null shows the bare link.
  final int Function(String status)? seeAllCount;

  const BookCoverGrid({
    super.key,
    required this.books,
    required this.onBookTap,
    this.onStatusChanged,
    this.availabilityLabels,
    this.showNewBadge,
    this.favoriteIds,
    this.selectedIds,
    this.onBookLongPress,
    this.maxCoverExtent = 150,
    this.groupByReadingStatus = false,
    this.onSeeAllStatus,
    this.seeAllCount,
  });

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_books, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No books found',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: maxCoverExtent, // Controls the width of items
      childAspectRatio: 0.65, // Standard book ratio (width / height)
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
    );
    // Evaluated once on the whole list, never per section: a section made
    // only of fresh books must keep its bands.
    final newBadge = showNewBadge ?? newBadgeIsInformative(books);

    if (!groupByReadingStatus) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: gridDelegate,
        itemCount: books.length,
        itemBuilder: (context, index) => _buildTile(books[index], newBadge),
      );
    }

    final groups = groupBooksByReadingStatus(books);
    return CustomScrollView(
      // Keeps pull-to-refresh working when the sections are short.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final group in groups) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            sliver: SliverToBoxAdapter(
              child: _buildSectionHeader(context, group.key, group.value),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                // The delegate's own column count, so the cap cuts exactly
                // at the end of a row.
                final columns =
                    (gridDelegate.getLayout(constraints)
                            as SliverGridRegularTileLayout)
                        .crossAxisCount;
                final shown = group.key == null
                    ? group.value
                    : group.value
                          .take(columns * coverGridRowsPerStatus)
                          .toList();
                return SliverGrid.builder(
                  gridDelegate: gridDelegate,
                  itemCount: shown.length,
                  itemBuilder: (context, index) =>
                      _buildTile(shown[index], newBadge),
                );
              },
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String? status,
    List<Book> books,
  ) {
    final title = TranslationService.translate(
      context,
      status == null ? 'books_group_other' : readingStatusLabelKey(status)!,
    );
    final seeAll = TranslationService.translate(context, 'books_group_see_all');
    final linkCount = status == null ? null : seeAllCount?.call(status);
    final linkLabel = linkCount != null && linkCount != books.length
        ? '$seeAll ($linkCount)'
        : seeAll;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              '$title (${books.length})',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        if (status != null && onSeeAllStatus != null)
          TextButton(
            onPressed: () => onSeeAllStatus!(status),
            child: Text(
              linkLabel,
              // The visible label is short; a screen reader hears which
              // section it opens.
              semanticsLabel: '$linkLabel, $title',
            ),
          ),
      ],
    );
  }

  Widget _buildTile(Book book, bool newBadge) {
    return SelectableBookTile(
      selected: selectedIds?.contains(book.id),
      semanticLabel: [
        book.title,
        if (book.author != null) book.author!,
      ].join(', '),
      onToggle: () => onBookTap(book),
      onLongPress: onBookLongPress != null
          ? () => onBookLongPress!(book)
          : null,
      child: BookCoverCard(
        book: book,
        onTap: () => onBookTap(book),
        onStatusChanged: onStatusChanged != null
            ? (status) => onStatusChanged!(book, status)
            : null,
        // Map lookup with a null ISBN just returns null (no badge).
        availabilityLabel: availabilityLabels?[book.isbn],
        showNewBadge: newBadge,
        isFavorite: favoriteIds?.contains(book.id) ?? false,
      ),
    );
  }
}
