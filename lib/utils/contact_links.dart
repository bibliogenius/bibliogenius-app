import '../models/contact_card.dart';

/// Builders for the outbound contact links of ADR-067.
///
/// Kept free of `BuildContext` so the URI shapes stay unit-testable. Every
/// value is escaped with [Uri.encodeComponent]: unescaped concatenation is how
/// an address or a book title ends up injecting into the target.
///
/// **Not `queryParameters`.** That constructor applies form encoding, which
/// writes a space as `+`. A mail client follows RFC 6068 and shows the plus
/// signs literally, so the reader receives "Je+vous+ecris". Percent encoding
/// is what these schemes expect.
class ContactLinks {
  const ContactLinks._();

  /// `mailto:` with a prefilled subject and body.
  static Uri mailto({
    required String email,
    String subject = '',
    String body = '',
  }) {
    final parts = <String>[
      if (subject.isNotEmpty) 'subject=${Uri.encodeComponent(subject)}',
      if (body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
    ];
    return Uri(
      scheme: 'mailto',
      path: email,
      query: parts.isEmpty ? null : parts.join('&'),
    );
  }

  /// `sms:` with a prefilled body. Android and iOS both accept `?body=`.
  static Uri sms({required String phone, String body = ''}) {
    return Uri(
      scheme: 'sms',
      path: phone,
      query: body.isEmpty ? null : 'body=${Uri.encodeComponent(body)}',
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
    return Uri.https(
      'wa.me',
      '/$number',
    ).replace(query: 'text=${Uri.encodeComponent(text)}');
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
