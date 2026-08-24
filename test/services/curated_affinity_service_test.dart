import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/services/curated_affinity_service.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';

/// ADR-066: which curated lists overlap the library enough to be suggested.
///
/// The guards under test are the ones the research doc froze: a threshold on
/// books in common, a score expressed as a RATIO so a mega-list cannot match
/// everyone, liked books weighing more than merely owned ones, and the
/// ADR-060 identity membrane deciding what "owned" means, translations
/// included.

const _service = CuratedAffinityService();

CuratedList _list(
  String id, {
  required List<CuratedBook> books,
  List<String> languages = const ['fr'],
  List<String> tags = const [],
  String curationStatus = CuratedList.curationReviewed,
}) {
  return CuratedList(
    id: id,
    version: 1,
    title: {'fr': 'Liste $id', 'en': 'List $id'},
    description: const {'fr': '', 'en': ''},
    tags: tags,
    books: books,
    contentLanguages: languages,
    curationStatus: curationStatus,
  );
}

/// Ten entries of which three are owned: the smallest shape that passes
/// every affinity gate, so a test can vary one thing at a time.
List<CuratedBook> _threeOfTen() => [
  _entry('9782070541270', 'Owned One', 'An Author'),
  _entry('9780306406157', 'Owned Two', 'An Author'),
  _entry('9780441007318', 'Owned Three', 'An Author'),
  ..._filler(7),
];

const _threeOwnedIsbns = {
  '9782070541270',
  '9780306406157',
  '9780441007318',
};

/// A note-only entry, the shape 100% of the note-carrying corpus uses.
CuratedBook _entry(String isbn, String title, String author) =>
    CuratedBook(isbn: isbn, note: '$title - $author');

/// N entries nobody owns, to pad a list out to a chosen size.
List<CuratedBook> _filler(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    _entry('978000000${i.toString().padLeft(4, '0')}', 'Filler $i', 'Nobody'),
];

DiscoveryLookupInputs _inputs({
  Set<String> isbns = const {},
  Set<String> keys = const {},
  Set<String> likedIsbns = const {},
  Set<String> likedKeys = const {},
}) {
  return DiscoveryLookupInputs(
    series: const [],
    authors: const [],
    libraryIsbns: isbns,
    libraryTitleAuthorKeys: keys,
    likedIsbns: likedIsbns,
    likedTitleAuthorKeys: likedKeys,
  );
}

List<CuratedAffinity> _rank(
  List<CuratedList> lists,
  DiscoveryLookupInputs inputs, {
  List<String> languages = const ['fr'],
  Map<String, String> covers = const {},
  Set<String> readerGenres = const {},
}) {
  return _service.rank(
    lists: lists,
    inputs: inputs,
    readerLanguages: languages,
    ownedCoverUrls: covers,
    readerGenreKeys: readerGenres,
  );
}

void main() {
  group('the editorial quality gate', () {
    test('a draft list is never suggested, however strong the overlap', () {
      // The tier turns a list from something the reader goes and finds into
      // something the app puts in front of them. The quality bar rises with
      // that, and this is the only dial a curator turns list by list.
      final list = _list(
        'draft',
        books: _threeOfTen(),
        curationStatus: CuratedList.curationDraft,
      );

      expect(_rank([list], _inputs(isbns: _threeOwnedIsbns)), isEmpty);
    });

    test('the same list reviewed is suggested', () {
      final list = _list(
        'reviewed',
        books: _threeOfTen(),
        curationStatus: CuratedList.curationReviewed,
      );

      expect(_rank([list], _inputs(isbns: _threeOwnedIsbns)), hasLength(1));
    });

    test('an absent status reads as draft, not as reviewed', () {
      // Fail-closed on purpose: a gate defaulting open would gate nothing
      // on exactly the lists nobody has audited yet.
      final list = CuratedList(
        id: 'legacy',
        version: 1,
        title: const {'fr': 'Legacy'},
        description: const {'fr': ''},
        tags: const [],
        books: _threeOfTen(),
        contentLanguages: const ['fr'],
      );

      expect(list.isReviewed, isFalse);
      expect(_rank([list], _inputs(isbns: _threeOwnedIsbns)), isEmpty);
    });

    test('a typo in the marker fails closed', () {
      final list = _list(
        'typo',
        books: _threeOfTen(),
        curationStatus: 'Reviewed ',
      );

      expect(_rank([list], _inputs(isbns: _threeOwnedIsbns)), isEmpty);
    });

    test('the YAML marker is parsed, and only the exact value promotes', () {
      CuratedList parse(String statusLine) => CuratedList.fromYaml(
        loadYaml('''
id: sample
version: 1
title:
  fr: Sample
description:
  fr: Desc
tags: [sample]
content_languages: [fr]
$statusLine
books:
  - isbn: "9780000000001"
    note: "A - B"
''') as YamlMap,
      );

      expect(parse('curation_status: reviewed').isReviewed, isTrue);
      expect(parse('curation_status: "reviewed"').isReviewed, isTrue);
      expect(parse('curation_status: draft').isReviewed, isFalse);
      expect(parse('curation_status: REVIEWED').isReviewed, isFalse);
      // No marker at all: every list authored before the gate existed.
      expect(parse('# no curation_status').isReviewed, isFalse);
    });
  });

  group('overlap thresholds', () {
    test('three owned books out of ten earns a card', () {
      final list = _list(
        'ten',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          _entry('9780441007318', 'Owned Three', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked, hasLength(1));
      expect(ranked.single.ownedCount, 3);
      expect(ranked.single.totalCount, 10);
      expect(ranked.single.remainingCount, 7);
    });

    test('two owned books DO count when the list is short enough', () {
      // The floor of three exists because two books in common on a large
      // library is what chance produces. On a FOUR-entry selection it is not
      // chance: half the list is already on the shelf. Measured on the
      // reference library (2026-08-24), this is the only near-miss shaped
      // like a real affinity: programming-rust, 2 owned of 4.
      final list = _list(
        'four',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          ..._filler(2),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(isbns: {'9782070541270', '9780306406157'}),
      );

      expect(ranked, hasLength(1));
      expect(ranked.single.ownedCount, 2);
      expect(ranked.single.totalCount, 4);
    });

    test('the short-list exception needs a STRONG ratio, not just a pair', () {
      // Two of five is exactly the floor and passes; two of six is below it
      // and does not. Without this the exception would swallow the rule.
      final borderline = _list(
        'five',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          ..._filler(3),
        ],
      );
      final tooThin = _list(
        'six',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          ..._filler(4),
        ],
      );
      final owned = {'9782070541270', '9780306406157'};

      expect(_rank([borderline], _inputs(isbns: owned)), hasLength(1));
      expect(_rank([tooThin], _inputs(isbns: owned)), isEmpty);
    });

    test('one book in common is never enough, however short the list', () {
      // One of two is a ratio of 0.5, above the strong floor, and must still
      // be refused: the exception lowers the pair to two, never to one.
      final list = _list(
        'two',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          ..._filler(1),
        ],
      );

      expect(_rank([list], _inputs(isbns: {'9782070541270'})), isEmpty);
    });

    test('two owned books is a coincidence, not an affinity', () {
      final list = _list(
        'ten',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          ..._filler(8),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(isbns: {'9782070541270', '9780306406157'}),
      );

      expect(ranked, isEmpty);
    });

    test('a list with nothing left to discover is not suggested', () {
      // 3 owned of 4: past the count gate and far past the ratio gate, but
      // only one book remains. The reader has this selection already.
      final list = _list(
        'four',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          _entry('9780441007318', 'Owned Three', 'An Author'),
          ..._filler(1),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked, isEmpty);
    });
  });

  group('the mega-list guard', () {
    test('a 72-entry list with three owned books matches nobody', () {
      // The shape the research doc names: a canon or a long series overlaps
      // every library, so a RAW COUNT would suggest it to everyone. Ratio
      // 3/72 = 0.042, far below the floor.
      final list = _list(
        'mega',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          _entry('9780441007318', 'Owned Three', 'An Author'),
          ..._filler(69),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked, isEmpty);
    });

    test('the same three books on a ten-entry selection DO match', () {
      // Same absolute overlap, different denominator: this is exactly what
      // makes the ratio the load-bearing guard rather than the count.
      final list = _list(
        'small',
        books: [
          _entry('9782070541270', 'Owned One', 'An Author'),
          _entry('9780306406157', 'Owned Two', 'An Author'),
          _entry('9780441007318', 'Owned Three', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked, hasLength(1));
    });
  });

  group('liked books weigh more', () {
    test('an overlap of liked books outranks an equal unliked one', () {
      final liked = _list(
        'liked',
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final plain = _list(
        'plain',
        books: [
          _entry('9782253006329', 'D', 'An Author'),
          _entry('9782070368228', 'E', 'An Author'),
          _entry('9780140449136', 'F', 'An Author'),
          ..._filler(7, from: 100),
        ],
      );

      final ranked = _rank(
        [plain, liked],
        _inputs(
          isbns: {
            '9782070541270',
            '9780306406157',
            '9780441007318',
            '9782253006329',
            '9782070368228',
            '9780140449136',
          },
          likedIsbns: {'9782070541270', '9780306406157'},
        ),
      );

      expect(ranked.map((a) => a.list.id), ['liked', 'plain']);
      expect(ranked.first.likedCount, 2);
      expect(ranked.last.likedCount, 0);
      expect(ranked.first.score, greaterThan(ranked.last.score));
    });

    test('zero liked books does not disqualify a list', () {
      // The liked signal is structurally sparse (14 liked books out of 492
      // on the reference library), so it weighs and explains; it does not
      // gate. A gate here would leave the whole tier dark.
      final list = _list(
        'unliked',
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked, hasLength(1));
      expect(ranked.single.likedCount, 0);
    });
  });

  group('the tag bonus can reorder but never open the gate', () {
    test('a thematic match does not make a thin overlap eligible', () {
      final list = _list(
        'thin',
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          ..._filler(9),
        ],
        tags: const ['polar'],
      );
      final ranked = _rank(
        [list],
        _inputs(isbns: {'9782070541270'}),
        readerGenres: const {'genre_detective'},
      );

      expect(ranked, isEmpty);
    });

    test('it breaks a tie between two equal overlaps', () {
      List<CuratedBook> owned(List<String> isbns) => [
        for (final isbn in isbns) _entry(isbn, 'Book $isbn', 'An Author'),
      ];
      final tagged = _list(
        'tagged',
        books: [
          ...owned(['9782070541270', '9780306406157', '9780441007318']),
          ..._filler(7),
        ],
        tags: const ['polar'],
      );
      final untagged = _list(
        'untagged',
        books: [
          ...owned(['9782253006329', '9782070368228', '9780140449136']),
          ..._filler(7, from: 100),
        ],
        tags: const ['prix'],
      );

      final ranked = _rank(
        [untagged, tagged],
        _inputs(
          isbns: {
            '9782070541270',
            '9780306406157',
            '9780441007318',
            '9782253006329',
            '9782070368228',
            '9780140449136',
          },
        ),
        readerGenres: const {'genre_detective'},
      );

      expect(ranked.map((a) => a.list.id), ['tagged', 'untagged']);
      expect(ranked.first.sharedGenreKeys, contains('genre_detective'));
    });
  });

  group('the language gate', () {
    test('an fr-only list is invisible to an en-only reader', () {
      final list = _list(
        'fr-only',
        languages: const ['fr'],
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final inputs = _inputs(
        isbns: {'9782070541270', '9780306406157', '9780441007318'},
      );

      expect(_rank([list], inputs, languages: const ['en']), isEmpty);
      expect(_rank([list], inputs, languages: const ['fr']), hasLength(1));
    });

    test('a bilingual list reaches a reader of either language', () {
      final list = _list(
        'bilingual',
        languages: const ['en', 'fr'],
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final inputs = _inputs(
        isbns: {'9782070541270', '9780306406157', '9780441007318'},
      );

      expect(_rank([list], inputs, languages: const ['en']), hasLength(1));
      expect(_rank([list], inputs, languages: const ['es']), isEmpty);
    });

    test('a list declaring no language is never suggested', () {
      // The import screen routes those to its "other languages" section so
      // they stay discoverable in a catalogue the reader chose to open. An
      // unsolicited suggestion is the opposite trade: absent beats wrong.
      final list = _list(
        'untagged-language',
        languages: const [],
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked, isEmpty);
    });
  });

  group('the identity membrane', () {
    test('matching stays translingual: an owned translation counts', () {
      // The reader owns the French "L'Etranger"; the list is an English one
      // naming the same work. It counts toward the overlap, and it is NOT
      // in what remains to discover. Deliberate, per ADR-060 section 4.2.
      final list = _list(
        'en-list',
        languages: const ['en', 'fr'],
        books: [
          _entry('9780679720201', "L'Étranger", 'Albert Camus'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          // A DIFFERENT edition ISBN, so only title+author can match.
          isbns: {'9780306406157', '9780441007318'},
          keys: {'l etranger|albert camus'},
        ),
      );

      expect(ranked, hasLength(1));
      expect(ranked.single.ownedCount, 3);
    });

    test('an inverted catalogue name still matches', () {
      // Catalogues store "Camus, Albert"; the corpus stores the natural
      // order. The shared index sorts author words on both sides.
      final list = _list(
        'inverted',
        books: [
          _entry('9780679720201', 'The Stranger', 'Albert Camus'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9780306406157', '9780441007318'},
          keys: {'the stranger|camus albert'},
        ),
      );

      expect(ranked.single.ownedCount, 3);
    });

    test('an entry is recognised through any of its editions', () {
      final list = _list(
        'alt-editions',
        books: [
          const CuratedBook(
            isbn: '9780679720201',
            note: 'The Stranger - Albert Camus',
            altEditions: {'fr': '9782070360024'},
          ),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        // The reader owns the French edition the entry lists as an
        // alternative, not the one the contributor picked.
        _inputs(
          isbns: {'9782070360024', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked.single.ownedCount, 3);
    });

    test('below the profile floor nothing is measured at all', () {
      // The ADR-059 floor reaches the client as an empty identity index.
      // Running the membrane against nothing would count every entry as
      // unowned and could still not produce a card, but the guard has to be
      // explicit: a future weight must not be able to slip past it.
      final list = _list(
        'anything',
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );

      expect(_rank([list], _inputs()), isEmpty);
    });
  });

  group('the card payload', () {
    test('the mosaic uses the reader OWN covers of the shared books', () {
      final list = _list(
        'covers',
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
        covers: const {
          '9782070541270': 'file:///local/a.jpg',
          '9780306406157': 'file:///local/b.jpg',
          // The third owned book has no cover: the mosaic simply carries two.
        },
      );

      expect(ranked.single.ownedCoverUrls, [
        'file:///local/a.jpg',
        'file:///local/b.jpg',
      ]);
    });

    test('the mosaic never holds more than four covers', () {
      final list = _list(
        'many',
        books: [
          for (var i = 0; i < 6; i++)
            _entry('978111111${i.toString().padLeft(4, '0')}', 'B$i', 'A'),
          ..._filler(6),
        ],
      );
      final owned = {
        for (var i = 0; i < 6; i++) '978111111${i.toString().padLeft(4, '0')}',
      };
      final ranked = _rank(
        [list],
        _inputs(isbns: owned),
        covers: {for (final isbn in owned) isbn: 'file:///$isbn.jpg'},
      );

      expect(
        ranked.single.ownedCoverUrls,
        hasLength(CuratedAffinityService.mosaicCovers),
      );
    });

    test('the dismissal key is namespaced by list id', () {
      final list = _list(
        'goncourt',
        books: [
          _entry('9782070541270', 'A', 'An Author'),
          _entry('9780306406157', 'B', 'An Author'),
          _entry('9780441007318', 'C', 'An Author'),
          ..._filler(7),
        ],
      );
      final ranked = _rank(
        [list],
        _inputs(
          isbns: {'9782070541270', '9780306406157', '9780441007318'},
        ),
      );

      expect(ranked.single.dismissalKey, 'list:goncourt');
    });
  });

  group('which entries the reader already owns', () {
    // The preview marks them, so the reader sees how much of a list is new
    // before they agree to import it. The predicate is the SAME membrane the
    // overlap count uses; a second one would let the card claim three books
    // in common while the preview ticked two.
    test('the indexes are the ones the membrane matched', () {
      final list = _list('overlap', books: _threeOfTen());

      final owned = _service.ownedEntryIndexes(
        list: list,
        inputs: _inputs(isbns: _threeOwnedIsbns),
      );

      expect(owned, {0, 1, 2});
    });

    test('a translation owned under another ISBN still counts', () {
      // Cross-language matching is deliberate (ADR-066 section 2.1): the
      // reader has the French edition of an English list's book, so the
      // preview must not offer it back as new.
      final list = _list(
        'overlap',
        books: [
          _entry('9781111111111', 'The Trial', 'Franz Kafka'),
          ..._filler(9),
        ],
      );

      final owned = _service.ownedEntryIndexes(
        list: list,
        inputs: _inputs(keys: const {'the trial|franz kafka'}),
      );

      expect(owned, {0});
    });

    test('below the profile floor nothing is claimed', () {
      // The FFI returns the empty default below the ADR-059 floor. Running
      // the membrane against nothing would tick no book, which is right, but
      // the guard is explicit so a future caller cannot read the empty set
      // as "the reader owns none of these".
      final list = _list('overlap', books: _threeOfTen());

      expect(
        _service.ownedEntryIndexes(list: list, inputs: _inputs()),
        isEmpty,
      );
    });
  });
}
