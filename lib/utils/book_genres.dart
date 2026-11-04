/// The closed list of genres offered when a book is added or edited.
///
/// A genre is not a schema concept: once picked it becomes an ordinary shelf (a
/// `tags` row) nested under a lazily created "Genre" parent. It therefore
/// inherits shelf filtering, renaming, syncing and deletion for free, and a
/// user who never picks a genre never gets a single extra row.
///
/// Two consequences drive the design of this file:
///
/// - `tags.name` is UNIQUE across the whole tree, so every label below must be
///   distinct from every other label, in every language. `bookGenresLabels` is
///   guarded by a test.
/// - a tag stores its label as plain text, so the label is frozen in whatever
///   language was active when the book was filed. Matching a subject back to a
///   genre therefore compares against every known translation, not just the
///   current one. See [genreAliases].
library;

import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// One entry of the closed genre list.
class BookGenre {
  /// Translation key, and the genre's stable identity across languages.
  final String key;

  /// Icon shown on the suggestion chip. Top-level genres only.
  final IconData? icon;

  /// Optional second level, revealed only once the parent is picked.
  final List<BookGenre> children;

  const BookGenre(this.key, {this.icon, this.children = const []});
}

/// Translation key of the parent shelf every genre hangs under.
const String genreRootKey = 'genre_root';

/// The curated taxonomy. Two levels: a short list of genres always visible, and
/// subgenres that only surface once their parent is selected. Kept deliberately
/// small; density is the failure mode this feature exists to avoid.
const List<BookGenre> bookGenres = [
  BookGenre(
    'genre_novel',
    icon: Icons.menu_book,
    children: [
      BookGenre('genre_contemporary_fiction'),
      BookGenre('genre_classic_fiction'),
      BookGenre('genre_historical_fiction'),
      BookGenre('genre_romance'),
      BookGenre('genre_short_stories'),
    ],
  ),
  BookGenre(
    'genre_crime',
    icon: Icons.local_police_outlined,
    children: [
      BookGenre('genre_detective'),
      BookGenre('genre_thriller'),
      BookGenre('genre_noir'),
      BookGenre('genre_spy'),
      BookGenre('genre_true_crime'),
    ],
  ),
  BookGenre(
    'genre_scifi',
    icon: Icons.rocket_launch_outlined,
    children: [
      BookGenre('genre_near_future'),
      BookGenre('genre_space_opera'),
      BookGenre('genre_dystopia'),
      BookGenre('genre_cyberpunk'),
      BookGenre('genre_alternate_history'),
    ],
  ),
  BookGenre(
    'genre_fantasy',
    icon: Icons.auto_awesome_outlined,
    children: [
      BookGenre('genre_epic_fantasy'),
      BookGenre('genre_urban_fantasy'),
      BookGenre('genre_supernatural'),
      BookGenre('genre_horror'),
    ],
  ),
  BookGenre(
    'genre_comics',
    icon: Icons.brush_outlined,
    children: [
      BookGenre('genre_franco_belgian'),
      BookGenre('genre_comics_us'),
      BookGenre('genre_manga'),
      BookGenre('genre_graphic_novel'),
    ],
  ),
  BookGenre(
    'genre_youth',
    icon: Icons.child_care_outlined,
    children: [
      BookGenre('genre_picture_book'),
      BookGenre('genre_first_reads'),
      BookGenre('genre_teen_fiction'),
      BookGenre('genre_young_adult'),
    ],
  ),
  BookGenre(
    'genre_essay',
    icon: Icons.lightbulb_outline,
    children: [
      BookGenre('genre_philosophy'),
      BookGenre('genre_science'),
      BookGenre('genre_politics_society'),
      BookGenre('genre_spirituality'),
    ],
  ),
  BookGenre(
    'genre_history',
    icon: Icons.account_balance_outlined,
    children: [
      BookGenre('genre_antiquity'),
      BookGenre('genre_middle_ages'),
      BookGenre('genre_early_modern'),
      BookGenre('genre_twentieth_century'),
    ],
  ),
  BookGenre('genre_biography', icon: Icons.person_outline),
  BookGenre('genre_poetry_theatre', icon: Icons.theater_comedy_outlined),
  BookGenre(
    'genre_practical',
    icon: Icons.handyman_outlined,
    children: [
      BookGenre('genre_cooking'),
      BookGenre('genre_travel'),
      BookGenre('genre_nature_garden'),
      BookGenre('genre_wellbeing'),
      BookGenre('genre_sport'),
    ],
  ),
  BookGenre(
    'genre_arts',
    icon: Icons.palette_outlined,
    children: [
      BookGenre('genre_fine_arts'),
      BookGenre('genre_photography'),
      BookGenre('genre_architecture'),
      BookGenre('genre_music'),
      BookGenre('genre_cinema'),
    ],
  ),
];

/// Every genre of the closed list, parents and children alike.
List<BookGenre> get allBookGenres => [
  for (final genre in bookGenres) ...[genre, ...genre.children],
];

/// The top-level genre [child] belongs to, or null when [child] is itself
/// top-level or absent from the list.
BookGenre? parentOfGenre(BookGenre child) {
  for (final parent in bookGenres) {
    if (parent.children.any((c) => c.key == child.key)) return parent;
  }
  return null;
}

/// Every known label for [key], lowercased, across all supported UI languages.
///
/// A shelf keeps the label it was created with, so a library filed in French
/// and later read in English still carries "Polar". Recognising the genre back
/// means accepting any of its translations, not only the current one.
Set<String> genreAliases(String key) {
  return {
    for (final locale in TranslationService.supportedLocales)
      TranslationService.translateByLocale(locale, key).trim().toLowerCase(),
  }..remove(key.toLowerCase());
}

/// The genres carried by [subjects], matched across every UI language.
///
/// [subjects] are the raw shelf labels stored on the book. Anything that is not
/// part of the closed list (a user's own shelf) is simply ignored.
List<BookGenre> selectedGenres(List<String> subjects) {
  final normalized = subjects.map((s) => s.trim().toLowerCase()).toSet();
  return [
    for (final genre in allBookGenres)
      if (genreAliases(genre.key).any(normalized.contains)) genre,
  ];
}

/// The label to file a book under for [genre], in the language in use now.
String genreLabel(BuildContext context, BookGenre genre) =>
    TranslationService.translate(context, genre.key);
