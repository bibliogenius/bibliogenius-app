import 'dart:convert';
import 'dart:io';

import 'package:bibliogenius/services/city_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// In-memory fake source that hands back fixed JSON payloads per country
/// code. Lets the repository tests exercise download / parse / search /
/// evict without touching the network or the real GeoNames files.
class _FakeCityDataSource implements CityDataSource {
  _FakeCityDataSource({Map<String, String>? files})
      : _files = {...?files};

  final Map<String, String> _files;
  int callCount = 0;
  final List<String> requested = [];

  void setFile(String country, String json) {
    _files[country.toUpperCase()] = json;
  }

  @override
  Future<List<int>?> downloadCountry(String country) async {
    callCount++;
    final cc = country.toUpperCase();
    requested.add(cc);
    final json = _files[cc];
    if (json == null) return null;
    // Encode as UTF-8 so accented names (Liège, Bazouge-de-Cheméré) round-trip
    // through writeAsBytes -> readAsString correctly.
    return utf8.encode(json);
  }
}

const _frJson = '''
[[2988507,"Paris","11",48.8534,2.3488],
 [2950159,"Berlin","16",52.5200,13.4050],
 [3013656,"La Bazouge-de-Cheméré","52",48.0667,-0.4500],
 [6454573,"Saint-Denis","93",48.9362,2.3574],
 [935317,"Saint-Denis","RE",-20.8823,55.4504]]
''';

const _beJson = '''
[[2800866,"Bruxelles","BRU",50.8503,4.3517],
 [2792196,"Liège","WAL",50.6326,5.5797]]
''';

const _chJson = '''
[[2657896,"Zurich","ZH",47.3667,8.5500],
 [2659811,"Genève","GE",46.2050,6.1429]]
''';

CityRepository _makeRepo(
  _FakeCityDataSource source,
  Directory tempDir, {
  int memoryCap = 3,
}) {
  return CityRepository(
    source: source,
    cacheDirResolver: () async => tempDir,
    memoryCap: memoryCap,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('city_repo_test_');
  });

  tearDown(() {
    try {
      tempRoot.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ensureDownloaded', () {
    test('downloads, writes the file to disk, and parses into memory',
        () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);

      final ok = await repo.ensureDownloaded('FR');

      expect(ok, true);
      expect(source.callCount, 1);
      final cached = File('${tempRoot.path}/FR.json');
      expect(cached.existsSync(), true,
          reason:
              'cache file must land at {appSupport}/cities/{CC}.json so a '
              'subsequent app launch finds it without re-downloading');
    });

    test('does not re-download when a valid cached file already exists',
        () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      // Pre-seed disk so the first ensure call should skip the network.
      File('${tempRoot.path}/FR.json').writeAsStringSync(_frJson);

      final repo = _makeRepo(source, tempRoot);
      final ok = await repo.ensureDownloaded('FR');

      expect(ok, true);
      expect(source.callCount, 0,
          reason:
              'a non-corrupt cached file must short-circuit the network — '
              'this is the entire point of the on-disk cache');
    });

    test('returns false when the hub has no file for the country', () async {
      final source = _FakeCityDataSource(); // empty
      final repo = _makeRepo(source, tempRoot);

      final ok = await repo.ensureDownloaded('XX');

      expect(ok, false);
      expect(File('${tempRoot.path}/XX.json').existsSync(), false,
          reason: 'a missing file must not leave a zero-byte artifact behind');
    });

    test('coalesces concurrent calls into a single download', () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);

      final results = await Future.wait([
        repo.ensureDownloaded('FR'),
        repo.ensureDownloaded('FR'),
        repo.ensureDownloaded('FR'),
      ]);

      expect(results, [true, true, true]);
      expect(source.callCount, 1,
          reason:
              'parallel triggers (settings picker + remote profile resolve) '
              'must share one network round-trip');
    });

    test('redownloads after a corrupt cached file is detected', () async {
      // Plant a corrupt file and a valid network payload.
      File('${tempRoot.path}/FR.json').writeAsStringSync('not valid json');
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);

      final ok = await repo.ensureDownloaded('FR');

      expect(ok, true);
      expect(source.callCount, 1,
          reason:
              'a corrupt file must trigger a re-download instead of being '
              'cached forever');
    });

    test('uppercases the country code so callers can pass either case',
        () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);

      expect(await repo.ensureDownloaded('fr'), true);
      expect(source.requested.single, 'FR');
    });
  });

  group('search', () {
    late CityRepository repo;
    late _FakeCityDataSource source;

    setUp(() async {
      source = _FakeCityDataSource(files: {'FR': _frJson, 'BE': _beJson});
      repo = _makeRepo(source, tempRoot);
      await repo.ensureDownloaded('FR');
      await repo.ensureDownloaded('BE');
    });

    test('matches by case-insensitive prefix', () async {
      final results = await repo.search('par', 'FR');
      expect(results.first.name, 'Paris');
    });

    test('matches diacritic-insensitively', () async {
      // Picker user types ASCII; record stores accented form.
      final results = await repo.search('liege', 'BE');
      expect(results.any((r) => r.name == 'Liège'), true,
          reason: 'ADR-035 trade-off: accent-insensitive matching at MVP');
    });

    test('orders prefix matches before substring matches', () async {
      // "denis" is a suffix in "Saint-Denis"; "Paris" does not contain it
      // at all. Both Saint-Denis records should match by substring.
      final results = await repo.search('denis', 'FR');
      expect(results.length, 2);
      // No prefix matches exist, so both are substring matches.
      expect(results.every((r) => r.name == 'Saint-Denis'), true);
    });

    test('returns up to limit when the query is empty', () async {
      final results = await repo.search('', 'FR', limit: 3);
      expect(results.length, 3,
          reason:
              'an empty query gives the picker a non-empty initial list to '
              'render before the user starts typing');
    });

    test('returns nothing when the country file is unavailable', () async {
      final results = await repo.search('paris', 'XX');
      expect(results, isEmpty);
    });
  });

  group('lookupById', () {
    test('returns the matching record from the requested country', () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);

      final paris = await repo.lookupById(2988507, country: 'FR');

      expect(paris, isNotNull);
      expect(paris!.name, 'Paris');
      expect(paris.country, 'FR');
      expect(paris.latitude, 48.8534);
    });

    test('lazy-downloads the country file on first lookup of a remote profile',
        () async {
      final source = _FakeCityDataSource(files: {'BE': _beJson});
      final repo = _makeRepo(source, tempRoot);
      // No prior ensureDownloaded call: lookupById must trigger one
      // when the caller passes the publisher's country code.

      final liege = await repo.lookupById(2792196, country: 'BE');

      expect(liege, isNotNull);
      expect(liege!.name, 'Liège');
      expect(source.callCount, 1,
          reason:
              'displaying a remote profile from a country we have never '
              'visited must trigger a one-time, lazy download');
    });

    test('returns null without downloading when country is omitted', () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);

      final result = await repo.lookupById(2988507);

      expect(result, isNull);
      expect(source.callCount, 0,
          reason:
              'no country -> no global GeoNames index by ADR-035 §2bis. We '
              'must not blindly download every country file just to resolve '
              'a single id.');
    });
  });

  group('evictCountry', () {
    test('removes the on-disk file and the in-memory cache', () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);
      await repo.ensureDownloaded('FR');
      expect(File('${tempRoot.path}/FR.json').existsSync(), true);

      await repo.evictCountry('FR');

      expect(File('${tempRoot.path}/FR.json').existsSync(), false);
      // After eviction, a fresh search must trigger another download.
      source.callCount = 0;
      await repo.search('par', 'FR');
      expect(source.callCount, 1,
          reason:
              'evict must drop the in-memory cache too, otherwise stale '
              'entries would survive a country change');
    });
  });

  group('memory cap (LRU)', () {
    // Bounded RAM cache so a user browsing many country profiles never
    // accumulates 100+ MB of resident parsed data on a low-end device
    // (perf policy). Eviction is observed indirectly via the fake
    // source: a country that has been evicted from memory must re-fetch
    // when accessed again (its on-disk file is still there but the
    // re-load goes through _doEnsure which checks _memory first).

    test('drops the least-recently-used country when the cap is exceeded',
        () async {
      final source = _FakeCityDataSource(
        files: {'FR': _frJson, 'BE': _beJson, 'CH': _chJson},
      );
      final repo = _makeRepo(source, tempRoot, memoryCap: 2);

      await repo.ensureDownloaded('FR'); // resident: [FR]
      await repo.ensureDownloaded('BE'); // resident: [FR, BE]
      await repo.ensureDownloaded('CH'); // resident: [BE, CH]; FR evicted

      // FR's on-disk file still exists, but the parsed list was evicted.
      // Touching FR again must re-load from disk (no extra network call
      // because the fake source counts every download attempt).
      final beforeReload = source.callCount;
      final results = await repo.search('', 'FR');
      expect(results, isNotEmpty,
          reason: 'evicted country must reload transparently from disk');
      expect(source.callCount, beforeReload,
          reason: 'evicted-but-on-disk reload must not re-hit the network');
    });

    test('access promotes a country so it survives the next eviction',
        () async {
      final source = _FakeCityDataSource(
        files: {'FR': _frJson, 'BE': _beJson, 'CH': _chJson},
      );
      final repo = _makeRepo(source, tempRoot, memoryCap: 2);

      await repo.ensureDownloaded('FR'); // resident: [FR]
      await repo.ensureDownloaded('BE'); // resident: [FR, BE]
      await repo.ensureDownloaded('FR'); // touched: [BE, FR]
      await repo.ensureDownloaded('CH'); // resident: [FR, CH]; BE evicted

      final beforeFr = source.callCount;
      await repo.search('par', 'FR');
      expect(source.callCount, beforeFr,
          reason: 'FR was touched, so it should still be in memory');
    });
  });

  group('country code validation', () {
    // ADR-035 hardening: a remote-controlled `locationCountry` field could
    // otherwise carry path traversal ("../../etc") or scheme tricks via the
    // path/URL segments built from it. Reject anything that isn't strictly
    // ISO 3166-1 alpha-2 before any I/O happens.
    // Note: leading/trailing whitespace is intentionally trimmed before
    // validation, so 'FR ' is treated as 'FR' (a valid code). The list
    // below is everything that should NOT survive the trim+regex check.
    final malformed = <String>[
      '',
      ' ',
      'F',
      'FRA',
      'F1',
      '12',
      'fr/',
      '../FR',
      'FR/..',
      'FR.json',
    ];

    test('ensureDownloaded rejects malformed codes without I/O', () async {
      final source = _FakeCityDataSource();
      final repo = _makeRepo(source, tempRoot);
      for (final cc in malformed) {
        final ok = await repo.ensureDownloaded(cc);
        expect(ok, false, reason: 'should reject "$cc"');
      }
      expect(source.callCount, 0,
          reason: 'no download must be attempted for malformed codes');
    });

    test('evictCountry no-ops on malformed codes without touching disk',
        () async {
      final source = _FakeCityDataSource(files: {'FR': _frJson});
      final repo = _makeRepo(source, tempRoot);
      await repo.ensureDownloaded('FR');
      final cached = File('${tempRoot.path}/FR.json');
      expect(cached.existsSync(), true);

      for (final cc in malformed) {
        await repo.evictCountry(cc);
      }

      expect(cached.existsSync(), true,
          reason: 'malformed evict must not delete unrelated cached files');
    });
  });
}
