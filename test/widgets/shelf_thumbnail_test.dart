import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';
import 'package:bibliogenius/utils/accessible_color.dart';
import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:bibliogenius/widgets/shelf_thumbnail.dart';
import 'package:bibliogenius/widgets/shelf_tree_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  ShelfThumbnail thumbnail, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: thumbnail)),
    ),
  );
}

/// The covers the pile draws, in paint order.
List<CachedBookCover> _covers(WidgetTester tester) =>
    tester.widgetList<CachedBookCover>(find.byType(CachedBookCover)).toList();

/// The fill of the pictogram badge.
Color? _badgeColor(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.byKey(const Key('shelfThumbnailBadge')),
  );
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await TranslationService.loadTranslations();
    ThemeRegistry.initialize();
  });

  group('the cover pile', () {
    for (final n in [1, 2, 3]) {
      testWidgets('$n cover(s): a straight pile, centred in the frame', (
        tester,
      ) async {
        await _pump(
          tester,
          ShelfThumbnail(
            name: 'Novels',
            hasBooks: true,
            coverPaths: [for (var i = 0; i < n; i++) 'https://c/$i.jpg'],
          ),
        );

        expect(_covers(tester), hasLength(n));
        expect(find.byKey(const Key('shelfThumbnailBadge')), findsNothing);
        expect(
          find.descendant(
            of: find.byType(ShelfThumbnail),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
        final frame = tester.getRect(find.byType(ShelfThumbnail));
        final lefts = [
          for (final e in find.byType(CachedBookCover).evaluate())
            tester.getTopLeft(find.byWidget(e.widget)).dx - frame.left,
        ];
        final spread = 38 + 14.0 * (n - 1);
        // Paint order: the oldest at the right, the newest at the left.
        expect(lefts, [
          for (var i = n - 1; i >= 0; i--) (72 - spread) / 2 + 14 * i,
        ]);
      });
    }

    testWidgets('never more than three covers, the newest on top', (
      tester,
    ) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          name: 'Novels',
          hasBooks: true,
          coverPaths: [
            'https://c/new.jpg',
            'https://c/b.jpg',
            'https://c/c.jpg',
            'https://c/d.jpg',
          ],
        ),
      );

      final covers = _covers(tester);
      expect(covers, hasLength(3));
      expect(covers.last.imageUrl, 'https://c/new.jpg');
    });

    testWidgets('the pile fits the 72 x 56 frame and each cover is decoded '
        'at its own size', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          name: 'Novels',
          hasBooks: true,
          coverPaths: ['https://c/a.jpg', 'https://c/b.jpg', 'https://c/c.jpg'],
        ),
      );

      expect(
        tester.getSize(find.byType(ShelfThumbnail)),
        const Size(72, 56),
      );
      for (final cover in _covers(tester)) {
        expect(cover.width, 38);
        expect(cover.height, 54);
      }
    });

    testWidgets('a cover that does not load leaves its place empty, never '
        'the grey book placeholder', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          name: 'Novels',
          hasBooks: true,
          coverPaths: ['/nowhere/gone.jpg'],
        ),
      );
      // Let the file read fail for real.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();

      expect(find.byIcon(Icons.book), findsNothing);
      final cover = _covers(tester).single;
      // Loading and failing both draw nothing in the slot.
      expect(cover.errorWidget, isA<SizedBox>());
      expect((cover.errorWidget! as SizedBox).child, isNull);
      expect(cover.placeholder, isA<SizedBox>());
      expect((cover.placeholder! as SizedBox).child, isNull);
    });
  });

  group('without a cover', () {
    testWidgets('books but no cover: the shelf pictogram on a tint of the '
        'name', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(name: 'Kitchen', hasBooks: true),
      );

      expect(find.byType(CachedBookCover), findsNothing);
      expect(find.byIcon(Icons.shelves), findsOneWidget);
      expect(
        _badgeColor(tester),
        ShelfTint.of('Kitchen', Brightness.light).background,
      );
    });

    testWidgets('the tint follows the name', (tester) async {
      expect(
        ShelfTint.of('Kitchen', Brightness.light).background,
        isNot(ShelfTint.of('Garden', Brightness.light).background),
      );
      expect(
        ShelfTint.of('Kitchen', Brightness.light),
        ShelfTint.of('Kitchen', Brightness.light),
      );
    });

    testWidgets('a genre shelf wears its genre icon, in any language', (
      tester,
    ) async {
      for (final name in ['Crime & thriller', 'Polar & thriller']) {
        await _pump(tester, ShelfThumbnail(name: name, hasBooks: true));
        expect(
          find.byIcon(Icons.local_police_outlined),
          findsOneWidget,
          reason: name,
        );
        expect(find.byIcon(Icons.shelves), findsNothing, reason: name);
      }
    });

    testWidgets('a subgenre wears the icon of its genre', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(name: 'Roman policier', hasBooks: true),
      );

      expect(find.byIcon(Icons.local_police_outlined), findsOneWidget);
    });

    testWidgets('the "Genre" root is an ordinary shelf', (tester) async {
      await _pump(tester, const ShelfThumbnail(name: 'Genre', hasBooks: true));

      expect(find.byIcon(Icons.shelves), findsOneWidget);
    });

    testWidgets('an empty shelf: the shelf icon on a neutral ground', (
      tester,
    ) async {
      final theme = ThemeRegistry.get(
        'default',
      )!.buildTheme(accentColor: Colors.blue);
      await _pump(
        tester,
        const ShelfThumbnail(name: 'Kitchen', hasBooks: false),
        theme: theme,
      );

      expect(find.byIcon(Icons.shelves), findsOneWidget);
      expect(_badgeColor(tester), theme.colorScheme.surfaceContainerHighest);
      expect(
        _badgeColor(tester),
        isNot(ShelfTint.of('Kitchen', theme.brightness).background),
      );
    });

    testWidgets('a shelf counted empty shows no cover, whatever it is sent', (
      tester,
    ) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          name: 'Kitchen',
          hasBooks: false,
          coverPaths: ['https://c/a.jpg'],
        ),
      );

      expect(find.byType(CachedBookCover), findsNothing);
      expect(find.byIcon(Icons.shelves), findsOneWidget);
    });

    testWidgets('an empty genre shelf is still just an empty shelf', (
      tester,
    ) async {
      await _pump(
        tester,
        const ShelfThumbnail(name: 'Crime & thriller', hasBooks: false),
      );

      expect(find.byIcon(Icons.shelves), findsOneWidget);
      expect(find.byIcon(Icons.local_police_outlined), findsNothing);
    });

    testWidgets('order: covers before the pictogram, books before empty', (
      tester,
    ) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          name: 'Crime & thriller',
          hasBooks: true,
          coverPaths: ['https://c/a.jpg'],
        ),
      );
      expect(find.byType(CachedBookCover), findsOneWidget);
      expect(find.byKey(const Key('shelfThumbnailBadge')), findsNothing);
    });
  });

  testWidgets('a row leaves room around its thumbnail at every level', (
    tester,
  ) async {
    for (final depth in [0, 1, 3]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ShelfTreeRow(
                key: const Key('row'),
                name: 'A',
                depth: depth,
                thumbnail: const ShelfThumbnail(name: 'A', hasBooks: true),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('row'))).height, 68);
    }
  });

  testWidgets('the thumbnail adds no semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    for (final thumbnail in const [
      ShelfThumbnail(
        name: 'Novels',
        hasBooks: true,
        coverPaths: ['https://c/a.jpg', 'https://c/b.jpg'],
      ),
      ShelfThumbnail(name: 'Crime & thriller', hasBooks: true),
      ShelfThumbnail(name: 'Kitchen', hasBooks: false),
    ]) {
      await _pump(tester, thumbnail);
      // The nearest node is the page's, not one of the thumbnail's own.
      expect(
        tester.getSemantics(find.byType(ShelfThumbnail)).id,
        tester.getSemantics(find.byType(Scaffold)).id,
        reason: thumbnail.name,
      );
    }
    handle.dispose();
  });

  group('contrast (rule A2)', () {
    test('the pictogram reads on every tint, light and dark', () {
      for (final brightness in Brightness.values) {
        for (var i = 0; i < 2000; i++) {
          final tint = ShelfTint.of('shelf $i', brightness);
          expect(
            contrastRatio(tint.foreground, tint.background),
            greaterThanOrEqualTo(4.5),
            reason: 'shelf $i, $brightness',
          );
        }
      }
    });

    test('the empty-shelf icon reads on its ground in every theme', () {
      for (final theme in ThemeRegistry.all) {
        final scheme = theme.buildTheme(accentColor: Colors.blue).colorScheme;
        final neutral = ShelfTint.neutral(scheme);
        expect(
          contrastRatio(neutral.foreground, neutral.background),
          greaterThanOrEqualTo(3),
          reason: theme.id,
        );
      }
    });
  });
}
