import 'package:bibliogenius/services/discover_dismissal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install has dismissed nothing', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await DiscoverDismissalService.loadDismissed(), isEmpty);
  });

  test('dismissing one suggestion leaves the others visible', () async {
    SharedPreferences.setMockInitialValues({});

    final after = await DiscoverDismissalService.dismiss(
      DiscoverSuggestionIds.publicDirectory,
    );

    expect(after, {DiscoverSuggestionIds.publicDirectory});
    expect(
      after.contains(DiscoverSuggestionIds.localWifi),
      isFalse,
      reason:
          'closing the directory suggestion must not silence the local network one',
    );
    expect(await DiscoverDismissalService.loadDismissed(), {
      DiscoverSuggestionIds.publicDirectory,
    });
  });

  test('dismissals accumulate across calls', () async {
    SharedPreferences.setMockInitialValues({});

    await DiscoverDismissalService.dismiss(DiscoverSuggestionIds.localWifi);
    final after = await DiscoverDismissalService.dismiss(
      DiscoverSuggestionIds.readingLanguages,
    );

    expect(after, {
      DiscoverSuggestionIds.localWifi,
      DiscoverSuggestionIds.readingLanguages,
    });
  });

  test('dismissing the same suggestion twice is idempotent', () async {
    SharedPreferences.setMockInitialValues({});

    await DiscoverDismissalService.dismiss(DiscoverSuggestionIds.localWifi);
    final after = await DiscoverDismissalService.dismiss(
      DiscoverSuggestionIds.localWifi,
    );

    expect(after, {DiscoverSuggestionIds.localWifi});
  });

  test('the legacy global flag migrates to every known id, once', () async {
    SharedPreferences.setMockInitialValues({
      DiscoverDismissalService.legacyDismissedAllKey: true,
    });

    expect(
      await DiscoverDismissalService.loadDismissed(),
      DiscoverSuggestionIds.all,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(DiscoverDismissalService.legacyDismissedAllKey),
      isNull,
      reason: 'the legacy flag must be consumed so it cannot re-hide new ids',
    );
    expect(
      prefs.getStringList(DiscoverDismissalService.dismissedIdsKey)?.toSet(),
      DiscoverSuggestionIds.all,
    );
  });

  test('a legacy flag set to false dismisses nothing', () async {
    SharedPreferences.setMockInitialValues({
      DiscoverDismissalService.legacyDismissedAllKey: false,
    });

    expect(await DiscoverDismissalService.loadDismissed(), isEmpty);
  });

  test(
    'after the migration a single dismissal no longer hides everything',
    () async {
      SharedPreferences.setMockInitialValues({});

      await DiscoverDismissalService.dismiss(
        DiscoverSuggestionIds.publicDirectory,
      );
      final remaining = DiscoverSuggestionIds.all.difference(
        await DiscoverDismissalService.loadDismissed(),
      );

      expect(remaining, {
        DiscoverSuggestionIds.localWifi,
        DiscoverSuggestionIds.readingLanguages,
        DiscoverSuggestionIds.favoritesMarker,
      });
    },
  );
}
