import '../../models/recommendation.dart';
import '../../services/ffi_service.dart';
import '../repositories/recommendation_repository.dart';

/// FFI-only implementation (Rule F3: new features use FFI direct). On web,
/// where FFI is unavailable, both calls degrade to "nothing to show" and
/// the recommendation sections stay hidden.
class RecommendationRepositoryImpl implements RecommendationRepository {
  final FfiService _ffiService;

  RecommendationRepositoryImpl(this._ffiService);

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) {
    return _ffiService.getBookRecommendations(bookId, limit: limit);
  }

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({int? limit}) {
    return _ffiService.getPersonalRecommendations(limit: limit);
  }
}
