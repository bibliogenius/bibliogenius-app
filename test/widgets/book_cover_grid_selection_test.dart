import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/book_cover_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Selection mode on the covers grid: a long press enters it, and once in it
// a tap can only mean "select" - the card's own gestures (open the book,
// change its status) are suspended.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
  });

  final books = [
    Book(id: 'a', title: 'Dune', author: 'Frank Herbert', owned: true),
    Book(id: 'b', title: 'Martin Eden', author: 'Jack London', owned: true),
  ];

  Future<void> pump(
    WidgetTester tester, {
    Set<String>? selectedIds,
    required List<String> taps,
    required List<String> longPresses,
    List<String>? statusChanges,
  }) {
    return tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: BookCoverGrid(
              books: books,
              onBookTap: (book) => taps.add(book.id!),
              onBookLongPress: (book) => longPresses.add(book.id!),
              onStatusChanged: (book, status) => statusChanges?.add(book.id!),
              selectedIds: selectedIds,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('outside selection mode a long press reports the book', (
    tester,
  ) async {
    final taps = <String>[];
    final longPresses = <String>[];
    await pump(tester, taps: taps, longPresses: longPresses);

    await tester.longPress(find.text('Dune'));
    await tester.pump();

    expect(longPresses, ['a']);
    expect(taps, isEmpty);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('in selection mode each tile is a toggle that says its state', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final taps = <String>[];
    final longPresses = <String>[];
    await pump(
      tester,
      selectedIds: {'a'},
      taps: taps,
      longPresses: longPresses,
    );

    // One check mark: the selected book only.
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Dune, Frank Herbert')),
      containsSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Martin Eden, Jack London')),
      containsSemantics(isButton: true, isSelected: false),
    );

    await tester.tap(find.bySemanticsLabel('Martin Eden, Jack London'));
    await tester.pump();
    expect(taps, ['b']);
    expect(longPresses, isEmpty);
    handle.dispose();
  });
}
