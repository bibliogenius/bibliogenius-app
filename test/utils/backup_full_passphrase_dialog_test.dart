import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/backup_actions.dart';

/// The passphrase dialog of the full backup owns a TextEditingController that
/// must outlive the dialog's closing transition: `showDialog` resolves on pop,
/// while the TextField is still on screen for the whole fade-out. Disposing
/// the controller right away raised "A TextEditingController was used after
/// being disposed" on the next rebuild (keyboard closing), which cascaded into
/// the framework's `_dependents.isEmpty` assertion and a full red screen.
class _FakeFfi extends FfiService {
  _FakeFfi() : super.forTest();

  @override
  Future<String> accountCheckPassphrase(String passphrase) async =>
      '{"score":4,"length":${passphrase.length},"acceptable":true,'
      '"warning":"","suggestions":[]}';
}

void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({
      'en': {'backup_export_button': 'Export', 'cancel': 'Cancel'},
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('confirming the passphrase survives the closing transition', (
    tester,
  ) async {
    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    final provider = AccountSyncProvider(ffi: _FakeFfi());
    late BuildContext screenContext;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AccountSyncProvider>.value(value: provider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                screenContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );

    final result = BackupActions.showFullBackupPassphraseDialog(screenContext);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'long-enough-secret');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    // Runs the pop transition frame by frame: this is where the disposed
    // controller used to be rebuilt.
    await tester.pumpAndSettle();

    expect(await result, isNotNull);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
