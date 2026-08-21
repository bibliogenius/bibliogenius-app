import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/collection_book.dart';
import 'package:bibliogenius/models/collection_deletion_preview.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/external_suggestion_sheet.dart';

/// ADR-062 section 11: adding a series-lane suggestion to the wishlist also
/// files the new book into the LOCAL series collection it completes, with
/// its ordinal as volume number.
///
/// Unowned wishlist books are already first-class collection members (the
/// frieze renders them with a dedicated "wanted" treatment), so this writes
/// into a state the app already displays. The collection write is
/// best-effort: it must never cost the reader the book itself.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService(), baseUrl: 'http://localhost:0');

  bool createSucceeds = true;
  Map<String, dynamic>? lastCreatePayload;

  @override
  Future<Response> createBook(Map<String, dynamic> bookData) async {
    lastCreatePayload = bookData;
    if (!createSucceeds) {
      return Response(
        requestOptions: RequestOptions(path: '/api/books'),
        statusCode: 409,
        data: const {'error': 'duplicate'},
      );
    }
    return Response(
      requestOptions: RequestOptions(path: '/api/books'),
      statusCode: 201,
      data: const {'id': 'book-new'},
    );
  }

  @override
  Future<Book?> findBookByIsbn(String isbn) async => null;
}

class _FakeCollectionRepository implements CollectionRepository {
  final List<(String, String)> added = [];
  final List<(String, String, int?)> volumes = [];

  /// When true, [addBookToCollection] throws, standing in for a collection
  /// write that fails after the book was already created.
  bool failAdd = false;

  @override
  Future<void> addBookToCollection(String collectionId, String bookId) async {
    if (failAdd) throw StateError('collection write failed');
    added.add((collectionId, bookId));
  }

  @override
  Future<void> setBookVolumeNumber(
    String collectionId,
    String bookId,
    int? volumeNumber,
  ) async {
    volumes.add((collectionId, bookId, volumeNumber));
  }

  @override
  Future<List<Collection>> getCollections() async => const [];
  @override
  Future<List<Collection>> getBookCollections(String bookId) async => const [];
  @override
  Future<void> updateBookCollections(String b, List<String> c) async {}
  @override
  Future<Collection> createCollection(String name, {String? description}) =>
      throw UnimplementedError();
  @override
  Future<void> deleteCollection(String id) async {}
  @override
  Future<List<String>> deleteCollectionWithBooks(String id) async => const [];
  @override
  Future<CollectionDeletionPreview> getDeletionPreview(String id) =>
      throw UnimplementedError();
  @override
  Future<List<CollectionBook>> getCollectionBooks(String id) async => const [];
  @override
  Future<void> removeBookFromCollection(String c, String b) async {}
  @override
  Future<void> markCollectionAsSeries(String c, bool isSeries) async {}
}

class _FakeRecommendationRepository implements RecommendationRepository {
  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];
  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => null;
  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Recommendation _seriesCard({String? collectionId, String ordinal = '2'}) {
  return Recommendation(
    book: Book(title: 'Chamber of Secrets', isbn: '9782070541270'),
    score: 0,
    reasons: [
      RecommendationReason(
        type: 'series_missing_volume',
        value: ordinal,
        params: {'ordinal': ordinal, 'series': 'Harry Potter'},
      ),
    ],
    source: RecommendationSource.external,
    externalKey: 'isbn:9782070541270',
    seriesCollectionId: collectionId,
  );
}

void main() {
  late _FakeApi api;
  late _FakeCollectionRepository collections;

  Widget harness(Recommendation suggestion) {
    // Providers sit ABOVE MaterialApp: the sheet opens on the root
    // navigator, so a MultiProvider nested under `home` would be out of
    // its ancestor chain.
    return MultiProvider(
      providers: [
          Provider<ApiService>.value(value: api),
          Provider<CollectionRepository>.value(value: collections),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          ChangeNotifierProvider<RecommendationProvider>(
            create: (_) => RecommendationProvider(
              _FakeRecommendationRepository(),
              BookRefreshNotifier(),
            ),
          ),
      ],
      // Opened as a real modal sheet: the add path pops its own route
      // before showing the confirmation, so a sheet sitting at the root of
      // the tree would tear down the Scaffold the SnackBar needs.
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ExternalSuggestionSheet.show(context, suggestion),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tapAdd(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Add to wishlist'));
    // The confirmation SnackBar holds a dismissal Timer, which schedules no
    // frame: pumpAndSettle alone would spin until it times out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _FakeApi();
    collections = _FakeCollectionRepository();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'external_suggestion_add_wishlist': 'Add to wishlist',
        'external_suggestion_added': 'Added',
        'external_suggestion_already_in_library': 'Already there',
        'external_suggestion_add_failed': 'Failed',
        'reason_series_missing_volume': 'Volume {ordinal} of {series}',
      },
    });
  });

  testWidgets('a series card files the added book into its collection', (
    tester,
  ) async {
    await tester.pumpWidget(harness(_seriesCard(collectionId: 'col-1')));
    await tapAdd(tester);

    expect(collections.added, [('col-1', 'book-new')]);
    expect(
      collections.volumes,
      [('col-1', 'book-new', 2)],
      reason: 'the ordinal the card announced becomes the volume number',
    );
  });

  testWidgets('a card without a series collection writes nothing', (
    tester,
  ) async {
    await tester.pumpWidget(harness(_seriesCard(collectionId: null)));
    await tapAdd(tester);

    expect(api.lastCreatePayload, isNotNull, reason: 'the book is still added');
    expect(collections.added, isEmpty);
    expect(collections.volumes, isEmpty);
  });

  testWidgets('a failed collection write still leaves the reader the book', (
    tester,
  ) async {
    collections.failAdd = true;

    await tester.pumpWidget(harness(_seriesCard(collectionId: 'col-1')));
    await tapAdd(tester);

    expect(find.text('Added'), findsOneWidget);
    expect(
      collections.volumes,
      isEmpty,
      reason: 'no volume number without a membership',
    );
  });

  testWidgets('the wishlist add itself is unchanged', (tester) async {
    await tester.pumpWidget(harness(_seriesCard(collectionId: 'col-1')));
    await tapAdd(tester);

    expect(api.lastCreatePayload!['reading_status'], 'wanting');
    expect(api.lastCreatePayload!['owned'], false);
  });
}
