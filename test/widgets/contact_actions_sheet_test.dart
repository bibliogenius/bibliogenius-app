import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
      expect(body, 'About Dune by Frank Herbert');
    });
  });
}
