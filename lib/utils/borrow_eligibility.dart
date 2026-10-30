import '../services/api_service.dart';

/// Identifies a book across P2P loan requests: its ISBN when it has one, its
/// title otherwise. A book without an ISBN has no other key on the borrower's
/// side; the backend duplicate guards apply the same rule. Null when there is
/// neither.
String? borrowRequestKey({required String? isbn, required String title}) {
  if (isbn != null && isbn.isNotEmpty) return isbn;
  if (title.isEmpty) return null;
  // Prefixed so a title can never collide with an ISBN.
  return 'title:$title';
}

/// A P2P loan request row reduced to what borrow eligibility needs.
class BorrowRequestEntry {
  final String peerUrl;
  final String isbn;
  final String title;
  final String status;

  const BorrowRequestEntry({
    required this.peerUrl,
    required this.isbn,
    required this.title,
    required this.status,
  });

  String? get bookKey => borrowRequestKey(isbn: isbn, title: title);
}

/// Snapshot of the outgoing/incoming P2P loan requests, queryable by peer.
///
/// Single source of truth for the "can this book be requested" rule, shared
/// by the peer library screen and the book details availability card. Do
/// not re-derive these sets inline in screens.
class BorrowRequestSnapshot {
  final List<BorrowRequestEntry> outgoing;
  final List<BorrowRequestEntry> incoming;

  const BorrowRequestSnapshot({required this.outgoing, required this.incoming});

  static const empty = BorrowRequestSnapshot(outgoing: [], incoming: []);

  /// Builds a snapshot from request rows as the local backend lists them.
  factory BorrowRequestSnapshot.fromRows({
    required dynamic outgoing,
    required dynamic incoming,
  }) => BorrowRequestSnapshot(
    outgoing: _parse(outgoing),
    incoming: _parse(incoming),
  );

  /// Loads both request directions from the local backend. Returns null on
  /// failure so callers can keep their previously known state instead of
  /// wrongly re-enabling buttons with an empty snapshot.
  static Future<BorrowRequestSnapshot?> load(ApiService api) async {
    try {
      final responses = await Future.wait([
        api.getOutgoingRequests(),
        api.getIncomingRequests(),
      ]);
      return BorrowRequestSnapshot.fromRows(
        outgoing: responses[0].data,
        incoming: responses[1].data,
      );
    } catch (_) {
      return null;
    }
  }

  static List<BorrowRequestEntry> _parse(dynamic data) {
    final list = data as List<dynamic>? ?? [];
    return list
        .map(
          (r) => BorrowRequestEntry(
            peerUrl: r['peer_url']?.toString() ?? '',
            isbn: r['book_isbn']?.toString() ?? '',
            title: r['book_title']?.toString() ?? '',
            status: r['status']?.toString() ?? '',
          ),
        )
        .where((e) => e.bookKey != null)
        .toList();
  }

  Set<String> _bookKeys(
    List<BorrowRequestEntry> entries,
    String status,
    String? peerUrl,
  ) {
    return entries
        .where(
          (e) =>
              e.status == status && (peerUrl == null || e.peerUrl == peerUrl),
        )
        .map((e) => e.bookKey!)
        .toSet();
  }

  // The sets below hold [borrowRequestKey] values.

  /// Outgoing requests awaiting the lender's answer.
  Set<String> pendingBookKeys({String? peerUrl}) =>
      _bookKeys(outgoing, 'pending', peerUrl);

  /// Outgoing requests accepted: the book is currently borrowed.
  Set<String> activeBorrowBookKeys({String? peerUrl}) =>
      _bookKeys(outgoing, 'accepted', peerUrl);

  /// Incoming requests accepted: the book is currently lent to that peer.
  Set<String> lendingBookKeys({String? peerUrl}) =>
      _bookKeys(incoming, 'accepted', peerUrl);
}

/// The accepted incoming request for a book lent to a peer, among request
/// rows as the local backend lists them. Matched on the book id the backend
/// resolved for the request, the only key for a book without an ISBN, then on
/// the ISBN for rows that carry no id. Null when none matches.
Map<dynamic, dynamic>? acceptedIncomingRequestFor(
  List<dynamic> rows, {
  required String? bookId,
  required String? isbn,
}) {
  final accepted = rows
      .whereType<Map<dynamic, dynamic>>()
      .where((r) => r['status'] == 'accepted');
  if (bookId != null && bookId.isNotEmpty) {
    for (final r in accepted) {
      if (r['book_id'] == bookId) return r;
    }
  }
  if (isbn != null && isbn.isNotEmpty) {
    for (final r in accepted) {
      if (r['book_isbn'] == isbn) return r;
    }
  }
  return null;
}

/// The borrow eligibility rule (previously inlined in the peer library
/// screen). A book can be requested when the peer actually owns it, at
/// least one copy may be available, and no request is already in flight
/// in either direction.
bool canBorrowBook({
  required bool owned,
  required int? availableCopies,
  required bool hasPendingRequest,
  required bool isActiveBorrow,
  required bool isLending,
}) {
  // Can't borrow a book the peer doesn't own (e.g. they borrowed it
  // themselves). For hub catalog books, owned defaults to true (unknown =
  // allow request, server auto-rejects if no available copy).
  if (!owned) return false;
  // availableCopies == null means unknown: allow the request.
  final noCopiesAvailable = availableCopies != null && availableCopies == 0;
  return !hasPendingRequest && !isActiveBorrow && !isLending &&
      !noCopiesAvailable;
}
