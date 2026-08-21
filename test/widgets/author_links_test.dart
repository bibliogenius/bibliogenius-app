import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/author_identity.dart';
import 'package:bibliogenius/widgets/author_links.dart';

/// The book-page entry point of ADR-061 surface 2: the author line is a
/// route, and how many routes it carries is decided by the library's own
/// vocabulary, never by the comma alone.
void main() {
  late ThemeProvider theme;
  late List<String> visited;

  final vocabulary = AuthorIdentity.vocabularyOf(const {
    'a wizard of earthsea|ursula k le guin',
    'the dispossessed|alia sun',
  });

  Widget harness(String flattened, {Set<String>? words}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: AuthorLinks(
              flattenedAuthor: flattened,
              vocabulary: words ?? vocabulary,
            ),
          ),
        ),
        GoRoute(
          path: '/authors/:name',
          builder: (context, state) {
            visited.add(state.pathParameters['name'] ?? '');
            return const Scaffold(body: Text('author page'));
          },
        ),
      ],
    );
    return ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  setUp(() {
    visited = [];
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {'author_page_open_semantic': 'Books by {author}'},
    });
  });

  testWidgets('an inverted "Last, First" name is ONE link', (tester) async {
    await tester.pumpWidget(harness('Le Guin, Ursula K.'));
    await tester.pumpAndSettle();

    expect(find.text('Le Guin, Ursula K.'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('two co-signing authors are two links', (tester) async {
    await tester.pumpWidget(harness('Ursula K. Le Guin, Alia Sun'));
    await tester.pumpAndSettle();

    expect(find.text('Ursula K. Le Guin'), findsOneWidget);
    expect(find.text('Alia Sun'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(2));
  });

  testWidgets('an unloaded vocabulary keeps the whole string linkable', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness('Ursula K. Le Guin, Alia Sun', words: const {}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ursula K. Le Guin, Alia Sun'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('tapping a name opens that author page', (tester) async {
    await tester.pumpWidget(harness('Ursula K. Le Guin, Alia Sun'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alia Sun'));
    await tester.pumpAndSettle();

    expect(visited, ['Alia Sun']);
    expect(find.text('author page'), findsOneWidget);
  });

  testWidgets('a name containing a slash still routes', (tester) async {
    // Percent-encoding survives the round trip, so an author whose name
    // carries a path separator opens their page instead of a dead end.
    await tester.pumpWidget(harness('AC/DC'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('AC/DC'));
    await tester.pumpAndSettle();

    expect(visited, ['AC/DC']);
  });

  testWidgets('each name is a button with its translated label', (
    tester,
  ) async {
    await tester.pumpWidget(harness('Ursula K. Le Guin, Alia Sun'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text('Alia Sun')),
      containsSemantics(isButton: true, label: 'Books by Alia Sun'),
    );
  });

  /// Colour and weight are the persistent affordance; the underline is an
  /// accent shown on hover OR keyboard focus (a static one reads heavy under
  /// a book title, and doubly so with two co-authors). Hover being
  /// pointer-only, the focus half is what keeps the two modalities at
  /// parity. Touch devices show neither and lose nothing, the ripple answers.
  group('hover and focus accent', () {
    TextStyle? styleOf(WidgetTester tester, String name) =>
        tester.widget<Text>(find.text(name)).style;

    testWidgets('no underline at rest', (tester) async {
      await tester.pumpWidget(harness('Ursula K. Le Guin, Alia Sun'));
      await tester.pumpAndSettle();

      expect(styleOf(tester, 'Alia Sun')?.decoration, isNot(TextDecoration.underline));
    });

    testWidgets('underlines the hovered name only', (tester) async {
      await tester.pumpWidget(harness('Ursula K. Le Guin, Alia Sun'));
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('Alia Sun')));
      await tester.pumpAndSettle();

      expect(styleOf(tester, 'Alia Sun')?.decoration, TextDecoration.underline);
      expect(
        styleOf(tester, 'Ursula K. Le Guin')?.decoration,
        isNot(TextDecoration.underline),
        reason: 'pointing at one co-author must not underline the other',
      );

      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(
        styleOf(tester, 'Alia Sun')?.decoration,
        isNot(TextDecoration.underline),
      );
    });

    testWidgets('keyboard focus gets the same accent as hover', (tester) async {
      // Hover is pointer-only. Without this, a keyboard user would get the
      // InkWell default highlight and nothing else, so the two modalities
      // would not be at parity.
      await tester.pumpWidget(harness('Ursula K. Le Guin, Alia Sun'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(
        styleOf(tester, 'Ursula K. Le Guin')?.decoration,
        TextDecoration.underline,
      );
      expect(
        styleOf(tester, 'Alia Sun')?.decoration,
        isNot(TextDecoration.underline),
        reason: 'focus accents one name, like hover',
      );

      // Traversal moves the accent along with the focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      expect(
        styleOf(tester, 'Alia Sun')?.decoration,
        TextDecoration.underline,
      );
      expect(
        styleOf(tester, 'Ursula K. Le Guin')?.decoration,
        isNot(TextDecoration.underline),
      );
    });
  });

  testWidgets('no author renders nothing at all', (tester) async {
    await tester.pumpWidget(harness('   '));
    await tester.pumpAndSettle();

    expect(find.byType(InkWell), findsNothing);
  });
}
