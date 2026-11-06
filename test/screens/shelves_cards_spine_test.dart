import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/settings/advanced_section.dart';
import 'package:bibliogenius/screens/settings/settings_scope.dart';
import 'package:bibliogenius/screens/shelves_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/theme/app_design.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';
import 'package:bibliogenius/utils/accessible_color.dart';
import 'package:bibliogenius/widgets/shelf_card.dart';
import 'package:bibliogenius/widgets/shelf_thumbnail.dart';

/// The card dressed along a strip, next to the one under a band, to compare
/// them on a device: only one survives.

class _Repo implements TagRepository {
  final List<Tag> tags;

  _Repo(this.tags);

  @override
  Future<List<Tag>> getTags() async => tags;

  @override
  Future<int> countUnshelvedBooks() async => 0;

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

Finder _card(String name) => find.byKey(ValueKey('shelfCard:$name'));

Finder _inCard(String name, String key) =>
    find.descendant(of: _card(name), matching: find.byKey(Key(key)));

const _twoLines = 'A name long enough to run over two lines';

void main() {
  setUpAll(ThemeRegistry.initialize);

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'displayed_books_count': '%d book',
        'displayed_books_count_plural': '%d books',
        'sub_shelves_count': '%d sub-shelf',
        'sub_shelves_count_plural': '%d sub-shelves',
      },
    });
    shelfCardVariant.value = ShelfCardVariant.spine;
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
    shelfCardVariant.value = ShelfCardVariant.band;
  });

  ThemeData themeOf(String style) =>
      ThemeRegistry.get(style)!.buildTheme(accentColor: Colors.blue);

  Future<void> pump(
    WidgetTester tester,
    List<Tag> tags, {
    double width = 390,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
          ),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          ChangeNotifierProvider<OwnershipPreferenceProvider>(
            create: (_) => OwnershipPreferenceProvider(),
          ),
          Provider<TagRepository>.value(value: _Repo(tags)),
        ],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: ShelvesScreen(isTabView: true)),
        ),
      ),
    );
    // Not to settle: a cover that cannot load keeps a spinner going.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void expectLaidOut(WidgetTester tester, String name, String books) {
    final card = tester.getRect(_card(name));
    final title = tester.getRect(
      find.descendant(of: _card(name), matching: find.text(name)),
    );
    final count = tester.getRect(
      find.descendant(of: _card(name), matching: find.text(books)),
    );
    expect(title.left, card.left + 18);
    expect(count.left, card.left + 18);
    expect(title.right, lessThanOrEqualTo(card.right - 10));
    expect(count.top, greaterThanOrEqualTo(title.bottom));
    expect(count.bottom, card.bottom - 13);

    // The frame of the fan above the name, even on two lines.
    final frame = find.descendant(
      of: _card(name),
      matching: find.byType(ShelfThumbnail),
    );
    expect(tester.getTopLeft(frame), card.topLeft + const Offset(10, 13));
    expect(tester.getRect(frame).bottom, lessThanOrEqualTo(title.top));
    expect(tester.takeException(), isNull);
  }

  for (final style in const ['default', 'dark', 'minimal']) {
    group(style, () {
      testWidgets('white card, no band: a strip of 7 pt from the shelf\'s '
          'ground down to its ink, inside the line of the card', (tester) async {
        final theme = themeOf(style);
        await pump(tester, [
          Tag(id: 's0', name: 'Shelf 0', count: 1),
        ], theme: theme);
        final tint = AppDesign.shelfTint(
          AppDesign.shelfTintHashSlot('s0'),
          theme.brightness,
        );

        expect(_inCard('Shelf 0', 'shelfCardGround'), findsNothing);

        final card = tester.getRect(_card('Shelf 0'));
        final strip = _inCard('Shelf 0', 'shelfCardSpine');
        final box = tester.getRect(strip);
        final line = shelfSurfaceSide(theme).width;
        expect(line, greaterThan(0));
        expect(box.left, card.left + line);
        expect(box.width, 7);
        expect(box.top, card.top);
        expect(box.height, card.height);

        final gradient =
            (tester.widget<Ink>(strip).decoration! as BoxDecoration).gradient!
                as LinearGradient;
        expect(gradient.colors, [tint.ground, tint.ink]);
        expect(gradient.begin, Alignment.topCenter);
        expect(gradient.end, Alignment.bottomCenter);

        final material = tester.widget<Material>(
          find
              .descendant(of: _card('Shelf 0'), matching: find.byType(Material))
              .first,
        );
        expect(material.color, theme.cardColor);
      });

      testWidgets('the watermark in the colour of the shelf, behind the rest', (
        tester,
      ) async {
        final theme = themeOf(style);
        await pump(tester, [
          Tag(id: 's0', name: 'Shelf 0', count: 1),
        ], theme: theme);
        final tint = AppDesign.shelfTint(
          AppDesign.shelfTintHashSlot('s0'),
          theme.brightness,
        );

        final watermark = _inCard('Shelf 0', 'shelfCardWatermark');
        expect(
          tester.widget<Icon>(watermark).color,
          tint.ground.withValues(alpha: 0.16),
        );
        expect(
          tester.getTopRight(watermark),
          tester.getTopRight(_card('Shelf 0')) + const Offset(20, -20),
        );
        final layers = tester
            .widget<Stack>(
              find.ancestor(of: watermark, matching: find.byType(Stack)).first,
            )
            .children;
        expect(
          find.descendant(
            of: find.byWidget(layers.first),
            matching: find.byKey(const Key('shelfCardWatermark')),
          ),
          findsOneWidget,
        );
      });

      testWidgets('170 pt in two columns, two lines of name fit', (
        tester,
      ) async {
        await pump(tester, [
          Tag(id: 'a', name: _twoLines, count: 3),
          Tag(id: 'b', name: 'Short', count: 3),
        ], theme: themeOf(style));

        expect(
          tester.getTopLeft(_card(_twoLines)).dy,
          tester.getTopLeft(_card('Short')).dy,
        );
        expect(tester.getSize(_card(_twoLines)).height, 170);
        expect(
          tester.getSize(find.text(_twoLines)).height,
          greaterThan(tester.getSize(find.text('Short')).height * 1.5),
          reason: 'the name does take two lines',
        );
        expectLaidOut(tester, _twoLines, '3 books');
        expectLaidOut(tester, 'Short', '3 books');
      });

      testWidgets('one column on a narrow screen, the same card', (
        tester,
      ) async {
        await pump(tester, [
          Tag(id: 'a', name: _twoLines, count: 3),
        ], width: 320, theme: themeOf(style));

        expect(tester.getSize(_card(_twoLines)).width, 320 - 2 * 16);
        expect(tester.getSize(_card(_twoLines)).height, 170);
        expectLaidOut(tester, _twoLines, '3 books');
      });

      testWidgets('text at 1.3: one column, the card grows, nothing overflows', (
        tester,
      ) async {
        await pump(
          tester,
          [Tag(id: 'a', name: _twoLines, count: 3)],
          textScale: 1.3,
          theme: themeOf(style),
        );

        expect(tester.getSize(_card(_twoLines)).width, 390 - 2 * 16);
        expect(tester.getSize(_card(_twoLines)).height, greaterThan(170));
        expectLaidOut(tester, _twoLines, '3 books');
      });

      testWidgets('text at 1.29, 390 pt: two columns, nothing overflows', (
        tester,
      ) async {
        await pump(
          tester,
          [
            Tag(id: 'a', name: _twoLines, count: 3),
            Tag(id: 'b', name: 'Short', count: 3),
          ],
          textScale: 1.29,
          theme: themeOf(style),
        );

        expect(
          tester.getTopLeft(_card(_twoLines)).dy,
          tester.getTopLeft(_card('Short')).dy,
        );
        expectLaidOut(tester, _twoLines, '3 books');
      });

      testWidgets('the folder and the number at the bottom right, on the line '
          'of the count, in the ink of the shelf, with no ground', (
        tester,
      ) async {
        final theme = themeOf(style);
        await pump(tester, [
          Tag(id: 's0', name: 'Shelf 0', count: 1),
          Tag(id: 'b', name: 'Sub', parentId: 's0', count: 0),
        ], theme: theme);
        final tint = AppDesign.shelfTint(
          AppDesign.shelfTintHashSlot('s0'),
          theme.brightness,
        );

        expect(_inCard('Shelf 0', 'shelfCardSubShelves'), findsNothing);
        final mark = _inCard('Shelf 0', 'shelfCardSubShelvesMark');
        final card = tester.getRect(_card('Shelf 0'));
        final box = tester.getRect(mark);
        final count = tester.getRect(
          find.descendant(of: _card('Shelf 0'), matching: find.text('1 book')),
        );
        expect(box.right, card.right - 10);
        expect(box.bottom, card.bottom - 13);
        expect(box.center.dy, count.center.dy);
        // Clear of the watermark, which stops 80 pt below the top of the card.
        expect(box.top, greaterThan(card.top + 80));
        expect(tester.takeException(), isNull);

        expect(
          find.descendant(
            of: mark,
            matching: find.byWidgetPredicate(
              (w) => w is Container || w is DecoratedBox || w is ColoredBox,
            ),
          ),
          findsNothing,
        );
        expect(
          tester
              .widget<RichText>(
                find.descendant(
                  of: find.descendant(of: mark, matching: find.text('1')),
                  matching: find.byType(RichText),
                ),
              )
              .text
              .style!
              .color,
          tint.ink,
        );
        final icon = tester.widget<Icon>(
          find.descendant(of: mark, matching: find.byType(Icon)),
        );
        expect(icon.icon, Icons.folder);
        expect(icon.color, tint.ink);
      });

      testWidgets('no mark with no sub-shelf', (tester) async {
        await pump(tester, [
          Tag(id: 's0', name: 'Shelf 0', count: 1),
        ], theme: themeOf(style));

        expect(_inCard('Shelf 0', 'shelfCardSubShelvesMark'), findsNothing);
      });

      testWidgets('the sub-shelves are still said to a screen reader, once', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pump(tester, [
          Tag(id: 's0', name: 'Shelf 0', count: 2),
          Tag(id: 'b', name: 'Sub', parentId: 's0', count: 0),
          Tag(id: 'c', name: 'Other', parentId: 's0', count: 0),
        ], theme: themeOf(style));

        expect(
          tester.getSemantics(_card('Shelf 0')).label,
          'Shelf 0, 2 books, 2 sub-shelves',
        );
        handle.dispose();
      });

      for (var slot = 0; slot < 8; slot++) {
        testWidgets('slot $slot: everything stays legible hovered and pressed, '
            'and a focus ring says the keyboard is there', (tester) async {
          final theme = themeOf(style);
          final tint = AppDesign.shelfTint(slot, theme.brightness);
          final card = shelfSurfaceColor(theme);
          await tester.pumpWidget(
            ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SizedBox(
                    width: 200,
                    height: 170,
                    child: ShelfCard(
                      tintSlot: slot,
                      name: 'A shelf',
                      books: 0,
                      subShelves: 2,
                      onTap: () {},
                    ),
                  ),
                ),
              ),
            ),
          );

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

          final well = tester.widget<InkWell>(find.byType(InkWell));
          Color veiled(Color under, List<Color> veils) => veils.fold(
            under,
            (under, over) => Color.alphaBlend(over, under),
          );
          final touch = [well.highlightColor!, well.splashColor!];
          final held = [well.hoverColor!, ...touch];
          for (final state in [
            <Color>[],
            [well.hoverColor!],
            touch,
            held,
          ]) {
            for (final text in ['A shelf', '0 books']) {
              expect(
                contrastRatio(colourOf(text), veiled(card, state)),
                greaterThanOrEqualTo(4.5),
                reason: '"$text" on the card',
              );
            }
            expect(
              contrastRatio(tint.ink, veiled(card, state)),
              greaterThanOrEqualTo(4.5),
              reason: 'the mark of the sub-shelves',
            );
          }

          expect(well.focusColor, Colors.transparent);
          final ring = find.byKey(const Key('shelfCardFocusRing'));
          expect(ring, findsNothing);
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          addTearDown(
            () => FocusManager.instance.highlightStrategy =
                FocusHighlightStrategy.automatic,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final line =
              ((tester.widget<DecoratedBox>(ring).decoration as BoxDecoration)
                          .border!
                      as Border)
                  .top;
          expect(line.color, tint.ink);
          expect(contrastRatio(line.color, card), greaterThanOrEqualTo(3));
        });
      }
    });
  }

  group('a shelf with no cover to show', () {
    for (final (what, count) in const [
      ('an empty shelf', 0),
      ('books with no cover', 2),
    ]) {
      testWidgets('wears the empty fan, in the grey of the theme, for $what', (tester) async {
        await pump(tester, [Tag(id: 'a', name: 'Shelf 0', count: count)]);

        expect(_inCard('Shelf 0', 'shelfThumbnailGhost'), findsOneWidget);
        expect(
          tester.renderObject(_inCard('Shelf 0', 'shelfThumbnailGhost')),
          paints..path(
            color: ThemeData().colorScheme.onSurface.withValues(alpha: 0.38),
          ),
        );
        expect(
          tester.getTopLeft(_inCard('Shelf 0', 'shelfThumbnailGhost')),
          tester.getTopLeft(_card('Shelf 0')) + const Offset(10, 13),
        );
      });
    }

    testWidgets('with covers it wears them, not the outline', (tester) async {
      await pump(tester, [
        Tag(id: 'a', name: 'Shelf 0', count: 2, coverPaths: const ['a.jpg']),
      ]);

      expect(_inCard('Shelf 0', 'shelfThumbnailGhost'), findsNothing);
    });
  });

  testWidgets('the grid follows the switch, and goes back', (tester) async {
    final tags = [Tag(id: 'a', name: 'Shelf 0', count: 0)];
    await pump(tester, tags);
    expect(_inCard('Shelf 0', 'shelfCardSpine'), findsOneWidget);

    shelfCardVariant.value = ShelfCardVariant.band;
    await tester.pump();

    expect(_inCard('Shelf 0', 'shelfCardSpine'), findsNothing);
    expect(_inCard('Shelf 0', 'shelfCardGround'), findsOneWidget);
    expect(_inCard('Shelf 0', 'shelfThumbnailGhost'), findsOneWidget);
  });

  testWidgets('a small card stays as it is', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
        child: MaterialApp(
          home: Scaffold(
            body: ShelfCard.compact(
              name: 'Comics',
              books: 3,
              subShelves: 2,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('shelfCardSpine')), findsNothing);
    expect(find.byKey(const Key('shelfCardWatermark')), findsNothing);
  });

  group('the switch in the settings', () {
    Future<void> pumpToggle(WidgetTester tester, Widget toggle) =>
        tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider()..setLocaleSync(const Locale('en')),
            child: MaterialApp(
              home: Scaffold(body: ListView(children: [toggle])),
            ),
          ),
        );

    setUp(() => shelfCardVariant.value = ShelfCardVariant.band);

    testWidgets('is one untranslated row outside a release, starting on A', (
      tester,
    ) async {
      await pumpToggle(tester, const ShelfCardVariantToggle());

      expect(find.text('Shelf cards: variant B'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isFalse);
    });

    testWidgets('changes the variant, and saves nothing', (tester) async {
      await pumpToggle(tester, const ShelfCardVariantToggle());
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getKeys().toSet();

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      expect(shelfCardVariant.value, ShelfCardVariant.spine);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue);
      expect(prefs.getKeys(), before);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(shelfCardVariant.value, ShelfCardVariant.band);
    });

    testWidgets('stays out of the results of a search', (tester) async {
      final data = SettingsData();
      addTearDown(data.dispose);
      await pumpToggle(
        tester,
        SettingsScope(
          data: data,
          query: 'reset',
          child: const ShelfCardVariantToggle(),
        ),
      );

      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('is absent from a release', (tester) async {
      await pumpToggle(tester, const ShelfCardVariantToggle(isRelease: true));

      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('Shelf cards: variant B'), findsNothing);
    });

    // A test never runs as a release: kReleaseMode is a constant, false here.
    // So the source has to say that the row hangs on it, and that the section
    // leaves it the default.
    test('the row goes by the release flag, and the section does not force it',
        () {
      final source = File(
        'lib/screens/settings/advanced_section.dart',
      ).readAsStringSync();

      expect(source, contains('this.isRelease = kReleaseMode'));
      expect(source, contains('if (isRelease ||'));
      expect(source, contains('const ShelfCardVariantToggle(),'));
    });

    testWidgets('the settings section carries it', (tester) async {
      tester.view.physicalSize = const Size(600, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpToggle(tester, const AdvancedSettingsSection());

      expect(find.text('Shelf cards: variant B'), findsOneWidget);
    });
  });
}
