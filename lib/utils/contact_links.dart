import '../models/contact_card.dart';

/// Builders for the outbound contact links of ADR-067.
///
/// Kept free of `BuildContext` so the URI shapes stay unit-testable. Every URI
/// goes through the `Uri` constructors: a hand-concatenated query string is how
/// an address or a book title ends up injecting into the target.
class ContactLinks {
  const ContactLinks._();

  /// `mailto:` with a prefilled subject and body.
  static Uri mailto({
    required String email,
    String subject = '',
    String body = '',
  }) {
    final params = <String, String>{
      if (subject.isNotEmpty) 'subject': subject,
      if (body.isNotEmpty) 'body': body,
    };
    return Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: params.isEmpty ? null : params,
    );
  }

  /// `sms:` with a prefilled body. Android and iOS both accept `?body=`.
  static Uri sms({required String phone, String body = ''}) {
    return Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: body.isEmpty ? null : {'body': body},
    );
  }

  /// WhatsApp through the https link, never the `whatsapp://` custom scheme:
  /// a custom scheme needs `LSApplicationQueriesSchemes` on iOS and a
  /// `<queries>` entry on Android, without which `canLaunchUrl` returns false
  /// with no diagnostic.
  ///
  /// Returns null when the number is not in international form.
  static Uri? whatsApp({required ContactCard card, required String text}) {
    final number = card.whatsAppNumber;
    if (number == null) return null;
    return Uri.https('wa.me', '/$number', {'text': text});
  }

  /// Plain-text rendering of the card, for the clipboard fallback.
  static String clipboardText(ContactCard card) {
    return [
      card.email,
      card.phone,
      card.note,
    ].where((s) => s.isNotEmpty).join('\n');
  }
}
