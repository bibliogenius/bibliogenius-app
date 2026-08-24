import '../models/discovery.dart';
import '../utils/curated_tag_genre_aliases.dart';
import 'curated_lists_service.dart';
import 'discovery_service.dart';

/// The editorial affinity tier (ADR-066): which curated lists overlap the
/// reader's library enough to be worth surfacing, and by how much.
///
/// This is the most private external tier of all. The corpus is bundled, so
/// nothing transits: no request, not even an anonymous one. Both the
/// computation and the data live on the device.
///
/// Everything here is pure over a snapshot (the corpus, the identity index,
/// the reader's languages). Loading and memoisation belong to
/// `RecommendationProvider`; caps and rendering to the surfaces.
class CuratedAffinityService {
  const CuratedAffinityService();

  /// Owned books in common below which an overlap is a coincidence.
  static const int minOwnedInCommon = 3;

  /// The same floor on a list short enough that two is not chance.
  ///
  /// Three exists because two books in common with a large library is what
  /// chance produces on a ten-entry list. On a four-entry selection it is
  /// half the list, which is the opposite of a coincidence. Measured on the
  /// reference library (2026-08-24, corpus fully reviewed): of the thirteen
  /// lists the gate refused, exactly one was shaped like a real affinity,
  /// `programming-rust` at 2 owned of 4, and the pair-on-a-long-list cases
  /// it kept out (2 of 10) are the ones the floor was written for.
  ///
  /// The exception lowers the pair to two, NEVER to one: one book in common
  /// says nothing at any length.
  static const int minOwnedInCommonStrong = 2;

  /// Ratio at or above which [minOwnedInCommonStrong] replaces
  /// [minOwnedInCommon]. Well above [minOverlapRatio] on purpose: this one
  /// RELAXES a guard, so it has to be hard to reach.
  static const double strongOverlapRatio = 0.40;

  /// Share of the list the reader must already own.
  ///
  /// This is THE mega-list guard, and it is the one that does the real work.
  /// A canon of a thousand titles overlaps every library on earth, so a raw
  /// count would suggest it to everyone. Measured on the reference library
  /// (2026-08-23): a 72-volume series with 3 owned volumes scores 0.042 and
  /// a 22-volume one scores 0.136, both correctly rejected, while a 10-book
  /// selection with 3 owned scores 0.30 and passes.
  static const double minOverlapRatio = 0.20;

  /// Books left to discover below which the list has nothing to offer. A
  /// reader owning 7 of 8 does not need to be sold the eighth as a
  /// selection; this is the membrane extinguishing a list as it fills up.
  static const int minRemaining = 2;

  /// A liked book counts double against a merely owned one (ADR-066): the
  /// research doc's "liked books weigh more" rule, applied in the ranking.
  static const double likedWeight = 2.0;
  static const double ownedWeight = 1.0;

  /// Ranking nudge per genre key shared between the list's tags and the
  /// reader's own themes, and the ceiling on it.
  ///
  /// Deliberately tiny, and deliberately applied AFTER eligibility: a list
  /// can never be suggested because of its tags. Books-in-common stays
  /// load-bearing, because local subjects are sparse (4 distinct shelf
  /// labels on the reference library) and a thematic-only match would be
  /// the least explainable card of the whole feature.
  static const double tagBonusPerMatch = 0.05;
  static const double tagBonusMax = 0.15;

  /// Covers taken from the reader's own copies to build a card's mosaic.
  static const int mosaicCovers = 4;

  /// Rank [lists] against the library, best affinity first.
  ///
  /// [readerLanguages] gates eligibility: a list whose `content_languages`
  /// does not intersect them is not a candidate at all. [ownedCoverUrls]
  /// maps a cleaned ISBN or a normalized "title|author" key to the cover of
  /// the reader's OWN copy, so a card shows the books they already have.
  /// [readerGenreKeys] are the genre keys of the reader's own themes.
  List<CuratedAffinity> rank({
    required List<CuratedList> lists,
    required DiscoveryLookupInputs inputs,
    required List<String> readerLanguages,
    Map<String, String> ownedCoverUrls = const {},
    Set<String> readerGenreKeys = const {},
  }) {
    // Below the ADR-059 profile floor the FFI returns the empty default,
    // identity index included. Running the membrane against nothing would
    // count every book as unowned and hand the reader a card claiming an
    // overlap that does not exist.
    if (inputs.hasNoIdentity) return const [];

    final languages = readerLanguages.toSet();
    final library = DiscoveryIdentityIndex.of(
      inputs.libraryIsbns,
      inputs.libraryTitleAuthorKeys,
    );
    final liked = DiscoveryIdentityIndex.of(
      inputs.likedIsbns,
      inputs.likedTitleAuthorKeys,
    );

    final ranked = <CuratedAffinity>[];
    for (final list in lists) {
      // The editorial gate comes first, before any measurement: it is the
      // one filter that does not depend on the reader at all.
      //
      // This tier changes a list's exposure from PULL to PUSH, so the
      // quality bar rises with it. The affinity thresholds below are a
      // personalized filter; this is the editorial dial on top of them, and
      // it is the only one a curator can turn list by list.
      if (!list.isReviewed) continue;
      if (!isEligibleLanguage(list, languages)) continue;
      final affinity = _measure(
        list,
        library,
        liked,
        ownedCoverUrls,
        readerGenreKeys,
      );
      if (affinity != null) ranked.add(affinity);
    }

    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Stable and explainable: more books in common, then alphabetical, so
      // two equal scores never reorder between two sweeps.
      final byOwned = b.ownedCount.compareTo(a.ownedCount);
      if (byOwned != 0) return byOwned;
      return a.list.id.compareTo(b.list.id);
    });
    return ranked;
  }

  /// The language gate, reusing the import screen's own partitioning rule.
  ///
  /// A list with no declared `content_languages` is NOT a candidate. The
  /// import screen routes those to its "other languages" section so they
  /// stay discoverable, which is right for a catalogue the reader chose to
  /// open; an unsolicited suggestion in a language they may not read is the
  /// opposite trade, and absent beats wrong.
  static bool isEligibleLanguage(CuratedList list, Set<String> languages) {
    return partitionCuratedListsByLanguage([
      list,
    ], languages).inYourLanguages.isNotEmpty;
  }

  /// Indexes into `list.books` the reader already owns.
  ///
  /// Exposed so the pre-import preview can mark them: a reader about to add
  /// ten books wants to know which of them are new, and the count in the
  /// dialog cannot say. It runs the SAME membrane the overlap count runs, so
  /// a card claiming three books in common and a preview ticking two is not
  /// a state this code can reach.
  ///
  /// Returns nothing below the ADR-059 profile floor, where the FFI hands
  /// back the empty identity index: an empty result there means "we do not
  /// know", and marking nothing is the only honest rendering of that.
  Set<int> ownedEntryIndexes({
    required CuratedList list,
    required DiscoveryLookupInputs inputs,
  }) {
    if (inputs.hasNoIdentity) return const {};

    final library = DiscoveryIdentityIndex.of(
      inputs.libraryIsbns,
      inputs.libraryTitleAuthorKeys,
    );
    final liked = DiscoveryIdentityIndex.of(
      inputs.likedIsbns,
      inputs.likedTitleAuthorKeys,
    );

    final owned = <int>{};
    for (var i = 0; i < list.books.length; i++) {
      if (_matchOne(list.books[i], library, liked, const {}).owned) {
        owned.add(i);
      }
    }
    return owned;
  }

  CuratedAffinity? _measure(
    CuratedList list,
    DiscoveryIdentityIndex library,
    DiscoveryIdentityIndex liked,
    Map<String, String> ownedCoverUrls,
    Set<String> readerGenreKeys,
  ) {
    final total = list.books.length;
    if (total == 0) return null;

    var ownedCount = 0;
    var likedCount = 0;
    final covers = <String>[];

    for (final book in list.books) {
      final match = _matchOne(book, library, liked, ownedCoverUrls);
      if (!match.owned) continue;
      ownedCount++;
      if (match.liked) likedCount++;
      final cover = match.coverUrl;
      if (cover != null &&
          covers.length < mosaicCovers &&
          !covers.contains(cover)) {
        covers.add(cover);
      }
    }

    final remaining = total - ownedCount;
    final ratio = ownedCount / total;
    final ownedFloor = ratio >= strongOverlapRatio
        ? minOwnedInCommonStrong
        : minOwnedInCommon;
    if (ownedCount < ownedFloor) return null;
    if (ratio < minOverlapRatio) return null;
    if (remaining < minRemaining) return null;

    // Eligibility is settled. Only now may the tags speak, and only to
    // reorder: this ordering is the invariant, not a style choice.
    final sharedGenres = genreKeysForTags(
      list.tags,
    ).intersection(readerGenreKeys);
    final bonus = (sharedGenres.length * tagBonusPerMatch).clamp(
      0.0,
      tagBonusMax,
    );
    final weighted =
        (likedCount * likedWeight + (ownedCount - likedCount) * ownedWeight) /
        total;

    return CuratedAffinity(
      list: list,
      ownedCount: ownedCount,
      likedCount: likedCount,
      totalCount: total,
      score: weighted + bonus,
      ownedCoverUrls: covers,
      sharedGenreKeys: sharedGenres,
    );
  }

  /// One entry against the membrane. ISBN first, then normalized
  /// title+author over every ISBN the entry can be recognised by.
  ///
  /// Cross-language matching is deliberate and must not be "fixed": owning
  /// the French translation of a book on an English list counts here, which
  /// is both what makes the overlap honest and what stops the tier offering
  /// a reader a book already on their shelf.
  _EntryMatch _matchOne(
    CuratedBook book,
    DiscoveryIdentityIndex library,
    DiscoveryIdentityIndex liked,
    Map<String, String> ownedCoverUrls,
  ) {
    for (final raw in book.allIsbns) {
      final cleaned = DiscoveryService.cleanIsbn(raw);
      if (cleaned.isEmpty) continue;
      if (library.hasIsbn(cleaned)) {
        return _EntryMatch(
          owned: true,
          liked: liked.hasIsbn(cleaned),
          coverUrl: ownedCoverUrls[cleaned],
        );
      }
    }

    final title = book.identityTitle;
    if (title == null) return const _EntryMatch(owned: false, liked: false);
    final normalizedTitle = DiscoveryService.normalizeIdentityText(title);
    if (normalizedTitle.isEmpty) {
      return const _EntryMatch(owned: false, liked: false);
    }
    for (final author in book.identityAuthors) {
      final normalizedAuthor = DiscoveryService.normalizeIdentityText(author);
      if (normalizedAuthor.isEmpty) continue;
      if (library.hasKey(normalizedTitle, normalizedAuthor)) {
        return _EntryMatch(
          owned: true,
          liked: liked.hasKey(normalizedTitle, normalizedAuthor),
          coverUrl: ownedCoverUrls['$normalizedTitle|$normalizedAuthor'],
        );
      }
    }
    return const _EntryMatch(owned: false, liked: false);
  }
}

class _EntryMatch {
  const _EntryMatch({required this.owned, required this.liked, this.coverUrl});

  final bool owned;
  final bool liked;
  final String? coverUrl;
}

/// One curated list measured against the library: enough to rank it, to
/// explain it on a card, and to build its mosaic.
class CuratedAffinity {
  const CuratedAffinity({
    required this.list,
    required this.ownedCount,
    required this.likedCount,
    required this.totalCount,
    required this.score,
    this.ownedCoverUrls = const [],
    this.sharedGenreKeys = const {},
  });

  final CuratedList list;

  /// Books of the list the reader already has, in any edition or language.
  final int ownedCount;

  /// How many of those they liked. Zero is a normal, common value: the
  /// liked signal is structurally sparse (14 liked books out of 492 on the
  /// reference library), which is why it weighs rather than gates.
  final int likedCount;

  final int totalCount;

  /// Weighted overlap ratio plus the tag bonus. Ranking only, never shown.
  final double score;

  /// Covers of the reader's OWN copies of the books in common, capped at
  /// [CuratedAffinityService.mosaicCovers]. Local URLs only: a card saying
  /// "you already have a foot in this selection" must show their books.
  final List<String> ownedCoverUrls;

  final Set<String> sharedGenreKeys;

  /// Books of the list still to discover. Always at least
  /// [CuratedAffinityService.minRemaining] on an eligible list.
  int get remainingCount => totalCount - ownedCount;

  /// Dismissal key, in the namespace the external suggestion store uses for
  /// this tier (ADR-066). Targets the SUGGESTION: the list itself stays in
  /// the import catalogue, which never consults the store.
  String get dismissalKey => 'list:${list.id}';
}
