import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/copy.dart';
import 'package:bibliogenius/utils/ownership_actions.dart';

import '../helpers/mock_repositories.dart';

/// Cover for the copy-side consequences of the `owned` flag.
///
/// The rule used to live inline in the edit form's save path, where nothing
/// tested it, while it deletes rows a live loan can point at. It is shared
/// with the book page's ownership sheet now, so it is pinned here.
Copy _copy(String id, {String status = 'available'}) =>
    Copy(id: id, bookId: 'b1', libraryId: 1, status: status);

void main() {
  late MockCopyRepository copies;

  setUp(() => copies = MockCopyRepository());

  test('releasing ownership deletes every copy', () async {
    copies.mockCopies = [_copy('c1'), _copy('c2')];

    final result = await applyOwnershipToCopies(
      copies: copies,
      bookId: 'b1',
      owned: false,
    );

    expect(copies.deletedCopyIds, ['c1', 'c2']);
    expect(result.copiesDeleted, 2);
    expect(result.copyId, isNull);
    expect(result.hadFailures, isFalse);
  });

  test('taking ownership with no copy creates one', () async {
    final result = await applyOwnershipToCopies(
      copies: copies,
      bookId: 'b1',
      owned: true,
    );

    expect(copies.createdCopies, hasLength(1));
    expect(copies.createdCopies.single['book_id'], 'b1');
    expect(copies.createdCopies.single['status'], 'available');
    expect(result.copyId, isNotNull);
    expect(copies.deletedCopyIds, isEmpty);
  });

  test('taking ownership with a copy already there keeps it', () async {
    final result = await applyOwnershipToCopies(
      copies: copies,
      bookId: 'b1',
      owned: true,
      existingCopyId: 'c1',
      copyStatus: 'lost',
    );

    expect(copies.createdCopies, isEmpty);
    expect(copies.deletedCopyIds, isEmpty);
    expect(result.copyId, 'c1');
  });

  test('a deletion that throws is reported, not swallowed', () async {
    // The edit form has always turned this into a debug line; a page that
    // just asked the reader to confirm a destructive change needs to know.
    final result = await applyOwnershipToCopies(
      copies: _ThrowingCopyRepository(),
      bookId: 'b1',
      owned: false,
    );

    expect(result.hadFailures, isTrue);
    expect(result.copiesDeleted, 0);
  });
}

class _ThrowingCopyRepository extends MockCopyRepository {
  @override
  Future<List<Copy>> getBookCopies(String bookId) async =>
      throw Exception('backend down');
}
