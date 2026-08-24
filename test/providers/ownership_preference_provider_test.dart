import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/utils/book_filters.dart';

/// ADR-063: the ownership axis is the ONLY filter this app remembers between
/// sessions. Sort is remembered too, but a sort reorders where a filter
/// hides, and a reader who has forgotten a filter believes their books are
/// gone. This axis is the safe one to persist: its widest value, "all", hides
/// nothing at all, so the worst an forgotten choice can do is show too much.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nothing remembered means no explicit choice, so the default holds', () {
    SharedPreferences.setMockInitialValues({});
    final provider = OwnershipPreferenceProvider();

    expect(provider.scope, isNull);
    expect(
      resolveOwnershipScope(explicit: provider.scope, status: null),
      OwnershipScope.library,
    );
  });

  test('a remembered choice comes back and wins over the default', () async {
    SharedPreferences.setMockInitialValues({
      'library_ownership_scope': OwnershipScope.all,
    });
    final provider = OwnershipPreferenceProvider();
    await provider.load();

    expect(provider.scope, OwnershipScope.all);
    expect(
      resolveOwnershipScope(explicit: provider.scope, status: null),
      OwnershipScope.all,
    );
  });

  test('setting then clearing brings the default back', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = OwnershipPreferenceProvider();
    await provider.load();

    await provider.setScope(OwnershipScope.all);
    expect(provider.scope, OwnershipScope.all);

    final reloaded = OwnershipPreferenceProvider();
    await reloaded.load();
    expect(reloaded.scope, OwnershipScope.all, reason: 'It was persisted.');

    await provider.setScope(null);
    expect(provider.scope, isNull);

    final afterClear = OwnershipPreferenceProvider();
    await afterClear.load();
    expect(afterClear.scope, isNull, reason: 'The key was removed, not blanked.');
  });

  test('a value the app no longer knows fails closed to the default', () async {
    // A downgrade, a hand-edited preference file or a renamed scope must not
    // leave the library filtering on a string nothing understands.
    SharedPreferences.setMockInitialValues({
      'library_ownership_scope': 'shelf_of_dreams',
    });
    final provider = OwnershipPreferenceProvider();
    await provider.load();

    expect(provider.scope, isNull);
  });

  test('it notifies, so a screen holding the axis can follow', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = OwnershipPreferenceProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);

    await provider.load();
    await provider.setScope(OwnershipScope.notOwned);
    await provider.setScope(OwnershipScope.notOwned);

    expect(notifications, 2, reason: 'Load and the real change, not the no-op.');
  });
}
