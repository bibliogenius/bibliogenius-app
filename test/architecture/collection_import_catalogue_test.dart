// Guard: every translation key the collection import surfaces ask for must
// exist in the catalogues.
//
// A key that is absent compiles, ships, and shows itself raw to the reader:
// the shared-list import dropdown asked for `status_to_read`, a key no
// catalogue ever held, so the option read "status_to_read" in every language
// while the two options beside it were translated. Nothing failed, because
// `TranslationService.translate` returns the key when it finds nothing.
//
// Scoped to the import/export surfaces rather than the whole app: this is the
// area the miss was found in, and a whole-app scan would report keys built at
// runtime that a textual scan cannot resolve.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _msgIds(String poPath) {
  final content = File(poPath).readAsStringSync();
  return RegExp(
    r'^msgid "([^"]+)"',
    multiLine: true,
  ).allMatches(content).map((m) => m.group(1)!).toSet();
}

void main() {
  const surfaces = [
    'lib/screens/collection/import_shared_list_screen.dart',
    'lib/screens/collection/import_curated_list_screen.dart',
    'lib/screens/collection/collection_detail_screen.dart',
    'lib/widgets/curated_import_dialog.dart',
  ];

  test('every key the import surfaces translate exists in fr.po and en.po', () {
    final keys = <String>{};
    for (final path in surfaces) {
      final source = File(path).readAsStringSync();
      // Only literal keys: an interpolated one cannot be resolved here, and
      // guessing at it would make this guard lie in both directions.
      keys.addAll(
        RegExp(
          r"translate\(\s*\w+\s*,\s*'([a-z0-9_]+)'",
        ).allMatches(source).map((m) => m.group(1)!),
      );
    }

    expect(
      keys,
      isNotEmpty,
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
}
