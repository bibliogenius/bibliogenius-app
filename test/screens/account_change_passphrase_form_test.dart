import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/account_change_passphrase_screen.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';

/// Guards the two gates of the passphrase-change form (ADR-042 section 12 and
/// 16.2): the section 12 strength floor (the meter's `acceptable`) AND a
/// matching confirmation, since a typo here locks the passphrase path for every
/// future device. Also pins that the old passphrase is never asked for: the
/// form carries exactly two fields, both for the new one.
const Map<String, String> _enKeys = {
  'account_sync_change_passphrase_intro': 'Choose a new passphrase.',
  'account_sync_new_passphrase_label': 'New passphrase',
  'account_sync_passphrase_hint': 'At least 12 characters.',
  'account_sync_change_passphrase_confirm_label': 'Confirm the new passphrase',
  'account_sync_change_passphrase_mismatch': 'The two passphrases do not match.',
  'account_sync_change_passphrase_note': 'Does not sign out other devices.',
  'account_sync_change_passphrase_submit': 'Save the new passphrase',
  'account_sync_change_passphrase_done': 'Passphrase changed.',
  'account_sync_change_passphrase_failed': 'Could not change the passphrase.',
  'account_sync_weak_passphrase': 'This passphrase is too weak.',
  'account_sync_show_passphrase': 'Show passphrase',
  'account_sync_hide_passphrase': 'Hide passphrase',
  'account_sync_strength_label': 'Strength',
  'account_sync_strength_0': 'Very weak',
  'account_sync_strength_4': 'Strong',
};

const String _strong = 'purple giraffe reading seven lanterns';

class _FakeFfi extends FfiService {
  _FakeFfi() : super.forTest();

  bool acceptable = true;
  Object? changeError;
  final List<String> changed = [];

  @override
  Future<String> accountCheckPassphrase(String passphrase) async =>
      acceptable
          ? '{"score":4,"length":${passphrase.length},"acceptable":true,'
                '"warning":"","suggestions":[]}'
          : '{"score":1,"length":${passphrase.length},"acceptable":false,'
                '"warning":"","suggestions":[]}';

  @override
  Future<String> accountChangePassphrase(String newPassphrase) async {
    changed.add(newPassphrase);
    if (changeError != null) throw changeError!;
    return '{"rotated":true}';
  }
}

void main() {
  late _FakeFfi ffi;
  late AccountSyncProvider provider;
  late int doneCalls;

  setUp(() {
    TranslationService.setPoTranslationsForTest({'en': _enKeys});
    ffi = _FakeFfi();
    provider = AccountSyncProvider(ffi: ffi);
    doneCalls = 0;
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Future<void> pumpForm(WidgetTester tester) async {
    // The locale must be set before the first frame (see the meter test).
    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AccountSyncProvider>.value(value: provider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountChangePassphraseForm(onDone: () => doneCalls++),
            ),
          ),
        ),
      ),
    );
  }

  Finder submitButton() =>
      find.widgetWithText(FilledButton, 'Save the new passphrase');

  bool submitEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(submitButton()).onPressed != null;

  Future<void> typeNew(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField).at(0), value);
    // Let the 300 ms strength debounce fire.
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> typeConfirm(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField).at(1), value);
    await tester.pump();
  }

  testWidgets('the form asks only for the new passphrase, twice', (
    tester,
  ) async {
    await pumpForm(tester);

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('New passphrase'), findsOneWidget);
    expect(find.text('Confirm the new passphrase'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('submit needs a strong passphrase AND a matching confirmation', (
    tester,
  ) async {
    await pumpForm(tester);

    await typeNew(tester, _strong);
    expect(submitEnabled(tester), isFalse, reason: 'confirmation still empty');

    await typeConfirm(tester, 'purple giraffe');
    expect(find.text('The two passphrases do not match.'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);

    await typeConfirm(tester, _strong);
    expect(find.text('The two passphrases do not match.'), findsNothing);
    expect(submitEnabled(tester), isTrue);

    await tester.tap(submitButton());
    await tester.pumpAndSettle();

    expect(ffi.changed, [_strong]);
    expect(doneCalls, 1);
    expect(find.text('Passphrase changed.'), findsOneWidget);
  });

  testWidgets('a weak passphrase never enables submit, even when confirmed', (
    tester,
  ) async {
    ffi.acceptable = false;
    await pumpForm(tester);

    await typeNew(tester, 'aaaaaaaaaaaa');
    await typeConfirm(tester, 'aaaaaaaaaaaa');

    expect(submitEnabled(tester), isFalse);
    expect(ffi.changed, isEmpty);
  });

  testWidgets('the backend weak-passphrase backstop is shown, not swallowed', (
    tester,
  ) async {
    ffi.changeError = Exception('E_WEAK_PASSPHRASE: below the floor');
    await pumpForm(tester);

    await typeNew(tester, _strong);
    await typeConfirm(tester, _strong);
    await tester.tap(submitButton());
    await tester.pumpAndSettle();

    expect(find.text('This passphrase is too weak.'), findsOneWidget);
    expect(doneCalls, 0);
  });

  testWidgets('a hub failure is reported and the form stays usable', (
    tester,
  ) async {
    ffi.changeError = Exception('Hub error: 503');
    await pumpForm(tester);

    await typeNew(tester, _strong);
    await typeConfirm(tester, _strong);
    await tester.tap(submitButton());
    await tester.pumpAndSettle();

    expect(find.text('Could not change the passphrase.'), findsOneWidget);
    expect(doneCalls, 0);
    expect(submitEnabled(tester), isTrue);
  });
}
