// Guard: rule A2 of SECURITY_GUIDELINES.md, no token or secret in a log,
// debug builds included (they are handed to testers).
//
// Pairing, connection and relay setup answers carry relay write tokens or a
// session secret; printing their whole body put a production mailbox token
// in the Flutter console during the 2026-10-20 recette.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Answers whose whole body may be logged: none carries a secret.
const _bodyLogsWithoutSecrets = [
  'createCopy error details', // local server error message
  'getCollectionBooks: Unexpected response format', // book list
  'autoApproveAllPeers', // approved peer count
  'Relay status (local)', // relay URL, mailbox id, counters
  'requestPeerManifest', // peer error message
  'getBooks: Unexpected response format', // book list
];

final _logCall = RegExp(r'\b(debugPrint|print|developer\.log|log)\s*\(');

/// A response body interpolated in any form: `${r.data}`, `${r.data['x']}`,
/// `${r.data.toString()}`, `${jsonEncode(r.data)}`. A length or a type is
/// fine.
final _responseBody = RegExp(
  r'\$\{[^}]*\.data\b(?!\??\.(length|runtimeType|isEmpty|isNotEmpty)\b)',
);

/// A token, recovery code or secret, as a variable, a field or a map key.
final _secretValue = RegExp(
  r'\$\{?[^}\s]*(write_?token|read_?token|recovery_?code|secret|password|\btoken\b)',
  caseSensitive: false,
);

/// A raw link or scanned string: an invite carries the inviter's relay
/// write token, so links go through `describeLinkForLog`.
final _rawLink = RegExp(
  r'\$\{?\s*(uri|link|shortUrl|raw|rawValue|inviteUrl|inviteLink|deepLink)\b',
);

/// Every log call of [source] with its line, parentheses balanced.
Iterable<(int, String)> _logCalls(String source) sync* {
  for (final m in _logCall.allMatches(source)) {
    var i = m.end;
    var depth = 1;
    while (depth > 0 && i < source.length) {
      final c = source[i];
      if (c == '(') depth++;
      if (c == ')') depth--;
      i++;
    }
    final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
    yield (line, source.substring(m.start, i));
  }
}

void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('lib/src/rust/'))
      .toList();

  test('the patterns catch the known shapes and spare the safe ones', () {
    for (final leak in [
      r"debugPrint('${cfg.writeToken}')",
      r"debugPrint('${data['write_token']}')",
      r"debugPrint('$recoveryCode')",
      r"debugPrint('$token')",
    ]) {
      expect(_secretValue.hasMatch(leak), isTrue, reason: leak);
    }
    for (final leak in [
      r"debugPrint('${resp.data}')",
      r"debugPrint('${resp.data['x']}')",
      r"debugPrint('${jsonEncode(resp.data)}')",
      r"debugPrint('${resp.data.toString()}')",
    ]) {
      expect(_responseBody.hasMatch(leak), isTrue, reason: leak);
    }
    for (final leak in [
      r"debugPrint('$uri')",
      r'''debugPrint('${uri ?? "null"}')''',
      r"debugPrint('fetching $shortUrl')",
      r"debugPrint('${raw.substring(0, 80)}')",
    ]) {
      expect(_rawLink.hasMatch(leak), isTrue, reason: leak);
    }
    for (final safe in [
      r"debugPrint('${resp.data?.length ?? 0} books')",
      r"debugPrint('${describeLinkForLog(uri.toString())}')",
      r"debugPrint('status=${resp.statusCode}')",
      r"debugPrint('relay_creds=$hasRelayCreds')",
    ]) {
      expect(_responseBody.hasMatch(safe), isFalse, reason: safe);
      expect(_rawLink.hasMatch(safe), isFalse, reason: safe);
      expect(_secretValue.hasMatch(safe), isFalse, reason: safe);
    }
  });

  test('no log call prints a response body that may carry a secret', () {
    final offenders = <String>[];
    for (final file in files) {
      for (final (line, call) in _logCalls(file.readAsStringSync())) {
        if (!_responseBody.hasMatch(call)) continue;
        if (_bodyLogsWithoutSecrets.any(call.contains)) continue;
        offenders.add('${file.path}:$line');
      }
    }
    expect(offenders, isEmpty);
  });

  test('no log call prints a raw link or scanned string', () {
    final offenders = <String>[];
    for (final file in files) {
      for (final (line, call) in _logCalls(file.readAsStringSync())) {
        if (_rawLink.hasMatch(call)) offenders.add('${file.path}:$line');
      }
    }
    expect(offenders, isEmpty);
  });

  test('no log call interpolates a token, a recovery code or a secret', () {
    final offenders = <String>[];
    for (final file in files) {
      for (final (line, call) in _logCalls(file.readAsStringSync())) {
        if (_secretValue.hasMatch(call)) offenders.add('${file.path}:$line');
      }
    }
    expect(offenders, isEmpty);
  });
}
