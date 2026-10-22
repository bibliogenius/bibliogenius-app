import 'package:bibliogenius/services/peer_sync_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// The local backend answers a sync that found no lane with a 502. When the
// peer answers under new keys it names it in `code`, and only then may the
// owner be told to pair it again.
DioException _failedSync(Object? data) {
  final options = RequestOptions(path: '/api/peers/sync_by_url');
  return DioException(
    requestOptions: options,
    response: Response(requestOptions: options, statusCode: 502, data: data),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  test('a 502 naming new keys is recognised', () {
    final error = _failedSync({
      'error': 'The peer answers with other keys, pair it again',
      'code': 'peer_keys_changed',
    });
    expect(peerSyncErrorCode(error), peerKeysChangedCode);
  });

  test('any other failure carries no code', () {
    expect(
      peerSyncErrorCode(
        _failedSync({'error': 'Another library answers at the peer address'}),
      ),
      isNull,
    );
    expect(peerSyncErrorCode(_failedSync('plain text body')), isNull);
    expect(peerSyncErrorCode(_failedSync({'code': 42})), isNull);
    expect(
      peerSyncErrorCode(
        DioException(
          requestOptions: RequestOptions(path: '/api/peers/sync_by_url'),
          type: DioExceptionType.receiveTimeout,
        ),
      ),
      isNull,
    );
    expect(peerSyncErrorCode(Exception('boom')), isNull);
  });
}
