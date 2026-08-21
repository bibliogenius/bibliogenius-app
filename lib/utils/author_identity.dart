import '../services/discovery_service.dart';

/// Author identity for the contextual discovery surfaces (ADR-061 section
/// 7, decision A3).
///
/// The problem this file exists to solve: `Book.author` is ONE Dart string.
/// The Rust DTO does hold a list (`Book.authors`), but `populate_authors`
/// flattens it with `names.join(", ")` and `FrbBook` carries only the
/// flattened form, so two very different situations reach Dart identical:
///
///     one author, catalogued the French way : "Le Guin, Ursula K."
///     two authors, joined by the FFI        : "Ursula K. Le Guin, Alia Sun"
///
/// Splitting on the comma unconditionally (what `ApiService.getAllAuthors`
/// does) turns the first case into two author pages that name nobody.
/// Never splitting turns the second into one page for the pair.
///
/// The way out needs no Rust change: `title_author_keys` on the Rust side
/// emits ONE KEY PER INDIVIDUAL AUTHOR, and those keys already cross the
/// FFI in `DiscoveryLookupInputs.libraryTitleAuthorKeys`. Their author
/// halves are the library's vocabulary of real, individual author names.
/// So we split on the comma but keep the split only when every part is a
/// name the library actually knows, and fall back to the whole string
/// otherwise. Precision before coverage, the ADR-060 rule.
///
/// Degraded case, accepted: below the ADR-059 profile floor the FFI returns
/// empty inputs, hence an empty vocabulary, hence the whole-string
/// fallback. Narrow, never wrong.
abstract final class AuthorIdentity {
  /// Comparison form of an author display name: the discovery identity
  /// normalization with the words sorted, so "Le Guin, Ursula K." and
  /// "Ursula K. Le Guin" compare equal.
  ///
  /// Word sorting mirrors [DiscoveryIdentityIndex], for the same reason:
  /// catalogues store the inverted form and an order-sensitive comparison
  /// silently matches nothing for those libraries.
  static String matchKey(String displayName) {
    final words = DiscoveryService.normalizeIdentityText(displayName).split(' ')
      ..sort();
    return words.where((w) => w.isNotEmpty).join(' ');
  }

  /// The library's vocabulary of individual author names, as match keys,
  /// read off the "title|author" identity keys the Rust index emits.
  static Set<String> vocabularyOf(Set<String> titleAuthorKeys) {
    final names = <String>{};
    for (final key in titleAuthorKeys) {
      final separator = key.lastIndexOf('|');
      if (separator < 0) continue;
      final name = matchKey(key.substring(separator + 1));
      if (name.isNotEmpty) names.add(name);
    }
    return names;
  }

  /// The individual authors of a book's flattened author string, as display
  /// names in their original order.
  ///
  /// Returns the whole trimmed string as a single name unless the comma or
  /// semicolon split yields at least two parts that the [vocabulary] all
  /// recognizes. An empty vocabulary therefore never splits anything.
  static List<String> split(String? flattened, Set<String> vocabulary) {
    final whole = flattened?.trim() ?? '';
    if (whole.isEmpty) return const [];

    final parts = whole
        .split(RegExp(r'[,;]'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) return [whole];
    if (parts.every((p) => vocabulary.contains(matchKey(p)))) return parts;
    return [whole];
  }

  /// True when [flattened] names the author [authorKey] (a [matchKey]).
  /// Used to select the local books of an author page without re-scanning
  /// the library through a filter the FFI does not expose.
  static bool names(
    String? flattened,
    String authorKey,
    Set<String> vocabulary,
  ) {
    if (authorKey.isEmpty) return false;
    return split(flattened, vocabulary).any((n) => matchKey(n) == authorKey);
  }
}
