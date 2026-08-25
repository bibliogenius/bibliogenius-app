import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/edit_book_screen.dart';
import 'package:bibliogenius/services/api_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// Neither reading date is mandatory. Once one is set, the picker alone can
/// never take it back off (cancelling keeps the old value, and its keyboard
/// mode refuses an empty field), so the form owns a clear button and must send
/// an explicit null when it is used.
class _RecordingBookRepository extends MockBookRepository {
  Map<String, dynamic>? lastUpdate;

  @override
  Future<Book> updateBook(String uuid, Map<String, dynamic> bookData) async {
    lastUpdate = Map<String, dynamic>.from(bookData);
    return mockBook ?? Book(id: uuid, title: bookData['title'] ?? 'Updated');
  }
}

/// The real provider debounces a catalog push on a 5s timer and would reach
/// for the FFI; the save path only needs it to accept the call.
class _QuietHubDirectoryProvider extends HubDirectoryProvider {
  @override
  void markCatalogDirty() {}

  @override
  Future<void> syncCatalogIfDirty() async {}
}

void main() {
  late _RecordingBookRepository bookRepo;
  late MockCollectionRepository collectionRepo;
  late MockCopyRepository copyRepo;
  late MockApiService apiService;

  final book = Book(
    id: 'book-uuid',
    title: 'Martin Eden',
    readingStatus: 'read',
    owned: false,
    startedReadingAt: DateTime(2026, 6, 1),
    finishedReadingAt: DateTime(2026, 7, 1),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bookRepo = _RecordingBookRepository()..mockBook = book;
    collectionRepo = MockCollectionRepository();
    copyRepo = MockCopyRepository();
    apiService = MockApiService();
  });

  Future<GoRouter> pumpEditScreen(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(path: '/edit', builder: (_, _) => EditBookScreen(book: book)),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<HubDirectoryProvider>(
            create: (_) => _QuietHubDirectoryProvider(),
          ),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          Provider<BookRepository>.value(value: bookRepo),
          Provider<CollectionRepository>.value(value: collectionRepo),
          Provider<CopyRepository>.value(value: copyRepo),
          Provider<ApiService>.value(value: apiService),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/edit');
    await tester.pumpAndSettle();
    return router;
  }

  /// The form is a lazily-built `ListView`: the reading dates sit past the
  /// first viewport and are not laid out until scrolled to.
  Future<void> scrollToFinishedDate(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('finished_reading_date_field')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(Form),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a set finishing date offers a way to remove it', (tester) async {
    await pumpEditScreen(tester);
    await scrollToFinishedDate(tester);

    expect(find.text('01/07/2026'), findsOneWidget);
    expect(find.byKey(const Key('finished_reading_date_clear')), findsOneWidget);
  });

  testWidgets('clearing the finishing date empties the field', (tester) async {
    await pumpEditScreen(tester);
    await scrollToFinishedDate(tester);

    await tester.tap(find.byKey(const Key('finished_reading_date_clear')));
    await tester.pumpAndSettle();

    expect(find.text('01/07/2026'), findsNothing);
    // With no date left there is nothing to clear, so the button steps aside.
    expect(find.byKey(const Key('finished_reading_date_clear')), findsNothing);
  });

  testWidgets('saving a cleared finishing date sends an explicit null', (
    tester,
  ) async {
    await pumpEditScreen(tester);
    await scrollToFinishedDate(tester);

    await tester.tap(find.byKey(const Key('finished_reading_date_clear')));
    await tester.pumpAndSettle();

    // The save button is `ElevatedButton.icon`, whose private subclass
    // `find.byType` cannot match; its check icon is unique on the screen.
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    expect(bookRepo.lastUpdate, isNotNull);
    expect(bookRepo.lastUpdate!.containsKey('finished_reading_at'), isTrue);
    expect(bookRepo.lastUpdate!['finished_reading_at'], isNull);
    // The status is untouched: "read" without a date is a valid state.
    expect(bookRepo.lastUpdate!['reading_status'], 'read');
    // The date the reader did not touch must survive the save.
    expect(
      bookRepo.lastUpdate!['started_reading_at'],
      DateTime(2026, 6, 1).toIso8601String(),
    );
  });
}
