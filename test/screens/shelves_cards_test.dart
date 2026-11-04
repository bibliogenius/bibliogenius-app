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
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
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
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<BookRefreshNotifier>.value(value: refresh),
          ChangeNotifierProvider<OwnershipPreferenceProvider>(
            create: (_) => OwnershipPreferenceProvider(),
          ),
          Provider<TagRepository>.value(value: repo),
        ],
        child: MaterialApp.router(routerConfig: router),
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

    testWidgets('wears the large thumbnail', (tester) async {
      await pump(tester);

      final tile = find.descendant(
        of: _card('Shelf 0'),
        matching: find.byType(ShelfThumbnail),
      );
      expect(tester.getSize(tile), const Size(92, 66));
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
