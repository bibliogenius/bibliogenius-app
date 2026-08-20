import '../../models/recommendation.dart';

/// Read-only access to the local reading recommendations engine (ADR-059).
/// Everything is computed on-device by the Rust core; there is no network
/// variant of this repository.
abstract class RecommendationRepository {
  /// Books from the library similar to [bookId] ("You might also like").
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  });

  /// Personal suggestions for the dashboard, with the taste-profile
  /// summary. Null when the FFI backend is unavailable (web).
  Future<PersonalRecommendations?> getPersonalRecommendations({int? limit});
}
