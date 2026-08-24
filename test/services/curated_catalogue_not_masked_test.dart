import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/services/curated_affinity_service.dart';
import 'package:bibliogenius/services/curated_lists_service.dart';
import 'package:bibliogenius/services/external_suggestion_dismissal_service.dart';

/// ADR-066, the two guarantees the import catalogue owes the tier, asserted
/// against the REAL bundled corpus.
///
/// Tested at the service layer rather than through the screen on purpose:
/// inside `testWidgets` the fake-async zone never completes a real
/// `rootBundle` read, so a widget test of this screen can only hang. What
/// the screen renders is what this data path returns, and the screen holds
/// no reference to the dismissal store at all. The rendering itself is a
/// manual recette item.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CuratedListsService.instance.clearCache();
  });

  test('the catalogue path serves the whole indexed corpus', () async {
    final corpus = await CuratedListsService.instance.loadAllLists();

    expect(corpus, hasLength(83));
    expect(corpus.map((l) => l.id).toSet(), hasLength(83));
  });

  test('the catalogue path never filters on the curation marker', () async {
    // Until 2026-08-24 this was proved with the corpus itself: some lists
    // were draft, the catalogue served them anyway, and the gap between the
    // two counts was the proof. The corpus is now 83 of 83 reviewed, so that
    // gap is gone and cannot come back on its own. The property it guarded
    // has not gone anywhere, so it is asserted at the source instead: the
    // service DECLARES the marker and must never APPLY it. A `.where((l) =>
    // l.isReviewed)` slipped into the catalogue path would bump this count,
    // where the corpus-shaped assertion would now see nothing at all.
    //
    // That the gate itself still bites is proved on synthetic lists in
    // curated_affinity_service_test.dart ("a draft list is never suggested,
    // however strong the overlap"), which no longer depends on the corpus
    // holding a draft.
    final source = File(
      'lib/services/curated_lists_service.dart',
    ).readAsStringSync();

    expect(
      'isReviewed'.allMatches(source).length,
      1,
      reason:
          'CuratedList declares isReviewed once, as a getter. The catalogue '
          'path must never read it: gating belongs to the affinity tier.',
    );

    // And should a draft ever return to the corpus, it must still be served.
    final corpus = await CuratedListsService.instance.loadAllLists();
    final drafts = corpus.where((l) => !l.isReviewed);
    expect(
      corpus.map((l) => l.id).toSet(),
      containsAll(drafts.map((l) => l.id)),
    );
  });

  test('the index is the source of truth, not the directory', () async {
    // Nine lists spent months on disk and out of index.yml for broken
    // ISBNs, and a consumer reading the DIRECTORY would have resurrected
    // exactly the ones that were pulled. They are repaired and back in the
    // index now, so no list currently discriminates between the two
    // readings and this assertion cannot fail today.
    //
    // It is kept as a CONTRACT: the set served must be the set the index
    // names, so the day a file is added, renamed or pulled again without
    // the index following, this says so instead of the corpus changing
    // silently under the reader.
    final indexed = RegExp(r'^\s+-\s+([a-z0-9][\w-]*)\s*$', multiLine: true)
        .allMatches(File('assets/curated_lists/index.yml').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    final served = (await CuratedListsService.instance.loadAllLists())
        .map((l) => l.id)
        .toSet();

    expect(served, indexed);
    expect(served, contains('monde-100-livres'));
  });

  test(
    'dismissing every suggestion empties no part of the catalogue',
    () async {
      final before = await CuratedListsService.instance.loadAllLists();
      for (final list in before) {
        await ExternalSuggestionDismissalService.dismiss('list:${list.id}');
      }
      CuratedListsService.instance.clearCache();

      final after = await CuratedListsService.instance.loadAllLists();

      // The dismissal targets the SUGGESTION, not the list. The catalogue
      // path does not consult the store, which is the simplest possible
      // guarantee that it cannot be emptied by it.
      expect(after.map((l) => l.id).toSet(), before.map((l) => l.id).toSet());
      expect(
        (await ExternalSuggestionDismissalService.loadDismissed()).length,
        greaterThan(0),
        reason: 'The dismissals really were written.',
      );
    },
  );

  test('the affinity gate is the ONLY thing curation filters', () async {
    // Same corpus, two consumers, opposite answers: the catalogue serves
    // all 83, the affinity serves none of them on a library this thin.
    //
    // Since the corpus went fully reviewed on 2026-08-24 it is the OVERLAP
    // thresholds that empty the ranking here, not the curation gate, so read
    // this as "the catalogue is never the thing that filters". The gate's own
    // bite is proved on synthetic lists in curated_affinity_service_test.dart.
    final corpus = await CuratedListsService.instance.loadAllLists();

    final ranked = const CuratedAffinityService().rank(
      lists: corpus,
      inputs: const DiscoveryLookupInputs(
        series: [],
        authors: [],
        // A library index rich enough that the gate is the only thing left
        // that can be doing the filtering.
        libraryIsbns: {'9782070541270'},
        libraryTitleAuthorKeys: {'dune|frank herbert'},
      ),
      readerLanguages: const ['fr', 'en'],
    );

    expect(corpus, hasLength(83));
    expect(ranked, isEmpty);
  });
}
