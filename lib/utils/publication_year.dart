/// Publication year extraction from the free-form dates metadata sources return.
///
/// No two external catalogues agree on the shape of a publication date:
/// OpenLibrary returns free text ("Jan 01, 2004", "c1998"), Google Books an ISO
/// date ("2004-01-01"), BNF and SUDOC a bare year. Callers used to guess, and
/// both guesses were wrong for the user:
///
/// - reading the first four characters turned "Jan 01, 2004" into "Jan ", which
///   is what the metadata refresh dialog proposed as a year;
/// - parsing the whole string as an integer returned null for every ISO date,
///   so the year silently vanished from the add/scan form.
///
/// The Rust lookup now normalises before answering, and this helper keeps the
/// Dart side honest for anything it did not go through (curated list imports,
/// older payloads, a source added later).
library;

/// Bounds a plausible publication year, so a volume number or a page count
/// caught in the same string cannot pass for one.
const int _minYear = 1000;
const int _maxYear = 2999;

final RegExp _digitGroup = RegExp(r'\d+');

/// Extract the publication year from a source-provided date string.
///
/// Returns the first standalone four-digit group in a plausible range, so
/// "Jan 01, 2004", "2004-01-01", "c2004" and "2004" all yield 2004. Digit
/// groups of any other length are skipped rather than truncated: a run of five
/// digits is not a year, and truncating it would invent one.
int? parsePublicationYear(String? raw) {
  if (raw == null) return null;
  for (final match in _digitGroup.allMatches(raw)) {
    final digits = match.group(0)!;
    if (digits.length != 4) continue;
    final year = int.parse(digits);
    if (year >= _minYear && year <= _maxYear) return year;
  }
  return null;
}

/// Canonical "YYYY" rendering of a source-provided date string, or null when it
/// carries no plausible year.
String? normalizePublicationYear(String? raw) =>
    parsePublicationYear(raw)?.toString();
