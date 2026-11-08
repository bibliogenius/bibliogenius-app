// Guard: a genre, in any catalogue, makes a shelf name the reader could have
// typed.
//
// Genres and curated lists create their shelves from these labels, without the
// name field that holds a typed name to the limit. A label over the limit
// would give a shelf its own Edit dialog then refuses to save as it stands.

import 'dart:io';

import 'package:bibliogenius/utils/book_genres.dart';
import 'package:bibliogenius/utils/shelf_name_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// The msgstr of every key in [poPath], continuation lines joined.
Map<String, String> _entries(String poPath) {
  final content = File(poPath).readAsStringSync();
  return {
    for (final m in RegExp(
      r'^msgid "((?:[^"\\]|\\.)*)"\s*\nmsgstr ((?:"(?:[^"\\]|\\.)*"\s*\n?)+)',
      multiLine: true,
    ).allMatches(content))
      m.group(1)!: RegExp(
        r'"((?:[^"\\]|\\.)*)"',
      ).allMatches(m.group(2)!).map((s) => s.group(1)!).join(),
  };
}

void main() {
  test('every genre label fits a shelf name, in every catalogue', () {
    final keys = [genreRootKey, ...allBookGenres.map((g) => g.key)];
    final catalogues = Directory('assets/i18n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.po'))
        .toList();
    expect(catalogues, isNotEmpty);

    final tooLong = <String>[];
    for (final po in catalogues) {
      final entries = _entries(po.path);
      for (final key in keys) {
        final label = entries[key];
        if (label != null && shelfNameTooLong(label)) {
          tooLong.add('${po.path}: $key "$label"');
        }
      }
    }
    expect(tooLong, isEmpty, reason: tooLong.join('\n'));
  });
}
