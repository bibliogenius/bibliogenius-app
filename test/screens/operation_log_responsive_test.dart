import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/operation_log_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/operation_log_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/theme/app_design.dart';

/// The operation log packs a stats strip, a filter bar and dense rows onto one
/// page. Every one of those was laid out at a fixed size: 80px stat tiles and a
/// header row holding a timestamp, a badge, an entity type and a uuid with no
/// flex at all. On a small phone that overflows; on a desktop window it
/// stretches to the full width. Only a pumped screen at a real size sees it.

class _FakeOperationLogProvider extends ChangeNotifier
    implements OperationLogProvider {
  @override
  final List<frb.FrbOperationLogEntry> entries = [
    const frb.FrbOperationLogEntry(
      id: 1,
      // Long on purpose: the widest entity type the log actually records.
      entityType: 'peer_catalog_entries',
      entityId: '8f14e45f-ceea-467a-9b2c-0a1b2c3d4e5f',
      operation: 'UPDATE',
      payload: '{"title":"La Peste"}',
      status: 'pending',
      pinned: false,
      createdAt: '2026-09-04T14:32:05',
    ),
  ];

  @override
  final frb.FrbOperationLogStats? stats = frb.FrbOperationLogStats(
    total: BigInt.from(12345),
    today: BigInt.from(42),
    pending: BigInt.from(7),
    failed: BigInt.from(3),
  );

  @override
  final List<String> entityTypes = ['books', 'peer_catalog_entries'];

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  /// Settable so a test can reach the states that only exist once a filter is
  /// applied, such as the menu's reset entry.
  String? entityTypeFilterValue;

  @override
  String? get entityTypeFilter => entityTypeFilterValue;

  @override
  String? get operationFilter => null;

  @override
  String? get statusFilter => null;

  @override
  String? get searchQuery => null;

  @override
  int get page => 0;

  @override
  int get totalPages => 3;

  @override
  Future<void> loadAll() async {}

  @override
  Future<void> loadEntries() async {}

  @override
  Future<void> loadStats() async {}

  @override
  Future<void> loadEntityTypes() async {}

  @override
  void setEntityTypeFilter(String? value) {}

  @override
  void setOperationFilter(String? value) {}

  @override
  void setStatusFilter(String? value) {}

  @override
  void setSearchQuery(String? value) {}

  @override
  void nextPage() {}

  @override
  void previousPage() {}

  @override
  void resetFilters() {}
}

Widget _harness(ThemeProvider theme, OperationLogProvider provider) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<OperationLogProvider>.value(value: provider),
      ],
      child: const OperationLogScreen(),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size,
  ThemeProvider theme,
  OperationLogProvider provider,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness(theme, provider));
  await tester.pumpAndSettle();
}

void main() {
  late ThemeProvider theme;
  late _FakeOperationLogProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    provider = _FakeOperationLogProvider();
    const strings = {
      'admin_operation_log_title': 'Operation log',
      'admin_log_stat_total': 'Total',
      'admin_log_stat_today': 'Today',
      'admin_log_stat_pending': 'Pending',
      'admin_log_stat_errors': 'Errors',
      'admin_log_filter_entity': 'Entity type',
      'admin_log_filter_operation': 'Operation',
      'admin_log_filter_status': 'Status',
      'admin_log_page_info': 'Page %d of %d',
      'back': 'Back',
      // Deliberately not the word "All": the catalogue has to be what feeds
      // the menu, and an English literal in the code would read the same.
      'filter_all': 'CATALOGUE-ALL',
      'admin_log_clear_filters': 'Clear',
    };
    TranslationService.setPoTranslationsForTest({'en': strings, 'fr': strings});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
    provider.dispose();
  });

  testWidgets('the screen always offers a way back', (tester) async {
    await _pumpAt(tester, const Size(400, 800), theme, provider);

    // The settings tile used to `go` here, which replaces the stack: the
    // implied leading of the AppBar then had nothing to pop and rendered
    // nothing at all, stranding the page.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('a uuid is shortened on screen and dated for a screen reader', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(400, 800), theme, provider);

    // `_resolveEntityId` used to branch on `entityId == 0` on a String field,
    // so the branch never ran and the row rendered the whole 36-character uuid.
    expect(find.text('#8f14e45f…'), findsOneWidget);
    expect(
      find.text('#8f14e45f-ceea-467a-9b2c-0a1b2c3d4e5f'),
      findsNothing,
      reason: 'the full uuid never reaches the line',
    );

    // The card's accessibility label carries the timestamp, which it did not.
    expect(
      find.bySemanticsLabel(RegExp(r'^04/09/2026 14:32:05, UPDATE ')),
      findsOneWidget,
    );
  });

  testWidgets('the filter menu resets through the catalogue, not a literal', (
    tester,
  ) async {
    provider.entityTypeFilterValue = 'books';
    await _pumpAt(tester, const Size(400, 800), theme, provider);

    await tester.tap(find.text('books'));
    await tester.pumpAndSettle();

    // The reset entry only exists while a filter is active, and it used to be
    // a hardcoded English 'All' in a French interface.
    expect(find.text('CATALOGUE-ALL'), findsOneWidget);
    expect(find.text('All'), findsNothing);
  });

  testWidgets('small phone: nothing overflows and the row folds in two', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(320, 640), theme, provider);

    expect(
      tester.takeException(),
      isNull,
      reason: 'no RenderFlex overflow at the narrowest supported width',
    );
    // Folded header: the timestamp moved to its own line, under the operation.
    final entityBox = tester.getRect(find.text('peer_catalog_entries'));
    final timeBox = tester.getRect(find.text('04/09/2026 14:32:05'));
    expect(timeBox.top, greaterThan(entityBox.bottom - 1));
  });

  testWidgets('small phone: stat tiles share the width instead of scrolling', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(320, 640), theme, provider);

    // Two columns of two, filling the gutters: the old fixed 80px tiles needed
    // a horizontal scroll with no affordance to reach the error count.
    expect(
      tester.getRect(find.text('Errors')).center.dy,
      greaterThan(tester.getRect(find.text('Total')).center.dy),
      reason: 'the last tile is on a second row, on screen',
    );
    final tile = find
        .ancestor(of: find.text('Total'), matching: find.byType(Container))
        .first;
    expect(
      tester.getSize(tile).width,
      greaterThan(100),
      reason: 'a tile takes its share of the 320px width, not a fixed 80px',
    );
  });

  testWidgets('desktop window: the body keeps a readable measure', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1600, 900), theme, provider);

    expect(tester.takeException(), isNull);
    final card = tester.getSize(find.byType(Card).first);
    expect(
      card.width,
      lessThanOrEqualTo(AppDesign.maxContentWidth),
      reason: 'log rows are capped instead of stretching across 1600px',
    );

    // Wide layout: timestamp and entity type share one line again.
    final entityBox = tester.getRect(find.text('peer_catalog_entries'));
    final timeBox = tester.getRect(find.text('04/09/2026 14:32:05'));
    expect(timeBox.center.dy, closeTo(entityBox.center.dy, 4));
  });
}
