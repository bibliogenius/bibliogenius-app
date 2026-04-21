import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/loan.dart';

/// Non-regression for the cover URL resolver refactor.
///
/// The ticket [TECH-DEBT] Unifier la résolution des cover URLs delegates
/// every cover getter to `CoverUrlResolver`. These tests lock in the
/// observable behavior of the four getters a screen may touch
/// (Book.coverUrl, Book.rawCoverUrl, Book.largeCoverUrl,
/// Loan.resolvedCoverUrl) so a future refactor of the resolver cannot
/// silently change what the UI renders.
void main() {
  group('Book.rawCoverUrl', () {
    test('returns the persisted value exactly, no fallback', () {
      final b = Book(title: 't', coverUrl: 'https://hub/covers/1');
      expect(b.rawCoverUrl, 'https://hub/covers/1');
    });

    test('returns null when not persisted, even if ISBN is present', () {
      // Critical non-regression: peer rendering must rely on this getter
      // so a book without an explicit cover never shows an OpenLibrary
      // image on the visitor's side.
      final b = Book(title: 't', isbn: '9781234567890');
      expect(b.rawCoverUrl, isNull);
    });
  });

  group('Book.coverUrl (local context)', () {
    test('returns the persisted URL when present', () {
      final b = Book(title: 't', coverUrl: 'https://hub/covers/1');
      expect(b.coverUrl, 'https://hub/covers/1');
    });

    test('falls back to OpenLibrary M when only ISBN is available', () {
      final b = Book(title: 't', isbn: '9781234567890');
      expect(
        b.coverUrl,
        'https://covers.openlibrary.org/b/isbn/9781234567890-M.jpg?default=false',
      );
    });

    test('returns null when neither persisted nor ISBN', () {
      final b = Book(title: 't');
      expect(b.coverUrl, isNull);
    });
  });

  group('Book.largeCoverUrl', () {
    test('returns the persisted URL when present (no L upgrade)', () {
      // When the user uploaded their own cover, we must not swap in an
      // OpenLibrary L variant: the persisted URL is authoritative.
      final b = Book(title: 't', coverUrl: 'https://hub/covers/1');
      expect(b.largeCoverUrl, 'https://hub/covers/1');
    });

    test('falls back to OpenLibrary L when only ISBN is available', () {
      final b = Book(title: 't', isbn: '9781234567890');
      expect(
        b.largeCoverUrl,
        'https://covers.openlibrary.org/b/isbn/9781234567890-L.jpg?default=false',
      );
    });
  });

  group('Loan.resolvedCoverUrl', () {
    Loan loan({String? coverUrl, String? isbn}) => Loan(
      id: 1,
      copyId: 1,
      contactId: 1,
      libraryId: 1,
      loanDate: '2026-04-20',
      dueDate: '2026-05-20',
      status: 'active',
      contactName: 'X',
      bookTitle: 'T',
      coverUrl: coverUrl,
      isbn: isbn,
    );

    test('returns the persisted URL when present', () {
      expect(
        loan(coverUrl: 'https://cdn/x.jpg', isbn: '9781234567890')
            .resolvedCoverUrl,
        'https://cdn/x.jpg',
      );
    });

    test('falls back to OpenLibrary M with default=false when only ISBN', () {
      // Pre-refactor this getter returned `...$isbn-M.jpg` without the
      // `default=false` suffix, which made OpenLibrary return a 1x1
      // grey placeholder for unknown ISBNs and hid the errorWidget.
      // Post-refactor it aligns with Book.coverUrl.
      expect(
        loan(isbn: '9781234567890').resolvedCoverUrl,
        'https://covers.openlibrary.org/b/isbn/9781234567890-M.jpg?default=false',
      );
    });

    test('returns null when neither persisted nor ISBN', () {
      expect(loan().resolvedCoverUrl, isNull);
    });
  });
}
