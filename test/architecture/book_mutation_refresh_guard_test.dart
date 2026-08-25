// Guard: every UI-layer site that deletes a book must ping
// [BookRefreshNotifier].
//
// The notifier is the ONLY invalidation channel of the catalogue-derived
// caches (recommendations, favorites). Popping a route with `true` refreshes
// the list the user lands back on and nothing else, so a delete that skipped
// the notifier left the book in the "To discover" strip, tappable through to
// its edit form.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UI layers only: `data/` and `services/` hold the plumbing the sites below
/// call into, not the mutation sites themselves.
const _scanned = ['lib/screens', 'lib/widgets', 'lib/utils', 'lib/providers'];

void main() {
  test('every UI site deleting a book pings BookRefreshNotifier', () {
    final offenders = <String>[];
    var sites = 0;

    for (final dir in _scanned) {
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        final source = file.readAsStringSync();
        final deletes = RegExp(r'\.deleteBook\(').allMatches(source);
        if (deletes.isEmpty) continue;
        sites += deletes.length;
        // Anchored on the CALL, not on the type name: `BookRefreshNotifier`
        // also appears where a helper captures the notifier before an await,
        // and those capture lines belong to other functions entirely, so a
        // scan for the type reports a ping that is not one.
        if (!source.contains('BookRefreshNotifier')) {
          offenders.add('${file.path} (no notifier at all)');
          continue;
        }
        // The ping must come AFTER the delete, not merely somewhere in the
        // file: the edit screen pinged on save and stayed silent on delete,
        // which a whole-file scan reads as compliant.
        final pings = RegExp(
          r'\.refresh\(\)',
        ).allMatches(source).map((m) => m.start).toList();
        for (final delete in deletes) {
          if (pings.any((at) => at > delete.start)) continue;
          offenders.add('${file.path} (offset ${delete.start})');
        }
      }
    }

    expect(
      sites,
      greaterThanOrEqualTo(3),
      reason:
          'the scan matched fewer delete sites than the ones known to exist '
          '(edit screen, details screen, backup reset): the call shape or the '
          'folder layout changed and this guard stopped proving anything',
    );
    expect(offenders, isEmpty);
  });
}
