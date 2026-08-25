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

    test(
      'is a no-op when the stored path already lives in the current covers dir',
      () {
        LocalCoverResolver.coversDirPathForTest =
            '/Users/x/Application Support/covers';
        const stored = '/Users/x/Application Support/covers/7.jpg';
        expect(LocalCoverResolver.resolve(stored, bookId: '7'), stored);
      },
    );

    test('rebases a bare basename that matches the bookId', () {
      LocalCoverResolver.coversDirPathForTest = '/now/covers';
      expect(
        LocalCoverResolver.resolve('42.jpg', bookId: '42'),
        '/now/covers/42.jpg',
      );
    });
  });

  group('LocalCoverResolver.normalizeForStorage', () {
    test('shortens an absolute path whose basename is the canonical name', () {
      expect(
        LocalCoverResolver.normalizeForStorage(
          '/var/mobile/Containers/Data/Application/UUID/Library/Application Support/covers/42.jpg',
          bookId: '42',
        ),
        '42.jpg',
      );
    });

    test('is idempotent on a value already stored short', () {
      expect(
        LocalCoverResolver.normalizeForStorage('42.jpg', bookId: '42'),
        '42.jpg',
      );
    });

    test('leaves remote and peer values untouched', () {
      expect(
        LocalCoverResolver.normalizeForStorage(
          'https://cdn/42.jpg',
          bookId: '42',
        ),
        'https://cdn/42.jpg',
      );
      expect(
        LocalCoverResolver.normalizeForStorage(
          'http://cdn/42.jpg',
          bookId: '42',
        ),
        'http://cdn/42.jpg',
      );
      expect(
        LocalCoverResolver.normalizeForStorage(
          '/api/books/42/cover',
          bookId: '42',
        ),
        '/api/books/42/cover',
      );
    });

    test('leaves a temp cover from the add flow untouched', () {
      // During add, the file is named `temp_<uuid4>.jpg` until the book exists
      // and `renameTempCover` finalises it. Shortening it would strip the only
      // prefix that makes it findable: the basename does not match the book id,
      // so no resolver would re-base it.
      const temp = '/Users/x/Application Support/covers/temp_abcd-1234.jpg';
      expect(LocalCoverResolver.normalizeForStorage(temp, bookId: '42'), temp);
    });

    test('leaves a foreign device path untouched', () {
      // Synced from device A under a fresh local id: basename 42 vs local 87.
      const foreign = '/var/mobile/.../Application Support/covers/42.jpg';
      expect(
        LocalCoverResolver.normalizeForStorage(foreign, bookId: '87'),
        foreign,
      );
    });

    test('leaves the value untouched when the book id is unknown', () {
      const stored = '/Users/x/Application Support/covers/42.jpg';
      expect(
        LocalCoverResolver.normalizeForStorage(stored, bookId: null),
        stored,
      );
      expect(
        LocalCoverResolver.normalizeForStorage(stored, bookId: ''),
        stored,
      );
    });

    test('passes null and empty through', () {
      expect(
        LocalCoverResolver.normalizeForStorage(null, bookId: '42'),
        isNull,
      );
      expect(LocalCoverResolver.normalizeForStorage('', bookId: '42'), '');
    });

    test(
      'round-trips: what it stores, resolve() turns back into a real path',
      () {
        LocalCoverResolver.coversDirPathForTest = '/now/covers';
        const captured = '/old/container/covers/42.jpg';
        final stored = LocalCoverResolver.normalizeForStorage(
          captured,
          bookId: '42',
        );
        expect(
          LocalCoverResolver.resolve(stored!, bookId: '42'),
          '/now/covers/42.jpg',
        );
        LocalCoverResolver.resetForTest();
      },
    );
  });
}
