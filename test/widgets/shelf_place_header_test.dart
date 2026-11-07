import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/theme/app_design.dart';
import 'package:bibliogenius/widgets/shelf_card.dart';
import 'package:bibliogenius/widgets/shelf_place_header.dart';
import 'package:bibliogenius/widgets/shelf_thumbnail.dart';

/// The head of a shelf's page recalls the colour and the rounding of the card it
/// was entered by, in a corner that holds the covers.

Tag _shelf(String id, {String? parent}) =>
    Tag(id: id, name: id, parentId: parent, count: 0);

ShelfPlace _place({required Tag shelf, int? tintSlot, bool canAct = true}) =>
    ShelfPlace(
      requestedName: shelf.name,
      shelf: shelf,
      ancestors: const [],
      subShelves: const [],
      books: 0,
      booksOf: (_) => 0,
      subShelvesOf: (_) => 0,
      hidden: false,
      canAct: canAct,
      tintSlot: tintSlot,
      actions: ShelfPlaceActions(
        onBack: () {},
        onOpen: (_) {},
        onRename: () {},
        onAddSubShelf: () {},
        onMove: () {},
        onDelete: () {},
        onOrganize: () {},
      ),
    );

Future<void> _pump(
  WidgetTester tester,
  ShelfPlace place, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: ThemeProvider()..setLocaleSync(const Locale('en')),
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(child: ShelfPlaceHeader(place: place)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _corner = find.byKey(const Key('shelfPlaceCorner'));
final _fan = find.byKey(const Key('shelfPlaceFan'));
final _title = find.byKey(const Key('shelfHeaderTitle'));
final _menu = find.byKey(const Key('shelfPlaceMenu'));

BoxDecoration _cornerDecoration(WidgetTester tester) =>
    tester.widget<DecoratedBox>(_corner).decoration as BoxDecoration;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Real labels: a bare key would give the counts the whole width.
    TranslationService.setPoTranslationsForTest({
      'en': {
        'displayed_books_count': '%d book',
        'displayed_books_count_plural': '%d books',
      },
    });
  });
  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  group('the colour of a page', () {
    final tags = [
      _shelf('living'),
      _shelf('study'),
      _shelf('crime', parent: 'living'),
      _shelf('nordic', parent: 'crime'),
      _shelf('essays', parent: 'study'),
    ];
    final slots = ShelfCard.tintSlotsOf(tags);

    int? slotOf(String id) => ShelfCard.placeTintSlot(
      tags.firstWhere((t) => t.id == id),
      shown: tags,
      all: tags,
    );

    test('a first-level shelf wears the colour of its card', () {
      expect(slotOf('living'), slots['living']);
      expect(slotOf('study'), slots['study']);
    });

    test('a sub-shelf wears the colour of its first level, however deep', () {
      expect(slotOf('crime'), slots['living']);
      expect(slotOf('nordic'), slots['living']);
      expect(slotOf('essays'), slots['study']);
    });

    test('a shelf waiting on its Undo keeps the colours of the others', () {
      final shown = tags.where((t) => t.id != 'study').toList();
      expect(
        ShelfCard.placeTintSlot(tags.first, shown: shown, all: tags),
        slots['living'],
      );
    });

    test('a shelf no listing knows has no colour yet', () {
      expect(
        ShelfCard.placeTintSlot(
          Tag(id: 'legacy:route', name: 'unknown', count: 0),
          shown: tags,
          all: tags,
        ),
        isNull,
      );
    });
  });

  group('the corner', () {
    for (final brightness in Brightness.values) {
      testWidgets('it carries the gradient of the card, $brightness', (
        tester,
      ) async {
        await _pump(
          tester,
          _place(shelf: _shelf('living'), tintSlot: 3),
          brightness: brightness,
        );

        expect(
          _cornerDecoration(tester).gradient,
          AppDesign.shelfGradient(
            AppDesign.shelfTint(3, brightness).ground,
            brightness,
          ),
        );
      });
    }

    testWidgets('it rounds the two angles that face the page, as a card does', (
      tester,
    ) async {
      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));

      expect(
        _cornerDecoration(tester).borderRadius,
        const BorderRadius.horizontal(left: Radius.circular(20)),
      );
    });

    for (final width in [320.0, 390.0, 700.0, 1024.0, 1440.0]) {
      testWidgets(
        'at $width pt, it hangs from the top right and holds the fan',
        (tester) async {
          await _pump(
            tester,
            _place(shelf: _shelf('living'), tintSlot: 0),
            width: width,
          );

          expect(tester.takeException(), isNull);
          final corner = tester.getRect(_corner);
          final fan = tester.getRect(_fan);
          expect(corner.top, 12);
          expect(corner.right, width);
          expect(corner.left, lessThan(fan.left));
          expect(corner.right, greaterThan(fan.right));
          expect(corner.top, lessThan(fan.top));
          expect(corner.bottom, greaterThan(fan.bottom));
        },
      );
    }

    for (final width in [700.0, 1024.0, 1440.0]) {
      testWidgets('at $width pt, it stops at the proportions of a card', (
        tester,
      ) async {
        await _pump(
          tester,
          _place(shelf: _shelf('living'), tintSlot: 0),
          width: width,
        );

        final corner = tester.getRect(_corner);
        expect(corner.width, 300);
        expect(corner.right, width);
        expect(tester.getRect(_fan).right, width - 18);
      });
    }

    testWidgets('on a phone, it takes what the text leaves, up to a margin', (
      tester,
    ) async {
      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));

      final corner = tester.getRect(_corner);
      expect(corner.width, greaterThan(148));
      expect(corner.width, lessThanOrEqualTo(300));
      expect(corner.left - tester.getRect(_menu).right, moreOrLessEquals(12));
    });

    testWidgets('the covers have the air of a card, above as under', (
      tester,
    ) async {
      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));

      final corner = tester.getRect(_corner);
      final fan = tester.getRect(_fan);
      // In its frame, the centre cover starts 7 pt down and the tip of a leaning
      // one ends 74 pt down; on a card, that tip leaves 12.4 pt of its band.
      expect((fan.top + 7) - corner.top, closeTo(12.44, 0.01));
      expect(corner.bottom - (fan.top + 74.02), closeTo(12.44, 0.01));
    });

    testWidgets('a long name leaves it the fan and its margins', (
      tester,
    ) async {
      await _pump(
        tester,
        _place(
          shelf: Tag(
            id: 'long',
            name: 'A very long name of a shelf that goes on and on and on',
            count: 0,
          ),
          tintSlot: 0,
        ),
      );

      expect(tester.getSize(_corner).width, 148);
    });

    testWidgets('its watermark shows across from the fan, for a colour only', (
      tester,
    ) async {
      final watermark = find.byKey(const Key('shelfPlaceWatermark'));

      await _pump(
        tester,
        _place(shelf: _shelf('living'), tintSlot: 0),
        width: 1024,
      );
      final icon = tester.widget<Icon>(watermark);
      expect(icon.icon, Icons.shelves);
      expect(icon.color, AppDesign.shelfWatermarkColor);
      expect(
        tester.getRect(watermark).right,
        lessThan(tester.getRect(_fan).left),
      );

      await _pump(tester, _place(shelf: _shelf('living')), width: 1024);
      expect(watermark, findsNothing);
    });

    testWidgets('it does not move when the menu comes with the listing', (
      tester,
    ) async {
      await _pump(
        tester,
        _place(shelf: _shelf('living'), tintSlot: 0, canAct: false),
      );
      final before = tester.getRect(_corner);

      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));

      expect(tester.getRect(_corner), before);
    });

    for (final width in [320.0, 390.0, 1024.0]) {
      testWidgets('at $width pt, a long name stays clear of it', (
        tester,
      ) async {
        await _pump(
          tester,
          _place(
            shelf: Tag(
              id: 'long',
              name: 'A very long name of a shelf that goes on and on and on',
              count: 0,
            ),
            tintSlot: 0,
          ),
          width: width,
        );

        expect(tester.takeException(), isNull);
        final corner = tester.getRect(_corner);
        expect(tester.getRect(_title).right, lessThanOrEqualTo(corner.left));
        expect(tester.getRect(_menu).right, lessThanOrEqualTo(corner.left));
      });
    }

    testWidgets('large text on a phone neither overflows nor reaches it', (
      tester,
    ) async {
      await _pump(
        tester,
        _place(shelf: _shelf('living'), tintSlot: 0),
        textScale: 2,
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(_title).right,
        lessThanOrEqualTo(tester.getRect(_corner).left),
      );
    });

    testWidgets('with no colour yet, it takes the same room with no ground', (
      tester,
    ) async {
      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));
      final size = tester.getSize(_corner);

      await _pump(tester, _place(shelf: _shelf('living')));

      expect(_cornerDecoration(tester).gradient, isNull);
      expect(tester.getSize(_corner), size);
      expect(tester.widget<ShelfThumbnail>(_fan).ghostColor, isNull);
    });

    testWidgets('an empty fan is drawn for the colour', (tester) async {
      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));

      expect(
        tester.widget<ShelfThumbnail>(_fan).ghostColor,
        AppDesign.shelfBandGhostColor,
      );
    });
  });

  group('the menu', () {
    testWidgets('it follows the name, 30 pt to see and 44 pt to touch', (
      tester,
    ) async {
      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));

      final button = find.descendant(
        of: _menu,
        matching: find.byType(IconButton),
      );
      expect(tester.getSize(button), const Size.square(44));
      expect(
        tester.getSize(find.byKey(const Key('shelfPlaceMenuDisc'))),
        const Size.square(30),
      );
      final title = tester.getRect(_title);
      final menu = tester.getRect(button);
      expect(menu.left, greaterThanOrEqualTo(title.right));
      expect(menu.left - title.right, lessThan(12));
      expect(menu.center.dy, moreOrLessEquals(title.center.dy, epsilon: 1));
    });

    testWidgets('the name does not move when it comes with the listing', (
      tester,
    ) async {
      await _pump(
        tester,
        _place(shelf: _shelf('living'), tintSlot: 0, canAct: false),
      );
      expect(_menu, findsNothing);
      final before = tester.getRect(_title);

      await _pump(tester, _place(shelf: _shelf('living'), tintSlot: 0));

      expect(tester.getRect(_title), before);
    });
  });
}
