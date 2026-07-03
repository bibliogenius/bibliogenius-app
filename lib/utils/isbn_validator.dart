class IsbnValidator {
  /// Strip formatting characters (hyphens, spaces), keep only digits and trailing X.
  static String clean(String isbn) {
    return isbn.replaceAll(RegExp(r'[\s-]'), '');
  }

  static bool isValid(String? isbn) {
    if (isbn == null || isbn.isEmpty) return false;

    // Remove hyphens and spaces
    final cleanIsbn = isbn.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

    if (cleanIsbn.length == 10) {
      return _isValidIsbn10(cleanIsbn);
    } else if (cleanIsbn.length == 13) {
      return _isValidIsbn13(cleanIsbn);
    }

    return false;
  }

  /// Canonical ISBN-13 plain form of [isbn], or null when the input is not a
  /// valid ISBN-10/13. Mirrors the Rust `utils::isbn::to_isbn13` helper so
  /// both sides of the hub-catalog matching share the same canonical form.
  static String? toIsbn13(String isbn) {
    final cleanIsbn = clean(isbn).toUpperCase();
    if (cleanIsbn.length == 13 && _isValidIsbn13(cleanIsbn)) return cleanIsbn;
    if (cleanIsbn.length == 10 && _isValidIsbn10(cleanIsbn)) {
      final first12 = '978${cleanIsbn.substring(0, 9)}';
      return '$first12${_ean13CheckDigit(first12)}';
    }
    return null;
  }

  /// Comparison key for ISBN matching: the ISBN-13 form when valid, the raw
  /// string unchanged otherwise, so an invalid value only matches itself and
  /// two distinct invalid values never collide.
  static String canonicalKey(String isbn) => toIsbn13(isbn) ?? isbn;

  static int _ean13CheckDigit(String first12) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      final digit = int.parse(first12[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    return (10 - sum % 10) % 10;
  }

  static bool _isValidIsbn10(String isbn) {
    if (!RegExp(r'^\d{9}[\dX]$').hasMatch(isbn)) return false;

    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(isbn[i]) * (10 - i);
    }

    final lastChar = isbn[9];
    if (lastChar == 'X') {
      sum += 10;
    } else {
      sum += int.parse(lastChar);
    }

    return sum % 11 == 0;
  }

  static bool _isValidIsbn13(String isbn) {
    if (!RegExp(r'^\d{13}$').hasMatch(isbn)) return false;

    int sum = 0;

    // Check for standard Bookland EAN prefix (978 or 979)
    if (!isbn.startsWith('978') && !isbn.startsWith('979')) {
      return false;
    }

    for (int i = 0; i < 13; i++) {
      int digit = int.parse(isbn[i]);
      if (i % 2 == 0) {
        sum += digit;
      } else {
        sum += digit * 3;
      }
    }

    return sum % 10 == 0;
  }
}
