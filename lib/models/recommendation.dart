import 'book.dart';

/// Why a book was recommended. [type] is the stable wire key coming from
/// the Rust engine ("same_author", "shared_subject", ...), [value] the
/// display payload ("Albert Camus"). The UI translates the pair through
/// `reason_<type>` i18n keys.
class RecommendationReason {
  final String type;
  final String value;

  const RecommendationReason({required this.type, required this.value});
}

/// One recommendation from the local engine: a book, its score, and the
/// human-readable reasons (strongest first). Explainability is the trust
/// contract of the feature: a card always shows at least the first reason.
class Recommendation {
  final Book book;
  final double score;
  final List<RecommendationReason> reasons;

  const Recommendation({
    required this.book,
    required this.score,
    required this.reasons,
  });
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
