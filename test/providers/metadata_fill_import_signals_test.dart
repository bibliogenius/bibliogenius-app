import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/providers/metadata_fill_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// The banner that offers "reimport to complete" (ADR-071 D9) speaks only when
// two independent signals agree: most of the library has no ISBN, AND a large
// group of those books was added on the same day. A ratio alone cannot tell a
// botched import from a shelf typed in by hand, and telling someone their
// import failed when it never happened is the failure these tests guard.
// ---------------------------------------------------------------------------

class _FakeFfiService extends FfiService {
  _FakeFfiService({required this.stats, this.cluster}) : super.forTest();

  /// Mutable: a test can let the library fill up under the provider.
  frb.FrbCompletenessStats stats;
  frb.FrbNoIsbnCluster? cluster;
  int statsCalls = 0;
  int clusterCalls = 0;

  @override
  Future<frb.FrbCompletenessStats> metadataFillStats() async {
    statsCalls++;
    return stats;
  }

  @override
  Future<frb.FrbNoIsbnCluster?> importNoIsbnCluster() async {
    clusterCalls++;
    return cluster;
  }
}

frb.FrbCompletenessStats _stats({required int owned, required int noIsbn}) =>
    frb.FrbCompletenessStats(
      ownedTotal: owned,
      complete: 0,
      incomplete: noIsbn,
      noIsbn: noIsbn,
      emptyFields: 0,
      gaps: const [],
    );

Future<MetadataFillProvider> loaded({
  required int owned,
  required int noIsbn,
  int? clusterCount,
}) async {
  final provider = MetadataFillProvider(
    ffi: _FakeFfiService(
      stats: _stats(owned: owned, noIsbn: noIsbn),
      cluster: clusterCount == null
          ? null
          : frb.FrbNoIsbnCluster(day: '2026-09-03', count: clusterCount),
    ),
  );
  await provider.loadImportSignals();
  return provider;
}

void main() {
  test('the library that motivated this: 2861 books, no ISBN, one day',
      () async {
    final provider = await loaded(
      owned: 2861,
      noIsbn: 2861,
      clusterCount: 2861,
    );
    expect(provider.suggestsFailedImport, isTrue);
  });

  test('a shelf typed in over the years is never accused', () async {
    // Same ratio, no cluster: the books were added a few at a time.
    final provider = await loaded(owned: 300, noIsbn: 300, clusterCount: 12);
    expect(provider.suggestsFailedImport, isFalse);
  });

  test('a library that mostly has its ISBNs stays quiet', () async {
    // A big same-day cluster (a real import) but only a fifth of the shelf
    // lacks an ISBN: nothing to repair in bulk.
    final provider = await loaded(owned: 1000, noIsbn: 200, clusterCount: 200);
    expect(provider.suggestsFailedImport, isFalse);
  });

  test('a small library is below the floor whatever its ratio', () async {
    final provider = await loaded(owned: 40, noIsbn: 40, clusterCount: 40);
    expect(provider.suggestsFailedImport, isFalse);
  });

  test('exactly at both thresholds, the banner speaks', () async {
    final provider = await loaded(owned: 50, noIsbn: 40, clusterCount: 50);
    expect(provider.suggestsFailedImport, isTrue);
  });

  test('one book under the ratio, it does not', () async {
    final provider = await loaded(owned: 50, noIsbn: 39, clusterCount: 50);
    expect(provider.suggestsFailedImport, isFalse);
  });

  test('a library with no cluster at all leaves the banner silent', () async {
    final provider = await loaded(owned: 2861, noIsbn: 2861);
    expect(provider.suggestsFailedImport, isFalse);
  });

  test('an import in the same session is seen, not left to the next launch',
      () async {
    // At startup the signals measured an empty library. The import that
    // follows is exactly what the banner exists for: re-reading only the
    // missing half would keep it blind until the app is relaunched.
    final ffi = _FakeFfiService(
      stats: _stats(owned: 0, noIsbn: 0),
      cluster: null,
    );
    final provider = MetadataFillProvider(ffi: ffi);
    await provider.loadImportSignals();
    expect(provider.suggestsFailedImport, isFalse);

    ffi
      ..stats = _stats(owned: 568, noIsbn: 568)
      ..cluster = const frb.FrbNoIsbnCluster(day: '2026-09-03', count: 568);
    await provider.loadImportSignals();

    expect(provider.suggestsFailedImport, isTrue);
    expect(ffi.statsCalls, 2, reason: 'the stale count must be re-read too');
    expect(ffi.clusterCalls, 2);
  });
}
