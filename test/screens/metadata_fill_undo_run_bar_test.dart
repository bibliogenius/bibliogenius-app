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

/// Undoing a whole completion is the promise the reimport makes (ADR-071 D1),
/// and its only durable home is this tab: the reimport's own summary sheet
/// closes, and undoing five hundred books one by one is not an option.
///
/// A RenderFlex overflow throws in a widget test, so laying the bar out at a
/// narrow width IS the assertion: a Row that keeps the sentence and the button
/// on one line squeezes the label until it reads one letter per line.
class _FakeFfiService extends FfiService {
  _FakeFfiService() : super.forTest();

  String? undoneBatch;

  @override
  Future<frb.FrbCompletenessStats> metadataFillStats() async =>
      const frb.FrbCompletenessStats(
        ownedTotal: 100,
        complete: 60,
        incomplete: 40,
        noIsbn: 3,
        emptyFields: 52,
        gaps: [frb.FrbFieldGap(field: 'summary', missing: 30)],
      );

  @override
  Future<frb.FrbFillProgress?> metadataFillProgress() async => null;

  @override
  Future<List<frb.FrbFilledBook>> metadataFillRecent({int limit = 50}) async =>
      const [
        frb.FrbFilledBook(
          bookId: 'b1',
          title: 'Martin Eden',
          coverUrl: null,
          fields: [
            frb.FrbFilledField(
              journalId: 1,
              batchId: 'batch-1',
              field: 'isbn',
              value: '9782264024848',
            ),
          ],
        ),
        frb.FrbFilledBook(
          bookId: 'b2',
          title: 'Fables',
          coverUrl: null,
          fields: [
            frb.FrbFilledField(
              journalId: 2,
              batchId: 'batch-1',
              field: 'isbn',
              value: '9782253010043',
            ),
          ],
        ),
      ];

  @override
  Future<List<frb.FrbIncompleteBookDetail>> metadataFillIncomplete({
    int? limit,
    String? missingField,
    bool noIsbnOnly = false,
  }) async => const [];

  @override
  Future<int> metadataFillProcessable({String? missingField}) async => 37;

  @override
  Future<int> metadataFillCoversSourcesHaveNot() async => 0;

  @override
  Future<frb.FrbNoIsbnCluster?> importNoIsbnCluster() async => null;

  @override
  Future<int> metadataFillUndoRun(String batchId) async {
    undoneBatch = batchId;
    return 2;
  }
}

/// Providers sit ABOVE `MaterialApp`: a dialog opens in a route of its own,
/// outside anything provided under `home`, and would not find them there. In
/// the app they live at the root, so this mirrors production rather than
/// working around it.
Widget _harness(ThemeProvider theme, MetadataFillProvider provider) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<MetadataFillProvider>.value(value: provider),
      ],
      child: const MaterialApp(home: MetadataFillScreen()),
    );

void main() {
  late ThemeProvider theme;
  late MetadataFillProvider provider;
  late _FakeFfiService ffi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    ffi = _FakeFfiService();
    provider = MetadataFillProvider(ffi: ffi);
    const strings = {
      'completeness_title': 'Complete my library',
      'completeness_card_title': 'Completeness',
      'completeness_complete': 'complete',
      'completeness_empty_fields': '{n} empty fields',
      'completeness_batch_label': 'Per batch of:',
      'completeness_batch_all': 'All',
      'completeness_start_n': 'Complete {n} books',
      'completeness_tab_todo': 'To complete ({n})',
      'completeness_tab_recent': 'Recent ({n})',
      'completeness_recent_hint': 'Tap undo to clear a field.',
      // The real French labels: a short English one leaves room where the
      // shipped one does not, and this bar broke on width, not on wording.
      'completeness_undo_run_hint': 'Dernière complétion : {n} livres',
      'completeness_undo_run': 'Tout annuler',
      'completeness_undo_run_confirm': 'Undo this completion?',
      'completeness_undo_run_confirm_body': '{n} books go back.',
      'reimport_undone': '{count} fields restored',
      'field_isbn': 'ISBN',
      'action_undo': 'Undo',
      'cancel': 'Cancel',
    };
    TranslationService.setPoTranslationsForTest({'en': strings, 'fr': strings});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
    provider.dispose();
  });

  Future<void> openRecentTab(WidgetTester tester) async {
    await tester.pumpWidget(_harness(theme, provider));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent (2)'));
    await tester.pumpAndSettle();
  }

  testWidgets('the last completion can be undone as a whole', (tester) async {
    await openRecentTab(tester);

    expect(find.text('Dernière complétion : 2 livres'), findsOneWidget);
    await tester.tap(find.text('Tout annuler'));
    await tester.pumpAndSettle();

    // Nothing is reverted until the reader confirms: this button is permanent
    // now, and one stray tap would undo a whole campaign.
    expect(find.text('Undo this completion?'), findsOneWidget);
    expect(ffi.undoneBatch, isNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Tout annuler'));
    await tester.pumpAndSettle();

    expect(ffi.undoneBatch, 'batch-1');
  });

  testWidgets('the button keeps its shape on a narrow window', (tester) async {
    // The failure this pins does not throw: squeezed between a sentence and
    // the window edge, the button keeps rendering, one letter per line, and
    // grows into a tall column of characters. So the assertion is its height.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openRecentTab(tester);

    expect(find.text('Dernière complétion : 2 livres'), findsOneWidget);
    // The label itself: squeezed, it wraps one letter per line and its box
    // becomes a tall column. `TextButton.icon` does not render a TextButton
    // widget to match on, so the text is what gets measured.
    final label = tester.getSize(find.text('Tout annuler'));
    expect(
      label.height,
      lessThan(60),
      reason: 'a label wrapping one letter per line becomes a column',
    );
  });
}
