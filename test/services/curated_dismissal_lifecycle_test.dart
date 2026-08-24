import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/services/external_suggestion_dismissal_service.dart';
import 'package:bibliogenius/utils/recommendation_display.dart';

/// A curated import writes `list:<id>` into the dismissal store, because
/// importing is the strongest signal a reader can give that they have dealt
/// with a list (ADR-066 section 7). Deleting the collection undoes their
/// gesture, and the app has to undo its own: otherwise the reader removes
/// the books and the suggestion never comes back.

class _Repo implements RecommendationRepository {
  @override
  Future<List<Recommendation>> getBookRecommendations(String id, {int? limit}) async => const [];
  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({int? limit}) async => null;
  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Collection _collection(String source) => Collection(
  id: 'c1',
  name: 'Les 100 livres du siècle',
  source: source,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a collection remembers the list it came from', () {
    test('a curated source names its list', () {
      expect(
        _collection('curated:monde-100-livres').curatedListId,
        'monde-100-livres',
      );
    });

    test('every other source names none', () {
      for (final s in const ['manual', 'series', 'favorites', 'curated:', '']) {
        expect(_collection(s).curatedListId, isNull, reason: s);
      }
    });
  });

  testWidgets('deleting it brings the suggestion back', (tester) async {
    await ExternalSuggestionDismissalService.dismiss('list:monde-100-livres');
    expect(
      await ExternalSuggestionDismissalService.loadDismissed(),
      contains('list:monde-100-livres'),
    );

    final provider = RecommendationProvider(_Repo(), BookRefreshNotifier());
    late BuildContext ctx;
    await tester.pumpWidget(
      ChangeNotifierProvider<RecommendationProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await forgetCuratedListDismissal(
      ctx,
      _collection('curated:monde-100-livres'),
    );

    expect(
      await ExternalSuggestionDismissalService.loadDismissed(),
      isNot(contains('list:monde-100-livres')),
    );
  });

  testWidgets('deleting an ordinary collection touches nothing', (
    tester,
  ) async {
    await ExternalSuggestionDismissalService.dismiss('list:monde-100-livres');

    final provider = RecommendationProvider(_Repo(), BookRefreshNotifier());
    late BuildContext ctx;
    await tester.pumpWidget(
      ChangeNotifierProvider<RecommendationProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await forgetCuratedListDismissal(ctx, _collection('manual'));

    expect(
      await ExternalSuggestionDismissalService.loadDismissed(),
      contains('list:monde-100-livres'),
    );
  });
}
