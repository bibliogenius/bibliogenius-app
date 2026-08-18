import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';

/// The `wanted` flag mirrors a peer's wishlist through the catalog wire
/// format. Cross-generation rule: absent stays absent (null), and it is
/// NEVER inferred from `owned == false`, which also covers books the peer
/// merely borrowed. The flag must round-trip through toJson because
/// cachePeerBooks re-serialises fetched catalogs before the local cache
/// upsert persists them.
void main() {
  test('fromJson keeps wanted null when the peer did not send it', () {
    final book = Book.fromJson({'title': 'T', 'owned': false});
    expect(book.wanted, isNull,
        reason: 'owned=false alone must not be read as a wish');
  });

  test('fromJson reads an explicit wanted flag', () {
    final book = Book.fromJson({'title': 'T', 'owned': false, 'wanted': true});
    expect(book.wanted, isTrue);
  });

  test('toJson round-trips wanted and omits it when absent', () {
    final wished =
        Book.fromJson({'title': 'T', 'owned': false, 'wanted': true});
    expect(wished.toJson()['wanted'], isTrue);

    final plain = Book.fromJson({'title': 'T', 'owned': false});
    expect(plain.toJson().containsKey('wanted'), isFalse,
        reason: 'an absent flag must stay absent, not become false');
  });
}
