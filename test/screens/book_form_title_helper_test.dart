import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
import 'package:bibliogenius/screens/add_book_screen.dart';
import 'package:bibliogenius/screens/edit_book_screen.dart';
import 'package:bibliogenius/services/api_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// A book has no subtitle field: the subtitle is written after the title,
/// behind a colon. Both book forms say so under the title label, so the
/// convention does not have to be guessed.
///
/// No catalogue is loaded here, so the helper shows as its translation key.
class _QuietHubDirectoryProvider extends HubDirectoryProvider {
  @override
  void markCatalogDirty() {}

  @override
  Future<void> syncCatalogIfDirty() async {}
}

void main() {
  final book = Book(id: 'book-uuid', title: 'Martin Eden', owned: true);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad();
  });

  Future<void> pumpForm(WidgetTester tester, Widget form) async {
    final router = GoRouter(
      initialLocation: '/form',
      routes: [GoRoute(path: '/form', builder: (_, _) => form)],
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
          Provider<BookRepository>.value(
            value: MockBookRepository()..mockBook = book,
          ),
          Provider<CollectionRepository>.value(
            value: MockCollectionRepository(),
          ),
          Provider<CopyRepository>.value(value: MockCopyRepository()),
          Provider<ApiService>.value(value: MockApiService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the add form explains how to write a subtitle', (tester) async {
    await pumpForm(tester, const AddBookScreen());

    expect(find.text('title_helper'), findsOneWidget);
  });

  testWidgets('the edit form explains how to write a subtitle', (tester) async {
    await pumpForm(tester, EditBookScreen(book: book));

    expect(find.text('title_helper'), findsOneWidget);
  });
}
