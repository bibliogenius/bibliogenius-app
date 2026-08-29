import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/passphrase_strength_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The backend hands the meter stable zxcvbn slugs, never English prose. These
/// tests pin the two halves of that contract: a known slug is rendered in the
/// reader's language, and an unknown one is dropped instead of leaking a raw
/// identifier onto the screen.
void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({
      'en': {
        'account_sync_strength_label': 'Strength',
        'account_sync_strength_0': 'Very weak',
        'account_sync_strength_1': 'Weak',
        'zxcvbn_warning_common_password': 'This is a very common password.',
        'zxcvbn_suggestion_add_another_word': 'Add another word or two.',
      },
      'fr': {
        'account_sync_strength_label': 'Robustesse',
        'account_sync_strength_0': 'Tres faible',
        'account_sync_strength_1': 'Faible',
        'zxcvbn_warning_common_password': 'Mot de passe tres courant.',
        'zxcvbn_suggestion_add_another_word': 'Ajoutez un ou deux mots.',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Future<void> pumpMeter(
    WidgetTester tester,
    PassphraseStrength strength, {
    Locale locale = const Locale('fr'),
  }) async {
    // The locale must be set before the first frame, otherwise the meter builds
    // once against the default language.
    final themeProvider = ThemeProvider()..setLocaleSync(locale);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: themeProvider,
        child: MaterialApp(
          home: Scaffold(body: PassphraseStrengthMeter(strength: strength)),
        ),
      ),
    );
  }

  testWidgets('known slugs are rendered in the reader language', (
    tester,
  ) async {
    await pumpMeter(
      tester,
      const PassphraseStrength(
        score: 1,
        length: 9,
        acceptable: false,
        warning: 'zxcvbn_warning_common_password',
        suggestions: ['zxcvbn_suggestion_add_another_word'],
      ),
    );

    expect(find.text('Robustesse: Faible'), findsOneWidget);
    expect(find.text('Mot de passe tres courant.'), findsOneWidget);
    expect(find.text('Ajoutez un ou deux mots.'), findsOneWidget);
  });

  testWidgets('an unknown slug shows nothing rather than the raw identifier', (
    tester,
  ) async {
    await pumpMeter(
      tester,
      const PassphraseStrength(
        score: 1,
        length: 9,
        acceptable: false,
        warning: 'zxcvbn_warning_not_in_the_catalogue_yet',
        suggestions: [
          'zxcvbn_suggestion_not_in_the_catalogue_yet',
          'zxcvbn_suggestion_add_another_word',
        ],
      ),
    );

    expect(find.textContaining('zxcvbn_'), findsNothing);
    // The slugs that ARE known still show, so one gap does not hide the rest.
    expect(find.text('Ajoutez un ou deux mots.'), findsOneWidget);
  });

  testWidgets('an empty passphrase shows the label and no advice', (
    tester,
  ) async {
    await pumpMeter(tester, const PassphraseStrength.empty());

    expect(find.textContaining('Robustesse'), findsOneWidget);
    expect(find.textContaining('zxcvbn_'), findsNothing);
  });
}
