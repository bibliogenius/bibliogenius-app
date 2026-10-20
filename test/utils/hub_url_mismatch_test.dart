import 'package:bibliogenius/utils/hub_url_mismatch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('hubUrlMismatchWarning', () {
    test('is null when .env and the effective hub agree', () {
      expect(
        hubUrlMismatchWarning(
          envHubUrl: 'https://hub.example.org',
          effectiveHubUrl: 'https://hub.example.org',
        ),
        isNull,
      );
    });

    test('ignores a trailing slash, like the Rust comparator', () {
      expect(
        hubUrlMismatchWarning(
          envHubUrl: 'https://hub.example.org/',
          effectiveHubUrl: 'https://hub.example.org',
        ),
        isNull,
      );
    });

    test('is null when the effective hub is unknown', () {
      expect(
        hubUrlMismatchWarning(
          envHubUrl: 'https://hub.example.org',
          effectiveHubUrl: null,
        ),
        isNull,
      );
    });

    test('names both hubs and the fix when they differ', () {
      final warning = hubUrlMismatchWarning(
        envHubUrl: 'https://hub-dev.example.org',
        effectiveHubUrl: 'https://hub.example.org',
      );
      expect(warning, isNotNull);
      expect(warning, contains('https://hub-dev.example.org'));
      expect(warning, contains('https://hub.example.org'));
      expect(warning, contains('.env'));
    });
  });

  group('logHubUrlMismatch', () {
    test('never throws, even when the effective hub cannot be read', () {
      final printed = <String>[];
      expect(
        () => logHubUrlMismatch(
          envHubUrl: 'https://hub.example.org',
          readEffectiveHubUrl: () => throw StateError('bridge not ready'),
          log: printed.add,
        ),
        returnsNormally,
      );
      expect(printed, isEmpty);
    });

    test('prints the warning when the hubs differ', () {
      final printed = <String>[];
      logHubUrlMismatch(
        envHubUrl: 'https://hub-dev.example.org',
        readEffectiveHubUrl: () => 'https://hub.example.org',
        log: printed.add,
      );
      expect(printed, hasLength(1));
    });
  });
}
