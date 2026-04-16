import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'cached_book_cover.dart';

/// Scope of the carousel — controls which [ThemeProvider] flag backs its
/// visibility so the own-lib and peer-lib carousels can be toggled
/// independently.
enum RecentlyAddedCarouselScope { ownLib, peerLib }

/// Horizontal strip of recently added books displayed at the top of a library
/// view. Books are filtered via [Book.isNew] (addedAt within the "new badge"
/// threshold). The user can dismiss the carousel; the choice is persisted in
/// [ThemeProvider] so the setting survives across navigation and can be
/// restored from the settings screen.
class RecentlyAddedCarousel extends StatelessWidget {
  const RecentlyAddedCarousel({
    super.key,
    required this.books,
    required this.scope,
    this.maxItems = 5,
    this.onBookTap,
  });

  final List<Book> books;
  final RecentlyAddedCarouselScope scope;
  final int maxItems;

  /// Optional override for tap handling. Defaults to GoRouter push to
  /// `/books/:id` (own-lib route). Peer lib screens should pass a custom
  /// handler because their detail route differs.
  final void Function(Book book)? onBookTap;

  bool _hidden(ThemeProvider provider) => switch (scope) {
    RecentlyAddedCarouselScope.ownLib => provider.carouselHiddenOwnLib,
    RecentlyAddedCarouselScope.peerLib => provider.carouselHiddenPeerLib,
  };

  Future<void> _setHidden(ThemeProvider provider, bool hidden) =>
      switch (scope) {
        RecentlyAddedCarouselScope.ownLib => provider.setCarouselHiddenOwnLib(
          hidden,
        ),
        RecentlyAddedCarouselScope.peerLib => provider.setCarouselHiddenPeerLib(
          hidden,
        ),
      };

  void _dismiss(BuildContext context, ThemeProvider provider) {
    _setHidden(provider, true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(context, 'carousel_hidden_snackbar'),
        ),
        action: SnackBarAction(
          label: TranslationService.translate(context, 'action_undo'),
          onPressed: () => _setHidden(provider, false),
        ),
      ),
    );
  }

  List<Book> _recentBooks() {
    final recent = books.where((b) => b.isNew).toList();
    recent.sort((a, b) => b.addedAt!.compareTo(a.addedAt!));
    return recent.take(maxItems).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThemeProvider>();
    if (_hidden(provider)) return const SizedBox.shrink();

    final recent = _recentBooks();
    if (recent.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesign.spacingMd,
        vertical: AppDesign.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    TranslationService.translate(
                      context,
                      'recently_added_title',
                    ),
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                tooltip: TranslationService.translate(
                  context,
                  'carousel_hide_tooltip',
                ),
                onPressed: () => _dismiss(context, provider),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: AppDesign.spacingSm),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: recent.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppDesign.spacingSm),
              itemBuilder: (context, index) {
                final book = recent[index];
                return _CarouselCover(
                  book: book,
                  onTap: () {
                    if (onBookTap != null) {
                      onBookTap!(book);
                    } else {
                      context.push('/books/${book.id}', extra: book);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CarouselCover extends StatelessWidget {
  const _CarouselCover({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = [
      book.title,
      if (book.author != null && book.author!.isNotEmpty) book.author!,
    ].join(' — ');

    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        child: SizedBox(
          width: 100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
                child: CachedBookCover(
                  imageUrl: book.coverUrl,
                  width: 100,
                  height: 130,
                  fit: BoxFit.cover,
                  semanticLabel: semanticLabel,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
