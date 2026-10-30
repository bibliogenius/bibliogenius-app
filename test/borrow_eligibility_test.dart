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
          title: 'Book 1',
          status: 'pending',
        ),
        BorrowRequestEntry(
          peerUrl: 'http://a.local:8000',
          isbn: '9782222222222',
          title: 'Book 2',
          status: 'accepted',
        ),
        BorrowRequestEntry(
          peerUrl: 'http://b.local:8000',
          isbn: '9783333333333',
          title: 'Book 3',
          status: 'pending',
        ),
      ],
      incoming: [
        BorrowRequestEntry(
          peerUrl: 'http://a.local:8000',
          isbn: '9784444444444',
          title: 'Book 4',
          status: 'accepted',
        ),
        BorrowRequestEntry(
          peerUrl: 'http://a.local:8000',
          isbn: '9785555555555',
          title: 'Book 5',
          status: 'pending',
        ),
      ],
    );

    test('filters by peer when a peerUrl is given', () {
      expect(
        snapshot.pendingBookKeys(peerUrl: 'http://a.local:8000'),
        {'9781111111111'},
      );
      expect(
        snapshot.activeBorrowBookKeys(peerUrl: 'http://a.local:8000'),
        {'9782222222222'},
      );
      // Incoming 'pending' rows are not lending yet.
      expect(
        snapshot.lendingBookKeys(peerUrl: 'http://a.local:8000'),
        {'9784444444444'},
      );
    });

    test('aggregates across peers when no peerUrl is given', () {
      expect(snapshot.pendingBookKeys(), {'9781111111111', '9783333333333'});
    });
  });

  group('borrowRequestKey', () {
    test('is the ISBN when the book has one', () {
      expect(borrowRequestKey(isbn: '9781111111111', title: 'Dune'),
          '9781111111111');
    });

    test('falls back to the title for a book without an ISBN', () {
      expect(borrowRequestKey(isbn: null, title: 'Carnet'),
          borrowRequestKey(isbn: '', title: 'Carnet'));
      expect(borrowRequestKey(isbn: '', title: 'Carnet'),
          isNot(borrowRequestKey(isbn: '', title: 'Autre carnet')));
    });

    test('names nothing when there is neither ISBN nor title', () {
      expect(borrowRequestKey(isbn: '', title: ''), isNull);
    });
  });

  group('BorrowRequestSnapshot without ISBN', () {
    // Rows as the backend lists them: an ISBN-less book is stored with "".
    final snapshot = BorrowRequestSnapshot.fromRows(
      outgoing: [
        {
          'peer_url': 'http://a.local:8000',
          'book_isbn': '',
          'book_title': 'Carnet de voyage',
          'status': 'pending',
        },
        {
          'peer_url': 'http://a.local:8000',
          'book_isbn': '',
          'book_title': '',
          'status': 'pending',
        },
      ],
      incoming: [
        {
          'peer_url': 'http://a.local:8000',
          'book_isbn': '',
          'book_title': 'Lettres',
          'status': 'accepted',
        },
      ],
    );

    test('tracks a pending request for a book without an ISBN', () {
      final pending = snapshot.pendingBookKeys(peerUrl: 'http://a.local:8000');
      expect(pending, {borrowRequestKey(isbn: null, title: 'Carnet de voyage')});
      expect(
        pending.contains(borrowRequestKey(isbn: null, title: 'Autre carnet')),
        isFalse,
      );
    });

    test('tracks a book without an ISBN lent to the peer', () {
      expect(snapshot.lendingBookKeys(peerUrl: 'http://a.local:8000'),
          {borrowRequestKey(isbn: null, title: 'Lettres')});
    });
  });

  group('acceptedIncomingRequestFor', () {
    final rows = [
      {
        'id': 'other',
        'book_id': 'book-2',
        'book_isbn': '',
        'status': 'accepted',
      },
      {
        'id': 'carnet',
        'book_id': 'book-1',
        'book_isbn': '',
        'status': 'accepted',
      },
      {
        'id': 'dune-pending',
        'book_id': 'book-3',
        'book_isbn': '9782266232508',
        'status': 'pending',
      },
      {
        'id': 'dune-legacy',
        'book_id': null,
        'book_isbn': '9782266232508',
        'status': 'accepted',
      },
    ];

    test('finds the loan of a book without an ISBN by its id', () {
      expect(
        acceptedIncomingRequestFor(rows, bookId: 'book-1', isbn: null)?['id'],
        'carnet',
      );
    });

    test('falls back to the ISBN for a row without a book id', () {
      expect(
        acceptedIncomingRequestFor(
          rows,
          bookId: 'book-9',
          isbn: '9782266232508',
        )?['id'],
        'dune-legacy',
      );
    });

    test('never matches on an empty ISBN', () {
      expect(acceptedIncomingRequestFor(rows, bookId: null, isbn: ''), isNull);
    });
  });
}
