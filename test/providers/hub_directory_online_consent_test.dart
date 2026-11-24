import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/online_services_consent.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ADR-073: nothing registers this installation on the hub, and no library
// data is sent to it, before the user chose the online services. These
// tests count the calls that would reach the hub (registration, relay
// mailbox creation, catalog push) from the paths the app takes on its own:
// startup, opening the network screen, a book edit.

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test';

  @override
  Future<String?> getAppVersion() async => '1.4.2';
}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  /// The local hub registration, as an installation that registered
  /// silently on an earlier build holds it.
  frb.FrbDirectoryConfig? directoryConfig;
  frb.FrbRelayConfig? relayConfig;
  bool signedIn = false;

  int registerCalls = 0;
  int catalogPushes = 0;
  int writeTokenImports = 0;
  /// When set, a registration waits here, like a hub that does not answer.
  Completer<void>? registrationGate;
  int registrationsFinished = 0;

  @override
  Future<bool> hubDirectoryImportWriteToken({
    required String nodeId,
    required String writeToken,
  }) async {
    writeTokenImports++;
    directoryConfig = _registered;
    return true;
  }

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      directoryConfig;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfigStrict() async =>
      directoryConfig;

  int followCalls = 0;

  @override
  Future<frb.FrbHubFollow?> hubDirectoryFollow(String nodeId) async {
    followCalls++;
    return null;
  }

  @override
  Future<frb.FrbHubFollow?> hubDirectoryResolveFollow(
    int followId,
    String resolution, {
    String? encryptedContact,
    String? followerX25519PublicKey,
    String? followerNodeId,
    required bool ownerGesture,
  }) async {
    resolveCalls++;
    return frb.FrbHubFollow(
      id: followId,
      followerNodeId: 'follower-1',
      followedNodeId: 'node-1',
      status: resolution == 'approve' ? 'active' : 'rejected',
      createdAt: '2026-01-01T00:00:00Z',
    );
  }

  int resolveCalls = 0;

  // A private catalog is only pushed once its readers can be seen.
  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => const [];

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => relayConfig;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfigStrict() async => relayConfig;

  @override
  Future<String> accountStatus() async => '{"signed_in": $signedIn}';

  @override
  Future<int> countBooks() async => 7;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<String?> hubDirectoryGetRecoveryCode() async => null;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerCalls++;
    await registrationGate?.future;
    registrationsFinished++;
    directoryConfig = frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: false,
      requiresApproval: true,
      acceptFrom: params.acceptFrom,
      allowBorrowing: false,
    );
    return directoryConfig;
  }

  @override
  Future<int> hubDirectorySyncCatalog() async {
    catalogPushes++;
    return 7;
  }

  @override
  Future<int> hubDirectorySyncCatalogEncrypted() async {
    catalogPushes++;
    return 7;
  }
}

class _MockApiService extends ApiService {
  _MockApiService(this._ffi)
    : super(AuthService(), baseUrl: 'http://localhost:0');

  final _MockFfiService _ffi;

  List<Map<String, dynamic>> peers = [];
  bool peersUnreadable = false;

  int relaySetups = 0;
  int relayForgottenLocally = 0;
  int relayDisconnects = 0;
  /// When set, a mailbox creation waits here.
  Completer<void>? relaySetupGate;

  @override
  Future<Response> getPeersStrict() async {
    if (peersUnreadable) throw StateError('local server not started');
    return Response(
      requestOptions: RequestOptions(path: '/api/peers'),
      statusCode: 200,
      data: {'data': peers},
    );
  }

  @override
  Future<Response> setupRelay({required String relayUrl}) async {
    relaySetups++;
    await relaySetupGate?.future;
    _ffi.relayConfig = const frb.FrbRelayConfig(
      relayUrl: 'https://hub.example.org',
      mailboxUuid: 'mbx-new',
      writeToken: 'wt-new',
    );
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/relay/setup'),
      statusCode: 200,
      data: const {'mailbox_uuid': 'mbx-new'},
    );
  }

  @override
  Future<Response> forgetRelayLocally() async {
    relayForgottenLocally++;
    _ffi.relayConfig = null;
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/relay/config'),
      statusCode: 200,
    );
  }

  @override
  Future<Response> disconnectRelay() async {
    relayDisconnects++;
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/relay/config'),
      statusCode: 200,
    );
  }
}

const _registered = frb.FrbDirectoryConfig(
  nodeId: 'node-1',
  isListed: false,
  requiresApproval: true,
  acceptFrom: 'everyone',
  allowBorrowing: false,
);

const _relay = frb.FrbRelayConfig(
  relayUrl: 'https://hub.example.org',
  mailboxUuid: 'mbx-old',
  writeToken: 'wt-old',
);

(HubDirectoryProvider, _MockFfiService, _MockApiService) _build({
  Map<String, Object> prefs = const {},
  bool registeredBefore = false,
}) {
  SharedPreferences.setMockInitialValues({
    'libraryName': 'Test Library',
    'languageCode': 'en',
    'remoteReachableEnabled': true,
    ...prefs,
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService();
  if (registeredBefore) {
    ffi
      ..directoryConfig = _registered
      ..relayConfig = _relay;
  }
  final api = _MockApiService(ffi);
  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
    apiService: api,
  )..relayRetryDelay = Duration.zero;
  return (provider, ffi, api);
}

int _hubCalls(_MockFfiService ffi, _MockApiService api) =>
    ffi.registerCalls + ffi.catalogPushes + api.relaySetups;

void main() {
  // This directory runs as a consenting installation by default
  // (flutter_test_config.dart); here the consent itself is under test.
  setUpAll(() {
    // ApiService.hubUrl reads the environment when a relay is set up.
    dotenv.testLoad();
  });
  setUp(() => OnlineServicesConsent.debugAlwaysAllowed = false);
  tearDown(() => OnlineServicesConsent.debugAlwaysAllowed = true);

  group('an installation that never used the network', () {
    test('startup registers nothing, creates no mailbox, pushes nothing', () async {
      final (provider, ffi, api) = _build();

      await provider.initAndSyncCatalog();
      await Future<void>.delayed(Duration.zero);

      expect(_hubCalls(ffi, api), 0);
      expect(provider.isRegistered, isFalse);
    });

    test('opening the network screen does not register it', () async {
      final (provider, ffi, api) = _build();

      await provider.loadConfig();
      expect(await provider.ensureRegistered(), isFalse);
      await provider.ensureKeysPublished('Test Library');
      await provider.syncCatalogIfDirty();

      expect(_hubCalls(ffi, api), 0);
    });
  });

  test('a peer row created by another device does not stand for a consent '
      'on an installation that never registered', () async {
    final (provider, ffi, api) = _build();
    api.peers = [
      {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'stranger'},
    ];

    await provider.initAndSyncCatalog();
    await Future<void>.delayed(Duration.zero);

    expect(await provider.onlineServicesAllowed(), isFalse);
    expect(_hubCalls(ffi, api), 0);
  });

  group('an installation registered silently by an earlier build', () {
    test('goes silent: no push, and the relay is forgotten on this device '
        'only', () async {
      final (provider, ffi, api) = _build(registeredBefore: true);

      await provider.initAndSyncCatalog();
      await Future<void>.delayed(Duration.zero);

      expect(_hubCalls(ffi, api), 0);
      expect(api.relayForgottenLocally, 1);
      expect(
        api.relayDisconnects,
        0,
        reason: 'no deletion call is sent to the hub (ADR-073)',
      );
    });

    test('a peer created by another device after it went silent does not '
        'reopen the hub', () async {
      final (provider, ffi, api) = _build(registeredBefore: true);
      await provider.initAndSyncCatalog();
      expect(api.relayForgottenLocally, 1);

      // Later: someone on the local network posts a connection request.
      api.peers = [
        {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'stranger'},
      ];
      await provider.initAndSyncCatalog();
      await provider.loadConfig();
      await provider.ensureKeysPublished('Test Library');
      await provider.syncCatalogIfDirty();
      await Future<void>.delayed(Duration.zero);

      expect(await provider.onlineServicesAllowed(), isFalse);
      expect(_hubCalls(ffi, api), 0);
    });

    test('a book edit pushes nothing', () async {
      final (provider, ffi, api) = _build(registeredBefore: true);
      await provider.loadConfig();
      expect(provider.isRegistered, isTrue);

      provider.markCatalogDirty();
      await provider.syncCatalogIfDirty();
      expect(await provider.syncCatalog(), -1);

      expect(_hubCalls(ffi, api), 0);
    });

    test('a profile update that is not a setting of the owner sends '
        'nothing, whoever calls it', () async {
      // The app bar and the profile screen rename through register()
      // directly, with the registration the settings screen loaded.
      final (provider, ffi, api) = _build(registeredBefore: true);
      await provider.loadConfig();

      final sent = await provider.register(
        nodeId: 'node-1',
        displayName: 'New name',
        bookCount: 7,
        acceptFrom: 'everyone',
        locationCountry: 'FR',
      );

      expect(sent, isFalse);
      expect(_hubCalls(ffi, api), 0);
    });

    test('a visibility setting changed by the owner always reaches the hub, '
        'and is not kept as a lasting yes', () async {
      // Leaving the directory must never be held back by the gate.
      final (provider, ffi, _) = _build(registeredBefore: true);
      await provider.loadConfig();

      final sent = await provider.register(
        nodeId: 'node-1',
        displayName: 'Test Library',
        bookCount: 7,
        acceptFrom: 'everyone',
        isListed: false,
      );

      expect(sent, isTrue);
      expect(ffi.registerCalls, 1);
      // Someone who looked at the directory and left must be able to fall
      // silent again once the switch is off.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(OnlineServicesConsent.prefKey), isNull);
    });

    test('renaming the library or moving it sends nothing, even once the '
        'settings loaded the local registration', () async {
      final (provider, ffi, api) = _build(registeredBefore: true);
      await provider.loadConfig();

      await provider.syncDisplayName('New name');
      await provider.syncLocationCountry('FR');
      await provider.syncLocationCityId(null);

      expect(_hubCalls(ffi, api), 0);
    });

    test('peers that cannot be read: nothing is sent, and nothing is '
        'removed either', () async {
      final (provider, ffi, api) = _build(registeredBefore: true);
      api.peersUnreadable = true;

      await provider.initAndSyncCatalog();
      await Future<void>.delayed(Duration.zero);

      expect(_hubCalls(ffi, api), 0);
      expect(
        api.relayForgottenLocally,
        0,
        reason: 'not knowing is not a no: a paired user keeps the relay',
      );
    });
  });

  group('an installation that uses the network', () {
    test('a peer stands for the consent: startup works as before', () async {
      final (provider, ffi, api) = _build(registeredBefore: true);
      api.peers = [
        {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'peer-1'},
      ];

      await provider.initAndSyncCatalog();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ffi.registerCalls, greaterThan(0), reason: 'relay publication');
      expect(ffi.catalogPushes, greaterThan(0));
      expect(api.relayForgottenLocally, 0);
    });

    test('the directory switch stands for the consent', () async {
      final (provider, _, _) = _build(prefs: {'hub_directory_enabled': true});
      expect(await provider.onlineServicesAllowed(), isTrue);
    });

    test('an encrypted account stands for the consent', () async {
      final (provider, ffi, _) = _build();
      ffi.signedIn = true;
      expect(await provider.onlineServicesAllowed(), isTrue);
    });
  });

  test('a paired installation that lost its registration row keeps its '
      'relay', () async {
    // An earlier build drops the row on a refused token; the mailbox its
    // peers write to is still there.
    final (provider, ffi, api) = _build();
    ffi.relayConfig = _relay;
    api.peers = [
      {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'peer-1'},
    ];

    await provider.initAndSyncCatalog();
    await Future<void>.delayed(Duration.zero);

    expect(api.relayForgottenLocally, 0);
    expect(ffi.registerCalls, greaterThan(0));
  });

  test('a device that could not be read at startup is looked at again when '
      'the app comes back', () async {
    final (provider, ffi, api) = _build(registeredBefore: true);
    api.peers = [
      {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'peer-1'},
    ];
    api.peersUnreadable = true;
    await provider.initAndSyncCatalog();
    expect(_hubCalls(ffi, api), 0);

    api.peersUnreadable = false;
    await provider.syncCatalogIfDirty();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(provider.isRegistered, isTrue);
    expect(ffi.registerCalls, greaterThan(0));
  });

  test('following a library from a fresh installation also creates the '
      'relay mailbox', () async {
    final (provider, ffi, api) = _build();
    // The user accepted the dialog shown before the action.
    await provider.recordOnlineServicesGrant();

    await provider.follow('some-library');

    expect(ffi.followCalls, 1);
    expect(api.relaySetups, 1);
  });

  test('publishing the library from a fresh installation creates the relay '
      'mailbox', () async {
    final (provider, ffi, api) = _build();
    // The user accepted the dialog shown before the action.
    await provider.recordOnlineServicesGrant();

    final ok = await provider.enableAndPublish(displayName: 'Test Library');

    expect(ok, isTrue);
    expect(api.relaySetups, 1);
    expect(ffi.registerCalls, greaterThan(0));
  });

  test('a registered installation whose mailbox is still being created '
      'waits for it at a gesture', () async {
    final (provider, ffi, api) = _build(registeredBefore: true);
    ffi.relayConfig = null;
    api.peers = [
      {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'peer-1'},
    ];
    api.relaySetupGate = Completer<void>();
    final startup = provider.initAndSyncCatalog();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(provider.isRegistered, isTrue);

    var returned = false;
    final gesture = provider.startOnlineServices().then((_) => returned = true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(returned, isFalse, reason: 'an invitation needs the mailbox');

    api.relaySetupGate!.complete();
    await gesture;
    await startup;
    expect(ffi.relayConfig, isNotNull);
  });

  test('a registered installation whose mailbox creation failed at startup '
      'gets it at the next gesture', () async {
    final (provider, ffi, api) = _build(registeredBefore: true);
    ffi.relayConfig = null;
    api.peers = [
      {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'peer-1'},
    ];
    await provider.loadConfig();

    await provider.startOnlineServices();

    expect(api.relaySetups, 1);
  });

  group('approving a follower', () {
    Future<String?> storedChoice() async =>
        (await SharedPreferences.getInstance()).getString(
          OnlineServicesConsent.prefKey,
        );

    test('by the owner is a choice: it is recorded', () async {
      // Nothing on the device says someone reads this catalog. Without the
      // record, leaving the directory later would freeze it for them.
      // The owner consents by use (the directory switch), never asked.
      final (provider, _, _) = _build(
        registeredBefore: true,
        prefs: {'hub_directory_enabled': true},
      );

      await provider.resolveFollow(1, 'approve', ownerGesture: true);

      expect(await storedChoice(), 'granted');
    });

    test('automatically, or a rejection, records nothing', () async {
      final (provider, _, _) = _build(registeredBefore: true);

      await provider.resolveFollow(1, 'approve', ownerGesture: false);
      await provider.resolveFollow(2, 'reject', ownerGesture: true);

      expect(await storedChoice(), isNull);
    });
  });

  group('without the yes of the dialog, a gesture sends nothing', () {
    // Every screen asks the question before the action. These are the
    // paths behind the screens: a caller that forgot to ask fails closed.
    Future<String?> storedChoice() async =>
        (await SharedPreferences.getInstance()).getString(
          OnlineServicesConsent.prefKey,
        );

    test('starting the online services', () async {
      final (provider, ffi, api) = _build();

      await provider.startOnlineServices();

      expect(_hubCalls(ffi, api), 0);
      expect(await storedChoice(), isNull);
    });

    test('following a library', () async {
      final (provider, ffi, api) = _build();

      expect(await provider.follow('some-library'), isFalse);

      expect(ffi.followCalls, 0);
      expect(_hubCalls(ffi, api), 0);
      expect(await storedChoice(), isNull);
    });

    test('approving a follower', () async {
      final (provider, ffi, api) = _build();

      final ok = await provider.resolveFollow(
        1,
        'approve',
        ownerGesture: true,
      );

      expect(ok, isFalse);
      expect(ffi.resolveCalls, 0);
      expect(_hubCalls(ffi, api), 0);
      expect(await storedChoice(), isNull);
    });

    test('publishing the library', () async {
      final (provider, ffi, api) = _build();

      final ok = await provider.enableAndPublish(displayName: 'Test Library');

      expect(ok, isFalse);
      expect(provider.isHubEnabled, isFalse);
      expect(_hubCalls(ffi, api), 0);
      expect(await storedChoice(), isNull);
    });

    test('turning the directory switch on', () async {
      final (provider, ffi, api) = _build();

      await provider.setHubEnabled(true);

      // The switch stands for a consent at the next launch: it stays off.
      expect(provider.isHubEnabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool('hub_directory_enabled'),
        isNot(true),
      );
      expect(_hubCalls(ffi, api), 0);
    });

    test('sharing the scores does not open the hub paths', () async {
      final (provider, ffi, api) = _build(
        prefs: {'shareGamificationStats': true},
      );

      await provider.initAndSyncCatalog();

      expect(await provider.onlineServicesAllowed(), isFalse);
      expect(_hubCalls(ffi, api), 0);
    });
  });

  group('the one-time notice (ADR-073 D3)', () {
    test('is for an installation that consents by use, never asked', () async {
      final (provider, _, _) = _build(prefs: {'hub_directory_enabled': true});
      expect(provider.onlineServicesInferred, isFalse, reason: 'not read yet');

      await provider.onlineServicesAllowed();

      expect(provider.onlineServicesInferred, isTrue);
    });

    test('not for one that answered the dialog', () async {
      final (provider, _, _) = _build(prefs: {'hub_directory_enabled': true});
      await provider.recordOnlineServicesGrant();

      await provider.onlineServicesAllowed();

      expect(provider.onlineServicesInferred, isFalse);
    });

    test('not for one that does not use the network', () async {
      final (provider, _, _) = _build();

      await provider.onlineServicesAllowed();

      expect(provider.onlineServicesInferred, isFalse);
    });
  });

  test('an accepted dialog holds at the next launch', () async {
    final (provider, ffi, _) = _build();
    await provider.recordOnlineServicesGrant();

    await provider.follow('some-library');

    expect(ffi.followCalls, 1);
    final (later, _, _) = _build(
      prefs: {
        OnlineServicesConsent.prefKey:
            (await SharedPreferences.getInstance()).getString(
              OnlineServicesConsent.prefKey,
            ) ??
            '',
      },
    );
    expect(
      await later.onlineServicesAllowed(),
      isTrue,
      reason: 'the next launch must not go silent on a library that follows',
    );
  });

  test('a user who already consents pays nothing at an invitation', () async {
    final (provider, ffi, api) = _build(registeredBefore: true);
    api.peers = [
      {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'peer-1'},
    ];
    await provider.initAndSyncCatalog();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final registrations = ffi.registerCalls;
    final pushes = ffi.catalogPushes;

    await provider.startOnlineServices();

    expect(ffi.registerCalls, registrations);
    expect(ffi.catalogPushes, pushes);
  });

  test('opening a screen does not rebuild a registration from the '
      'Keychain', () async {
    // After a reinstall the Keychain still holds the old write token.
    // Importing it writes a local registration row, which would make this
    // installation look "registered by an earlier build".
    final (provider, ffi, _) = _build();
    await AuthService().saveHubWriteToken('token-from-keychain');

    await provider.loadConfig();

    expect(ffi.writeTokenImports, 0);
    expect(provider.isRegistered, isFalse);
  });

  test('a gesture never waits longer than its bound on a silent hub', () async {
    final (provider, ffi, _) = _build();
    ffi.registrationGate = Completer<void>();
    // The user accepted the dialog shown before the action.
    await provider.recordOnlineServicesGrant();

    await provider.startOnlineServices(
      maxWait: const Duration(milliseconds: 50),
    );

    // The gesture got its hand back while the hub still has not answered.
    expect(ffi.registerCalls, 1);
    expect(ffi.registrationsFinished, 0);
    expect(
      await provider.onlineServicesAllowed(),
      isTrue,
      reason: 'the consent holds whatever the hub does',
    );

    ffi.registrationGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      ffi.registrationsFinished,
      greaterThan(0),
      reason: 'the run went on behind (registration, then relay publication)',
    );
  });

  test('a second gesture joins the run in progress instead of going on '
      'without a registration', () async {
    // A pairing gave up waiting after its bound; the user then creates an
    // invitation, which needs the mailbox the first run is still creating.
    final (provider, ffi, api) = _build();
    ffi.registrationGate = Completer<void>();
    // The user accepted the dialog shown before the action.
    await provider.recordOnlineServicesGrant();
    await provider.startOnlineServices(
      maxWait: const Duration(milliseconds: 20),
    );

    var secondReturned = false;
    final second = provider.startOnlineServices().then((_) {
      secondReturned = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(secondReturned, isFalse, reason: 'it waits for the run under way');

    ffi.registrationGate!.complete();
    await second;

    expect(provider.isRegistered, isTrue);
    expect(api.relaySetups, 1, reason: 'one mailbox, not one per gesture');
  });

  test('a gesture made while startup is deciding "no" still registers', () async {
    final (provider, ffi, _) = _build();
    final startup = provider.initAndSyncCatalog();

    // The user accepted the dialog while startup was still reading.
    await provider.recordOnlineServicesGrant();
    await provider.startOnlineServices();
    await startup;

    expect(provider.isRegistered, isTrue);
    expect(ffi.registerCalls, greaterThan(0));
  });

  test('a network action of the user opens the hub paths', () async {
    final (provider, ffi, api) = _build();
    expect(await provider.ensureRegistered(), isFalse);

    // The user accepted the dialog shown before the action.
    await provider.recordOnlineServicesGrant();
    await provider.startOnlineServices();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // What startup used to do without asking now follows the choice.
    expect(await provider.onlineServicesAllowed(), isTrue);
    expect(provider.isRegistered, isTrue);
    expect(api.relaySetups, 1, reason: 'the mailbox is created on consent');
    expect(ffi.registerCalls, greaterThan(0));
    expect(ffi.catalogPushes, greaterThan(0));
    expect(api.relayForgottenLocally, 0);
  });
}
