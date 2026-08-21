import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/discovery_service.dart';
import 'package:bibliogenius/services/external_suggestion_dismissal_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/book_series_discovery_card.dart';
import 'package:bibliogenius/widgets/suggestion_tile.dart';

/// ADR-061 surface 1: "complete the series" on a book page.
///
/// The rules pinned here are the ones the ADR argues for: the card is
/// CACHE-ONLY (a book page must never fire a hub lookup), it is a single
/// card even for a book sitting in two series collections, and a dismissal
/// reveals the next missing ordinal of the SAME series.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.inputs);

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

DiscoverySeriesLookup _lookup(String collectionId, String name) {
  return DiscoverySeriesLookup(
    collectionId: collectionId,
    name: name,
    anchorIsbns: const ['9782070541270'],
    memberIsbns: const {},
    memberTitleAuthorKeys: const {},
  );
}

Map<String, dynamic> _cachedSeries(
  String sourceId,
  List<(int, String)> volumes,
) {
  return {
    'at': DateTime.now().millisecondsSinceEpoch,
    'status': 'resolved',
    'series': {
      'source': 'wikidata',
      'source_id': sourceId,
      'label': 'Series $sourceId',
      'volumes': [
        for (final (ordinal, title) in volumes)
          {
            'ordinal': ordinal,
            'title': title,
            'authors': const ['J. K. Rowling'],
            'year': 2000,
            'editions': const [],
            'other_langs_exist': false,
          },
      ],
    },
  };
}

void main() {
  late ThemeProvider theme;
  late List<Uri> hubCalls;
  late RecommendationProvider provider;

  /// Any hub call from a book page is a failure of the cache-only rule, so
  /// the client records it and answers a definitive negative.
  DiscoveryService recordingService() {
    return DiscoveryService(
      baseUrl: 'https://hub.test',
      client: MockClient((request) async {
        hubCalls.add(request.url);
        return http.Response(jsonEncode({'status': 'unknown'}), 200);
      }),
    );
  }

  Widget harness({
    required List<DiscoverySeriesLookup> lookups,
    required List<String> collectionIds,
  }) {
    provider = RecommendationProvider(
      _FakeRepository(
        DiscoveryLookupInputs(
          series: lookups,
          authors: const [],
          libraryIsbns: const {},
          libraryTitleAuthorKeys: const {},
        ),
      ),
      BookRefreshNotifier(),
      discoveryService: recordingService(),
    );

    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<RecommendationProvider>.value(
            value: provider,
          ),
        ],
        child: Scaffold(
          body: SingleChildScrollView(
            child: BookSeriesDiscoveryCard(seriesCollectionIds: collectionIds),
          ),
        ),
      ),
    );
  }

  setUp(() {
    hubCalls = [];
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'series_discovery_header': 'Complete the series',
        'suggestion_badge_external': 'To discover',
        'reason_series_missing_volume': 'Volume {ordinal} of {series}',
        'recommendation_not_interested': 'Not interested',
      },
    });
  });

  testWidgets('a warm cache offers the lowest missing volume', (tester) async {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode({
        'col-1': _cachedSeries('Q1', [(3, 'Prisoner of Azkaban'), (2, 'Chamber of Secrets')]),
      }),
    });

    await tester.pumpWidget(
      harness(
        lookups: [_lookup('col-1', 'Harry Potter')],
        collectionIds: const ['col-1'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Complete the series'), findsOneWidget);
    expect(find.text('Chamber of Secrets'), findsOneWidget);
    expect(find.text('Prisoner of Azkaban'), findsNothing);
    expect(find.text('Volume 2 of Harry Potter'), findsOneWidget);
    expect(find.text('To discover'), findsOneWidget);
    expect(
      hubCalls,
      isEmpty,
      reason: 'a book page must never fire a discovery lookup',
    );
  });

  testWidgets('a cold cache renders nothing and calls nothing', (tester) async {
    await tester.pumpWidget(
      harness(
        lookups: [_lookup('col-1', 'Harry Potter')],
        collectionIds: const ['col-1'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SuggestionTile), findsNothing);
    expect(find.text('Complete the series'), findsNothing);
    expect(hubCalls, isEmpty);
  });

  testWidgets('a book outside any series renders nothing', (tester) async {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode({
        'col-1': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
      }),
    });

    await tester.pumpWidget(
      harness(
        lookups: [_lookup('col-1', 'Harry Potter')],
        collectionIds: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SuggestionTile), findsNothing);
  });

  testWidgets('a book in two series collections still shows ONE card', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode({
        'col-1': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
        'col-2': _cachedSeries('Q2', [(5, 'Omnibus Volume')]),
      }),
    });

    await tester.pumpWidget(
      harness(
        lookups: [_lookup('col-1', 'Harry Potter'), _lookup('col-2', 'Omnibus')],
        collectionIds: const ['col-1', 'col-2'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SuggestionTile), findsOneWidget);
    expect(find.text('Chamber of Secrets'), findsOneWidget);
    expect(find.text('Omnibus Volume'), findsNothing);
  });

  testWidgets('dismissing reveals the next ordinal of the same series', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode({
        'col-1': _cachedSeries('Q1', [(2, 'Chamber of Secrets'), (3, 'Prisoner of Azkaban')]),
      }),
    });

    await tester.pumpWidget(
      harness(
        lookups: [_lookup('col-1', 'Harry Potter')],
        collectionIds: const ['col-1'],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chamber of Secrets'), findsOneWidget);

    await provider.dismissExternal('series:Q1:2');
    await tester.pumpAndSettle();

    expect(find.text('Chamber of Secrets'), findsNothing);
    expect(
      find.text('Prisoner of Azkaban'),
      findsOneWidget,
      reason: 'a dismissal promotes the next ordinal, it does not empty',
    );

    // Undo restores the original card in place.
    await provider.restoreDismissedExternal('series:Q1:2');
    await tester.pumpAndSettle();
    expect(find.text('Chamber of Secrets'), findsOneWidget);
  });

  testWidgets('every candidate dismissed leaves no card and no header', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode({
        'col-1': _cachedSeries('Q1', [(2, 'Chamber of Secrets')]),
      }),
      ExternalSuggestionDismissalService.dismissedKeysKey: ['series:Q1:2'],
    });

    await tester.pumpWidget(
      harness(
        lookups: [_lookup('col-1', 'Harry Potter')],
        collectionIds: const ['col-1'],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SuggestionTile), findsNothing);
    expect(find.text('Complete the series'), findsNothing);
  });
}
