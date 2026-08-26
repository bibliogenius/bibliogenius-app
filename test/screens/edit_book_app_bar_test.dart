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

/// The edit form is pushed on top of the shell, so its app bar owns the way
/// back and nothing else. A hamburger here used to replace that back arrow on
/// a narrow screen, and it opened nothing: the shell only builds a drawer when
/// the bottom navigation bar is off, so `openDrawer()` was a silent no-op in
/// the default configuration and the form became a dead end.
class _QuietHubDirectoryProvider extends HubDirectoryProvider {
  @override
  void markCatalogDirty() {}

  @override
  Future<void> syncCatalogIfDirty() async {}
}

void main() {
  late MockBookRepository bookRepo;
  late MockCollectionRepository collectionRepo;
  late MockCopyRepository copyRepo;
  late MockApiService apiService;

  final book = Book(id: 'book-uuid', title: 'Martin Eden', owned: true);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bookRepo = MockBookRepository()..mockBook = book;
    collectionRepo = MockCollectionRepository();
    copyRepo = MockCopyRepository();
    apiService = MockApiService();
  });

  /// Below the 600px shell breakpoint, where the hamburger used to appear.
  void useNarrowScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(599, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<GoRouter> pumpEditScreen(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(
          path: '/edit',
          builder: (_, _) => EditBookScreen(book: book),
        ),
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

  testWidgets('a narrow screen keeps the back arrow, not a hamburger', (
    tester,
  ) async {
    useNarrowScreen(tester);
    await pumpEditScreen(tester);

    expect(find.byIcon(Icons.menu), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('the back arrow leaves the form on a narrow screen', (
    tester,
  ) async {
    useNarrowScreen(tester);
    final router = await pumpEditScreen(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(router.routerDelegate.currentConfiguration.uri.path, '/');
  });
}
