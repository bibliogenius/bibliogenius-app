import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/collection_share_sheet.dart';

/// The panel a reader sees before sending a list to someone.
///
/// It exists because the two halves of sharing did not name each other: the
/// export dropped a .yml into the system share sheet with nothing said, while
/// the import accepted a file OR a paste. So this states what the recipient
/// gets, promises them their library is not touched without confirmation, and
/// offers BOTH transports the import understands.
const _yaml = '''
id: mangas-essentiels
title: "Mangas essentiels"
books:
  - isbn: "9782723488525"
    note: "One Piece - Eiichiro Oda"
''';

Future<void> _noop(Rect origin) async {}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'collection_share_title': 'Share this list',
        'collection_share_explainer':
            'They receive a BiblioGenius list file. Nothing enters their '
                'library until they confirm.',
        'collection_share_count': '{count} books',
        'collection_share_languages': 'Declared languages: {languages}',
        'collection_share_copy': 'Copy',
        'collection_share_send': 'Send the file',
        'collection_share_copied': 'List copied',
      },
    });
  });

  Future<void> pump(
    WidgetTester tester, {
    required ShareCollectionCallback onShare,
    List<String> languages = const ['fr'],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: Scaffold(
            body: CollectionShareSheet(
              collectionName: 'Mangas essentiels',
              bookCount: 8,
              yaml: _yaml,
              languages: languages,
              onShare: onShare,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('it names the list, counts it, and says what is sent', (
    tester,
  ) async {
    await pump(tester, onShare: _noop);

    expect(find.text('Mangas essentiels'), findsOneWidget);
    expect(find.text('8 books'), findsOneWidget);
    expect(
      find.textContaining('Nothing enters their library'),
      findsOneWidget,
      reason: 'The promise is the whole point of the panel.',
    );
  });

  testWidgets('Copy puts the exact YAML on the clipboard', (tester) async {
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pump(tester, onShare: _noop);
    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(clipboard, [_yaml], reason: 'The import reads a paste verbatim.');
    expect(find.text('List copied'), findsOneWidget);
  });

  testWidgets('Send hands over to the caller, which owns the file', (
    tester,
  ) async {
    var shared = 0;
    await pump(
      tester,
      onShare: (origin) async {
        shared++;
      },
    );

    await tester.tap(find.text('Send the file'));
    await tester.pump();

    expect(shared, 1);
  });

  testWidgets('Send hands over a non-zero anchor for the iOS popover', (
    tester,
  ) async {
    // The bug this covers: with no origin, share_plus throws on iPhone and
    // iPad and the throw was swallowed, so the button did nothing while
    // macOS worked. An empty rect would reproduce it exactly.
    Rect? origin;
    await pump(
      tester,
      onShare: (anchor) async {
        origin = anchor;
      },
    );

    await tester.tap(find.text('Send the file'));
    await tester.pump();

    expect(origin, isNotNull);
    expect(origin!.isEmpty, isFalse, reason: 'iOS refuses a zero origin.');
    expect(
      origin!.contains(tester.getCenter(find.text('Send the file'))),
      isTrue,
      reason: 'The popover must point at the button that was pressed.',
    );
  });

  testWidgets('the declared languages are shown, and skipped when none', (
    tester,
  ) async {
    await pump(tester, onShare: _noop);
    expect(find.textContaining('Declared languages: fr'), findsOneWidget);

    await pump(tester, onShare: _noop, languages: const []);
    expect(
      find.textContaining('Declared languages'),
      findsNothing,
      reason: 'An absent declaration is honest; an empty one reads as a bug.',
    );
  });

  testWidgets('it grows and scrolls at 200% text instead of clipping', (
    tester,
  ) async {
    // Measured before the fix: 396 pixels over on a 400x700 viewport. The
    // promise about the recipient's library is the line that got cut, which
    // is the one line that must never be (RGAA 4.1 / WCAG 1.4.4).
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: CollectionShareSheet(
                collectionName: 'Une très longue liste de mangas essentiels',
                bookCount: 8,
                yaml: 'x',
                languages: ['fr', 'en', 'es'],
                onShare: _noop,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('the panel announces itself as a header', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, onShare: _noop);

    expect(
      tester.getSemantics(find.text('Share this list')),
      matchesSemantics(label: 'Share this list', isHeader: true),
    );
    handle.dispose();
  });
}
