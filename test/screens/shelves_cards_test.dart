import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/shelves_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/theme/app_design.dart';
import 'package:bibliogenius/utils/accessible_color.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';
import 'package:bibliogenius/widgets/shelf_card.dart';
import 'package:bibliogenius/widgets/shelf_thumbnail.dart';

/// The shelves tab as a place to walk into: a grid of first-level shelves,
/// the "Organize" row above it and the sober "to shelve" line.

class _Repo implements TagRepository {
  List<Tag> tags;
  int unshelved = 0;

  _Repo(this.tags);

  @override
  Future<List<Tag>> getTags() async => tags;

  @override
  Future<int> countUnshelvedBooks() async => unshelved;

  @override
  Future<Tag> createTag(String name, {String? parentId}) async =>
      Tag(id: 'new', name: name, parentId: parentId, count: 0);

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async =>
      Tag(id: uuid, name: name, parentId: parentId, count: 0);

  @override
  Future<void> deleteTag(String uuid) async {}

  @override
  Future<void> deleteShelf(Tag tag) async {}
}

const _catalogue = {
  'en': {
    'organize': 'Organize',
    'create_shelf': 'Create a shelf',
    'sub_shelves_count': '%d sub-shelf',
    'sub_shelves_count_plural': '%d sub-shelves',
    'displayed_books_count': '%d book',
    'displayed_books_count_plural': '%d books',
    'to_shelve_title': 'To shelve',
    'to_shelve_count': '%d book on no shelf',
    'to_shelve_count_plural': '%d books on no shelf',
    'to_shelve_hide': 'Hide "To shelve" until more books need shelving',
  },
};

const _dismissedKey = 'to_shelve_dismissed_count';

Finder _card(String name) => find.byKey(ValueKey('shelfCard:$name'));

final _hide = find.byTooltip(_catalogue['en']!['to_shelve_hide']!);
final _line = find.byKey(const Key('toShelveCard'));

List<Tag> _roots(int n) => [
  for (var i = 0; i < n; i++) Tag(id: 's$i', name: 'Shelf $i', count: 1),
];

void main() {
  late _Repo repo;
  late BookRefreshNotifier refresh;
  final navigated = <String>[];

  setUpAll(ThemeRegistry.initialize);

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest(_catalogue);
    repo = _Repo(_roots(8));
    refresh = BookRefreshNotifier();
    navigated.clear();
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(
    WidgetTester tester, {
    double width = 390,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    Widget stub(GoRouterState state) {
      navigated.add(state.uri.toString());
      return const Scaffold(body: Text('elsewhere'));
    }

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const ShelvesScreen(isTabView: true),
        ),
        GoRoute(path: '/shelves', builder: (_, s) => stub(s)),
        GoRoute(path: '/shelves-management', builder: (_, s) => stub(s)),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<BookRefreshNotifier>.value(value: refresh),
          ChangeNotifierProvider<OwnershipPreferenceProvider>(
            create: (_) => OwnershipPreferenceProvider(),
          ),
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp.router(routerConfig: router, theme: theme),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// How many cards share the top row.
  int columns(WidgetTester tester) {
    final top = tester.getTopLeft(_card('Shelf 0')).dy;
    return [
      for (var i = 0; i < 8; i++)
        if (_card('Shelf $i').evaluate().isNotEmpty &&
            tester.getTopLeft(_card('Shelf $i')).dy == top)
          i,
    ].length;
  }

  group('the grid', () {
    const cases = [
      (320.0, 1.0, 1),
      (359.0, 1.0, 1),
      (360.0, 1.0, 2),
      (390.0, 1.0, 2),
      (390.0, 1.29, 2),
      (390.0, 1.3, 1),
      (599.0, 1.0, 2),
      (600.0, 1.0, 3),
      (700.0, 1.0, 3),
      (899.0, 1.0, 3),
      (900.0, 1.0, 4),
      (1024.0, 1.0, 4),
      (1024.0, 1.3, 1),
    ];
    for (final (width, scale, expected) in cases) {
      testWidgets('$expected column(s) at $width pt, text at $scale', (
        tester,
      ) async {
        await pump(tester, width: width, textScale: scale);
        expect(columns(tester), expected);
      });
    }

    testWidgets('only the first level is on the grid', (tester) async {
      repo.tags = [
        Tag(id: 'a', name: 'Living room', count: 0),
        Tag(id: 'b', name: 'Comics', parentId: 'a', count: 2),
      ];
      await pump(tester);

      expect(_card('Living room'), findsOneWidget);
      expect(_card('Comics'), findsNothing);
      expect(find.text('Comics'), findsNothing);
    });

    testWidgets('a long name stays within its card at every width and scale', (
      tester,
    ) async {
      repo.tags = [
        Tag(
          id: 'a',
          name: 'Donaudampfschifffahrtsgesellschaftskapitänsbibliothek '
              'und noch viel mehr Bücher im Wohnzimmer',
          count: 1234,
        ),
        Tag(id: 'b', name: 'Sub', parentId: 'a', count: 1),
        Tag(id: 'c', name: 'Other', parentId: 'a', count: 1),
      ];
      for (final (width, scale) in const [
        (320.0, 1.0),
        (360.0, 1.29),
        (390.0, 1.0),
        (390.0, 1.3),
        (390.0, 2.0),
        (700.0, 1.29),
      ]) {
        await pump(tester, width: width, textScale: scale);
        expect(tester.takeException(), isNull, reason: '$width at $scale');
      }
    });
  });

  group('a card', () {
    testWidgets('is one button named by the shelf and its counts, the '
        'thumbnail out of it', (tester) async {
      final handle = tester.ensureSemantics();
      repo.tags = [
        Tag(id: 'a', name: 'Living room', count: 10),
        Tag(id: 'b', name: 'Comics', parentId: 'a', count: 15),
        Tag(id: 'c', name: 'By the sofa', parentId: 'a', count: 5),
        Tag(id: 'd', name: 'Summer', parentId: 'a', count: 0),
      ];
      await pump(tester);

      expect(
        tester.getSemantics(_card('Living room')),
        matchesSemantics(
          label: 'Living room, 30 books, 3 sub-shelves',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('prints the core\'s subtree count, not what the shelves add up '
        'to: 3 books, not 4', (tester) async {
      repo.tags = [
        Tag(
          id: 'a',
          name: 'Essay',
          count: 1,
          totalCount: 1,
          subtreeCount: 3,
          subtreeTotalCount: 3,
        ),
        Tag(
          id: 'b',
          name: 'Politics',
          parentId: 'a',
          count: 2,
          totalCount: 2,
          subtreeCount: 3,
          subtreeTotalCount: 3,
        ),
        Tag(
          id: 'c',
          name: 'Crime',
          parentId: 'b',
          count: 1,
          totalCount: 1,
          subtreeCount: 1,
          subtreeTotalCount: 1,
        ),
      ];
      await pump(tester);

      expect(
        find.descendant(
          of: _card('Essay'),
          matching: find.text('3 books · 1 sub-shelf'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('says "0 books" and no sub-shelf when there is none', (
      tester,
    ) async {
      repo.tags = [Tag(id: 'a', name: 'Kitchen', count: 0)];
      await pump(tester);

      expect(
        find.descendant(of: _card('Kitchen'), matching: find.text('0 books')),
        findsOneWidget,
      );
    });

    testWidgets('prints the counts it announces', (tester) async {
      repo.tags = [
        Tag(id: 'a', name: 'Living room', count: 1),
        Tag(id: 'b', name: 'Comics', parentId: 'a', count: 0),
      ];
      await pump(tester);

      expect(
        find.descendant(
          of: _card('Living room'),
          matching: find.text('1 book · 1 sub-shelf'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('wears the large fan when it has covers to show', (
      tester,
    ) async {
      repo.tags = [
        Tag(id: 'a', name: 'Shelf 0', count: 2, coverPaths: const ['a.jpg']),
      ];
      await pump(tester);

      final tile = find.descendant(
        of: _card('Shelf 0'),
        matching: find.byType(ShelfThumbnail),
      );
      expect(tester.getSize(tile), const Size(92, 66));
      expect(find.byKey(const Key('shelfCardIcon')), findsNothing);
    });

    for (final (what, count, covers) in const [
      ('an empty shelf', 0, <String>[]),
      ('books with no cover', 2, <String>[]),
    ]) {
      testWidgets('wears the icon of a shelf, no fan, for $what', (
        tester,
      ) async {
        repo.tags = [
          Tag(id: 'a', name: 'Shelf 0', count: count, coverPaths: covers),
        ];
        await pump(tester);

        expect(find.byType(ShelfThumbnail), findsNothing);
        expect(find.byKey(const Key('shelfThumbnailGhost')), findsNothing);
        expect(find.byIcon(Icons.label), findsOneWidget);
      });
    }

    testWidgets('its icon says when it holds sub-shelves', (tester) async {
      repo.tags = [
        Tag(id: 'a', name: 'Shelf 0', count: 0),
        Tag(id: 'b', name: 'Sub', parentId: 'a', count: 0),
      ];
      await pump(tester);

      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('keeps the same height with the icon as with the fan', (
      tester,
    ) async {
      repo.tags = [
        Tag(id: 'a', name: 'With', count: 2, coverPaths: const ['a.jpg']),
        Tag(id: 'b', name: 'Without', count: 0),
      ];
      await pump(tester);

      expect(
        tester.getTopLeft(find.text('Without')).dy,
        tester.getTopLeft(find.text('With')).dy,
      );
    });

    testWidgets('opens the shelf', (tester) async {
      repo.tags = [Tag(id: 'a', name: 'Art & craft', count: 1)];
      await pump(tester);

      await tester.tap(_card('Art & craft'));
      await tester.pumpAndSettle();

      expect(navigated, ['/shelves?tag=Art+%26+craft']);
    });
  });

  testWidgets('the tab refresh notifier reloads the grid', (tester) async {
    final tabRefresh = ValueNotifier<int>(0);
    addTearDown(tabRefresh.dispose);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(
            value: ThemeProvider()..setLocaleSync(const Locale('en')),
          ),
          ChangeNotifierProvider<BookRefreshNotifier>.value(value: refresh),
          ChangeNotifierProvider<OwnershipPreferenceProvider>(
            create: (_) => OwnershipPreferenceProvider(),
          ),
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp(
          home: ShelvesScreen(isTabView: true, refreshNotifier: tabRefresh),
        ),
      ),
    );
    await tester.pumpAndSettle();

    repo.tags = [Tag(id: 'n', name: 'New one', count: 0)];
    tabRefresh.value++;
    await tester.pumpAndSettle();

    expect(_card('New one'), findsOneWidget);
  });

  testWidgets('a small card holds two lines of name at every text scale, and '
      'stays a 44 pt target', (tester) async {
    for (final scale in const [1.0, 1.29, 1.3, 2.0]) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: SizedBox(
                    width: 174,
                    height: ShelfCard.compactExtentFor(context),
                    child: ShelfCard.compact(
                      name: 'A rather long sub-shelf name',
                      books: 30,
                      subShelves: 3,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'at $scale');
      expect(
        ShelfCard.compactExtentFor(tester.element(find.byType(ShelfCard))),
        greaterThanOrEqualTo(44),
      );
    }
  });

  group('the colour of a card', () {
    final palettes = {
      'light': AppDesign.shelfTintsLight,
      'dark': AppDesign.shelfTintsDark,
    };

    palettes.forEach((name, tints) {
      test('$name: eight distinct colours', () {
        expect(tints.toSet(), hasLength(8));
      });

      for (final tint in tints) {
        final hex = tint.toARGB32().toRadixString(16);

        test('$name $hex: white text reads at 4.5:1 all along the gradient', () {
          final gradient = AppDesign.shelfGradient(tint);
          expect(gradient.colors.every((c) => c.a == 1), isTrue);
          for (final point in gradient.colors) {
            expect(
              contrastRatio(Colors.white, point),
              greaterThanOrEqualTo(4.5),
            );
          }
          // The lightest point is the tint, where the gradient ends.
          expect(gradient.colors.last, tint);
        });

        test('$name $hex: the icon reads at 3:1 on its translucent square', () {
          final square = Color.alphaBlend(
            Colors.white.withValues(alpha: 0.2),
            tint,
          );
          expect(contrastRatio(Colors.white, square), greaterThanOrEqualTo(3));
        });
      }
    });

    test('hangs on the id alone, by a hash pinned across runs', () {
      expect(AppDesign.shelfTint('s0', Brightness.light), const Color(0xFFE11D48));
      expect(
        AppDesign.shelfTint(
          '0191f3a2-7c44-7d10-9a31-5e2b8c4d1f60',
          Brightness.light,
        ),
        const Color(0xFF2563EB),
      );
    });

    test('a dark theme draws from its own palette, at the same index', () {
      final light = AppDesign.shelfTint('s0', Brightness.light);
      final dark = AppDesign.shelfTint('s0', Brightness.dark);
      expect(
        AppDesign.shelfTintsDark.indexOf(dark),
        AppDesign.shelfTintsLight.indexOf(light),
      );
    });

    testWidgets('a shelf keeps its colour wherever it sits in the grid', (
      tester,
    ) async {
      Gradient? groundOf(String name) =>
          (tester
                      .widget<Ink>(
                        find.descendant(
                          of: _card(name),
                          matching: find.byKey(const Key('shelfCardGround')),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .gradient;

      repo.tags = _roots(2);
      await pump(tester);
      expect(
        groundOf('Shelf 1'),
        AppDesign.shelfGradient(AppDesign.shelfTint('s1', Brightness.light)),
      );

      repo.tags = _roots(2).reversed.toList();
      await pump(tester);
      expect(
        groundOf('Shelf 1'),
        AppDesign.shelfGradient(AppDesign.shelfTint('s1', Brightness.light)),
      );
    });

    for (final style in const ['default', 'dark', 'minimal']) {
      testWidgets('$style: a coloured ground, no line, a tinted shadow, white '
          'text', (tester) async {
        final theme = ThemeRegistry.get(style)!.buildTheme(
          accentColor: Colors.blue,
        );
        await pump(tester, theme: theme);
        final tint = AppDesign.shelfTint('s0', theme.brightness);

        final material = tester.widget<Material>(
          find
              .descendant(of: _card('Shelf 0'), matching: find.byType(Material))
              .first,
        );
        expect(material.color, Colors.transparent);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side, BorderSide.none);
        expect(shape.borderRadius, BorderRadius.circular(18));

        final ground = tester.widget<Ink>(
          find.descendant(
            of: _card('Shelf 0'),
            matching: find.byKey(const Key('shelfCardGround')),
          ),
        );
        expect(
          (ground.decoration! as BoxDecoration).gradient,
          AppDesign.shelfGradient(tint),
        );

        final shadow = tester
            .widgetList<DecoratedBox>(
              find.ancestor(
                of: find.text('Shelf 0'),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((b) => b.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.boxShadow?.isNotEmpty ?? false)
            .boxShadow!
            .single;
        expect(shadow.color, tint.withValues(alpha: 0.28));

        for (final text in ['Shelf 0', '1 book']) {
          final painted = tester.widget<RichText>(
            find.descendant(
              of: find.descendant(
                of: _card('Shelf 0'),
                matching: find.text(text),
              ),
              matching: find.byType(RichText),
            ),
          );
          expect(painted.text.style!.color, Colors.white);
        }
      });
    }

    testWidgets('no count bubble and no menu on the card', (tester) async {
      await pump(tester);

      expect(
        find.descendant(
          of: _card('Shelf 0'),
          matching: find.byType(PopupMenuButton<String>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: _card('Shelf 0'), matching: find.text('1')),
        findsNothing,
      );
    });
  });

  group('its surfaces', () {
    /// The nearest box with a shadow around [of].
    BoxDecoration shadowAround(WidgetTester tester, Finder of) => tester
        .widgetList<DecoratedBox>(
          find.ancestor(of: of, matching: find.byType(DecoratedBox)),
        )
        .map((b) => b.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.boxShadow?.isNotEmpty ?? false);

    for (final (style, card, line) in const [
      ('default', Color(0xFFFFFFFF), Color(0xFFE7E5E4)),
      ('dark', Color(0xFF1E293B), Color(0xFF334155)),
      ('minimal', Color(0xFFFAFAFA), Color(0xFFE5E5E5)),
    ]) {
      ThemeData themeOf() =>
          ThemeRegistry.get(style)!.buildTheme(accentColor: Colors.blue);

      void expectSurface(WidgetTester tester, Finder of, double radius) {
        final material = tester.widget<Material>(
          find.descendant(of: of, matching: find.byType(Material)).first,
        );
        expect(material.color, card);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side.color, line);
        expect(shape.side.width, 1);
        expect(shape.borderRadius, BorderRadius.circular(radius));
      }

      testWidgets('$style: a small card too', (tester) async {
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
            child: MaterialApp(
              theme: themeOf(),
              home: Scaffold(
                body: ShelfCard.compact(
                  key: const Key('small'),
                  name: 'Comics',
                  books: 3,
                  subShelves: 0,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );

        expectSurface(tester, find.byKey(const Key('small')), 14);
      });

      testWidgets('$style: the "to shelve" line too', (tester) async {
        repo.unshelved = 2;
        await pump(tester, theme: themeOf());

        expectSurface(tester, _line, 12);
        expect(
          shadowAround(tester, find.textContaining('To shelve')).boxShadow,
          AppDesign.subtleShadow,
        );
      });
    }

    testWidgets('the values come from cardTheme, not from elsewhere in the '
        'theme', (tester) async {
      const ground = Color(0xFF112233);
      const line = Color(0xFF445566);
      repo.unshelved = 2;
      await pump(
        tester,
        theme: ThemeData(
          colorScheme: const ColorScheme.light(
            surface: Color(0xFFAA0000),
            outline: Color(0xFF00AA00),
          ),
          cardColor: const Color(0xFF0000AA),
          cardTheme: const CardThemeData(
            color: ground,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: line, width: 3),
            ),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(of: _line, matching: find.byType(Material)).first,
      );
      expect(material.color, ground);
      expect(
        (material.shape! as RoundedRectangleBorder).side,
        const BorderSide(color: line, width: 3),
      );
    });

    for (final style in const ['default', 'dark', 'minimal']) {
      testWidgets('$style: the number of a small card is quieter than its name, '
          'and still legible', (tester) async {
        final theme = ThemeRegistry.get(style)!.buildTheme(
          accentColor: Colors.blue,
        );
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
            child: MaterialApp(
              theme: theme,
              home: Scaffold(
                body: ShelfCard.compact(
                  name: 'Comics',
                  books: 3,
                  subShelves: 0,
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        final surface = theme.cardTheme.color!;
        Color colourOf(String text) => tester
            .widget<RichText>(
              find.descendant(
                of: find.text(text),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!
            .color!;

        final number = contrastRatio(colourOf('3'), surface);
        expect(number, greaterThanOrEqualTo(4.5));
        expect(number, lessThan(contrastRatio(colourOf('Comics'), surface)));
      });

      testWidgets('$style: "Organize" stays legible on the page gradient', (
        tester,
      ) async {
        final theme = ThemeRegistry.get(style)!.buildTheme(
          accentColor: Colors.blue,
        );
        await pump(tester, theme: theme);

        final colour = tester
            .widget<RichText>(
              find.descendant(
                of: find.text('Organize'),
                matching: find.byType(RichText),
              ),
            )
            .text
            .style!
            .color!;
        expect(
          contrastRatio(
            colour,
            AppDesign.pageGradientForTheme(style).colors.first,
          ),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    testWidgets('the row above the grid has no ground of its own', (
      tester,
    ) async {
      await pump(tester, width: 700);

      expect(
        find.ancestor(
          of: find.text('Organize'),
          matching: find.descendant(
            of: find.byKey(const Key('shelfCardsScroll')),
            matching: find.byWidgetPredicate(
              (w) => w is DecoratedBox || w is ColoredBox,
            ),
          ),
        ),
        findsNothing,
      );
    });
  });

  group('the row above the grid', () {
    testWidgets('on a phone: "Organize" and the add button floating', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Organize'), findsOneWidget);
      expect(find.text('Create a shelf'), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('from 600 pt: the add button joins the row, at its left', (
      tester,
    ) async {
      await pump(tester, width: 600);

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        tester.getTopLeft(find.text('Create a shelf')).dx,
        lessThan(tester.getTopLeft(find.text('Organize')).dx),
      );
    });

    for (final (width, gap) in const [(390.0, 12.0), (700.0, 16.0)]) {
      testWidgets('at $width pt it keeps $gap pt from the cards, like the cards '
          'between them', (tester) async {
        await pump(tester, width: width);

        final organize = find.ancestor(
          of: find.text('Organize'),
          matching: find.byWidgetPredicate((w) => w is TextButton),
        );
        expect(
          tester.getTopLeft(_card('Shelf 0')).dy -
              tester.getBottomLeft(organize).dy,
          gap,
        );
      });
    }

    testWidgets('it keeps its distance from the tabs with no "to shelve" line', (
      tester,
    ) async {
      await pump(tester);

      final organize = find.ancestor(
        of: find.text('Organize'),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      );
      expect(tester.getTopLeft(organize).dy, 8);
    });

    testWidgets('the add button has the corners of the app buttons', (
      tester,
    ) async {
      await pump(tester, width: 700);

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Create a shelf'),
          matching: find.byWidgetPredicate((w) => w is OutlinedButton),
        ),
      );
      expect(
        button.style?.shape?.resolve(const {}),
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
      expect(
        button.style?.textStyle?.resolve(const {})?.fontWeight,
        FontWeight.w600,
      );
    });

    testWidgets('"Organize" leads to the organizing route', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Organize'));
      await tester.pumpAndSettle();

      expect(navigated, ['/shelves-management']);
    });
  });

  group('the "to shelve" line', () {
    testWidgets('names the pile and its count, 44 pt high, above the row', (
      tester,
    ) async {
      repo.unshelved = 569;
      await pump(tester);

      expect(find.textContaining('To shelve'), findsOneWidget);
      expect(find.textContaining('569 books'), findsOneWidget);
      expect(tester.getSize(_line).height, greaterThanOrEqualTo(44));
      expect(
        tester.getTopLeft(_line).dy,
        lessThan(tester.getTopLeft(find.text('Organize')).dy),
      );
    });

    testWidgets('reads as one button with the whole sentence', (tester) async {
      final handle = tester.ensureSemantics();
      repo.unshelved = 2;
      await pump(tester);

      expect(
        find.bySemanticsLabel('To shelve, 2 books on no shelf'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('uses the singular for one book', (tester) async {
      repo.unshelved = 1;
      await pump(tester);

      expect(
        find.descendant(of: _line, matching: find.textContaining('1 book')),
        findsOneWidget,
      );
      expect(find.textContaining('1 books'), findsNothing);
    });

    testWidgets('follows a book change elsewhere, and disappears at zero', (
      tester,
    ) async {
      repo.unshelved = 2;
      await pump(tester);
      expect(_line, findsOneWidget);

      repo.unshelved = 0;
      refresh.refresh();
      await tester.pumpAndSettle();

      expect(_line, findsNothing);
    });

    testWidgets('is absent when every book is on a shelf', (tester) async {
      await pump(tester);

      expect(_line, findsNothing);
    });

    testWidgets('leads to the books to shelve', (tester) async {
      repo.unshelved = 2;
      await pump(tester);

      await tester.tap(find.textContaining('To shelve'));
      await tester.pumpAndSettle();

      expect(navigated.single, startsWith('/shelves?unshelved=1'));
    });

    testWidgets('its cross hides it and keeps the count of the moment', (
      tester,
    ) async {
      repo.unshelved = 5;
      await pump(tester);

      await tester.tap(_hide);
      await tester.pumpAndSettle();

      expect(_line, findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_dismissedKey), 5);
    });

    testWidgets('its cross hands the focus on to the row below', (tester) async {
      repo.unshelved = 5;
      await pump(tester);

      await tester.tap(_hide);
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'organizeShelves',
      );
    });

    testWidgets('its cross is a 44 pt named button', (tester) async {
      repo.unshelved = 5;
      await pump(tester);

      final size = tester.getSize(_hide);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('stays hidden when the app comes back at the same count', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        _dismissedKey: 5,
      });
      repo.unshelved = 5;
      await pump(tester);

      expect(_line, findsNothing);
    });

    testWidgets('comes back with a higher count', (tester) async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        _dismissedKey: 5,
      });
      repo.unshelved = 5;
      await pump(tester);
      expect(_line, findsNothing);

      repo.unshelved = 6;
      refresh.refresh();
      await tester.pumpAndSettle();

      expect(_line, findsOneWidget);
    });

    testWidgets('a count that falls, even to the zero of a failed read, keeps '
        'it hidden up to the number it was hidden at', (tester) async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        _dismissedKey: 5,
      });
      repo.unshelved = 3;
      await pump(tester);
      expect(_line, findsNothing);

      repo.unshelved = 0;
      refresh.refresh();
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(_dismissedKey), 5);

      repo.unshelved = 5;
      refresh.refresh();
      await tester.pumpAndSettle();
      expect(_line, findsNothing);

      repo.unshelved = 6;
      refresh.refresh();
      await tester.pumpAndSettle();
      expect(_line, findsOneWidget);
    });

    testWidgets('heads the empty state too', (tester) async {
      repo
        ..tags = []
        ..unshelved = 2;
      await pump(tester);

      expect(_line, findsOneWidget);
    });
  });
}
