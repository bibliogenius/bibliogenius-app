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

/// A search suggestion now carries the edition's year and page count (from
/// the source's own record, no extra request). Picking it must fill both
/// fields: the page count used to be ignored by the form, so the reader got
/// an edition with no page count although the source had it.
class _SuggestingApiService extends MockApiService {
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
    return [
      {
        'title': 'Martin Eden',
        'author': 'Jack London',
        'isbn': '978-2-7529-0553-6',
        'publisher': 'Phébus',
        'publication_year': 2010,
        'page_count': 462,
      },
    ];
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad();
  });

  Future<void> pumpAddScreen(WidgetTester tester, ApiService api) async {
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, _) => const AddBookScreen()),
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

  String fieldText(WidgetTester tester, String key) {
    return tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(Key(key)),
                matching: find.byType(TextField),
              ),
            )
            .controller
            ?.text ??
        '';
  }

  testWidgets('picking a suggestion fills the page count and the year', (
    tester,
  ) async {
    // The form is a ListView: fields below the fold are not built at the
    // default test size, so the assertions could not find them.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpAddScreen(tester, _SuggestingApiService());

    // A query no other test caches: the search cache outlives a screen.
    await tester.enterText(
      find.byKey(const Key('titleField')),
      'Martin Eden Phébus',
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    // The option tile titles the suggestion with the bare title; the field
    // itself holds the longer query, so this matches the tile only.
    expect(find.text('Martin Eden'), findsOneWidget);
    await tester.tap(find.text('Martin Eden'));
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'yearField'), '2010');
    expect(fieldText(tester, 'pageCountField'), '462');
  });
}
