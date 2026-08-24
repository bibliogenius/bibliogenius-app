import 'package:flutter/material.dart';

import '../services/curated_lists_service.dart';
import '../services/translation_service.dart';

/// The books a curated list holds: three of them, and the rest when the
/// reader asks.
///
/// Promoted out of `ImportCuratedListScreen`, which has always shown this,
/// so the ADR-066 suggestion card can show it too. Before the promotion the
/// pushed surface named a COUNT and no title while the browsed catalogue
/// listed them, which is the wrong way round: a card that arrives unasked
/// owes the reader more than one they went looking for.
///
/// Deliberately NOT a scrolling list by default. It renders inside whatever
/// already scrolls (a page, a dialog's content), and three rows is a preview
/// rather than a viewport. [maxExpandedHeight] is for the one caller that
/// cannot let 72 rows push its own controls off screen.
class CuratedBookPreview extends StatefulWidget {
  const CuratedBookPreview({
    super.key,
    required this.books,
    this.collapsedCount = 3,
    this.maxExpandedHeight,
    this.ownedIndexes = const {},
  });

  final List<CuratedBook> books;

  /// Indexes into [books] the reader already has, so the preview answers the
  /// question the count cannot: how much of this list is new to me.
  ///
  /// Indexes rather than ISBNs because ownership is decided by the ADR-060
  /// membrane, which matches an entry by ISBN OR by normalized title and
  /// author. A caller holding only ISBNs would silently drop every match the
  /// membrane made the other way, and under-report on exactly the entries
  /// whose ISBN is the corpus's weak spot.
  final Set<int> ownedIndexes;

  /// Rows shown before the reader asks for the rest.
  final int collapsedCount;

  /// Ceiling on the expanded height, above which the rows scroll among
  /// themselves. Null leaves them unbounded, which is right on a page.
  final double? maxExpandedHeight;

  /// What one entry is called, with the catalogue's own last resort.
  ///
  /// The name itself comes from [CuratedBook.displayTitle], shared with the
  /// import so the two cannot drift; an entry that offers no name at all
  /// falls back to its ISBN rather than rendering an empty row.
  static String displayTitle(CuratedBook book) =>
      book.displayTitle ?? book.isbn;

  @override
  State<CuratedBookPreview> createState() => _CuratedBookPreviewState();
}

class _CuratedBookPreviewState extends State<CuratedBookPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    if (books.isEmpty) return const SizedBox.shrink();

    final shownCount = _expanded
        ? books.length
        : (books.length < widget.collapsedCount
              ? books.length
              : widget.collapsedCount);
    Widget rows = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shownCount; i++)
          _Row(book: books[i], owned: widget.ownedIndexes.contains(i)),
      ],
    );

    final ceiling = widget.maxExpandedHeight;
    if (_expanded && ceiling != null) {
      rows = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: ceiling),
        child: SingleChildScrollView(child: rows),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rows,
        // Absent when everything is already on screen: a toggle that reveals
        // nothing is a dead control.
        if (books.length > widget.collapsedCount)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? TranslationService.translate(
                          context,
                          'curated_see_less',
                        )
                      : TranslationService.translate(
                          context,
                          'curated_see_all_books',
                          params: {'count': '${books.length}'},
                        ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.book, required this.owned});

  final CuratedBook book;

  /// The reader already has this one. Marked rather than hidden: the list is
  /// an editorial whole, and dropping its entries would misrepresent it.
  final bool owned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = CuratedBookPreview.displayTitle(book);
    final ownedLabel = TranslationService.translate(
      context,
      'catalog_already_in_library',
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        // One announcement per row (ADR-061 A2). The tick is the sighted
        // half of the statement and the label is the other half; neither
        // carries it alone, and colour never carries it at all.
        excludeSemantics: true,
        label: owned ? '$title, $ownedLabel' : title,
        child: Row(
          children: [
            if (owned)
              Tooltip(
                message: ownedLabel,
                child: Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              )
            else
              // Decorative: the title next to it is what the row says.
              const Icon(Icons.book, size: 16, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: owned ? theme.colorScheme.onSurfaceVariant : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
