import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/metadata_fill_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/metadata_fill_screen.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;

/// Books with no author are the one gap this screen cannot close, and the one
/// every other number on it hides: an author is a `book_authors` relation, so
/// it is not a gap-fill field, and a book without one is counted `complete`.
/// The line exists to say so. These tests pin that it appears on the number the
/// backend gives and disappears when there is nothing to report, because a
/// counter that silently reads zero would restore the exact blind spot it was
/// added to close.

class _FakeFfiService extends FfiService {
  _FakeFfiService(this.authorless) : super.forTest();

  /// What the backend reports for `count_books_without_author`.
  final int authorless;

  @override
  Future<frb.FrbCompletenessStats> metadataFillStats() async =>
      const frb.FrbCompletenessStats(
        ownedTotal: 461,
        // The library the counter was written for: every one of these is
        // reported complete while 180 of them carry no author at all.
        complete: 461,
        incomplete: 0,
        noIsbn: 0,
        emptyFields: 0,
        gaps: [],
      );

  @override
  Future<int> metadataFillBooksWithoutAuthor() async => authorless;

  @override
  Future<frb.FrbFillProgress?> metadataFillProgress() async => null;

  @override
  Future<List<frb.FrbFilledBook>> metadataFillRecent({int limit = 50}) async =>
      const [];

  @override
  Future<List<frb.FrbIncompleteBookDetail>> metadataFillIncomplete({
    int? limit,
    String? missingField,
    bool noIsbnOnly = false,
  }) async => const [];

  @override
  Future<int> metadataFillProcessable({String? missingField}) async => 0;

  @override
  Future<int> metadataFillCoversSourcesHaveNot() async => 0;
}

Widget _harness(ThemeProvider theme, MetadataFillProvider provider) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<MetadataFillProvider>.value(value: provider),
      ],
      child: const MetadataFillScreen(),
    ),
  );
}

void main() {
  late ThemeProvider theme;
  MetadataFillProvider? provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    const strings = {
      'completeness_title': 'Complete my library',
      'completeness_card_title': 'Completeness',
      'completeness_complete': 'complete',
      'completeness_empty_fields': '{n} empty fields',
      'completeness_batch_label': 'Per batch of:',
      'completeness_batch_all': 'All',
      'completeness_start_n': 'Complete {n} books',
      'completeness_filter_all': 'All ({n})',
      'completeness_books_without_author': '{n} books have no author at all.',
    };
    TranslationService.setPoTranslationsForTest({'en': strings, 'fr': strings});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
    provider?.dispose();
    provider = null;
  });

  testWidgets('authorless books are reported even when the library reads complete', (
    tester,
  ) async {
    final p = MetadataFillProvider(ffi: _FakeFfiService(180));
    provider = p;

    await tester.pumpWidget(_harness(theme, p));
    await p.loadAll();
    await tester.pumpAndSettle();

    expect(
      find.text('180 books have no author at all.'),
      findsOneWidget,
      reason:
          'the stats say complete: 461 / incomplete: 0, so this line is the '
          'only thing on the screen that reports the 180',
    );
  });

  testWidgets('a filter hides it, because the count is library-wide', (
    tester,
  ) async {
    final p = MetadataFillProvider(ffi: _FakeFfiService(180));
    provider = p;

    await tester.pumpWidget(_harness(theme, p));
    await p.loadAll();
    await tester.pumpAndSettle();
    expect(find.textContaining('no author at all'), findsOneWidget);

    // Every other number in this header narrows to the filter. This one counts
    // the whole library, so leaving it up would put two populations in one
    // block, and it would eat the above-the-fold budget on every filter.
    await p.setFilter('summary');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no author at all'),
      findsNothing,
      reason: 'the overview strip has no meaning under a field filter',
    );
  });

  testWidgets('a library with every author linked gets no line', (
    tester,
  ) async {
    final p = MetadataFillProvider(ffi: _FakeFfiService(0));
    provider = p;

    await tester.pumpWidget(_harness(theme, p));
    await p.loadAll();
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no author at all'),
      findsNothing,
      reason: 'nothing to report, so nothing is shown',
    );
  });
}
