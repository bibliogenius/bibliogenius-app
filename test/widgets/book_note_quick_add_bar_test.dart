import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_note_quick_add_bar.dart';

/// The add-note field takes several lines. On a computer Enter sends and
/// Shift+Enter starts a new line; on a phone the keyboard key starts a new
/// line and the send button sends. A blank note is never sent.

const _newlineHint = 'Shift+Enter for a new line';

void main() {
  late TextEditingController content;
  late TextEditingController page;
  late int submits;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'add_note_placeholder': 'Add a note...',
        'tooltip_add_note': 'Add a note',
        'note_newline_hint': _newlineHint,
      },
    });
    content = TextEditingController();
    page = TextEditingController();
    submits = 0;
  });

  tearDown(() {
    content.dispose();
    page.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: BookNoteQuickAddBar(
              contentController: content,
              pageController: page,
              dictationEnabled: false,
              onSubmit: () => submits++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder contentField() =>
      find.byWidgetPredicate((w) => w is TextField && w.controller == content);

  Future<void> typeInContent(WidgetTester tester, String text) async {
    await tester.tap(contentField());
    await tester.enterText(contentField(), text);
    await tester.pump();
  }

  group('on a computer', () {
    testWidgets('Enter sends the note', (tester) async {
      await pump(tester);
      await typeInContent(tester, 'A short note');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(submits, 1);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets(
      'Shift+Enter starts a new line and does not send',
      (tester) async {
        await pump(tester);
        await typeInContent(tester, 'First line');

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(submits, 0);
        final field = tester.widget<TextField>(contentField());
        expect(field.keyboardType, TextInputType.multiline);
        expect(field.maxLines, greaterThan(1));
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'Enter on a blank note sends nothing',
      (tester) async {
        await pump(tester);
        await typeInContent(tester, '   ');

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(submits, 0);
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets(
      'Enter while an input method is composing does not send',
      (tester) async {
        await pump(tester);
        await typeInContent(tester, 'nihon');
        content.value = const TextEditingValue(
          text: 'nihon',
          selection: TextSelection.collapsed(offset: 5),
          composing: TextRange(start: 0, end: 5),
        );
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(submits, 0);
      },
      variant: TargetPlatformVariant.desktop(),
    );

    testWidgets('shows how to start a new line', (tester) async {
      await pump(tester);
      expect(find.text(_newlineHint), findsOneWidget);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets(
      'a screen reader hears how to start a new line on the field',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester);

        final node = tester.getSemantics(find.byType(EditableText).last);
        expect(node.getSemanticsData().hint, contains(_newlineHint));
        // Announced once, on the field, not again as a stray text.
        expect(find.bySemanticsLabel(_newlineHint), findsNothing);
        semantics.dispose();
      },
      variant: TargetPlatformVariant.desktop(),
    );
  });

  group('on a phone', () {
    testWidgets(
      'the keyboard key starts a new line instead of sending',
      (tester) async {
        await pump(tester);

        final field = tester.widget<TextField>(contentField());
        expect(field.keyboardType, TextInputType.multiline);
        expect(field.textInputAction, TextInputAction.newline);
        expect(field.onSubmitted, isNull);
        expect(find.text(_newlineHint), findsNothing);
      },
      variant: TargetPlatformVariant.mobile(),
    );

    testWidgets(
      'a note typed on three lines is kept as is',
      (tester) async {
        await pump(tester);
        await typeInContent(tester, 'one\ntwo\nthree');

        expect(content.text, 'one\ntwo\nthree');
        expect(submits, 0);
      },
      variant: TargetPlatformVariant.mobile(),
    );
  });

  testWidgets('the send button sends the note', (tester) async {
    await pump(tester);
    await typeInContent(tester, 'one\ntwo');

    await tester.tap(find.byTooltip('Add a note'));
    await tester.pump();

    expect(submits, 1);
  });

  testWidgets('the send button sends nothing for a blank note', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Add a note'));
    await tester.pump();

    expect(submits, 0);
  });
}
