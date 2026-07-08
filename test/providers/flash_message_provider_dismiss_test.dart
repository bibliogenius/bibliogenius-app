import 'package:bibliogenius/providers/flash_message_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FlashMessageDefinition _definition(String key, {bool persistDismissal = true}) {
  return FlashMessageDefinition(
    key: key,
    textKey: key,
    condition: (_) => true,
    persistDismissal: persistDismissal,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('dismiss persists to SharedPreferences by default', () async {
    final provider = FlashMessageProvider();
    provider.register(_definition('flash_persistent'));

    await provider.dismiss('flash_persistent');

    expect(provider.isDismissed('flash_persistent'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('flash_persistent_dismissed'), isTrue);
  });

  test('persistDismissal: false hides for the session only', () async {
    final provider = FlashMessageProvider();
    provider.register(_definition('flash_port_conflict', persistDismissal: false));

    await provider.dismiss('flash_port_conflict');

    // Hidden for the rest of this session...
    expect(provider.isDismissed('flash_port_conflict'), isTrue);
    // ...but nothing written: a fresh launch re-evaluates the condition.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('flash_port_conflict_dismissed'), isNull);

    // Simulate the next launch: a new provider loading the same prefs.
    final nextLaunch = FlashMessageProvider();
    nextLaunch.register(
      _definition('flash_port_conflict', persistDismissal: false),
    );
    await nextLaunch.loadDismissedFlags();
    expect(nextLaunch.isDismissed('flash_port_conflict'), isFalse);
  });
}
