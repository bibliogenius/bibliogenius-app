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
    void Function(String url)? onFetch,
    void Function()? onSave,
  }) {
    return WebCoverService(
      fetch: (url) async {
        onFetch?.call(url);
        if (fetchError != null) throw fetchError;
        return (bytes: bytes, imageUrl: 'https://cdn.example.org/42.jpg');
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
      onFetch: (u) => fetched = u,
      onSave: () => saved = true,
    ).fetchAndSave('  https://www.example.org/livre/42  ');

    expect(fetched, 'https://www.example.org/livre/42', reason: 'trimmed');
    expect(saved, isTrue);
    expect(pick.path, '/covers/temp_x.jpg', reason: 'a preview, never final');
    expect(pick.imageUrl, 'https://cdn.example.org/42.jpg');
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
      throwsA(isA<WebCoverException>().having((e) => e.code, 'code', 'too_large')),
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

  test('every known code has a stable message key', () {
    for (final code in WebCoverException.knownCodes) {
      expect(WebCoverException(code).translationKey, 'web_cover_error_$code');
    }
  });
}
