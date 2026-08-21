import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';

/// ADR-062 section 5: the blend rule moves into the provider so the
/// dashboard digest and the library slot cannot drift apart. These tests
/// pin the rule the dashboard shipped with (ADR-060 section 4.4): externals
/// take at most their cap, they sit AFTER the locals, and locals fill the
/// remaining slots.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.personal);

  final PersonalRecommendations? personal;

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
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Recommendation _local(String id, String title) {
  return Recommendation(
    book: Book(id: id, title: title),
    score: 1,
    reasons: const [RecommendationReason(type: 'same_author', value: 'X')],
  );
}

PersonalRecommendations _payload(List<Recommendation> recs) {
  return PersonalRecommendations(
    recommendations: recs,
    topSubjects: const [],
    favoriteAuthors: const [],
    scoredBooksCount: 12,
  );
}

Future<RecommendationProvider> _providerWith(
  List<Recommendation> locals,
) async {
  final provider = RecommendationProvider(
    _FakeRepository(_payload(locals)),
    BookRefreshNotifier(),
  );
  // The constructor loads the dismissal stores asynchronously and REPLACES
  // the sets when it lands. Let it settle before a test dismisses anything,
  // or the load overwrites the dismissal.
  await Future<void>.delayed(Duration.zero);
  await provider.loadPersonal();
  return provider;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('blendedDigest', () {
    test('locals first, capped at maxDisplayed', () async {
      final provider = await _providerWith([
        for (var i = 0; i < 8; i++) _local('b$i', 'Book $i'),
      ]);

      final blend = provider.blendedDigest(maxDisplayed: 5, maxExternal: 2);

      expect(blend.length, 5);
      expect(blend.map((r) => r.book.title), [
        'Book 0',
        'Book 1',
        'Book 2',
        'Book 3',
        'Book 4',
      ]);
    });

    test('a dismissed local is counted out of the blend', () async {
      final provider = await _providerWith([
        for (var i = 0; i < 4; i++) _local('b$i', 'Book $i'),
      ]);
      await provider.dismiss('b1');

      final blend = provider.blendedDigest(maxDisplayed: 5, maxExternal: 2);

      expect(blend.map((r) => r.book.title), ['Book 0', 'Book 2', 'Book 3']);
    });

    test('the caps are per-surface, not global', () async {
      final provider = await _providerWith([
        for (var i = 0; i < 12; i++) _local('b$i', 'Book $i'),
      ]);

      expect(provider.blendedDigest(maxDisplayed: 3, maxExternal: 1).length, 3);
      expect(provider.blendedDigest(maxDisplayed: 5, maxExternal: 2).length, 5);
      expect(provider.blendedDigest(maxDisplayed: 8, maxExternal: 2).length, 8);
    });

    test('the horizontal slot shows MORE than the vertical digest', () async {
      // The dashboard cap protects vertical space: ten stacked rows cost ten
      // row heights. A horizontal strip pays nothing vertically for an extra
      // card, so importing the digest cap there was a mistake.
      expect(
        RecommendationProvider.slotMaxDisplayed,
        greaterThan(RecommendationProvider.dashboardMaxDisplayed),
      );
      // Discovery still stays a minority of the strip (ADR-060 section 4.4).
      expect(
        RecommendationProvider.slotMaxExternal * 2,
        lessThan(RecommendationProvider.slotMaxDisplayed),
      );
    });
  });

  group('the visible-suggestions floor', () {
    test('passes at two visible suggestions', () async {
      final provider = await _providerWith([
        _local('b0', 'Book 0'),
        _local('b1', 'Book 1'),
      ]);

      expect(provider.hasVisibleSuggestions, isTrue);
    });

    test('fails at one, dismissals counted', () async {
      final provider = await _providerWith([
        _local('b0', 'Book 0'),
        _local('b1', 'Book 1'),
      ]);
      await provider.dismiss('b1');

      expect(provider.hasVisibleSuggestions, isFalse);
    });

    test('fails when the profile floor never loaded anything', () async {
      final provider = RecommendationProvider(
        _FakeRepository(null),
        BookRefreshNotifier(),
      );
      await provider.loadPersonal();

      expect(
        provider.hasVisibleSuggestions,
        isFalse,
        reason: 'below the profile floor the FFI returns nothing at all',
      );
      expect(provider.hasReachedProfileFloor, isFalse);
    });

    test('the profile floor is independent of the visible floor', () async {
      // One suggestion: the profile floor passed (the engine answered),
      // the visible floor did not. The app-bar action keys on the first.
      final provider = await _providerWith([_local('b0', 'Book 0')]);

      expect(provider.hasReachedProfileFloor, isTrue);
      expect(provider.hasVisibleSuggestions, isFalse);
    });
  });
}
