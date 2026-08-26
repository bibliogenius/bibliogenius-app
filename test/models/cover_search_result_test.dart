import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/cover_candidate.dart';

/// The cover search used to report every empty outcome with the same words,
/// "no cover found", whether the sources had answered or not. A user whose
/// network was flapping was told a cover does not exist, and stopped looking.
/// These tests pin the four outcomes apart.
void main() {
  CoverSourceStatus status(String source, String state, [String? detail]) =>
      CoverSourceStatus(source: source, state: state, detail: detail);

  const candidate = CoverCandidate(
    url: 'https://inventaire.io/img/entities/abc',
    source: 'Inventaire',
  );

  group('verdict', () {
    test('candidates make it a find, whatever the sources said', () {
      final result = CoverSearchResult(
        candidates: const [candidate],
        sources: [status('Google Books', 'unavailable', 'HTTP 503')],
      );

      expect(result.verdict, CoverSearchVerdict.found);
    });

    test('every source answering nothing is a real absence', () {
      final result = CoverSearchResult(
        candidates: const [],
        sources: [status('Inventaire', 'empty'), status('BNF', 'empty')],
      );

      expect(result.verdict, CoverSearchVerdict.none);
    });

    test('one silent source makes the absence unknowable', () {
      final result = CoverSearchResult(
        candidates: const [],
        sources: [
          status('Inventaire', 'empty'),
          status('Google Books', 'unavailable', 'HTTP 503'),
        ],
      );

      expect(result.verdict, CoverSearchVerdict.incomplete);
      expect(result.unavailableSources.single.source, 'Google Books');
    });

    test('every source silent at once reads as one outage, not four', () {
      // Four sources failing together is the device being offline, which is the
      // only thing the reader can act on; listing four names buries it.
      final result = CoverSearchResult(
        candidates: const [],
        sources: [
          status('Inventaire', 'unavailable', 'Request failed'),
          status('OpenLibrary', 'unavailable', 'Request failed'),
          status('BNF', 'unavailable', 'Request failed'),
          status('Google Books', 'unavailable', 'Request failed'),
        ],
      );

      expect(result.verdict, CoverSearchVerdict.incomplete);
      expect(result.nothingReachable, isTrue);
    });

    test('one source down among several that answered is not an outage', () {
      final result = CoverSearchResult(
        candidates: const [],
        sources: [
          status('Inventaire', 'empty'),
          status('Google Books', 'unavailable', 'quota'),
        ],
      );

      expect(result.nothingReachable, isFalse);
    });

    test('a source merely skipped does not make it an outage', () {
      final result = CoverSearchResult(
        candidates: const [],
        sources: [status('BNF', 'skipped'), status('Inventaire', 'empty')],
      );

      expect(result.nothingReachable, isFalse);
    });

    test('nothing queried at all is not an absence either', () {
      final result = CoverSearchResult(
        candidates: const [],
        sources: [status('Inventaire', 'skipped'), status('BNF', 'skipped')],
      );

      expect(result.verdict, CoverSearchVerdict.noSource);
    });

    test('a search that never ran reports no source, not no cover', () {
      expect(
        const CoverSearchResult.empty().verdict,
        CoverSearchVerdict.noSource,
      );
    });
  });

  group('merging the ISBN pass with the title pass', () {
    test('a source that failed once stays failed', () {
      final isbnPass = CoverSearchResult(
        candidates: const [],
        sources: [status('Google Books', 'unavailable', 'quota')],
      );
      final titlePass = CoverSearchResult(
        candidates: const [],
        sources: [status('Google Books', 'empty')],
      );

      final merged = isbnPass.mergedWith(titlePass);

      expect(merged.sources.single.state, 'unavailable');
      expect(merged.sources.single.isQuota, isTrue);
      expect(merged.verdict, CoverSearchVerdict.incomplete);
    });

    test('a source is reported once, not once per pass', () {
      final isbnPass = CoverSearchResult(
        candidates: const [],
        sources: [status('Inventaire', 'empty'), status('BNF', 'empty')],
      );
      final titlePass = CoverSearchResult(
        candidates: const [candidate],
        sources: [status('Inventaire', 'found')],
      );

      final merged = isbnPass.mergedWith(titlePass);

      expect(merged.sources.map((s) => s.source), ['Inventaire', 'BNF']);
      expect(
        merged.sources.firstWhere((s) => s.source == 'Inventaire').state,
        'found',
      );
    });

    test('the same cover found twice is offered once', () {
      final isbnPass = CoverSearchResult(
        candidates: const [candidate],
        sources: [status('Inventaire', 'found')],
      );
      final titlePass = CoverSearchResult(
        candidates: const [candidate],
        sources: [status('Inventaire', 'found')],
      );

      expect(isbnPass.mergedWith(titlePass).candidates, hasLength(1));
    });
  });
}
