// Guard: the search for missing covers has one way in.
//
// `CoverEnrichmentCoordinator` is what keeps two sweeps from running at once
// and what publishes the covers a sweep finds. A call site that reaches
// `enrichMissingCovers()` directly gets neither: the sweep it starts can
// overlap another, and its results stay out of the published catalog until
// something else pushes it. Nothing fails when that happens, the directory
// just shows fewer covers, so the wiring is checked here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only the coordinator wiring starts a cover sweep', () {
    // The declarations and pass-through wrappers of the call itself.
    const wrappers = {
      'lib/services/api_service.dart',
      'lib/services/ffi_service.dart',
    };
    final callers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.readAsStringSync().contains('enrichMissingCovers'))
        // Windows lists these paths with backslashes.
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'))
        .where((p) => !p.startsWith('lib/src/rust/'))
        .where((p) => !wrappers.contains(p))
        .toList();

    expect(callers, ['lib/main.dart']);

    final main = File('lib/main.dart').readAsStringSync();
    expect(
      RegExp(r'enrichMissingCovers').allMatches(main),
      hasLength(1),
      reason: 'handed to the coordinator once, never called on the side',
    );
    expect(main, contains('enrich: apiService.enrichMissingCovers'));
  });

  test('a successful import asks for a cover sweep', () {
    final source = File('lib/utils/import_actions.dart').readAsStringSync();
    final branch = RegExp(
      r'if \(imported > 0\) \{(.*?)\n      \}',
      dotAll: true,
    ).firstMatch(source);

    expect(branch, isNotNull, reason: 'the import outcome branch moved');
    expect(branch!.group(1), contains('coverEnrichment.run()'));
    expect(branch.group(1), contains('hubDirectory.markCatalogDirty()'));
  });
}
