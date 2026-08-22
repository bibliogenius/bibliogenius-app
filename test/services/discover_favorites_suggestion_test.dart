import 'package:bibliogenius/services/discover_dismissal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The favorites-marker Discover tile (ADR-064) rides the existing per-id
// dismissal mechanics: its id must be registered (so the legacy-flag
// migration silences it for users who closed the old section) and its
// dismissal must persist like the others.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the favorites id is registered and stable', () {
    expect(DiscoverSuggestionIds.favoritesMarker, 'favorites_marker');
    expect(
      DiscoverSuggestionIds.all,
      contains(DiscoverSuggestionIds.favoritesMarker),
    );
  });

  test('dismissing the favorites tile persists', () async {
    expect(await DiscoverDismissalService.loadDismissed(), isEmpty);

    await DiscoverDismissalService.dismiss(
      DiscoverSuggestionIds.favoritesMarker,
    );

    final dismissed = await DiscoverDismissalService.loadDismissed();
    expect(dismissed, contains(DiscoverSuggestionIds.favoritesMarker));
  });

  test('the legacy global flag also silences the favorites tile', () async {
    SharedPreferences.setMockInitialValues({
      DiscoverDismissalService.legacyDismissedAllKey: true,
    });
    final dismissed = await DiscoverDismissalService.loadDismissed();
    expect(dismissed, contains(DiscoverSuggestionIds.favoritesMarker));
  });
}
