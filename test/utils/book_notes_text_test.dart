import 'package:bibliogenius/models/book_note.dart';
import 'package:bibliogenius/utils/book_notes_text.dart';
import 'package:flutter_test/flutter_test.dart';

BookNote _note(int id, String content, {int? page}) => BookNote(
  id: id,
  bookId: 'book-uuid',
  content: content,
  page: page,
  createdAt: '2026-11-13T10:00:00Z',
  updatedAt: '2026-11-13T10:00:00Z',
);

void main() {
  group('formatBookNotes - plain text', () {
    String plain({
      String title = 'Le Petit Prince',
      String? author = 'Antoine de Saint-Exupéry',
      required List<BookNote> notes,
    }) => formatBookNotes(
      title: title,
      author: author,
      notes: notes,
      format: BookNotesExportFormat.plainText,
    );

    test('title, author, then every note with its page, in list order', () {
      final text = plain(
        notes: [
          _note(2, 'Second written, shown first', page: 42),
          _note(1, 'First written', page: 7),
        ],
      );
      expect(
        text,
        'Le Petit Prince\n'
        'Antoine de Saint-Exupéry\n'
        '\n'
        'Second written, shown first\n'
        'p. 42\n'
        '\n'
        'First written\n'
        'p. 7\n',
      );
    });

    test('a note without a page has no page line', () {
      expect(
        plain(notes: [_note(1, 'No page here')]),
        'Le Petit Prince\nAntoine de Saint-Exupéry\n\nNo page here\n',
      );
    });

    test('a book without an author has no author line', () {
      const expected = 'Le Petit Prince\n\nA note\np. 3\n';
      expect(
        plain(author: null, notes: [_note(1, 'A note', page: 3)]),
        expected,
      );
      expect(
        plain(author: '  ', notes: [_note(1, 'A note', page: 3)]),
        expected,
      );
    });

    test('an empty title leaves no blank header line', () {
      expect(
        plain(title: '', author: null, notes: [_note(1, 'A note')]),
        'A note\n',
      );
    });

    test('multiline content is kept as written', () {
      expect(
        plain(
          author: null,
          notes: [_note(1, 'Line one\nLine two\n\nLine four')],
        ),
        'Le Petit Prince\n\nLine one\nLine two\n\nLine four\n',
      );
    });

    test('special characters are left untouched', () {
      const content = '# not a title *not bold* > not a quote - [x](y) \\ _u_';
      expect(
        plain(author: null, notes: [_note(1, content)]),
        'Le Petit Prince\n\n$content\n',
      );
    });
  });

  group('formatBookNotes - Markdown', () {
    String md({
      String title = 'Le Petit Prince',
      String? author = 'Antoine de Saint-Exupéry',
      required List<BookNote> notes,
    }) => formatBookNotes(
      title: title,
      author: author,
      notes: notes,
      format: BookNotesExportFormat.markdown,
    );

    test('title as heading, author in italics, notes as quotes in order', () {
      final text = md(
        notes: [
          _note(2, 'Second written, shown first', page: 42),
          _note(1, 'First written', page: 7),
        ],
      );
      expect(
        text,
        '# Le Petit Prince\n'
        '\n'
        '*Antoine de Saint-Exupéry*\n'
        '\n'
        '> Second written, shown first\n'
        '\n'
        'p. 42\n'
        '\n'
        '> First written\n'
        '\n'
        'p. 7\n',
      );
    });

    test('a note without a page has no page line', () {
      expect(
        md(author: null, notes: [_note(1, 'No page here')]),
        '# Le Petit Prince\n\n> No page here\n',
      );
    });

    test('a book without an author has no author line', () {
      expect(
        md(author: null, notes: [_note(1, 'A note', page: 3)]),
        '# Le Petit Prince\n\n> A note\n\np. 3\n',
      );
    });

    test('an empty title leaves no heading', () {
      expect(
        md(title: ' ', author: null, notes: [_note(1, 'A note')]),
        '> A note\n',
      );
    });

    test('multiline content stays in one quote with hard line breaks', () {
      expect(
        md(author: null, notes: [_note(1, 'Line one\nLine two\n\nLine four')]),
        '# Le Petit Prince\n\n'
        '> Line one\\\n'
        '> Line two\n'
        '>\n'
        '> Line four\n',
      );
    });

    test('inline Markdown characters are escaped', () {
      expect(
        md(
          author: null,
          notes: [_note(1, r'a *b* _c_ `d` [e](f) <g> h#i j|k ~l~ m&n o\p >q')],
        ),
        '# Le Petit Prince\n\n'
        r'> a \*b\* \_c\_ \`d\` \[e\](f) \<g\> h\#i j\|k \~l\~ m\&n o\\p \>q'
        '\n',
      );
    });

    test('line-start block markers are escaped', () {
      expect(
        md(
          author: null,
          notes: [
            _note(
              1,
              '# Title\n> quote\n- item\n+ item\n12. item\n3) item\n---\n===',
            ),
          ],
        ),
        '# Le Petit Prince\n\n'
        '> \\# Title\\\n'
        '> \\> quote\\\n'
        '> \\- item\\\n'
        '> \\+ item\\\n'
        '> 12\\. item\\\n'
        '> 3\\) item\\\n'
        '> \\---\\\n'
        '> \\===\n',
      );
    });

    test('numbers that are not list markers are left alone', () {
      expect(
        md(author: null, notes: [_note(1, '1984 was 12.5 times better')]),
        '# Le Petit Prince\n\n> 1984 was 12.5 times better\n',
      );
    });

    test('URLs are left intact so autolinks keep pointing to them', () {
      expect(
        md(
          author: null,
          notes: [
            _note(
              1,
              'See https://fr.wikipedia.org/wiki/Le_Petit_Prince#Plot and '
              'www.example.com/a_b?x=1&y=2 *done*',
            ),
          ],
        ),
        '# Le Petit Prince\n\n'
        '> See https://fr.wikipedia.org/wiki/Le_Petit_Prince#Plot and '
        r'www.example.com/a_b?x=1&y=2 \*done\*'
        '\n',
      );
    });

    test('a word ending in www is not taken for a URL', () {
      expect(
        md(author: null, notes: [_note(1, 'awww.a*b')]),
        '# Le Petit Prince\n\n> awww.a\\*b\n',
      );
    });

    test('a URL ending a line keeps the break outside the link', () {
      // A trailing backslash would be swallowed by the autolink, so the
      // break falls back to two trailing spaces after a URL.
      expect(
        md(author: null, notes: [_note(1, 'See https://example.com\nnext')]),
        '# Le Petit Prince\n\n> See https://example.com  \n> next\n',
      );
    });

    test('an explicit <URL> autolink is kept as typed', () {
      expect(
        md(author: null, notes: [_note(1, 'See <https://a.com/x_y> now')]),
        '# Le Petit Prince\n\n> See <https://a.com/x_y> now\n',
      );
    });

    test('a URL right after an underscore is still recognised', () {
      expect(
        md(author: null, notes: [_note(1, '_https://a.com_')]),
        '# Le Petit Prince\n\n> \\_https://a.com_\n',
      );
    });

    test('an underscore inside a word is left alone (emails, snake_case)', () {
      expect(
        md(
          author: null,
          notes: [_note(1, 'Write to marie.curie_1@exemple.fr about snake_case _here_')],
        ),
        '# Le Petit Prince\n\n'
        '> Write to marie.curie_1@exemple.fr about snake_case \\_here\\_\n',
      );
    });

    test('indentation is capped so it never turns into a code block', () {
      expect(
        md(author: null, notes: [_note(1, 'a\n\n    verse *one*\n\t\tverse two')]),
        '# Le Petit Prince\n\n'
        '> a\n'
        '>\n'
        '>    verse \\*one\\*\\\n'
        '>    verse two\n',
      );
    });

    test('title and author are escaped too', () {
      expect(
        md(title: 'C# *in* depth', author: '_J_Doe', notes: [_note(1, 'x')]),
        '# C\\# \\*in\\* depth\n\n*\\_J_Doe*\n\n> x\n',
      );
    });
  });
}
