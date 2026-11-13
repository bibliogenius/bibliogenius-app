import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book_note.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_note_tile.dart';

/// A single note can be copied from a long-press menu, and from a screen
/// reader action, without taking away "tap to edit" or "swipe to delete"
/// (selectable text took the swipe away from the text, see the tile docs).

const _content = 'A sentence worth keeping\non two lines';

BookNote _note() => const BookNote(
  id: 1,
  bookId: 'book-uuid',
  content: _content,
  page: 12,
  createdAt: '2026-11-13T10:00:00Z',
  updatedAt: '2026-11-13T10:00:00Z',
);

class _Clipboard {
  String? text;
}

/// Records what the app writes to the system clipboard.
_Clipboard _mockClipboard(WidgetTester tester) {
  final clipboard = _Clipboard();
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      clipboard.text = (call.arguments as Map)['text'] as String?;
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return clipboard;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'delete_note_confirm': 'Delete this note?',
        'note_copy_action': 'Copy note',
        'note_copied': 'Note copied',
      },
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: BookNoteTile(
              note: _note(),
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a long press offers Copy note, which copies the whole note', (
    tester,
  ) async {
    final clipboard = _mockClipboard(tester);
    var edits = 0;
    await pump(tester, onEdit: () => edits++, onDelete: () {});

    await tester.longPress(find.text(_content));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy note'));
    await tester.pumpAndSettle();

    expect(clipboard.text, _content);
    expect(find.text('Note copied'), findsOneWidget);
    expect(edits, 0);
  });

  testWidgets('dismissing the long-press menu copies nothing', (tester) async {
    final clipboard = _mockClipboard(tester);
    await pump(tester, onEdit: () {}, onDelete: () {});

    await tester.longPress(find.text(_content));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Copy note'), findsNothing);
    expect(clipboard.text, isNull);
  });

  testWidgets('screen readers get Copy note as a custom action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final clipboard = _mockClipboard(tester);
    await pump(tester, onEdit: () {}, onDelete: () {});

    // One node carries everything: focusing the tile must offer the tap,
    // the long press with its hint, and the copy action together.
    final node = tester.getSemantics(find.byType(BookNoteTile));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasAction(SemanticsAction.longPress), isTrue);
    expect(node.hintOverrides?.onLongPressHint, 'Copy note');
    expect(
      RegExp(RegExp.escape(_content)).allMatches(data.label),
      hasLength(1),
      reason: 'the note text is read once, not twice',
    );
    final ids = data.customSemanticsActionIds ?? const <int>[];
    final copy = ids
        .map(CustomSemanticsAction.getAction)
        .whereType<CustomSemanticsAction>()
        .where((a) => a.label == 'Copy note');
    expect(copy, hasLength(1));

    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.customAction,
        viewId: tester.view.viewId,
        nodeId: node.id,
        arguments: CustomSemanticsAction.getIdentifier(copy.single),
      ),
    );
    await tester.pumpAndSettle();

    expect(clipboard.text, _content);
    semantics.dispose();
  });

  testWidgets('a tap on the text still opens the editor', (tester) async {
    var edits = 0;
    await pump(tester, onEdit: () => edits++, onDelete: () {});

    await tester.tap(find.text(_content));
    await tester.pumpAndSettle();

    expect(edits, 1);
    expect(find.text('Copy note'), findsNothing);
  });

  testWidgets('swiping the text left, then confirming, deletes the note', (
    tester,
  ) async {
    var deletes = 0;
    await pump(tester, onEdit: () {}, onDelete: () => deletes++);

    await tester.drag(find.text(_content), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Delete this note?'), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(deletes, 1);
  });

  testWidgets('cancelling the swipe confirmation keeps the note', (
    tester,
  ) async {
    var deletes = 0;
    await pump(tester, onEdit: () {}, onDelete: () => deletes++);

    await tester.drag(find.text(_content), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deletes, 0);
    expect(find.text(_content), findsOneWidget);
  });
}
