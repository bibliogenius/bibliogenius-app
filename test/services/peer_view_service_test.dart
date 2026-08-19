import 'dart:io';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/services/peer_view_service.dart';
import 'package:flutter_test/flutter_test.dart';

Book _book({String? coverUrl}) =>
    Book(title: 'Le Horla', author: 'Maupassant', coverUrl: coverUrl);

void main() {
  group('cover resolution mirrors what a peer does', () {
    const snapshotBase = 'http://127.0.0.1:8000';

    test('a relative cover path is resolved against the served base', () {
      final snapshot = PeerViewSnapshot(books: const [], baseUrl: snapshotBase);

      expect(
        snapshot.coverUrlFor(_book(coverUrl: '/api/books/abc/cover?v=7')),
        '$snapshotBase/api/books/abc/cover?v=7',
      );
    });

    test('an absolute cover URL is left untouched', () {
      final snapshot = PeerViewSnapshot(books: const [], baseUrl: snapshotBase);

      expect(
        snapshot.coverUrlFor(
          _book(coverUrl: 'https://covers.openlibrary.org/b/id/1.jpg'),
        ),
        'https://covers.openlibrary.org/b/id/1.jpg',
      );
    });

    test('a book the peer receives without a cover stays without one', () {
      final snapshot = PeerViewSnapshot(books: const [], baseUrl: snapshotBase);

      expect(snapshot.coverUrlFor(_book()), isNull);
    });
  });

  // The preview is only worth showing if it cannot diverge from the real
  // publication. Two ways it could: authenticating (which flips the Rust
  // handler into owner mode) or re-deriving the privacy rule in Dart. Both are
  // guarded here at the source level, because either regression would be
  // invisible in behaviour tests run against an owner-empty catalogue.
  group('the peer view cannot drift from what is published', () {
    late String serviceSource;
    late String screenSource;

    setUpAll(() {
      final lib = _libDirFromCwd();
      // Comments are stripped: both files document the Rust-side rule they
      // deliberately do NOT reimplement, and those explanations must not read
      // as violations.
      serviceSource = _strippedCode(
        File('${lib.path}/services/peer_view_service.dart'),
      );
      screenSource = _strippedCode(
        File('${lib.path}/screens/peer_view_screen.dart'),
      );
    });

    test('the fetch sends no owner credential', () {
      expect(
        serviceSource.toLowerCase(),
        isNot(contains('authorization')),
        reason:
            'an owner token would make the handler return private books and '
            'personal annotations, and the preview would stop being the peer view',
      );
      expect(serviceSource, isNot(contains('Bearer')));
    });

    test('neither the service nor the screen re-filters privacy in Dart', () {
      for (final source in [serviceSource, screenSource]) {
        expect(
          source,
          isNot(contains('.private')),
          reason:
              'the Rust handler owns the privacy rule; a second copy in Dart '
              'would drift and lie about what peers receive',
        );
        expect(source, isNot(contains('redact')));
      }
    });

    test('the fetch keeps the peer request shape: bare GET /api/books', () {
      expect(
        serviceSource,
        contains("get<Map<String, dynamic>>('/api/books')"),
      );
      expect(
        serviceSource,
        isNot(contains('owned_only')),
        reason:
            'peer catalogue sync issues /api/books with no query parameters '
            '(api/peer/sync.rs); adding one would preview a different response',
      );
    });
  });
}

/// Source of [file] without its comment lines, so the guards below match
/// executable code only. Whole lines only: cutting at the first `//` would also
/// truncate string literals holding a URL.
String _strippedCode(File file) => file
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

/// Resolves the project's `lib/` directory regardless of where the test runner
/// anchors the working directory.
Directory _libDirFromCwd() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    final candidate = Directory('${dir.path}/lib');
    if (candidate.existsSync() &&
        File('${dir.path}/pubspec.yaml').existsSync()) {
      return candidate;
    }
    dir = dir.parent;
  }
  return Directory('${Directory.current.path}/lib');
}
