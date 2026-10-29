import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

const _selfNode = 'self-node-uuid';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  String x25519Key = 'x25519-pubkey-hex';
  frb.FrbRelayConfig? relay = const frb.FrbRelayConfig(
    relayUrl: 'https://relay.example.test',
    mailboxUuid: 'mailbox-1',
    writeToken: 'token-1',
  );
  bool registerFails = false;

  /// Every registration the hub would have received.
  final List<frb.FrbRegisterParams> registrations = [];

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      const frb.FrbDirectoryConfig(
        nodeId: _selfNode,
        isListed: false,
        requiresApproval: true,
        acceptFrom: 'everyone',
        allowBorrowing: false,
      );

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => relay;

  @override
  Future<int> countBooks() async => 3;

  @override
  Future<String?> getLocalX25519PublicKey() async => x25519Key;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    if (registerFails) throw Exception('hub unreachable');
    registrations.add(params);
    return frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: params.isListed ?? false,
      requiresApproval: params.requiresApproval ?? true,
      acceptFrom: params.acceptFrom,
      allowBorrowing: params.allowBorrowing ?? false,
    );
  }
}

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';
  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test';
  @override
  Future<String?> getAppVersion() async => '1.0.0';
}

Future<(HubDirectoryProvider, _MockFfiService)> _provider() async {
  SharedPreferences.setMockInitialValues({'hub_directory_enabled': true});
  AuthService.storage = MockSecureStorage();
  final ffi = _MockFfiService();
  final p = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  await p.loadHubEnabled();
  await p.loadConfig();
  return (p, ffi);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ensureKeysPublished', () {
    test('registers once per session for an unchanged key, relay and name',
        () async {
      // The Contacts screen reloads every 30 s and on every peer event, and
      // each reload asked the hub to register again with the same payload.
      final (p, ffi) = await _provider();

      await p.ensureKeysPublished('My Library');
      await p.ensureKeysPublished('My Library');
      await p.ensureKeysPublished('My Library');

      expect(ffi.registrations, hasLength(1));
    });

    test('registers again when the relay credentials change', () async {
      final (p, ffi) = await _provider();
      await p.ensureKeysPublished('My Library');

      ffi.relay = const frb.FrbRelayConfig(
        relayUrl: 'https://relay.example.test',
        mailboxUuid: 'mailbox-2',
        writeToken: 'token-2',
      );
      await p.ensureKeysPublished('My Library');

      expect(ffi.registrations, hasLength(2));
      expect(ffi.registrations.last.relayMailboxId, 'mailbox-2');
    });

    test('registers again when the key or the name changes', () async {
      final (p, ffi) = await _provider();
      await p.ensureKeysPublished('My Library');

      ffi.x25519Key = 'rotated-pubkey-hex';
      await p.ensureKeysPublished('My Library');
      expect(ffi.registrations, hasLength(2));
      expect(ffi.registrations.last.x25519PublicKey, 'rotated-pubkey-hex');

      await p.ensureKeysPublished('Renamed Library');
      expect(ffi.registrations, hasLength(3));
      expect(ffi.registrations.last.displayName, 'Renamed Library');
    });

    test('a failed registration is retried on the next call', () async {
      final (p, ffi) = await _provider();
      ffi.registerFails = true;
      await p.ensureKeysPublished('My Library');
      expect(ffi.registrations, isEmpty);

      ffi.registerFails = false;
      await p.ensureKeysPublished('My Library');
      expect(ffi.registrations, hasLength(1));
    });
  });
}
