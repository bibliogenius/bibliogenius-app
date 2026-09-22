import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/edition_picker_sheet.dart';

/// The picker sorts editions by completeness and used to open on the first
/// one, whatever the reader had just clicked in the suggestion list: they had
/// to find their edition a second time.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // No cover URLs on purpose: a cover would sort first and load an image.
  final gallimard = <String, dynamic>{
    'title': 'Martin Eden',
    'isbn': '9782070795987',
    'publisher': 'Gallimard',
  };
  final libretto = <String, dynamic>{
    'title': 'Martin Eden',
    'isbn': '9782752905536',
    'publisher': 'Libretto',
  };
  final bareEdition = <String, dynamic>{'title': 'Martin Eden'};

  group('initialIndexFor', () {
    test('finds the selected entry itself', () {
      final editions = [gallimard, libretto, bareEdition];
      expect(EditionPickerSheet.initialIndexFor(editions, libretto), 1);
    });

    test('falls back to the ISBN when the maps differ', () {
      final editions = [gallimard, libretto];
      final copy = <String, dynamic>{'isbn': '978-2-7529-0553-6'};
      expect(EditionPickerSheet.initialIndexFor(editions, copy), 1);
    });

    test('opens on the first page when nothing matches or nothing is selected', () {
      final editions = [gallimard, libretto];
      final stranger = <String, dynamic>{'isbn': '9780000000002'};
      expect(EditionPickerSheet.initialIndexFor(editions, stranger), 0);
      expect(EditionPickerSheet.initialIndexFor(editions, null), 0);
      expect(EditionPickerSheet.initialIndexFor([], libretto), 0);
    });
  });

  testWidgets('the carousel opens on the clicked edition and selects it', (
    tester,
  ) async {
    Map<String, dynamic>? picked;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await EditionPickerSheet.show(
                  context: context,
                  title: 'Martin Eden',
                  // Given in an order the sort reshuffles: the bare edition
                  // drops last, the two with a publisher keep their order.
                  editions: [bareEdition, gallimard, libretto],
                  selected: libretto,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Position indicator: the clicked edition is the second of three.
    expect(find.textContaining('2 / 3'), findsOneWidget);

    // `FilledButton.icon` builds a private subclass `byType` would miss.
    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await tester.pumpAndSettle();

    expect(picked, same(libretto));
  });
}
