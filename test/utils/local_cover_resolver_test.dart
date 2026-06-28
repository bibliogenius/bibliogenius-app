import 'package:bibliogenius/utils/local_cover_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalCoverResolver.resolve', () {
    tearDown(LocalCoverResolver.resetForTest);

    test('passes non-local values through unchanged', () {
      LocalCoverResolver.coversDirPathForTest = '/now/covers';
      expect(
        LocalCoverResolver.resolve('https://cdn/x.jpg', bookId: '42'),
        'https://cdn/x.jpg',
      );
      expect(
        LocalCoverResolver.resolve('http://cdn/x.jpg', bookId: '42'),
        'http://cdn/x.jpg',
      );
      expect(
        LocalCoverResolver.resolve('/api/books/1/cover', bookId: '1'),
        '/api/books/1/cover',
      );
      expect(LocalCoverResolver.resolve('', bookId: '42'), '');
    });

    test('returns the stored path untouched when covers dir is unknown', () {
      LocalCoverResolver.resetForTest();
      const stored =
          '/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/covers/42.jpg';
      expect(LocalCoverResolver.resolve(stored, bookId: '42'), stored);
    });

    test('returns the stored path untouched when bookId is unknown', () {
      LocalCoverResolver.coversDirPathForTest = '/now/covers';
      const stored = '/old/covers/42.jpg';
      expect(LocalCoverResolver.resolve(stored), stored);
    });

    test('re-bases a stale own cover path (basename matches bookId)', () {
      LocalCoverResolver.coversDirPathForTest =
          '/var/mobile/Containers/Data/Application/NEW-UUID/Library/Application Support/covers';
      const stored =
          '/var/mobile/Containers/Data/Application/OLD-UUID/Library/Application Support/covers/42.jpg';
      expect(
        LocalCoverResolver.resolve(stored, bookId: '42'),
        '/var/mobile/Containers/Data/Application/NEW-UUID/Library/Application Support/covers/42.jpg',
      );
    });

    test(
      'does NOT re-base a foreign synced path (basename != bookId) — no wrong cover',
      () {
        // Book synced from device A: A's path with A-side basename 42, but
        // inserted under this device's local id 87. Must NOT map onto 87.jpg.
        LocalCoverResolver.coversDirPathForTest = '/now/covers';
        const stored = '/var/mobile/.../Application Support/covers/42.jpg';
        expect(LocalCoverResolver.resolve(stored, bookId: '87'), stored);
      },
    );

    test('is a no-op when the stored path already lives in the current covers dir', () {
      LocalCoverResolver.coversDirPathForTest = '/Users/x/Application Support/covers';
      const stored = '/Users/x/Application Support/covers/7.jpg';
      expect(LocalCoverResolver.resolve(stored, bookId: '7'), stored);
    });

    test('rebases a bare basename that matches the bookId', () {
      LocalCoverResolver.coversDirPathForTest = '/now/covers';
      expect(LocalCoverResolver.resolve('42.jpg', bookId: '42'), '/now/covers/42.jpg');
    });
  });
}
