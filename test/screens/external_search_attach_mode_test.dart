import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/flash_message_provider.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/external_search_screen.dart';
import 'package:bibliogenius/services/api_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// A recent edition is routinely absent from every source that indexes by ISBN
/// while sibling editions of the same work are catalogued with covers. The book
/// sheet therefore sends the reader here, to the search that does find
/// something, and this screen must hand the chosen edition BACK to the book
/// they came from. Creating a second book for a work already in the library is
/// exactly the failure this mode exists to avoid.
class _SearchStub extends MockApiService {
  _SearchStub(this.results);

  final List<Map<String, dynamic>> results;
  final List<Map<String, String?>> queries = [];

  @override
  Future<ExternalSearchResult> searchBooksWithNotices({
    String? query,
    String? title,
    String? author,
    String? publisher,
    String? subject,
    String? lang,
    String? source,
    bool autocomplete = false,
  }) async {
    queries.add({'title': title, 'author': author});
    return ExternalSearchResult(results: results, notices: const []);
  }

  @override
  Future<Response> getUserStatus() async => Response(
    requestOptions: RequestOptions(path: '/api/user/status'),
    statusCode: 200,
    data: const {'config': {}},
  );
}

class _QuietHubDirectoryProvider extends HubDirectoryProvider {
  @override
  void markCatalogDirty() {}

  @override
  Future<void> syncCatalogIfDirty() async {}
}

void main() {
  late _SearchStub api;
  late MockCopyRepository copyRepo;

  final edition = <String, dynamic>{
    'title': 'Retour en Afrique',
    'author': 'Chester Himes',
    'publisher': '10/18',
    'publication_year': 1984,
    'isbn': '9782264005564',
    'cover_url': 'https://inventaire.io/img/entities/deadbeef',
    'source': 'inventaire',
    'work_id': 'wd:Q5175678',
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    copyRepo = MockCopyRepository();
    api = _SearchStub([edition]);
  });

  /// Opens the screen the way the book sheet does and returns the future the
  /// caller awaits.
  Future<Future<Map<String, dynamic>?>> pushAttachMode(
    WidgetTester tester, {
    String location =
        '/search/external?attach=1&title=Retour+en+Afrique&author=Chester+Himes',
  }) async {
    // Tall enough for a whole edition card, action button included.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(
          path: '/search/external',
          builder: (_, _) => const ExternalSearchScreen(),
        ),
      ],
    );

    // ShimmerLoading animates forever while a search runs, so pumpAndSettle
    // would never return: pump fixed frames instead.
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
          ChangeNotifierProvider<FlashMessageProvider>(
            create: (_) => FlashMessageProvider(),
          ),
          // The shared app bar consumes it; it polls nothing until started.
          ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
          ),
          Provider<CopyRepository>.value(value: copyRepo),
          Provider<ApiService>.value(value: api),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();

    final result = router.push<Map<String, dynamic>>(location);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return result;
  }

  testWidgets('attach mode searches the book title and author on its own', (
    tester,
  ) async {
    await pushAttachMode(tester);

    expect(api.queries, isNotEmpty);
    expect(api.queries.first['title'], 'Retour en Afrique');
    expect(api.queries.first['author'], 'Chester Himes');
  });

  testWidgets('the chosen edition goes back to the caller, unadded', (
    tester,
  ) async {
    final result = await pushAttachMode(tester);

    final action = find.byIcon(Icons.download_done_outlined).first;
    await tester.ensureVisible(action);
    await tester.pump();
    await tester.tap(action);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(await result, isNotNull);
    expect((await result)!['cover_url'], edition['cover_url']);
    expect(
      api.createdBooks,
      isEmpty,
      reason: 'completing a book must not create a second one',
    );
  });

  testWidgets('a blank title still completes, it never adds', (tester) async {
    // A book with no title reaches this screen with an empty `title` param.
    // Falling back to the plain search would put an "add to library" button in
    // front of a reader trying to complete a book they already own.
    final result = await pushAttachMode(
      tester,
      location: '/search/external?attach=1&title=',
    );

    expect(
      api.queries,
      isEmpty,
      reason: 'nothing to search for, so no search should fire',
    );

    // The action still hands the edition back rather than creating a book.
    await tester.enterText(find.byType(TextFormField).first, 'Retour');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final action = find.byIcon(Icons.download_done_outlined).first;
    await tester.ensureVisible(action);
    await tester.pump();
    await tester.tap(action);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(await result, isNotNull);
    expect(api.createdBooks, isEmpty);
  });

  testWidgets('leaving without choosing answers nothing, not a flag', (
    tester,
  ) async {
    final result = await pushAttachMode(tester);

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(await result, isNull);
  });
}
