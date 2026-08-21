import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/author_screen.dart';
import 'package:bibliogenius/services/discovery_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/suggestion_tile.dart';

import '../helpers/mock_repositories.dart';

/// ADR-061 surface 2: the author page.
///
/// What is pinned here: the local half selects the right books through
/// [AuthorIdentity] (no author filter crosses the FFI, and a co-signed book
/// must be found by either author), the discovery half resolves ON OPEN but
/// only once per 24h, an author with no anchor ISBN costs no request, and
/// the page shows nothing rather than an error when the resolver hesitates.
class _FakeRecommendationRepository implements RecommendationRepository {
  _FakeRecommendationRepository(this.inputs);

  final DiscoveryLookupInputs? inputs;

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
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => inputs;
}

Book _book(String id, String title, String author, {String? isbn}) {
  return Book(id: id, title: title, author: author, isbn: isbn);
}

/// The library the tests describe: Le Guin catalogued the inverted way, a
/// co-signed book, and one book by someone else.
const _libraryKeys = {
  'a wizard of earthsea|ursula k le guin',
  'the dispossessed|ursula k le guin',
  'the dispossessed|alia sun',
  'letranger|albert camus',
};

Map<String, dynamic> _resolvedAuthor(List<String> works) => {
  'status': 'resolved',
  'author': {
    'source': 'wikidata',
    'source_id': 'Q181659',
    'label': 'Ursula K. Le Guin',
    'works': [
      for (final (index, title) in works.indexed)
        {
          'title': title,
          'titles': [title],
          'authors': const ['Ursula K. Le Guin'],
          'year': 1974,
          'editions_count': 40 - index,
          'editions': const [],
          'other_langs_exist': false,
        },
    ],
  },
};

void main() {
  late ThemeProvider theme;
  late MockBookRepository books;
  late List<String> hubBodies;

  Widget harness(
    String authorName, {
    required http.Response Function() answer,
    Set<String> libraryKeys = _libraryKeys,
  }) {
    final provider = RecommendationProvider(
      _FakeRecommendationRepository(
        DiscoveryLookupInputs(
          series: const [],
          // The visited author is deliberately NOT a favorite: the page
          // must build its own lookup.
          authors: const [],
          libraryIsbns: const {},
          libraryTitleAuthorKeys: libraryKeys,
        ),
      ),
      BookRefreshNotifier(),
      discoveryService: DiscoveryService(
        baseUrl: 'https://hub.test',
        client: MockClient((request) async {
          hubBodies.add(request.body);
          return answer();
        }),
      ),
    );

    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<RecommendationProvider>.value(value: provider),
          Provider<BookRepository>.value(value: books),
        ],
        child: AuthorScreen(authorName: authorName),
      ),
    );
  }

  setUp(() {
    hubBodies = [];
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    books = MockBookRepository()
      ..mockBooks = [
        _book('b1', 'A Wizard of Earthsea', 'Le Guin, Ursula K.',
            isbn: '9780553383041'),
        _book('b2', 'The Dispossessed', 'Ursula K. Le Guin, Alia Sun',
            isbn: '9780061054884'),
        _book('b3', "L'Etranger", 'Albert Camus', isbn: '9782070360024'),
      ];
    TranslationService.setPoTranslationsForTest({
      'en': {
        'author_page_in_library': 'In your library ({count})',
        'author_page_no_local_books': 'No book by this author in your library.',
        'author_page_to_discover': 'To discover',
        'author_page_open_semantic': 'Books by {author}',
        'suggestion_badge_external': 'To discover',
        'reason_author_completion': 'Author you like: {author}',
        'recommendation_not_interested': 'Not interested',
        'untitled_book': 'Untitled',
      },
    });
  });

  testWidgets('lists the author own books, inverted catalogue included', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(jsonEncode({'status': 'unknown'}), 200),
      ),
    );
    await tester.pumpAndSettle();

    // "Le Guin, Ursula K." is the same person (word multiset), and the
    // co-signed "Ursula K. Le Guin, Alia Sun" counts too. Camus does not.
    expect(find.text('In your library (2)'), findsOneWidget);
    expect(find.text('A Wizard of Earthsea'), findsOneWidget);
    expect(find.text('The Dispossessed'), findsOneWidget);
    expect(find.text("L'Etranger"), findsNothing);
  });

  testWidgets('the co-author of a shared book has their own page', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        'Alia Sun',
        answer: () => http.Response(jsonEncode({'status': 'unknown'}), 200),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('In your library (1)'), findsOneWidget);
    expect(find.text('The Dispossessed'), findsOneWidget);
  });

  testWidgets('resolves on open and lists the unowned works', (tester) async {
    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(
          jsonEncode(_resolvedAuthor(['The Lathe of Heaven', 'The Word for World'])),
          200,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(hubBodies, hasLength(1), reason: 'one lookup per page open');
    final body = jsonDecode(hubBodies.single) as Map<String, dynamic>;
    expect(body['name'], 'Ursula K. Le Guin');
    expect(
      body['anchor_isbns'],
      ['9780553383041', '9780061054884'],
      reason: 'anchors are built client-side from the local books',
    );

    expect(find.text('To discover'), findsWidgets);
    expect(find.text('The Lathe of Heaven'), findsOneWidget);
    expect(find.text('The Word for World'), findsOneWidget);
    expect(find.byType(SuggestionTile), findsNWidgets(2));
  });

  testWidgets('a second open inside 24h does not resolve again', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.authorCacheKey: jsonEncode({
        'Ursula K. Le Guin': {
          'at': DateTime.now().millisecondsSinceEpoch,
          'status': 'resolved',
          'author': _resolvedAuthor(['The Lathe of Heaven'])['author'],
        },
      }),
    });

    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(jsonEncode({'status': 'unknown'}), 200),
      ),
    );
    await tester.pumpAndSettle();

    expect(hubBodies, isEmpty);
    expect(find.text('The Lathe of Heaven'), findsOneWidget);
  });

  testWidgets('a checksum-invalid ISBN never becomes an anchor', (
    tester,
  ) async {
    // Real catalogues carry ISBNs that pass the eye and fail the checksum.
    // The hub validates format AND checksum and 400s the WHOLE request on
    // the first bad one, and the client counts any non-200 as an attempt:
    // letting one through would veto the valid anchor beside it and silence
    // this author for the full 24h throttle.
    books.mockBooks = [
      _book('b1', 'Bad ISBN', 'Ursula K. Le Guin', isbn: '9780553383042'),
      _book('b2', 'Good ISBN', 'Ursula K. Le Guin', isbn: '9780553383041'),
    ];

    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(
          jsonEncode(_resolvedAuthor(['The Lathe of Heaven'])),
          200,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final body = jsonDecode(hubBodies.single) as Map<String, dynamic>;
    expect(
      body['anchor_isbns'],
      ['9780553383041'],
      reason: 'the malformed ISBN is dropped, the valid one still anchors',
    );
    expect(find.text('The Lathe of Heaven'), findsOneWidget);
  });

  testWidgets('an ISBN-10 anchors in its canonical ISBN-13 form', (
    tester,
  ) async {
    // The Rust lane sends canonical ISBN-13; the page must not diverge.
    books.mockBooks = [
      _book('b1', 'Ten Digits', 'Ursula K. Le Guin', isbn: '0-553-38304-3'),
    ];

    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(jsonEncode({'status': 'unknown'}), 200),
      ),
    );
    await tester.pumpAndSettle();

    final body = jsonDecode(hubBodies.single) as Map<String, dynamic>;
    expect(body['anchor_isbns'], ['9780553383041']);
  });

  testWidgets('an author without any ISBN costs no request', (tester) async {
    books.mockBooks = [_book('b9', 'Handwritten', 'Ursula K. Le Guin')];

    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(
          jsonEncode(_resolvedAuthor(['Never Shown'])),
          200,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(hubBodies, isEmpty);
    expect(find.text('Never Shown'), findsNothing);
    expect(find.text('Handwritten'), findsOneWidget);
  });

  testWidgets('an ambiguous answer shows nothing, never an error surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(jsonEncode({'status': 'ambiguous'}), 200),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SuggestionTile), findsNothing);
    expect(find.text('To discover'), findsNothing);
    expect(find.text('A Wizard of Earthsea'), findsOneWidget);
  });

  testWidgets('an empty identity index disables the lane, membrane first', (
    tester,
  ) async {
    // Below the ADR-059 profile floor the FFI returns an empty index.
    // Running the lane there would offer books already on the shelf, which
    // the precision doctrine forbids: the ADR-061 "visits bypass the
    // floors" rule stops exactly here.
    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(
          jsonEncode(_resolvedAuthor(['Never Shown'])),
          200,
        ),
        libraryKeys: const {},
      ),
    );
    await tester.pumpAndSettle();

    expect(hubBodies, isEmpty);
    expect(find.byType(SuggestionTile), findsNothing);
  });

  testWidgets('the page title is a heading, not a button', (tester) async {
    await tester.pumpWidget(
      harness(
        'Ursula K. Le Guin',
        answer: () => http.Response(jsonEncode({'status': 'unknown'}), 200),
      ),
    );
    await tester.pumpAndSettle();

    // The page IS this author: only the names that LEAD here are buttons
    // (ADR-061 section 7, decision A2).
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Ursula K. Le Guin'),
        ),
      ),
      containsSemantics(isHeader: true, isButton: false),
    );
  });
}
