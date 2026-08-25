import 'package:intl/intl.dart';

/// Formats a 0-5 star rating for the value announced to screen readers.
///
/// Ratings are stored 0-10 and halved for display, so a value is either whole
/// or a half step. Two things follow, and `toStringAsFixed(1)` gets both wrong:
///
/// - A whole rating must be announced "4", not "4.0". Half of all ratings are
///   whole, and "four point zero out of five" is noise in every language.
/// - The decimal separator belongs to the reader's locale. `toStringAsFixed`
///   always emits a dot, so a French, German, Turkish or Bulgarian reader was
///   read a separator their language does not use.
///
/// [localeTag] is a BCP-47 tag as returned by `Locale.toLanguageTag()`
/// (`fr`, `pt-BR`); `intl` canonicalises the dash form itself. An unrecognised
/// tag falls back to `intl`'s default locale rather than throwing: a rating is
/// never important enough to break a screen.
String formatStarRating(double rating, String localeTag) =>
    _formatFor(localeTag).format(rating);

String? _cachedTag;
NumberFormat? _cachedFormat;

/// One memoised formatter, rebuilt only when the locale changes.
///
/// Building a `NumberFormat` resolves the locale and parses a pattern, where
/// the `toStringAsFixed` this replaced allocated nothing. The statistics screen
/// builds one rating row per rated shelf and collection, eagerly rather than
/// through a `builder`, so a large library would otherwise construct dozens of
/// identical formatters per frame. A single entry is enough and is bounded by
/// construction: the reader has exactly one language at a time.
NumberFormat _formatFor(String localeTag) {
  if (_cachedTag == localeTag && _cachedFormat != null) return _cachedFormat!;
  NumberFormat format;
  try {
    format = NumberFormat.decimalPattern(localeTag);
  } catch (_) {
    format = NumberFormat.decimalPattern();
  }
  format
    ..minimumFractionDigits = 0
    ..maximumFractionDigits = 1;
  _cachedTag = localeTag;
  _cachedFormat = format;
  return format;
}
