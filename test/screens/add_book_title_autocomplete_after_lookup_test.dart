import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/add_book_screen.dart';
import 'package:bibliogenius/services/api_service.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// Once an ISBN lookup has filled the form, the book is identified by that
/// ISBN: editing the title is a correction, not a search. The title
/// autocomplete used to keep running there, and picking one of its editions
/// replaced the scanned ISBN, publisher, year and cover with that edition's.
class _SearchingApiService extends MockApiService {
  final List<String> searches = [];

  @override
  Future<List<Map<String, dynamic>>> searchBooks({
    String? query,
    String? title,
    String? author,
    String? publisher,
    String? subject,
    String? lang,
    String? source,
    bool autocomplete = false,
  }) async {
    searches.add(query ?? '');
    return [
      {
        'title': 'Lettres à un jeune poète',
        'author': 'Rainer Maria Rilke',
        'isbn': '9782070000000',
        'publisher': 'Another publisher',
      },
    ];
  }
}

void main() {
  late _SearchingApiService api;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad();
    api = _SearchingApiService();
  });

  Future<void> pumpAddScreen(WidgetTester tester, {String? isbn}) async {
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, _) => AddBookScreen(isbn: isbn)),
      ],
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          Provider<BookRepository>.value(value: MockBookRepository()),
          Provider<CollectionRepository>.value(
            value: MockCollectionRepository(),
          ),
          Provider<CopyRepository>.value(value: MockCopyRepository()),
          Provider<ApiService>.value(value: api),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types a title and waits past the autocomplete debounce.
  Future<void> retypeTitle(WidgetTester tester, String title) async {
    final field = find.byKey(const Key('titleField'));
    await tester.enterText(field, '');
    await tester.pump();
    await tester.enterText(field, title);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  testWidgets('retyping the title after a successful ISBN lookup does not '
      'search for other editions', (tester) async {
    api.lookupResult = {
      'title': 'suivies de Réflexions sur la vie créatrice',
      'authors': ['Rainer Maria Rilke'],
      'publisher': 'Grasset',
    };
    await pumpAddScreen(tester, isbn: '9782246639718');
    expect(api.lookups, contains('lookupBook:9782246639718'));

    await retypeTitle(tester, 'Lettres à un jeune poète');

    expect(api.searches, isEmpty);
    expect(find.text('Another publisher', findRichText: true), findsNothing);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('titleField')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller?.text, 'Lettres à un jeune poète');
  });

  testWidgets('a lookup that names no title leaves the search on', (
    tester,
  ) async {
    api.lookupResult = {'authors': ['Rainer Maria Rilke'], 'publisher': 'Grasset'};
    await pumpAddScreen(tester, isbn: '9782246639718');
    expect(api.lookups, contains('lookupBook:9782246639718'));

    // Another uncached query, for the same reason as below.
    await retypeTitle(tester, 'Les cahiers de Malte Laurids Brigge');

    expect(api.searches, isNotEmpty);
  });

  testWidgets('without a resolved ISBN, typing a title still searches', (
    tester,
  ) async {
    await pumpAddScreen(tester);

    // A query the first test never cached: the search cache outlives a screen.
    await retypeTitle(tester, 'Le livre de l\'intranquillité');

    expect(api.searches, isNotEmpty);
  });
}
