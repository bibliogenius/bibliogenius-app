import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book_note.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_notes_export_sheet.dart';

/// The export sheet: copies every note in the order given, remembers the
/// format, and offers Share only where the system share sheet takes text.

BookNote _note(int id, String content, {int? page}) => BookNote(
  id: id,
  bookId: 'book-uuid',
  content: content,
  page: page,
  createdAt: '2026-11-13T10:00:00Z',
  updatedAt: '2026-11-13T10:00:00Z',
);

final _notes = [_note(2, 'Newest *note*', page: 9), _note(1, 'Oldest note')];

class _Clipboard {
  String? text;
}

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
    TranslationService.setPoTranslationsForTest({
      'en': {
        'notes_export': 'Export notes',
        'notes_export_plain_text': 'Plain text',
        'notes_export_markdown': 'Markdown',
        'notes_export_copy': 'Copy',
        'notes_export_copied': 'Notes copied',
        'action_share': 'Share',
      },
    });
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => BookNotesExportSheet.show(
                  context,
                  title: 'Le Petit Prince',
                  author: 'Antoine de Saint-Exupéry',
                  notes: _notes,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Copy puts every note on the clipboard, in order, as text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final clipboard = _mockClipboard(tester);
    await open(tester);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(
      clipboard.text,
      'Le Petit Prince\nAntoine de Saint-Exupéry\n\n'
      'Newest *note*\np. 9\n\nOldest note\n',
    );
    expect(find.text('Notes copied'), findsOneWidget);
    expect(find.text('Export notes'), findsNothing);
  });

  testWidgets('a second Copy while the first runs leaves the notes screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    var writes = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        writes++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await open(tester);

    await tester.tap(find.text('Copy'));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.text('Copy'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(writes, 1);
    expect(find.text('open'), findsOneWidget, reason: 'screen behind kept');
  });

  testWidgets('the Markdown choice is used and remembered', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final clipboard = _mockClipboard(tester);
    await open(tester);

    await tester.tap(find.text('Markdown'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kBookNotesExportFormatPrefKey), 'markdown');

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard.text, startsWith('# Le Petit Prince\n'));
    expect(clipboard.text, contains(r'> Newest \*note\*'));
  });

  testWidgets('a remembered Markdown choice is preselected', (tester) async {
    SharedPreferences.setMockInitialValues({
      kBookNotesExportFormatPrefKey: 'markdown',
    });
    final clipboard = _mockClipboard(tester);
    await open(tester);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard.text, startsWith('# Le Petit Prince\n'));
  });

  testWidgets('an unknown saved value falls back to plain text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      kBookNotesExportFormatPrefKey: 'pdf',
    });
    final clipboard = _mockClipboard(tester);
    await open(tester);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard.text, startsWith('Le Petit Prince\n'));
  });

  for (final platform in TargetPlatform.values) {
    final shares = const {
      TargetPlatform.iOS,
      TargetPlatform.android,
      TargetPlatform.macOS,
    }.contains(platform);
    testWidgets('Share is ${shares ? '' : 'not '}offered on ${platform.name}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = platform;
      try {
        await open(tester);
        expect(find.text('Share'), shares ? findsOneWidget : findsNothing);
        expect(find.text('Copy'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
