import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/providers/duplicate_books_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Fake FfiService: the duplicate scan and the merges are the only calls this
// provider makes, so the whole surface is three overrides. The engine itself
// is covered Rust-side (services::book_merge_service); what is at stake here
// is the screen's contract: a preview that refreshes after every merge, and a
// failure that surfaces as an error instead of an exception.
// ---------------------------------------------------------------------------

frb.FrbDuplicateBook _book(String id, String title) => frb.FrbDuplicateBook(
  id: id,
  title: title,
  isbn: '9782264024848',
  author: 'Frank Herbert',
  createdAt: '2026-01-01T00:00:00Z',
  coverUrl: null,
);

frb.FrbDuplicateGroup _group({required bool automatic, String key = 'k'}) =>
    frb.FrbDuplicateGroup(
      key: key,
      automatic: automatic,
      canonical: _book('old', 'Dune'),
      duplicates: [_book('young', 'Dune')],
    );

class _FakeFfiService extends FfiService {
  _FakeFfiService() : super.forTest();

  frb.FrbDuplicateScan scan = const frb.FrbDuplicateScan(
    automatic: [],
    proposed: [],
    booksRemovedByAutomatic: 0,
  );
  Object? scanError;
  Object? mergeError;
  int scanCalls = 0;
  int mergeAllCalls = 0;
  final List<String> mergedKeys = [];

  @override
  Future<frb.FrbDuplicateScan> scanDuplicateBooks() async {
    scanCalls++;
    if (scanError != null) throw scanError!;
    return scan;
  }

  @override
  Future<frb.FrbMergeReport> mergeDuplicateBooks() async {
    mergeAllCalls++;
    if (mergeError != null) throw mergeError!;
    return const frb.FrbMergeReport(
      groupsMerged: 1,
      booksRemoved: 1,
      copiesCollapsed: 1,
      coversRecovered: 0,
    );
  }

  @override
  Future<frb.FrbMergeReport> mergeDuplicateGroup(String key) async {
    mergedKeys.add(key);
    if (mergeError != null) throw mergeError!;
    return const frb.FrbMergeReport(
      groupsMerged: 1,
      booksRemoved: 1,
      copiesCollapsed: 0,
      coversRecovered: 0,
    );
  }
}

void main() {
  late _FakeFfiService ffi;
  late DuplicateBooksProvider provider;

  setUp(() {
    ffi = _FakeFfiService();
    provider = DuplicateBooksProvider(ffi: ffi);
  });

  test('an empty scan reports nothing to repair', () async {
    await provider.refresh();

    expect(provider.hasAnything, isFalse);
    expect(provider.booksRemovedByAutomatic, 0);
    expect(provider.error, isNull);
  });

  test('the two families stay separate', () async {
    ffi.scan = frb.FrbDuplicateScan(
      automatic: [_group(automatic: true, key: 'isbn:9782264024848')],
      proposed: [_group(automatic: false, key: 'ta:dune|herbert|1965')],
      booksRemovedByAutomatic: 1,
    );

    await provider.refresh();

    expect(provider.automatic.single.automatic, isTrue);
    expect(provider.proposed.single.automatic, isFalse);
    expect(provider.hasAnything, isTrue);
  });

  test('a failed scan surfaces an error instead of throwing', () async {
    ffi.scanError = Exception('no database');

    await provider.refresh();

    expect(provider.error, isNotNull);
    expect(provider.scan, isNull);
    expect(provider.isScanning, isFalse);
  });

  test('merging refreshes the preview so no stale survivor is shown', () async {
    ffi.scan = frb.FrbDuplicateScan(
      automatic: [_group(automatic: true)],
      proposed: const [],
      booksRemovedByAutomatic: 1,
    );
    await provider.refresh();
    expect(ffi.scanCalls, 1);

    // The library is repaired underneath the provider.
    ffi.scan = const frb.FrbDuplicateScan(
      automatic: [],
      proposed: [],
      booksRemovedByAutomatic: 0,
    );
    final ok = await provider.mergeAutomatic();

    expect(ok, isTrue);
    expect(ffi.mergeAllCalls, 1);
    expect(ffi.scanCalls, 2, reason: 'the preview is re-read after a merge');
    expect(provider.hasAnything, isFalse);
    expect(provider.lastReport?.booksRemoved, 1);
    expect(provider.lastReport?.copiesCollapsed, 1);
  });

  test('a proposed group merges by its own key', () async {
    await provider.mergeGroup('ta:dune|herbert|1965');

    expect(ffi.mergedKeys, ['ta:dune|herbert|1965']);
  });

  test('a failed merge reports failure and keeps the screen usable', () async {
    ffi.mergeError = Exception('aborted');

    final ok = await provider.mergeAutomatic();

    expect(ok, isFalse);
    expect(provider.error, isNotNull);
    expect(provider.isMerging, isFalse);
    expect(provider.lastReport, isNull);
  });
}
