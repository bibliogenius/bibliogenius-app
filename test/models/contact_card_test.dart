import 'dart:convert';

import 'package:bibliogenius/models/contact_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContactCard.decode legacy tolerance', () {
    test('a pre-ADR-067 free-text blob becomes the note', () {
      final card = ContactCard.decode('Federico, 06 12 34 56 78, le soir');
      expect(card.email, isEmpty);
      expect(card.phone, isEmpty);
      expect(card.note, 'Federico, 06 12 34 56 78, le soir');
      // A note alone opens no channel.
      expect(card.isActionable, isFalse);
    });

    test('malformed JSON degrades to a note instead of throwing', () {
      final card = ContactCard.decode('{"email": "a@b.c"');
      expect(card.note, '{"email": "a@b.c"');
      expect(card.email, isEmpty);
    });

    test('a JSON object without a version marker is treated as legacy', () {
      final card = ContactCard.decode('{"email": "a@b.co"}');
      expect(card.email, isEmpty);
      expect(card.note, '{"email": "a@b.co"}');
    });

    test('an empty blob yields an empty card', () {
      expect(ContactCard.decode('   '), ContactCard.empty);
    });

    test('non-string members are ignored, not crashed on', () {
      final card = ContactCard.decode(
        '{"v":1,"email":42,"phone":"+33612345678"}',
      );
      expect(card.email, isEmpty);
      expect(card.phone, '+33612345678');
    });
  });

  group('ContactCard round trip', () {
    test('encode then decode preserves the three fields', () {
      final card = ContactCard.sanitized(
        email: 'a@b.co',
        phone: '+33 6 12 34 56 78',
        note: 'Evenings preferred',
      );
      final decoded = ContactCard.decode(card.encode());
      expect(decoded.email, 'a@b.co');
      expect(decoded.phone, '+33612345678');
      expect(decoded.note, 'Evenings preferred');
    });

    test('encode carries the version marker', () {
      final encoded = ContactCard.sanitized(email: 'a@b.co').encode();
      expect(jsonDecode(encoded)['v'], 1);
    });

    test('an empty card encodes to an empty string', () {
      expect(ContactCard.empty.encode(), isEmpty);
      expect(ContactCard.sanitized(note: '   ').encode(), isEmpty);
    });

    test('empty fields are omitted from the payload', () {
      final encoded = ContactCard.sanitized(email: 'a@b.co').encode();
      expect(encoded.contains('phone'), isFalse);
      expect(encoded.contains('note'), isFalse);
    });

    test(
      'an oversized card is capped by shrinking the note, never the email',
      () {
        final card = ContactCard.sanitized(
          email: 'a@b.co',
          phone: '+33612345678',
          note: 'x' * 900,
        );
        final encoded = card.encode();
        expect(encoded.length, lessThanOrEqualTo(ContactCard.maxEncodedLength));
        final decoded = ContactCard.decode(encoded);
        expect(decoded.email, 'a@b.co');
        expect(decoded.phone, '+33612345678');
        expect(decoded.note, isNotEmpty);
      },
    );
  });

  group('ContactCard sanitization', () {
    test('a newline in the email is stripped (mailto header injection)', () {
      final card = ContactCard.sanitized(email: 'a@b.co\nBcc: evil@x.co');
      expect(card.email.contains('\n'), isFalse);
      expect(card.email, 'a@b.coBcc:evil@x.co');
    });

    test('whitespace is stripped from the phone', () {
      expect(ContactCard.sanitized(phone: ' +33 6 12 ').phone, '+33612');
    });

    test('the note keeps its line breaks', () {
      final card = ContactCard.sanitized(note: '12 rue X\n75000 Paris');
      expect(card.note, '12 rue X\n75000 Paris');
    });

    test('HTML tags are stripped from every field', () {
      final card = ContactCard.sanitized(
        email: '<b>a@b.co</b>',
        note: '<script>x</script>hours',
      );
      expect(card.email, 'a@b.co');
      expect(card.note, 'xhours');
    });
  });

  group('ContactCard channel availability', () {
    test('a well-formed address can be mailed', () {
      expect(ContactCard.sanitized(email: 'a@b.co').canSendEmail, isTrue);
    });

    test('a malformed address offers no mail action', () {
      expect(
        ContactCard.sanitized(email: 'not-an-address').canSendEmail,
        isFalse,
      );
      expect(ContactCard.sanitized(email: 'a@b').canSendEmail, isFalse);
      expect(ContactCard.sanitized(email: 'a@b@c.co').canSendEmail, isFalse);
    });

    test(
      'an address carrying a list separator is never turned into a link',
      () {
        // The card is authored by a remote library: "a,b@c.co" would reach the
        // mail client as two recipients, and "&" opens a second header.
        expect(ContactCard.sanitized(email: 'a,b@c.co').canSendEmail, isFalse);
        expect(ContactCard.sanitized(email: 'a;b@c.co').canSendEmail, isFalse);
        expect(
          ContactCard.sanitized(email: 'a&cc=x@c.co').canSendEmail,
          isFalse,
        );
        // Still displayed and copyable, just not clickable.
        expect(ContactCard.sanitized(email: 'a,b@c.co').isActionable, isTrue);
      },
    );

    test('a national number can be texted but not WhatsApped', () {
      final card = ContactCard.sanitized(phone: '06 12 34 56 78');
      expect(card.canSendMessage, isTrue);
      expect(card.whatsAppNumber, isNull);
    });

    test('an international number yields the wa.me digits', () {
      final card = ContactCard.sanitized(phone: '+33 6 12 34 56 78');
      expect(card.whatsAppNumber, '33612345678');
    });

    test('a too short number offers nothing', () {
      final card = ContactCard.sanitized(phone: '+33');
      expect(card.canSendMessage, isFalse);
      expect(card.whatsAppNumber, isNull);
    });

    test(
      'the call to action shows for an email or a phone, never a note alone',
      () {
        expect(ContactCard.sanitized(email: 'a@b.co').isActionable, isTrue);
        expect(ContactCard.sanitized(phone: '0612345678').isActionable, isTrue);
        expect(
          ContactCard.sanitized(note: 'ask at the desk').isActionable,
          isFalse,
        );
        expect(ContactCard.empty.isActionable, isFalse);
      },
    );
  });
}
