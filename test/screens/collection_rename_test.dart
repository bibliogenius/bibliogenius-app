import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/collection/collection_detail_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/translation_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// Renaming a collection, and the one collection that must not offer it.
///
/// The favorites collection derives its label from the translations and never
/// from `collections.name` (ADR-064): a rename would be a silent no-op on
/// screen, so the action is not offered at all. The Rust guard covers the
/// callers that do not go through this screen.

class _RecordingCollectionRepository extends MockCollectionRepository {
  final List<(String, String)> renames = [];

  @override
  Future<void> renameCollection(String id, String name) async {
    renames.add((id, name));
  }
}

Collection _collection({required String source, String name = 'Polars'}) =>
    Collection(
      id: 'c1',
      name: name,
      source: source,
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
    );

void main() {
  late _RecordingCollectionRepository collectionRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    collectionRepo = _RecordingCollectionRepository();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'rename': 'Rename',
        'rename_collection': 'Rename collection',
        'name': 'Name',
        'cancel': 'Cancel',
        'import_books': 'Import books',
        'action_share': 'Share',
        'delete_collection_title': 'Delete collection',
        'favorites_collection_name': 'Favorites',
        'quick_actions_title': 'Actions',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pumpDetail(WidgetTester tester, Collection collection) async {
    // A phone-sized surface: the quick-actions sheet is not scrollable, so
    // its height is asserted implicitly by the absence of an overflow.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => CollectionDetailScreen(collection: collection),
        ),
      ],
    );

    await tester.pumpWidget(
      // Providers ABOVE MaterialApp: the quick-actions sheet is a modal route
      // pushed on the root navigator and would not see an inner scope.
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
          ),
          Provider<CollectionRepository>.value(value: collectionRepo),
          Provider<CopyRepository>.value(value: MockCopyRepository()),
          Provider<ApiService>.value(value: MockApiService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openQuickActions(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.bolt).first);
    await tester.pumpAndSettle();
  }

  testWidgets('a manual collection offers the rename action', (tester) async {
    await pumpDetail(tester, _collection(source: 'manual'));
    await openQuickActions(tester);

    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('the favorites collection does not offer it', (tester) async {
    await pumpDetail(tester, _collection(source: 'favorites'));
    await openQuickActions(tester);

    // The other actions are still there: only the rename card is withheld.
    expect(find.text('Delete collection'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('renaming writes the new name and updates the title', (
    tester,
  ) async {
    await pumpDetail(tester, _collection(source: 'manual'));
    await openQuickActions(tester);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  Romans noirs  ');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(collectionRepo.renames, [('c1', 'Romans noirs')]);
    expect(find.text('Romans noirs'), findsWidgets);
  });

  testWidgets('an unchanged name writes nothing', (tester) async {
    await pumpDetail(tester, _collection(source: 'manual'));
    await openQuickActions(tester);

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(collectionRepo.renames, isEmpty);
  });
}
