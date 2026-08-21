import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book.dart';
import '../models/discovery.dart';
import '../models/recommendation.dart';
import 'api_service.dart';

/// External discovery client (ADR-060, series lane): anonymous hub calls,
/// 24h throttle, bounded persistent cache, and the precision membrane that
/// filters resolver answers against the library identity index.
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

  /// External lookups run at most once per 24h per lookup key (ADR-060
  /// section 4.3). The attempt is what is throttled: a failed sweep also
  /// waits, and its cached payload keeps rendering meanwhile.
  static const Duration throttle = Duration(hours: 24);

  /// Bound on cached lookups (storage policy: bounded structures). Evicts
  /// the oldest entries; 50 series collections is far past any real shelf.
  static const int maxCacheEntries = 50;

  static const Duration _requestTimeout = Duration(seconds: 8);

  // ── Candidate building (pure over the cache snapshot) ───────────────

  /// External candidates from the current cache: one inner list per series
  /// (missing volumes, lowest ordinal first). The provider picks the first
  /// non-dismissed candidate of each series (ADR-060: one card per
  /// series). Volumes matching the library identity index by ISBN or by
  /// title+author are never candidates (section 4.2: translations and
  /// re-editions are the main false-positive reservoir).
  Future<List<List<Recommendation>>> buildFromCache(
    DiscoveryLookupInputs inputs,
    List<String> langs,
  ) async {
    return buildSeriesCandidates(
      inputs: inputs,
      cache: await _readCache(),
      langs: langs,
    );
  }

  /// Pure candidate builder, visible for tests.
  @visibleForTesting
  static List<List<Recommendation>> buildSeriesCandidates({
    required DiscoveryLookupInputs inputs,
    required Map<String, dynamic> cache,
    required List<String> langs,
  }) {
    final perSeries = <List<Recommendation>>[];
    for (final lookup in inputs.series) {
      final entry = cache[lookup.collectionId];
      final series = entry is Map ? entry['series'] : null;
      if (series is! Map) continue;

      final volumes = (series['volumes'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      final cards = <Recommendation>[];
      for (final volume in volumes) {
        final card = _volumeCard(volume, series, lookup, inputs, langs);
        if (card != null) cards.add(card);
      }
      cards.sort(
        (a, b) => (int.tryParse(a.reasons.first.value) ?? 0)
            .compareTo(int.tryParse(b.reasons.first.value) ?? 0),
      );
      if (cards.isNotEmpty) perSeries.add(cards);
    }
    return perSeries;
  }

  static Recommendation? _volumeCard(
    Map<dynamic, dynamic> volume,
    Map<dynamic, dynamic> series,
    DiscoverySeriesLookup lookup,
    DiscoveryLookupInputs inputs,
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

    if (_matchesLibrary(title, authors, editions, lookup, inputs)) return null;

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

  /// The precision membrane: a volume already in the library (any status,
  /// wishlist included) or among the series members must never be
  /// suggested. ISBN first, then normalized title+author, exactly the two
  /// halves the Rust identity index was built for.
  static bool _matchesLibrary(
    String title,
    List<String> authors,
    List<Map<dynamic, dynamic>> editions,
    DiscoverySeriesLookup lookup,
    DiscoveryLookupInputs inputs,
  ) {
    for (final edition in editions) {
      final raw = edition['isbn'];
      if (raw is! String) continue;
      final cleaned = cleanIsbn(raw);
      if (cleaned.isEmpty) continue;
      if (lookup.memberIsbns.contains(cleaned) ||
          inputs.libraryIsbns.contains(cleaned)) {
        return true;
      }
    }
    final normTitle = normalizeIdentityText(title);
    if (normTitle.isEmpty) return false;
    for (final author in authors) {
      final normAuthor = normalizeIdentityText(author);
      if (normAuthor.isEmpty) continue;
      final key = '$normTitle|$normAuthor';
      if (lookup.memberTitleAuthorKeys.contains(key) ||
          inputs.libraryTitleAuthorKeys.contains(key)) {
        return true;
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

  // ── Sweep (throttled hub calls) ─────────────────────────────────────

  /// Refresh stale lookups against the hub. Returns true when the cache
  /// changed (the caller rebuilds its candidates). Never blocks rendering:
  /// callers render from cache first and sweep behind.
  Future<bool> sweep(DiscoveryLookupInputs inputs, List<String> langs) async {
    final cache = await _readCache();
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
      final at = entry is Map ? entry['at'] : null;
      if (at is int &&
          _now().difference(DateTime.fromMillisecondsSinceEpoch(at)) <
              throttle) {
        continue;
      }

      final envelope = await _postSeries(lookup, langs);
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

    if (changed) await _writeCache(cache);
    return changed;
  }

  Future<Map<String, dynamic>?> _postSeries(
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
        return null;
      }
      final data = jsonDecode(response.body);
      return data is Map<String, dynamic> ? data : null;
    } catch (e) {
      debugPrint('DiscoveryService: series lookup failed: $e');
      return null;
    }
  }

  // ── Persistent bounded cache ────────────────────────────────────────

  Future<Map<String, dynamic>> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(cacheKey);
      if (raw == null) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (e) {
      debugPrint('DiscoveryService: cache read error: $e');
      return <String, dynamic>{};
    }
  }

  Future<void> _writeCache(Map<String, dynamic> cache) async {
    try {
      if (cache.length > maxCacheEntries) {
        final byAge = cache.entries.toList()
          ..sort((a, b) {
            final aAt = a.value is Map ? (a.value['at'] as int? ?? 0) : 0;
            final bAt = b.value is Map ? (b.value['at'] as int? ?? 0) : 0;
            return bAt.compareTo(aAt);
          });
        cache
          ..clear()
          ..addEntries(byAge.take(maxCacheEntries));
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cacheKey, jsonEncode(cache));
    } catch (e) {
      debugPrint('DiscoveryService: cache write error: $e');
    }
  }

  // ── Identity normalization (mirror of the Rust side) ────────────────

  /// Separator-stripped uppercase ISBN, the comparison form of the Rust
  /// identity index (which already carries both 10/13 forms).
  static String cleanIsbn(String raw) =>
      raw.trim().replaceAll(RegExp(r'[-\s]'), '').toUpperCase();

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
