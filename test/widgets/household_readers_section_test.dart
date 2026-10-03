import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/household_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart'
    show FrbReader, FrbReadingImportReport;
import 'package:bibliogenius/widgets/household_readers_section.dart';

class _FakeFfi extends FfiService {
  _FakeFfi() : super.forTest();

  final List<FrbReader> readers = [];
  String? currentId;
  String? importedJson;
  Object? importFailure;

  @override
  Future<FrbReadingImportReport> importHouseholdReadings(String json) async {
    if (importFailure != null) throw importFailure!;
    importedJson = json;
    return const FrbReadingImportReport(
      matched: 2,
      created: 1,
      ambiguous: 1,
      ambiguousTitles: ['Twice on the shelf'],
      skipped: 0,
    );
  }

  @override
  Future<List<FrbReader>> listHouseholdReaders() async => List.of(readers);

  @override
  Future<FrbReader?> getCurrentHouseholdReader() async {
    for (final r in readers) {
      if (r.id == currentId) return r;
    }
    return null;
  }

  @override
  Future<void> setCurrentHouseholdReader(String readerId) async {
    currentId = readerId;
  }

  @override
  Future<void> clearCurrentHouseholdReader() async {
    currentId = null;
  }

  @override
  Future<void> renameHouseholdReader(String readerId, String name) async {
    final i = readers.indexWhere((r) => r.id == readerId);
    readers[i] = FrbReader(id: readerId, name: name);
  }

  @override
  Future<void> deleteHouseholdReader(String readerId) async {
    readers.removeWhere((r) => r.id == readerId);
    if (currentId == readerId) currentId = null;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'household_title': 'Readers',
        'household_subtitle': 'A reader is a person.',
        'household_note': 'One reader per person.',
        'household_update_note': 'Update every device.',
        'household_create_me': 'Create my reader',
        'household_add_reader': 'Add a reader',
        'household_reads_here': 'Reads here',
        'household_pick_prompt': 'Tap a name.',
        'household_leave_reader': 'Back to the shared view',
        'household_rename_title': 'Rename the reader',
        'household_name': 'First name',
        'household_error': 'Failed',
        'household_delete_title': 'Delete {name}?',
        'household_delete_body': 'Their readings will be erased.',
        'household_import_button': 'Import my readings',
        'household_import_title': 'Import my readings',
        'household_import_summary': '{matched} matched, {created} added.',
        'household_import_ambiguous': '{count} ambiguous:',
        'household_import_skipped': '{count} skipped.',
        'household_import_error': 'Import failed: {detail}',
        'close': 'Close',
        'delete': 'Delete',
        'rename': 'Rename',
        'save': 'Save',
        'cancel': 'Cancel',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Future<(HouseholdProvider, BookRefreshNotifier)> pump(
    WidgetTester tester,
    _FakeFfi ffi, {
    Future<String?> Function()? pickExport,
  }) async {
    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    final household = HouseholdProvider(ffi: ffi);
    final refresh = BookRefreshNotifier();
    await household.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<HouseholdProvider>.value(value: household),
          ChangeNotifierProvider<BookRefreshNotifier>.value(value: refresh),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HouseholdReadersSection(pickExport: pickExport),
            ),
          ),
        ),
      ),
    );
    return (household, refresh);
  }

  testWidgets('with no reader the section only offers to create one', (
    tester,
  ) async {
    await pump(tester, _FakeFfi());
    expect(find.text('A reader is a person.'), findsOneWidget);
    expect(find.text('One reader per person.'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Create my reader'),
      findsOneWidget,
    );
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('Update every device.'), findsNothing);
    expect(find.text('Back to the shared view'), findsNothing);
  });

  testWidgets('a chosen reader can rename, switch and step back', (
    tester,
  ) async {
    final ffi = _FakeFfi()
      ..readers.addAll(const [
        FrbReader(id: 'r1', name: 'Alice'),
        FrbReader(id: 'r2', name: 'Bruno'),
      ])
      ..currentId = 'r1';
    final (household, refresh) = await pump(tester, ffi);
    var refreshed = 0;
    refresh.addListener(() => refreshed++);

    expect(find.text('Update every device.'), findsOneWidget);
    expect(find.text('Reads here'), findsOneWidget);
    expect(find.text('Tap a name.'), findsNothing);
    expect(find.text('Add a reader'), findsOneWidget);

    // Rename Alice through the dialog.
    await tester.tap(find.byTooltip('Rename').first);
    await tester.pumpAndSettle();
    expect(find.text('Rename the reader'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Alicia');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Alicia'), findsOneWidget);
    expect(refreshed, 1);

    // Switch to Bruno: every list must refresh.
    await tester.tap(find.text('Bruno'));
    await tester.pumpAndSettle();
    expect(household.currentReader?.name, 'Bruno');
    expect(refreshed, 2);

    // Back to the shared view: the readers stay, nothing is chosen.
    await tester.tap(find.text('Back to the shared view'));
    await tester.pumpAndSettle();
    expect(household.currentReaderId, isNull);
    expect(find.text('Back to the shared view'), findsNothing);
    expect(find.text('Reads here'), findsNothing);
    expect(find.text('Bruno'), findsOneWidget);
    // Nobody reads here: the rows carry no radio, so the list says what a
    // tap does.
    expect(find.text('Tap a name.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('readers show as people, the one reading here is marked', (
    tester,
  ) async {
    final ffi = _FakeFfi()
      ..readers.addAll(const [
        FrbReader(id: 'r1', name: 'alice'),
        FrbReader(id: 'r2', name: 'Bruno'),
      ])
      ..currentId = 'r1';
    final handle = tester.ensureSemantics();
    await pump(tester, ffi);

    // The subtitle stays, the creation note gives way to the list.
    expect(find.text('A reader is a person.'), findsOneWidget);
    expect(find.text('One reader per person.'), findsNothing);
    // Initials, not device glyphs.
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    // One marker, with its own icon, on the reader of this device.
    expect(find.text('Reads here'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book), findsOneWidget);

    // Assistive tech gets a single-choice list: name, marker, checked state.
    expect(
      tester.getSemantics(find.bySemanticsLabel('alice, Reads here')),
      containsSemantics(
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Bruno')),
      containsSemantics(
        hasCheckedState: true,
        isChecked: false,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('importing readings needs a reader and reports what it did', (
    tester,
  ) async {
    final ffi = _FakeFfi()..readers.add(const FrbReader(id: 'r1', name: 'Alice'));
    final (household, refresh) = await pump(
      tester,
      ffi,
      pickExport: () async => '{"books": []}',
    );
    var refreshed = 0;
    refresh.addListener(() => refreshed++);

    // The readings would have nobody to belong to.
    expect(find.text('Import my readings'), findsNothing);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    refreshed = 0;
    await tester.tap(find.text('Import my readings'));
    await tester.pumpAndSettle();

    expect(ffi.importedJson, '{"books": []}');
    expect(find.text('2 matched, 1 added.'), findsOneWidget);
    expect(find.text('1 ambiguous:'), findsOneWidget);
    expect(find.textContaining('Twice on the shelf'), findsOneWidget);
    expect(find.textContaining('skipped'), findsNothing);
    expect(refreshed, 1);
    expect(household.busy, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    // A refused file says why, and refreshes nothing.
    ffi.importFailure = 'Unreadable catalogue export';
    await tester.tap(find.text('Import my readings'));
    await tester.pumpAndSettle();
    expect(
      find.text('Import failed: Unreadable catalogue export'),
      findsOneWidget,
    );
    expect(refreshed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cancelled file choice imports nothing', (tester) async {
    final ffi = _FakeFfi()
      ..readers.add(const FrbReader(id: 'r1', name: 'Alice'))
      ..currentId = 'r1';
    await pump(tester, ffi, pickExport: () async => null);

    await tester.tap(find.text('Import my readings'));
    await tester.pumpAndSettle();
    expect(ffi.importedJson, isNull);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('deleting a reader asks first and removes them', (tester) async {
    final ffi = _FakeFfi()
      ..readers.addAll(const [
        FrbReader(id: 'r1', name: 'Alice'),
        FrbReader(id: 'r2', name: 'Bruno'),
      ])
      ..currentId = 'r1';
    final (household, _) = await pump(tester, ffi);

    // Cancelling changes nothing.
    await tester.tap(find.byTooltip('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete Bruno?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(household.readers, hasLength(2));

    await tester.tap(find.byTooltip('Delete').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(household.readers.single.name, 'Alice');
    expect(find.text('Bruno'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
