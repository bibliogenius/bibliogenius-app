import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/bulk_shelving.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_repositories.dart';

// The bulk filing flow: pick shelves and/or collections for a selection of
// books, optionally take the books out of where they were selected, and send
// it all as ONE repository call.
void main() {
  late MockCollectionRepository collections;
  late BookRefreshNotifier refreshNotifier;
  bool? outcome;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    collections = MockCollectionRepository();
    refreshNotifier = BookRefreshNotifier();
    outcome = null;
    TranslationService.setPoTranslationsForTest({
      'en': {
        'bulk_assign_done_plural': '{count} books filed',
        'bulk_assign_nothing_changed': 'Already there',
        'bulk_assign_remove_from': 'Remove from {name}',
        'error_save_failed': 'Save failed',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> openFlow(
    WidgetTester tester, {
    BulkShelvingSource? source,
    List<String> bookIds = const ['a', 'b'],
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CollectionRepository>.value(value: collections),
          Provider<TagRepository>.value(value: MockTagRepository()),
          ChangeNotifierProvider<BookRefreshNotifier>.value(
            value: refreshNotifier,
          ),
          // TranslationService reads the locale from it.
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  outcome = await showBulkShelvingFlow(
                    context,
                    bookIds: bookIds,
                    source: source,
                  );
                },
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

  /// Types a collection name and adds it: the mock has no collection, so
  /// the selector creates one (id '1').
  Future<void> pickNewCollection(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField), 'Polars');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
  }

  final confirm = find.byKey(const Key('bulkAssignConfirmButton'));

  testWidgets('nothing can be confirmed before a destination is picked', (
    tester,
  ) async {
    await openFlow(tester);

    expect(tester.widget<ButtonStyleButton>(confirm).onPressed, isNull);
    expect(collections.lastAssignment, isNull);
  });

  testWidgets('adding is the default: the source is left untouched', (
    tester,
  ) async {
    await openFlow(
      tester,
      source: const BulkShelvingSource.collection(
        label: 'Source',
        collectionId: 'src',
      ),
    );
    await pickNewCollection(tester);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(collections.lastAssignment, {
      'bookIds': ['a', 'b'],
      'addShelves': <String>[],
      'addCollectionIds': ['1'],
      'removeShelves': <String>[],
      'removeCollectionIds': <String>[],
    });
    expect(outcome, isTrue);
    expect(refreshNotifier.refreshCount, 1);
    expect(find.text('2 books filed'), findsOneWidget);
  });

  testWidgets('ticking the option moves the books out of the source', (
    tester,
  ) async {
    await openFlow(
      tester,
      source: const BulkShelvingSource.shelf(
        label: 'Roman',
        shelfPaths: ['Genre > Roman', 'Roman'],
      ),
    );
    await pickNewCollection(tester);
    await tester.tap(find.text('Remove from Roman'));
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(collections.lastAssignment?['removeShelves'], [
      'Genre > Roman',
      'Roman',
    ]);
    expect(collections.lastAssignment?['removeCollectionIds'], isEmpty);
  });

  testWidgets('books that were already there are reported as such', (
    tester,
  ) async {
    collections.mockAssignedCount = 0;
    await openFlow(tester);
    await pickNewCollection(tester);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('Already there'), findsOneWidget);
  });

  testWidgets('a failed call says so and reports nothing filed', (
    tester,
  ) async {
    collections.assignError = Exception('boom');
    await openFlow(tester);
    await pickNewCollection(tester);
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(outcome, isFalse);
    expect(refreshNotifier.refreshCount, 0);
    expect(find.text('Save failed'), findsOneWidget);
  });

  testWidgets('cancelling sends nothing', (tester) async {
    await openFlow(tester);
    await pickNewCollection(tester);
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();

    expect(outcome, isFalse);
    expect(collections.lastAssignment, isNull);
  });
}
