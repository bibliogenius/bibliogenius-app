import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';

/// A catalogue mutation must reach the suggestion surfaces that are ALREADY
/// on screen. The library slot (ADR-062) has no load trigger of its own: it
/// renders whatever the provider holds. So a book deleted from anywhere kept
/// showing in "To discover", tappable, all the way to its edit form, until
/// the app was restarted or the dashboard section mounted again.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.personal);

  /// Mutated by the tests between fetches to stand for a catalogue change.
  PersonalRecommendations? personal;

  int fetches = 0;

  /// When set, a fetch parks on it: lets a test land a mutation while a
  /// pass is in flight.
  Completer<void>? gate;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async {
    fetches++;
    // Snapshot BEFORE parking: a fetch answers about the catalogue as it
    // was when it started, which is the whole point of the mid-flight test.
    final answer = personal;
    final gate = this.gate;
    if (gate != null) {
      this.gate = null;
      await gate.future;
    }
    return answer;
  }

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Recommendation _local(String id, String title) => Recommendation(
  book: Book(id: id, title: title),
  score: 1,
  reasons: const [RecommendationReason(type: 'same_author', value: 'X')],
);

PersonalRecommendations _payload(List<Recommendation> recs) =>
    PersonalRecommendations(
      recommendations: recs,
      topSubjects: const [],
      favoriteAuthors: const [],
      scoredBooksCount: 12,
    );

void main() {
  /// Errors the zone swallows on our behalf: the eager revalidation is
  /// fire-and-forget, so a throw inside it never reaches an expect().
  late List<Object> errors;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    errors = [];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) errors.add(message);
    };
  });

  tearDown(() => debugPrint = debugPrintThrottled);

  test('a catalogue mutation refreshes the suggestions on its own', () async {
    final repo = _FakeRepository(
      _payload([_local('a', 'Kept'), _local('b', 'Deleted')]),
    );
    final notifier = BookRefreshNotifier();
    final provider = RecommendationProvider(repo, notifier);
    await pumpEventQueue();
    await provider.loadPersonal();

    expect(provider.visiblePersonal.map((r) => r.book.id), ['a', 'b']);

    // The reader deletes "b". No suggestion surface remounts: the library
    // slot is a StatelessWidget reading the provider.
    repo.personal = _payload([_local('a', 'Kept')]);
    notifier.refresh();
    // Drains the queue rather than counting microtask turns: the eager
    // revalidation is a chain whose depth is an implementation detail, and
    // a fixed number of turns would silently stop proving anything the day
    // it grows one await.
    await pumpEventQueue();

    expect(provider.visiblePersonal.map((r) => r.book.id), ['a']);
  });

  test('a mutation landing mid-fetch is not lost', () async {
    final repo = _FakeRepository(
      _payload([_local('a', 'Kept'), _local('b', 'Deleted')]),
    );
    final notifier = BookRefreshNotifier();
    final provider = RecommendationProvider(repo, notifier);
    await pumpEventQueue();

    final gate = Completer<void>();
    repo.gate = gate;
    final inFlight = provider.loadPersonal();
    await pumpEventQueue();

    // The delete happens while the first pass is still parked: its answer
    // already describes a catalogue that no longer exists.
    repo.personal = _payload([_local('a', 'Kept')]);
    notifier.refresh();
    gate.complete();
    await inFlight;
    await pumpEventQueue();

    expect(provider.visiblePersonal.map((r) => r.book.id), ['a']);
    expect(repo.fetches, 2);
  });

  test('a revalidation landing after dispose notifies nothing', () async {
    final repo = _FakeRepository(_payload([_local('a', 'Kept')]));
    final notifier = BookRefreshNotifier();
    final provider = RecommendationProvider(repo, notifier);
    await pumpEventQueue();

    final gate = Completer<void>();
    repo.gate = gate;
    notifier.refresh();
    await pumpEventQueue();

    // The app tears down while the eager revalidation is still in flight.
    // Nothing is left to check anything: the pass has no widget behind it.
    provider.dispose();
    gate.complete();
    await pumpEventQueue();

    expect(
      errors,
      isEmpty,
      reason: 'notifying a disposed ChangeNotifier throws in debug builds',
    );
  });
}
