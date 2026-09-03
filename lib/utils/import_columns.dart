/// Column lookup and line parsing shared by the CSV and XLSX library imports.
///
/// Every source names its columns differently: Gleeph exports `book_title` /
/// `book_author`, Goodreads `Title` / `Author` (plus `Author l-f` and
/// `Additional Authors`), Babelio `Titre` / `Auteur`. The CSV path already
/// looked the author up, the XLSX path never did, so a library migrated from
/// Gleeph arrived with every book anonymous. One helper, used by both, keeps
/// the two paths from drifting apart again.
///
/// The ISBN lookup, the delimiter detection and the ISBN cleaning live here for
/// the same reason. A 2861-book library once arrived with no ISBN at all after
/// an import that reported success: the file's ISBN column was simply not
/// recognised, and nothing said so. A semicolon-separated file fared worse: the
/// whole line landed in every field and its digits were glued into a 17-digit
/// "ISBN".
library;

/// Column names that ARE the author column, in no particular order.
const List<String> _exactAuthorNames = [
  'author',
  'authors',
  'book_author',
  'book_authors',
  'auteur',
  'auteurs',
  'primary author',
  'authors labels',
];

/// Index of the author column in [headers], or -1 when the file names none.
///
/// An exact name wins over a partial one so that `Additional Authors`, which
/// contains "author", cannot be picked ahead of the real `Author` column.
/// Headers are compared lowercased and trimmed; the caller may pass them raw.
int findAuthorColumn(List<String> headers) {
  final normalized = headers.map((h) => h.toLowerCase().trim()).toList();

  final exact = normalized.indexWhere(_exactAuthorNames.contains);
  if (exact != -1) return exact;

  return normalized.indexWhere(
    (h) => h.contains('author') || h.contains('auteur'),
  );
}

/// Goodreads carries both `ISBN` and `ISBN13`; the 13-digit one is preferred.
const List<String> _isbn13Names = ['isbn13', 'isbn 13', 'isbn-13', 'isbn_13'];

/// French exports name the ISBN-13 by its barcode: EAN. Only considered when
/// no column mentions "isbn", so a file carrying both keeps the ISBN one.
const List<String> _eanNames = ['ean', 'ean13', 'ean 13', 'ean-13', 'ean_13'];

/// Index of the ISBN column in [headers], or -1 when the file names none.
///
/// Order: an exact ISBN-13 name, then any header containing "isbn", then an
/// exact EAN name. Headers are compared lowercased and trimmed.
int findIsbnColumn(List<String> headers) {
  final normalized = headers.map((h) => h.toLowerCase().trim()).toList();

  final isbn13 = normalized.indexWhere(_isbn13Names.contains);
  if (isbn13 != -1) return isbn13;

  final anyIsbn = normalized.indexWhere((h) => h.contains('isbn'));
  if (anyIsbn != -1) return anyIsbn;

  return normalized.indexWhere(_eanNames.contains);
}

/// The field separator a CSV header line uses: `;`, `\t` or `,`.
///
/// Counted over the raw line, most frequent wins, comma on a tie. A header
/// carries no quoted free text, so counting inside quotes is not a concern.
String detectCsvDelimiter(String headerLine) {
  int count(String char) => char.allMatches(headerLine).length;
  final semicolons = count(';');
  final tabs = count('\t');
  final commas = count(',');
  if (semicolons > commas && semicolons >= tabs) return ';';
  if (tabs > commas && tabs > semicolons) return '\t';
  return ',';
}

/// Split one CSV line on [delimiter], honouring double quotes and the `""`
/// escape inside a quoted field.
List<String> parseCsvLine(String line, {String delimiter = ','}) {
  final result = <String>[];
  bool inQuotes = false;
  StringBuffer current = StringBuffer();

  for (int i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        current.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == delimiter && !inQuotes) {
      result.add(current.toString());
      current = StringBuffer();
    } else {
      current.write(char);
    }
  }
  result.add(current.toString());
  return result;
}

/// A spreadsheet number: 9782253140191.0 or 9.782253140191E12.
final RegExp _spreadsheetNumber = RegExp(r'^\d+(\.\d+)?([eE][+-]?\d+)?$');

/// Everything an ISBN is not made of.
final RegExp _notIsbnCharacter = RegExp(r'[^\dXx]');

/// Outcome of cleaning one imported ISBN cell.
///
/// [isbn] is the value to store, null when the cell holds none. [rejected] is
/// true when the cell held something that is not an ISBN: the value is dropped
/// rather than stored, and the import reports the count so the reader knows
/// the file, not the app, is at fault.
typedef ImportedIsbn = ({String? isbn, bool rejected});

/// Clean one ISBN cell from an imported file.
///
/// Strips the Goodreads `="..."` armour (the CSV parser already ate the
/// quotes, so only the `=` survives) and every formatting character, then
/// keeps the value only if it has the length of an ISBN. The checksum is not
/// required: real shelves hold mistyped ISBNs, and the edit form warns about
/// those without refusing them. Length is the line: a 17-digit run is a
/// mis-split line, never a book.
ImportedIsbn cleanImportedIsbn(String? raw) {
  if (raw == null) return (isbn: null, rejected: false);
  var value = raw.trim();
  if (value.startsWith('=')) value = value.substring(1);
  value = value.replaceAll('"', '').trim();
  // A spreadsheet that treated the column as a number writes 9.782253140191E12
  // or 9782253140191.0; both are the same 13 digits.
  if (_spreadsheetNumber.hasMatch(value) &&
      (value.contains('.') || value.contains('e') || value.contains('E'))) {
    final number = double.tryParse(value);
    if (number != null) value = number.toStringAsFixed(0);
  }
  value = value.replaceAll(_notIsbnCharacter, '');
  if (value.isEmpty) return (isbn: null, rejected: false);
  value = value.toUpperCase();
  if (value.length == 10 || value.length == 13) {
    return (isbn: value, rejected: false);
  }
  return (isbn: null, rejected: true);
}
