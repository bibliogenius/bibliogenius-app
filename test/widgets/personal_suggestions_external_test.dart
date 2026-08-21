import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/discovery_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/personal_suggestions_section.dart';

/// ADR-060 blend rules on the dashboard section: external cards append
/// after the locals with their source badge, at most 2 of the 5 slots,
/// externally-keyed dismissal with Undo, one card per series (lowest
/// missing ordinal first) and author-completion cards behind them.
class _FakeRepository implements RecommendationRepository {
  _FakeRepository(this.payload, this.inputs);

  final PersonalRecommendations? payload;
  final DiscoveryLookupInputs? inputs;

  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => payload;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => inputs;
}

Recommendation _local(String title) {
  return Recommendation(
    book: Book(id: 'book-$title', title: title, author: 'Albert Camus'),
    score: 1,
    reasons: const [
      RecommendationReason(type: 'same_author', value: 'Albert Camus'),
    ],
  );
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
    // Fresh timestamp: the sweep stays inside the 24h throttle, so the
    // widget test never touches the network.
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

Map<String, dynamic> _cachedAuthor(String sourceId, List<String> works) {
  return {
    'at': DateTime.now().millisecondsSinceEpoch,
    'status': 'resolved',
    'author': {
      'source': 'wikidata',
      'source_id': sourceId,
      'label': 'Albert Camus',
      'works': [
        for (final (index, title) in works.indexed)
          {
            'title': title,
            'titles': [title],
            'authors': const ['Albert Camus'],
            'year': 1947,
            'editions_count': 40 - index,
            'editions': const [],
            'other_langs_exist': false,
          },
      ],
    },
  };
}

Widget _harness({
  required ThemeProvider theme,
  required List<Recommendation> locals,
  required List<DiscoverySeriesLookup> lookups,
  List<DiscoveryAuthorLookup> authorLookups = const [],
}) {
  final provider = RecommendationProvider(
    _FakeRepository(
      PersonalRecommendations(
        recommendations: locals,
        topSubjects: const [],
        favoriteAuthors: const [],
        scoredBooksCount: 12,
      ),
      DiscoveryLookupInputs(
        series: lookups,
        authors: authorLookups,
        libraryIsbns: const {},
        libraryTitleAuthorKeys: const {},
      ),
    ),
    BookRefreshNotifier(),
  );

  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<RecommendationProvider>.value(value: provider),
      ],
      child: const Scaffold(
        body: SingleChildScrollView(child: PersonalSuggestionsSection()),
      ),
    ),
  );
}

void main() {
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'recommendations_personal': 'Suggestions for you',
        'reason_same_author': 'Same author: {value}',
        'reason_same_author_short': 'Same author',
        'reason_series_missing_volume': 'Volume {ordinal} of {series}',
        'reason_author_completion': 'Author you like: {author}',
        'suggestion_badge_external': 'To discover',
        'recommendation_not_interested': 'Not interested',
        'recommendation_dismissed': 'Suggestion hidden',
        'action_undo': 'Undo',
        'see_all_recommendations': 'See all',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Future<void> _seedCache(
    Map<String, dynamic> cache, {
    Map<String, dynamic> authors = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      DiscoveryService.cacheKey: jsonEncode(cache),
      DiscoveryService.authorCacheKey: jsonEncode(authors),
    });
  }

  testWidgets('external card renders after locals with its source badge', (
    tester,
  ) async {
    await _seedCache({
      'col-1': _cachedSeries('Q1', [(3, 'The Missing Volume')]),
    });
    await tester.pumpWidget(
      _harness(
        theme: theme,
        locals: [_local('La Peste'), _local('Le Mythe de Sisyphe')],
        lookups: [_lookup('col-1', 'My Series')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The Missing Volume'), findsOneWidget);
    expect(find.text('To discover'), findsOneWidget);
    expect(find.text('Volume 3 of My Series'), findsOneWidget);

    // The badge and reason are folded into the tile's single semantics
    // label (excludeSemantics swallows everything else, Rule A1).
    expect(
      find.bySemanticsLabel(RegExp('The Missing Volume.*To discover.*Volume 3')),
      findsOneWidget,
    );
  });

  testWidgets('at most 2 external cards, locals never fully displaced', (
    tester,
  ) async {
    await _seedCache({
      'col-1': _cachedSeries('Q1', [(2, 'Ext One')]),
      'col-2': _cachedSeries('Q2', [(5, 'Ext Two')]),
      'col-3': _cachedSeries('Q3', [(7, 'Ext Three')]),
    });
    await tester.pumpWidget(
      _harness(
        theme: theme,
        locals: [
          _local('Local A'),
          _local('Local B'),
          _local('Local C'),
          _local('Local D'),
        ],
        lookups: [
          _lookup('col-1', 'S1'),
          _lookup('col-2', 'S2'),
          _lookup('col-3', 'S3'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 5 slots: 3 locals + 2 externals; the third series waits its turn.
    expect(find.text('Local A'), findsOneWidget);
    expect(find.text('Local B'), findsOneWidget);
    expect(find.text('Local C'), findsOneWidget);
    expect(find.text('Local D'), findsNothing);
    expect(find.text('Ext One'), findsOneWidget);
    expect(find.text('Ext Two'), findsOneWidget);
    expect(find.text('Ext Three'), findsNothing);
  });

  testWidgets('external dismissal has Undo and reveals the next ordinal', (
    tester,
  ) async {
    await _seedCache({
      'col-1': _cachedSeries('Q1', [
        (2, 'Volume Two'),
        (3, 'Volume Three'),
      ]),
    });
    await tester.pumpWidget(
      _harness(
        theme: theme,
        locals: [_local('La Peste'), _local('Le Mythe de Sisyphe')],
        lookups: [_lookup('col-1', 'My Series')],
      ),
    );
    await tester.pumpAndSettle();

    // One card per series: the lowest missing ordinal.
    expect(find.text('Volume Two'), findsOneWidget);
    expect(find.text('Volume Three'), findsNothing);

    // Dismiss it: the next missing ordinal takes the slot, Undo appears.
    await tester.tap(find.byTooltip('Not interested').last);
    await tester.pumpAndSettle();
    expect(find.text('Volume Two'), findsNothing);
    expect(find.text('Volume Three'), findsOneWidget);
    expect(find.text('Suggestion hidden'), findsOneWidget);

    // Undo restores the lowest ordinal.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Volume Two'), findsOneWidget);
    expect(find.text('Volume Three'), findsNothing);
  });

  testWidgets('an author card carries its reason, badge and single label', (
    tester,
  ) async {
    await _seedCache(
      const {},
      authors: {'Albert Camus': _cachedAuthor('Q34670', ['The Plague'])},
    );
    await tester.pumpWidget(
      _harness(
        theme: theme,
        locals: [_local('La Peste'), _local('Le Mythe de Sisyphe')],
        lookups: const [],
        authorLookups: const [
          DiscoveryAuthorLookup(
            name: 'Albert Camus',
            anchorIsbns: ['9782070360024'],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The Plague'), findsOneWidget);
    expect(find.text('Author you like: Albert Camus'), findsOneWidget);
    expect(find.text('To discover'), findsOneWidget);
    // Rule A1: title, author, badge and reason are spoken once, by the
    // tile's own label (excludeSemantics swallows the rest).
    expect(
      find.bySemanticsLabel(
        RegExp('The Plague.*To discover.*Author you like: Albert Camus'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a series card takes the external slot ahead of an author', (
    tester,
  ) async {
    await _seedCache(
      {'col-1': _cachedSeries('Q1', [(3, 'The Missing Volume')])},
      authors: {
        'Albert Camus': _cachedAuthor('Q34670', ['The Plague', 'The Fall']),
      },
    );
    await tester.pumpWidget(
      _harness(
        theme: theme,
        locals: [_local('Local A'), _local('Local B'), _local('Local C')],
        lookups: [_lookup('col-1', 'My Series')],
        authorLookups: const [
          DiscoveryAuthorLookup(
            name: 'Albert Camus',
            anchorIsbns: ['9782070360024'],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Two external slots: the series card first, then one author work.
    expect(find.text('The Missing Volume'), findsOneWidget);
    expect(find.text('The Plague'), findsOneWidget);
    expect(find.text('The Fall'), findsNothing);
  });
}
