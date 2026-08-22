import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/collection_repository.dart';
import '../models/collection.dart';
import '../models/collection_book.dart';
import '../providers/favorites_provider.dart';
import '../services/translation_service.dart';
import '../utils/collection_display.dart';
import 'cached_book_cover.dart';

/// Discreet favorites showcase for the profile page (ADR-064 follow-up):
/// the latest favorite covers plus the count, tapping through to the
/// standard Favorites collection detail. Pure display of existing data
/// (FavoritesProvider set + collection membership); the parent renders
/// nothing when there are no favorites, so the block never begs.
class FavoritesShowcase extends StatefulWidget {
  const FavoritesShowcase({super.key});

  /// Covers shown, latest marked first.
  static const int maxCovers = 4;

  @override
  State<FavoritesShowcase> createState() => _FavoritesShowcaseState();
}

class _FavoritesShowcaseState extends State<FavoritesShowcase> {
  FavoritesProvider? _favorites;
  Collection? _collection;
  List<CollectionBook> _latest = const [];

  /// The favorite id set the current [_latest] was loaded for, so provider
  /// notifications only refetch when membership actually changed.
  Set<String> _loadedFor = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _favorites = context.read<FavoritesProvider>()
        ..addListener(_onFavoritesChanged)
        ..ensureLoaded();
      _load();
    });
  }

  @override
  void dispose() {
    _favorites?.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    final ids = _favorites?.favoriteIds ?? const {};
    if (ids.length != _loadedFor.length || !ids.containsAll(_loadedFor)) {
      _load();
    }
  }

  Future<void> _load() async {
    final favorites = _favorites;
    if (favorites == null) return;
    final repo = context.read<CollectionRepository>();
    try {
      final collections = await repo.getCollections();
      final favoritesCollection = collections
          .cast<Collection?>()
          .firstWhere((c) => c!.isFavorites, orElse: () => null);
      if (!mounted) return;
      if (favoritesCollection == null) {
        setState(() {
          _collection = null;
          _latest = const [];
          _loadedFor = Set.of(favorites.favoriteIds);
        });
        return;
      }
      final books = await repo.getCollectionBooks(favoritesCollection.id);
      if (!mounted) return;
      setState(() {
        _collection = favoritesCollection;
        // Membership rows come back oldest first: latest marked first here.
        _latest = books.reversed.take(FavoritesShowcase.maxCovers).toList();
        _loadedFor = Set.of(favorites.favoriteIds);
      });
    } catch (_) {
      // Non-critical display block: keep whatever was rendered.
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = _collection;
    if (collection == null || _latest.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final count = collection.totalBooks;
    final booksLabel = TranslationService.translate(
      context,
      'collection_group_books_count',
    );
    final tapHint = TranslationService.translate(
      context,
      'collection_group_tap_hint',
    );
    final title = collectionDisplayName(context, collection);

    return Semantics(
      button: true,
      label: '$title, $count $booksLabel. $tapHint',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            context.push('/collections/${collection.id}', extra: collection),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              for (final book in _latest) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 40,
                    height: 60,
                    child: book.coverUrl != null && book.coverUrl!.isNotEmpty
                        ? CachedBookCover(
                            imageUrl: book.coverUrl!,
                            fit: BoxFit.cover,
                            placeholder: const SizedBox.shrink(),
                            errorWidget: const ColoredBox(
                              color: Colors.black12,
                              child: Icon(Icons.book_outlined, size: 18),
                            ),
                            semanticLabel: book.title,
                          )
                        : ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.book_outlined, size: 18),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              Text(
                '$count $booksLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
