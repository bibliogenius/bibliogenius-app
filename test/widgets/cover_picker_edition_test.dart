import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/cover_candidate.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/cover_picker_dialog.dart';

/// The picker used to show an image and a source badge, nothing else. When the
/// ISBN carries no cover the candidates come from sibling editions of the same
/// work, which is usually fine and sometimes not, and the reader had no way to
/// see which one they were about to put on the shelf.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'cover_other_edition': 'Another edition',
        'cover_this_edition': 'This edition',
        'cover_pick_title': 'Choose a cover',
        'cover_use_button': 'Use',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pumpPicker(
    WidgetTester tester,
    List<CoverCandidate> candidates,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CoverPickerDialog(
              candidates: candidates,
              bookTitle: 'Retour en Afrique',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a sibling edition says so', (tester) async {
    await pumpPicker(tester, const [
      CoverCandidate(
        url: 'https://inventaire.io/img/entities/abc',
        source: 'Inventaire',
        language: 'fr',
      ),
    ]);

    expect(find.text('Another edition'), findsOneWidget);
    expect(find.text('This edition'), findsNothing);
  });

  testWidgets("the book's own edition says so too", (tester) async {
    await pumpPicker(tester, const [
      CoverCandidate(
        url: 'https://covers.openlibrary.org/b/isbn/x-L.jpg',
        source: 'OpenLibrary',
        sameEdition: true,
      ),
    ]);

    expect(find.text('This edition'), findsOneWidget);
    expect(find.text('Another edition'), findsNothing);
  });

  testWidgets('the language chip is announced by name, not spelled out', (
    tester,
  ) async {
    await pumpPicker(tester, const [
      CoverCandidate(
        url: 'https://inventaire.io/img/entities/abc',
        source: 'Inventaire',
        language: 'fr',
      ),
    ]);

    // "FR" reads as "F R" to a screen reader; the chip must carry the name.
    expect(
      tester.getSemantics(find.text('FR')).label,
      contains('Français'),
    );
  });

  testWidgets('a stated language is shown, an unknown one is not invented', (
    tester,
  ) async {
    await pumpPicker(tester, const [
      CoverCandidate(
        url: 'https://inventaire.io/img/entities/abc',
        source: 'Inventaire',
        language: 'en',
      ),
    ]);
    expect(find.text('EN'), findsOneWidget);

    await pumpPicker(tester, const [
      CoverCandidate(
        url: 'https://inventaire.io/img/entities/abc',
        source: 'Inventaire',
      ),
    ]);
    expect(find.text('EN'), findsNothing);
  });
}
