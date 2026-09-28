import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph, SemanticsFlag;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/add_connection_sheet.dart';

// The "add a connection" sheet separates two kinds of people that used to sit
// in one row of three cards: another BiblioGenius library (scan, invite) and a
// contact without the app, whose loans are handled by hand. It must say what
// a connection gives, give the contact the same footprint as the library
// actions, and every tap target must carry a name and a button role.

const _translations = {
  'add_connection_title': 'Add a connection',
  'add_connection_intro': 'Connect to another library to exchange loans.',
  'add_connection_section': 'A BiblioGenius library',
  'add_connection_scan': 'Scan their code',
  'add_connection_scan_hint': 'Side by side.',
  'add_connection_invite': 'Invite someone',
  'add_connection_invite_hint': 'Show your code or send your link.',
  'add_connection_contact_section': 'A contact without the app',
  'add_connection_contact_hint': 'Loans handled by hand.',
  'add_connection_contact': 'Add a contact',
};

Future<void> _pumpSheet(
  WidgetTester tester, {
  VoidCallback? onScan,
  VoidCallback? onEnterAddress,
  VoidCallback? onInvite,
}) async {
  SharedPreferences.setMockInitialValues({'languageCode': 'en'});
  final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: MaterialApp(
        home: Scaffold(
          body: AddConnectionSheet(
            onScan: onScan ?? () {},
            onEnterAddress: onEnterAddress ?? () {},
            onInvite: onInvite ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({'en': _translations});
  });

  testWidgets('explains the purpose and separates libraries from contacts', (
    tester,
  ) async {
    await _pumpSheet(tester);

    expect(find.text('Add a connection'), findsOneWidget);
    expect(
      find.text('Connect to another library to exchange loans.'),
      findsOneWidget,
    );
    expect(find.text('A BiblioGenius library'), findsOneWidget);
    expect(find.text('A contact without the app'), findsOneWidget);
    expect(find.text('Loans handled by hand.'), findsOneWidget);
    expect(find.byKey(const Key('actionScanQr')), findsOneWidget);
    expect(find.byKey(const Key('actionEnterManually')), findsOneWidget);
    expect(find.byKey(const Key('actionInvite')), findsOneWidget);
    // The old third card and the direct-share button are gone.
    expect(find.byKey(const Key('actionShowMyCode')), findsNothing);
    expect(find.byKey(const Key('actionShareInviteLink')), findsNothing);
    // Same footprint for the contact as for the library actions.
    final scan = tester.getSize(find.byKey(const Key('actionScanQr')));
    final contact = tester.getSize(
      find.byKey(const Key('actionEnterManually')),
    );
    expect(contact.width, scan.width);
    expect(contact.height, scan.height);
  });

  testWidgets('fits a short viewport without overflowing', (tester) async {
    // A phone in landscape, or the bottom sheet's capped height on desktop:
    // the content must scroll rather than overflow.
    tester.view.physicalSize = const Size(360, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pumpSheet(tester);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('actionEnterManually')), findsOneWidget);
  });

  testWidgets('hints wrap instead of being cut on a narrow, large-text phone', (
    tester,
  ) async {
    // 320 dp is the narrowest phone width; 1.5 is a common accessibility
    // text scale. Neither may truncate the hint or push it out of its tile.
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pumpSheet(tester);
    expect(tester.takeException(), isNull);

    final hint = find.text('Show your code or send your link.');
    expect(hint, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(hint);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'the hint must wrap, never be cut with an ellipsis',
    );
    final tile = tester.getRect(find.byKey(const Key('actionInvite')));
    expect(
      tile.contains(tester.getRect(hint).bottomRight),
      isTrue,
      reason: 'the wrapped hint must stay inside its tile',
    );
  });

  testWidgets('each action fires its own callback', (tester) async {
    final calls = <String>[];
    await _pumpSheet(
      tester,
      onScan: () => calls.add('scan'),
      onEnterAddress: () => calls.add('address'),
      onInvite: () => calls.add('invite'),
    );

    await tester.tap(find.byKey(const Key('actionScanQr')));
    await tester.ensureVisible(find.byKey(const Key('actionEnterManually')));
    await tester.tap(find.byKey(const Key('actionEnterManually')));
    await tester.ensureVisible(find.byKey(const Key('actionInvite')));
    await tester.tap(find.byKey(const Key('actionInvite')));
    await tester.pump();

    expect(calls, ['scan', 'address', 'invite']);
  });

  testWidgets('tap targets are named buttons and titles are headers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpSheet(tester);

    const buttons = {
      'actionScanQr': 'Scan their code',
      'actionEnterManually': 'Add a contact',
      'actionInvite': 'Invite someone',
    };
    for (final entry in buttons.entries) {
      final node = tester.getSemantics(find.byKey(Key(entry.key)));
      expect(
        node.hasFlag(SemanticsFlag.isButton),
        isTrue,
        reason: '"${entry.value}" must be announced as a button',
      );
      expect(node.label, startsWith(entry.value));
    }
    for (final title in [
      'Add a connection',
      'A BiblioGenius library',
      'A contact without the app',
    ]) {
      expect(
        tester.getSemantics(find.text(title)).hasFlag(SemanticsFlag.isHeader),
        isTrue,
        reason: '"$title" must be announced as a header',
      );
    }
    handle.dispose();
  });
}
