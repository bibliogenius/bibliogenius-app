import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/screens/peer_book_list_screen.dart';

void main() {
  group('shouldReplaceDisplayedBooks (post-delta cache reload guard)', () {
    test('empty cache must NOT wipe a hub-fallback display', () {
      // Regression: Mac showed 513 hub-catalog books for an offline paired
      // peer, then the background delta sync (ADR-029) reported applied and
      // the empty peer_books reload blanked the screen after ~1 second
      // ("Aucun livre trouve" / "Jamais synchronise").
      expect(
        shouldReplaceDisplayedBooks(cachedCount: 0, displayedCount: 513),
        isFalse,
      );
    });

    test('non-empty cache replaces the display (normal delta refresh)', () {
      expect(
        shouldReplaceDisplayedBooks(cachedCount: 42, displayedCount: 513),
        isTrue,
      );
    });

    test('non-empty cache may shrink the display (peer deleted books)', () {
      expect(
        shouldReplaceDisplayedBooks(cachedCount: 3, displayedCount: 10),
        isTrue,
      );
    });

    test('empty cache over an empty display is a no-op replace (allowed)', () {
      expect(
        shouldReplaceDisplayedBooks(cachedCount: 0, displayedCount: 0),
        isTrue,
      );
    });
  });
}
