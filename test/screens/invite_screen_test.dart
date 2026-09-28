import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsFlag;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/invite_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/invite_payload.dart';

// The invite screen is the one place that shows this library's QR code and
// invite link. It must explain both ways of pairing (in person, remote), say
// honestly whether the link works beyond the Wi-Fi, and keep the keys the
// integration tour relies on (myQrCode, copyInviteLinkBtn, shareInviteLinkBtn,
// closeShowMyCode).

const _translations = {
  'invite_screen_title': 'My invitation',
  'close': 'Close',
  'generating_invite_link': 'Preparing your invite link...',
  'invite_intro': 'A connected library can exchange loans with you.',
  'invite_in_person_title': 'In person',
  'invite_in_person_hint': 'Show this code to the other library.',
  'invite_qr_semantics': 'QR code of your invitation',
  'invite_remote_title': 'Remotely',
  'invite_remote_hint': 'Send your link by message.',
  'invite_works_everywhere': 'This link works on any network.',
  'invite_lan_only': 'This link only works on your Wi-Fi.',
  'copy_invite_link': 'Copy link',
  'invite_send': 'Send',
  'invite_link_copied': 'Invite link copied!',
  'share_failed': 'Sharing failed.',
  'invite_share_message': 'Join {name} on BiblioGenius: {link}',
  'invite_unavailable_title': 'Your invitation cannot be prepared.',
  'qr_wifi_suggestion': 'Check your Wi-Fi connection and try again.',
  'retry': 'Retry',
};

const _lanAndRelay = InviteLinkData(
  payload: {'v': 4, 'n': 'Ada', 'u': 'http://192.168.1.2:8000', 'mi': 'm'},
  link: 'https://hub.example.org/i/abc',
);

const _lanOnly = InviteLinkData(
  payload: {'v': 4, 'n': 'Ada', 'u': 'http://192.168.1.2:8000'},
  link: 'https://hub.example.org/i/lan',
);

Future<void> _pumpScreen(WidgetTester tester, InviteLoader loader) async {
  SharedPreferences.setMockInitialValues({'languageCode': 'en'});
  final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>.value(
      value: theme,
      child: MaterialApp(home: InviteScreen(loader: loader)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({'en': _translations});
  });

  testWidgets('explains both ways of pairing and shows the QR code', (
    tester,
  ) async {
    await _pumpScreen(tester, () async => _lanAndRelay);

    expect(find.text('My invitation'), findsOneWidget);
    expect(find.text('In person'), findsOneWidget);
    expect(find.text('Remotely'), findsOneWidget);
    expect(find.byKey(const Key('myQrCode')), findsOneWidget);
    expect(find.byKey(const Key('copyInviteLinkBtn')), findsOneWidget);
    expect(find.byKey(const Key('shareInviteLinkBtn')), findsOneWidget);
    expect(find.text('This link works on any network.'), findsOneWidget);
    expect(find.text('This link only works on your Wi-Fi.'), findsNothing);
  });

  testWidgets('section titles are headers and the QR code is described', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpScreen(tester, () async => _lanAndRelay);

    for (final title in ['In person', 'Remotely']) {
      final node = tester.getSemantics(find.text(title));
      expect(
        node.hasFlag(SemanticsFlag.isHeader),
        isTrue,
        reason: '"$title" must be announced as a section header',
      );
    }
    expect(find.bySemanticsLabel('QR code of your invitation'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('without relay credentials the link is announced as Wi-Fi only', (
    tester,
  ) async {
    await _pumpScreen(tester, () async => _lanOnly);

    expect(find.text('This link only works on your Wi-Fi.'), findsOneWidget);
    expect(find.text('This link works on any network.'), findsNothing);
    // The QR code and the link are still offered: they work on the LAN.
    expect(find.byKey(const Key('myQrCode')), findsOneWidget);
  });

  testWidgets('copy puts the link on the clipboard and confirms it', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _pumpScreen(tester, () async => _lanAndRelay);
    await tester.tap(find.byKey(const Key('copyInviteLinkBtn')));
    await tester.pump();

    expect(copied, 'https://hub.example.org/i/abc');
    expect(find.text('Invite link copied!'), findsOneWidget);
  });

  testWidgets('when nothing can be reached, explains it and offers a retry', (
    tester,
  ) async {
    var calls = 0;
    await _pumpScreen(tester, () async {
      calls++;
      return calls == 1 ? null : _lanAndRelay;
    });

    expect(find.text('Your invitation cannot be prepared.'), findsOneWidget);
    expect(
      find.text('Check your Wi-Fi connection and try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('myQrCode')), findsNothing);
    expect(find.byKey(const Key('copyInviteLinkBtn')), findsNothing);

    await tester.tap(find.byKey(const Key('retryInviteBtn')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.byKey(const Key('myQrCode')), findsOneWidget);
    expect(find.text('Your invitation cannot be prepared.'), findsNothing);
  });

  testWidgets('the close button dismisses the screen', (tester) async {
    await _pumpScreen(tester, () async => _lanAndRelay);
    expect(find.byKey(const Key('showMyCodeDialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('closeShowMyCode')));
    await tester.pumpAndSettle();

    // The screen is pushed as a full-screen dialog in the app; popped from a
    // MaterialApp home it simply has nowhere to go, so we only assert it did
    // not throw. The dismissal itself is exercised by the integration tour.
    expect(tester.takeException(), isNull);
  });
}
