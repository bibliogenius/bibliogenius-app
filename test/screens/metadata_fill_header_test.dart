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

/// The completeness header carries four things at once: the library stat, the
/// lot selector, the start button and the filter bar. They read each other's
/// state, which is exactly where a page drifts: a control rendered twice, or a
/// number that keeps announcing the library while a filter is applied. None of
/// that shows up in a provider test - only a pumped screen sees it.

class _FakeFfiService extends FfiService {
  _FakeFfiService() : super.forTest();

  @override
  Future<frb.FrbCompletenessStats> metadataFillStats() async =>
      const frb.FrbCompletenessStats(
        ownedTotal: 100,
        complete: 60,
        incomplete: 40,
        noIsbn: 3,
        emptyFields: 52,
        gaps: [
          frb.FrbFieldGap(field: 'summary', missing: 30),
          frb.FrbFieldGap(field: 'publisher', missing: 22),
        ],
      );

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
  }) async => const [
    frb.FrbIncompleteBookDetail(
      id: 'b1',
      title: 'La Peste',
      isbn: '9782070360420',
      coverUrl: null,
      missing: ['summary'],
    ),
  ];

  @override
  Future<int> metadataFillProcessable({String? missingField}) async =>
      missingField == 'summary' ? 27 : 37;

  @override
  Future<int> metadataFillCoversSourcesHaveNot() async => 180;
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
  late MetadataFillProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    provider = MetadataFillProvider(ffi: _FakeFfiService());
    const strings = {
      'completeness_title': 'Complete my library',
      'completeness_card_title': 'Completeness',
      'completeness_complete': 'complete',
      'completeness_empty_fields': '{n} empty fields',
      'completeness_empty_fields_field': '{n} books without {field}',
      'completeness_batch_label': 'Per batch of:',
      'completeness_batch_all': 'All',
      'completeness_start_n': 'Complete {n} books',
      'completeness_start_n_filtered': 'Complete {n} books (filter: {field})',
      'completeness_scope_hint': 'Only the books in this filter are processed.',
      'completeness_no_isbn_scope': 'These books have no ISBN.',
      'completeness_no_isbn_chip': 'No ISBN',
      'completeness_filter_all': 'All ({n})',
      'field_summary': 'Summary',
      'field_cover_url': 'Cover',
      'completeness_covers_unavailable':
          '{n} of these were already looked up, with no result.',
      'field_publisher': 'Publisher',
    };
    TranslationService.setPoTranslationsForTest({'en': strings, 'fr': strings});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
    provider.dispose();
  });

  testWidgets('the lot selector is offered once, not once per owner', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(theme, provider));
    await tester.pumpAndSettle();

    // The action strip offers it for every non-running state; the start button
    // used to render its own copy on top of that.
    expect(find.text('Per batch of:'), findsOneWidget);
  });

  testWidgets('a filter switches the card and the button onto that field', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(theme, provider));
    await tester.pumpAndSettle();
    expect(find.text('52 empty fields'), findsOneWidget);

    await provider.setFilter('summary');
    await tester.pumpAndSettle();

    expect(
      find.text('30 books without Summary'),
      findsOneWidget,
      reason: 'the card reports the filtered field, not the library',
    );
    expect(find.text('52 empty fields'), findsNothing);
    // 27 processable books, capped by the default lot of 20.
    expect(find.text('Complete 20 books (filter: Summary)'), findsOneWidget);
    expect(
      find.text('Only the books in this filter are processed.'),
      findsOneWidget,
    );
  });

  testWidgets('the cover filter explains why a run cannot fill them', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(theme, provider));
    await tester.pumpAndSettle();
    expect(find.textContaining('already looked up'), findsNothing);

    await provider.setFilter(MetadataFillProvider.coverField);
    await tester.pumpAndSettle();

    expect(
      find.text('180 of these were already looked up, with no result.'),
      findsOneWidget,
      reason: 'an empty cover is the sources\' answer, not a failed run',
    );
  });

  testWidgets('the no-ISBN filter replaces the start button with a notice', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(theme, provider));
    await tester.pumpAndSettle();

    await provider.setFilter(MetadataFillProvider.noIsbnFilter);
    await tester.pumpAndSettle();

    expect(find.text('These books have no ISBN.'), findsOneWidget);
    expect(
      find.byType(FilledButton),
      findsNothing,
      reason: 'no run can identify these books',
    );
  });
}
