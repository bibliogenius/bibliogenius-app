import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/catalog_push_mode.dart';
import 'package:bibliogenius/models/hub_directory.dart';

HubFollow _follower({
  required int id,
  String status = 'active',
  String? key = 'abababababababababababababababababababababababababababababababab',
  String? version = '1.3.0+600',
  String? readerStatus = 'reader',
}) => HubFollow(
  id: id,
  followerNodeId: 'reader-$id',
  followedNodeId: 'owner',
  status: status,
  createdAt: '2026-10-19T00:00:00Z',
  followerX25519PublicKey: key,
  followerAppVersion: version,
  catalogReaderStatus: readerStatus,
);

void main() {
  group('compareAppVersions', () {
    test('orders by major, minor, patch', () {
      expect(compareAppVersions('1.3.0', '1.2.9'), greaterThan(0));
      expect(compareAppVersions('1.2.9', '1.3.0'), lessThan(0));
      expect(compareAppVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareAppVersions('1.3.0', '1.3.0'), 0);
    });

    test('a build number only breaks a tie when both carry one', () {
      expect(compareAppVersions('1.3.0+601', '1.3.0+600'), greaterThan(0));
      expect(compareAppVersions('1.3.0+600', '1.3.0'), 0);
      expect(compareAppVersions('1.3.0', '1.3.0+600'), 0);
    });

    test('a short core is padded with zeros', () {
      expect(compareAppVersions('1.3', '1.3.0'), 0);
      expect(compareAppVersions('2', '1.9.9'), greaterThan(0));
    });

    test('an unparseable version is the lowest there is', () {
      expect(compareAppVersions('dev', '1.3.0'), lessThan(0));
      expect(compareAppVersions('1.3.0', ''), greaterThan(0));
      expect(compareAppVersions('x', 'y'), 0);
    });
  });

  group('decideCatalogPushMode', () {
    test('a public library stays in clear whatever its followers run', () {
      final mode = decideCatalogPushMode(
        isListed: true,
        requiresApproval: false,
        followers: [_follower(id: 1)],
      );
      expect(mode, CatalogPushMode.clear);
    });

    test('an unlisted library with no follower encrypts', () {
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: const [],
      );
      expect(mode, CatalogPushMode.encrypted);
    });

    test('encrypts when every active follower can read it', () {
      final mode = decideCatalogPushMode(
        isListed: true,
        requiresApproval: true,
        followers: [
          _follower(id: 1),
          _follower(id: 2, version: '1.4.2+700'),
          // Not readers: pending and rejected follows do not count.
          _follower(id: 3, status: 'pending', version: '1.0.0'),
          _follower(id: 4, status: 'rejected', version: null),
        ],
      );
      expect(mode, CatalogPushMode.encrypted);
    });

    test('one follower below the floor keeps the catalog in clear', () {
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: [_follower(id: 1), _follower(id: 2, version: '1.2.3+498')],
      );
      expect(mode, CatalogPushMode.clear);
    });

    test('an unknown version reads as too old', () {
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: [_follower(id: 1, version: null)],
      );
      expect(mode, CatalogPushMode.clear);
    });

    test('a follower without a key cannot be wrapped for', () {
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: [_follower(id: 1, key: null)],
      );
      expect(mode, CatalogPushMode.clear);
    });

    test('an active follower off the readers list does not count', () {
      // An ex-peer still following on an old build: it gets no wrap, so it
      // must not hold every real reader back in clear either (R1+).
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: [
          _follower(id: 1),
          _follower(id: 2, version: '1.2.3+498', readerStatus: 'not_reader'),
          _follower(id: 3, key: null, readerStatus: 'not_reader'),
        ],
      );
      expect(mode, CatalogPushMode.encrypted);
    });

    test('a follower whose key changed is no reader: the catalog stays '
        'encrypted', () {
      // A reinstall, or a key the hub substituted: the follower gets no
      // wrap until the owner approves or pairs it again, and must not push
      // the catalog back to clear for everyone (rule (b)).
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: [
          _follower(id: 1),
          _follower(id: 2, readerStatus: 'key_mismatch'),
        ],
      );
      expect(mode, CatalogPushMode.encrypted);
    });

    test('the version of a follower whose key changed is not consulted', () {
      // Whatever the hub says about its build: it is not a reader.
      for (final version in <String?>['1.2.3+498', null, '']) {
        final mode = decideCatalogPushMode(
          isListed: false,
          requiresApproval: true,
          followers: [
            _follower(id: 1),
            _follower(id: 2, version: version, readerStatus: 'key_mismatch'),
          ],
        );
        expect(mode, CatalogPushMode.encrypted, reason: 'version $version');
      }
    });

    test('a follower whose key the hub no longer returns is no reader', () {
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: [
          _follower(id: 1, key: null, readerStatus: 'key_mismatch'),
        ],
      );
      expect(mode, CatalogPushMode.encrypted);
    });

    test('a public library stays in clear even with a key mismatch', () {
      final mode = decideCatalogPushMode(
        isListed: true,
        requiresApproval: false,
        followers: [_follower(id: 1, readerStatus: 'key_mismatch')],
      );
      expect(mode, CatalogPushMode.clear);
    });

    test('a follower the owner never let in keeps the catalog in clear', () {
      // Approved without a key to pin, or followed while the library was
      // public: it gets no wrap, so encrypting would lock it out.
      final mode = decideCatalogPushMode(
        isListed: false,
        requiresApproval: true,
        followers: [
          _follower(id: 1),
          _follower(id: 2, key: null, readerStatus: 'unknown'),
        ],
      );
      expect(mode, CatalogPushMode.clear);
    });

    test('an unknown reader status is judged on the follower alone', () {
      expect(
        decideCatalogPushMode(
          isListed: false,
          requiresApproval: true,
          followers: [_follower(id: 1, readerStatus: null)],
        ),
        CatalogPushMode.encrypted,
      );
      expect(
        decideCatalogPushMode(
          isListed: false,
          requiresApproval: true,
          followers: [
            _follower(id: 1, version: '1.2.3', readerStatus: null),
          ],
        ),
        CatalogPushMode.clear,
      );
    });

    test('the floor is the version that ships the reader', () {
      expect(encryptedCatalogMinAppVersion, '1.3.0');
      expect(
        followerCanReadEncryptedCatalog(_follower(id: 1, version: '1.3.0')),
        isTrue,
      );
      expect(
        followerCanReadEncryptedCatalog(_follower(id: 1, version: '1.2.99')),
        isFalse,
      );
    });
  });
}
