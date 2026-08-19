// The city is a LOCAL preference (ADR-035 §3, amended): the user fills it in
// whether or not they publish it, and the "share my city" toggle governs the
// outbound copy only.
//
// Two invariants are load-bearing and asserted here, because breaking either
// one is silent:
//
//   1. Filling in a city locally must NEVER reach the hub. The danger is not
//      the picker (which pushes explicitly) but `_currentLocationForRegister`:
//      every cross-cutting `register()` caller (relay publish, rename, country
//      change) re-asserts the location, and `initAndSyncCatalog` runs on every
//      cold start. Without a gate, a purely local city would be published on
//      the next app launch with no user gesture at all.
//
//   2. Opting out of sharing must stop the publication without erasing the
//      user's own city. Before the amendment the two were cleared in lockstep,
//      which is exactly the coupling this change removes.
//
// The backfill group covers the reverse direction: a device that never picked
// the city locally must adopt it from its own hub profile. That is not just
// migration politeness. `location_city_id` is always serialized (null when
// absent, see hub_directory_service.rs build_register_body), so a second
// device with an empty local value WIPES the hub city on its next register.

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

  frb.FrbDirectoryConfig? existingConfig;

  /// Own hub profile returned by [hubDirectoryGetProfile]. `null` models a
  /// hub that has never seen this node (or is unreachable): FfiService
  /// swallows transport errors and returns null, so the two are
  /// indistinguishable to the provider.
  frb.FrbHubProfile? ownProfile;

  /// Counts the profile probes so tests can assert the backfill costs one
  /// hub round-trip per install rather than one per app launch.
  int getProfileCalls = 0;

  /// Every register() call is logged so tests can assert exactly which
  /// location fields were pushed.
  final List<frb.FrbRegisterParams> registerParamsLog = [];

  @override
  Future<frb.FrbRelayConfig?> getRelayConfig() async => const frb.FrbRelayConfig(
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
  Future<frb.FrbHubProfile?> hubDirectoryGetProfile(String nodeId) async {
    getProfileCalls++;
    return ownProfile;
  }

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryRegister(
    frb.FrbRegisterParams params,
  ) async {
    registerParamsLog.add(params);
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
  Future<String?> hubDirectoryExportWriteToken() async => 'write-token-hex';

  @override
  Future<List<frb.FrbHubProfile>> hubDirectoryList({
    required int limit,
    required int offset,
    String? search,
    String? country,
    int? cityId,
  }) async => const [];
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const int _kParis = 2988507;
const int _kColombes = 2996944;

CityRecord _city({required int id, required String country}) => CityRecord(
  id: id,
  country: country,
  name: 'City-$id',
  admin1Code: '',
  admin1Name: '',
  admin2Code: '',
  admin2Name: '',
  latitude: 0,
  longitude: 0,
);

CityLookup _lookup(Map<int, CityRecord> records) =>
    (int id, {String? country}) async => records[id];

frb.FrbDirectoryConfig _config({String nodeId = 'me-self', bool isListed = true}) =>
    frb.FrbDirectoryConfig(
      nodeId: nodeId,
      isListed: isListed,
      requiresApproval: false,
      acceptFrom: 'anyone',
      allowBorrowing: true,
    );

frb.FrbHubProfile _hubProfile({int? cityId, String? country = 'FR'}) =>
    frb.FrbHubProfile(
      nodeId: 'me-self',
      displayName: 'TestLib',
      bookCount: 1,
      locationCountry: country,
      locationCityId: cityId,
      requiresApproval: false,
    );

Future<({HubDirectoryProvider provider, _MockFfiService ffi})> _setup({
  Map<String, Object> prefs = const {},
  Map<int, CityRecord> cities = const {},
  frb.FrbDirectoryConfig? existingConfig,
  frb.FrbHubProfile? ownProfile,
}) async {
  SharedPreferences.setMockInitialValues({
    'libraryName': 'TestLib',
    'languageCode': 'en',
    ...prefs,
  });
  AuthService.storage = MockSecureStorage();

  final ffi = _MockFfiService()
    ..existingConfig = existingConfig
    ..ownProfile = ownProfile;
  final provider =
      HubDirectoryProvider(
          ffi: ffi,
          deviceService: _MockDeviceService(),
          lookupCity: _lookup(cities),
        )
        ..relayRetryDelay = Duration.zero
        ..relayCooldown = Duration.zero;
  return (provider: provider, ffi: ffi);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Group 1: a local city is never published without the share toggle
  // -------------------------------------------------------------------------
  group('local city stays local while share-city is off', () {
    test('a cross-cutting register omits the city', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
          // hub_share_city absent: the user filled in their city but never
          // opted into publishing it.
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();
      ffi.registerParamsLog.clear();

      await provider.syncDisplayName('Renamed library');

      expect(ffi.registerParamsLog, isNotEmpty);
      expect(
        ffi.registerParamsLog.last.locationCityId,
        isNull,
        reason:
            'a rename must not smuggle the local city to the hub; the share '
            'toggle is the only authorisation to publish it',
      );
      expect(
        provider.localCityId,
        _kParis,
        reason: 'gating the outbound copy must not touch the local value',
      );
    });

    test('relay publish omits the city too', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();
      ffi.registerParamsLog.clear();

      await provider.ensureRelayPublished();

      expect(ffi.registerParamsLog, isNotEmpty);
      expect(
        ffi.registerParamsLog.every((p) => p.locationCityId == null),
        isTrue,
        reason:
            'ensureRelayPublished runs on every cold start; it is the path '
            'that would silently publish an unshared city',
      );
    });

    test('the city IS re-asserted once the user opts in', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();
      ffi.registerParamsLog.clear();

      await provider.syncDisplayName('Renamed library');

      final params = ffi.registerParamsLog.last;
      expect(
        params.locationCityId,
        _kParis,
        reason:
            'the pre-existing state-preservation contract must survive: a '
            'rename may not wipe the city of a user who shares it',
      );
      expect(params.locationCountry, 'FR');
    });

    test('the gate reads the persisted toggle, not the in-memory default', () async {
      // register() fires from paths that never went through loadShareCity()
      // (flash rename at first run, network screen registration). Reading the
      // unloaded field would default to false and wipe the hub city of a user
      // who did opt in.
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadLocalCityId();
      // Deliberately NOT calling loadShareCity().
      expect(provider.isShareCityEnabled, isFalse);
      ffi.registerParamsLog.clear();

      await provider.syncDisplayName('Renamed library');

      expect(
        ffi.registerParamsLog.last.locationCityId,
        _kParis,
        reason:
            'the outbound gate must consult SharedPreferences so it is '
            'independent of provider load order',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 1bis: leaving the directory withdraws the city with it
  //
  // The settings screen calls setShareCity(false) when the user un-lists.
  // This asserts the consequence that matters: once the consent is gone, no
  // later register re-publishes the city, on an unlisted profile or any
  // other. The gate deliberately does not read `isListed` itself - see the
  // note in _currentLocationForRegister.
  // -------------------------------------------------------------------------
  group('withdrawing from the directory stops republishing the city', () {
    test('an unlisted profile carries no city on later registers', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(isListed: true),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      // What _toggleDirectoryListing does when the user leaves the directory.
      await provider.setShareCity(false);
      ffi.registerParamsLog.clear();

      await provider.ensureRelayPublished();

      expect(ffi.registerParamsLog, isNotEmpty);
      expect(
        ffi.registerParamsLog.every((p) => p.locationCityId == null),
        isTrue,
        reason:
            'un-listing must end the publication for good, including on the '
            'cold-start relay republish that runs behind the user back',
      );
      expect(
        provider.localCityId,
        _kParis,
        reason: 'and it still must not erase the local value',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 2: opting out stops the publication, it does not erase the city
  // -------------------------------------------------------------------------
  group('opting out of sharing keeps the local city', () {
    test('setShareCity(false) leaves localCityId untouched', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      await provider.setShareCity(false);

      expect(provider.isShareCityEnabled, isFalse);
      expect(
        provider.localCityId,
        _kParis,
        reason:
            'the city is the user own data; withdrawing it from the public '
            'profile must not delete it from the device',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('hub_local_location_city_id'), _kParis);
    });

    test('and stops publishing it on the next register', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      await provider.setShareCity(false);
      ffi.registerParamsLog.clear();
      await provider.syncDisplayName('Renamed library');

      expect(
        ffi.registerParamsLog.last.locationCityId,
        isNull,
        reason:
            'un-listing from the directory must not keep publishing the city '
            'through the back door of a routine profile update',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 3: backfill from the hub profile
  // -------------------------------------------------------------------------
  group('adoptHubCityIfLocalEmpty', () {
    test('adopts the hub city when the device has none', () async {
      final (:provider, :ffi) = await _setup(
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
        ownProfile: _hubProfile(cityId: _kParis, country: 'FR'),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();
      expect(provider.localCityId, isNull);

      final adopted = await provider.adoptHubCityIfLocalEmpty();

      expect(adopted, isTrue);
      expect(provider.localCityId, _kParis);
      expect(
        provider.isShareCityEnabled,
        isTrue,
        reason:
            'the city was already public on this profile; leaving the toggle '
            'off would make the next register wipe it, silently un-sharing '
            'something the user had opted into',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('hub_local_location_city_country'), 'FR');
    });

    test('never overwrites a city already picked on this device', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kColombes,
          'hub_local_location_city_country': 'FR',
        },
        cities: {
          _kParis: _city(id: _kParis, country: 'FR'),
          _kColombes: _city(id: _kColombes, country: 'FR'),
        },
        existingConfig: _config(),
        ownProfile: _hubProfile(cityId: _kParis, country: 'FR'),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      final adopted = await provider.adoptHubCityIfLocalEmpty();

      expect(adopted, isFalse);
      expect(
        provider.localCityId,
        _kColombes,
        reason: 'the local pick is the source of truth, the hub is the mirror',
      );
      expect(
        provider.isShareCityEnabled,
        isFalse,
        reason: 'a skipped backfill must not flip the sharing consent either',
      );
    });

    test('does nothing when the hub profile carries no city', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(),
        ownProfile: _hubProfile(cityId: null),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      final adopted = await provider.adoptHubCityIfLocalEmpty();

      expect(adopted, isFalse);
      expect(provider.localCityId, isNull);
      expect(provider.isShareCityEnabled, isFalse);
    });

    test('does nothing when the hub profile cannot be read', () async {
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(),
        ownProfile: null,
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      final adopted = await provider.adoptHubCityIfLocalEmpty();

      expect(adopted, isFalse);
      expect(provider.localCityId, isNull);
    });

    test('is idempotent: a second pass adopts nothing', () async {
      final (:provider, :ffi) = await _setup(
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
        ownProfile: _hubProfile(cityId: _kParis, country: 'FR'),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      expect(await provider.adoptHubCityIfLocalEmpty(), isTrue);
      expect(await provider.adoptHubCityIfLocalEmpty(), isFalse);
      expect(provider.localCityId, _kParis);
    });

    test('probes the hub once per install, not once per launch', () async {
      // The overwhelming majority of users never pick a city (sharing is
      // opt-in and off by default), so they are precisely the ones who would
      // pay this probe on every cold start. One round-trip per install.
      final (:provider, :ffi) = await _setup(
        existingConfig: _config(),
        ownProfile: _hubProfile(cityId: null),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      expect(await provider.adoptHubCityIfLocalEmpty(), isFalse);
      expect(await provider.adoptHubCityIfLocalEmpty(), isFalse);
      expect(await provider.adoptHubCityIfLocalEmpty(), isFalse);

      expect(
        ffi.getProfileCalls,
        1,
        reason:
            'a nothing-to-adopt answer is final; re-asking on every launch '
            'is a network cost paid by the users who need it least',
      );
    });

    test('retries on a later launch when the profile could not be read', () async {
      // FfiService swallows transport errors into a null profile, so "no
      // profile" and "hub unreachable" look identical. Burning the one shot
      // on an offline first launch would lose the recovery for good.
      final (:provider, :ffi) = await _setup(
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
        ownProfile: null,
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      expect(await provider.adoptHubCityIfLocalEmpty(), isFalse);

      // Next launch, hub reachable again.
      ffi.ownProfile = _hubProfile(cityId: _kParis, country: 'FR');
      expect(await provider.adoptHubCityIfLocalEmpty(), isTrue);
      expect(provider.localCityId, _kParis);
      expect(ffi.getProfileCalls, 2);
    });

    test('refuses a malformed country code from the hub', () async {
      // The hub is not a trusted source for this value: it lands in a pref
      // that is exported into .bgbackup archives and re-applied on restore,
      // and country codes become path and URL segments in CityRepository.
      // Adopt the city (its id is validated), drop the junk country.
      final (:provider, :ffi) = await _setup(
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
        ownProfile: _hubProfile(cityId: _kParis, country: '../../etc'),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      expect(await provider.adoptHubCityIfLocalEmpty(), isTrue);
      expect(provider.localCityId, _kParis);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('hub_local_location_city_country'),
        isNull,
        reason: 'a non ISO 3166-1 alpha-2 value must never be persisted',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Group 4: the city must not outlive the country it belongs to
  // -------------------------------------------------------------------------
  group('dropCityForCountryChange', () {
    test('drops a city that belonged to the previous country', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      final dropped = await provider.dropCityForCountryChange('BE');

      expect(dropped, isTrue);
      expect(
        provider.localCityId,
        isNull,
        reason:
            'a French city under a Belgian country is incoherent: it renders '
            'as "unknown city" and would publish a country+city pair that no '
            'directory filter can match',
      );
    });

    test('keeps a city that belongs to the new country', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      // Re-selecting the same country, or a lowercase spelling of it.
      expect(await provider.dropCityForCountryChange('fr'), isFalse);
      expect(provider.localCityId, _kParis);
    });

    test('leaves a city whose country was never recorded', () async {
      // Legacy installs stored the id without the companion country. We
      // cannot tell whether it matches, and silently deleting the user's
      // city on a guess is worse than showing a stale one.
      final (:provider, :ffi) = await _setup(
        prefs: const {'hub_local_location_city_id': _kParis},
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();

      expect(await provider.dropCityForCountryChange('BE'), isFalse);
      expect(provider.localCityId, _kParis);
    });

    test('withdraws a shared city from the hub as it drops it', () async {
      final (:provider, :ffi) = await _setup(
        prefs: const {
          'hub_local_location_city_id': _kParis,
          'hub_local_location_city_country': 'FR',
          'hub_share_city': true,
        },
        cities: {_kParis: _city(id: _kParis, country: 'FR')},
        existingConfig: _config(),
      );
      await provider.loadConfig();
      await provider.loadShareCity();
      await provider.loadLocalCityId();
      ffi.registerParamsLog.clear();

      expect(await provider.dropCityForCountryChange('BE'), isTrue);

      expect(provider.localCityId, isNull);
      expect(
        provider.isShareCityEnabled,
        isFalse,
        reason: 'there is nothing left to share, the consent must not linger',
      );
      expect(
        ffi.registerParamsLog.last.locationCityId,
        isNull,
        reason: 'the public profile must lose the stale city immediately',
      );
    });
  });
}
