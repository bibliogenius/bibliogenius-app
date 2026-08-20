import 'package:flutter/foundation.dart';

import '../data/repositories/recommendation_repository.dart';
import '../models/recommendation.dart';
import 'book_refresh_notifier.dart';

/// Caches the dashboard "Suggestions for you" payload (Rule F4: caching is
/// Flutter's job, the Rust engine is stateless).
///
/// Strategy: stale-while-revalidate. The dashboard shows the cached list
/// instantly and a refresh runs in the background on every dashboard load.
/// Catalogue mutations (add/edit/delete/import) invalidate the cache
/// through [BookRefreshNotifier], which the mutation sites already ping.
class RecommendationProvider extends ChangeNotifier {
  final RecommendationRepository _repository;
  final BookRefreshNotifier _bookRefreshNotifier;

  PersonalRecommendations? _personal;
  bool _stale = true;
  bool _loading = false;

  RecommendationProvider(this._repository, this._bookRefreshNotifier) {
    _bookRefreshNotifier.addListener(_markStale);
  }

  /// Last fetched dashboard payload, possibly stale. Null until the first
  /// successful fetch (or when the FFI backend is unavailable).
  PersonalRecommendations? get personal => _personal;

  void _markStale() {
    _stale = true;
  }

  /// Fetch personal suggestions if the cache is stale (or [force]d).
  /// Keeps serving the previous list while the refresh runs.
  Future<void> loadPersonal({bool force = false}) async {
    if (_loading || (!_stale && !force && _personal != null)) return;
    _loading = true;
    try {
      final fresh = await _repository.getPersonalRecommendations();
      if (fresh != null) {
        _personal = fresh;
        _stale = false;
        notifyListeners();
      }
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _bookRefreshNotifier.removeListener(_markStale);
    super.dispose();
  }
}
