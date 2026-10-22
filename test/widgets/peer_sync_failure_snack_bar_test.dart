import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/peer_sync_error.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/peer_sync_failure_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A manual sync that failed because the peer has new keys must tell the
// owner to pair again, and stay up long enough to be read; any other
// failure keeps the generic message.
void main() {
  late ThemeProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'peer_keys_changed': 'Pair it again',
        'sync_failed': 'Sync failed',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  Future<SnackBar> barFor(WidgetTester tester, Object error) async {
    late SnackBar bar;
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: Builder(
            builder: (context) {
              bar = peerSyncFailureSnackBar(context, error);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return bar;
  }

  String textOf(SnackBar bar) => (bar.content as Text).data!;

  testWidgets('new keys ask for a new pairing and stay up longer', (
    tester,
  ) async {
    final bar = await barFor(tester, const PeerKeysChangedException());
    expect(textOf(bar), 'Pair it again');
    expect(bar.duration, const Duration(seconds: 10));
  });

  testWidgets('any other failure keeps the generic message', (tester) async {
    final bar = await barFor(tester, Exception('boom'));
    expect(textOf(bar), 'Sync failed');
    expect(bar.duration, const Duration(milliseconds: 4000));
  });
}
