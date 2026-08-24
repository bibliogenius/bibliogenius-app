import 'package:bibliogenius/models/contact_card.dart';
import 'package:bibliogenius/utils/contact_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContactLinks', () {
    test('mailto encodes subject and body instead of concatenating them', () {
      final uri = ContactLinks.mailto(
        email: 'a@b.co',
        subject: 'Borrow request',
        body: 'About "Le Rouge & le Noir"\nThanks',
      );
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'a@b.co');
      expect(uri.queryParameters['subject'], 'Borrow request');
      expect(uri.queryParameters['body'], 'About "Le Rouge & le Noir"\nThanks');
      // The ampersand must not open a second query parameter.
      expect(uri.toString().contains('le Noir"'), isFalse);
    });

    test('sms carries the body', () {
      final uri = ContactLinks.sms(phone: '+33612345678', body: 'Hello');
      expect(uri.scheme, 'sms');
      expect(uri.path, '+33612345678');
      expect(uri.queryParameters['body'], 'Hello');
    });

    test('whatsApp uses the https link with digits only', () {
      final uri = ContactLinks.whatsApp(
        card: ContactCard.sanitized(phone: '+33 6 12 34 56 78'),
        text: 'Hello',
      );
      expect(uri, isNotNull);
      expect(uri!.host, 'wa.me');
      expect(uri.scheme, 'https');
      expect(uri.path, '/33612345678');
      expect(uri.queryParameters['text'], 'Hello');
    });

    test('whatsApp is unavailable for a national number', () {
      final uri = ContactLinks.whatsApp(
        card: ContactCard.sanitized(phone: '06 12 34 56 78'),
        text: 'Hello',
      );
      expect(uri, isNull);
    });

    test('an empty prefill leaves no dangling query', () {
      // The peer sheet opens a channel with no book context.
      final mail = ContactLinks.mailto(email: 'a@b.co');
      expect(mail.toString(), 'mailto:a@b.co');
      final sms = ContactLinks.sms(phone: '+33612345678');
      expect(sms.toString(), 'sms:+33612345678');
    });

    test('clipboard text joins the filled fields only', () {
      final text = ContactLinks.clipboardText(
        ContactCard.sanitized(email: 'a@b.co', note: 'Evenings'),
      );
      expect(text, 'a@b.co\nEvenings');
    });
  });
}
