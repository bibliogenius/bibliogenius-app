import 'package:flutter/widgets.dart';

import 'book.dart';

/// The books a list showed, in its order, with the one the reader opened:
/// lets the book page step to the previous or next book of that list.
class BookSequence {
  /// A frozen copy: the list behind may refresh or reorder meanwhile, the
  /// reader keeps stepping through what they saw.
  final List<Book> books;
  final int index;

  const BookSequence._(this.books, this.index);

  /// The sequence around [current] in [books], or null when there is nothing
  /// to step to ([current] absent or alone). Books without an id are left
  /// out, their page cannot open; a book listed twice keeps its first place.
  static BookSequence? around(Iterable<Book> books, Book current) {
    final seen = <String>{};
    final list = List<Book>.unmodifiable([
      for (final book in books)
        if (book.id != null && seen.add(book.id!)) book,
    ]);
    final index = list.indexWhere((b) => b.id == current.id);
    if (index < 0 || list.length < 2) return null;
    return BookSequence._(list, index);
  }

  /// What to hand the `/books/:id` route when [book] is opened from a page
  /// showing [shown]: the sequence when there is a neighbour to step to,
  /// otherwise the book alone, as every other door does.
  static Object routeExtra(Iterable<Book> shown, Book book) =>
      around(shown, book) ?? book;

  Book get current => books[index];

  Book? get previous => index > 0 ? books[index - 1] : null;

  Book? get next => index < books.length - 1 ? books[index + 1] : null;

  /// The sequence moved by [delta] books. [delta] must stay in range.
  BookSequence step(int delta) {
    final target = index + delta;
    assert(target >= 0 && target < books.length);
    return BookSequence._(books, target);
  }
}

/// What a book page opened from a [BookSequence] gets to offer stepping:
/// the neighbours (null at the ends of the list) and how to reach them.
class BookStepper {
  final Book? previous;
  final Book? next;

  /// Null at the ends, so a button bound to it shows disabled.
  final void Function()? onPrevious;
  final void Function()? onNext;

  /// An earlier book of the same browse was changed: the page must still
  /// report a change when it pops, or the list behind will not refresh.
  final bool carriedChanges;

  /// Called by the page each time it changes its book.
  final void Function() onChanged;

  const BookStepper({
    this.previous,
    this.next,
    this.onPrevious,
    this.onNext,
    required this.carriedChanges,
    required this.onChanged,
  });
}

/// Whether the book page below is the one shown, or one still sliding out
/// after a step. A page sliding out must leave the back button to the page
/// shown: it would pop with what it knew when it was left.
class BookPageActivity extends InheritedWidget {
  final bool active;

  const BookPageActivity({
    super.key,
    required this.active,
    required super.child,
  });

  /// True outside a browse: a page opened alone is always the one shown.
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BookPageActivity>()?.active ??
      true;

  @override
  bool updateShouldNotify(BookPageActivity oldWidget) =>
      active != oldWidget.active;
}
