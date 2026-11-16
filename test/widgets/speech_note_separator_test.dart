import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/widgets/speech_note_button.dart';

/// Dictated words are appended to the note. They get a space after a word,
/// but not at the start of a new line, nor in an empty note.
void main() {
  test('a space separates dictated words from the last word', () {
    expect(dictationSeparator('First words'), ' ');
  });

  test('no space at the start of a new line', () {
    expect(dictationSeparator('First line\n'), '');
  });

  test('no space after an existing space or in an empty note', () {
    expect(dictationSeparator('First words '), '');
    expect(dictationSeparator(''), '');
  });
}
