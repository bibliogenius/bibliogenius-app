import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/contact_audience.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/widgets/contact_audience_fields.dart';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => [];
}

/// The audience checkboxes of the "My contact details" section: that a tick
/// reaches the provider and survives a reload, that the dead end of "nobody
/// receives it" is spelled out, and that a screen reader hears who each box
/// is about and whether it is ticked.
void main() {
  const paired = 'My paired libraries';
  const directory = 'My directory followers';
  const nobody = 'Nobody will receive your contact details.';

  setUp(() {
    TranslationService.setPoTranslationsForTest({
      'en': {
        'contact_audience_title': 'Who receives them',
        'contact_audience_paired': paired,
        'contact_audience_paired_desc': 'The ones you paired with.',
        'contact_audience_directory': directory,
        'contact_audience_directory_desc': 'Any follower you accepted.',
        'contact_audience_nobody': nobody,
        'contact_audience_withdraw_note': 'Unticking withdraws them.',
      },
    });
  });

  Future<HubDirectoryProvider> pump(
    WidgetTester tester, {
    required String storedCard,
    String? storedAudience,
  }) async {
    SharedPreferences.setMockInitialValues({
      'hub_contact_info': storedCard,
      if (storedAudience != null) 'hub_contact_audience': storedAudience,
    });
    final hub = HubDirectoryProvider(ffi: _MockFfiService());
    await hub.loadContactInfo();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          // TranslationService reads the locale through ThemeProvider.
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ContactAudienceFields()),
          ),
        ),
      ),
    );
    return hub;
  }

  testWidgets('a tick reaches the provider and is stored', (tester) async {
    final hub = await pump(tester, storedCard: '');
    expect(hub.contactAudience, ContactAudience.fresh);

    await tester.tap(find.text(directory));
    await tester.pumpAndSettle();

    expect(hub.contactAudience, ContactAudience.legacy);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('hub_contact_audience'), 'paired,directory');
  });

  testWidgets('unticking both boxes of a filled card says nobody gets it', (
    tester,
  ) async {
    await pump(
      tester,
      storedCard: '{"v":1,"email":"owner@example.org"}',
      storedAudience: '',
    );
    expect(find.text(nobody), findsOneWidget);
  });

  testWidgets('no warning while the card is empty: nothing is withheld', (
    tester,
  ) async {
    await pump(tester, storedCard: '', storedAudience: '');
    expect(find.text(nobody), findsNothing);
  });

  testWidgets('each box announces who it is about and its state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, storedCard: '', storedAudience: 'paired');

    // The tile is a merge boundary: the checkbox's state reaches the tile's
    // node through its merged data, which is what a screen reader announces.
    final pairedData = tester.getSemantics(find.text(paired)).getSemanticsData();
    expect(pairedData.label, contains(paired));
    expect(pairedData.label, contains('The ones you paired with.'));
    expect(pairedData.flagsCollection.isChecked, CheckedState.isTrue);

    final directoryData = tester
        .getSemantics(find.text(directory))
        .getSemanticsData();
    expect(directoryData.flagsCollection.isChecked, CheckedState.isFalse);

    final header = tester
        .getSemantics(find.text('Who receives them'))
        .getSemanticsData();
    expect(header.flagsCollection.isHeader, isTrue);
    handle.dispose();
  });
}
