import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/services/external_suggestion_dismissal_service.dart';

/// Freezes the ADR-060 section 4.5 store contract: ordered FIFO list
/// capped at 500 entries, namespaced keys, undo removal. The cap is the
/// storage policy (bounded structures) applied to a store that can only
/// grow one tap at a time.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('dismiss appends and restore removes', () async {
    await ExternalSuggestionDismissalService.dismiss('isbn:9782070541270');
    await ExternalSuggestionDismissalService.dismiss('series:Q8337:4');
    expect(await ExternalSuggestionDismissalService.loadDismissed(), [
      'isbn:9782070541270',
      'series:Q8337:4',
    ]);

    await ExternalSuggestionDismissalService.restore('isbn:9782070541270');
    expect(await ExternalSuggestionDismissalService.loadDismissed(), [
      'series:Q8337:4',
    ]);
  });

  test('re-dismissing moves the entry to the young end, no duplicate', () async {
    await ExternalSuggestionDismissalService.dismiss('isbn:1');
    await ExternalSuggestionDismissalService.dismiss('isbn:2');
    await ExternalSuggestionDismissalService.dismiss('isbn:1');
    expect(await ExternalSuggestionDismissalService.loadDismissed(), [
      'isbn:2',
      'isbn:1',
    ]);
  });

  test('FIFO cap evicts the oldest entries past 500', () async {
    SharedPreferences.setMockInitialValues({
      ExternalSuggestionDismissalService.dismissedKeysKey: [
        for (var i = 0; i < ExternalSuggestionDismissalService.maxEntries; i++)
          'isbn:$i',
      ],
    });

    await ExternalSuggestionDismissalService.dismiss('isbn:new');

    final keys = await ExternalSuggestionDismissalService.loadDismissed();
    expect(keys.length, ExternalSuggestionDismissalService.maxEntries);
    expect(keys.first, 'isbn:1', reason: 'oldest entry evicted');
    expect(keys.last, 'isbn:new');
  });
}
