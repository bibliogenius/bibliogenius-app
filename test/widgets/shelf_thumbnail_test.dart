import 'dart:io';
import 'dart:math' as math;

import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:bibliogenius/widgets/shelf_thumbnail.dart';
import 'package:bibliogenius/widgets/shelf_tree_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1 x 1 PNG, to decode a cover for real.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

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

/// The covers of the fan, in paint order: the last one is in front.
List<CachedBookCover> _covers(WidgetTester tester) =>
    tester.widgetList<CachedBookCover>(find.byType(CachedBookCover)).toList();

/// The rotation of [cover], in degrees.
double _degreesOf(WidgetTester tester, CachedBookCover cover) {
  final transform = tester.widget<Transform>(
    find
        .ancestor(of: find.byWidget(cover), matching: find.byType(Transform))
        .first,
  );
  final m = transform.transform;
  return math.atan2(m.entry(1, 0), m.entry(0, 0)) * 180 / math.pi;
}

/// Where [cover] sits in the frame, before its rotation.
Offset _slotOf(WidgetTester tester, CachedBookCover cover) {
  final positioned = tester.widget<Positioned>(
    find
        .ancestor(of: find.byWidget(cover), matching: find.byType(Positioned))
        .first,
  );
  return Offset(positioned.left!, positioned.top!);
}

/// A cover lifted by its shadow.
final _shadow = find.byWidgetPredicate(
  (w) =>
      w is DecoratedBox &&
      w.decoration is BoxDecoration &&
      ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false),
);
const _ghost = Key('shelfThumbnailGhost');

const _three = ['https://c/new.jpg', 'https://c/b.jpg', 'https://c/c.jpg'];

void main() {
  group('the fan', () {
    const sizes = {
      ShelfThumbnailSize.s: (Size(48, 34), Size(18, 25)),
      ShelfThumbnailSize.l: (Size(92, 66), Size(34, 52)),
      ShelfThumbnailSize.xl: (Size(112, 80), Size(40, 60)),
    };
    sizes.forEach((size, dims) {
      testWidgets('$size: the frame and the covers have their dimensions', (
        tester,
      ) async {
        await _pump(
          tester,
          ShelfThumbnail(size: size, hasBooks: true, coverPaths: _three),
        );

        expect(tester.getSize(find.byType(ShelfThumbnail)), dims.$1);
        for (final cover in _covers(tester)) {
          expect(Size(cover.width!, cover.height!), dims.$2);
        }
      });
    });

    testWidgets('three covers: the newest in the centre and in front, the '
        'next at the left, the third at the right', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: _three,
        ),
      );

      final covers = _covers(tester);
      expect(covers.map((c) => c.imageUrl), [
        'https://c/b.jpg',
        'https://c/c.jpg',
        'https://c/new.jpg',
      ]);
      expect(_slotOf(tester, covers[0]), const Offset(12, 9));
      expect(_slotOf(tester, covers[1]), const Offset(46, 9));
      expect(_slotOf(tester, covers[2]), const Offset(29, 6));
      expect(_degreesOf(tester, covers[0]), closeTo(-10, 0.01));
      expect(_degreesOf(tester, covers[1]), closeTo(10, 0.01));
      expect(_degreesOf(tester, covers[2]), closeTo(0, 0.01));
    });

    testWidgets('the small fan leans a little less, as drawn', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.s,
          hasBooks: true,
          coverPaths: _three,
        ),
      );

      final covers = _covers(tester);
      expect(_degreesOf(tester, covers[0]), closeTo(-9, 0.01));
      expect(_degreesOf(tester, covers[1]), closeTo(9, 0.01));
    });

    testWidgets('one cover stands in the centre, two take the centre and '
        'the left', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: ['https://c/a.jpg'],
        ),
      );
      expect(_slotOf(tester, _covers(tester).single), const Offset(29, 6));

      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: ['https://c/a.jpg', 'https://c/b.jpg'],
        ),
      );
      final covers = _covers(tester);
      expect(covers.map((c) => c.imageUrl), [
        'https://c/b.jpg',
        'https://c/a.jpg',
      ]);
      expect(_slotOf(tester, covers.first), const Offset(12, 9));
    });

    testWidgets('never more than three covers', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: [..._three, 'https://c/d.jpg'],
        ),
      );

      expect(_covers(tester), hasLength(3));
    });

    testWidgets('a local cover is decoded at its size in physical pixels', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: ['/nowhere/a.jpg'],
        ),
      );

      final image = tester.widget<Image>(find.byType(Image)).image;
      expect((image as ResizeImage).width, 34 * 3);
    });

    testWidgets('no box behind the fan: nothing fills the frame', (
      tester,
    ) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: _three,
        ),
      );

      expect(
        find.descendant(
          of: find.byType(ShelfThumbnail),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ShelfThumbnail),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });

    testWidgets('a cover that does not load leaves its place empty: no grey '
        'book, no shadow', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: ['/nowhere/gone.jpg'],
        ),
      );
      // Let the file read fail for real.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.book), findsNothing);
      final cover = _covers(tester).single;
      expect(cover.errorWidget, isNotNull);
      expect(_shadow, findsNothing);
    });

    testWidgets('a cover that loads casts its shadow', (tester) async {
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('fan'),
      );
      addTearDown(() => dir!.deleteSync(recursive: true));
      final file = File('${dir!.path}/a.png');
      await tester.runAsync(() => file.writeAsBytes(_png));

      await _pump(
        tester,
        ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: true,
          coverPaths: [file.path],
        ),
      );
      final mounted = tester.element(find.byType(CachedBookCover));
      // Not before the image is there, frames going by or not.
      await tester.pump();
      await tester.pump();
      expect(_shadow, findsNothing);

      for (var i = 0; i < 50 && _shadow.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }

      expect(_shadow, findsOneWidget);
      // Lifting it did not mount the cover anew: it would load again.
      expect(tester.element(find.byType(CachedBookCover)), same(mounted));
    });
  });

  group('nothing to show', () {
    final theme = ThemeData(
      colorScheme: const ColorScheme.light(onSurface: Color(0xFF123456)),
    );

    for (final (label, thumbnail) in [
      (
        'an empty shelf',
        const ShelfThumbnail(size: ShelfThumbnailSize.l, hasBooks: false),
      ),
      (
        'books without a cover',
        const ShelfThumbnail(size: ShelfThumbnailSize.l, hasBooks: true),
      ),
      (
        'a shelf counted empty, whatever it is sent',
        const ShelfThumbnail(
          size: ShelfThumbnailSize.l,
          hasBooks: false,
          coverPaths: ['https://c/a.jpg'],
        ),
      ),
    ]) {
      testWidgets('$label: the ghost fan, and no icon', (tester) async {
        await _pump(tester, thumbnail, theme: theme);

        expect(find.byKey(_ghost), findsOneWidget);
        expect(find.byType(CachedBookCover), findsNothing);
        expect(
          find.descendant(
            of: find.byType(ShelfThumbnail),
            matching: find.byType(Icon),
          ),
          findsNothing,
        );
      });
    }

    testWidgets('the ghost is three visible outlines, 1.5 pt, '
        'with no fill', (tester) async {
      await _pump(
        tester,
        const ShelfThumbnail(size: ShelfThumbnailSize.l, hasBooks: false),
        theme: theme,
      );

      final paint = tester.widget<CustomPaint>(find.byKey(_ghost));
      expect(
        find.byKey(_ghost),
        paints
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: 1.5,
            color: const Color(0xFF123456).withValues(alpha: 0.38),
          )
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: 1.5,
            color: const Color(0xFF123456).withValues(alpha: 0.38),
          )
          ..path(
            style: PaintingStyle.stroke,
            strokeWidth: 1.5,
            color: const Color(0xFF123456).withValues(alpha: 0.38),
          ),
      );
      expect(paint.size, const Size(92, 66));
    });

    testWidgets('the ghost has the same three sizes', (tester) async {
      for (final (size, frame) in const [
        (ShelfThumbnailSize.s, Size(48, 34)),
        (ShelfThumbnailSize.xl, Size(112, 80)),
      ]) {
        await _pump(tester, ShelfThumbnail(size: size, hasBooks: false));
        expect(tester.getSize(find.byType(ShelfThumbnail)), frame);
      }
    });
  });

  testWidgets('a row keeps the height of the arrangement around its small '
      'thumbnail at every level', (tester) async {
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
                thumbnail: const ShelfThumbnail(
                  size: ShelfThumbnailSize.s,
                  hasBooks: true,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byKey(const Key('row'))).height, 52);
    }
  });

  testWidgets('the thumbnail adds no semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    for (final thumbnail in const [
      ShelfThumbnail(
        size: ShelfThumbnailSize.l,
        hasBooks: true,
        coverPaths: ['https://c/a.jpg', 'https://c/b.jpg'],
      ),
      ShelfThumbnail(size: ShelfThumbnailSize.xl, hasBooks: true),
      ShelfThumbnail(size: ShelfThumbnailSize.s, hasBooks: false),
    ]) {
      await _pump(tester, thumbnail);
      // The nearest node is the page's, not one of the thumbnail's own.
      expect(
        tester.getSemantics(find.byType(ShelfThumbnail)).id,
        tester.getSemantics(find.byType(Scaffold)).id,
      );
    }
    handle.dispose();
  });
}
