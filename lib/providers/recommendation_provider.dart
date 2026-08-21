import 'package:flutter/foundation.dart';

import '../data/repositories/recommendation_repository.dart';
import '../models/discovery.dart';
import '../utils/author_identity.dart';
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
/// External discovery (ADR-060): the provider additionally blends
/// "complete the series" and "complete the author" cards resolved by the
/// hub. The candidates come from [DiscoveryService] (cache-first,
/// throttled sweep behind), their dismissal uses the second, namespaced
/// store ([ExternalSuggestionDismissalService]), and the blend rules live
/// here: one card per series (lowest missing ordinal), at most two works
/// per author, series ahead of authors, locals never displaced by
/// externals, caps per surface.
///
/// Contextual surfaces (ADR-061) read the same caches through
/// [seriesCardsForCollections] (cache-only, for a book page) and
/// [authorPageDiscovery] (resolves on open, for an author page). Both go
/// through [ensureLookupInputs] so a page opening never triggers a second
/// library pass.
class RecommendationProvider extends ChangeNotifier {
  final RecommendationRepository _repository;
  final BookRefreshNotifier _bookRefreshNotifier;
  final DiscoveryService _discovery;

  PersonalRecommendations? _personal;
  bool _stale = true;
  bool _loading = false;

  Set<String> _dismissedBookIds = {};

  /// Per-series external candidates (missing volumes, lowest ordinal
  /// first), keyed by collection id in lookup order; the visible pick is the
  /// first non-dismissed of each series.
  Map<String, List<Recommendation>> _externalCandidates = const {};

  /// Per-author external candidates (unowned works, most editions first),
  /// keyed by lookup name in lookup order; the visible picks are the first
  /// non-dismissed of each author.
  Map<String, List<Recommendation>> _externalAuthorCandidates = const {};
  Set<String> _dismissedExternalKeys = {};
  bool _externalStale = true;
  bool _externalLoading = false;

  /// Last discovery lookup inputs (lookups plus the library identity index).
  /// Cached across surfaces so opening a book or an author page never costs
  /// a full library pass: only a catalogue mutation invalidates them
  /// (ADR-061 section 3).
  DiscoveryLookupInputs? _lookupInputs;
  bool _inputsStale = true;
  Future<DiscoveryLookupInputs?>? _inputsInFlight;

  /// Whether the once-per-session startup warm-up already ran
  /// ([warmUpAtStartup]). Never reset by a catalogue mutation: staleness is
  /// what re-runs the work, this only stops the startup kick repeating.
  bool _startupWarmUpDone = false;

  /// Memoised [authorVocabulary], derived from [_lookupInputs] and dying
  /// with them.
  Set<String>? _authorVocabulary;

  /// Dashboard cap on external cards (ADR-060 section 4.4): discovery
  /// never drowns "read what is already at home".
  static const int dashboardMaxExternal = 2;

  /// The ADR-059 visible-suggestions floor: below this many surviving
  /// suggestions, a digest surface renders nothing rather than a thin one.
  static const int minVisibleSuggestions = 2;

  /// Cards in the dashboard digest.
  static const int dashboardMaxDisplayed = 5;

  /// Cards in the library-screen slot (ADR-062 section 5).
  ///
  /// Deliberately LARGER than the dashboard digest, which is the opposite of
  /// what it shipped as. The digest cap of 5 exists to protect vertical
  /// space: on the dashboard each suggestion is a stacked row, so ten of
  /// them cost ten row heights. The slot is a horizontal strip, where an
  /// extra card costs nothing vertically and only rewards a scroll the
  /// reader has already started. Capping it at 3 imported a constraint from
  /// a context that does not apply here, and left the strip looking
  /// truncated next to a "see all" card.
  static const int slotMaxDisplayed = 8;

  /// External cap inside the slot. Scales with the larger digest, and stays
  /// a minority of it: ADR-060 section 4.4 caps discovery so it never drowns
  /// "read what is already at home". That rule bounds the EXTERNAL cards,
  /// not the total, which is why the two caps move independently.
  static const int slotMaxExternal = 2;

  /// See-all cap on external cards, appended after the locals.
  static const int seeAllMaxExternal = 10;

  /// Cap on works shown per favorite author (ADR-060 section 4.4).
  static const int authorMaxWorks = 2;

  /// Cap on discovered works listed on an author page (ADR-061 section 5).
  /// Higher than [authorMaxWorks] because the page is not a blend competing
  /// for scarce slots: the user asked about this author.
  static const int authorPageMaxWorks = 10;

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

  /// Visible external cards: one per series (the lowest-ordinal missing
  /// volume that is not dismissed), then up to two works per favorite
  /// author. Series completion outranks author completion inside the
  /// external tier (ADR-060 section 4.4): it is the more precise of the
  /// two, so it takes the scarce external slots first.
  List<Recommendation> get visibleExternal => [
    ..._pickPerLookup(_externalCandidates, 1),
    ..._pickPerLookup(_externalAuthorCandidates, authorMaxWorks),
  ];

  /// True while the first personal fetch of this screen is still in flight
  /// and nothing has ever landed. Surfaces need it to tell a cold cache
  /// apart from a genuinely empty list: an empty state shown while the
  /// engine is still answering is simply false.
  bool get isLoadingFirstPersonal => _loading && _personal == null;

  /// The ADR-059 profile floor, as the client can see it: the engine
  /// answered at all. Below 5 scored books the Rust side returns nothing,
  /// so a null payload IS the floor failing. Distinct from
  /// [hasVisibleSuggestions] on purpose (ADR-062 section 6): an entry point
  /// gated on this one never leads to an empty screen, yet does not blink
  /// in and out as the reader dismisses cards.
  bool get hasReachedProfileFloor => _personal != null;

  /// The ADR-059 visible-suggestions floor: at least [minVisibleSuggestions]
  /// suggestions survive dismissal filtering. A rendering rule, evaluated
  /// on [visiblePersonal] so dismissals count.
  bool get hasVisibleSuggestions =>
      visiblePersonal.length >= minVisibleSuggestions;

  /// One blend rule for every digest surface (ADR-062 section 5): the
  /// dashboard section and the library slot call THIS, so they cannot
  /// drift apart. Externals take at most [maxExternal] of the
  /// [maxDisplayed] slots and sit AFTER the locals, so the strongest local
  /// suggestions are never displaced by discovery (ADR-060 section 4.4).
  List<Recommendation> blendedDigest({
    required int maxDisplayed,
    required int maxExternal,
  }) {
    final externals = visibleExternal.take(maxExternal).toList();
    final locals = visiblePersonal
        .take(maxDisplayed - externals.length)
        .toList();
    return [...locals, ...externals];
  }

  /// Whether a [blendedDigest] with the same caps left anything out, which
  /// is what earns a "see all" link.
  bool digestIsTruncated({
    required int maxDisplayed,
    required int maxExternal,
  }) {
    final externals = visibleExternal.take(maxExternal).length;
    final locals = visiblePersonal.take(maxDisplayed - externals).length;
    return visiblePersonal.length > locals || visibleExternal.length > externals;
  }

  /// First [perLookup] non-dismissed cards of each lookup, in lookup
  /// order. A dismissal therefore promotes the next candidate of the same
  /// series or author rather than leaving a hole.
  List<Recommendation> _pickPerLookup(
    Map<String, List<Recommendation>> candidates,
    int perLookup,
  ) {
    final picks = <Recommendation>[];
    for (final cards in candidates.values) {
      var taken = 0;
      for (final card in cards) {
        if (taken >= perLookup) break;
        if (!isExternalDismissed(card.externalKey)) {
          picks.add(card);
          taken++;
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
    _externalCandidates = _withoutKey(_externalCandidates, externalKey);
    _externalAuthorCandidates = _withoutKey(
      _externalAuthorCandidates,
      externalKey,
    );
    notifyListeners();
  }

  static Map<String, List<Recommendation>> _withoutKey(
    Map<String, List<Recommendation>> candidates,
    String externalKey,
  ) {
    final kept = <String, List<Recommendation>>{};
    candidates.forEach((lookup, cards) {
      final remaining = cards
          .where((c) => c.externalKey != externalKey)
          .toList();
      if (remaining.isNotEmpty) kept[lookup] = remaining;
    });
    return kept;
  }

  void _markStale() {
    _stale = true;
    _externalStale = true;
    // A catalogue mutation changes the identity index and the lookups
    // themselves, so the contextual surfaces must not keep filtering
    // against a library that no longer exists.
    _inputsStale = true;
  }

  /// Discovery lookup inputs, fetched once and reused by every surface
  /// until a catalogue mutation invalidates them. Concurrent callers (a
  /// dashboard sweep and a page opening together) share one library pass.
  /// Null when the FFI backend is unavailable.
  Future<DiscoveryLookupInputs?> ensureLookupInputs() {
    if (_lookupInputs != null && !_inputsStale) {
      return Future<DiscoveryLookupInputs?>.value(_lookupInputs);
    }
    return _inputsInFlight ??= _fetchLookupInputs();
  }

  Future<DiscoveryLookupInputs?> _fetchLookupInputs() async {
    try {
      final fresh = await _repository.getDiscoveryLookupInputs();
      if (fresh != null) {
        _lookupInputs = fresh;
        _inputsStale = false;
        // Derived from the inputs, so it dies with them and is rebuilt once
        // rather than on every page open (ADR-061 section 4).
        _authorVocabulary = null;
      }
      return _lookupInputs;
    } finally {
      _inputsInFlight = null;
    }
  }

  /// The library's individual author names, as [AuthorIdentity] match keys.
  ///
  /// Both contextual surfaces need it (the book page to decide whether the
  /// comma in an author string separates two people, the author page to
  /// select its books), and deriving it walks every identity key of the
  /// library with a normalization and a word sort each. Computing that on
  /// every page open was measurable work on the UI isolate for a value that
  /// only changes when the catalogue does.
  Future<Set<String>> authorVocabulary() async {
    final memo = _authorVocabulary;
    if (memo != null && !_inputsStale) return memo;
    final inputs = await ensureLookupInputs();
    return _authorVocabulary ??= AuthorIdentity.vocabularyOf(
      inputs?.libraryTitleAuthorKeys ?? const {},
    );
  }

  /// Fetch personal suggestions if the cache is stale (or [force]d).
  /// Keeps serving the previous list while the refresh runs.
  Future<void> loadPersonal({bool force = false}) async {
    if (_loading || (!_stale && !force && _personal != null)) return;
    _loading = true;
    // Let a cold surface paint its loading state instead of its empty one.
    if (_personal == null) notifyListeners();
    try {
      final fresh = await _repository.getPersonalRecommendations();
      if (fresh != null) {
        _personal = fresh;
        _stale = false;
        notifyListeners();
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Load and refresh the external "complete the series" and "complete the
  /// author" cards (ADR-060).
  ///
  /// Renders from the persistent caches first, then sweeps stale lookups
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
        _clearExternal();
        return;
      }
      final inputs = await ensureLookupInputs();
      if (inputs == null || inputs.isEmpty) {
        _externalStale = false;
        _clearExternal();
        return;
      }

      _externalCandidates = await _discovery.buildFromCache(inputs, langs);
      _externalAuthorCandidates = await _discovery.buildAuthorsFromCache(
        inputs,
        langs,
      );
      _externalStale = false;
      notifyListeners();

      // Both lanes sweep on their own throttle; either one changing is
      // enough to rebuild, and neither blocks the other.
      final seriesChanged = await _discovery.sweep(inputs, langs);
      if (seriesChanged) {
        _externalCandidates = await _discovery.buildFromCache(inputs, langs);
        notifyListeners();
      }
      final authorsChanged = await _discovery.sweepAuthors(inputs, langs);
      if (authorsChanged) {
        _externalAuthorCandidates = await _discovery.buildAuthorsFromCache(
          inputs,
          langs,
        );
        notifyListeners();
      }
    } finally {
      _externalLoading = false;
    }
  }

  /// One-shot discovery warm-up for the app session (ADR-061 section 7,
  /// decision A5): load the local suggestions, then run the external sweep,
  /// without any dashboard widget having to build.
  ///
  /// The dashboard section used to be the ONLY igniter, and the app opens on
  /// the book list, so a reader who never visited it never swept and never
  /// saw a book-page series card. This decouples the two: the section keeps
  /// its stale-while-revalidate render path, it simply stops being the
  /// trigger of record.
  ///
  /// Every gate is unchanged and still evaluated here, not by the caller:
  /// the profile floor through the empty FFI inputs, the two-visible-local
  /// floor inside [loadExternal], and the 24h per-key throttle inside the
  /// service. Cheap to call: on a warm cache it does no network at all.
  Future<void> warmUpAtStartup({required List<String> langs}) async {
    if (_startupWarmUpDone) return;
    await loadPersonal();
    // The backend can be unavailable (web, or a failed init). Leave the flag
    // down so a later trigger still gets its chance rather than the session
    // silently losing its only kick.
    if (_personal == null) return;
    _startupWarmUpDone = true;
    await loadExternal(langs: langs);
  }

  void _clearExternal() {
    if (_externalCandidates.isEmpty && _externalAuthorCandidates.isEmpty) {
      return;
    }
    _externalCandidates = const {};
    _externalAuthorCandidates = const {};
    notifyListeners();
  }

  // ── Contextual surfaces (ADR-061) ───────────────────────────────────

  /// Missing-volume candidates for a book that belongs to [collectionIds],
  /// CACHE-ONLY: this never fires a lookup (ADR-061 section 2). Owned series
  /// are already swept by the dashboard, and a second trigger surface would
  /// buy outbound pressure for a redundant answer.
  ///
  /// Returns the candidates of the FIRST of those collections that has any,
  /// in lookup order: a book sitting in both a cycle and an omnibus
  /// collection still shows one card. The caller picks the first
  /// non-dismissed of the list, so a dismissal reveals the next ordinal of
  /// the same series rather than jumping to another one.
  ///
  /// Deliberately independent of [loadExternal]: the app opens on the book
  /// list, not the dashboard, so the in-memory blend is usually empty when a
  /// book page renders. Only the persistent cache is consulted.
  Future<List<Recommendation>> seriesCardsForCollections(
    Iterable<String> collectionIds, {
    required List<String> langs,
  }) async {
    final wanted = collectionIds.toSet();
    if (wanted.isEmpty) return const [];
    final inputs = await ensureLookupInputs();
    if (inputs == null || inputs.series.isEmpty) return const [];

    final byCollection = await _discovery.buildFromCache(inputs, langs);
    for (final lookup in inputs.series) {
      if (!wanted.contains(lookup.collectionId)) continue;
      final cards = byCollection[lookup.collectionId];
      if (cards != null && cards.isNotEmpty) return cards;
    }
    return const [];
  }

  /// Unowned works of the author an author page is showing, resolving on
  /// open under the shared 24h throttle (ADR-061 section 2).
  ///
  /// The ADR-059 floor on visible local suggestions is a dashboard-rendering
  /// rule and does not apply here: the visit IS the explicit gesture. The
  /// PROFILE floor is different and cannot be bypassed: below it the FFI
  /// returns an empty identity index, and running the lane without the
  /// membrane would offer the reader books already on their shelf, which the
  /// precision doctrine forbids outright. An empty index therefore shows
  /// nothing.
  Future<List<Recommendation>> authorPageDiscovery({
    required String name,
    required List<String> anchorIsbns,
    required List<String> langs,
  }) async {
    final inputs = await ensureLookupInputs();
    if (inputs == null) return const [];
    if (inputs.libraryIsbns.isEmpty && inputs.libraryTitleAuthorKeys.isEmpty) {
      return const [];
    }
    return _discovery.resolveAuthorForVisit(
      lookup: DiscoveryAuthorLookup(name: name, anchorIsbns: anchorIsbns),
      inputs: inputs,
      langs: langs,
      limit: authorPageMaxWorks,
    );
  }

  @override
  void dispose() {
    _bookRefreshNotifier.removeListener(_markStale);
    super.dispose();
  }
}
