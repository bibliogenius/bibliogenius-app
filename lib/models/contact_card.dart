import 'dart:convert';

/// Contact details a library owner shares with its approved followers
/// (ADR-067).
///
/// The card travels inside the sealed blob attached to a follow relationship.
/// That blob is opaque to Rust and to the hub, which store and forward a base64
/// string without ever inspecting it, so the wire format is a pure client-side
/// convention: a versioned JSON object.
///
/// ```json
/// {"v": 1, "email": "...", "phone": "...", "note": "..."}
/// ```
///
/// **Legacy tolerance is load-bearing.** Before ADR-067 the sealed plaintext
/// was a single free-text field. An owner who never reopens the settings keeps
/// emitting that shape forever, so [decode] accepts anything that is not a
/// versioned object and keeps it as [note] rather than losing it.
class ContactCard {
  /// Address used to build a `mailto:` link. Whitespace-free (see [sanitize]).
  final String email;

  /// Number used to build message links. Whitespace-free, may start with `+`.
  final String phone;

  /// Free text: postal address, opening hours, "evenings preferred".
  /// The only field that keeps its line breaks.
  final String note;

  const ContactCard({this.email = '', this.phone = '', this.note = ''});

  static const ContactCard empty = ContactCard();

  /// Maximum size of the serialized card. The blob is sealed once per follower
  /// and stored on the hub, so the pre-existing 500 character budget is kept.
  static const int maxEncodedLength = 500;

  static const int _maxEmailLength = 254;
  static const int _maxPhoneLength = 32;

  // Hoisted: the sanitizers run on every keystroke of the settings form.
  static final RegExp _htmlTag = RegExp(r'<[^>]*>');
  static final RegExp _controlChars = RegExp(
    r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]',
  );
  static final RegExp _whitespace = RegExp(r'\s');
  static final RegExp _nonDigits = RegExp(r'[^0-9]');

  /// Characters that split an address list or open a second header in a
  /// `mailto:` URI. The card is authored by a remote library, so an address
  /// carrying any of them is shown as text but never turned into a link.
  static final RegExp _addressSeparators = RegExp(r'[,;&<>"]');

  bool get isEmpty => email.isEmpty && phone.isEmpty && note.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Whether a "Contact" affordance should be offered at all (ADR-067 D5).
  ///
  /// A note alone opens no channel, so it never produces a call to action; it
  /// stays visible as text on the peer sheet.
  bool get isActionable => email.isNotEmpty || phone.isNotEmpty;

  /// Whether the address is shaped well enough to hand to a mail client.
  /// Deliberately permissive: the goal is to avoid offering a link that cannot
  /// open, not to validate addresses.
  bool get canSendEmail {
    if (email.isEmpty || email.length > _maxEmailLength) return false;
    if (_addressSeparators.hasMatch(email)) return false;
    final parts = email.split('@');
    if (parts.length != 2) return false;
    final local = parts[0];
    final domain = parts[1];
    if (local.isEmpty || domain.length < 3) return false;
    if (!domain.contains('.')) return false;
    if (domain.startsWith('.') || domain.endsWith('.')) return false;
    return true;
  }

  /// Whether the number can be dialled or texted.
  bool get canSendMessage => _phoneDigits.length >= 5;

  /// International number, digits only, for a `https://wa.me/` link.
  ///
  /// Null unless the owner typed the number in international form. A national
  /// number carries no country, and guessing one would be wrong for every
  /// library outside the guesser's own country (ADR-067 D1).
  String? get whatsAppNumber {
    if (!phone.startsWith('+')) return null;
    final digits = _phoneDigits;
    return digits.length >= 8 ? digits : null;
  }

  String get _phoneDigits => phone.replaceAll(_nonDigits, '');

  ContactCard copyWith({String? email, String? phone, String? note}) {
    return ContactCard(
      email: email ?? this.email,
      phone: phone ?? this.phone,
      note: note ?? this.note,
    );
  }

  /// Builds a card from raw user input, applying the ADR-067 D8 rules.
  factory ContactCard.sanitized({
    String email = '',
    String phone = '',
    String note = '',
  }) {
    return ContactCard(
      email: _sanitizeStrict(email, _maxEmailLength),
      phone: _sanitizeStrict(phone, _maxPhoneLength),
      note: sanitizeNote(note),
    );
  }

  /// Reads a decrypted blob. Never throws: an unreadable payload degrades to a
  /// note rather than to nothing.
  factory ContactCard.decode(String plaintext) {
    final raw = plaintext.trim();
    if (raw.isEmpty) return empty;
    if (raw.startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['v'] != null) {
          return ContactCard.sanitized(
            email: _asString(decoded['email']),
            phone: _asString(decoded['phone']),
            note: _asString(decoded['note']),
          );
        }
      } on FormatException {
        // Not JSON after all: fall through to the legacy path.
      }
    }
    return ContactCard(note: sanitizeNote(raw));
  }

  /// Serializes for sealing. Returns an empty string for an empty card, which
  /// the caller treats as "nothing to share".
  String encode() {
    if (isEmpty) return '';
    var card = this;
    var out = _encodeOf(card);
    // The note is the elastic field: shrink it until the whole card fits
    // rather than truncating an address or a number into something unusable.
    while (out.length > maxEncodedLength && card.note.isNotEmpty) {
      final excess = out.length - maxEncodedLength;
      final keep = card.note.length - excess;
      card = card.copyWith(note: keep > 0 ? card.note.substring(0, keep) : '');
      out = _encodeOf(card);
    }
    return out;
  }

  static String _encodeOf(ContactCard card) {
    final map = <String, dynamic>{'v': 1};
    if (card.email.isNotEmpty) map['email'] = card.email;
    if (card.phone.isNotEmpty) map['phone'] = card.phone;
    if (card.note.isNotEmpty) map['note'] = card.note;
    return jsonEncode(map);
  }

  static String _asString(dynamic value) => value is String ? value : '';

  /// Note sanitizer: strips HTML tags and control characters but keeps line
  /// breaks and tabs, which are meaningful in a postal address.
  static String sanitizeNote(String raw) {
    var s = raw.replaceAll(_htmlTag, '');
    s = s.replaceAll(_controlChars, '');
    s = s.trim();
    if (s.length > maxEncodedLength) s = s.substring(0, maxEncodedLength);
    return s;
  }

  /// Strict sanitizer for the fields that end up inside a URI.
  ///
  /// Removes every whitespace character, line breaks included: a newline inside
  /// an address used to build a `mailto:` is a header injection vector.
  static String _sanitizeStrict(String raw, int maxLength) {
    var s = raw.replaceAll(_htmlTag, '');
    s = s.replaceAll(_controlChars, '');
    s = s.replaceAll(_whitespace, '');
    if (s.length > maxLength) s = s.substring(0, maxLength);
    return s;
  }

  @override
  bool operator ==(Object other) =>
      other is ContactCard &&
      other.email == email &&
      other.phone == phone &&
      other.note == note;

  @override
  int get hashCode => Object.hash(email, phone, note);

  @override
  String toString() =>
      'ContactCard(email: $email, phone: $phone, note: ${note.length} chars)';
}
