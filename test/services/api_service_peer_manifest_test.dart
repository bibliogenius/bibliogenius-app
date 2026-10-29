import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/peer_sync_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the local backend answering the relay library request
/// with a failure status and JSON body.
class _RefusingApiService extends ApiService {
  _RefusingApiService(this.status, this.body)
    : super(AuthService(), baseUrl: 'http://localhost:0');

  final int status;
  final Map<String, dynamic> body;

  @override
  Future<Response> relayLibraryRequest({
    required int peerId,
    required String requestType,
    int? cursor,
    int? limit,
    String? query,
  }) async {
    final options = RequestOptions(path: '/api/peers/relay/library_request');
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: options,
        statusCode: status,
        data: body,
      ),
    );
  }
}

void main() {
  group('requestPeerManifest on a 502 from the local backend', () {
    test('reports a peer the hub confirmed has new keys', () async {
      // The backend refuses to relay to such a peer and answers at once; the
      // screen must tell the owner to pair again instead of showing the
      // generic offline state.
      final api = _RefusingApiService(502, {
        'error': 'The peer has new keys, pair it again',
        'code': peerKeysChangedCode,
      });

      final manifest = await api.requestPeerManifest(7);

      expect(manifest, {'error': peerKeysChangedCode});
    });

    test('keeps reporting an unreachable peer otherwise', () async {
      final api = _RefusingApiService(502, {
        'error': 'peer_unreachable',
        'message': 'mailbox expired',
      });

      final manifest = await api.requestPeerManifest(7);

      expect(manifest, {'error': 'peer_unreachable'});
    });
  });
}
