import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/widgets/borrow_request_sent_snack_bar.dart';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async =>
      const frb.FrbDirectoryConfig(
        nodeId: 'node-local',
        isListed: false,
        requiresApproval: true,
        acceptFrom: 'anyone',
        allowBorrowing: true,
      );
}

const _hint = 'Add your contact details so the lender can reach you.';

/// The confirmation of a borrow request is the moment the borrower needs to
/// be reachable. With an empty card it says so, and offers the form; it must
/// then still expire like any confirmation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ThemeProvider theme;

  setUp(() {
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'borrow_request_sent': 'Request sent successfully!',
        'request_sent_to': 'Request sent to',
        'borrow_request_sent_contact_hint': _hint,
        'add': 'Add',
        'contact_prompt_title': 'How can people reach you?',
        'hub_contact_email_label': 'Email',
        'done': 'Done',
      },
    });
  });

  Future<HubDirectoryProvider> hub({required String storedContact}) async {
    SharedPreferences.setMockInitialValues({'hub_contact_info': storedContact});
    final p = HubDirectoryProvider(ffi: _MockFfiService());
    await p.loadConfig();
    await p.loadContactInfo();
    return p;
  }

  Widget harness(
    HubDirectoryProvider hub,
    void Function(BuildContext) show, {
    bool accessibleNavigation = false,
  }) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(accessibleNavigation: accessibleNavigation),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => show(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

  testWidgets('an empty card adds the hint and an action that expires', (
    tester,
  ) async {
    final h = await hub(storedContact: '');
    await tester.pumpWidget(
      harness(
        h,
        (c) => showBorrowRequestSentSnackBar(c, lenderIsPairedPeer: true),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Request sent successfully! $_hint'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Add'), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);

    // Two steps: the dismissal timer is armed once the entrance animation has
    // finished, so the clock has to pass that point first.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('with a screen reader on, the action waits to be reached', (
    tester,
  ) async {
    // Flutter's timer only reads `persist`: an expiring bar would vanish
    // before a screen reader user can move focus to its action.
    final h = await hub(storedContact: '');
    await tester.pumpWidget(
      harness(
        h,
        (c) => showBorrowRequestSentSnackBar(c, lenderIsPairedPeer: true),
        accessibleNavigation: true,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).persist, isTrue);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SnackBarAction, 'Add'), findsOneWidget);
  });

  testWidgets('the action opens the contact card form', (tester) async {
    final h = await hub(storedContact: '');
    await tester.pumpWidget(
      harness(
        h,
        (c) => showBorrowRequestSentSnackBar(c, lenderIsPairedPeer: true),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('How can people reach you?'), findsOneWidget);
  });

  testWidgets('the lender name stays in the message', (tester) async {
    final h = await hub(storedContact: '');
    await tester.pumpWidget(
      harness(
        h,
        (c) => showBorrowRequestSentSnackBar(
          c,
          lenderName: 'Alice',
          lenderIsPairedPeer: true,
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Request sent to Alice $_hint'), findsOneWidget);
  });

  testWidgets('a filled card keeps the plain confirmation', (tester) async {
    final h = await hub(storedContact: 'Ask at the desk');
    await tester.pumpWidget(
      harness(
        h,
        (c) => showBorrowRequestSentSnackBar(c, lenderIsPairedPeer: true),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Request sent successfully!'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsNothing);
  });

  testWidgets('no hint toward a lender the card would not reach', (
    tester,
  ) async {
    // A directory library that is not a paired peer receives the card only
    // under conditions this screen cannot see: promising it would be a guess.
    final h = await hub(storedContact: '');
    await tester.pumpWidget(
      harness(
        h,
        (c) => showBorrowRequestSentSnackBar(c, lenderIsPairedPeer: false),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();

    expect(find.text('Request sent successfully!'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsNothing);
  });
}
