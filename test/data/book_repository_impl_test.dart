import 'package:bibliogenius/data/repositories_impl/book_repository_impl.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/mock_classes.dart';

class _StubApiService extends MockApiService {
  Map<String, dynamic>? lastUpdatePayload;

  @override
  Future<Response> updateBook(
    String uuid,
    Map<String, dynamic> bookData,
  ) async {
    lastUpdatePayload = bookData;
    return Response(
      requestOptions: RequestOptions(path: '/api/books/$uuid'),
      statusCode: 200,
      data: {'id': uuid, 'title': 'T', 'cover_url': bookData['cover_url']},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StubApiService api;
  late BookRepositoryImpl repo;

  setUp(() {
    api = _StubApiService();
    repo = BookRepositoryImpl(api);
  });

  group('BookRepositoryImpl.updateBook cover_url normalization', () {
    // A cover the user has just captured is written to
    // `{AppSupport}/covers/<uuid>.jpg` and the screen hands the repository the
    // absolute path it needs for its own preview and cache eviction. The
    // absolute prefix is device-specific and vestigial (every reader rebuilds
    // it from the current app-support directory), so only the basename is
    // persisted: two devices then store the same value for the same cover
    // (ADR-044 Addendum A.4).
    test('persists a freshly captured cover by its basename', () async {
      await repo.updateBook('42', {
        'cover_url':
            '/var/mobile/Containers/Data/Application/UUID/Library/Application Support/covers/42.jpg',
      });
      expect(api.lastUpdatePayload!['cover_url'], '42.jpg');
    });

    test('leaves a remote cover URL untouched', () async {
      await repo.updateBook('42', {'cover_url': 'https://cdn/42.jpg'});
      expect(api.lastUpdatePayload!['cover_url'], 'https://cdn/42.jpg');
    });

    test('leaves a peer cover path untouched', () async {
      await repo.updateBook('42', {'cover_url': '/api/books/42/cover'});
      expect(api.lastUpdatePayload!['cover_url'], '/api/books/42/cover');
    });

    test(
      'leaves a path whose basename is not the canonical name untouched',
      () async {
        const temp = '/Users/x/Application Support/covers/temp_abcd.jpg';
        await repo.updateBook('42', {'cover_url': temp});
        expect(api.lastUpdatePayload!['cover_url'], temp);
      },
    );

    test('passes a null cover through (cover removal)', () async {
      await repo.updateBook('42', {'cover_url': null});
      expect(api.lastUpdatePayload!.containsKey('cover_url'), isTrue);
      expect(api.lastUpdatePayload!['cover_url'], isNull);
    });

    test('leaves a payload without cover_url untouched', () async {
      await repo.updateBook('42', {'title': 'T'});
      expect(api.lastUpdatePayload!.containsKey('cover_url'), isFalse);
      expect(api.lastUpdatePayload!['title'], 'T');
    });

    test('does not mutate the caller-owned map', () async {
      final payload = <String, dynamic>{
        'cover_url': '/Users/x/Application Support/covers/42.jpg',
      };
      await repo.updateBook('42', payload);
      expect(
        payload['cover_url'],
        '/Users/x/Application Support/covers/42.jpg',
      );
    });
  });
}
