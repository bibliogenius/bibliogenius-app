import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' show FrbWishlistProvider;
import 'package:bibliogenius/widgets/external_suggestion_sheet.dart';

/// Borrow CTA on the external suggestion preview sheet: the availability
/// row is no longer informative only. When a provider holds the ISBN, the
/// sheet renders the shared borrow rows: a paired peer goes through the
/// existing P2P request (requestBookByUrl), a followed-but-unpaired
/// library through the hub borrow request (ADR-018). The guaranteed
/// minimal action stays add-to-wishlist; a profile without the borrowing
/// capability keeps the info row only.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService(), baseUrl: 'http://localhost:0');

  (String, String, String)? lastBorrowRequest;
  int borrowStatusCode = 200;

  @override
  Future<Response> requestBookByUrl(
    String peerUrl,
    String isbn,
    String title,
  ) async {
    lastBorrowRequest = (peerUrl, isbn, title);
    return Response(
      requestOptions: RequestOptions(path: '/api/peers/request_by_url'),
      statusCode: borrowStatusCode,
      data: const {'status': 'pending'},
    );
  }

  @override
  Future<Response> getOutgoingRequests() async => Response(
    requestOptions: RequestOptions(path: '/api/peers/requests/outgoing'),
    statusCode: 200,
    data: const [],
  );

  @override
  Future<Response> getIncomingRequests() async => Response(
    requestOptions: RequestOptions(path: '/api/peers/requests'),
    statusCode: 200,
    data: const [],
  );
}

class _FakeHubDirectoryProvider extends HubDirectoryProvider {
  (String, String, String)? lastHubRequest;
  bool shouldThrow = false;

  @override
  Future<bool> createBorrowRequest(
    String lenderNodeId,
    String isbn,
    String bookTitle,
  ) async {
    lastHubRequest = (lenderNodeId, isbn, bookTitle);
    if (shouldThrow) throw StateError('hub unreachable');
    return true;
  }
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

const _isbn = '9782070541270';

Recommendation _card() => Recommendation(
  book: Book(title: 'Chamber of Secrets', isbn: _isbn),
  score: 0,
  reasons: [
    RecommendationReason(
      type: 'author_completion',
      value: 'J. K. Rowling',
      params: const {'author': 'J. K. Rowling'},
    ),
  ],
  source: RecommendationSource.external,
  externalKey: 'isbn:$_isbn',
);

FrbWishlistProvider _pairedProvider({int? availableCopies = 1}) =>
    FrbWishlistProvider(
      isbn: _isbn,
      peerId: 33,
      sourceName: 'Bibliotheque de Marie',
      peerUrl: 'http://peer.local:1234',
      availableCopies: availableCopies,
    );

FrbWishlistProvider _directoryProvider() => const FrbWishlistProvider(
  isbn: _isbn,
  peerId: 0,
  nodeId: 'node-1',
  sourceName: 'Mediatheque suivie',
);

void main() {
  late _FakeApi api;
  late _FakeHubDirectoryProvider hub;

  Widget harness(
    Recommendation suggestion,
    List<FrbWishlistProvider> providers,
  ) {
    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
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
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => ExternalSuggestionSheet.show(
                context,
                suggestion,
                availabilityLoader: (_) async => providers,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _FakeApi();
    hub = _FakeHubDirectoryProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'external_suggestion_add_wishlist': 'Add to wishlist',
        'external_suggestion_available_network': 'Available in your network',
        'borrow': 'Borrow',
        'borrow_pending': 'Requested',
        'borrow_unavailable': 'Unavailable',
        'borrow_on_loan': 'On loan',
        'borrow_request_sent': 'Request sent',
        'borrow_request_rejected_no_copy': 'No copy',
        'reason_author_completion': 'Author you like: {author}',
      },
    });
  });

  testWidgets('a paired provider offers a borrow button wired to the P2P '
      'request', (tester) async {
    await tester.pumpWidget(harness(_card(), [_pairedProvider()]));
    await openSheet(tester);

    expect(find.text('Available in your network'), findsOneWidget);
    expect(find.text('Bibliotheque de Marie'), findsOneWidget);
    await tester.tap(find.text('Borrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      api.lastBorrowRequest,
      ('http://peer.local:1234', _isbn, 'Chamber of Secrets'),
    );
    expect(find.text('Request sent'), findsOneWidget);
    expect(
      find.text('Requested'),
      findsOneWidget,
      reason: 'the tapped row flips to its pending state',
    );
  });

  testWidgets('a directory-only provider goes through the hub borrow '
      'request', (tester) async {
    await tester.pumpWidget(harness(_card(), [_directoryProvider()]));
    await openSheet(tester);

    await tester.tap(find.text('Borrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(hub.lastHubRequest, ('node-1', _isbn, 'Chamber of Secrets'));
    expect(api.lastBorrowRequest, isNull);
  });

  testWidgets('no provider means no availability block at all', (tester) async {
    await tester.pumpWidget(harness(_card(), const []));
    await openSheet(tester);

    expect(find.text('Available in your network'), findsNothing);
    expect(find.text('Borrow'), findsNothing);
    expect(
      find.text('Add to wishlist'),
      findsOneWidget,
      reason: 'the guaranteed minimal action is untouched',
    );
  });

  testWidgets('a profile without the borrowing capability keeps the info '
      'row only', (tester) async {
    SharedPreferences.setMockInitialValues({'canBorrowBooks': false});
    await tester.pumpWidget(harness(_card(), [_pairedProvider()]));
    final themeContext = tester.element(find.text('open'));
    await themeContext.read<ThemeProvider>().setCanBorrowBooks(false);
    await openSheet(tester);

    expect(find.text('Available in your network'), findsOneWidget);
    expect(find.text('Borrow'), findsNothing);
  });

  testWidgets('a provider with no available copy shows the unavailable '
      'state instead of a button', (tester) async {
    await tester.pumpWidget(
      harness(_card(), [_pairedProvider(availableCopies: 0)]),
    );
    await openSheet(tester);

    expect(find.text('Borrow'), findsNothing);
    expect(find.text('Unavailable'), findsOneWidget);
  });

  testWidgets('a hub failure shows the error and re-enables the row', (
    tester,
  ) async {
    hub.shouldThrow = true;
    await tester.pumpWidget(harness(_card(), [_directoryProvider()]));
    await openSheet(tester);

    await tester.tap(find.text('Borrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No copy'), findsOneWidget);
    expect(
      find.text('Borrow'),
      findsOneWidget,
      reason: 'a failed hub request must not leave the row stuck on pending',
    );
  });

  testWidgets('a 409 reads as on loan and re-enables the row', (tester) async {
    api.borrowStatusCode = 409;
    await tester.pumpWidget(harness(_card(), [_pairedProvider()]));
    await openSheet(tester);

    await tester.tap(find.text('Borrow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('On loan'), findsOneWidget);
    expect(
      find.text('Borrow'),
      findsOneWidget,
      reason: 'a failed request must not leave the row stuck on pending',
    );
  });
}
