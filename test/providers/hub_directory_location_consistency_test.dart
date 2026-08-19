import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/city_repository.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test-1234';

  @override
  Future<String?> getAppVersion() async => '1.2.3';
}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  /// Optional canned local config. The provider reads it through
  /// hubDirectoryGetConfig at loadConfig() time to know its own nodeId
  /// and the latest is_listed flags.
  frb.FrbDirectoryConfig? existingConfig;

  /// Forces register() to fail (returns null) when set to false. Useful to
  /// drive the pending-flag persistence branch.
  bool registerOk = true;

  /// Every register() call is logged so tests can assert which fields were
  /// actually pushed to the hub (locationCountry, locationCityId, etc.).
  final List<frb.FrbRegisterParams> registerParamsLog = [];

  /// Probe responses keyed by cityId; returns empty if unstubbed.
  Map<int, List<frb.FrbHubProfile>> probeResults = const {};

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async =>
      const frb.FrbRelayConfig(
        relayUrl: 'wss://relay.example.com',
        mailboxUuid: 'mbx-1234',
        writeToken: 'wt-secret',
      );

  @override
  Future<int> countBooks() async => 42;

  @override
  Future<String?> getLocalX25519PublicKey() async => 'x25519-pubkey-hex';

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      existingConfig;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerParamsLog.add(params);
    if (!registerOk) return null;
    final next = frb.FrbDirectoryConfig(
      nodeId: params.nodeId,
      isListed: params.isListed,
      requiresApproval: params.requiresApproval,
      acceptFrom: params.acceptFrom,
      allowBorrowing: params.allowBorrowing,
    );
    existingConfig = next;
    return next;
  }

  @override
  Future<int> hubDirectorySyncCatalog() async => 0;

  @override
  Future<bool> hubDirectoryPurgeConfig() async => true;

  @override
  Future<String?> hubDirectoryExportWriteToken() async => 'write-token-hex';

  @override
  Future<List<frb.FrbHubProfile>> hubDirectoryList({
    required int limit,
    required int offset,
    String? search,
    String? country,
    int? cityId,
  }) async {
    if (cityId != null) return probeResults[cityId] ?? const [];
    return const [];
  }
}

CityRecord _city({
  required int id,
  required String country,
  String name = 'Colombes',
}) => CityRecord(
  id: id,
  country: country,
  name: name,
  admin1Code: '',
  admin1Name: '',
  admin2Code: '',
  admin2Name: '',
  latitude: 0,
  longitude: 0,
);

/// Builds a `lookupCity` stub that returns whatever the test plants in
/// [records] (keyed by GeoNames id). Defaults to no-op for unknown ids.
CityLookup _lookup(Map<int, CityRecord> records) {
  return (int id, {String? country}) async => records[id];
}

frb.FrbDirectoryConfig _config({
  String nodeId = 'me-self',
  bool isListed = true,
  bool requiresApproval = false,
  String acceptFrom = 'anyone',
  bool allowBorrowing = true,
}) {
  return frb.FrbDirectoryConfig(
    nodeId: nodeId,
    isListed: isListed,
    requiresApproval: requiresApproval,
    acceptFrom: acceptFrom,
    allowBorrowing: allowBorrowing,
  );
}

frb.FrbHubProfile _profile({
  required String nodeId,
  String country = 'FR',
  int cityId = 2988507,
}) => frb.FrbHubProfile(
  nodeId: nodeId,
  displayName: nodeId,
  bookCount: 1,
  locationCountry: country,
  locationCityId: cityId,
  requiresApproval: false,
);

Future<({HubDirectoryProvider provider, _MockFfiService ffi})> _setup({
  Map<String, Object> prefs = const {},
  Map<int, CityRecord> cities = const {},
  frb.FrbDirectoryConfig? existingConfig,
  bool registerOk = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'libraryName': 'TestLib',
    'languageCode': 'en',
    ...prefs,
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService()
    ..existingConfig = existingConfig
    ..registerOk = registerOk;
  final provider = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
    lookupCity: _lookup(cities),
  );
  return (provider: provider, ffi: ffi);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Group 1: country + city co-push contract (the root-cause fix)
  // -------------------------------------------------------------------------
  group('syncLocationCityId co-pushes country + city', () {
    test(
      'explicit country is forwarded to register alongside the city',
      () async {
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(nodeId: 'me-self'),
        );
        ffi.registerParamsLog.clear();

        final ok = await provider.syncLocationCityId(2988507, country: 'FR');

        expect(ok, isTrue);
        final params = ffi.registerParamsLog.last;
        expect(params.locationCityId, 2988507);
        expect(
          params.locationCountry,
          'FR',
          reason:
              'A city implies its country - pushing only city_id leaves the '
              'hub in an inconsistent state where country=NULL excludes the '
              'profile from country+city filters (asymmetry observed in '
              'production iPhone-vs-Mac flow).',
        );
      },
    );

    test(
      'falls back to CityRepository lookup when caller omits country',
      () async {
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(),
          cities: {2988507: _city(id: 2988507, country: 'FR')},
        );
        ffi.registerParamsLog.clear();

        await provider.syncLocationCityId(2988507);

        expect(
          ffi.registerParamsLog.last.locationCountry,
          'FR',
          reason:
              'The pending replay path has no caller to pass country - rely '
              'on the local city DB as a single source of truth.',
        );
      },
    );

    test(
      'lookup miss is graceful: city pushed without country (legacy mode)',
      () async {
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(),
          // no city in the lookup map: simulates a country file not yet on disk
          cities: const {},
        );
        ffi.registerParamsLog.clear();

        final ok = await provider.syncLocationCityId(2988507);

        expect(ok, isTrue);
        final params = ffi.registerParamsLog.last;
        expect(params.locationCityId, 2988507);
        expect(
          params.locationCountry,
          isNull,
          reason:
              'When the country cannot be derived, fall back to the legacy '
              'behavior (city only) instead of aborting the push - the hub '
              'preserves the existing country (Rust omits null fields from '
              'the JSON body).',
        );
      },
    );

    test('country is uppercased so picker output is canonical', () async {
      final (:provider, :ffi) = await _setup(existingConfig: _config());
      ffi.registerParamsLog.clear();

      await provider.syncLocationCityId(2988507, country: 'fr');

      expect(ffi.registerParamsLog.last.locationCountry, 'FR');
    });

    test(
      'clearing the city does NOT push country (preserves hub state)',
      () async {
        final (:provider, :ffi) = await _setup(existingConfig: _config());
        ffi.registerParamsLog.clear();

        // User toggled "Partager ma ville" off. They may still want to be
        // listed by country alone; the country must NOT be wiped from the hub
        // by the city-clear push.
        await provider.syncLocationCityId(null);

        final params = ffi.registerParamsLog.last;
        expect(params.locationCityId, isNull);
        expect(
          params.locationCountry,
          isNull,
          reason:
              'null locationCountry is omitted from the JSON body by Rust, '
              'so the hub-stored country survives the city clear.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 2: pending replay carries country
  // -------------------------------------------------------------------------
  group('pending replay carries country alongside city', () {
    test('failed push persists both city id and country for replay', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(),
        registerOk: false,
      );

      final ok = await provider.syncLocationCityId(2988507, country: 'FR');

      expect(ok, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hub_pending_location_city_id'), '2988507');
      expect(
        prefs.getString('hub_pending_location_city_country'),
        'FR',
        reason:
            'On replay we must re-push the same (city, country) pair we '
            'tried to push originally - falling back to a fresh lookup '
            'risks a different country if the picker has moved on.',
      );
    });

    test('replay forwards the stored country to register', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(nodeId: 'me-self'),
        prefs: const {
          'hub_pending_location_city_id': '2988507',
          'hub_pending_location_city_country': 'FR',
        },
      );
      ffi.registerParamsLog.clear();

      await provider.initAndSyncCatalog();

      final cityCalls = ffi.registerParamsLog
          .where((p) => p.locationCityId == 2988507)
          .toList();
      expect(cityCalls, isNotEmpty);
      expect(
        cityCalls.last.locationCountry,
        'FR',
        reason:
            'replay must restore the same country that was attempted at '
            'pick time - this is the path that closes the asymmetry bug '
            'where a deferred city push left location_country NULL forever',
      );
    });

    test(
      'legacy pending without country falls back to a fresh lookup',
      () async {
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(),
          cities: {2988507: _city(id: 2988507, country: 'FR')},
          // legacy format: only the city key, no country key
          prefs: const {'hub_pending_location_city_id': '2988507'},
        );
        ffi.registerParamsLog.clear();

        await provider.initAndSyncCatalog();

        final cityCalls = ffi.registerParamsLog
            .where((p) => p.locationCityId == 2988507)
            .toList();
        expect(
          cityCalls.last.locationCountry,
          'FR',
          reason:
              'Existing installs that pended a city pre-fix (no country key) '
              'must be remediated on the next cold start, not stuck forever.',
        );
      },
    );

    test('successful push clears both pending keys', () async {
      final (:provider, :ffi) = await _setup(existingConfig: _config());

      await provider.syncLocationCityId(2988507, country: 'FR');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('hub_pending_location_city_id'), isFalse);
      expect(prefs.containsKey('hub_pending_location_city_country'), isFalse);
    });

    test('clearing the city does not store a country pending key', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(),
        registerOk: false,
      );

      await provider.syncLocationCityId(null);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_pending_location_city_id'),
        '',
        reason: 'empty-string sentinel means "pending clear"',
      );
      expect(
        prefs.containsKey('hub_pending_location_city_country'),
        isFalse,
        reason:
            'clearing the city must not also stage a country change for '
            'the replay - country survives independently on the hub',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 3: init-time location remediation
  // -------------------------------------------------------------------------
  group('init-time remediation pushes country if local state diverges', () {
    test(
      'first cold start with a city pushes country and updates snapshot',
      () async {
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(nodeId: 'me-self'),
          cities: {2988507: _city(id: 2988507, country: 'FR')},
          prefs: const {'hub_local_location_city_id': 2988507},
          // no last-pushed snapshot: legacy install that registered city
          // without country before this fix shipped
        );
        ffi.registerParamsLog.clear();

        await provider.initAndSyncCatalog();

        final calls = ffi.registerParamsLog
            .where((p) => p.locationCityId == 2988507)
            .toList();
        expect(
          calls,
          isNotEmpty,
          reason:
              'remediation pass must re-push (city, country) when no '
              'snapshot is recorded - this is the path that fixes existing '
              'installs',
        );
        expect(calls.last.locationCountry, 'FR');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('hub_last_pushed_location_city_id'), 2988507);
        expect(
          prefs.getString('hub_last_pushed_location_city_country'),
          'FR',
          reason:
              'snapshot must be persisted post-success so subsequent cold '
              'starts skip the redundant push',
        );
      },
    );

    test(
      'uses the locally stored country hint when the city DB is cold',
      () async {
        // Cold-start scenario: the user opened the app, the country file
        // has not been downloaded yet (CityRepository lookup returns null),
        // but the picker stored the country alongside the city in
        // SharedPreferences. The remediation must use that hint instead of
        // skipping, otherwise legacy installs never converge.
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(nodeId: 'me-self'),
          cities: const {}, // CityRepository returns null
          prefs: const {
            'hub_local_location_city_id': 2988507,
            'hub_local_location_city_country': 'FR',
            'hub_share_city': true,
          },
        );
        ffi.registerParamsLog.clear();

        await provider.initAndSyncCatalog();

        final calls = ffi.registerParamsLog
            .where((p) => p.locationCityId == 2988507)
            .toList();
        expect(
          calls.last.locationCountry,
          'FR',
          reason:
              'Local country hint must short-circuit the (slow, possibly '
              'failing) CityRepository lookup so remediation works on the '
              'first cold start after upgrade',
        );
      },
    );

    test('idempotent when the snapshot already matches local state', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(nodeId: 'me-self'),
        cities: {2988507: _city(id: 2988507, country: 'FR')},
        prefs: const {
          'hub_local_location_city_id': 2988507,
          'hub_last_pushed_location_city_id': 2988507,
          'hub_last_pushed_location_city_country': 'FR',
        },
      );
      await provider.loadConfig();
      await provider.loadLocalCityId();

      final pushed = await provider.ensureLocationCityCountryConsistency();

      expect(
        pushed,
        isFalse,
        reason:
            'Steady state: zero hub call from the remediation method '
            'itself. Other paths (relay republish) still re-assert the '
            'cityId for preservation, but those are not "remediation" - '
            'they are the architecture-wide invariant. The remediation '
            'optimization (snapshot-skip) prevents an EXTRA dedicated '
            'push on every cold start (perf policy: intermittent '
            'network).',
      );
    });

    test(
      'lookup miss skips remediation rather than pushing without country',
      () async {
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(),
          // city in prefs but no country file loaded, no local hint either
          prefs: const {'hub_local_location_city_id': 2988507},
          cities: const {},
        );
        await provider.loadConfig();
        await provider.loadLocalCityId();
        ffi.registerParamsLog.clear();

        final pushed = await provider.ensureLocationCityCountryConsistency();

        expect(
          pushed,
          isFalse,
          reason:
              'Without a derivable country, the remediation method must '
              'NOT push city alone (that would recreate the bug). The '
              'cross-cutting register paths still re-assert their best '
              'effort, but the remediation itself stays silent.',
        );
      },
    );

    test('runs nothing when the user has no city set', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(),
        // no city in prefs, no last-pushed snapshot
      );
      final pre = ffi.registerParamsLog.length;

      await provider.initAndSyncCatalog();

      // Allow other init-time pushes (silent registration, relay republish)
      // but assert no city push happened.
      final cityCalls = ffi.registerParamsLog
          .skip(pre)
          .where((p) => p.locationCityId != null)
          .toList();
      expect(cityCalls, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Group 4: loadSameCityHighlight error stability
  // -------------------------------------------------------------------------
  group('loadSameCityHighlight keeps last good state on error', () {
    test('a thrown probe call leaves _sameCityProfiles untouched', () async {
      final ffi = _ThrowingFfi();
      SharedPreferences.setMockInitialValues({
        'hub_local_location_city_id': 2988507,
      });
      AuthService.storage = MockSecureStorage();

      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
        lookupCity: _lookup(const {}),
      );
      await provider.loadLocalCityId();

      // Plant a synthetic prior success.
      ffi.shouldThrow = false;
      ffi.next = [_profile(nodeId: 'peer-mac')];
      await provider.loadSameCityHighlight();
      expect(provider.sameCityProfiles, hasLength(1));

      // Now error.
      ffi.shouldThrow = true;
      await provider.loadSameCityHighlight();

      expect(
        provider.sameCityProfiles,
        hasLength(1),
        reason:
            'Probe errors are transient - clearing the state would make '
            'the banner flicker (observed cross-device while one peer was '
            'mid-sync). Keep the last successful snapshot until a NEW '
            'successful response replaces it.',
      );
    });

    test('a successful empty response IS allowed to clear the state', () async {
      final ffi = _ThrowingFfi();
      SharedPreferences.setMockInitialValues({
        'hub_local_location_city_id': 2988507,
      });
      AuthService.storage = MockSecureStorage();

      final provider = HubDirectoryProvider(
        ffi: ffi,
        deviceService: _MockDeviceService(),
        lookupCity: _lookup(const {}),
      );
      await provider.loadLocalCityId();

      ffi.next = [_profile(nodeId: 'peer-mac')];
      await provider.loadSameCityHighlight();
      expect(provider.sameCityProfiles, hasLength(1));

      // The peer left the hub or was unlisted. This is real data, not an
      // error - the banner SHOULD disappear.
      ffi.next = const [];
      await provider.loadSameCityHighlight();
      expect(
        provider.sameCityProfiles,
        isEmpty,
        reason:
            '0-results is a valid hub answer, not a transient failure - '
            'the banner correctly hides for "no peer in your city anymore"',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 5: setLocalCityId thread the country to the sync layer
  // -------------------------------------------------------------------------
  group('setLocalCityId propagates country', () {
    test(
      'country passed to setLocalCityId reaches syncLocationCityId',
      () async {
        // The picker calls setLocalCityId(picked.id, country: picked.country)
        // and then syncLocationCityId(picked.id, country: picked.country) -
        // the test is on the sync side: the country must travel as far as the
        // FFI register call.
        final (:provider, :ffi) = await _setup(existingConfig: _config());
        await provider.setLocalCityId(2988507, country: 'FR');
        ffi.registerParamsLog.clear();

        await provider.syncLocationCityId(2988507, country: 'FR');

        expect(ffi.registerParamsLog.last.locationCountry, 'FR');
        expect(ffi.registerParamsLog.last.locationCityId, 2988507);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Group 6: ANY register() caller re-asserts location_city_id (ADR-035 §8)
  //
  // The Rust serializer (build_register_body) ALWAYS includes
  // location_city_id in the JSON body, sending null when the param is None.
  // ADR-035 §8 picked this shape so toggling off "Partager ma ville" clears
  // the hub side immediately. The flip side: any register() call that
  // omits the cityId silently wipes the hub-stored value. This group nails
  // the invariant that every cross-cutting register path (relay, display
  // name, country picker, etc.) re-asserts the local cityId.
  //
  // Every fixture here sets `hub_share_city` because that is what the group
  // is about: a user who publishes their city. Since ADR-035 §3 was amended
  // the city is a local preference that exists without being published, so
  // re-asserting it now requires that consent. The complementary cases, "it
  // must NOT be re-asserted without consent", live in
  // hub_directory_local_city_test.dart.
  // -------------------------------------------------------------------------
  group('every register() path preserves location_city_id', () {
    test(
      '_pushDisplayName (rename) keeps the local cityId on the hub',
      () async {
        final (:provider, :ffi) = await _setup(
          existingConfig: _config(nodeId: 'me-self'),
          cities: {2988507: _city(id: 2988507, country: 'FR')},
          prefs: const {
            'hub_local_location_city_id': 2988507,
            'hub_local_location_city_country': 'FR',
            'hub_share_city': true,
          },
        );
        await provider.loadLocalCityId();
        ffi.registerParamsLog.clear();

        await provider.syncDisplayName('Bibliothèque Renommée');

        expect(ffi.registerParamsLog, isNotEmpty);
        // Check the rename push specifically - it carries the new display name.
        final renamePush = ffi.registerParamsLog
            .where((p) => p.displayName == 'Bibliothèque Renommée')
            .single;
        expect(
          renamePush.locationCityId,
          2988507,
          reason:
              'A rename must NOT clear the city - the Rust serializer wipes '
              'location_city_id on every register that omits it (ADR-035 §8 '
              'clear-on-toggle), so the renamer must re-assert local state.',
        );
        expect(
          renamePush.locationCountry,
          'FR',
          reason:
              'Same reason for country - omitting it would not wipe (Rust '
              'omits null country) but re-asserting keeps the snapshot in '
              'sync with the visible local state.',
        );
      },
    );

    test('_pushLocationCountry preserves the local cityId', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(nodeId: 'me-self'),
        cities: {2988507: _city(id: 2988507, country: 'FR')},
        prefs: const {
          'hub_local_location_city_id': 2988507,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
      );
      await provider.loadLocalCityId();
      ffi.registerParamsLog.clear();

      // User changes their public country (independent picker).
      await provider.syncLocationCountry('FR');

      expect(
        ffi.registerParamsLog.last.locationCityId,
        2988507,
        reason:
            'A country-only update must keep the city. Without this, the '
            'country picker silently wipes the city, defeating the whole '
            'V1 same-city banner.',
      );
    });

    test('ensureRelayPublished preserves the local cityId', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(nodeId: 'me-self'),
        cities: {2988507: _city(id: 2988507, country: 'FR')},
        prefs: const {
          'hub_local_location_city_id': 2988507,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
      );
      provider.relayRetryDelay = Duration.zero;
      provider.relayCooldown = Duration.zero;
      await provider.loadConfig();
      await provider.loadLocalCityId();
      ffi.registerParamsLog.clear();

      await provider.ensureRelayPublished();

      // ensureRelayPublished may make multiple attempts on failure; we only
      // assert that EVERY attempt carries the cityId, never zero.
      expect(ffi.registerParamsLog, isNotEmpty);
      for (final params in ffi.registerParamsLog) {
        expect(
          params.locationCityId,
          2988507,
          reason:
              'Relay republish runs at every cold start and on nudges - '
              'a missing cityId here causes the hub to wipe location_city_id '
              'on every app launch, observed in production logs as 6+ '
              'register_or_update calls in a few minutes that emptied the '
              'database between each user action.',
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Throwing FFI helper for the error-stability tests. Kept at the bottom so
// the main mocks above stay focused on the success / failure-by-flag paths.
// ---------------------------------------------------------------------------
class _ThrowingFfi extends FfiService {
  _ThrowingFfi() : super.forTest();

  bool shouldThrow = false;
  List<frb.FrbHubProfile> next = const [];

  @override
  Future<List<frb.FrbHubProfile>> hubDirectoryList({
    required int limit,
    required int offset,
    String? search,
    String? country,
    int? cityId,
  }) async {
    if (shouldThrow) throw Exception('hub-down');
    return next;
  }
}
