import 'package:flutter/foundation.dart';

import '../data/repositories/recommendation_repository.dart';
import '../models/recommendation.dart';
import '../services/discovery_service.dart';
import '../services/external_suggestion_dismissal_service.dart';
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
///
/// External discovery (ADR-060, series lane): the provider additionally
/// blends "complete the series" cards resolved by the hub. The candidates
/// come from [DiscoveryService] (cache-first, throttled sweep behind),
/// their dismissal uses the second, namespaced store
/// ([ExternalSuggestionDismissalService]), and the blend rules live here:
/// one card per series (lowest missing ordinal), locals never displaced by
/// externals, caps per surface.
class RecommendationProvider extends ChangeNotifier {
  final RecommendationRepository _repository;
  final BookRefreshNotifier _bookRefreshNotifier;
  final DiscoveryService _discovery;

  PersonalRecommendations? _personal;
  bool _stale = true;
  bool _loading = false;

  Set<String> _dismissedBookIds = {};

  /// Per-series external candidates (missing volumes, lowest ordinal
  /// first); the visible pick is the first non-dismissed of each series.
  List<List<Recommendation>> _externalCandidates = const [];
  Set<String> _dismissedExternalKeys = {};
  bool _externalStale = true;
  bool _externalLoading = false;

  /// Dashboard cap on external cards (ADR-060 section 4.4): discovery
  /// never drowns "read what is already at home".
  static const int dashboardMaxExternal = 2;

  /// See-all cap on external cards, appended after the locals.
  static const int seeAllMaxExternal = 10;

  RecommendationProvider(
    this._repository,
    this._bookRefreshNotifier, {
    DiscoveryService? discoveryService,
  }) : _discovery = discoveryService ?? DiscoveryService() {
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

  /// Visible external cards: one per series, the lowest-ordinal missing
  /// volume that is not dismissed. Order follows the series lookups.
  List<Recommendation> get visibleExternal {
    final picks = <Recommendation>[];
    for (final cards in _externalCandidates) {
      for (final card in cards) {
        if (!isExternalDismissed(card.externalKey)) {
          picks.add(card);
          break;
        }
      }
    }
    return picks;
  }

  /// True when the user marked [bookId] as "Not interested".
  bool isDismissed(String? bookId) =>
      bookId != null && _dismissedBookIds.contains(bookId);

  bool isExternalDismissed(String? key) =>
      key != null && _dismissedExternalKeys.contains(key);

  /// The dismissed set itself, for `context.select` subscribers on the
  /// similar-books carousel. Every mutation REPLACES the instance, so
  /// identity comparison rebuilds them exactly when a dismissal changes
  /// and on nothing else. Do not mutate.
  Set<String> get dismissedBookIds => _dismissedBookIds;

  /// Same replace-the-instance contract as [dismissedBookIds], for the
  /// external store.
  Set<String> get dismissedExternalKeys => _dismissedExternalKeys;

  Future<void> _loadDismissed() async {
    _dismissedBookIds = await RecommendationDismissalService.loadDismissed();
    _dismissedExternalKeys =
        (await ExternalSuggestionDismissalService.loadDismissed()).toSet();
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

  Future<void> dismissExternal(String key) async {
    _dismissedExternalKeys = {..._dismissedExternalKeys, key};
    notifyListeners();
    await ExternalSuggestionDismissalService.dismiss(key);
  }

  Future<void> restoreDismissedExternal(String key) async {
    _dismissedExternalKeys = {..._dismissedExternalKeys}..remove(key);
    notifyListeners();
    await ExternalSuggestionDismissalService.restore(key);
  }

  /// Drop one external card after its book was imported: the identity
  /// index only refreshes on the next lookup pass, so the card would
  /// otherwise linger this session. The next missing ordinal of the same
  /// series surfaces naturally.
  void hideExternalAfterImport(String externalKey) {
    _externalCandidates = _externalCandidates
        .map(
          (cards) => cards.where((c) => c.externalKey != externalKey).toList(),
        )
        .where((cards) => cards.isNotEmpty)
        .toList();
    notifyListeners();
  }

  void _markStale() {
    _stale = true;
    _externalStale = true;
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

  /// Load and refresh the external "complete the series" cards (ADR-060).
  ///
  /// Renders from the persistent cache first, then sweeps stale lookups
  /// against the hub behind (never blocking the local suggestions, which
  /// must already be loaded). The ADR-059 thresholds gate the whole
  /// feature: below 5 profile books the FFI returns no lookups, and below
  /// 2 visible local suggestions no external lookup runs at all.
  Future<void> loadExternal({
    required List<String> langs,
    bool force = false,
  }) async {
    if (_externalLoading) return;
    if (!_externalStale && !force) return;
    _externalLoading = true;
    try {
      if (_personal == null || visiblePersonal.length < 2) {
        if (_externalCandidates.isNotEmpty) {
          _externalCandidates = const [];
          notifyListeners();
        }
        return;
      }
      final inputs = await _repository.getDiscoveryLookupInputs();
      if (inputs == null || inputs.series.isEmpty) {
        _externalStale = false;
        if (_externalCandidates.isNotEmpty) {
          _externalCandidates = const [];
          notifyListeners();
        }
        return;
      }

      _externalCandidates = await _discovery.buildFromCache(inputs, langs);
      _externalStale = false;
      notifyListeners();

      final changed = await _discovery.sweep(inputs, langs);
      if (changed) {
        _externalCandidates = await _discovery.buildFromCache(inputs, langs);
        notifyListeners();
      }
    } finally {
      _externalLoading = false;
    }
  }

  @override
  void dispose() {
    _bookRefreshNotifier.removeListener(_markStale);
    super.dispose();
  }
}
