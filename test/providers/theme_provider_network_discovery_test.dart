// Turning local discovery on from the app (settings toggle, or the Nearby
// empty state of the Network screen) must announce the E2EE public keys, as
// the launch path in main.dart does. It used to announce without them, so a
// peer pairing from that announcement got no keys until the next launch.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';

void main() {
  late List<Map<String, String?>> announced;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    announced = [];
    ThemeProvider.mdnsAnnounceOverride =
        (
          String libraryName,
          int port, {
          String? libraryId,
          String? ed25519PublicKey,
          String? x25519PublicKey,
        }) async {
          announced.add({
            'libraryId': libraryId,
            'ed25519': ed25519PublicKey,
            'x25519': x25519PublicKey,
          });
          return true;
        };
  });

  tearDown(() {
    ThemeProvider.mdnsAnnounceOverride = null;
    ThemeProvider.publicKeysOverride = null;
  });

  test('turning discovery on announces the identity keys', () async {
    ThemeProvider.publicKeysOverride = () async =>
        '{"ed25519": "aa11", "x25519": "bb22"}';

    await ThemeProvider().setNetworkDiscoveryEnabled(
      true,
      libraryId: 'library-uuid',
      port: 8000,
    );

    expect(announced, [
      {'libraryId': 'library-uuid', 'ed25519': 'aa11', 'x25519': 'bb22'},
    ]);
  });

  test('without an identity it still announces, without keys', () async {
    ThemeProvider.publicKeysOverride = () async => null;

    await ThemeProvider().setNetworkDiscoveryEnabled(
      true,
      libraryId: 'library-uuid',
      port: 8000,
    );

    expect(announced, [
      {'libraryId': 'library-uuid', 'ed25519': null, 'x25519': null},
    ]);
  });
}
