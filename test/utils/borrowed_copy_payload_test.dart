import 'package:bibliogenius/utils/borrowed_copy_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('contactLoanCopyPayload (ADR-034)', () {
    test('writes the lender to the typed columns, never to notes', () {
      final payload = contactLoanCopyPayload(
        bookId: 'book-uuid',
        lenderDisplayName: 'Ada Lovelace',
      );

      expect(payload['book_id'], 'book-uuid');
      expect(payload['status'], 'borrowed');
      expect(payload['lender_display_name'], 'Ada Lovelace');
      expect(payload['borrow_source'], 'contact');
      expect(
        payload.containsKey('notes'),
        isFalse,
        reason:
            'notes belongs to the user (ADR-034); the lender goes in a column',
      );
    });

    test('a contact loan is not a temporary copy', () {
      // `is_temporary` scopes the P2P queries (borrow_source = peer). A contact
      // loan that claimed the flag would drift into that space; the borrowed
      // list keys on `status` instead, so the flag buys nothing here.
      final payload = contactLoanCopyPayload(
        bookId: 'book-uuid',
        lenderDisplayName: 'Ada Lovelace',
      );

      expect(payload['is_temporary'], isFalse);
    });

    test('carries the optional dates only when supplied', () {
      final bare = contactLoanCopyPayload(
        bookId: 'book-uuid',
        lenderDisplayName: 'Ada Lovelace',
      );
      expect(bare.containsKey('acquisition_date'), isFalse);
      expect(bare.containsKey('borrow_due_date'), isFalse);

      final dated = contactLoanCopyPayload(
        bookId: 'book-uuid',
        lenderDisplayName: 'Ada Lovelace',
        acquisitionDate: '2026-07-11',
        borrowDueDate: '2026-08-11',
      );
      expect(dated['acquisition_date'], '2026-07-11');
      expect(dated['borrow_due_date'], '2026-08-11');
    });
  });
}
