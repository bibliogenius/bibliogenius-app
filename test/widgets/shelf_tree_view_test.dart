import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/shelf_tree_view.dart';

/// The tree on its own, outside the library tab: there the list scrolls by
/// itself, with no NestedScrollView around it to absorb the edge scroll.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, List<Tag> tags) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: ShelfTreeView(
              allTags: tags,
              bookCount: (tag) => tag.count,
              onOpen: (_) {},
              onMoveRequested: (_) {},
              onDrop: (_, _) async => false,
              menuBuilder: (_, _) => const SizedBox(width: 48),
              onRefresh: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('shelfTreeList')),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  testWidgets('the edge scroll stops once the pointer leaves the edge, even '
      'after the row in hand has scrolled away', (tester) async {
    await pump(tester, [
      for (var i = 1; i <= 200; i++)
        Tag(id: 'm$i', name: 'Shelf ${'$i'.padLeft(3, '0')}', count: 1),
    ]);
    // Mounted, on screen or in the list's cache.
    final handle = find.byKey(
      const ValueKey('shelfTreeHandle:Shelf 001'),
      skipOffstage: false,
    );

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await tester.pump();
    final list = tester.getRect(find.byKey(const Key('shelfTreeList')));
    await gesture.moveTo(Offset(list.center.dx, list.center.dy));
    await tester.pump();
    await gesture.moveTo(Offset(list.center.dx, list.bottom - 8));
    for (var i = 0; i < 60 && handle.evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(handle, findsNothing);

    await gesture.moveTo(list.center);
    await tester.pump(const Duration(milliseconds: 50));
    final held = position(tester).pixels;
    await tester.pump(const Duration(seconds: 1));

    expect(position(tester).pixels, held);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a long press follows its own finger, not one that touched '
      'the list while it waited', (tester) async {
    await pump(tester, [
      for (var i = 1; i <= 200; i++)
        Tag(id: 'm$i', name: 'Shelf ${'$i'.padLeft(3, '0')}', count: 1),
    ]);
    Finder row(String name) => find.byKey(ValueKey('shelfTreeRow:$name'));

    final finger = await tester.startGesture(
      tester.getCenter(row('Shelf 001')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    // Another finger lands on another row and slides off, before the long
    // press is through.
    final touch = await tester.startGesture(
      tester.getCenter(row('Shelf 003')),
    );
    await tester.pump();
    await touch.cancel();
    await tester.pump(kLongPressTimeout);
    await tester.pump();

    final list = tester.getRect(find.byKey(const Key('shelfTreeList')));
    await finger.moveTo(list.center);
    await tester.pump();
    await finger.moveTo(Offset(list.center.dx, list.bottom - 8));
    await tester.pump(const Duration(milliseconds: 500));

    // The finger holding the shelf drives the edge scroll.
    expect(position(tester).pixels, greaterThan(0));
    await finger.up();
    await tester.pumpAndSettle();
  });
}
