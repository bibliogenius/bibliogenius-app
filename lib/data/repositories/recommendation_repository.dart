import '../../models/discovery.dart';
import '../../models/recommendation.dart';

/// Read-only access to the local reading recommendations engine (ADR-059)
/// and to the discovery lookup inputs it derives (ADR-060). Everything is
/// computed on-device by the Rust core; the hub call itself lives in
/// DiscoveryService, not here.
abstract class RecommendationRepository {
  /// Books from the library similar to [bookId] ("You might also like").
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  });

  /// Personal suggestions for the dashboard, with the taste-profile
  /// summary. Null when the FFI backend is unavailable (web).
  Future<PersonalRecommendations?> getPersonalRecommendations({int? limit});

  /// Inputs of the external discovery lookups (ADR-060): what to ask the
  /// hub resolver plus the identity index filtering its answers. Null when
  /// the FFI backend is unavailable (web).
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs();
}
