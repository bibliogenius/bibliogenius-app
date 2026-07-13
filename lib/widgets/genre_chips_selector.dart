import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/tag_repository.dart';
import '../services/genre_tag_service.dart';
import '../services/translation_service.dart';
import '../utils/book_genres.dart';

/// Suggests the closed list of genres next to the free-form shelf selector.
///
/// A genre is just a shelf: picking one appends its label to the book's shelves
/// and, the first time only, creates the "Genre" shelf and the genre under it.
/// Nothing here is a new kind of data, so genres filter, rename, sync and delete
/// like any other shelf.
///
/// Only the top level is shown until a genre is picked; its subgenres surface
/// then, and only then. Density is the failure mode this feature exists to
/// avoid.
class GenreChipsSelector extends StatefulWidget {
  /// The book's shelves, as stored in `subjects`. Genres live in there too.
  final List<String> selectedShelves;
  final ValueChanged<List<String>> onShelvesChanged;

  const GenreChipsSelector({
    super.key,
    required this.selectedShelves,
    required this.onShelvesChanged,
  });

  @override
  State<GenreChipsSelector> createState() => _GenreChipsSelectorState();
}

class _GenreChipsSelectorState extends State<GenreChipsSelector> {
  /// Genre key currently being resolved, so its chip can show progress and
  /// double taps cannot create the shelf twice.
  String? _pending;

  List<BookGenre> get _selected => selectedGenres(widget.selectedShelves);

  /// The genre whose subgenres are worth showing: the selected top-level one,
  /// or the parent of the selected subgenre.
  BookGenre? get _expanded {
    for (final genre in _selected) {
      final top = parentOfGenre(genre) ?? genre;
      if (top.children.isNotEmpty) return top;
    }
    return null;
  }

  bool _isSelected(BookGenre genre) =>
      _selected.any((g) => g.key == genre.key);

  /// Drop every label of [genre], in any language it may have been filed under.
  List<String> _withoutGenre(List<String> shelves, BookGenre genre) {
    final aliases = genreAliases(genre.key);
    return shelves
        .where((s) => !aliases.contains(s.trim().toLowerCase()))
        .toList();
  }

  Future<void> _toggle(BookGenre genre) async {
    if (_pending != null) return;

    if (_isSelected(genre)) {
      var shelves = _withoutGenre(widget.selectedShelves, genre);
      // Unselecting a genre takes its subgenres with it: a book left on
      // "Thriller" but no longer on "Polar" would be incoherent.
      for (final child in genre.children) {
        shelves = _withoutGenre(shelves, child);
      }
      widget.onShelvesChanged(shelves);
      return;
    }

    setState(() => _pending = genre.key);

    try {
      final service = GenreTagService(context.read<TagRepository>());
      final parent = parentOfGenre(genre);

      final chain = [
        TranslationService.translate(context, genreRootKey),
        if (parent != null) genreLabel(context, parent),
        genreLabel(context, genre),
      ];

      final shelf = await service.resolveShelfChain(chain);
      if (!mounted) return;

      final shelves = List<String>.from(widget.selectedShelves);
      if (!shelves.contains(shelf.name)) shelves.add(shelf.name);
      widget.onShelvesChanged(shelves);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'tag_creation_error'),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expanded = _expanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(theme),
        const SizedBox(height: 8),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final genre in bookGenres) _buildChip(theme, genre),
          ],
        ),

        if (expanded != null) ...[
          const SizedBox(height: 12),
          Text(
            TranslationService.translate(context, 'genre_refine'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final child in expanded.children) _buildChip(theme, child),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLabel(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            Icons.category_outlined,
            size: 20,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  TranslationService.translate(context, 'genre_picker_label'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color.lerp(
                      theme.colorScheme.primary,
                      Colors.black,
                      0.25,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                TranslationService.translate(context, 'genre_picker_helper'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.85,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip(ThemeData theme, BookGenre genre) {
    final isPending = _pending == genre.key;

    return FilterChip(
      label: Text(genreLabel(context, genre)),
      selected: _isSelected(genre),
      onSelected: _pending != null ? null : (_) => _toggle(genre),
      avatar: isPending
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : (genre.icon != null
                ? Icon(genre.icon, size: 18, color: theme.colorScheme.primary)
                : null),
    );
  }
}
