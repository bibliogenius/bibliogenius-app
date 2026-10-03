import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/household_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' show FrbReader;
import 'package:bibliogenius/widgets/household_readers_section.dart';

class _FakeFfi extends FfiService {
  _FakeFfi() : super.forTest();

  final List<FrbReader> readers = [];
  String? currentId;

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
        'household_note': 'Shared library.',
        'household_update_note': 'Update every device.',
        'household_create_me': 'Create my reader',
        'household_add_reader': 'Add a reader',
        'household_reads_here': 'Reads on this device',
        'household_leave_reader': 'Back to the shared view',
        'household_rename_title': 'Rename the reader',
        'household_name': 'First name',
        'household_error': 'Failed',
        'household_delete_title': 'Delete {name}?',
        'household_delete_body': 'Their readings will be erased.',
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
    _FakeFfi ffi,
  ) async {
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
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: HouseholdReadersSection()),
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
    expect(find.text('Create my reader'), findsOneWidget);
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
    expect(find.text('Reads on this device'), findsOneWidget);
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
    expect(find.text('Reads on this device'), findsNothing);
    expect(find.text('Bruno'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
