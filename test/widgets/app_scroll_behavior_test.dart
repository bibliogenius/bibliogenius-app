import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/main.dart';

/// A tall list driven by the app-wide scroll behavior, as every screen is.
Widget _scrollableList(ScrollController controller) {
  return MaterialApp(
    scrollBehavior: AppScrollBehavior(),
    home: Scaffold(
      body: ListView.builder(
        controller: controller,
        itemCount: 100,
        itemExtent: 50,
        itemBuilder: (_, i) => Text('Item $i'),
      ),
    ),
  );
}

void main() {
  // Since Flutter 3.3, a macOS trackpad emits pan/zoom events instead of
  // scroll-wheel events; scrollables only honour them when the trackpad is
  // one of the behavior's drag devices.
  testWidgets('trackpad two-finger swipe scrolls the list', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_scrollableList(controller));

    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(tester.getCenter(find.byType(ListView)));
    await gesture.panZoomUpdate(
      tester.getCenter(find.byType(ListView)),
      pan: const Offset(0, -300),
    );
    await gesture.panZoomEnd();
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('mouse wheel scrolls the list', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_scrollableList(controller));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(ListView))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });
}
