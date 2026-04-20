import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/utils/cover_url_resolver.dart';

void main() {
  group('CoverUrlResolver.isServableRemotely', () {
    test('accepts http and https only', () {
      expect(CoverUrlResolver.isServableRemotely('http://a'), isTrue);
      expect(CoverUrlResolver.isServableRemotely('https://a'), isTrue);
      expect(CoverUrlResolver.isServableRemotely('/api/books/1/cover'), isFalse);
      expect(CoverUrlResolver.isServableRemotely('/var/mobile/c.jpg'), isFalse);
      expect(CoverUrlResolver.isServableRemotely(''), isFalse);
      expect(CoverUrlResolver.isServableRemotely('file:///x'), isFalse);
    });
  });

  group('CoverUrlResolver.resolveForLocal', () {
    test('returns persisted cover URL when present', () {
      final out = CoverUrlResolver.resolveForLocal(
        coverUrl: 'https://cdn/x.jpg',
        isbn: '9781234567890',
      );
      expect(out, 'https://cdn/x.jpg');
    });

    test('falls back to OpenLibrary M when cover is null', () {
      final out = CoverUrlResolver.resolveForLocal(
        coverUrl: null,
        isbn: '9781234567890',
      );
      expect(
        out,
        'https://covers.openlibrary.org/b/isbn/9781234567890-M.jpg?default=false',
      );
    });

    test('falls back to OpenLibrary L when large requested', () {
      final out = CoverUrlResolver.resolveForLocal(
        coverUrl: null,
        isbn: '9781234567890',
        large: true,
      );
      expect(
        out,
        'https://covers.openlibrary.org/b/isbn/9781234567890-L.jpg?default=false',
      );
    });

    test('empty cover URL triggers fallback', () {
      final out = CoverUrlResolver.resolveForLocal(
        coverUrl: '',
        isbn: '9781234567890',
      );
      expect(
        out,
        'https://covers.openlibrary.org/b/isbn/9781234567890-M.jpg?default=false',
      );
    });

    test('returns null when neither cover nor ISBN are available', () {
      expect(CoverUrlResolver.resolveForLocal(coverUrl: null, isbn: null), isNull);
      expect(CoverUrlResolver.resolveForLocal(coverUrl: '', isbn: ''), isNull);
      expect(CoverUrlResolver.resolveForLocal(coverUrl: '', isbn: null), isNull);
    });
  });

  group('CoverUrlResolver.resolveForPeer', () {
    const peerUrl = 'http://192.168.1.10:3000';

    test('HTTP URL passes through', () {
      final out = CoverUrlResolver.resolveForPeer(
        coverUrl: 'https://hub/covers/7',
        bookId: 7,
        peerUrl: peerUrl,
      );
      expect(out, 'https://hub/covers/7');
    });

    test('/api path is routed through the local cover-proxy', () {
      final out = CoverUrlResolver.resolveForPeer(
        coverUrl: '/api/books/42/cover',
        bookId: 42,
        peerUrl: peerUrl,
      );
      final expectedPeer = Uri.encodeQueryComponent(peerUrl);
      expect(
        out,
        '/api/peers/cover-proxy?peer_url=$expectedPeer&book_id=42',
      );
    });

    test('local filesystem path returns null (no OpenLibrary fallback)', () {
      // Key non-regression: the peer is the authoritative source of its
      // covers. Falling back to OpenLibrary here would show a different
      // image to the visitor than to the uploader.
      final out = CoverUrlResolver.resolveForPeer(
        coverUrl: '/var/mobile/cover_42.jpg',
        bookId: 42,
        peerUrl: peerUrl,
      );
      expect(out, isNull);
    });

    test('null or empty cover returns null', () {
      expect(
        CoverUrlResolver.resolveForPeer(
          coverUrl: null,
          bookId: 42,
          peerUrl: peerUrl,
        ),
        isNull,
      );
      expect(
        CoverUrlResolver.resolveForPeer(
          coverUrl: '',
          bookId: 42,
          peerUrl: peerUrl,
        ),
        isNull,
      );
    });

    test('/api path without book id returns null', () {
      final out = CoverUrlResolver.resolveForPeer(
        coverUrl: '/api/books/42/cover',
        bookId: null,
        peerUrl: peerUrl,
      );
      expect(out, isNull);
    });
  });
}
