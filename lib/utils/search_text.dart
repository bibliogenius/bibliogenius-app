/// Comparison form for free-text search: lowercased, diacritics folded.
///
/// Applied to BOTH the query and the searched field, so `rene` finds
/// `René Barjavel` and `René` still finds `Rene`. Dart has no NFD in the core
/// library, so precomposed Latin letters are mapped directly, and the
/// combining marks of text that arrives already decomposed (`e` + U+0301)
/// are dropped.
String foldForSearch(String value) {
  final buffer = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    if (_isCombiningMark(char.codeUnitAt(0))) continue;
    buffer.write(_diacritics[char] ?? char);
  }
  return buffer.toString();
}

/// Combining Diacritical Marks block (U+0300–U+036F).
bool _isCombiningMark(int codeUnit) => codeUnit >= 0x0300 && codeUnit <= 0x036F;

const _diacritics = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'ă': 'a',
  'ą': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'đ': 'd',
  'ď': 'd',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ę': 'e',
  'ě': 'e',
  'ğ': 'g',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
  'ı': 'i',
  'ł': 'l',
  'ñ': 'n',
  'ń': 'n',
  'ň': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ō': 'o',
  'ő': 'o',
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ş': 's',
  'ș': 's',
  'ţ': 't',
  'ț': 't',
  'ť': 't',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ű': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'œ': 'oe',
  'æ': 'ae',
  'ß': 'ss',
};
