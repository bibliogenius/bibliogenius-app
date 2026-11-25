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
  /// When set, building a registration waits here, before anything is
  /// sent: a call that started but has not left yet.
  static Completer<void>? modelGate;

  @override
  Future<String?> getDeviceModel() async {
    await modelGate?.future;
    return 'TestDevice';
  }

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
  bool accountUnreadable = false;

  /// Every value the provider gave the Rust core's hub gate, in order.
  final hubContact = <bool>[];

  /// The gate as it stood when the last registration left.
  bool? hubContactAtRegistration;

  @override
  void setHubContactAllowed(bool allowed) => hubContact.add(allowed);

  /// Every withdrawal asked of the core: the ids named, and the gate as it
  /// stood when the call left.
  final withdrawals = <({String? nodeId, String? mailboxUuid, bool? gate})>[];

  /// What the core answers: 'done', 'pending', or an error code to throw.
  String withdrawalAnswer = 'done';

  @override
  Future<String> withdrawHubRegistration({
    String? nodeId,
    String? mailboxUuid,
  }) async {
    withdrawals.add((
      nodeId: nodeId,
      mailboxUuid: mailboxUuid,
      gate: hubContact.isEmpty ? null : hubContact.last,
    ));
    await withdrawalGate?.future;
    if (withdrawalAnswer == 'done') {
      directoryConfig = null;
      relayConfig = null;
      return 'done';
    }
    if (withdrawalAnswer == 'pending') return 'pending';
    if (withdrawalAnswer == 'unconfirmed') {
      // The core keeps nothing once the hub refused its credentials.
      directoryConfig = null;
      relayConfig = null;
      return 'unconfirmed';
    }
    throw StateError(withdrawalAnswer);
  }

  int registerCalls = 0;
  int catalogPushes = 0;
  int writeTokenImports = 0;
  /// When set, a registration waits here, like a hub that does not answer.
  Completer<void>? registrationGate;
  /// When set, the hub refuses the registration with this message.
  String? registrationError;
  int purges = 0;
  String? storedRecoveryCode;
  /// When set, a token recovery waits here.
  Completer<void>? recoverGate;
  int recoveries = 0;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRecover({
    required String nodeId,
    required String recoveryCode,
  }) async {
    recoveries++;
    await recoverGate?.future;
    throw Exception('Hub error 401: Invalid recovery code.');
  }

  @override
  Future<bool> hubDirectoryPurgeConfig() async {
    purges++;
    directoryConfig = null;
    return true;
  }
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
    await resolveGate?.future;
    return frb.FrbHubFollow(
      id: followId,
      followerNodeId: 'follower-1',
      followedNodeId: 'node-1',
      status: resolution == 'approve' ? 'active' : 'rejected',
      createdAt: '2026-01-01T00:00:00Z',
    );
  }

  int resolveCalls = 0;
  /// When set, the approval of a follower waits here.
  Completer<void>? resolveGate;
  /// When set, the core's withdrawal waits here.
  Completer<void>? withdrawalGate;

  // A private catalog is only pushed once its readers can be seen.
  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => const [];

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => relayConfig;

  @override
  Future<frb.FrbRelayConfig?> getRelayConfigStrict() async => relayConfig;

  @override
  Future<String> accountStatus() async {
    if (accountUnreadable) throw StateError('database busy');
    return '{"signed_in": $signedIn}';
  }

  @override
  Future<int> countBooks() async => 7;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<String?> hubDirectoryGetRecoveryCode() async => storedRecoveryCode;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerCalls++;
    hubContactAtRegistration = hubContact.isEmpty ? null : hubContact.last;
    await registrationGate?.future;
    if (registrationError != null) throw Exception(registrationError);
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

/// The same device at its next launch: a new provider over the same
/// preferences, local rows and Keychain.
HubDirectoryProvider _relaunch(_MockFfiService ffi, _MockApiService api) =>
    HubDirectoryProvider(
      ffi: ffi,
      deviceService: _MockDeviceService(),
      apiService: api,
    )..relayRetryDelay = Duration.zero;

const _aPeer = [
  {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'friend'},
];

int _hubCalls(_MockFfiService ffi, _MockApiService api) =>
    ffi.registerCalls + ffi.catalogPushes + api.relaySetups;

void main() {
  // This directory runs as a consenting installation by default
  // (flutter_test_config.dart); here the consent itself is under test.
  setUpAll(() {
    // ApiService.hubUrl reads the environment when a relay is set up.
    dotenv.testLoad();
  });
  setUp(() {
    OnlineServicesConsent.debugAlwaysAllowed = false;
    _MockDeviceService.modelGate = null;
  });
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

  // The Rust core sends to the hub on its own (relay deposits when a book
  // changes, relay poller, nudge listener). Its gate is closed at launch
  // and follows the consent read here.
  group('the hub gate of the Rust core', () {
    test('stays closed on an installation that never used the network', () async {
      final (provider, ffi, _) = _build();

      await provider.initAndSyncCatalog();

      expect(ffi.hubContact, isNotEmpty);
      expect(ffi.hubContact, everyElement(isFalse));
    });

    test('is closed on an installation an earlier build registered and that '
        'never used the network', () async {
      final (provider, ffi, _) = _build(registeredBefore: true);

      await provider.initAndSyncCatalog();

      expect(ffi.hubContact, everyElement(isFalse));
      expect(ffi.hubContact, isNotEmpty);
    });

    test('opens for an installation that uses the network', () async {
      final (provider, ffi, api) = _build(registeredBefore: true);
      api.peers = [
        {'id': 1, 'connection_status': 'accepted', 'library_uuid': 'friend'},
      ];

      await provider.initAndSyncCatalog();

      expect(ffi.hubContact.last, isTrue);
    });

    test('opens as soon as the dialog is accepted', () async {
      final (provider, ffi, _) = _build();
      expect(await provider.onlineServicesAllowed(), isFalse);
      expect(ffi.hubContact.last, isFalse);

      await provider.recordOnlineServicesGrant();

      expect(ffi.hubContact.last, isTrue);
    });

    test('is left alone when the device cannot be read', () async {
      // Not knowing is not a no: the gate of a paired user is never closed
      // by a database that was busy. At launch it is closed anyway.
      final (provider, ffi, api) = _build(registeredBefore: true);
      api.peersUnreadable = true;

      expect(await provider.onlineServicesAllowed(), isFalse);

      expect(ffi.hubContact, isEmpty);
    });

    test('is held open for a visibility setting of the owner, then closed '
        'again', () async {
      // Leaving the directory must reach the hub even when turning the
      // switch off has just ended the inferred consent.
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
      expect(ffi.hubContactAtRegistration, isTrue);
      expect(ffi.hubContact.last, isFalse);
    });
  });

  test('the hub gate of the Rust core does not stay open after a setting of '
      'the owner when the device cannot be read', () async {
    final (provider, ffi, api) = _build(registeredBefore: true);
    await provider.loadConfig();
    api.peersUnreadable = true;

    await provider.register(
      nodeId: 'node-1',
      displayName: 'Test Library',
      bookCount: 7,
      acceptFrom: 'everyone',
      isListed: false,
    );

    expect(ffi.hubContactAtRegistration, isTrue);
    expect(
      ffi.hubContact.last,
      isFalse,
      reason: 'not knowing must not leave the gate open',
    );
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

  group('withdrawing the registration (ADR-073 D4)', () {
    /// An installation that uses the hub: registered, with a mailbox and a
    /// peer, never asked (its consent is inferred).
    Future<(HubDirectoryProvider, _MockFfiService, _MockApiService)>
    consenting({Map<String, Object> prefs = const {}}) async {
      final (provider, ffi, api) = _build(
        registeredBefore: true,
        prefs: prefs,
      );
      api.peers = _aPeer;
      await provider.initAndSyncCatalog();
      await Future<void>.delayed(Duration.zero);
      expect(await provider.onlineServicesAllowed(), isTrue);
      return (provider, ffi, api);
    }

    test('goes silent first, then asks the core to delete this '
        'registration', () async {
      final (provider, ffi, api) = await consenting();
      await AuthService().saveHubWriteToken('kept-for-a-reinstall');
      await AuthService().saveHubRecoveryCode('rc-1');

      final result = await provider.withdrawOnlineServices();

      expect(result, HubWithdrawal.done);
      expect(ffi.withdrawals, hasLength(1));
      expect(ffi.withdrawals.single.nodeId, 'node-1');
      expect(ffi.withdrawals.single.mailboxUuid, 'mbx-old');
      expect(
        ffi.withdrawals.single.gate,
        isFalse,
        reason: 'the gate is closed before the deletion is asked',
      );
      expect(ffi.hubContact.last, isFalse);
      expect(provider.onlineServicesKnownAllowed, isFalse);
      expect(provider.isRegistered, isFalse);
      expect(provider.hubRemovalPending, isFalse);
      expect(await AuthService().getHubWriteToken(), isNull);
      expect(await AuthService().getHubRecoveryCode(), isNull);
    });

    test('an inferred consent is withdrawn at once, not at the next '
        'launch, and the directory switch goes off', () async {
      final (provider, ffi, api) = await consenting(
        prefs: {'hub_directory_enabled': true},
      );
      await provider.loadHubEnabled();
      expect(provider.isHubEnabled, isTrue);
      final callsBefore = _hubCalls(ffi, api);

      await provider.withdrawOnlineServices();

      expect(await provider.onlineServicesAllowed(), isFalse);
      expect(provider.isHubEnabled, isFalse);
      // What the app does on its own afterwards.
      await provider.initAndSyncCatalog();
      await provider.loadConfig();
      await provider.ensureKeysPublished('Test Library');
      await provider.syncCatalogIfDirty();
      await provider.startOnlineServices();
      await Future<void>.delayed(Duration.zero);
      expect(_hubCalls(ffi, api), callsBefore);
      expect(ffi.hubContact.last, isFalse);
    });

    test('a hub that does not answer: silent all the same, and the '
        'deletion is tried again at the next launches', () async {
      final (provider, ffi, api) = await consenting();
      ffi.withdrawalAnswer = 'pending';
      final callsBefore = _hubCalls(ffi, api);

      expect(await provider.withdrawOnlineServices(), HubWithdrawal.pending);
      expect(provider.hubRemovalPending, isTrue);
      expect(await provider.onlineServicesAllowed(), isFalse);

      // Next launch, hub still silent: one more try, nothing else.
      final second = _relaunch(ffi, api);
      await second.initAndSyncCatalog();
      await second.syncCatalogIfDirty();
      expect(
        ffi.withdrawals,
        hasLength(2),
        reason: 'one try per launch, not one per lifecycle hook',
      );
      expect(ffi.withdrawals.map((w) => w.nodeId).toSet(), {'node-1'});
      expect(ffi.withdrawals.every((w) => w.gate == false), isTrue);
      expect(_hubCalls(ffi, api), callsBefore);
      expect(
        api.relayForgottenLocally,
        0,
        reason: 'the relay row holds the token of the pending deletion',
      );

      // The hub is back.
      ffi.withdrawalAnswer = 'done';
      final third = _relaunch(ffi, api);
      await third.initAndSyncCatalog();
      expect(third.hubRemovalPending, isFalse);
      final tries = ffi.withdrawals.length;

      // And then nothing is tried any more.
      final fourth = _relaunch(ffi, api);
      await fourth.initAndSyncCatalog();
      await fourth.syncCatalogIfDirty();
      expect(ffi.withdrawals, hasLength(tries));
      expect(_hubCalls(ffi, api), callsBefore);
    });

    test('rows a restored backup brings back are dropped without being '
        'named to the hub', () async {
      final (provider, ffi, api) = await consenting();
      await provider.withdrawOnlineServices();
      // A "replace" restore: the archive's rows are back, the withdrawal
      // (not part of the backup) still stands.
      ffi
        ..directoryConfig = _registered
        ..relayConfig = _relay;
      await OnlineServicesConsent.forgetSilence();
      final callsBefore = _hubCalls(ffi, api);

      final next = _relaunch(ffi, api);
      await next.initAndSyncCatalog();

      expect(await next.onlineServicesAllowed(), isFalse);
      expect(ffi.withdrawals.last.nodeId, isNull);
      expect(ffi.withdrawals.last.mailboxUuid, isNull);
      expect(ffi.directoryConfig, isNull);
      expect(_hubCalls(ffi, api), callsBefore);
      expect(ffi.hubContact.last, isFalse);
    });

    test('is refused while an encrypted account is on this device, and '
        'changes nothing', () async {
      final (provider, ffi, api) = await consenting();
      ffi.signedIn = true;

      final result = await provider.withdrawOnlineServices();

      expect(result, HubWithdrawal.accountSignedIn);
      expect(ffi.withdrawals, isEmpty);
      expect(await provider.onlineServicesAllowed(), isTrue);
      expect(provider.isRegistered, isTrue);
    });

    test('changes nothing when the device cannot be read', () async {
      final (provider, ffi, api) = await consenting();
      ffi.accountUnreadable = true;

      final result = await provider.withdrawOnlineServices();

      expect(result, HubWithdrawal.failed);
      expect(ffi.withdrawals, isEmpty);
      expect(await provider.onlineServicesAllowed(), isTrue);
    });

    test('waits for a hub call in progress before asking for the '
        'deletion', () async {
      // A registration that arrives after the deletion would create the
      // profile again on the hub.
      final (provider, ffi, api) = _build(
        prefs: {'online_services_consent': 'granted'},
      );
      ffi.registrationGate = Completer<void>();
      unawaited(provider.initAndSyncCatalog());
      await Future<void>.delayed(Duration.zero);
      expect(ffi.registerCalls, 1);

      final withdrawing = provider.withdrawOnlineServices();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ffi.withdrawals, isEmpty, reason: 'the registration still runs');
      expect(ffi.hubContact.last, isFalse, reason: 'but the gate is closed');

      ffi.registrationGate!.complete();
      expect(await withdrawing, HubWithdrawal.done);
      expect(
        ffi.withdrawals.single.nodeId,
        isNotNull,
        reason: 'the registration that just finished is the one deleted',
      );
      expect(ffi.registerCalls, 1, reason: 'the run stopped there');
    });

    test('a visibility setting no longer goes through once withdrawn', () async {
      final (provider, ffi, api) = await consenting();
      await provider.withdrawOnlineServices();
      final registrations = ffi.registerCalls;
      final gateBefore = ffi.hubContact.length;

      final sent = await provider.register(
        nodeId: 'node-1',
        displayName: 'Test Library',
        bookCount: 7,
        acceptFrom: 'everyone',
        isListed: true,
      );

      expect(sent, isFalse);
      expect(ffi.registerCalls, registrations);
      expect(
        ffi.hubContact.skip(gateBefore),
        isNot(contains(true)),
        reason: 'the gate is not held open for a setting any more',
      );
    });

    test('a yes given later lifts the withdrawal', () async {
      final (provider, ffi, api) = await consenting();
      ffi.withdrawalAnswer = 'pending';
      await provider.withdrawOnlineServices();

      await provider.recordOnlineServicesGrant();

      expect(await provider.onlineServicesAllowed(), isTrue);
      expect(provider.hubRemovalPending, isFalse);
      expect(ffi.hubContact.last, isTrue);
      final tries = ffi.withdrawals.length;
      await provider.syncCatalogIfDirty();
      expect(ffi.withdrawals, hasLength(tries), reason: 'no deletion after a yes');
    });
    test('a setting of the owner on its way does not hold the gate open, '
        'and the deletion waits for it', () async {
      final (provider, ffi, api) = await consenting();
      ffi.registrationGate = Completer<void>();
      final setting = provider.register(
        nodeId: 'node-1',
        displayName: 'Test Library',
        bookCount: 7,
        acceptFrom: 'everyone',
        isListed: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(ffi.hubContact.last, isTrue, reason: 'held open for the setting');

      final withdrawing = provider.withdrawOnlineServices();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ffi.hubContact.last, isFalse, reason: 'closed all the same');
      expect(ffi.withdrawals, isEmpty, reason: 'the setting still runs');

      ffi.registrationGate!.complete();
      await setting;
      expect(await withdrawing, HubWithdrawal.done);
      expect(ffi.hubContact.last, isFalse);
      expect(ffi.withdrawals.single.gate, isFalse);
    });

    test('a mailbox being created is waited for, then deleted with the '
        'rest', () async {
      final (provider, ffi, api) = _build(
        prefs: {'online_services_consent': 'granted'},
      );
      await provider.initAndSyncCatalog();
      // The Connect button of the settings, on its way.
      api.relaySetupGate = Completer<void>();
      final creating = provider.trackHubWrite(
        api.setupRelay(relayUrl: 'https://hub.example.org'),
      );

      final withdrawing = provider.withdrawOnlineServices();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ffi.withdrawals, isEmpty);

      api.relaySetupGate!.complete();
      await creating;
      expect(await withdrawing, HubWithdrawal.done);
      expect(ffi.withdrawals.single.mailboxUuid, 'mbx-new');
    });

    test('a yes given while a withdrawal runs waits for it, then stands', () async {
      final (provider, ffi, api) = await consenting();
      ffi.withdrawalGate = Completer<void>();
      final withdrawing = provider.withdrawOnlineServices();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ffi.withdrawals, hasLength(1));

      final granting = provider.recordOnlineServicesGrant();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        await provider.onlineServicesAllowed(),
        isFalse,
        reason: 'the yes is not written in the middle of the deletion',
      );

      ffi.withdrawalGate!.complete();
      expect(await withdrawing, HubWithdrawal.done);
      await granting;
      expect(await provider.onlineServicesAllowed(), isTrue);
      expect(provider.hubRemovalPending, isFalse);
      // Nothing deletes the registration the yes is about to make.
      await provider.syncCatalogIfDirty();
      await provider.initAndSyncCatalog();
      expect(ffi.withdrawals, hasLength(1));
    });

    test('an approval on its way when the owner withdraws does not write '
        'a yes', () async {
      final (provider, ffi, api) = await consenting();
      ffi.resolveGate = Completer<void>();
      final approving = provider.resolveFollow(
        12,
        'approve',
        ownerGesture: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await provider.withdrawOnlineServices(), HubWithdrawal.done);
      ffi.resolveGate!.complete();
      await approving;

      expect(await provider.onlineServicesAllowed(), isFalse);
      expect(ffi.hubContact.last, isFalse);
    });

    test('a core that fails after the withdrawal is written leaves a '
        'deletion to try again, not a dead end', () async {
      final (provider, ffi, api) = await consenting();
      ffi.withdrawalAnswer = 'database error: busy';

      expect(await provider.withdrawOnlineServices(), HubWithdrawal.pending);
      expect(provider.hubRemovalPending, isTrue);
      expect(await provider.onlineServicesAllowed(), isFalse);

      ffi.withdrawalAnswer = 'done';
      final next = _relaunch(ffi, api);
      await next.initAndSyncCatalog();
      expect(next.hubRemovalPending, isFalse);
      expect(ffi.withdrawals.last.nodeId, 'node-1');
    });

    test('an account only the core sees: refused, and the choice the user '
        'had is put back', () async {
      final (provider, ffi, api) = await consenting(
        prefs: {'hub_directory_enabled': true},
      );
      await provider.loadHubEnabled();
      ffi.withdrawalAnswer = 'account_signed_in';

      final result = await provider.withdrawOnlineServices();

      expect(result, HubWithdrawal.accountSignedIn);
      expect(
        provider.isHubEnabled,
        isTrue,
        reason: 'nothing changed: the switch is back on too',
      );
      expect(await provider.onlineServicesAllowed(), isTrue);
      expect(provider.hubRemovalPending, isFalse);
      expect(ffi.hubContact.last, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(OnlineServicesConsent.prefKey), isNull);
      expect(
        prefs.getString(OnlineServicesConsent.removalPendingPrefKey),
        isNull,
      );
    });

    test('registering again in the same session pushes the catalog '
        'again', () async {
      final (provider, ffi, api) = await consenting();
      await provider.syncCatalogIfDirty();
      await Future<void>.delayed(Duration.zero);
      await provider.withdrawOnlineServices();
      final pushes = ffi.catalogPushes;
      final setups = api.relaySetups;

      await provider.recordOnlineServicesGrant();
      await provider.startOnlineServices();
      await Future<void>.delayed(Duration.zero);

      expect(provider.isRegistered, isTrue);
      expect(ffi.catalogPushes, greaterThan(pushes));
      expect(
        api.relaySetups,
        greaterThan(setups),
        reason: 'the mailbox the hub deleted is created again',
      );
      expect(ffi.relayConfig, isNotNull);
    });
    test('a yes given while a pending deletion is being tried again waits '
        'for it', () async {
      final (provider, ffi, api) = await consenting();
      ffi.withdrawalAnswer = 'pending';
      await provider.withdrawOnlineServices();

      // Next launch: the deletion is tried again, and the hub is slow.
      final next = _relaunch(ffi, api);
      ffi
        ..withdrawalAnswer = 'done'
        ..withdrawalGate = Completer<void>();
      final launching = next.initAndSyncCatalog();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ffi.withdrawals, hasLength(2), reason: 'the retry is in the core');

      final granting = next.recordOnlineServicesGrant();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        await next.onlineServicesAllowed(),
        isFalse,
        reason: 'a yes written now would be followed by the deletion',
      );

      ffi.withdrawalGate!.complete();
      await launching;
      await granting;
      expect(await next.onlineServicesAllowed(), isTrue);
      expect(next.hubRemovalPending, isFalse);
      await next.syncCatalogIfDirty();
      expect(ffi.withdrawals, hasLength(2), reason: 'nothing deletes after it');
    });

    test('a registration the hub refuses (401) while the withdrawal runs '
        'does not throw the local registration away', () async {
      // That row holds the token and the recovery code the core deletes
      // with: purged, the core would find nothing and call it done.
      final (provider, ffi, api) = await consenting();
      ffi
        ..registrationGate = Completer<void>()
        ..registrationError = 'Hub error 401: unauthorized';
      final setting = provider.register(
        nodeId: 'node-1',
        displayName: 'Test Library',
        bookCount: 7,
        acceptFrom: 'everyone',
        isListed: true,
      );
      await Future<void>.delayed(Duration.zero);
      final registrations = ffi.registerCalls;

      final withdrawing = provider.withdrawOnlineServices();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ffi.registrationGate!.complete();

      expect(await setting, isFalse);
      expect(await withdrawing, HubWithdrawal.done);
      expect(ffi.purges, 0);
      expect(ffi.registerCalls, registrations, reason: 'no fresh registration');
      expect(ffi.withdrawals.single.nodeId, 'node-1');
    });

    test('a registration that was being prepared when the user withdrew '
        'never leaves', () async {
      final (provider, ffi, api) = await consenting();
      final registrations = ffi.registerCalls;
      _MockDeviceService.modelGate = Completer<void>();
      // Passed the first check, has not reached the hub yet.
      final setting = provider.register(
        nodeId: 'node-1',
        displayName: 'Test Library',
        bookCount: 7,
        acceptFrom: 'everyone',
        isListed: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(await provider.withdrawOnlineServices(), HubWithdrawal.done);
      _MockDeviceService.modelGate!.complete();

      expect(await setting, isFalse);
      expect(ffi.registerCalls, registrations);
      expect(ffi.hubContact.last, isFalse);
    });
    test('the user withdraws while a refused token is being recovered: the '
        'local registration is still not thrown away', () async {
      final (provider, ffi, api) = await consenting();
      ffi
        ..storedRecoveryCode = 'rc-1'
        ..registrationError = 'Hub error 401: unauthorized'
        ..recoverGate = Completer<void>();
      final renaming = provider.register(
        nodeId: 'node-1',
        displayName: 'Test Library',
        bookCount: 7,
        acceptFrom: 'everyone',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ffi.recoveries, 1, reason: 'the recovery is on its way');

      final withdrawing = provider.withdrawOnlineServices();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ffi.withdrawals, isEmpty, reason: 'the deletion waits for it');
      ffi.recoverGate!.complete();

      expect(await renaming, isFalse);
      expect(await withdrawing, HubWithdrawal.done);
      expect(ffi.purges, 0);
      expect(ffi.withdrawals.single.nodeId, 'node-1');
    });

    test('an approval that comes back in the middle of a withdrawal does '
        'not write a yes', () async {
      final (provider, ffi, api) = await consenting();
      ffi
        ..resolveGate = Completer<void>()
        ..withdrawalGate = Completer<void>();
      final approving = provider.resolveFollow(
        12,
        'approve',
        ownerGesture: true,
      );
      await Future<void>.delayed(Duration.zero);
      final withdrawing = provider.withdrawOnlineServices();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The hub answers the approval while the deletion is being asked.
      ffi.resolveGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      ffi.withdrawalGate!.complete();
      expect(await withdrawing, HubWithdrawal.done);
      await approving;

      expect(await provider.onlineServicesAllowed(), isFalse);
    });

    test('a hub that refuses the credentials of this device: said so, for '
        'good, and never asked again', () async {
      final (provider, ffi, api) = await consenting();
      ffi.withdrawalAnswer = 'unconfirmed';

      final result = await provider.withdrawOnlineServices();

      expect(result, HubWithdrawal.unconfirmed);
      expect(provider.hubRemovalUnconfirmed, isTrue);
      expect(provider.hubRemovalPending, isFalse);
      expect(await provider.onlineServicesAllowed(), isFalse);

      // Next launches: the state is still shown, nothing is asked again.
      ffi.directoryConfig = null;
      ffi.relayConfig = null;
      final next = _relaunch(ffi, api);
      await next.initAndSyncCatalog();
      await next.syncCatalogIfDirty();
      expect(next.hubRemovalUnconfirmed, isTrue);
      expect(ffi.withdrawals, hasLength(1));

      // A yes given later clears it.
      await next.recordOnlineServicesGrant();
      expect(next.hubRemovalUnconfirmed, isFalse);
    });
  });
}
