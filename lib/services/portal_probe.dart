import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/library_portals.dart';

/// Lenient witness probe behind the connection wizard's "Check" button:
/// fetches the result page the user pasted and looks for the witness
/// title in the body. Reads at most [maxBytes] of the response so a
/// pathological site cannot balloon memory, and treats every failure as
/// "unconfirmed" rather than an error: an OPAC may not hold the witness
/// edition, or render its results client-side.
Future<bool> probePortalWitness(
  String url, {
  Dio? dio,
  int maxBytes = 256 * 1024,
}) async {
  final ownsClient = dio == null;
  final client =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
  try {
    final response = await client.get<ResponseBody>(
      url,
      options: Options(responseType: ResponseType.stream),
    );
    final stream = response.data?.stream;
    if (stream == null) return false;
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length >= maxBytes) break;
    }
    final body = utf8.decode(bytes, allowMalformed: true).toLowerCase();
    return body.contains(libraryWitnessNeedle);
  } catch (_) {
    return false;
  } finally {
    // Only the client created here is ours to close; an injected one
    // belongs to the caller.
    if (ownsClient) client.close();
  }
}
