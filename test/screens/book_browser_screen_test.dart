import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/book_sequence.dart';
import 'package:bibliogenius/screens/book_browser_screen.dart';

/// Stepping between book pages from a list: keyboard arrows, a horizontal
/// swipe and the page's own buttons, in the list's order, without stealing
/// the arrows of a text field, and without losing the "something changed"
/// signal the list waits for when the page pops.
final _books = [
  Book(id: 'a', title: 'Alpha'),
  Book(id: 'b', title: 'Bravo'),
  Book(id: 'c', title: 'Charlie'),
];

/// Stands in for the real book page: shows the title, exposes the stepper
/// through buttons, and pops with the change flag like the real page does.
Widget _fakePage(BuildContext context, Book book, BookStepper stepper) {
  return _FakePage(book: book, stepper: stepper);
}

class _FakePage extends StatefulWidget {
  final Book book;
  final BookStepper stepper;

  const _FakePage({required this.book, required this.stepper});

  @override
  State<_FakePage> createState() => _FakePageState();
}

/// How many times a page of each book was mounted.
final _mounts = <String, int>{};

class _FakePageState extends State<_FakePage> {
  late bool _changed = widget.stepper.carriedChanges;

  @override
  void initState() {
    super.initState();
    _mounts.update(widget.book.id!, (n) => n + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      // As the real page: a page sliding out leaves the back to the one shown.
      onWillPop: () async {
        if (!BookPageActivity.isActive(context)) return true;
        Navigator.of(context).pop(_changed);
        return false;
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      body: SizedBox.expand(
        child: Column(
          children: [
            Text('page ${widget.book.title}'),
            if (widget.stepper.carriedChanges) const Text('carried'),
            TextButton(
              onPressed: widget.stepper.onPrevious,
              child: const Text('prev'),
            ),
            TextButton(
              onPressed: widget.stepper.onNext,
              child: const Text('next'),
            ),
            TextButton(
              onPressed: () {
                _changed = true;
                widget.stepper.onChanged();
              },
              child: const Text('change'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_changed),
              child: const Text('back'),
            ),
            const SizedBox(width: 200, child: TextField()),
          ],
        ),
      ),
    );
  }
}

Future<void> _pumpBrowser(
  WidgetTester tester, {
  int index = 0,
  void Function(Object? result)? onResult,
  void Function(KeyEvent event)? onUnhandledKey,
}) async {
  _mounts.clear();
  final sequence = BookSequence.around(_books, _books[index])!;
  await tester.pumpWidget(
    MaterialApp(
      // Above the navigator: sees the keys no page handled.
      builder: (context, child) => Focus(
        onKeyEvent: (node, event) {
          onUnhandledKey?.call(event);
          return KeyEventResult.ignored;
        },
        child: child!,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final result = await Navigator.of(context).push(
              MaterialPageRoute<Object?>(
                builder: (_) => BookBrowserScreen(
                  sequence: sequence,
                  pageBuilder: _fakePage,
                ),
              ),
            );
            onResult?.call(result);
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the page buttons step to the neighbours', (tester) async {
    await _pumpBrowser(tester);
    expect(find.text('page Alpha'), findsOneWidget);

    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('page Bravo'), findsOneWidget);
    expect(find.text('page Alpha'), findsNothing);

    await tester.tap(find.text('prev'));
    await tester.pumpAndSettle();
    expect(find.text('page Alpha'), findsOneWidget);
  });

  testWidgets('the ends of the list have no button to step past them', (
    tester,
  ) async {
    await _pumpBrowser(tester);
    final prev = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'prev'),
    );
    expect(prev.onPressed, isNull);

    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    final next = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'next'),
    );
    expect(find.text('page Charlie'), findsOneWidget);
    expect(next.onPressed, isNull);
  });

  testWidgets('the arrow keys step, and keep working after a step', (
    tester,
  ) async {
    await _pumpBrowser(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('page Alpha'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('page Bravo'), findsOneWidget);

    // The first page, and whatever had focus in it, is gone: the keys
    // must still reach the browser.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('page Charlie'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('page Bravo'), findsOneWidget);
  });

  testWidgets('holding an arrow down steps once, not once per repeat', (
    tester,
  ) async {
    // Each step mounts a full book page and its queries: the key repeat
    // must not run through the library at thirty pages a second.
    await _pumpBrowser(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('page Bravo'), findsOneWidget);
  });

  testWidgets('the arrow keys stay with a text field that has focus', (
    tester,
  ) async {
    await _pumpBrowser(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('page Alpha'), findsOneWidget);
  });

  testWidgets('a swipe to the left opens the next book, to the right the '
      'previous one', (tester) async {
    await _pumpBrowser(tester);
    final centre = tester.getCenter(find.byType(Scaffold).last);

    await tester.flingFrom(centre, const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('page Bravo'), findsOneWidget);

    await tester.flingFrom(centre, const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('page Alpha'), findsOneWidget);
  });

  testWidgets('a short or slow horizontal drag does not step', (tester) async {
    await _pumpBrowser(tester);
    final centre = tester.getCenter(find.byType(Scaffold).last);

    await tester.dragFrom(centre, const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect(find.text('page Alpha'), findsOneWidget);
  });

  testWidgets('a change made on an earlier book reaches the list on pop', (
    tester,
  ) async {
    Object? result;
    await _pumpBrowser(tester, onResult: (r) => result = r);

    await tester.tap(find.text('change'));
    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('carried'), findsOneWidget);

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('without any change the page pops false', (tester) async {
    Object? result;
    await _pumpBrowser(tester, onResult: (r) => result = r);

    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('carried'), findsNothing);

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('the page that slides out is kept, not mounted again', (
    tester,
  ) async {
    await _pumpBrowser(tester);

    await tester.tap(find.text('next'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(_mounts, {'a': 1, 'b': 1});
  });

  testWidgets('a back press during the slide is answered by the page shown', (
    tester,
  ) async {
    Object? result;
    await _pumpBrowser(tester, onResult: (r) => result = r);

    await tester.tap(find.text('next'));
    // Far enough into the slide for the incoming page to be on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    // Only the incoming page takes taps: its change, then the system back.
    await tester.tap(find.text('change').last);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('stepping straight back leaves a single live page', (
    tester,
  ) async {
    await _pumpBrowser(tester);

    await tester.tap(find.text('next'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 50));
    final pages = tester.widgetList<BookPageActivity>(
      find.byType(BookPageActivity),
    );
    expect(pages.where((p) => p.active), hasLength(1));
    expect(
      tester
          .widgetList<HeroMode>(find.byType(HeroMode))
          .where((h) => h.enabled),
      hasLength(1),
    );
    await tester.pumpAndSettle();
    expect(find.text('page Alpha'), findsOneWidget);
  });

  testWidgets('an arrow past an end of the list goes on to the app', (
    tester,
  ) async {
    final unhandled = <LogicalKeyboardKey>[];
    await _pumpBrowser(
      tester,
      onUnhandledKey: (e) {
        if (e is KeyDownEvent) unhandled.add(e.logicalKey);
      },
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('page Alpha'), findsOneWidget);
    expect(unhandled, [LogicalKeyboardKey.arrowLeft]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(unhandled, [LogicalKeyboardKey.arrowLeft]);
  });
}
