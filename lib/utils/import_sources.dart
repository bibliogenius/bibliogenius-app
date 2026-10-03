/// What a library export says about the reading, read the same way whatever
/// produced the file.
///
/// The first imports carried the books and nothing else: a Babelio shelf of
/// 448 books, 397 of them marked "Lu", arrived as 448 books "to read". Every
/// export names its reading columns, its statuses and its rating scale
/// differently, so the knowledge lives in two places:
///
/// - a generic reading of the header names and the values, in English and in
///   French, which any spreadsheet benefits from;
/// - an [ImportSource] per export format we have seen, which only says what
///   the generic reading cannot guess (author order, rating scale).
///
/// Adding a format means adding a source here, not a branch in the importer.
/// See docs/import/README.md for the rules and how to add one.
library;

import 'dart:convert';

import 'import_columns.dart';

/// How a source writes a person's name in its author column.
enum AuthorOrder {
  /// "Joëlle Zask": stored as it stands.
  givenNameFirst,

  /// "Zask Joëlle": Babelio. Turned around on the way in, or the library
  /// holds the same writer twice, once from Babelio and once from every
  /// other source.
  surnameFirst,
}

/// An export format we know, recognised by its header row.
class ImportSource {
  const ImportSource._({
    required this.id,
    required this.authorOrder,
    this.ratingScale,
    this.readsDates = true,
  });

  /// Stable name, for logs and tests.
  final String id;

  final AuthorOrder authorOrder;

  /// Top of the source's rating scale (5 stars), or null to infer it from the
  /// values: a column where nothing exceeds 5 is read as out of 5.
  final int? ratingScale;

  /// Whether the date columns found by name are reading dates. Off for
  /// Babelio, whose only date is when the book was entered into Babelio.
  final bool readsDates;

  /// Babelio "Biblio_export": `ISBN;Titre;Auteur;Editeur;Date de publication;
  /// Date d'entrée dans Babelio;Statut;Note`, Windows-1252, authors surname
  /// first, a 0 to 5 rating where 0.0 means "not rated".
  ///
  /// Its entry date is not a reading date: on the one export we hold, 302 of
  /// 448 books share the day the reader moved their shelf into Babelio.
  static const babelio = ImportSource._(
    id: 'babelio',
    authorOrder: AuthorOrder.surnameFirst,
    ratingScale: 5,
    readsDates: false,
  );

  /// Goodreads "library export": `My Rating` out of 5, `Exclusive Shelf`,
  /// `Date Read`, authors given name first.
  static const goodreads = ImportSource._(
    id: 'goodreads',
    authorOrder: AuthorOrder.givenNameFirst,
    ratingScale: 5,
  );

  /// Anything else: the header names and the values decide.
  static const generic = ImportSource._(
    id: 'generic',
    authorOrder: AuthorOrder.givenNameFirst,
  );

  /// The source that wrote a file with these headers (lowercased, trimmed).
  static ImportSource detect(List<String> headers) {
    if (headers.any((h) => h.contains('babelio'))) return babelio;
    if (headers.contains('exclusive shelf') && headers.contains('my rating')) {
      return goodreads;
    }
    return generic;
  }

  /// The author cell as the library should store it.
  String? author(String? raw) => switch (authorOrder) {
    AuthorOrder.givenNameFirst => raw,
    AuthorOrder.surnameFirst => raw == null ? null : givenNameFirst(raw),
  };
}

/// The reading one row carries, every field optional.
typedef ImportedReading = ({
  String? status,
  int? rating,
  String? startedAt,
  String? finishedAt,
});

/// Where the reading lives in a file, resolved once from its header row.
class ReadingColumns {
  ReadingColumns._({
    required this.source,
    required this.status,
    required this.rating,
    required this.started,
    required this.finished,
    required this.ratingScale,
  });

  final ImportSource source;
  final int status;
  final int rating;
  final int started;
  final int finished;
  final int ratingScale;

  /// Resolve the columns of [headers] (lowercased, trimmed). [ratingCells]
  /// is every value of the rating column, used only when the source does not
  /// state its scale.
  factory ReadingColumns.resolve(
    List<String> headers, {
    ImportSource? source,
    Iterable<String?> Function(int column)? ratingCells,
  }) {
    final from = source ?? ImportSource.detect(headers);
    final rating = findRatingColumn(headers);
    return ReadingColumns._(
      source: from,
      status: findReadingStatusColumn(headers),
      rating: rating,
      started: from.readsDates ? findStartedDateColumn(headers) : -1,
      finished: from.readsDates ? findFinishedDateColumn(headers) : -1,
      ratingScale:
          from.ratingScale ??
          inferRatingScale(
            rating >= 0 && ratingCells != null ? ratingCells(rating) : const [],
          ),
    );
  }

  /// Whether the file says anything about the reading at all.
  bool get any => status >= 0 || rating >= 0 || started >= 0 || finished >= 0;

  /// Read one row. [cell] returns the raw value at a column, or null.
  ImportedReading read(String? Function(int column) cell) {
    final finishedAt = parseImportedDate(cell(finished));
    var readStatus = parseReadingStatus(cell(status));
    // A finish date is a reading that ended: Goodreads leaves the shelf to
    // the reader, but a date on a book "to read" is the shelf lagging behind.
    if (finishedAt != null && (readStatus == null || readStatus == 'to_read')) {
      readStatus = 'read';
    }
    return (
      status: readStatus,
      rating: parseImportedRating(cell(rating), scale: ratingScale),
      startedAt: parseImportedDate(cell(started)),
      finishedAt: finishedAt,
    );
  }
}

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// Lowercase, accents off, punctuation as spaces: "À lire", "a-lire" and
/// "A_LIRE" all read "a lire".
String _fold(String raw) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyyoa';
  final buffer = StringBuffer();
  for (final rune in raw.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final i = from.indexOf(char);
    buffer.write(i >= 0 ? to[i] : char);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r"[-_'’./]+"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Every way an export we know of, or a person filling a spreadsheet, writes
/// a reading status, folded by [_fold].
const Map<String, String> _statusWords = {
  // read
  'lu': 'read', 'lue': 'read', 'deja lu': 'read', 'termine': 'read',
  'read': 'read', 'finished': 'read', 'done': 'read',
  // reading
  'en cours': 'reading', 'en cours de lecture': 'reading',
  'reading': 'reading', 'currently reading': 'reading',
  // to_read
  'a lire': 'to_read', 'pal': 'to_read', 'non lu': 'to_read',
  'to read': 'to_read', 'unread': 'to_read', 'want to read': 'to_read',
  // abandoned
  'abandonne': 'abandoned', 'abandon': 'abandoned', 'abandoned': 'abandoned',
  'did not finish': 'abandoned', 'dnf': 'abandoned',
  // wanting: Babelio's "Pense-bête" is a list of books to get hold of
  'pense bete': 'wanting', 'envie': 'wanting', 'liste d envies': 'wanting',
  'wishlist': 'wanting', 'wish': 'wanting', 'wanted': 'wanting',
  'wanting': 'wanting',
};

/// The app's reading status for an imported cell, or null when the cell is
/// empty or says something we do not know: the book then keeps the default,
/// rather than a guess.
String? parseReadingStatus(String? raw) {
  if (raw == null) return null;
  return _statusWords[_fold(raw)];
}

/// The scale a rating column uses when its source does not say: out of 5
/// unless a value exceeds 5.
int inferRatingScale(Iterable<String?> cells) {
  for (final cell in cells) {
    final value = _ratingValue(cell);
    if (value != null && value.$1 > 5) return 10;
  }
  return 5;
}

/// The number in a rating cell and, when the cell spells it ("4/5"), its scale.
(double, int?)? _ratingValue(String? raw) {
  if (raw == null) return null;
  final match = RegExp(
    r'^\s*(\d+(?:[.,]\d+)?)\s*(?:/\s*(\d+))?\s*$',
  ).firstMatch(raw);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (value == null) return null;
  final scale = match.group(2) == null ? null : int.tryParse(match.group(2)!);
  return (value, scale);
}

/// The app stores a rating out of 10 (half stars on a 5-star scale).
///
/// 0 is "not rated" in every export we know (Babelio writes 0.0, Goodreads 0),
/// so it is read as no rating rather than as the worst one.
int? parseImportedRating(String? raw, {required int scale}) {
  final parsed = _ratingValue(raw);
  if (parsed == null) return null;
  final (value, ownScale) = parsed;
  final top = ownScale ?? scale;
  if (value <= 0 || top <= 0 || value > top) return null;
  return (value * 10 / top).round().clamp(1, 10);
}

/// An imported date as the app stores it (ISO 8601), or null.
///
/// Accepts `2024-06-09`, `2024/06/09` (Goodreads), either followed by a time,
/// and `09/06/2024` (day first, as French exports write it). `0000-00-00`, a
/// month 13 or a 31 February are no date, not an error.
String? parseImportedDate(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  int y, m, d;
  final isoMatch = RegExp(
    r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})',
  ).firstMatch(value);
  final dayFirst = RegExp(
    r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})',
  ).firstMatch(value);
  if (isoMatch != null) {
    y = int.parse(isoMatch.group(1)!);
    m = int.parse(isoMatch.group(2)!);
    d = int.parse(isoMatch.group(3)!);
  } else if (dayFirst != null) {
    d = int.parse(dayFirst.group(1)!);
    m = int.parse(dayFirst.group(2)!);
    y = int.parse(dayFirst.group(3)!);
  } else {
    return null;
  }
  if (y < 1000 || m < 1 || m > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, m, d);
  // DateTime rolls 31 February over into March; a date that moved was not one.
  if (date.month != m || date.day != d) return null;
  return date.toIso8601String();
}

/// Particles that belong to a surname: "Le Carré", "Da Costa", "de Bruycker".
const Set<String> _particles = {
  'de',
  'du',
  'des',
  "d'",
  'la',
  'le',
  'les',
  'von',
  'van',
  'der',
  'den',
  'di',
  'da',
  'del',
  'della',
  'dos',
  'das',
  'do',
  'ten',
  'ter',
  'zu',
  'mac',
};

bool _isParticle(String token) => _particles.contains(token.toLowerCase());

/// "Zask Joëlle" as "Joëlle Zask", one name at a time.
///
/// The surname is the first word, plus the words that follow a particle
/// ("Le Carré John", "Da Costa Mélissa"); a particle the source pushed to the
/// end goes back in front of the surname ("Bruycker Daniel de" is Daniel de
/// Bruycker). A one-word name ("Voltaire") stays as it is.
///
/// A two-word surname with no particle cannot be told apart from a two-word
/// given name: "Vargas Llosa Mario" and "Burke James Lee" have the same shape.
/// The first word is taken as the surname, which is right far more often.
///
/// Several names in one cell (`;` or `&`) are each turned around and joined
/// with ", ", the way the app joins co-authors. A comma is not a separator
/// here: in a surname-first file it may sit between surname and given name.
String givenNameFirst(String raw) {
  final names = raw
      .split(RegExp(r'\s*[;&]\s*'))
      .map(_givenNameFirstOne)
      .where((n) => n.isNotEmpty)
      .toList();
  return names.join(', ');
}

String _givenNameFirstOne(String raw) {
  // "Zask, Joëlle": the comma already says where the surname ends.
  final comma = raw.indexOf(',');
  if (comma > 0) {
    final given = raw.substring(comma + 1).trim();
    final surname = raw.substring(0, comma).trim();
    return given.isEmpty ? surname : '$given $surname';
  }
  final tokens = raw.trim().split(RegExp(r'\s+'))
    ..removeWhere((t) => t.isEmpty);
  if (tokens.length < 2) return tokens.join(' ');

  final trailing = <String>[];
  while (tokens.length > 2 && _isParticle(tokens.last)) {
    trailing.insert(0, tokens.removeLast());
  }

  var surnameLength = 1;
  while (surnameLength < tokens.length - 1 &&
      _isParticle(tokens[surnameLength - 1])) {
    surnameLength++;
  }
  final surname = tokens.sublist(0, surnameLength);
  final given = tokens.sublist(surnameLength);
  return [...given, ...trailing, ...surname].join(' ');
}

// ---------------------------------------------------------------------------
// Bytes
// ---------------------------------------------------------------------------

/// Windows-1252 code points for 0x80..0x9F, where it departs from Latin-1.
/// `’` (0x92) and `œ` (0x9C) are everywhere in French titles.
const List<int> _cp1252High = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, //
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, //
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178, //
];

/// The text of an imported file, whatever it was saved as.
///
/// UTF-8 first, without its byte order mark. A file that is not valid UTF-8
/// is read as Windows-1252, which is what Babelio and Excel on Windows write:
/// reading it as UTF-8 threw on the first "é", and the import failed before
/// reading a single book.
String decodeImportText(List<int> bytes) {
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final body = start == 0 ? bytes : bytes.sublist(start);
  try {
    return utf8.decode(body);
  } on FormatException {
    return String.fromCharCodes(
      body.map((b) => b >= 0x80 && b <= 0x9F ? _cp1252High[b - 0x80] : b),
    );
  }
}
