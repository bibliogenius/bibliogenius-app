import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';

import '../helpers/mock_repositories.dart';

/// ADR-066: how the provider exposes the editorial tier. The measurement
/// itself is covered by `curated_affinity_service_test.dart`; this covers
/// the gates around it, the per-surface caps, the `list:<id>` dismissal and
/// what an import does to a card.

class _FakeRepository implements RecommendationRepository {
  _FakeRepository({this.personal, this.inputs});

  final PersonalRecommendations? personal;
  final DiscoveryLookupInputs? inputs;
  int inputsCalls = 0;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => personal;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async {
    inputsCalls++;
    return inputs;
  }
}

class _FakeBooks extends MockBookRepository {
  _FakeBooks(this._books);

  final List<Book> _books;

  @override
  Future<List<Book>> getBooks({
    String? status,
    String? author,
    String? title,
    String? tag,
  }) async => _books;
}

CuratedList _list(String id, {int owned = 3, int total = 10}) {
  return CuratedList(
    id: id,
    version: 1,
    title: {'fr': 'Liste $id', 'en': 'List $id'},
    description: const {'fr': '', 'en': ''},
    tags: const [],
    contentLanguages: const ['fr'],
    curationStatus: CuratedList.curationReviewed,
    books: [
      for (var i = 0; i < owned; i++)
        CuratedBook(isbn: _ownedIsbn(id, i), note: 'Owned $i - An Author'),
      for (var i = 0; i < total - owned; i++)
        CuratedBook(isbn: '97899$id$i'.padRight(13, '0'), note: 'Rest $i - X'),
    ],
  );
}

String _ownedIsbn(String id, int index) =>
    '97810${id.hashCode.abs() % 1000}$index'.padRight(13, '0');

Set<String> _ownedIsbnsOf(String id, int count) => {
  for (var i = 0; i < count; i++) _ownedIsbn(id, i),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  RecommendationProvider build({
    required List<CuratedList> corpus,
    required DiscoveryLookupInputs? inputs,
    List<Book> books = const [],
    int? corpusCalls,
  }) {
    return RecommendationProvider(
      _FakeRepository(inputs: inputs),
      BookRefreshNotifier(),
      curatedCorpusLoader: () async => corpus,
      bookRepository: _FakeBooks(books),
    );
  }

  DiscoveryLookupInputs inputsFor(Iterable<String> isbns) {
    return DiscoveryLookupInputs(
      series: const [],
      authors: const [],
      libraryIsbns: isbns.toSet(),
      libraryTitleAuthorKeys: const {},
    );
  }

  test('an eligible list becomes a visible affinity', () async {
    final provider = build(
      corpus: [_list('a')],
      inputs: inputsFor(_ownedIsbnsOf('a', 3)),
    );

    await provider.loadCuratedAffinity(readerLanguages: const ['fr']);

    expect(provider.visibleCuratedAffinities, hasLength(1));
    expect(provider.visibleCuratedAffinities.single.list.id, 'a');
  });

  test('nothing is measured below the profile floor', () async {
    // The floor reaches the client as an empty identity index. A card built
    // against it would claim an overlap nobody verified.
    final provider = build(
      corpus: [_list('a')],
      inputs: const DiscoveryLookupInputs(
        series: [],
        authors: [],
        libraryIsbns: {},
        libraryTitleAuthorKeys: {},
      ),
    );

    await provider.loadCuratedAffinity(readerLanguages: const ['fr']);

    expect(provider.visibleCuratedAffinities, isEmpty);
  });

  test('an unavailable backend yields no cards and no throw', () async {
    final provider = build(corpus: [_list('a')], inputs: null);

    await provider.loadCuratedAffinity(readerLanguages: const ['fr']);

    expect(provider.visibleCuratedAffinities, isEmpty);
  });

  test('the corpus is parsed once per session, not once per call', () async {
    var calls = 0;
    final provider = RecommendationProvider(
      _FakeRepository(inputs: inputsFor(_ownedIsbnsOf('a', 3))),
      BookRefreshNotifier(),
      curatedCorpusLoader: () async {
        calls++;
        return [_list('a')];
      },
      bookRepository: _FakeBooks(const []),
    );

    await provider.loadCuratedAffinity(readerLanguages: const ['fr']);
    await provider.loadCuratedAffinity(readerLanguages: const ['fr'], force: true);

    expect(calls, 1, reason: 'The bundle cannot change without an app update.');
  });

  test('a catalogue mutation makes the affinity stale again', () async {
    final notifier = BookRefreshNotifier();
    final provider = RecommendationProvider(
      _FakeRepository(inputs: inputsFor(_ownedIsbnsOf('a', 3))),
      notifier,
      curatedCorpusLoader: () async => [_list('a')],
      bookRepository: _FakeBooks(const []),
    );

    await provider.loadCuratedAffinity(readerLanguages: const ['fr']);
    expect(provider.visibleCuratedAffinities, hasLength(1));

    // Importing a list is the likeliest mutation here, and it changes every
    // overlap count on screen.
    notifier.refresh();
    await provider.loadCuratedAffinity(readerLanguages: const ['en']);

    expect(
      provider.visibleCuratedAffinities,
      isEmpty,
      reason: 'A stale affinity must be recomputed, not served.',
    );
  });

  group('per-surface caps', () {
    test('the slot takes one card and the Collections block two', () async {
      final provider = build(
        corpus: [_list('a'), _list('b'), _list('c')],
        inputs: inputsFor({
          ..._ownedIsbnsOf('a', 3),
          ..._ownedIsbnsOf('b', 3),
          ..._ownedIsbnsOf('c', 3),
        }),
      );

      await provider.loadCuratedAffinity(readerLanguages: const ['fr']);

      expect(provider.visibleCuratedAffinities, hasLength(3));
      expect(
        provider.curatedAffinitiesFor(
          cap: RecommendationProvider.slotMaxCuratedLists,
        ),
        hasLength(1),
      );
      expect(
        provider.curatedAffinitiesFor(
          cap: RecommendationProvider.collectionsMaxCuratedLists,
        ),
        hasLength(2),
      );
    });
  });

  group('dismissal', () {
    test('a dismissed list disappears from every surface', () async {
      final provider = build(
        corpus: [_list('a'), _list('b')],
        inputs: inputsFor({
          ..._ownedIsbnsOf('a', 3),
          ..._ownedIsbnsOf('b', 3),
        }),
      );
      await provider.loadCuratedAffinity(readerLanguages: const ['fr']);
      final target = provider.visibleCuratedAffinities.first;

      await provider.dismissExternal(target.dismissalKey);

      expect(
        provider.visibleCuratedAffinities.map((a) => a.list.id),
        isNot(contains(target.list.id)),
      );
    });

    test('it rides the existing external store under a list namespace', () async {
      final provider = build(
        corpus: [_list('a')],
        inputs: inputsFor(_ownedIsbnsOf('a', 3)),
      );
      await provider.loadCuratedAffinity(readerLanguages: const ['fr']);

      await provider.dismissExternal('list:a');

      expect(provider.dismissedExternalKeys, contains('list:a'));
      expect(
        provider.isExternalDismissed('isbn:9782070541270'),
        isFalse,
        reason: 'Namespaces must not collide with the ISBN-keyed entries.',
      );
    });

    test('undo brings the card back', () async {
      final provider = build(
        corpus: [_list('a')],
        inputs: inputsFor(_ownedIsbnsOf('a', 3)),
      );
      await provider.loadCuratedAffinity(readerLanguages: const ['fr']);

      await provider.dismissExternal('list:a');
      expect(provider.visibleCuratedAffinities, isEmpty);

      await provider.restoreDismissedExternal('list:a');
      expect(provider.visibleCuratedAffinities, hasLength(1));
    });
  });

  test('an imported list stops being suggested this session', () async {
    // The identity index only refreshes on the next pass, so without this
    // the card would linger showing a count the import just invalidated.
    final provider = build(
      corpus: [_list('a'), _list('b')],
      inputs: inputsFor({
        ..._ownedIsbnsOf('a', 3),
        ..._ownedIsbnsOf('b', 3),
      }),
    );
    await provider.loadCuratedAffinity(readerLanguages: const ['fr']);
    expect(provider.visibleCuratedAffinities, hasLength(2));

    provider.hideCuratedAfterImport('a');

    expect(provider.visibleCuratedAffinities.map((a) => a.list.id), ['b']);
  });

  test('the tier is absent when no corpus loader is wired', () async {
    final provider = RecommendationProvider(
      _FakeRepository(inputs: inputsFor(_ownedIsbnsOf('a', 3))),
      BookRefreshNotifier(),
    );

    await provider.loadCuratedAffinity(readerLanguages: const ['fr']);

    expect(provider.visibleCuratedAffinities, isEmpty);
  });
}
