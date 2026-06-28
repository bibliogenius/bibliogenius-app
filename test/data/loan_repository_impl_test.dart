import 'package:bibliogenius/data/repositories_impl/loan_repository_impl.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_classes.dart';

class _StubApiService extends MockApiService {
  dynamic borrowedResponseData;

  @override
  Future<Response> getBorrowedCopies() async {
    return Response(
      requestOptions: RequestOptions(path: '/api/copies/borrowed'),
      statusCode: 200,
      data: borrowedResponseData,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StubApiService api;
  late LoanRepositoryImpl repo;

  setUp(() {
    api = _StubApiService();
    repo = LoanRepositoryImpl(api);
  });

  group('LoanRepositoryImpl.getBorrowedCopies', () {
    test('parses loans key from backend payload (ADR-034 shape)', () async {
      // Mirrors what `/api/copies/borrowed` actually returns (see
      // bibliogenius/src/api/copy.rs:159 get_borrowed_copies).
      api.borrowedResponseData = {
        'loans': [
          {
            'id': 1,
            'book_id': 10,
            'title': 'Book A',
            'status': 'borrowed',
            'borrow_source': 'contact',
          },
          {
            'id': 2,
            'book_id': 11,
            'title': 'Book B',
            'status': 'borrowed',
            'borrow_source': 'peer',
          },
        ],
        'total': 2,
      };

      final result = await repo.getBorrowedCopies();

      expect(result.length, 2);
      expect(result[0].id, '1');
      expect(result[0].bookId, '10');
      expect(result[1].borrowSource, 'peer');
    });

    test('returns empty list when loans key is absent', () async {
      api.borrowedResponseData = {'total': 0};
      final result = await repo.getBorrowedCopies();
      expect(result, isEmpty);
    });

    test('accepts a raw list payload as fallback', () async {
      api.borrowedResponseData = [
        {'id': 5, 'book_id': 20, 'status': 'borrowed'},
      ];
      final result = await repo.getBorrowedCopies();
      expect(result.length, 1);
      expect(result.first.id, '5');
    });

    test('tolerates missing library_id in payload', () async {
      // The backend payload intentionally omits library_id for borrowed
      // copies; Copy.fromJson requires a non-null int, so the repo must
      // inject a default rather than crash.
      api.borrowedResponseData = {
        'loans': [
          {'id': 7, 'book_id': 30, 'status': 'borrowed'},
        ],
      };
      final result = await repo.getBorrowedCopies();
      expect(result.length, 1);
      expect(result.first.libraryId, 0);
    });
  });
}
