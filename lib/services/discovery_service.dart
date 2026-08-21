import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../models/discovery.dart';
import '../models/recommendation.dart';
import '../utils/isbn_validator.dart';
import 'api_service.dart';

/// External discovery client (ADR-060, series and author lanes): anonymous
/// hub calls, 24h throttle, bounded persistent caches, and the precision
/// membrane that filters resolver answers against the library identity
/// index.
///
/// Failure doctrine: never throw toward the UI. A hub failure keeps the
/// previously cached payload rendering (stale-while-error); an empty cache
/// plus no network simply means no external cards.
///
/// Blending, caps and dismissal live in RecommendationProvider; this
/// service owns fetching, caching and candidate building only.
class DiscoveryService {
  DiscoveryService({http.Client? client, String? baseUrl, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl,
      _now = now ?? DateTime.now;

  final http.Client _client;
  final String? _baseUrl;
  final DateTime Function() _now;

  String get _resolvedBaseUrl => _baseUrl ?? ApiService.hubUrl;

  /// SharedPreferences key: JSON map of collection id to
  /// `{"at": epochMs, "status": ..., "series": <resolver payload>}`.
  /// Listed in the backup prefs blacklist (device-local cache).
  static const String cacheKey = 'discovery_series_cache_v1';

  /// Same shape for the author lane, keyed by author name (the lookup key
  /// of a favorite author: the client holds no author identifier, ADR-060
  /// grounding facts). Also listed in the backup prefs blacklist.
  static const String authorCacheKey = 'discovery_author_cache_v1';

  /// External lookups run at most once per 24h per lookup key (ADR-060
  /// section 4.3). The attempt is what is throttled: a failed sweep also
  /// waits, and its cached payload keeps rendering meanwhile.
  static const Duration throttle = Duration(hours: 24);

  /// Bound on cached lookups (storage policy: bounded structures). Evicts
  /// the oldest entries; 50 series collections is far past any real shelf.
  static const int maxCacheEntries = 50;

  /// Same bound for the author lane, raised to the series bound because
  /// the author page (ADR-061) resolves ANY consulted author, not just the
  /// five favorites a sweep covers.
  ///
  /// Eviction is pure LRU on the entry timestamp, deliberately: the sweep
  /// used to drop every key absent from the taste profile, which with
  /// visit lookups would erase a page-warmed entry on the next dashboard
  /// load and defeat the 24h throttle it exists to enforce.
  static const int maxAuthorCacheEntries = 50;

  /// At most two works per author reach the blend (ADR-060 section 4.4).
  /// Kept deeper here so a dismissal reveals the next work instead of
  /// emptying the author.
  static const int authorCandidatesPerAuthor = 6;

  /// Anchor width of one lookup (ADR-060 section 5, decision 3). Mirror of
  /// the Rust `ANCHOR_ISBNS_MAX`; the hub rejects a fourth entry.
  static const int anchorIsbnsMax = 3;

  static const Duration _requestTimeout = Duration(seconds: 8);

  // ── Candidate building (pure over the cache snapshot) ───────────────

  /// External candidates from the current cache, keyed by the collection id
  /// of their series and in lookup order: one entry per series, its missing
  /// volumes lowest ordinal first. The provider picks the first
  /// non-dismissed candidate of each series (ADR-060: one card per
  /// series). Volumes matching the library identity index by ISBN or by
  /// title+author are never candidates (section 4.2: translations and
  /// re-editions are the main false-positive reservoir).
  ///
  /// Keyed rather than positional because the book page (ADR-061) needs the
  /// candidates of ONE named series collection, not the whole blend.
  Future<Map<String, List<Recommendation>>> buildFromCache(
    DiscoveryLookupInputs inputs,
    List<String> langs,
  ) async {
    return buildSeriesCandidates(
      inputs: inputs,
      cache: await _readCache(cacheKey),
      langs: langs,
    );
  }

  /// Pure candidate builder, visible for tests.
  @visibleForTesting
  static Map<String, List<Recommendation>> buildSeriesCandidates({
    required DiscoveryLookupInputs inputs,
    required Map<String, dynamic> cache,
    required List<String> langs,
  }) {
    final perSeries = <String, List<Recommendation>>{};
    final library = DiscoveryIdentityIndex.of(
      inputs.libraryIsbns,
      inputs.libraryTitleAuthorKeys,
    );
    for (final lookup in inputs.series) {
      final entry = cache[lookup.collectionId];
      final series = entry is Map ? entry['series'] : null;
      if (series is! Map) continue;

      final members = DiscoveryIdentityIndex.of(
        lookup.memberIsbns,
        lookup.memberTitleAuthorKeys,
      );
      final volumes = (series['volumes'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      final cards = <Recommendation>[];
      for (final volume in volumes) {
        final card = _volumeCard(volume, series, lookup, library, members, langs);
        if (card != null) cards.add(card);
      }
      cards.sort(
        (a, b) => (int.tryParse(a.reasons.first.value) ?? 0)
            .compareTo(int.tryParse(b.reasons.first.value) ?? 0),
      );
      if (cards.isNotEmpty) perSeries[lookup.collectionId] = cards;
    }
    return perSeries;
  }

  static Recommendation? _volumeCard(
    Map<dynamic, dynamic> volume,
    Map<dynamic, dynamic> series,
    DiscoverySeriesLookup lookup,
    DiscoveryIdentityIndex library,
    DiscoveryIdentityIndex members,
    List<String> langs,
  ) {
    final ordinal = _asInt(volume['ordinal']);
    final title = volume['title'];
    if (ordinal == null || title is! String || title.trim().isEmpty) {
      return null;
    }
    final authors =
        (volume['authors'] as List? ?? const []).whereType<String>().toList();
    final editions =
        (volume['editions'] as List? ?? const []).whereType<Map>().toList();

    if (_matchesLibraryIdentity(
      [title],
      authors,
      editions,
      library,
      members: members,
    )) {
      return null;
    }

    final edition = _pickEdition(editions, langs);
    final isbn = edition?['isbn'] is String ? edition!['isbn'] as String : null;
    final coverUrl = _pickCoverUrl(edition, editions);
    final sourceId = series['source_id']?.toString() ?? '';
    final seriesName = lookup.name.trim().isNotEmpty
        ? lookup.name.trim()
        : (series['label']?.toString() ?? '');

    return Recommendation(
      book: Book(
        title: title,
        isbn: isbn,
        author: authors.isEmpty ? null : authors.join(', '),
        publicationYear: _asInt(volume['year']),
        coverUrl: coverUrl,
        owned: false,
      ),
      score: 0,
      reasons: [
        RecommendationReason(
          type: 'series_missing_volume',
          value: '$ordinal',
          params: {'ordinal': '$ordinal', 'series': seriesName},
        ),
      ],
      source: RecommendationSource.external,
      externalKey: isbn != null ? 'isbn:$isbn' : 'series:$sourceId:$ordinal',
    );
  }

  /// The precision membrane, shared by both lanes: a candidate already in
  /// the library (any status, wishlist included) or among the series
  /// members must never be suggested. ISBN first, then normalized
  /// title+author over every known title of the candidate, exactly the two
  /// halves the Rust identity index was built for.
  static bool _matchesLibraryIdentity(
    List<String> titles,
    List<String> authors,
    List<Map<dynamic, dynamic>> editions,
    DiscoveryIdentityIndex library, {
    DiscoveryIdentityIndex? members,
  }) {
    for (final edition in editions) {
      final raw = edition['isbn'];
      if (raw is! String) continue;
      final cleaned = cleanIsbn(raw);
      if (cleaned.isEmpty) continue;
      if (library.hasIsbn(cleaned) || (members?.hasIsbn(cleaned) ?? false)) {
        return true;
      }
    }
    for (final title in titles) {
      final normTitle = normalizeIdentityText(title);
      if (normTitle.isEmpty) continue;
      for (final author in authors) {
        final normAuthor = normalizeIdentityText(author);
        if (normAuthor.isEmpty) continue;
        if (library.hasKey(normTitle, normAuthor) ||
            (members?.hasKey(normTitle, normAuthor) ?? false)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Among the returned editions (already filtered hub-side to the reader
  /// languages plus the original), prefer a reading-language one and fall
  /// back to the first (the original edition when known) otherwise.
  ///
  /// The reader's languages are tried IN ORDER, each against the whole
  /// payload: a trilingual reader whose first language is French must get
  /// the French edition even when the payload happens to list a Spanish one
  /// first. Matching a set of languages in payload order would satisfy "a
  /// reading-language edition" to the letter while defeating the point of
  /// sending the reader's languages at all.
  static Map<dynamic, dynamic>? _pickEdition(
    List<Map<dynamic, dynamic>> editions,
    List<String> langs,
  ) {
    if (editions.isEmpty) return null;
    for (final lang in langs) {
      final lower = lang.toLowerCase();
      final dash = lower.indexOf('-');
      final base = dash > 0 ? lower.substring(0, dash) : lower;
      for (final edition in editions) {
        final editionLang = edition['lang'];
        if (editionLang is! String) continue;
        final normalized = editionLang.toLowerCase();
        if (normalized == lower || normalized == base) return edition;
      }
    }
    return editions.first;
  }

  static String? _pickCoverUrl(
    Map<dynamic, dynamic>? picked,
    List<Map<dynamic, dynamic>> editions,
  ) {
    final own = picked?['cover_url'];
    if (own is String && own.isNotEmpty) return own;
    for (final edition in editions) {
      final url = edition['cover_url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return null;
  }

  /// External candidates from the author cache, keyed by lookup name and in
  /// lookup order: one entry per author, its works ranked by edition count
  /// (the popularity proxy the resolver publishes). The provider shows at
  /// most two per author; the rest are the reserve a dismissal draws from.
  Future<Map<String, List<Recommendation>>> buildAuthorsFromCache(
    DiscoveryLookupInputs inputs,
    List<String> langs,
  ) async {
    return buildAuthorCandidates(
      inputs: inputs,
      cache: await _readCache(authorCacheKey),
      langs: langs,
    );
  }

  /// Pure candidate builder for the author lane, visible for tests.
  ///
  /// [lookups] defaults to the taste profile's favorite authors. The author
  /// page (ADR-061) passes the single author being consulted instead, which
  /// is routinely NOT a favorite: only the library identity index of
  /// [inputs] is needed to filter, never its author list.
  @visibleForTesting
  static Map<String, List<Recommendation>> buildAuthorCandidates({
    required DiscoveryLookupInputs inputs,
    required Map<String, dynamic> cache,
    required List<String> langs,
    List<DiscoveryAuthorLookup>? lookups,
    int limit = authorCandidatesPerAuthor,
  }) {
    final perAuthor = <String, List<Recommendation>>{};
    final library = DiscoveryIdentityIndex.of(
      inputs.libraryIsbns,
      inputs.libraryTitleAuthorKeys,
    );
    // Spelling variants of one name ("J.K. Rowling" and "J. K. Rowling")
    // survive the Rust profile normalization as two favorite authors, so
    // two lookups resolve to the SAME entity and would show the same works
    // twice. The resolved source_id is the only reliable identity we have:
    // the first lookup (profile order, liked-count first) keeps the cards.
    final seenAuthorIds = <String>{};
    for (final lookup in lookups ?? inputs.authors) {
      final entry = cache[lookup.name];
      final author = entry is Map ? entry['author'] : null;
      if (author is! Map) continue;
      final sourceId = author['source_id']?.toString() ?? '';
      if (sourceId.isNotEmpty && !seenAuthorIds.add(sourceId)) continue;

      final works = (author['works'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      // Popularity first, the resolver's own ranking breaking ties: a work
      // whose editions were never counted (past the resolver's enrichment
      // rank) sorts last rather than first.
      final ranked = works.indexed.toList()
        ..sort((a, b) {
          final byCount = (_asInt(b.$2['editions_count']) ?? -1).compareTo(
            _asInt(a.$2['editions_count']) ?? -1,
          );
          return byCount != 0 ? byCount : a.$1.compareTo(b.$1);
        });

      final cards = <Recommendation>[];
      for (final entry in ranked) {
        if (cards.length >= limit) break;
        final card = _workCard(entry.$2, author, lookup, library, langs);
        if (card != null) cards.add(card);
      }
      if (cards.isNotEmpty) perAuthor[lookup.name] = cards;
    }
    return perAuthor;
  }

  static Recommendation? _workCard(
    Map<dynamic, dynamic> work,
    Map<dynamic, dynamic> author,
    DiscoveryAuthorLookup lookup,
    DiscoveryIdentityIndex library,
    List<String> langs,
  ) {
    final title = work['title'];
    if (title is! String || title.trim().isEmpty) return null;

    // The resolver answers in the reader's language when the sources know
    // it and lists the other titles it holds: a library catalogued in
    // French must match a work the sources name in English, or the
    // membrane silently stops working on translations.
    final titles = <String>{
      title,
      ...(work['titles'] as List? ?? const []).whereType<String>(),
    }.toList();
    final authors =
        (work['authors'] as List? ?? const []).whereType<String>().toList();
    final editions =
        (work['editions'] as List? ?? const []).whereType<Map>().toList();

    if (_matchesLibraryIdentity(
      titles,
      authors.isEmpty ? [lookup.name] : authors,
      editions,
      library,
    )) {
      return null;
    }

    final edition = _pickEdition(editions, langs);
    final isbn = edition?['isbn'] is String ? edition!['isbn'] as String : null;
    final sourceId = author['source_id']?.toString() ?? '';

    return Recommendation(
      book: Book(
        title: title,
        isbn: isbn,
        author: authors.isEmpty ? lookup.name : authors.join(', '),
        publicationYear: _asInt(work['year']),
        coverUrl: _pickCoverUrl(edition, editions),
        owned: false,
      ),
      score: 0,
      reasons: [
        RecommendationReason(
          type: 'author_completion',
          value: lookup.name,
          params: {'author': lookup.name},
        ),
      ],
      source: RecommendationSource.external,
      externalKey: isbn != null
          ? 'isbn:$isbn'
          : 'author:$sourceId:${normalizeIdentityText(title)}',
    );
  }

  // ── Sweep (throttled hub calls) ─────────────────────────────────────

  /// Refresh stale lookups against the hub. Returns true when the cache
  /// changed (the caller rebuilds its candidates). Never blocks rendering:
  /// callers render from cache first and sweep behind.
  Future<bool> sweep(DiscoveryLookupInputs inputs, List<String> langs) async {
    final cache = await _readCache(cacheKey);
    var changed = false;

    // Entries whose lookup is no longer derivable (series deleted, ISBNs
    // lost) are evicted (ADR-060 section 4.3).
    final liveIds = inputs.series.map((s) => s.collectionId).toSet();
    for (final stale in cache.keys.where((k) => !liveIds.contains(k)).toList()) {
      cache.remove(stale);
      changed = true;
    }

    for (final lookup in inputs.series) {
      final entry = cache[lookup.collectionId];
      if (_isThrottled(entry)) continue;

      final result = await _postSeries(lookup, langs);
      if (result.rateLimited) continue;
      final envelope = result.envelope;
      final next = <String, dynamic>{'at': _now().millisecondsSinceEpoch};
      final status = envelope?['status'];
      if (status == 'resolved' && envelope!['series'] is Map) {
        next['status'] = 'resolved';
        next['series'] = envelope['series'];
      } else if (status == 'ambiguous' || status == 'unknown') {
        // Definitive negative from the resolver: show nothing, and drop
        // any stale payload so it cannot resurface.
        next['status'] = status;
      } else {
        // 'unavailable' or transport failure: not cached hub-side, and
        // client-side the previous payload keeps rendering.
        next['status'] = 'unavailable';
        final previous = entry is Map ? entry['series'] : null;
        if (previous is Map) next['series'] = previous;
      }
      cache[lookup.collectionId] = next;
      changed = true;
    }

    if (changed) await _writeCache(cacheKey, cache, maxCacheEntries);
    return changed;
  }

  Future<_LookupResult> _postSeries(
    DiscoverySeriesLookup lookup,
    List<String> langs,
  ) async {
    try {
      final name = lookup.name.trim();
      final response = await _client
          .post(
            Uri.parse('$_resolvedBaseUrl/api/discovery/series'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'isbns': lookup.anchorIsbns,
              if (name.isNotEmpty)
                'name': name.length > 256 ? name.substring(0, 256) : name,
              'langs': langs.take(8).toList(),
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        debugPrint(
          'DiscoveryService: series lookup returned HTTP ${response.statusCode}',
        );
        return _LookupResult.failed(response.statusCode);
      }
      final data = jsonDecode(response.body);
      return _LookupResult(data is Map<String, dynamic> ? data : null, false);
    } catch (e) {
      debugPrint('DiscoveryService: series lookup failed: $e');
      return const _LookupResult(null, false);
    }
  }

  /// Refresh stale author lookups against the hub, same contract as
  /// [sweep]: throttled per lookup key, stale-while-error.
  ///
  /// Unlike the series lane this one does NOT evict the keys missing from
  /// [inputs]: since the author page resolves consulted authors into the
  /// same cache (ADR-061), absence from the taste profile no longer means
  /// "no longer derivable", and evicting would erase a page-warmed entry on
  /// the next dashboard load. The bound is the LRU cap of [_writeCache].
  Future<bool> sweepAuthors(
    DiscoveryLookupInputs inputs,
    List<String> langs,
  ) async {
    final cache = await _readCache(authorCacheKey);
    var changed = false;

    for (final lookup in inputs.authors) {
      if (_isThrottled(cache[lookup.name])) continue;

      final result = await _postAuthor(lookup, langs);
      if (result.rateLimited) continue;
      cache[lookup.name] = _authorCacheEntry(result.envelope, cache[lookup.name]);
      changed = true;
    }

    if (changed) {
      await _writeCache(authorCacheKey, cache, maxAuthorCacheEntries);
    }
    return changed;
  }

  /// Resolve ONE author for a page visit (ADR-061): serve from cache, and
  /// fire a single lookup when the entry is missing or past the 24h
  /// throttle. The visit is the explicit gesture, so no local-suggestion
  /// floor applies, but the anchor rule does: an author none of whose local
  /// books carries a checksum-valid ISBN produces no request at all.
  ///
  /// The cache is shared with the profile sweep under the same key shape, so
  /// a visit warms the dashboard and vice versa.
  Future<List<Recommendation>> resolveAuthorForVisit({
    required DiscoveryAuthorLookup lookup,
    required DiscoveryLookupInputs inputs,
    required List<String> langs,
    required int limit,
  }) async {
    final cache = await _readCache(authorCacheKey);
    final entry = cache[lookup.name];
    if (lookup.anchorIsbns.isNotEmpty && !_isThrottled(entry)) {
      final result = await _postAuthor(lookup, langs);
      // Back-pressure is not a resolution outcome: leave the entry alone so
      // the next visit retries instead of going silent for a day.
      if (!result.rateLimited) {
        cache[lookup.name] = _authorCacheEntry(result.envelope, entry);
        await _writeCache(authorCacheKey, cache, maxAuthorCacheEntries);
      }
    }
    return buildAuthorCandidates(
          inputs: inputs,
          cache: cache,
          langs: langs,
          lookups: [lookup],
          limit: limit,
        )[lookup.name] ??
        const [];
  }

  /// What the client keeps of a resolved author payload (ADR-061 section 4):
  /// the fields it actually consumes, and nothing else.
  ///
  /// Measured on a real 40-work bibliography before choosing what to cut, so
  /// this is a subtraction of dead weight and NOT a "render-only" reduction:
  ///
  ///     editions 25%   titles 21%   authors 16.5%   title 15%
  ///     other_langs_exist 9.7%   editions_count 8%   year 5%
  ///
  /// Everything above 5% except `other_langs_exist` is read by the precision
  /// membrane: it compares EVERY edition ISBN and EVERY alternate title
  /// against the library, which is what stops the reader being offered a
  /// translation of a book on their shelf. Dropping those to save bytes
  /// would silently disable the rule the whole feature rests on, and it
  /// would not show up as a failure, only as worse suggestions.
  ///
  /// So what actually goes: `other_langs_exist`, which no client code reads
  /// (the "no edition at all" vs "none in my languages" distinction was
  /// never built), the alternate titles that merely repeat `title` (40 of 59
  /// in the sample; the membrane unions them anyway), edition fields beyond
  /// the three that are used, and empty values. Result on that sample:
  /// 11.7 KB down to 7.4 KB, 37% saved with the membrane fully intact.
  ///
  /// The shape is a strict SUBSET of the hub's, and the builders read by
  /// field name, so entries written before this projection existed stay
  /// readable and are rewritten as projections when their 24h throttle
  /// lapses. No cache-key bump, which would have forced every device to
  /// re-resolve and spent hub outbound budget for nothing.
  @visibleForTesting
  static Map<String, dynamic> projectAuthorPayload(
    Map<dynamic, dynamic> author,
  ) {
    final works = (author['works'] as List? ?? const []).whereType<Map>();
    return {
      if (author['source'] != null) 'source': author['source'],
      if (author['source_id'] != null) 'source_id': author['source_id'],
      if (author['label'] != null) 'label': author['label'],
      'works': [for (final work in works) _projectWork(work)],
    };
  }

  static Map<String, dynamic> _projectWork(Map<dynamic, dynamic> work) {
    final title = work['title'];
    final alternates = (work['titles'] as List? ?? const [])
        .whereType<String>()
        .where((t) => t != title)
        .toList();
    final authors =
        (work['authors'] as List? ?? const []).whereType<String>().toList();
    final editions = [
      for (final edition in (work['editions'] as List? ?? const [])
          .whereType<Map>())
        {
          for (final field in const ['isbn', 'lang', 'cover_url'])
            if (edition[field] != null) field: edition[field],
        },
    ]..removeWhere((edition) => edition.isEmpty);

    return {
      if (title != null) 'title': title,
      if (alternates.isNotEmpty) 'titles': alternates,
      if (authors.isNotEmpty) 'authors': authors,
      if (work['editions_count'] != null)
        'editions_count': work['editions_count'],
      if (work['year'] != null) 'year': work['year'],
      if (editions.isNotEmpty) 'editions': editions,
    };
  }

  /// True while [entry]'s last attempt is inside the 24h window.
  bool _isThrottled(dynamic entry) {
    final at = entry is Map ? entry['at'] : null;
    return at is int &&
        _now().difference(DateTime.fromMillisecondsSinceEpoch(at)) < throttle;
  }

  /// The cache entry one author lookup leaves behind, whatever its outcome.
  /// Shared by the sweep and the page visit so the two cannot drift on the
  /// stale-while-error rule.
  Map<String, dynamic> _authorCacheEntry(
    Map<String, dynamic>? envelope,
    dynamic previous,
  ) {
    final next = <String, dynamic>{'at': _now().millisecondsSinceEpoch};
    final status = envelope?['status'];
    if (status == 'resolved' && envelope!['author'] is Map) {
      next['status'] = 'resolved';
      next['author'] = projectAuthorPayload(
        envelope['author'] as Map<dynamic, dynamic>,
      );
    } else if (status == 'ambiguous' || status == 'unknown') {
      // Definitive negative: a homonym or an unknown author shows
      // nothing, and any stale payload is dropped so it cannot resurface.
      next['status'] = status;
    } else {
      next['status'] = 'unavailable';
      final kept = previous is Map ? previous['author'] : null;
      if (kept is Map) next['author'] = kept;
    }
    return next;
  }

  Future<_LookupResult> _postAuthor(
    DiscoveryAuthorLookup lookup,
    List<String> langs,
  ) async {
    try {
      final name = lookup.name.trim();
      final response = await _client
          .post(
            Uri.parse('$_resolvedBaseUrl/api/discovery/author'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'name': name.length > 256 ? name.substring(0, 256) : name,
              'anchor_isbns': lookup.anchorIsbns,
              'langs': langs.take(8).toList(),
            }),
          )
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        debugPrint(
          'DiscoveryService: author lookup returned HTTP ${response.statusCode}',
        );
        return _LookupResult.failed(response.statusCode);
      }
      final data = jsonDecode(response.body);
      return _LookupResult(data is Map<String, dynamic> ? data : null, false);
    } catch (e) {
      debugPrint('DiscoveryService: author lookup failed: $e');
      return const _LookupResult(null, false);
    }
  }

  // ── Persistent bounded cache ────────────────────────────────────────

  /// Decoded caches, kept in memory so a page opening does not re-parse them
  /// (ADR-061 section 4). The series cache alone can hold 50 payloads, and
  /// every book page used to pay a full `jsonDecode` of the lot on the UI
  /// isolate just to read one series.
  ///
  /// Callers get a shallow COPY: the sweeps mutate what they receive before
  /// writing it back, and handing them the memo itself would let a mutation
  /// that never reaches [_writeCache] desynchronise the two. The copy is
  /// cheap next to the decode it replaces.
  final Map<String, Map<String, dynamic>> _decodedCaches = {};

  /// Number of real `jsonDecode` passes, so a test can prove the memo works
  /// rather than assert on timing.
  @visibleForTesting
  int cacheDecodeCount = 0;

  Future<Map<String, dynamic>> _readCache(String key) async {
    final memo = _decodedCaches[key];
    if (memo != null) return Map<String, dynamic>.of(memo);
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return <String, dynamic>{};
      cacheDecodeCount++;
      final decoded = jsonDecode(raw);
      final map = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      _decodedCaches[key] = map;
      return Map<String, dynamic>.of(map);
    } catch (e) {
      debugPrint('DiscoveryService: cache read error: $e');
      return <String, dynamic>{};
    }
  }

  /// Persist [cache], dropping the least recently attempted entries past
  /// [maxEntries] (LRU on the `at` timestamp). This is the only bound on the
  /// author cache since page visits made "absent from the taste profile" a
  /// meaningless eviction criterion (ADR-061).
  Future<void> _writeCache(
    String key,
    Map<String, dynamic> cache,
    int maxEntries,
  ) async {
    try {
      if (cache.length > maxEntries) {
        final byAge = cache.entries.toList()
          ..sort((a, b) {
            final aAt = a.value is Map ? (a.value['at'] as int? ?? 0) : 0;
            final bAt = b.value is Map ? (b.value['at'] as int? ?? 0) : 0;
            return bAt.compareTo(aAt);
          });
        cache
          ..clear()
          ..addEntries(byAge.take(maxEntries));
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(cache));
      // The memo now IS this map: readers get copies of it, so nothing else
      // holds a reference that could drift.
      _decodedCaches[key] = cache;
    } catch (e) {
      debugPrint('DiscoveryService: cache write error: $e');
    }
  }

  // ── Identity normalization (mirror of the Rust side) ────────────────

  /// Separator-stripped uppercase ISBN, the comparison form of the Rust
  /// identity index (which already carries both 10/13 forms).
  ///
  /// Comparison only: this deliberately does NOT validate, so an unparseable
  /// value still matches itself inside the membrane. Never use it to build a
  /// lookup anchor, see [anchorIsbnsFrom].
  static String cleanIsbn(String raw) =>
      raw.trim().replaceAll(RegExp(r'[-\s]'), '').toUpperCase();

  /// Up to [anchorIsbnsMax] canonical ISBN-13 anchors for one lookup, in the
  /// order given, deduplicated. Mirror of the Rust `push_anchor`, and it has
  /// to stay one: a value that is not a valid ISBN-10/13 is DROPPED here, not
  /// passed through.
  ///
  /// The reason is not tidiness. The hub validates format AND checksum and
  /// answers 400 for the whole request on the first malformed entry, while
  /// the client counts any non-200 as an attempt: one bad ISBN among a
  /// reader's books would therefore veto the valid anchors sitting next to
  /// it AND silence that lookup for the full 24h throttle. Real catalogues
  /// carry those values, which is the same trap the resolver paid hub-side
  /// (ADR-060, "a source client error is an answer, not an outage").
  static List<String> anchorIsbnsFrom(Iterable<String?> rawIsbns) {
    final anchors = <String>[];
    for (final raw in rawIsbns) {
      if (anchors.length >= anchorIsbnsMax) break;
      if (raw == null) continue;
      final canonical = IsbnValidator.toIsbn13(raw);
      if (canonical == null || anchors.contains(canonical)) continue;
      anchors.add(canonical);
    }
    return anchors;
  }

  /// Mirror of `normalize_identity_text` in the Rust
  /// `discovery_lookup_service`: lowercase, fold diacritics, split on any
  /// non-alphanumeric character, join words with single spaces. Keep the
  /// two implementations in sync (shared test fixtures on both sides).
  ///
  /// The fold here maps the precomposed Latin letters that NFD decomposes
  /// (plus the two Cyrillic ones) and strips stray combining marks;
  /// letters without a canonical decomposition (o-slash, oe, ae, eszett)
  /// stay as-is, exactly like the Rust NFD pass.
  static String normalizeIdentityText(String s) {
    final folded = s
        .toLowerCase()
        .split('')
        .map((c) => _diacriticFold[c] ?? c)
        .join()
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '');
    return folded
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .join(' ');
  }

  static const Map<String, String> _diacriticFold = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    'ç': 'c', 'ñ': 'n',
    'ā': 'a', 'ă': 'a', 'ą': 'a',
    'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c',
    'ď': 'd',
    'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
    'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
    'ĥ': 'h',
    'ĩ': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i',
    'ĵ': 'j', 'ķ': 'k',
    'ĺ': 'l', 'ļ': 'l', 'ľ': 'l',
    'ń': 'n', 'ņ': 'n', 'ň': 'n',
    'ō': 'o', 'ŏ': 'o', 'ő': 'o',
    'ŕ': 'r', 'ŗ': 'r', 'ř': 'r',
    'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's',
    'ţ': 't', 'ť': 't',
    'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
    'ŵ': 'w', 'ŷ': 'y',
    'ź': 'z', 'ż': 'z', 'ž': 'z',
    'й': 'и', 'ё': 'е',
  };

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}


/// One side of the precision membrane: the ISBNs and "title|author"
/// identity keys a candidate is matched against.
///
/// The keys are held twice, as they come from the Rust index and with the
/// author's words sorted. Catalogues imported as "Rowling, J. K." produce
/// keys whose author words are in the other order from the sources'
/// ("j k rowling" against "rowling j k"), and an order-sensitive
/// comparison then matches nothing for those libraries: the reader is
/// offered translations of books sitting on their shelf. Sorting BOTH
/// sides here fixes it without touching the Rust index (which keeps
/// emitting its keys unchanged), and it cannot widen the match beyond the
/// same words about the same title.
///
/// Public because every discovery surface must match through THIS class and
/// never re-derive its own comparison (ADR-061): the alternate-title and
/// inverted-name handling above was paid for twice already.
class DiscoveryIdentityIndex {
  const DiscoveryIdentityIndex(this._isbns, this._keys, this._sortedKeys);

  factory DiscoveryIdentityIndex.of(Set<String> isbns, Set<String> keys) {
    return DiscoveryIdentityIndex(
      isbns,
      keys,
      keys.map(_sortAuthorWords).toSet(),
    );
  }

  final Set<String> _isbns;
  final Set<String> _keys;
  final Set<String> _sortedKeys;

  bool hasIsbn(String cleanedIsbn) => _isbns.contains(cleanedIsbn);

  bool hasKey(String normalizedTitle, String normalizedAuthor) {
    final key = '$normalizedTitle|$normalizedAuthor';
    return _keys.contains(key) || _sortedKeys.contains(_sortAuthorWords(key));
  }

  /// "dune|herbert frank" becomes "dune|frank herbert": only the author
  /// half is reordered, a title's word order is meaningful.
  static String _sortAuthorWords(String key) {
    final separator = key.lastIndexOf('|');
    if (separator < 0) return key;
    final author = key.substring(separator + 1).split(' ')..sort();
    return '${key.substring(0, separator)}|${author.join(' ')}';
  }
}

/// Outcome of one hub lookup: the envelope when the hub answered, plus
/// whether the hub applied BACK-PRESSURE (429).
///
/// The 24h throttle deliberately counts attempts, so a failed sweep waits
/// like a successful one (ADR-060 section 4.3). A 429 is the exception: it
/// is not a resolution outcome but our own burst hitting the anonymous
/// per-IP limiter, and recording it as an attempt would silence that
/// lookup for a full day. A library with many series AND favorite authors
/// sweeps both lanes on its first run, which is exactly when the burst
/// happens, so those lookups are left untouched and retried on the next
/// dashboard load instead.
class _LookupResult {
  const _LookupResult(this.envelope, this.rateLimited);

  factory _LookupResult.failed(int statusCode) =>
      _LookupResult(null, statusCode == 429);

  final Map<String, dynamic>? envelope;
  final bool rateLimited;
}
