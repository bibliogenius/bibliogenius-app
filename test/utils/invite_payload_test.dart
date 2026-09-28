import 'package:bibliogenius/utils/invite_payload.dart';
import 'package:flutter_test/flutter_test.dart';

// The invite payload is what the other library receives when it scans our QR
// code or opens our invite link. It used to be assembled in three places that
// had drifted apart; these tests pin the single shared behaviour across the
// pairing lanes: Wi-Fi only, relay only (mobile data), both, neither.

const _relayConfig = <String, dynamic>{
  'library_uuid': 'lib-uuid',
  'ed25519_public_key': 'ed-key',
  'x25519_public_key': 'x-key',
  'relay_url': 'https://hub.example.org',
  'mailbox_id': 'mailbox-1',
  'relay_write_token': 'write-token',
};

const _lanOnlyConfig = <String, dynamic>{
  'library_uuid': 'lib-uuid',
  'ed25519_public_key': 'ed-key',
  'x25519_public_key': 'x-key',
};

void main() {
  group('usableWifiIp', () {
    test('keeps a routable private address', () {
      expect(usableWifiIp('192.168.1.42'), '192.168.1.42');
    });

    test('rejects link-local and missing addresses', () {
      // 169.254.x.x means the device has no DHCP lease: nobody can reach it.
      expect(usableWifiIp('169.254.10.2'), isNull);
      expect(usableWifiIp(null), isNull);
      expect(usableWifiIp(''), isNull);
    });
  });

  group('buildLocalInvitePayload', () {
    test('Wi-Fi only: LAN address, no relay keys', () {
      final payload = buildLocalInvitePayload(
        libraryName: 'Ada',
        config: _lanOnlyConfig,
        lanIp: '192.168.1.42',
        httpPort: 8000,
      );

      expect(payload, isNotNull);
      expect(payload!['v'], 4);
      expect(payload['n'], 'Ada');
      expect(payload['u'], 'http://192.168.1.42:8000');
      expect(payload['lu'], 'lib-uuid');
      expect(payload['ek'], 'ed-key');
      expect(payload['xk'], 'x-key');
      expect(payload.containsKey('ru'), isFalse);
      expect(payload.containsKey('mi'), isFalse);
      expect(payload.containsKey('wt'), isFalse);
    });

    test('relay only (mobile data): empty address, relay credentials', () {
      final payload = buildLocalInvitePayload(
        libraryName: 'Ada',
        config: _relayConfig,
        lanIp: null,
        httpPort: 8000,
      );

      expect(payload, isNotNull);
      // The receiver treats an empty address as "relay-only" and lets the
      // Rust backend mint its own relay:// placeholder. Never put a
      // relay:// URL here: the deep-link acceptance screen would prefix it
      // with http:// and attempt a doomed LAN handshake first.
      expect(payload!['u'], '');
      expect(payload['ru'], 'https://hub.example.org');
      expect(payload['mi'], 'mailbox-1');
      expect(payload['wt'], 'write-token');
    });

    test('Wi-Fi and relay: LAN address plus relay credentials', () {
      final payload = buildLocalInvitePayload(
        libraryName: 'Ada',
        config: _relayConfig,
        lanIp: '10.0.0.7',
        httpPort: 8010,
      );

      expect(payload!['u'], 'http://10.0.0.7:8010');
      expect(payload['ru'], 'https://hub.example.org');
      expect(payload['mi'], 'mailbox-1');
    });

    test('neither Wi-Fi nor relay: nothing to invite with', () {
      final payload = buildLocalInvitePayload(
        libraryName: 'Ada',
        config: _lanOnlyConfig,
        lanIp: null,
        httpPort: 8000,
      );

      expect(payload, isNull);
    });

    test('incomplete relay credentials count as no relay', () {
      final payload = buildLocalInvitePayload(
        libraryName: 'Ada',
        config: const {
          'library_uuid': 'lib-uuid',
          'relay_url': 'https://hub.example.org',
          // mailbox_id missing
        },
        lanIp: null,
        httpPort: 8000,
      );

      expect(payload, isNull);
    });

    test('tolerates an untyped config map from the HTTP layer', () {
      final Map<dynamic, dynamic> raw = {'relay_url': 'r', 'mailbox_id': 'm'};
      final payload = buildLocalInvitePayload(
        libraryName: 'Ada',
        config: raw,
        lanIp: null,
        httpPort: 8000,
      );

      expect(payload!['mi'], 'm');
    });
  });

  group('loadInviteLink', () {
    Future<String> fakeCreateLink(
      Map<String, dynamic> payload, {
      required String hubBaseUrl,
    }) async => 'https://short.example/i/abc';

    test('returns link and payload on the relay-only lane', () async {
      final result = await loadInviteLink(
        libraryName: 'Ada',
        fetchLibraryConfig: () async => _relayConfig,
        resolveLanIp: () async => null,
        httpPort: 8000,
        hubBaseUrl: 'https://hub.example.org',
        createLink: fakeCreateLink,
      );

      expect(result, isNotNull);
      expect(result!.link, 'https://short.example/i/abc');
      expect(result.payload['u'], '');
      expect(result.payload['mi'], 'mailbox-1');
    });

    test('returns link and payload on the Wi-Fi lane', () async {
      final result = await loadInviteLink(
        libraryName: 'Ada',
        fetchLibraryConfig: () async => _lanOnlyConfig,
        resolveLanIp: () async => '192.168.1.42',
        httpPort: 8000,
        hubBaseUrl: 'https://hub.example.org',
        createLink: fakeCreateLink,
      );

      expect(result!.payload['u'], 'http://192.168.1.42:8000');
    });

    test('returns null when neither lane is available', () async {
      final result = await loadInviteLink(
        libraryName: 'Ada',
        fetchLibraryConfig: () async => _lanOnlyConfig,
        resolveLanIp: () async => null,
        httpPort: 8000,
        hubBaseUrl: 'https://hub.example.org',
        createLink: fakeCreateLink,
      );

      expect(result, isNull);
    });

    test(
      'returns null instead of throwing when the config fetch fails',
      () async {
        final result = await loadInviteLink(
          libraryName: 'Ada',
          fetchLibraryConfig: () async => throw StateError('backend down'),
          resolveLanIp: () async => '192.168.1.42',
          httpPort: 8000,
          hubBaseUrl: 'https://hub.example.org',
          createLink: fakeCreateLink,
        );

        expect(result, isNull);
      },
    );

    test('a failing IP resolver degrades to the relay lane', () async {
      final result = await loadInviteLink(
        libraryName: 'Ada',
        fetchLibraryConfig: () async => _relayConfig,
        resolveLanIp: () async => throw StateError('no network info'),
        httpPort: 8000,
        hubBaseUrl: 'https://hub.example.org',
        createLink: fakeCreateLink,
      );

      expect(result!.payload['u'], '');
    });
  });
}
