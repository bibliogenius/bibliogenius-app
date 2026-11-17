import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/services/web_cover_service.dart';
import 'package:bibliogenius/utils/cover_camera_helper.dart';

void main() {
  final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);

  WebCoverService service({
    Object? fetchError,
    Object? saveError,
    void Function(String url, String? isbn)? onFetch,
    void Function()? onSave,
  }) {
    return WebCoverService(
      fetch: (url, {isbn}) async {
        onFetch?.call(url, isbn);
        if (fetchError != null) throw fetchError;
        return (
          bytes: bytes,
          imageUrl: 'https://cdn.example.org/42.jpg',
          candidates: [
            'https://cdn.example.org/42.jpg',
            'https://cdn.example.org/43.jpg',
          ],
        );
      },
      fetchImage: (url) async {
        if (fetchError != null) throw fetchError;
        return (bytes: bytes, imageUrl: url, candidates: <String>[]);
      },
      save: (b) async {
        onSave?.call();
        if (saveError != null) throw saveError;
        return '/covers/temp_x.jpg';
      },
    );
  }

  test('saves the fetched cover and keeps its web address', () async {
    String? fetched;
    var saved = false;
    final pick = await service(
      onFetch: (u, _) => fetched = u,
      onSave: () => saved = true,
    ).fetchAndSave('  https://www.example.org/livre/42  ');

    expect(fetched, 'https://www.example.org/livre/42', reason: 'trimmed');
    expect(saved, isTrue);
    expect(pick.path, '/covers/temp_x.jpg', reason: 'a preview, never final');
    expect(pick.imageUrl, 'https://cdn.example.org/42.jpg');
    expect(pick.candidates, hasLength(2), reason: 'kept for stepping');
  });

  test('passes the ISBN on, and no ISBN for a blank field', () async {
    final seen = <String?>[];
    final s = service(onFetch: (_, isbn) => seen.add(isbn));
    await s.fetchAndSave('https://x.org/a', isbn: ' 9782290003299 ');
    await s.fetchAndSave('https://x.org/a', isbn: '   ');
    await s.fetchAndSave('https://x.org/a');
    expect(seen, ['9782290003299', null, null]);
  });

  test('saves a candidate the user stepped to', () async {
    final pick = await service().fetchCandidateAndSave(
      'https://cdn.example.org/43.jpg',
    );
    expect(pick.imageUrl, 'https://cdn.example.org/43.jpg');
    expect(pick.path, '/covers/temp_x.jpg');
    await expectLater(
      service(
        fetchError: 'unsupported_image',
      ).fetchCandidateAndSave('https://cdn.example.org/43.jpg'),
      throwsA(
        isA<WebCoverException>().having(
          (e) => e.code,
          'code',
          'unsupported_image',
        ),
      ),
    );
  });

  test('turns a Rust error code into its message key', () async {
    await expectLater(
      service(fetchError: 'no_image_found').fetchAndSave('https://x.org/a'),
      throwsA(
        isA<WebCoverException>().having(
          (e) => e.translationKey,
          'translationKey',
          'web_cover_error_no_image_found',
        ),
      ),
    );
  });

  test('reports an unknown failure as a network error', () async {
    for (final error in <Object>['something_new', StateError('bridge')]) {
      await expectLater(
        service(fetchError: error).fetchAndSave('https://x.org/a'),
        throwsA(
          isA<WebCoverException>().having((e) => e.code, 'code', 'network'),
        ),
      );
    }
  });

  test('reports bytes the cover pipeline cannot decode', () async {
    await expectLater(
      service(
        saveError: const FormatException('bad'),
      ).fetchAndSave('https://x.org/a'),
      throwsA(
        isA<WebCoverException>().having(
          (e) => e.code,
          'code',
          'unreadable_image',
        ),
      ),
    );
  });

  test('reports an image too large to decode as too large', () async {
    await expectLater(
      service(
        saveError: const CoverImageTooLargeException(20000, 20000),
      ).fetchAndSave('https://x.org/a'),
      throwsA(
        isA<WebCoverException>().having((e) => e.code, 'code', 'too_large'),
      ),
    );
  });

  test('turns any other save failure into a message, never a hang', () async {
    for (final error in <Object>[
      const UnsupportedCoverImageException('animated WebP'),
      RangeError('corrupt'),
      const FileSystemException('disk full'),
    ]) {
      await expectLater(
        service(saveError: error).fetchAndSave('https://x.org/a'),
        throwsA(isA<WebCoverException>()),
        reason: '$error',
      );
    }
    await expectLater(
      service(
        saveError: const UnsupportedCoverImageException('animated WebP'),
      ).fetchAndSave('https://x.org/a'),
      throwsA(
        isA<WebCoverException>().having(
          (e) => e.code,
          'code',
          'unsupported_image',
        ),
      ),
    );
  });

  test('a site that turns away automated clients keeps its own code', () {
    // Not folded into `network`: its message tells the user to copy the
    // image address from their browser instead.
    expect(WebCoverException('blocked_by_site').code, 'blocked_by_site');
  });

  test('every known code has a stable message key', () {
    for (final code in WebCoverException.knownCodes) {
      expect(WebCoverException(code).translationKey, 'web_cover_error_$code');
    }
  });

  group('adoptForBook', () {
    const pick = WebCoverPick(
      path: '/covers/temp_x.jpg',
      imageUrl: 'https://cdn.example.org/42.jpg',
    );

    ({
      WebCoverService service,
      List<String?> writes,
      List<String> renamed,
      List<String> discarded,
      List<String> origins,
    })
    harness({bool renameFails = false, bool originFails = false}) {
      final writes = <String?>[];
      final renamed = <String>[];
      final discarded = <String>[];
      final origins = <String>[];
      final service = WebCoverService(
        rename: (temp, bookId) async {
          if (renameFails) return null;
          renamed.add('$temp -> $bookId');
          return '/covers/$bookId.jpg';
        },
        discard: (path) async => discarded.add(path),
        recordOrigin: (bookId, url) async {
          if (originFails) throw StateError('origin store down');
          origins.add('$bookId $url');
        },
      );
      return (
        service: service,
        writes: writes,
        renamed: renamed,
        discarded: discarded,
        origins: origins,
      );
    }

    test(
      'stores the path, then replaces the file, then records the origin',
      () async {
        final h = harness();
        final path = await h.service.adoptForBook(
          pick,
          bookId: 'book-1',
          previousCoverUrl: 'https://old.example.org/a.jpg',
          updateCoverUrl: (url) async => h.writes.add(url),
        );
        expect(path, '/covers/book-1.jpg');
        expect(h.writes, ['/covers/book-1.jpg']);
        expect(h.renamed, ['/covers/temp_x.jpg -> book-1']);
        expect(h.origins, ['book-1 https://cdn.example.org/42.jpg']);
        expect(h.discarded, isEmpty);
      },
    );

    test(
      'keeps the new cover when only its origin cannot be recorded',
      () async {
        // The cover is already in place: an origin that could not be stored is
        // no reason to tell the user the update failed.
        final h = harness(originFails: true);
        final path = await h.service.adoptForBook(
          pick,
          bookId: 'book-1',
          previousCoverUrl: 'https://old.example.org/a.jpg',
          updateCoverUrl: (url) async => h.writes.add(url),
        );
        expect(path, '/covers/book-1.jpg');
        expect(h.writes, ['/covers/book-1.jpg'], reason: 'nothing rolled back');
        expect(h.renamed, ['/covers/temp_x.jpg -> book-1']);
        expect(h.discarded, isEmpty);
        expect(h.origins, isEmpty);
      },
    );

    test('recordOrigin on its own never throws either', () async {
      final h = harness(originFails: true);
      await expectLater(
        h.service.recordOrigin('book-1', 'https://cdn.example.org/42.jpg'),
        completes,
      );
    });

    test(
      'puts the previous cover back when the file cannot be renamed',
      () async {
        final h = harness(renameFails: true);
        await expectLater(
          h.service.adoptForBook(
            pick,
            bookId: 'book-1',
            previousCoverUrl: 'https://old.example.org/a.jpg',
            updateCoverUrl: (url) async => h.writes.add(url),
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(h.writes, [
          '/covers/book-1.jpg',
          'https://old.example.org/a.jpg',
        ]);
        expect(h.discarded, ['/covers/temp_x.jpg']);
        expect(h.origins, isEmpty);
      },
    );

    test('touches no file when the database refuses the path', () async {
      final h = harness();
      await expectLater(
        h.service.adoptForBook(
          pick,
          bookId: 'book-1',
          previousCoverUrl: null,
          updateCoverUrl: (url) async => throw StateError('db down'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(h.renamed, isEmpty, reason: 'the old cover file is intact');
      expect(h.discarded, ['/covers/temp_x.jpg']);
      expect(h.origins, isEmpty);
    });
  });

  group('publisher site', () {
    const book = (
      isbn: ' 9782070360024 ',
      title: ' L\'Étranger ',
      authors: 'Albert Camus',
      publisher: '  ',
    );

    WebCoverService publisherService({
      Object? findError,
      Object? saveError,
      void Function(PublisherBook book)? onFind,
    }) {
      return WebCoverService(
        findOnPublisherSite: (b) async {
          onFind?.call(b);
          if (findError != null) throw findError;
          return (
            bytes: bytes,
            imageUrl: 'https://www.gallimard.fr/couv/9782070360024.jpg',
            candidates: [
              'https://www.gallimard.fr/couv/9782070360024.jpg',
              'https://www.gallimard.fr/couv/autre.jpg',
            ],
            site: 'gallimard.fr',
            pageUrl:
                'https://www.gallimard.fr/catalogue/l-etranger/9782070360024',
          );
        },
        save: (b) async {
          if (saveError != null) throw saveError;
          return '/covers/temp_p.jpg';
        },
      );
    }

    test('saves the cover found and says on which site', () async {
      PublisherBook? asked;
      final pick = await publisherService(
        onFind: (b) => asked = b,
      ).findOnPublisherSiteAndSave(book);

      expect(asked!.isbn, '9782070360024', reason: 'trimmed');
      expect(asked!.title, "L'Étranger");
      expect(asked!.publisher, isNull, reason: 'a blank publisher is none');
      expect(pick.path, '/covers/temp_p.jpg');
      expect(pick.imageUrl, 'https://www.gallimard.fr/couv/9782070360024.jpg');
      expect(pick.candidates, hasLength(2), reason: 'kept for stepping');
      expect(pick.site, 'gallimard.fr');
    });

    test('a failed search keeps its code for the message', () async {
      for (final code in PublisherCoverException.knownCodes) {
        await expectLater(
          publisherService(findError: code).findOnPublisherSiteAndSave(book),
          throwsA(
            isA<PublisherCoverException>()
                .having((e) => e.code, 'code', code)
                .having(
                  (e) => e.translationKey,
                  'key',
                  'publisher_cover_error_$code',
                ),
          ),
        );
      }
    });

    test('an unknown failure is reported as the site not answering', () async {
      for (final error in ['something_new', StateError('ffi')]) {
        await expectLater(
          publisherService(findError: error).findOnPublisherSiteAndSave(book),
          throwsA(
            isA<PublisherCoverException>().having(
              (e) => e.code,
              'code',
              'network',
            ),
          ),
        );
      }
    });

    test('an image the app cannot use is no usable cover', () async {
      for (final Object error in [
        const CoverImageTooLargeException(20000, 20000),
        const UnsupportedCoverImageException('animated WebP'),
        const FormatException('corrupt'),
      ]) {
        await expectLater(
          publisherService(saveError: error).findOnPublisherSiteAndSave(book),
          throwsA(
            isA<PublisherCoverException>().having(
              (e) => e.code,
              'code',
              'no_image_found',
            ),
          ),
        );
      }
    });
  });

  group('SingleFlight', () {
    test('a second ask for the same key joins the search running', () async {
      final flight = SingleFlight<int>();
      final pending = Completer<int>();
      var starts = 0;
      Future<int> start() {
        starts++;
        return pending.future;
      }

      final first = flight.run('9782070360024', start);
      final second = flight.run('9782070360024', start);
      expect(starts, 1);
      pending.complete(7);
      expect(await first, 7);
      expect(await second, 7);

      // Once done, a new ask starts a new search.
      await flight.run('9782070360024', () async {
        starts++;
        return 8;
      });
      expect(starts, 2);
    });

    test('other keys run on their own, and a failure is not kept', () async {
      final flight = SingleFlight<int>();
      final pending = Completer<int>();
      final a = flight.run('a', () => pending.future);
      var otherStarted = false;
      await flight.run('b', () async {
        otherStarted = true;
        return 1;
      });
      expect(otherStarted, isTrue);
      pending.completeError('network');
      await expectLater(a, throwsA('network'));
      expect(await flight.run('a', () async => 2), 2);
    });
  });
}
