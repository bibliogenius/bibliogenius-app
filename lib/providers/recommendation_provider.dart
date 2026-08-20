import 'package:flutter/foundation.dart';

import '../data/repositories/recommendation_repository.dart';
import '../models/recommendation.dart';
import '../services/recommendation_dismissal_service.dart';
import 'book_refresh_notifier.dart';

/// Caches the dashboard "Suggestions for you" payload (Rule F4: caching is
/// Flutter's job, the Rust engine is stateless).
///
/// Strategy: stale-while-revalidate. The dashboard shows the cached list
/// instantly and a refresh runs in the background on every dashboard load.
/// Catalogue mutations (add/edit/delete/import) invalidate the cache
/// through [BookRefreshNotifier], which the mutation sites already ping.
///
/// Also owns the in-memory "Not interested" dismissal set (ADR-059
/// follow-up). Dismissals are keyed by book uuid, filtered Flutter-side
/// (the Rust engine does not change), apply to every recommendation
/// surface, and persist device-locally through
/// [RecommendationDismissalService].
class RecommendationProvider extends ChangeNotifier {
  final RecommendationRepository _repository;
  final BookRefreshNotifier _bookRefreshNotifier;

  PersonalRecommendations? _personal;
  bool _stale = true;
  bool _loading = false;

  Set<String> _dismissedBookIds = {};

  RecommendationProvider(this._repository, this._bookRefreshNotifier) {
    _bookRefreshNotifier.addListener(_markStale);
    _loadDismissed();
  }

  /// Last fetched dashboard payload, possibly stale. Null until the first
  /// successful fetch (or when the FFI backend is unavailable).
  PersonalRecommendations? get personal => _personal;

  /// Personal suggestions ready to display: explained (the engine should
  /// never emit reasonless cards, dropped defensively) and not dismissed.
  /// Every visibility threshold is evaluated on THIS list, so the
  /// "hidden below 2 suggestions" floor counts dismissals out.
  List<Recommendation> get visiblePersonal {
    final all = _personal?.recommendations;
    if (all == null) return const [];
    return all
        .where((r) => r.reasons.isNotEmpty && !isDismissed(r.book.id))
        .toList();
  }

  /// True when the user marked [bookId] as "Not interested".
  bool isDismissed(String? bookId) =>
      bookId != null && _dismissedBookIds.contains(bookId);

  /// The dismissed set itself, for `context.select` subscribers that only
  /// care about dismissals (the similar-books carousel). Every mutation
  /// REPLACES the instance, so identity comparison rebuilds them exactly
  /// when a dismissal changes and on nothing else. Do not mutate.
  Set<String> get dismissedBookIds => _dismissedBookIds;

  Future<void> _loadDismissed() async {
    _dismissedBookIds = await RecommendationDismissalService.loadDismissed();
    notifyListeners();
  }

  /// Mark [bookId] as "Not interested": hides it on every recommendation
  /// surface, immediately and on later launches.
  Future<void> dismiss(String bookId) async {
    _dismissedBookIds = {..._dismissedBookIds, bookId};
    notifyListeners();
    await RecommendationDismissalService.dismiss(bookId);
  }

  /// Undo a [dismiss] (the SnackBar "Undo" action): the suggestion
  /// reappears where it was.
  Future<void> restoreDismissed(String bookId) async {
    _dismissedBookIds = {..._dismissedBookIds}..remove(bookId);
    notifyListeners();
    await RecommendationDismissalService.restore(bookId);
  }

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
