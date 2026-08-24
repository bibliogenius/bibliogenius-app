import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/contact_card.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/contact_actions_sheet.dart';

/// ADR-067: the channel picker offers only what can actually open. A card that
/// cannot open a channel must not show a dead entry, and copy is always there.
void main() {
  late ThemeProvider theme;

  setUp(() {
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'contact_sheet_title': 'Contact the library',
        'contact_action_email': 'Send an email',
        'contact_action_sms': 'Send a text message',
        'contact_action_whatsapp': 'WhatsApp',
        'contact_action_copy': 'Copy contact details',
        'contact_message_subject': 'Borrowing: {title}',
        'contact_message_body': 'About {title}',
        'contact_message_body_with_author': 'About {title} by {author}',
        'contact_message_short': 'Lend me {title}?',
        'contact_message_reciprocity': 'What would you like in return?',
        'contact_message_closing': 'Thank you,',
        'contact_message_short_plain': 'About your library',
        'contact_message_subject_plain': 'About your library',
        'contact_message_body_plain': 'About your library',
      },
    });
  });

  Future<void> openSheet(WidgetTester tester, ContactCard card) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showContactActionsSheet(context, card: card),
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

  testWidgets('an international number offers WhatsApp and SMS', (
    tester,
  ) async {
    await openSheet(tester, ContactCard.sanitized(phone: '+33 6 12 34 56 78'));
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Send a text message'), findsOneWidget);
    expect(find.text('Send an email'), findsNothing);
    expect(find.text('Copy contact details'), findsOneWidget);
  });

  testWidgets('a national number hides WhatsApp, keeps SMS', (tester) async {
    await openSheet(tester, ContactCard.sanitized(phone: '06 12 34 56 78'));
    expect(find.text('WhatsApp'), findsNothing);
    expect(find.text('Send a text message'), findsOneWidget);
  });

  testWidgets('a malformed address offers no mail entry', (tester) async {
    await openSheet(tester, ContactCard.sanitized(email: 'not-an-address'));
    expect(find.text('Send an email'), findsNothing);
    // Copy is the fallback that never fails.
    expect(find.text('Copy contact details'), findsOneWidget);
  });

  testWidgets('the note is shown but opens nothing', (tester) async {
    await openSheet(
      tester,
      ContactCard.sanitized(email: 'a@b.co', note: 'Evenings preferred'),
    );
    expect(find.text('Send an email'), findsOneWidget);
    expect(find.text('Evenings preferred'), findsOneWidget);
  });

  group('prefilled message', () {
    testWidgets('names the book and its author, nothing else', (tester) async {
      late String body;
      late String subject;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                subject = contactMessageSubject(context, bookTitle: 'Dune');
                body = contactMessageBody(
                  context,
                  bookTitle: 'Dune',
                  bookAuthor: 'Frank Herbert',
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(subject, 'Borrowing: Dune');
      expect(body, 'About Dune by Frank Herbert\n\nThank you,');
    });

    testWidgets('reciprocity is offered to a peer, never to a public library', (
      tester,
    ) async {
      late String withPeer;
      late String withLibrary;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                withPeer = contactMessageBody(
                  context,
                  bookTitle: 'Dune',
                  reciprocal: true,
                );
                withLibrary = contactMessageBody(context, bookTitle: 'Dune');
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(withPeer, contains('What would you like in return?'));
      expect(withLibrary, isNot(contains('What would you like in return?')));
      // The offer sits before the sign-off, not after it.
      expect(
        withPeer.indexOf('What would you like in return?'),
        lessThan(withPeer.indexOf('Thank you,')),
      );
    });

    testWidgets('a text message stays one line, with no sign-off', (
      tester,
    ) async {
      late String short;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                short = contactMessageBody(
                  context,
                  bookTitle: 'Dune',
                  reciprocal: true,
                  short: true,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(short, 'Lend me Dune?');
    });

    testWidgets('the short version is used for text messages', (tester) async {
      late String short;
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                short = contactMessageBody(
                  context,
                  bookTitle: 'Dune',
                  bookAuthor: 'Frank Herbert',
                  short: true,
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(short, 'Lend me Dune?');
    });

    testWidgets(
      'a chosen library name signs the message, a default one does not',
      (tester) async {
        late String unsigned;
        late String signed;
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: theme,
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  unsigned = contactMessageBody(context, bookTitle: 'Dune');
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        // Fresh install: the name is the localized default, which identifies
        // nobody, so nothing is signed.
        expect(unsigned, 'About Dune\n\nThank you,');

        // Loaded from storage rather than set through setLibraryName, which
        // syncs the name to the Rust backend and has nothing to talk to in a
        // widget test: the call never returns.
        SharedPreferences.setMockInitialValues({
          'libraryName': 'Chez Federico',
          'libraryNameCustomized': true,
        });
        final named = ThemeProvider();
        await named.loadSettings();
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: named,
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  signed = contactMessageBody(context, bookTitle: 'Dune');
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
        expect(signed, 'About Dune\n\nThank you,\nChez Federico');
      },
    );
  });
}
