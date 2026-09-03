// Guard: every translation key the "reimport to complete" flow asks for must
// exist in the catalogues, and the reasons the backend can send must all have
// a sentence to show.
//
// A missing key compiles, ships, and shows itself raw:
// `TranslationService.translate` returns the key when it finds nothing. The
// reason list is the second half of the same risk, because those strings cross
// the FFI boundary as wire names ("no_match", "ambiguous_in_file", ...) and are
// mapped to keys in Dart: a reason the Rust side gains and the mapping ignores
// would read as a wrong sentence rather than as an error.

import 'dart:io';

import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/utils/import_actions.dart';
import 'package:flutter_test/flutter_test.dart';

Set<String> _msgIds(String poPath) {
  final content = File(poPath).readAsStringSync();
  return RegExp(
    r'^msgid "([^"]+)"',
    multiLine: true,
  ).allMatches(content).map((m) => m.group(1)!).toSet();
}

void main() {
  test('every key the reimport surfaces translate exists in fr.po and en.po',
      () {
    const surfaces = [
      'lib/utils/import_actions.dart',
      'lib/screens/metadata_fill_screen.dart',
    ];
    final keys = <String>{
      // Built in main.dart, where the flash is registered.
      'flash_reimport_to_complete',
    };
    for (final path in surfaces) {
      final source = File(path).readAsStringSync();
      keys.addAll(
        RegExp(
          r"translate\(\s*\w+\s*,\s*'([a-z0-9_]+)'",
        ).allMatches(source).map((m) => m.group(1)!),
      );
      // The completeness screen reads its labels through a one-argument
      // helper rather than the full call.
      keys.addAll(
        RegExp(r"_t\(\s*'([a-z0-9_]+)'").allMatches(source).map(
              (m) => m.group(1)!,
            ),
      );
    }

    expect(
      keys,
      contains('reimport_action'),
      reason: 'the key scan matched nothing, the call shape changed',
    );

    for (final lang in ['fr', 'en']) {
      final ids = _msgIds('assets/i18n/$lang.po');
      final missing = keys.where((k) => !ids.contains(k)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason: 'missing in $lang.po: ${missing.join(', ')}',
      );
    }
  });

  test('a capped list of skipped rows says how many it does not show', () {
    // The backend caps the sample at 200 rows; the counters stay exact.
    // Announcing "431 ambiguous" above a list of 200 with no word about the
    // gap would read as a wrong count.
    frb.FrbImportCompletionReport report({
      required int noMatch,
      required int ambiguous,
      required int listed,
    }) => frb.FrbImportCompletionReport(
      batchId: 'b',
      rowsRead: 1000,
      completed: 0,
      fieldsWritten: 0,
      noMatch: noMatch,
      ambiguous: ambiguous,
      skipped: List.generate(
        listed,
        (i) => frb.FrbSkippedImportRow(title: 't$i', reason: 'no_match'),
      ),
    );

    expect(
      ImportActions.hiddenSkippedRows(
        report(noMatch: 231, ambiguous: 200, listed: 200),
      ),
      231,
    );
    expect(
      ImportActions.hiddenSkippedRows(
        report(noMatch: 3, ambiguous: 1, listed: 4),
      ),
      0,
    );
  });

  test('every reason the backend can send maps to a translated sentence', () {
    // The wire names are `SkipReason::as_str` in import_completion_service.rs.
    const reasons = ['no_match', 'ambiguous_in_file', 'ambiguous_in_library'];
    final ids = _msgIds('assets/i18n/en.po');

    final keys = reasons.map(ImportActions.skipReasonKey).toList();
    expect(
      keys.toSet(),
      hasLength(reasons.length),
      reason: 'each reason must have its own sentence, not a shared fallback',
    );
    for (final key in keys) {
      expect(ids, contains(key));
    }
    // An unknown reason must degrade to a sentence, never to a wire name.
    expect(
      ImportActions.skipReasonKey('something_new'),
      'reimport_reason_no_match',
    );
  });
}
