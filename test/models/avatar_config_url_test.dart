import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/avatar_config.dart';

void main() {
  group('AvatarConfig.toUrl', () {
    test('builds the DiceBear URL for a normal style', () {
      final url = const AvatarConfig(
        seed: 'bibliogenius',
        style: 'avataaars',
      ).toUrl(size: 72);

      expect(url, startsWith('https://api.dicebear.com/7.x/avataaars/png?'));
      expect(url, contains('seed=bibliogenius'));
      expect(url, contains('size=72'));
    });

    test('maps a preset style onto its API style', () {
      final url = const AvatarConfig(seed: 'man', style: 'man').toUrl();

      expect(url, startsWith('https://api.dicebear.com/7.x/avataaars/'));
    });

    test('returns the bundled asset for the genie style', () {
      final url = const AvatarConfig(seed: 'genie', style: 'genie').toUrl();

      expect(url, 'assets/genie_mascot.jpg');
    });

    test('a style parsed from remote data cannot steer path or query', () {
      // A config can come straight from a hub profile or a peer record, so
      // `style` is remote input. Unencoded, it used to be interpolated into
      // the URL path as-is.
      final url = const AvatarConfig(
        seed: 'bibliogenius',
        style: '../../evil/png?x=',
      ).toUrl();

      expect(
        Uri.parse(url).host,
        'api.dicebear.com',
        reason: 'The host prefix is fixed, it must stay unreachable.',
      );
      expect(
        Uri.parse(url).pathSegments,
        ['7.x', '../../evil/png?x=', 'png'],
        reason:
            'The style must land in a single, escaped path segment instead of '
            'adding segments or opening the query string.',
      );
      expect(
        Uri.parse(url).queryParameters.keys,
        containsAll(<String>['seed', 'size']),
        reason: 'No injected query parameter survives the encoding.',
      );
    });
  });
}
