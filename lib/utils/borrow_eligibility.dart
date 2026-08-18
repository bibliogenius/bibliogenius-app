import '../services/api_service.dart';

/// A P2P loan request row reduced to what borrow eligibility needs.
class BorrowRequestEntry {
  final String peerUrl;
  final String isbn;
  final String status;

  const BorrowRequestEntry({
    required this.peerUrl,
    required this.isbn,
    required this.status,
  });
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

  /// Loads both request directions from the local backend. Returns null on
  /// failure so callers can keep their previously known state instead of
  /// wrongly re-enabling buttons with an empty snapshot.
  static Future<BorrowRequestSnapshot?> load(ApiService api) async {
    try {
      final responses = await Future.wait([
        api.getOutgoingRequests(),
        api.getIncomingRequests(),
      ]);
      return BorrowRequestSnapshot(
        outgoing: _parse(responses[0].data),
        incoming: _parse(responses[1].data),
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
            status: r['status']?.toString() ?? '',
          ),
        )
        .where((e) => e.isbn.isNotEmpty)
        .toList();
  }

  Set<String> _isbns(
    List<BorrowRequestEntry> entries,
    String status,
    String? peerUrl,
  ) {
    return entries
        .where(
          (e) =>
              e.status == status && (peerUrl == null || e.peerUrl == peerUrl),
        )
        .map((e) => e.isbn)
        .toSet();
  }

  /// Outgoing requests awaiting the lender's answer.
  Set<String> pendingIsbns({String? peerUrl}) =>
      _isbns(outgoing, 'pending', peerUrl);

  /// Outgoing requests accepted: the book is currently borrowed.
  Set<String> activeBorrowIsbns({String? peerUrl}) =>
      _isbns(outgoing, 'accepted', peerUrl);

  /// Incoming requests accepted: the book is currently lent to that peer.
  Set<String> lendingIsbns({String? peerUrl}) =>
      _isbns(incoming, 'accepted', peerUrl);
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
