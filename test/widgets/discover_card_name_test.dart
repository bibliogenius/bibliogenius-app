import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/hub_directory.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/discover_card.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/hub_location_label.dart';

// ---------------------------------------------------------------------------
// Mocks (same shape as test/widgets/same_city_banner_test.dart).
// ---------------------------------------------------------------------------

/// Generated library name: the action chip left it about 150 of 360 logical
/// pixels, so a single line cut it down to "Bibliothèque de ...".
const _longName = 'Bibliothèque de Ménilmontant';

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
}

HubProfile _profile({String name = _longName}) => HubProfile(
  nodeId: 'node-1',
  displayName: name,
  bookCount: 448,
  locationCountry: 'FR',
  requiresApproval: true,
);

Future<HubDirectoryProvider> _provider() async {
  SharedPreferences.setMockInitialValues({});
  AuthService.storage = MockSecureStorage();
  return HubDirectoryProvider(
    ffi: _MockFfiService(),
    deviceService: _MockDeviceService(),
  );
}

Widget _harness(HubDirectoryProvider hub, ThemeProvider theme, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
    ],
    child: MaterialApp(
      home: Scaffold(
        // Phone width: the truncation only shows up at 360 logical pixels,
        // not at the 800px default of the test viewport.
        body: Center(child: SizedBox(width: 360, child: child)),
      ),
    ),
  );
}

void main() {
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'directory_request': 'Request',
        'directory_follow': 'Follow',
        'directory_pending': 'Awaiting',
        'directory_following': 'Following',
        'directory_books': 'books',
        'directory_your_library': 'Your library',
        'directory_wants_to_follow_you': 'Wants to follow you',
        'directory_filter_by_location_a11y':
            'Filter directory by this location',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  group('DiscoverCard name', () {
    testWidgets('wraps a long library name onto a second line', (tester) async {
      final hub = await _provider();

      await tester.pumpWidget(
        _harness(hub, theme, DiscoverCard(profile: _profile())),
      );
      await tester.pumpAndSettle();

      final nameText = tester.widget<Text>(find.text(_longName));
      expect(
        nameText.maxLines,
        2,
        reason:
            'One line next to the action chip cut exactly the part that tells '
            'two generated names apart.',
      );

      // Structural, not font-dependent (widget tests render in Ahem): the name
      // must actually occupy two lines at phone width. A 15px single line is
      // about 18 logical pixels tall.
      final nameHeight = tester.getRect(find.text(_longName)).height;
      expect(
        nameHeight,
        greaterThan(30),
        reason: 'The name must render on two lines, not one truncated line.',
      );
    });

    testWidgets('keeps a short name on a single line', (tester) async {
      final hub = await _provider();

      await tester.pumpWidget(
        _harness(hub, theme, DiscoverCard(profile: _profile(name: 'Amanda'))),
      );
      await tester.pumpAndSettle();

      final nameHeight = tester.getRect(find.text('Amanda')).height;
      expect(
        nameHeight,
        lessThan(30),
        reason:
            'Cards must not grow for short names: the directory is an '
            'infinite list and every pixel is paid on every row.',
      );
    });
  });

  group('HubLocationLabel', () {
    testWidgets('truncates instead of overflowing its metadata row', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 60,
                child: Row(
                  children: [
                    Flexible(
                      child: HubLocationLabel(country: 'FR', cityId: null),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.text('FR'));
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
    });
  });
}
