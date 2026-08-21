import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/book_repository.dart';
import '../models/book.dart';
import '../models/recommendation.dart';
import '../providers/recommendation_provider.dart';
import '../providers/theme_provider.dart';
import '../services/discovery_service.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/author_identity.dart';
import '../utils/book_display.dart';
import '../utils/recommendation_display.dart';
import '../widgets/book_cover_card.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/external_suggestion_sheet.dart';
import '../widgets/suggestion_tile.dart';

/// Everything the library knows about one author, plus what it does not
/// hold yet (ADR-061): the reader's own books first, then unowned works
/// resolved by the ADR-060 author lane.
///
/// The page is the right host for author completion: on the dashboard such
/// a card arrives unprompted and competes for two scarce slots, here the
/// reader just said this author interests them.
///
/// Identity is STRING-keyed in v1: the route carries a display name and
/// matching goes through [AuthorIdentity], which reuses the discovery
/// normalization (words sorted, so the inverted "Last, First" form of
/// French catalogues matches). Spelling variants therefore still split into
/// two pages; the resolver-`source_id` upgrade is a separate chantier.
///
/// The discovery half resolves ON OPEN under the shared 24h throttle: the
/// visit is the explicit gesture. It shows nothing while resolving, nothing
/// on failure and nothing when the answer is ambiguous, never an error
/// surface.
class AuthorScreen extends StatefulWidget {
  const AuthorScreen({super.key, required this.authorName});

  /// Display name as it appears on the book that led here.
  final String authorName;

  @override
  State<AuthorScreen> createState() => _AuthorScreenState();
}

class _AuthorScreenState extends State<AuthorScreen> {
  List<Book>? _localBooks;
  List<Recommendation> _discovered = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final provider = context.read<RecommendationProvider>();
    final langs = context.read<ThemeProvider>().userLanguages;
    final repository = context.read<BookRepository>();

    // The identity index doubles as the vocabulary of individual author
    // names, so one shared derivation serves both the local matching and
    // the membrane. Memoised provider-side: opening this page costs neither
    // a library pass nor a re-derivation (ADR-061 sections 3 and 4).
    final vocabulary = await provider.authorVocabulary();
    final authorKey = AuthorIdentity.matchKey(widget.authorName);

    // No author filter crosses the FFI (`get_all_books` drops
    // `BookFilter.author`), so the selection happens here, over the list the
    // repository already serves.
    List<Book> local;
    try {
      local = (await repository.getBooks())
          .where((b) => AuthorIdentity.names(b.author, authorKey, vocabulary))
          .toList();
    } catch (e) {
      debugPrint('AuthorScreen: local books failed: $e');
      local = const [];
    }
    if (!mounted) return;
    setState(() => _localBooks = local);

    // No anchor, no request: an author none of whose local books carries a
    // checksum-valid ISBN produces no lookup at all, exactly like a profile
    // author (ADR-060 section 3.2). The validation is not decorative, see
    // [DiscoveryService.anchorIsbnsFrom].
    final anchors = DiscoveryService.anchorIsbnsFrom(
      local.map((book) => book.isbn),
    );

    final discovered = await provider.authorPageDiscovery(
      name: widget.authorName,
      anchorIsbns: anchors,
      langs: langs,
    );
    if (!mounted) return;
    setState(() => _discovered = discovered);
  }

  @override
  Widget build(BuildContext context) {
    final local = _localBooks;
    // Dismissals apply on every surface (ADR-060 section 4.5); a narrow
    // selector rebuilds this page only when one changes.
    final dismissed = context.select<RecommendationProvider, Set<String>>(
      (provider) => provider.dismissedExternalKeys,
    );
    final discovered = _discovered
        .where((c) => !dismissed.contains(c.externalKey))
        .toList();

    return Scaffold(
      appBar: AppBar(
        // The page IS this author, so the title is a heading, never a
        // button: the only tappable author names are the ones that lead
        // here (ADR-061 section 7, decision A2).
        title: Semantics(header: true, child: Text(widget.authorName)),
      ),
      body: local == null
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppDesign.maxContentWidth,
                ),
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                  children: [
                    FriezeSectionHeader(
                      icon: Icons.menu_book_outlined,
                      title: TranslationService.translate(
                        context,
                        'author_page_in_library',
                        params: {'count': '${local.length}'},
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (local.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          TranslationService.translate(
                            context,
                            'author_page_no_local_books',
                          ),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    else
                      _LocalBooksGrid(books: local),
                    if (discovered.isNotEmpty) ...[
                      const SizedBox(height: 32),
                      FriezeSectionHeader(
                        icon: Icons.explore_outlined,
                        title: TranslationService.translate(
                          context,
                          'author_page_to_discover',
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Frieze-register card (not the heavier dashboard
                      // SectionCard): gives the list a defined edge instead
                      // of floating loose in the page, same treatment as
                      // the "complete the series" card on the book page.
                      FriezeCard(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 6,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < discovered.length; i++) ...[
                              if (i > 0) const SuggestionSeparator(),
                              _DiscoveredTile(suggestion: discovered[i]),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The author's own books, as the standard cover grid. Each cover is a
/// single announced button (Rule A1): [BookCoverCard] labels its image but
/// carries no button semantics of its own.
class _LocalBooksGrid extends StatelessWidget {
  const _LocalBooksGrid({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.65,
        crossAxisSpacing: AppDesign.spacingMd,
        mainAxisSpacing: AppDesign.spacingMd,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return Semantics(
          button: true,
          excludeSemantics: true,
          label: BookDisplay.coverLabelOf(context, book),
          child: BookCoverCard(
            book: book,
            onTap: () => context.push('/books/${book.id}', extra: book),
          ),
        );
      },
    );
  }
}

/// One unowned work: the shared suggestion tile, so the badge, the reason
/// line, the single screen-reader announcement and the pre-import preview
/// sheet are literally the same code as on the dashboard.
class _DiscoveredTile extends StatelessWidget {
  const _DiscoveredTile({required this.suggestion});

  final Recommendation suggestion;

  @override
  Widget build(BuildContext context) {
    final externalKey = suggestion.externalKey;
    return SuggestionTile(
      suggestion: suggestion,
      onTap: () => ExternalSuggestionSheet.show(context, suggestion),
      onDismiss: externalKey == null
          ? null
          : () => dismissExternalSuggestionWithUndo(context, externalKey),
      dismissTooltip: TranslationService.translate(
        context,
        'recommendation_not_interested',
      ),
    );
  }
}
