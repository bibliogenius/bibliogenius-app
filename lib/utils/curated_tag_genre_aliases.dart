/// Bridge between the curated corpus's free-text tags and the app's closed
/// genre vocabulary (ADR-066).
///
/// The two vocabularies are deliberately NOT merged. Corpus tags are
/// editorial labels, rendered raw as chips on the import screen, and most of
/// them have no genre equivalent at all: of the 151 tags measured on
/// 2026-08-23, about fifty map to a genre and the hundred others (`prix`,
/// `classiques`, `informatique`, `nobel`, `francais`, `rentree`, `CM1`...)
/// name a prize, a language, a school level or a trade. Re-tagging the corpus
/// would mean discarding those or inventing a hundred false genres.
///
/// Two roads therefore lead from a label to a genre key, and this file is the
/// only door to both:
///
/// 1. the translation catalogues, through [genreAliases], which already know
///    every UI language's label for a key. This is what makes the reverse
///    mapping work outside French: genres are stored TRANSLATED in
///    `books.subjects`, so the key is the invariant and the stored label is
///    not;
/// 2. [curatedTagGenreAliases], the hand-written synonym table below, for the
///    corpus vocabulary that no translation covers (`polar`, `sf`, `shonen`).
///
/// Callers use [genreKeysForTags] and [genreKeysForStoredLabels] and never
/// learn which road answered.
///
/// Poisoning rule (ADR-059): the table's values are genre keys of the closed
/// list, so it can never file anything under a favorites-like label. A shared
/// "favoris" shelf marks affection, not theme. Both halves of that rule are
/// pinned by tests.
library;

import 'book_genres.dart';

/// Comparison form for any genre-ish label, corpus tag or stored shelf alike:
/// lowercased, diacritics folded, every run of non-alphanumerics collapsed to
/// a single space, trimmed.
///
/// Applied to BOTH sides of every comparison, so `science-fiction`,
/// `Science Fiction` and `science fiction` are one token, and `rentree`
/// matches `rentrée`. It is a strict superset of the trim-and-lowercase that
/// [selectedGenres] applies: everything that matched before still matches.
/// [selectedGenres] itself is deliberately left alone, it belongs to the
/// genre picker.
String normalizeGenreToken(String value) {
  final folded = _foldDiacritics(value.toLowerCase());
  return folded
      .split(RegExp(r'[^0-9a-z]+'))
      .where((word) => word.isNotEmpty)
      .join(' ');
}

/// Combining marks are not stripped by `toLowerCase`, and Dart has no NFD in
/// the core library, so the handful of Latin-1 letters the corpus actually
/// uses are mapped directly. Mirrors the Rust `normalize_identity_text`
/// intent without pulling a dependency for eight characters.
String _foldDiacritics(String value) {
  const map = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'œ': 'oe', 'æ': 'ae', 'ß': 'ss',
  };
  final buffer = StringBuffer();
  for (final char in value.split('')) {
    buffer.write(map[char] ?? char);
  }
  return buffer.toString();
}

/// Corpus tag (normalized) to genre key.
///
/// Keys are normalized with [normalizeGenreToken]; look them up through
/// [genreKeysForTags], never directly.
///
/// Entries are only added when the tag names a genre unambiguously. The
/// tags left out are left out ON PURPOSE and must stay out: prize names
/// (`prix`, `nobel`, `booker`, `pulitzer`, `goncourt`, `hugo`, `nebula`,
/// `edgar`...), languages and nationalities (`francais`, `english`,
/// `american`, `russe`, `japonais`, `scandinave`...), the tech vocabulary
/// (`informatique`, `backend`, `php`, `rust`, `python`, `drupal`...), school
/// levels (`ecole`, `college`, `CM1`, `sixieme`, `rentree`) and vague
/// registers (`aventure`, `fiction`, `psychologique`, `nature`, `design`).
/// `hugo` is the sharpest case: a science-fiction prize AND a French
/// novelist, so mapping it would produce exactly the confusion the whole
/// discovery doctrine exists to avoid. Those lists match through
/// books-in-common instead, which is the doctrine anyway.
const Map<String, String> curatedTagGenreAliases = {
  'adolescent': 'genre_teen_fiction',
  'album': 'genre_picture_book',
  'amour': 'genre_romance',
  'anticipation': 'genre_near_future',
  'antiracisme': 'genre_politics_society',
  'art': 'genre_arts',
  'autobiographie': 'genre_biography',
  'bd': 'genre_franco_belgian',
  'bien etre': 'genre_wellbeing',
  'biographie': 'genre_biography',
  'classics': 'genre_classic_fiction',
  'classiques': 'genre_classic_fiction',
  'comics': 'genre_comics_us',
  'contemporain': 'genre_contemporary_fiction',
  'cuisine': 'genre_cooking',
  'cyberpunk': 'genre_cyberpunk',
  'dev personnel': 'genre_wellbeing',
  'droits civiques': 'genre_politics_society',
  'dystopie': 'genre_dystopia',
  'epique': 'genre_epic_fantasy',
  'epouvante': 'genre_horror',
  'essai': 'genre_essay',
  'fantasy': 'genre_fantasy',
  'feminisme': 'genre_politics_society',
  'gastronomie': 'genre_cooking',
  'histoire': 'genre_history',
  'horreur': 'genre_horror',
  'jeunesse': 'genre_youth',
  'lgbtq': 'genre_politics_society',
  'manga': 'genre_manga',
  'meditation': 'genre_spirituality',
  'non fiction': 'genre_essay',
  'philosophie': 'genre_philosophy',
  'poesie': 'genre_poetry_theatre',
  'polar': 'genre_detective',
  'politique': 'genre_politics_society',
  'recettes': 'genre_cooking',
  'romance': 'genre_romance',
  'sagesse': 'genre_spirituality',
  'science': 'genre_science',
  'science fiction': 'genre_scifi',
  'seinen': 'genre_manga',
  'sf': 'genre_scifi',
  'shonen': 'genre_manga',
  'societe': 'genre_politics_society',
  'spiritualite': 'genre_spirituality',
  'suspense': 'genre_thriller',
  'theatre': 'genre_poetry_theatre',
  'thriller': 'genre_thriller',
  'vers': 'genre_poetry_theatre',
  'vulgarisation': 'genre_science',
  'xxe siecle': 'genre_twentieth_century',
  '20th century': 'genre_twentieth_century',
  'young adult': 'genre_young_adult',
};

/// Genre keys named by a curated list's [tags].
///
/// Tries the translation catalogues first (a list tagged with the very label
/// the app shows for a genre resolves without any table entry), then the
/// synonym table.
Set<String> genreKeysForTags(Iterable<String> tags) {
  final keys = <String>{};
  for (final tag in tags) {
    final token = normalizeGenreToken(tag);
    if (token.isEmpty) continue;
    final translated = _keyForTranslatedLabel(token);
    if (translated != null) {
      keys.add(translated);
      continue;
    }
    final alias = curatedTagGenreAliases[token];
    if (alias != null) keys.add(alias);
  }
  return keys;
}

/// Genre keys carried by stored subject labels (shelves and genres alike).
///
/// This is the reverse map the language trap needs: a genre filed in French
/// is stored as "Roman policier", and a reader now running the app in
/// English must still see it recognised as `genre_detective`.
Set<String> genreKeysForStoredLabels(Iterable<String> labels) {
  final keys = <String>{};
  for (final label in labels) {
    final token = normalizeGenreToken(label);
    if (token.isEmpty) continue;
    final translated = _keyForTranslatedLabel(token);
    if (translated != null) {
      keys.add(translated);
      continue;
    }
    final alias = curatedTagGenreAliases[token];
    if (alias != null) keys.add(alias);
  }
  return keys;
}

/// The genre key whose label, in ANY supported UI language, normalizes to
/// [token]. Null when no genre is named by it.
String? _keyForTranslatedLabel(String token) => _labelIndex[token];

/// Normalized label to genre key, across every supported locale. Memoised:
/// it walks 57 genres times the supported locales, which is real work to
/// repeat per book at import time.
///
/// An EMPTY result is not cached. `genreAliases` reads the translation
/// catalogues, and before they load it returns nothing at all; caching that
/// would leave the reverse map permanently blind for the whole process,
/// which no caller could diagnose from its behaviour.
Map<String, String>? _labelIndexMemo;

Map<String, String> get _labelIndex {
  final memo = _labelIndexMemo;
  if (memo != null && memo.isNotEmpty) return memo;
  return _labelIndexMemo = _buildLabelIndex();
}

/// Drops the memoised label index. For tests that load catalogues between
/// cases; the app never needs it.
void resetGenreLabelIndexForTest() => _labelIndexMemo = null;

Map<String, String> _buildLabelIndex() {
  final index = <String, String>{};
  for (final genre in allBookGenres) {
    for (final alias in genreAliases(genre.key)) {
      final token = normalizeGenreToken(alias);
      // First writer wins: the closed list guarantees distinct labels, and
      // a collision could only come from a catalogue typo, where silently
      // keeping the first is better than letting the last overwrite.
      if (token.isNotEmpty) index.putIfAbsent(token, () => genre.key);
    }
  }
  return index;
}
