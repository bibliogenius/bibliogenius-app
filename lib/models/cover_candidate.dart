/// A cover candidate from an external source.
class CoverCandidate {
  final String url;
  final String source; // "Inventaire", "OpenLibrary", "BNF", "Google Books"

  /// The edition's language code when the source states it.
  final String? language;

  /// True when the candidate came from the book's own ISBN, so it really is
  /// this edition's cover. False means another edition of the same work: a
  /// perfectly good cover for most uses, and one the reader must be told about
  /// rather than left to discover on the shelf.
  final bool sameEdition;

  const CoverCandidate({
    required this.url,
    required this.source,
    this.language,
    this.sameEdition = false,
  });

  CoverCandidate asSameEdition() => CoverCandidate(
    url: url,
    source: source,
    language: language,
    sameEdition: true,
  );
}

/// What one source answered during a cover search.
///
/// [state] mirrors the Rust vocabulary: `found`, `empty`, `skipped`,
/// `unavailable`. [detail] carries the reason behind `unavailable` (an HTTP
/// status, a transport error, or `quota`).
class CoverSourceStatus {
  static const String quotaDetail = 'quota';

  final String source;
  final String state;
  final String? detail;

  const CoverSourceStatus({
    required this.source,
    required this.state,
    this.detail,
  });

  bool get isUnavailable => state == 'unavailable';
  bool get answered => state == 'found' || state == 'empty';
  bool get isQuota => detail == quotaDetail;
}

/// Why a cover search ended the way it did.
///
/// A search that found nothing because every source was down used to reach the
/// user as "no cover found", the same words as a search where every source
/// answered and none had a cover. The first is a reason to try again, the second
/// is a reason to stop, and the reader could not tell them apart.
enum CoverSearchVerdict {
  /// There are candidates to show.
  found,

  /// Every source that ran answered, and none has a cover for this book.
  none,

  /// At least one source did not answer, so "no cover" would be a guess.
  incomplete,

  /// No source ran at all: they are all turned off, or the platform has none.
  noSource,
}

/// Cover candidates plus what each source answered.
class CoverSearchResult {
  final List<CoverCandidate> candidates;
  final List<CoverSourceStatus> sources;

  const CoverSearchResult({required this.candidates, required this.sources});

  const CoverSearchResult.empty() : candidates = const [], sources = const [];

  /// The same result with every candidate marked as this book's own edition.
  /// Applied to the ISBN pass, whose candidates are covers of the very ISBN
  /// asked for; the title pass returns sibling editions instead.
  CoverSearchResult asSameEdition() => CoverSearchResult(
    candidates: candidates.map((c) => c.asSameEdition()).toList(),
    sources: sources,
  );

  List<CoverSourceStatus> get unavailableSources =>
      sources.where((s) => s.isUnavailable).toList();

  /// True when not one queried source managed to answer.
  ///
  /// Four sources failing at once is almost never four outages: it is the
  /// device that is offline, or DNS that is down. Naming them one by one buries
  /// the only thing the reader can act on.
  bool get nothingReachable =>
      sources.any((s) => s.isUnavailable) && !sources.any((s) => s.answered);

  CoverSearchVerdict get verdict {
    if (candidates.isNotEmpty) return CoverSearchVerdict.found;
    if (sources.any((s) => s.isUnavailable)) {
      return CoverSearchVerdict.incomplete;
    }
    if (sources.any((s) => s.answered)) return CoverSearchVerdict.none;
    return CoverSearchVerdict.noSource;
  }

  /// Merge a second pass (the title fallback) into this one, keeping every
  /// candidate the first pass did not already carry, and folding each source's
  /// two answers into one.
  ///
  /// A source asked twice keeps its worst answer, `unavailable` winning over
  /// everything: one silent pass means we do not know what that source holds,
  /// which is exactly what the reader must not be told is an absence.
  CoverSearchResult mergedWith(CoverSearchResult other) {
    // Built eagerly: a lazy `where` whose predicate also fills `seen` would
    // silently yield nothing on a second iteration.
    final seen = candidates.map((c) => c.url).toSet();
    final merged = [...candidates];
    for (final candidate in other.candidates) {
      if (seen.add(candidate.url)) merged.add(candidate);
    }

    final folded = <String, CoverSourceStatus>{};
    for (final status in [...sources, ...other.sources]) {
      final kept = folded[status.source];
      if (kept == null || _severity(status.state) > _severity(kept.state)) {
        folded[status.source] = status;
      }
    }
    return CoverSearchResult(
      candidates: merged,
      sources: folded.values.toList(),
    );
  }

  /// Ranks the four states so a fold keeps the answer that matters most.
  static int _severity(String state) => switch (state) {
    'unavailable' => 3,
    'found' => 2,
    'empty' => 1,
    _ => 0,
  };
}
