import 'dart:async';
import 'dart:convert';

import 'package:bibliogenius/models/memory_game.dart';
import 'package:bibliogenius/providers/memory_game_provider.dart';
import 'package:bibliogenius/src/rust/api/frb.dart';
import 'package:bibliogenius/services/memory_cover_check.dart';
import 'package:flutter_test/flutter_test.dart';

MemoryCard _card(String id) =>
    MemoryCard(bookId: id, title: 'Book $id', coverUrl: 'https://c/$id.jpg');

List<MemoryCard> _board(List<String> ids) => [
  for (final id in ids) _card(id),
  for (final id in ids.reversed) _card(id),
];

CoverCheck _failing(Set<String> deadIds, {List<String>? asked}) => (url) async {
  final id = url.split('/').last.replaceAll('.jpg', '');
  asked?.add(id);
  return !deadIds.contains(id);
};

// A 1x1 transparent PNG, what Open Library serves for an ISBN without cover.
const _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

FrbMemoryCard _frbCard(String id) =>
    FrbMemoryCard(bookId: id, title: 'Book $id', coverUrl: 'https://c/$id.jpg');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a board whose covers all draw is returned untouched', () async {
    final cards = _board(['a', 'b']);
    final result = await keepDrawablePairs(
      cards: cards,
      reserve: [_card('r1')],
      isDrawable: _failing({}),
    );
    expect(result, same(cards));
  });

  test(
    'a failing pair is replaced by a reserve book at both positions',
    () async {
      final cards = _board(['a', 'b', 'c']);
      final result = await keepDrawablePairs(
        cards: cards,
        reserve: [_card('r1'), _card('r2')],
        isDrawable: _failing({'b'}),
      );

      expect(result.map((c) => c.bookId).toList(), [
        'a', 'r1', 'c', 'c', 'r1', 'a', //
      ]);
      // Two distinct instances: flip state is per card.
      final replaced = result.where((c) => c.bookId == 'r1').toList();
      expect(identical(replaced[0], replaced[1]), isFalse);
    },
  );

  test('a reserve book that fails too is skipped for the next one', () async {
    final asked = <String>[];
    final result = await keepDrawablePairs(
      cards: _board(['a', 'b']),
      reserve: [_card('r1'), _card('r2'), _card('r3')],
      isDrawable: _failing({'a', 'b', 'r1'}, asked: asked),
    );

    expect(result.map((c) => c.bookId).toSet(), {'r2', 'r3'});
    expect(asked, ['a', 'b', 'r1', 'r2', 'r3']);
  });

  test('only as many reserve books as needed are checked', () async {
    final asked = <String>[];
    await keepDrawablePairs(
      cards: _board(['a', 'b']),
      reserve: [_card('r1'), _card('r2'), _card('r3')],
      isDrawable: _failing({'a'}, asked: asked),
    );
    expect(asked, ['a', 'b', 'r1']);
  });

  test('an exhausted reserve throws instead of dealing grey pairs', () async {
    expect(
      keepDrawablePairs(
        cards: _board(['a', 'b']),
        reserve: [_card('r1')],
        isDrawable: _failing({'a', 'b'}),
      ),
      throwsA(
        isA<NotEnoughDrawableCoversException>().having(
          (e) => e.missing,
          'missing',
          1,
        ),
      ),
    );
  });

  test('an empty URL never counts as drawable', () async {
    expect(await isCoverDrawable(''), isFalse);
  });

  test('the reserve is walked for a bounded number of rounds', () async {
    final asked = <String>[];
    await expectLater(
      keepDrawablePairs(
        cards: _board(['a']),
        reserve: [for (var i = 1; i <= 10; i++) _card('r$i')],
        isDrawable: (url) async {
          asked.add(url);
          return false;
        },
        maxReserveRounds: 2,
      ),
      throwsA(isA<NotEnoughDrawableCoversException>()),
    );
    // The board book, then one reserve book per round.
    expect(asked, hasLength(3));
  });

  test('a 1x1 stand-in pixel is not a drawable cover', () async {
    expect(await hasDrawableWidth(base64Decode(_onePixelPng)), isFalse);
  });

  test('a deal superseded by a reset never starts a game', () async {
    final covers = Completer<bool>();
    final provider = MemoryGameProvider(
      coverCheck: (_) => covers.future,
      dealGame: (_) async => FrbMemoryDeal(
        cards: [_frbCard('a'), _frbCard('a')],
        reserve: const [],
      ),
    );
    addTearDown(provider.dispose);
    provider.selectDifficulty('easy');

    final started = provider.startGame();
    await Future<void>.delayed(Duration.zero);
    expect(provider.isLoading, isTrue);

    // The player leaves while covers are still being checked.
    provider.resetToSetup();
    covers.complete(true);
    await started;

    expect(provider.phase, GamePhase.setup);
    expect(provider.cards, isEmpty);
    expect(provider.isLoading, isFalse);
    expect(provider.elapsedSeconds, 0);
  });

  test('a current deal whose covers all fail reports it', () async {
    final provider = MemoryGameProvider(
      coverCheck: (_) async => false,
      dealGame: (_) async => FrbMemoryDeal(
        cards: [_frbCard('a'), _frbCard('a')],
        reserve: const [],
      ),
    );
    addTearDown(provider.dispose);
    provider.selectDifficulty('easy');

    await provider.startGame();

    expect(provider.coversUnavailable, isTrue);
    expect(provider.phase, GamePhase.setup);
  });

  test('a deal abandoned when the screen goes never starts a game', () async {
    final covers = Completer<bool>();
    final provider = MemoryGameProvider(
      coverCheck: (_) => covers.future,
      dealGame: (_) async => FrbMemoryDeal(
        cards: [_frbCard('a'), _frbCard('a')],
        reserve: const [],
      ),
    );
    addTearDown(provider.dispose);
    provider.selectDifficulty('easy');

    final started = provider.startGame();
    await Future<void>.delayed(Duration.zero);
    provider.abandonPendingDeal();
    covers.complete(true);
    await started;

    expect(provider.phase, GamePhase.setup);
    expect(provider.cards, isEmpty);
    expect(provider.isLoading, isFalse);
  });

  test('abandoning with no deal in flight leaves a running game alone', () async {
    final provider = MemoryGameProvider(
      coverCheck: (_) async => true,
      dealGame: (_) async => FrbMemoryDeal(
        cards: [_frbCard('a'), _frbCard('a')],
        reserve: const [],
      ),
    );
    addTearDown(provider.dispose);
    provider.selectDifficulty('easy');
    await provider.startGame();

    provider.abandonPendingDeal();

    expect(provider.phase, GamePhase.playing);
    expect(provider.cards, hasLength(2));
  });
}
