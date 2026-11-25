// The "Nearby" empty state of the Network screen.
//
// Local discovery is off on a fresh install. The state used to say "no nearby
// libraries" whatever the setting, so two fresh installs on the same Wi-Fi
// each read that nobody was there while neither was listening. It now says
// discovery is off and turns it on in one tap; "no nearby libraries" only
// shows once discovery is on.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/network_empty_state.dart';

/// Records the calls instead of starting mDNS, which needs the FFI.
class _FakeTheme extends ThemeProvider {
  _FakeTheme({required this.discoveryOn});

  bool discoveryOn;
  final enableCalls = <bool>[];

  @override
  bool get networkEnabled => discoveryOn;

  @override
  Future<void> setNetworkEnabled(bool enabled) async {
    enableCalls.add(enabled);
    discoveryOn = enabled;
    notifyListeners();
  }
}

Widget _harness(ThemeProvider theme) => ChangeNotifierProvider.value(
  value: theme,
  child: const MaterialApp(home: Scaffold(body: NearbyEmptyState())),
);

const _newKeys = [
  'nearby_discovery_off_title',
  'nearby_discovery_off_hint',
  'nearby_discovery_off_ios_hint',
  'nearby_discovery_enable_btn',
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // An empty catalogue makes translate() return the key, so the test reads
    // which key each line shows.
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('discovery off: says so and offers to turn it on', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_FakeTheme(discoveryOn: false)));

    expect(find.text('nearby_discovery_off_title'), findsOneWidget);
    expect(find.text('nearby_discovery_off_hint'), findsOneWidget);
    expect(find.text('nearby_discovery_enable_btn'), findsOneWidget);
    expect(find.text('no_nearby_peers'), findsNothing);
    expect(find.text('no_nearby_peers_hint'), findsNothing);
  });

  testWidgets('one tap on the button turns discovery on', (tester) async {
    final theme = _FakeTheme(discoveryOn: false);
    await tester.pumpWidget(_harness(theme));

    await tester.tap(find.byKey(const Key('enableNearbyDiscoveryBtn')));
    await tester.pump();

    expect(theme.enableCalls, [true]);
    // Discovery on and nobody found yet: the usual state takes over.
    expect(find.text('no_nearby_peers'), findsOneWidget);
    expect(find.byKey(const Key('enableNearbyDiscoveryBtn')), findsNothing);
  });

  testWidgets('discovery on and nobody found: the state is unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_FakeTheme(discoveryOn: true)));

    expect(find.byKey(const Key('networkEmptyNearby')), findsOneWidget);
    expect(find.text('no_nearby_peers'), findsOneWidget);
    expect(find.text('no_nearby_peers_hint'), findsOneWidget);
    expect(find.text('nearby_discovery_off_title'), findsNothing);
    expect(find.byKey(const Key('enableNearbyDiscoveryBtn')), findsNothing);
  });

  testWidgets('the iOS sentence shows on iOS only', (tester) async {
    await tester.pumpWidget(_harness(_FakeTheme(discoveryOn: false)));
    final onIos = defaultTargetPlatform == TargetPlatform.iOS;
    expect(
      find.text('nearby_discovery_off_ios_hint'),
      onIos ? findsOneWidget : findsNothing,
    );
  }, variant: TargetPlatformVariant.all());

  testWidgets('accessible: translated button of 48 dp, title is a header', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_harness(_FakeTheme(discoveryOn: false)));

    final button = find.byKey(const Key('enableNearbyDiscoveryBtn'));
    final size = tester.getSize(button);
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(
      find.bySemanticsLabel('nearby_discovery_enable_btn'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('nearby_discovery_off_title')),
      matchesSemantics(label: 'nearby_discovery_off_title', isHeader: true),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  test('the new keys exist in every exposed catalogue and the template', () {
    final files = Directory('assets/i18n')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.po') || f.path.endsWith('.pot'))
        .toList();
    expect(files.length, 12, reason: '11 catalogues and messages.pot');
    for (final file in files) {
      final ids = RegExp(
        r'^msgid "([^"]+)"',
        multiLine: true,
      ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!).toSet();
      final missing = _newKeys.where((k) => !ids.contains(k)).toList();
      expect(missing, isEmpty, reason: 'missing in ${file.path}');
    }
  });
}
