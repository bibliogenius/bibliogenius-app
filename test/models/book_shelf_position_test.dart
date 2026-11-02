import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/book.dart';

/// `shelf_position` is the order a reader gave the books of a shelf by hand.
/// The Rust core stored it and returned it all along, but the Dart model
/// dropped it on the way in, so the saved order was never shown, and an edit
/// sent null back and erased it. The model now carries it through.
void main() {
  test('fromJson reads shelf_position, also when sent as a string', () {
    expect(
      Book.fromJson({'title': 'T', 'shelf_position': 3}).shelfPosition,
      3,
    );
    expect(
      Book.fromJson({'title': 'T', 'shelf_position': '7'}).shelfPosition,
      7,
    );
  });

  test('fromJson keeps an absent position null', () {
    expect(Book.fromJson({'title': 'T'}).shelfPosition, isNull);
    expect(
      Book.fromJson({'title': 'T', 'shelf_position': null}).shelfPosition,
      isNull,
    );
  });

  test('toJson round-trips the position', () {
    final book = Book.fromJson({'title': 'T', 'shelf_position': 2});
    expect(book.toJson()['shelf_position'], 2);
    expect(Book.fromJson({'title': 'T'}).toJson()['shelf_position'], isNull);
  });

  test('the copy helpers keep the position', () {
    final book = Book(title: 'T', shelfPosition: 4);
    expect(book.copyWithRating(8).shelfPosition, 4);
    expect(book.copyWithCoverUrl('https://c/x.jpg').shelfPosition, 4);
  });
}
