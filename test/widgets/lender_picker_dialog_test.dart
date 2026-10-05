import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/contact.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/library_portals.dart';
import 'package:bibliogenius/widgets/lender_picker_dialog.dart';

/// Manual borrow lender picker: connected libraries, contacts, a new contact
/// or a typed place, then an optional due date.

const _catalogues = {
  'en': {
    'select_lender': 'Who did you borrow it from?',
    'lender_section_libraries': 'Connected libraries',
    'contacts': 'Contacts',
    'contact_has_book': 'Has this book',
    'lender_new_contact': 'New contact',
    'lender_other_place': 'A library or another place',
    'lender_place_name_label': 'Place name',
    'lender_place_name_hint': 'Library, little free library…',
    'lender_place_name_required': 'Enter a name',
    'borrow_due_date_title': 'Return date (optional)',
    'borrow_due_date_skip': 'Skip',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
  },
};

const _portal = LocalLibraryPortal(
  name: 'Médiathèque du centre',
  urlTemplate: 'https://example.org/search?q={ean13}',
);

Contact _contact(String name, {bool? hasBook}) =>
    Contact(type: 'borrower', name: name, hasBook: hasBook);

/// Pumps a button that runs [action] and records its result in [results].
Future<void> _pumpLauncher(
  WidgetTester tester,
  Future<String?> Function(BuildContext) action,
  List<String?> results,
) async {
  SharedPreferences.setMockInitialValues({'languageCode': 'en'});
  final provider = ThemeProvider()..setLocaleSync(const Locale('en'));
  // Providers above MaterialApp: dialogs push on the root navigator.
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(await action(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _pumpPicker(
  WidgetTester tester,
  List<String?> results, {
  List<LocalLibraryPortal> portals = const [],
  List<Contact> contacts = const [],
  Future<Contact?> Function()? createContact,
}) => _pumpLauncher(
  tester,
  (context) => pickLenderName(
    context,
    portals: portals,
    contacts: contacts,
    createContact: createContact ?? () async => null,
  ),
  results,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest(_catalogues);
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('with nothing to list, the picker still offers both actions', (
    tester,
  ) async {
    final results = <String?>[];
    await _pumpPicker(tester, results);

    expect(find.text('Who did you borrow it from?'), findsOneWidget);
    expect(find.text('New contact'), findsOneWidget);
    expect(find.text('A library or another place'), findsOneWidget);
    expect(find.text('Connected libraries'), findsNothing);
    expect(find.text('Contacts'), findsNothing);
  });

  testWidgets('a connected library is picked by its name', (tester) async {
    final results = <String?>[];
    await _pumpPicker(tester, results, portals: [_portal]);

    await tester.tap(find.text('Médiathèque du centre'));
    await tester.pumpAndSettle();

    expect(results, ['Médiathèque du centre']);
  });

  testWidgets('libraries come first, then contacts, then the actions', (
    tester,
  ) async {
    final results = <String?>[];
    await _pumpPicker(
      tester,
      results,
      portals: [_portal],
      contacts: [_contact('Zoe', hasBook: true), _contact('Alice')],
    );

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Médiathèque du centre'), lessThan(top('Zoe')));
    // Owning the book outranks alphabetical order.
    expect(top('Zoe'), lessThan(top('Alice')));
    expect(top('Alice'), lessThan(top('New contact')));
    expect(top('New contact'), lessThan(top('A library or another place')));
    expect(find.text('Has this book'), findsOneWidget);
  });

  testWidgets('section titles are announced as headers', (tester) async {
    final handle = tester.ensureSemantics();
    final results = <String?>[];
    await _pumpPicker(
      tester,
      results,
      portals: [_portal],
      contacts: [_contact('Alice')],
    );

    for (final label in ['Connected libraries', 'Contacts']) {
      expect(
        tester.getSemantics(find.text(label)).flagsCollection.isHeader,
        isTrue,
        reason: label,
      );
    }
    handle.dispose();
  });

  testWidgets('a typed place is refused when blank and trimmed otherwise', (
    tester,
  ) async {
    final results = <String?>[];
    await _pumpPicker(tester, results);

    await tester.tap(find.text('A library or another place'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(results, isEmpty);

    await tester.enterText(find.byType(TextFormField), '  Boîte à livres  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(results, ['Boîte à livres']);
  });

  testWidgets('cancelling the place field brings the picker back', (
    tester,
  ) async {
    final results = <String?>[];
    await _pumpPicker(tester, results);

    await tester.tap(find.text('A library or another place'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Who did you borrow it from?'), findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('a new contact becomes the lender, a cancelled one does not', (
    tester,
  ) async {
    final results = <String?>[];
    final created = <Contact?>[null, _contact('Martin')];
    var calls = 0;
    await _pumpPicker(
      tester,
      results,
      createContact: () async => created[calls++],
    );

    await tester.tap(find.text('New contact'));
    await tester.pumpAndSettle();
    // Cancelled creation: back on the picker, nothing recorded.
    expect(find.text('Who did you borrow it from?'), findsOneWidget);
    expect(results, isEmpty);

    await tester.tap(find.text('New contact'));
    await tester.pumpAndSettle();
    expect(results, ['Martin']);
  });

  testWidgets('the due date can be skipped or picked', (tester) async {
    final results = <String?>[];
    await _pumpLauncher(tester, pickBorrowDueDate, results);

    expect(find.text('Return date (optional)'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(results, [null]);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    final expected = DateUtils.dateOnly(
      DateTime.now(),
    ).add(const Duration(days: 21)).toIso8601String().split('T')[0];
    expect(results, [null, expected]);
  });
}
