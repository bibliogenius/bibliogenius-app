import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/utils/book_filters.dart';

/// A shelf badge has to announce what its tap will open (ADR-063). Since the
/// reader's ownership axis is remembered, the badge cannot be a single fixed
/// number: Rust reports both scopes and the screen picks.
Tag shelf({required int count, required int totalCount}) =>
    Tag(id: 'x', name: 'Dystopie', count: count, totalCount: totalCount);

void main() {
  test('the possession view counts what the reader has', () {
    expect(
      countForOwnershipScope(
        shelf(count: 3, totalCount: 13),
        OwnershipScope.library,
      ),
      3,
    );
  });

  test('"all" counts every book carrying the subject', () {
    expect(
      countForOwnershipScope(
        shelf(count: 3, totalCount: 13),
        OwnershipScope.all,
      ),
      13,
    );
  });

  test('"not owned" counts exactly the complement', () {
    // The reported case: ten wished books imported onto a shelf. Under this
    // scope the shelf lists those ten, so the badge must say ten and not the
    // thirteen it holds in total.
    expect(
      countForOwnershipScope(
        shelf(count: 3, totalCount: 13),
        OwnershipScope.notOwned,
      ),
      10,
    );
  });

  test('a shelf with nothing owned reads 0 only under the possession view', () {
    final imported = shelf(count: 0, totalCount: 10);

    expect(countForOwnershipScope(imported, OwnershipScope.library), 0);
    expect(countForOwnershipScope(imported, OwnershipScope.all), 10);
    expect(countForOwnershipScope(imported, OwnershipScope.notOwned), 10);
  });

  test('an old payload without the total never goes negative', () {
    // Tag.totalCount defaults to count, so a shelf built from a source that
    // does not carry it reports the same number on every scope rather than a
    // nonsense complement.
    final legacy = Tag(id: 'x', name: 'Dystopie', count: 4);

    expect(countForOwnershipScope(legacy, OwnershipScope.all), 4);
    expect(countForOwnershipScope(legacy, OwnershipScope.notOwned), 0);
  });
}
