class IsbnValidator {
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
