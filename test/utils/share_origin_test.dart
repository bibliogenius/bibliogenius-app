import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/utils/share_origin.dart';

void main() {
  const view = Size(393, 852);

  /// Pumps [child] inside a fixed-size view and hands back its context.
  Future<BuildContext> pumpAndFindContext(
    WidgetTester tester,
    Widget child,
    Key key,
  ) async {
    tester.view.physicalSize = view;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
    return tester.element(find.byKey(key));
  }

  testWidgets('a widget fully on screen anchors to its own bounds', (
    tester,
  ) async {
    const key = Key('anchor');
    final context = await pumpAndFindContext(
      tester,
      const Center(child: SizedBox(key: key, width: 100, height: 40)),
      key,
    );

    final rect = shareOrigin(context);

    expect(rect, const Rect.fromLTWH(146.5, 406, 100, 40));
  });

  testWidgets(
    'a scrolled widget overflowing the view is clamped to the view bounds',
    (tester) async {
      // Mirrors the settings screen: a body taller than the screen, scrolled
      // so its top sits above the view. Passing the raw rect to iOS throws
      // "must be non-zero and within coordinate space of source view".
      const key = Key('body');
      final controller = ScrollController(initialScrollOffset: 104);
      addTearDown(controller.dispose);
      final context = await pumpAndFindContext(
        tester,
        SingleChildScrollView(
          controller: controller,
          child: const SizedBox(key: key, width: 393, height: 987),
        ),
        key,
      );

      final rect = shareOrigin(context);

      expect(rect, const Rect.fromLTWH(0, 0, 393, 852));
    },
  );

  testWidgets('a widget scrolled entirely out of view falls back to centre', (
    tester,
  ) async {
    const key = Key('gone');
    final controller = ScrollController(initialScrollOffset: 500);
    addTearDown(controller.dispose);
    final context = await pumpAndFindContext(
      tester,
      SingleChildScrollView(
        controller: controller,
        child: Column(
          children: const [
            SizedBox(key: key, width: 393, height: 100),
            SizedBox(width: 393, height: 2000),
          ],
        ),
      ),
      key,
    );

    final rect = shareOrigin(context);

    expect(rect.width, 1);
    expect(rect.height, 1);
    expect(rect.center, const Offset(196.5, 426));
  });
}
