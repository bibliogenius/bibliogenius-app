import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The reported bug: on narrow covers (the /books activity carousel is ~80px
// wide) the status pill is anchored right with an intrinsic width and no
// overflow handling, so a long label like "ENVIE DE LIRE" bleeds past the
// cover's left edge and gets clipped to "IVIE DE LIRE". Below a width
// threshold the badge collapses to the status icon alone; above it the pill
// keeps an ellipsis as a safety net.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'reading_status_wanting': 'Envie de lire',
        'reading_status_reading': 'En cours',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    String status = 'wanting',
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 130,
                child: BookCoverCard(
                  book: Book(
                    title: 'Le Livre',
                    owned: false,
                    readingStatus: status,
                  ),
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a narrow cover collapses the status pill to its icon', (
    tester,
  ) async {
    await pump(tester, width: 80);

    expect(find.text('ENVIE DE LIRE'), findsNothing);
    // The wanting status icon, announced for the screen reader.
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Envie de lire')), findsOneWidget);
  });

  // Regression: the ownership badge used to add a SECOND heart (filled,
  // top-left) next to the wanting status badge (outline, top-right), telling
  // the same fact twice. On surfaces rendering a status badge, the wished
  // ownership badge stands down; the desaturation still marks possession.
  testWidgets('a wanting book shows one heart, not two', (tester) async {
    await pump(tester, width: 80);

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsNothing);
  });

  testWidgets('a wide cover keeps the text pill', (tester) async {
    await pump(tester, width: 200);

    expect(find.text('ENVIE DE LIRE'), findsOneWidget);
  });

  // A reader who cleared the reading status carries an empty string, not
  // null: the value is storable since the "no status" option became real.
  // A badge there would print an untranslated `reading_status_` and claim a
  // state the book does not have.
  testWidgets('a book left without a status wears no status badge', (
    tester,
  ) async {
    await pump(tester, width: 200, status: '');

    expect(find.text('READING_STATUS_'), findsNothing);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
  });

  testWidgets('the text pill can never overflow the cover again', (
    tester,
  ) async {
    // Just above the icon threshold: the pill must ellipsize, not clip.
    await pump(tester, width: 130);

    final text = tester.widget<Text>(find.text('ENVIE DE LIRE'));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });
}
