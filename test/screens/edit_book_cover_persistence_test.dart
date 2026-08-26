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

/// `Book.coverUrl` is a *display* getter: when nothing is persisted it invents
/// an OpenLibrary URL from the ISBN, which 404s for any edition OpenLibrary
/// does not carry. The edit form used to seed its cover field from that getter
/// and write it straight back, so merely saving an unrelated change gave a
/// coverless book a dead cover URL. The damage outlives the screen: the cover
/// enrichment queue selects on `cover_url IS NULL`, so such a book is never
/// looked at again, and the cover sheet starts offering "change" instead of
/// "add". The form must persist what the book really has (`rawCoverUrl`).
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    collectionRepo = MockCollectionRepository();
    copyRepo = MockCopyRepository();
    apiService = MockApiService();
  });

  Future<void> pumpAndSave(WidgetTester tester, Book book) async {
    bookRepo = MockBookRepository()..mockBook = book;
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

    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
  }

  testWidgets('saving a coverless book does not invent an OpenLibrary cover', (
    tester,
  ) async {
    await pumpAndSave(
      tester,
      Book(
        id: 'book-uuid',
        title: 'Retour en Afrique',
        isbn: '9782073087768',
        owned: true,
      ),
    );

    expect(bookRepo.lastUpdate, isNotNull);
    expect(bookRepo.lastUpdate!['cover_url'], isNull);
  });

  testWidgets('saving keeps the cover the book really has', (tester) async {
    await pumpAndSave(
      tester,
      Book(
        id: 'book-uuid',
        title: 'Retour en Afrique',
        isbn: '9782073087768',
        coverUrl: 'https://inventaire.io/img/entities/abc',
        owned: true,
      ),
    );

    expect(
      bookRepo.lastUpdate!['cover_url'],
      'https://inventaire.io/img/entities/abc',
    );
  });
}
