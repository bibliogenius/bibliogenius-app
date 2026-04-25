// City lookup service for the public directory location picker (ADR-035).
//
// City data lives as static files served by the hub (one gzipped JSON file
// per ISO 3166-1 alpha-2 country code, derived from GeoNames feature class
// P). The Flutter app ships with zero city data: each country file is
// downloaded on demand the first time the user picks or views it, then
// cached locally under `{appSupport}/cities/{CC}.json` for the lifetime
// of the install.
//
// Search is intentionally local: a hub typeahead would receive every
// keystroke, leaking which cities each user is considering even if they
// never opt in to share one. Scanning the parsed list in memory stays
// well under 5 ms for the largest country files at MVP.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api_service.dart';

/// One populated place from the GeoNames-derived country file.
@immutable
class CityRecord {
  final int id;

  /// ISO 3166-1 alpha-2 country code (implicit in the source file name,
  /// repeated here so callers can keep records around without losing
  /// provenance).
  final String country;
  final String name;

  /// GeoNames admin1 code (e.g. "11" for Paris in France). Useful for
  /// disambiguating namesakes in the picker (`Saint-Denis (93)` vs
  /// `Saint-Denis (974)`).
  final String admin1;
  final double latitude;
  final double longitude;

  const CityRecord({
    required this.id,
    required this.country,
    required this.name,
    required this.admin1,
    required this.latitude,
    required this.longitude,
  });
}

/// Source of raw country file bytes. The production implementation hits
/// the hub static endpoint; tests inject a local fake.
abstract class CityDataSource {
  /// Returns the decompressed JSON bytes for [country], or null when the
  /// hub has no file for that country code (e.g. typo, or the build script
  /// has not run yet for that ISO code). Implementations MUST NOT throw
  /// on network errors: callers treat null as "data unavailable for now,
  /// try again later".
  Future<List<int>?> downloadCountry(String country);
}

/// Default data source: fetches `{hub}/static/cities/{CC}.json.gz` and
/// returns the decompressed payload.
class HubCityDataSource implements CityDataSource {
  HubCityDataSource({String? baseUrl, HttpClient? client})
      : _baseUrl = baseUrl,
        _client = client ?? HttpClient();

  final String? _baseUrl;
  final HttpClient _client;

  String get _resolvedBaseUrl => _baseUrl ?? ApiService.hubUrl;

  @override
  Future<List<int>?> downloadCountry(String country) async {
    final cc = country.toUpperCase();
    final uri = Uri.parse('$_resolvedBaseUrl/static/cities/$cc.json.gz');
    try {
      final req = await _client.getUrl(uri);
      // Tell the server we accept gzip even though we always download the
      // .gz file directly: this lets a future CDN serve a pre-compressed
      // variant without forcing a content-encoding handshake.
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'gzip');
      final res = await req.close();
      if (res.statusCode != 200) {
        debugPrint(
          'CityRepository: $cc download returned HTTP ${res.statusCode}',
        );
        return null;
      }
      final bytes = await consolidateBytes(res);
      // Some HTTP stacks transparently decompress gzip; if so the bytes
      // already look like JSON. Detect the gzip magic to decide.
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        return gzip.decode(bytes);
      }
      return bytes;
    } catch (e) {
      debugPrint('CityRepository: $cc download failed: $e');
      return null;
    }
  }

  /// Visible for reuse in tests that need to force-collect a stream.
  static Future<List<int>> consolidateBytes(HttpClientResponse res) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }
}

/// Cache + lookup facade for city data. Singleton in production
/// (`CityRepository.shared`) so providers and screens share the same
/// in-memory cache.
class CityRepository {
  CityRepository({
    CityDataSource? source,
    Future<Directory> Function()? cacheDirResolver,
  })  : _source = source ?? HubCityDataSource(),
        _cacheDirResolver = cacheDirResolver ?? _defaultCacheDir;

  final CityDataSource _source;
  final Future<Directory> Function() _cacheDirResolver;

  /// Country code -> parsed records. Populated lazily from disk on the
  /// first lookup, kept in memory for subsequent searches so a typeahead
  /// over 50k cities stays instantaneous.
  final Map<String, List<CityRecord>> _memory = {};

  /// In-flight downloads, keyed by country code. Lets concurrent
  /// `ensureDownloaded` callers (settings picker + remote profile
  /// resolution firing in parallel) share the same network round-trip.
  final Map<String, Future<bool>> _inFlight = {};

  static CityRepository? _shared;

  /// App-wide singleton. Tests should use a fresh instance instead.
  // ignore: prefer_constructors_over_static_methods
  static CityRepository shared() => _shared ??= CityRepository();

  @visibleForTesting
  static void resetShared() => _shared = null;

  static Future<Directory> _defaultCacheDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/cities');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<File> _fileFor(String country) async {
    final dir = await _cacheDirResolver();
    return File('${dir.path}/${country.toUpperCase()}.json');
  }

  /// Ensure the country file is on disk and parsed in memory.
  ///
  /// Idempotent and safe to call from any UI lifecycle (app start, country
  /// change, picker open, profile card render). Returns true once data is
  /// available, false if the hub has no file or the network is down — the
  /// caller is expected to retry on the next user-driven trigger rather
  /// than block on this.
  Future<bool> ensureDownloaded(String country) async {
    final cc = country.trim().toUpperCase();
    if (cc.isEmpty) return false;
    if (_memory.containsKey(cc)) return true;

    final pending = _inFlight[cc];
    if (pending != null) return pending;

    final future = _doEnsure(cc);
    _inFlight[cc] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(cc);
    }
  }

  Future<bool> _doEnsure(String cc) async {
    final file = await _fileFor(cc);
    if (file.existsSync()) {
      try {
        await _loadFromFile(cc, file);
        return true;
      } catch (e) {
        debugPrint('CityRepository: $cc cached file corrupt, re-downloading: $e');
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    final bytes = await _source.downloadCountry(cc);
    if (bytes == null) return false;
    try {
      await file.writeAsBytes(bytes, flush: true);
      await _loadFromFile(cc, file);
      return true;
    } catch (e) {
      debugPrint('CityRepository: $cc parse/write failed: $e');
      return false;
    }
  }

  Future<void> _loadFromFile(String cc, File file) async {
    final raw = await file.readAsString();
    final parsed = jsonDecode(raw);
    if (parsed is! List) {
      throw const FormatException('city file root is not a JSON array');
    }
    final records = <CityRecord>[];
    for (final row in parsed) {
      if (row is! List || row.length < 5) continue;
      records.add(CityRecord(
        id: (row[0] as num).toInt(),
        country: cc,
        name: row[1] as String,
        admin1: row[2] as String,
        latitude: (row[3] as num).toDouble(),
        longitude: (row[4] as num).toDouble(),
      ));
    }
    _memory[cc] = records;
  }

  /// Search [country]'s city list for [query]. Diacritic-insensitive prefix
  /// match, with substring matches appended after for typeahead UX. Returns
  /// at most [limit] results; an empty query yields the first [limit] cities
  /// in source order so the picker has something to show before the user
  /// types.
  Future<List<CityRecord>> search(
    String query,
    String country, {
    int limit = 20,
  }) async {
    final ok = await ensureDownloaded(country);
    if (!ok) return const [];
    final records = _memory[country.toUpperCase()] ?? const <CityRecord>[];
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return records.take(limit).toList();
    }
    final needle = _fold(trimmed);
    final prefix = <CityRecord>[];
    final substring = <CityRecord>[];
    for (final r in records) {
      final hay = _fold(r.name);
      if (hay.startsWith(needle)) {
        prefix.add(r);
      } else if (hay.contains(needle)) {
        substring.add(r);
      }
      if (prefix.length >= limit) break;
    }
    if (prefix.length >= limit) return prefix.take(limit).toList();
    return [...prefix, ...substring].take(limit).toList();
  }

  /// Resolve a record by GeoNames id. When [country] is known (e.g. the
  /// remote profile carries a `locationCountry`), the matching country
  /// file is downloaded if missing. When omitted, only already-loaded
  /// countries are scanned — there is no global GeoNames index, by design
  /// (ADR-035 §2bis: hub serves no city search endpoint).
  Future<CityRecord?> lookupById(int id, {String? country}) async {
    if (country != null && country.isNotEmpty) {
      final cc = country.toUpperCase();
      await ensureDownloaded(cc);
      final list = _memory[cc];
      if (list != null) {
        for (final r in list) {
          if (r.id == id) return r;
        }
      }
      return null;
    }
    for (final list in _memory.values) {
      for (final r in list) {
        if (r.id == id) return r;
      }
    }
    return null;
  }

  /// Drop the cached country file from disk and memory. Used when the
  /// user changes their `location_country` so we do not keep an unused
  /// 250 KB blob around.
  Future<void> evictCountry(String country) async {
    final cc = country.trim().toUpperCase();
    _memory.remove(cc);
    try {
      final file = await _fileFor(cc);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('CityRepository: $cc evict failed: $e');
    }
  }

  /// Diacritic-insensitive lowercase fold. Covers the Latin accents that
  /// matter for FR / BE / CH / IT / ES / DE / PT / PL pickers; non-Latin
  /// scripts pass through unchanged so the user can still match by
  /// canonical GeoNames spelling.
  static String _fold(String input) {
    final lower = input.toLowerCase();
    final buf = StringBuffer();
    for (final code in lower.codeUnits) {
      buf.writeCharCode(_foldChar(code));
    }
    return buf.toString();
  }

  static int _foldChar(int code) {
    // Latin-1 supplement + Latin Extended-A common accents.
    if (code >= 0x00C0 && code <= 0x017F) {
      const map = <int, int>{
        0xE0: 0x61, 0xE1: 0x61, 0xE2: 0x61, 0xE3: 0x61, 0xE4: 0x61, 0xE5: 0x61,
        0xE6: 0x61,
        0xE7: 0x63,
        0xE8: 0x65, 0xE9: 0x65, 0xEA: 0x65, 0xEB: 0x65,
        0xEC: 0x69, 0xED: 0x69, 0xEE: 0x69, 0xEF: 0x69,
        0xF1: 0x6E,
        0xF2: 0x6F, 0xF3: 0x6F, 0xF4: 0x6F, 0xF5: 0x6F, 0xF6: 0x6F, 0xF8: 0x6F,
        0xF9: 0x75, 0xFA: 0x75, 0xFB: 0x75, 0xFC: 0x75,
        0xFD: 0x79, 0xFF: 0x79,
        0x153: 0x6F, // œ -> o
        0x161: 0x73, // š
        0x17E: 0x7A, // ž
      };
      final mapped = map[code];
      if (mapped != null) return mapped;
    }
    return code;
  }
}
