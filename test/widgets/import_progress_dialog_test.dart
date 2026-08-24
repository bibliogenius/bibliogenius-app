import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/import_progress_dialog.dart';

/// Importing a curated list is one network call per book, in sequence. The
/// reader used to get a closed dialog and a silent screen for as long as
/// that took, with no way to tell a slow import from a dead one and no way
/// to stop it.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'importing_collection': 'Importing collection...',
        'cancel': 'Cancel',
      },
    });
  });

  Future<int?> pumpAndRun(
    WidgetTester tester,
    Future<int> Function(void Function(int, int), bool Function()) run, {
    int total = 5,
  }) async {
    int? outcome;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  outcome = await ImportProgressDialog.run<int>(
                    context,
                    total: total,
                    task: run,
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    return outcome;
  }

  testWidgets('the reader sees the dialog before the first book', (
    tester,
  ) async {
    await pumpAndRun(tester, (onProgress, isCancelled) async {
      onProgress(0, 5);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return 5;
    });

    expect(find.text('Importing collection...'), findsOneWidget);
    expect(find.text('0 / 5'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  });

  testWidgets('the counter follows the import', (tester) async {
    late void Function(int, int) report;
    await pumpAndRun(tester, (onProgress, isCancelled) async {
      report = onProgress;
      onProgress(0, 5);
      await Future<void>.delayed(const Duration(seconds: 1));
      return 5;
    });

    report(3, 5);
    await tester.pump();
    expect(find.text('3 / 5'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('Cancel reaches the task, which decides what to return', (
    tester,
  ) async {
    var polled = false;
    late bool Function() cancelled;

    await pumpAndRun(tester, (onProgress, isCancelled) async {
      cancelled = isCancelled;
      onProgress(0, 5);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      polled = isCancelled();
      return 2;
    });

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(cancelled(), isTrue);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(polled, isTrue);
  });

  testWidgets('the dialog closes on its own when the task finishes', (
    tester,
  ) async {
    await pumpAndRun(tester, (onProgress, isCancelled) async {
      onProgress(0, 3);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return 3;
    });

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('the dialog announces itself as one thing, not four', (
    tester,
  ) async {
    await pumpAndRun(tester, (onProgress, isCancelled) async {
      onProgress(2, 5);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return 5;
    });
    // Let the post-frame start fire, so the task has reported its position.
    await tester.pump();

    // Asserted on the Semantics widget rather than on a rendered node: this
    // harness does not materialise a semantics tree (even the Cancel button
    // has no node in it), so a tree assertion here would pass on nothing.
    // What must not regress is the composition rule: ONE label carrying the
    // whole sentence, with the two fragments excluded (ADR-061 A2).
    final status = tester.widget<Semantics>(
      find.byKey(const Key('import-progress-status')),
    );
    expect(status.properties.label, 'Importing collection..., 2 / 5');
    expect(status.excludeSemantics, isTrue);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
  });
}
