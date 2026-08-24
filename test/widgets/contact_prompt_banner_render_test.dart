import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/contact_card_prompt.dart';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();
}

/// What the appearance-rule tests cannot see: that the banner actually renders,
/// at a narrow width and in both themes, and that its button leads somewhere.
/// A RenderFlex overflow throws in a widget test, so laying it out IS the
/// assertion.
void main() {
  late ThemeProvider theme;
  late HubDirectoryProvider hub;

  setUp(() {
    theme = ThemeProvider();
    hub = HubDirectoryProvider(ffi: _MockFfiService());
    TranslationService.setPoTranslationsForTest({
      'en': {
        'contact_prompt_title': 'How can people reach you?',
        'contact_prompt_body':
            'Without contact details, nobody can agree a place or a date with '
            'you for a loan. Only the libraries you approved receive them, '
            'encrypted.',
        'contact_prompt_irreversible': 'Once sent, they cannot be taken back.',
        'contact_prompt_banner_body':
            'Libraries follow you, but cannot reach you.',
        'contact_prompt_action': 'Add my contact details',
        'hub_contact_email_label': 'Email',
        'hub_contact_phone_label': 'Phone',
        'hub_contact_phone_helper': 'International format',
        'hub_contact_phone_hint': '+44 7700 900123',
        'hub_contact_note_label': 'Details',
        'hub_contact_note_hint': 'Address, hours',
        'hub_contact_encrypted_notice': 'Encrypted',
        'close': 'Close',
        'done': 'Done',
      },
    });
  });

  Widget harness({
    required VoidCallback onDismiss,
    Brightness brightness = Brightness.light,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContactPromptBanner(onDismiss: onDismiss),
          ),
        ),
      ),
    );
  }

  testWidgets('lays out on a narrow window without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(onDismiss: () {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('How can people reach you?'), findsOneWidget);
    expect(
      find.text('Libraries follow you, but cannot reach you.'),
      findsOneWidget,
    );
    expect(find.text('Add my contact details'), findsOneWidget);
  });

  testWidgets('renders in the dark theme too', (tester) async {
    await tester.pumpWidget(
      harness(onDismiss: () {}, brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add my contact details'), findsOneWidget);
  });

  testWidgets('the close button reports the dismissal', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(harness(onDismiss: () => dismissed = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(dismissed, isTrue);
  });

  testWidgets(
    'the action opens the form, with the three fields and the caveat',
    (tester) async {
      await tester.pumpWidget(harness(onDismiss: () {}));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add my contact details'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(
        find.text('Once sent, they cannot be taken back.'),
        findsOneWidget,
      );
      // The notice belongs to the settings, where nothing else says who reads
      // the card; here the body already says it.
      expect(find.text('Encrypted'), findsNothing);
    },
  );
}
