import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/services/curated_affinity_service.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';

/// ADR-066: the tier claims to transit NOTHING, so it must also be the one
/// suggestion source that works with the radio off.
///
/// The claim is worth pinning rather than trusting: the corpus is bundled
/// today but is on its way to a CDN, and the mosaic is one careless fallback
/// away from fetching a list's remote `cover_url`. Any of that would turn a
/// silent computation into a request, and nothing else in the suite would
/// notice.
///
/// The guard below makes every outbound connection throw, and the first test
/// proves the guard actually bites before the others lean on it.

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    throw StateError('the editorial affinity tier reached the network');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CuratedListsService.instance.clearCache();
  });

  test('the guard trips on a request, so the tests below mean something', () {
    HttpOverrides.runZoned(() {
      expect(() => HttpClient(), throwsA(isA<StateError>()));
    }, createHttpClient: (context) => _NoNetwork().createHttpClient(context));
  });

  test('the corpus loads with the radio off', () async {
    final corpus = await HttpOverrides.runZoned(
      () => CuratedListsService.instance.loadAllLists(),
      createHttpClient: (context) => _NoNetwork().createHttpClient(context),
    );

    expect(corpus, hasLength(83));
  });

  test('the whole affinity pass runs with the radio off', () async {
    // A library that overlaps a reviewed list at the ADR-066 thresholds, so
    // the pass goes all the way to a card rather than short-circuiting on
    // the first gate and proving nothing.
    final inputs = DiscoveryLookupInputs(
      series: const [],
      authors: const [],
      libraryIsbns: const {'9782070368228'},
      libraryTitleAuthorKeys: const {
        '1984|george orwell',
        'la condition humaine|andre malraux',
        'le petit prince|antoine de saint exupery',
      },
    );

    final ranked = await HttpOverrides.runZoned(() async {
      final corpus = await CuratedListsService.instance.loadAllLists();
      return const CuratedAffinityService().rank(
        lists: corpus,
        inputs: inputs,
        readerLanguages: const ['fr'],
      );
    }, createHttpClient: (context) => _NoNetwork().createHttpClient(context));

    expect(
      ranked.map((a) => a.list.id),
      contains('monde-100-livres'),
      reason:
          'the reference overlap must survive the offline pass, '
          'otherwise this test proves only that nothing ran',
    );
  });
}
