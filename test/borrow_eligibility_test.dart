import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/borrow_eligibility.dart';

void main() {
  group('canBorrowBook', () {
    test('rejects a book the peer does not own', () {
      expect(
        canBorrowBook(
          owned: false,
          availableCopies: 3,
          hasPendingRequest: false,
          isActiveBorrow: false,
          isLending: false,
        ),
        isFalse,
      );
    });

    test('rejects when every copy is on loan (0 available)', () {
      expect(
        canBorrowBook(
          owned: true,
          availableCopies: 0,
          hasPendingRequest: false,
          isActiveBorrow: false,
          isLending: false,
        ),
        isFalse,
      );
    });

    test('allows when the copy count is unknown (null)', () {
      expect(
        canBorrowBook(
          owned: true,
          availableCopies: null,
          hasPendingRequest: false,
          isActiveBorrow: false,
          isLending: false,
        ),
        isTrue,
      );
    });

    test('rejects when a request is already in flight in either direction',
        () {
      for (final flags in [
        (pending: true, active: false, lending: false),
        (pending: false, active: true, lending: false),
        (pending: false, active: false, lending: true),
      ]) {
        expect(
          canBorrowBook(
            owned: true,
            availableCopies: 1,
            hasPendingRequest: flags.pending,
            isActiveBorrow: flags.active,
            isLending: flags.lending,
          ),
          isFalse,
        );
      }
    });
  });

  group('BorrowRequestSnapshot', () {
    const snapshot = BorrowRequestSnapshot(
      outgoing: [
        BorrowRequestEntry(
          peerUrl: 'http://a.local:8000',
          isbn: '9781111111111',
          status: 'pending',
        ),
        BorrowRequestEntry(
          peerUrl: 'http://a.local:8000',
          isbn: '9782222222222',
          status: 'accepted',
        ),
        BorrowRequestEntry(
          peerUrl: 'http://b.local:8000',
          isbn: '9783333333333',
          status: 'pending',
        ),
      ],
      incoming: [
        BorrowRequestEntry(
          peerUrl: 'http://a.local:8000',
          isbn: '9784444444444',
          status: 'accepted',
        ),
        BorrowRequestEntry(
          peerUrl: 'http://a.local:8000',
          isbn: '9785555555555',
          status: 'pending',
        ),
      ],
    );

    test('filters by peer when a peerUrl is given', () {
      expect(
        snapshot.pendingIsbns(peerUrl: 'http://a.local:8000'),
        {'9781111111111'},
      );
      expect(
        snapshot.activeBorrowIsbns(peerUrl: 'http://a.local:8000'),
        {'9782222222222'},
      );
      // Incoming 'pending' rows are not lending yet.
      expect(
        snapshot.lendingIsbns(peerUrl: 'http://a.local:8000'),
        {'9784444444444'},
      );
    });

    test('aggregates across peers when no peerUrl is given', () {
      expect(snapshot.pendingIsbns(), {'9781111111111', '9783333333333'});
    });
  });
}
