/// Comparison form for free-text search: lowercased, diacritics folded.
///
/// Applied to BOTH the query and the searched field, so `rene` finds
/// `René Barjavel` and `René` still finds `Rene`. Dart has no NFD in the core
/// library, so the Latin letters a library actually holds are mapped directly.
String foldForSearch(String value) {
  final buffer = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    buffer.write(_diacritics[char] ?? char);
  }
  return buffer.toString();
}

const _diacritics = {
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'á': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'ć': 'c',
  'č': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ę': 'e',
  'ě': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ī': 'i',
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
  'ř': 'r',
  'ś': 's',
  'š': 's',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ū': 'u',
  'ů': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ź': 'z',
  'ż': 'z',
  'ž': 'z',
  'œ': 'oe',
  'æ': 'ae',
  'ß': 'ss',
};
