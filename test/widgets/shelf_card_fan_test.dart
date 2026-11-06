import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/shelves_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';
import 'package:bibliogenius/widgets/shelf_thumbnail.dart';

/// Where the covers of a fan really fall on the band of a card, tilted as they
/// are, against the pill and the name.
///
/// In a file of its own: it loads a real font, which would change the metrics
/// of every test run after it. The square glyphs of the test font make digits
/// far wider than any font a device has.

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

/// Roboto as the SDK ships it, under the families the themes ask for: no theme
/// bundles a font, so an Android device falls back on this one.
Future<void> _loadRoboto() async {
  final sdk = Platform.resolvedExecutable.split('/bin/cache/').first;
  final dir = '$sdk/bin/cache/artifacts/material_fonts';
  ByteData read(String file) =>
      ByteData.sublistView(File('$dir/$file').readAsBytesSync());
  for (final family in const ['Inter', 'Roboto']) {
    await (FontLoader(family)
          ..addFont(Future.value(read('Roboto-Regular.ttf')))
          ..addFont(Future.value(read('Roboto-Bold.ttf'))))
        .load();
  }
}

void main() {
  setUpAll(ThemeRegistry.initialize);

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'displayed_books_count_plural': '%d books',
        'sub_shelves_count_plural': '%d sub-shelves',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  final card = find.byKey(const ValueKey('shelfCard:Parent'));

  /// A parent with three covers and [subShelves] sub-shelves, on the real grid.
  Future<void> pumpGrid(
    WidgetTester tester, {
    required double width,
    required double textScale,
    required String style,
    int subShelves = 12,
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
          Provider<TagRepository>.value(
            value: _Repo([
              Tag(
                id: 'p',
                name: 'Parent',
                count: 3,
                coverPaths: const ['a.jpg', 'b.jpg', 'c.jpg'],
              ),
              Tag(id: 'q', name: 'Other', count: 1),
              for (var i = 0; i < subShelves; i++)
                Tag(id: 'c$i', name: 'Child $i', parentId: 'p', count: 0),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: ThemeRegistry.get(style)!.buildTheme(accentColor: Colors.blue),
          home: const Scaffold(body: ShelvesScreen(isTabView: true)),
        ),
      ),
    );
    // Not to settle: a cover that cannot load keeps a spinner going.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The box the tilted covers really reach, not the frame of the fan.
  Rect coversOf(WidgetTester tester) {
    final tilts = find.descendant(
      of: find.descendant(of: card, matching: find.byType(ShelfThumbnail)),
      matching: find.byType(Transform),
    );
    expect(tilts, findsNWidgets(3), reason: 'the three covers of the fan');
    final points = [
      for (final element in tilts.evaluate())
        for (final corner in () {
          final tilt = element.renderObject! as RenderTransform;
          final cover = tilt.child!;
          return [
            Offset.zero,
            cover.size.topRight(Offset.zero),
            cover.size.bottomLeft(Offset.zero),
            cover.size.bottomRight(Offset.zero),
          ].map(cover.localToGlobal);
        }())
          corner,
    ];
    final xs = points.map((p) => p.dx).toList()..sort();
    final ys = points.map((p) => p.dy).toList()..sort();
    return Rect.fromLTRB(xs.first, ys.first, xs.last, ys.last);
  }

  for (final style in const ['default', 'dark', 'minimal']) {
    for (final width in const [360.0, 375.0]) {
      testWidgets(
        '$style, $width pt, text at 1.29: a pill of two digits covers '
        'no cover',
        (tester) async {
          await tester.runAsync(_loadRoboto);
          await pumpGrid(tester, width: width, textScale: 1.29, style: style);

          // Two columns, as the grid has them at this size.
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('shelfCard:Other'))).dy,
            tester.getTopLeft(card).dy,
          );
          final pill = find.descendant(
            of: card,
            matching: find.byKey(const Key('shelfCardSubShelves')),
          );
          expect(
            find.descendant(of: pill, matching: find.text('12')),
            findsOneWidget,
          );
          expect(
            tester.getTopLeft(pill).dx,
            greaterThan(coversOf(tester).right),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('$style: the left edge of the fan lines up with the name', (
      tester,
    ) async {
      await pumpGrid(tester, width: 390, textScale: 1, style: style);

      expect(
        coversOf(tester).left,
        closeTo(
          tester
              .getTopLeft(
                find.descendant(of: card, matching: find.text('Parent')),
              )
              .dx,
          1,
        ),
      );
    });
  }

  testWidgets('the fan stays within the band and the card', (tester) async {
    await pumpGrid(tester, width: 390, textScale: 1, style: 'default');

    final covers = coversOf(tester);
    final band = tester.getRect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('shelfCardGround')),
      ),
    );
    expect(covers.left, greaterThan(band.left));
    expect(covers.top, greaterThan(band.top));
    expect(covers.bottom, lessThan(band.bottom));
  });
}
