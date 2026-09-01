import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/providers/metadata_fill_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Fake FfiService: what is at stake here is the completeness screen's contract
// around a *scoped* run (ADR-041, scoped runs). The selection itself is covered
// Rust-side; this pins the three things the screen depends on: the announced
// backlog comes from the backend count for the active scope (never from the
// capped overview list), a run carries that scope, and a late answer for a
// scope the user has left never lands on the wrong filter.
// ---------------------------------------------------------------------------

class _FakeFfiService extends FfiService {
  _FakeFfiService({this.counts = const {}, this.progress, this.stats})
    : super.forTest();

  /// Backend answer to `metadataFillProcessable`, keyed by scope.
  final Map<String?, int> counts;
  final frb.FrbFillProgress? progress;

  /// Mutable: a test can let the library change under the provider.
  frb.FrbCompletenessStats? stats;

  /// Filters each overview-list load was called with.
  final List<({String? missingField, bool noIsbnOnly})> listCalls = [];

  /// Scope each start was called with, in order.
  final List<String?> startedScopes = [];

  /// Gate to hold an in-flight count answer, for the stale-answer test.
  Completer<int>? pending;

  @override
  Future<int> metadataFillProcessable({String? missingField}) async {
    final gate = pending;
    if (gate != null) return gate.future;
    return counts[missingField] ?? 0;
  }

  @override
  Future<String> metadataFillStart({
    List<String>? languages,
    int? lotLimit,
    String? missingField,
  }) async {
    startedScopes.add(missingField);
    return 'batch-1';
  }

  @override
  Future<frb.FrbFillProgress?> metadataFillProgress() async => progress;

  @override
  Future<List<frb.FrbIncompleteBookDetail>> metadataFillIncomplete({
    int? limit,
    String? missingField,
    bool noIsbnOnly = false,
  }) async {
    listCalls.add((missingField: missingField, noIsbnOnly: noIsbnOnly));
    return const [];
  }

  @override
  Future<frb.FrbCompletenessStats> metadataFillStats() async =>
      stats ??
      const frb.FrbCompletenessStats(
        ownedTotal: 0,
        complete: 0,
        incomplete: 0,
        noIsbn: 0,
        emptyFields: 0,
        gaps: [],
      );
}

frb.FrbFillProgress _progress({String? missingField}) => frb.FrbFillProgress(
  batchId: 'batch-1',
  status: 'interrupted',
  total: 40,
  done: 12,
  filled: 10,
  skipped: 2,
  errored: 0,
  currentTitle: null,
  missingField: missingField,
);

void main() {
  test(
    'a field gap and its percentage come from the stat, not the list',
    () async {
      final ffi = _FakeFfiService(
        stats: const frb.FrbCompletenessStats(
          ownedTotal: 100,
          complete: 55,
          incomplete: 45,
          noIsbn: 5,
          emptyFields: 52,
          gaps: [
            frb.FrbFieldGap(field: 'summary', missing: 30),
            frb.FrbFieldGap(field: 'publisher', missing: 22),
          ],
        ),
      );
      final provider = MetadataFillProvider(ffi: ffi);
      addTearDown(provider.dispose);

      await provider.loadStats();
      expect(provider.fieldGap('summary'), 30);
      expect(provider.fieldGap('publisher'), 22);
      expect(provider.fieldGap('cover_url'), 0, reason: 'absent from the stat');
      // 70 of the 100 owned books already have a summary.
      expect(provider.fieldCompletionPercent('summary'), 70);
      // The library-wide teaser is unchanged by any of this.
      expect(provider.completionPercent, 55);
    },
  );

  test('a filter announces the backend count for that field', () async {
    final ffi = _FakeFfiService(counts: {'summary': 37, 'publisher': 4});
    final provider = MetadataFillProvider(ffi: ffi);
    addTearDown(provider.dispose);

    await provider.setFilter('summary');
    expect(provider.scopeField, 'summary');
    expect(provider.scopedProcessableCount, 37);

    await provider.setFilter('publisher');
    expect(provider.scopedProcessableCount, 4);
  });

  test('dropping the filter falls back to the whole backlog', () async {
    final ffi = _FakeFfiService(counts: {'summary': 37});
    final provider = MetadataFillProvider(ffi: ffi);
    addTearDown(provider.dispose);

    await provider.setFilter('summary');
    await provider.setFilter(null);
    // No stats loaded in this test, so the whole backlog reads as 0 - the point
    // is that it is no longer the scoped count.
    expect(provider.scopeField, isNull);
    expect(provider.filter, isNull);
    expect(provider.scopedProcessableCount, 0);
  });

  test(
    'the list is reloaded from the backend with the filter applied',
    () async {
      final ffi = _FakeFfiService(counts: {'summary': 37});
      final provider = MetadataFillProvider(ffi: ffi);
      addTearDown(provider.dispose);

      await provider.setFilter('summary');
      expect(ffi.listCalls.last.missingField, 'summary');
      expect(ffi.listCalls.last.noIsbnOnly, isFalse);
    },
  );

  test('the no-ISBN filter narrows the list but never scopes a run', () async {
    final ffi = _FakeFfiService();
    final provider = MetadataFillProvider(ffi: ffi);
    addTearDown(provider.dispose);

    await provider.setFilter(MetadataFillProvider.noIsbnFilter);
    expect(ffi.listCalls.last.noIsbnOnly, isTrue);
    expect(ffi.listCalls.last.missingField, isNull);
    expect(provider.scopeField, isNull, reason: 'no ISBN, nothing to look up');

    await provider.start(const ['fr']);
    expect(ffi.startedScopes, [null]);
  });

  test('a filter whose slice has emptied is dropped', () async {
    final ffi = _FakeFfiService(
      counts: {'summary': 3},
      stats: const frb.FrbCompletenessStats(
        ownedTotal: 10,
        complete: 7,
        incomplete: 3,
        noIsbn: 0,
        emptyFields: 3,
        gaps: [frb.FrbFieldGap(field: 'summary', missing: 3)],
      ),
    );
    final provider = MetadataFillProvider(ffi: ffi);
    addTearDown(provider.dispose);

    await provider.loadStats();
    await provider.setFilter('summary');
    expect(provider.filter, 'summary');

    // The run fills the last three summaries.
    ffi.stats = const frb.FrbCompletenessStats(
      ownedTotal: 10,
      complete: 10,
      incomplete: 0,
      noIsbn: 0,
      emptyFields: 0,
      gaps: [frb.FrbFieldGap(field: 'summary', missing: 0)],
    );
    await provider.loadStats();
    expect(
      provider.filter,
      isNull,
      reason: 'its pill is gone, the filter must not strand the user',
    );
  });

  test('a fresh run is started with the active scope', () async {
    final ffi = _FakeFfiService(counts: {'summary': 37});
    final provider = MetadataFillProvider(ffi: ffi);
    addTearDown(provider.dispose);

    await provider.setFilter('summary');
    await provider.start(const ['fr'], lotLimit: 20);
    expect(ffi.startedScopes, ['summary']);
  });

  test('a late count for a scope the user has left is dropped', () async {
    final ffi = _FakeFfiService(counts: {'publisher': 4});
    final provider = MetadataFillProvider(ffi: ffi);
    addTearDown(provider.dispose);

    final gate = Completer<int>();
    ffi.pending = gate;
    final inFlight = provider.setFilter('summary');
    // The user moves to another filter before that answer lands.
    ffi.pending = null;
    await provider.setFilter('publisher');
    gate.complete(37);
    await inFlight;

    expect(provider.scopeField, 'publisher');
    expect(
      provider.scopedProcessableCount,
      4,
      reason: 'the stale count for "summary" must not be shown here',
    );
  });

  test(
    'the run scope is read from the run itself, not from the filter',
    () async {
      final ffi = _FakeFfiService(
        counts: {'summary': 37},
        progress: _progress(missingField: 'publisher'),
      );
      final provider = MetadataFillProvider(ffi: ffi);
      addTearDown(provider.dispose);

      await provider.refreshProgress();
      await provider.setFilter('summary');
      expect(provider.runScopeField, 'publisher');
      expect(provider.isResumable, isTrue);
    },
  );
}
