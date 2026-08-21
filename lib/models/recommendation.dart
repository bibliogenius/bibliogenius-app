import 'book.dart';

/// Recommendation sources, as Dart-only card metadata (ADR-060: the Rust
/// wire contract stays untouched; the source distinction is a UI concern).
abstract final class RecommendationSource {
  /// Scored from the local library by the on-device engine (ADR-059).
  static const String library = 'library';

  /// Resolved by the hub discovery resolver from an anonymous lookup
  /// (ADR-060): the book does not exist locally.
  static const String external = 'external';
}

/// Why a book was recommended. [type] is the stable wire key coming from
/// the Rust engine ("same_author", "shared_subject", ...), [value] the
/// display payload ("Albert Camus"). The UI translates the pair through
/// `reason_<type>` i18n keys.
///
/// [params] exists only on client-built reasons (external discovery cards)
/// whose i18n line needs more than one placeholder; wire reasons never set
/// it and keep the `{value}` convention.
class RecommendationReason {
  final String type;
  final String value;
  final Map<String, String>? params;

  const RecommendationReason({
    required this.type,
    required this.value,
    this.params,
  });
}

/// One recommendation: a book, its score, and the human-readable reasons
/// (strongest first). Explainability is the trust contract of the feature:
/// a card always shows at least the first reason.
///
/// [source] distinguishes local-library cards from external discovery
/// cards (ADR-060); [externalKey] is the namespaced dismissal key of an
/// external card (`isbn:<isbn13>` or `series:<source_id>:<ordinal>`),
/// null on library cards, whose dismissal keys on the book uuid.
///
/// [seriesCollectionId] is set on series-lane cards only (ADR-062 section
/// 11): the LOCAL series collection whose missing volume this card offers,
/// so adding the book files it back into that collection from any surface.
/// It has to ride on the card rather than be looked up later: a cycle and
/// an omnibus resolving to the same hub series (ADR-052) produce two cards
/// sharing one [externalKey], and only a value set inside the per-lookup
/// loop tells them apart. Null on library and author-lane cards, which
/// belong to no series collection and write nothing.
class Recommendation {
  final Book book;
  final double score;
  final List<RecommendationReason> reasons;
  final String source;
  final String? externalKey;
  final String? seriesCollectionId;

  const Recommendation({
    required this.book,
    required this.score,
    required this.reasons,
    this.source = RecommendationSource.library,
    this.externalKey,
    this.seriesCollectionId,
  });

  bool get isExternal => source == RecommendationSource.external;
}

/// Dashboard payload: personal suggestions plus the taste-profile summary
/// that produced them. [scoredBooksCount] gates the section (hidden below
/// the Rust-side threshold of 5 profile books).
class PersonalRecommendations {
  final List<Recommendation> recommendations;
  final List<String> topSubjects;
  final List<String> favoriteAuthors;
  final int scoredBooksCount;

  const PersonalRecommendations({
    required this.recommendations,
    required this.topSubjects,
    required this.favoriteAuthors,
    required this.scoredBooksCount,
  });
}
