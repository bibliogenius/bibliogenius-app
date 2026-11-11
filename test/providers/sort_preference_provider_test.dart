import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/sort_preference_provider.dart';
import 'package:bibliogenius/utils/book_sort.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to author + asc when nothing is persisted', () async {
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.sortBy, SortBy.author);
    expect(provider.sortDir, SortDir.asc);
    expect(provider.isLoaded, true);
  });

  test('loads persisted values', () async {
    SharedPreferences.setMockInitialValues({
      'library_sort_by': 'title',
      'library_sort_dir': 'desc',
    });
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.sortBy, SortBy.title);
    expect(provider.sortDir, SortDir.desc);
  });

  test('restores the date-added sort', () async {
    SharedPreferences.setMockInitialValues({
      'library_sort_by': 'addedAt',
      'library_sort_dir': 'desc',
    });
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.sortBy, SortBy.addedAt);
    expect(provider.sortDir, SortDir.desc);
  });

  test('ignores unknown persisted values and falls back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      'library_sort_by': 'author_surname',
      'library_sort_dir': 'random',
    });
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.sortBy, SortBy.author);
    expect(provider.sortDir, SortDir.asc);
  });

  test('the shelf order sits beside the sort, shelf by shelf, leaving the '
      'sort untouched', () async {
    // A reader in "Title Z-A" saves the order of one shelf: that shelf
    // honours it, the others and the rest of the library keep "Title Z-A".
    SharedPreferences.setMockInitialValues({
      'library_sort_by': 'title',
      'library_sort_dir': 'desc',
    });
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.shelfOrderFor('salon'), isFalse);

    await provider.setShelfOrder('salon', true);
    expect(provider.shelfOrderFor('salon'), isTrue);
    expect(provider.shelfOrderFor('bureau'), isFalse);
    expect(provider.shelfOrderFor(null), isFalse);
    expect(provider.sortBy, SortBy.title);
    expect(provider.sortDir, SortDir.desc);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('shelf_order_ids'), ['salon']);
    expect(prefs.getString('library_sort_by'), 'title');
    expect(prefs.getString('library_sort_dir'), 'desc');

    // And it survives a relaunch.
    final reloaded = SortPreferenceProvider();
    await reloaded.load();
    expect(reloaded.shelfOrderFor('salon'), isTrue);
    expect(reloaded.shelfOrderFor('bureau'), isFalse);
    expect(reloaded.sortBy, SortBy.title);
    expect(reloaded.sortDir, SortDir.desc);
  });

  test('picking a field sort in a shelf notifies once and drops that '
      "shelf's order only", () async {
    SharedPreferences.setMockInitialValues({
      'shelf_order_ids': ['salon', 'bureau'],
    });
    final provider = SortPreferenceProvider();
    await provider.load();
    var notifyCount = 0;
    provider.addListener(() => notifyCount++);

    await provider.setFieldSort(SortBy.title, SortDir.desc, shelfId: 'bureau');
    expect(notifyCount, 1, reason: 'field, direction and flag change as one');
    expect(provider.sortBy, SortBy.title);
    expect(provider.sortDir, SortDir.desc);
    expect(provider.shelfOrderFor('bureau'), isFalse);
    expect(provider.shelfOrderFor('salon'), isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_sort_by'), 'title');
    expect(prefs.getString('library_sort_dir'), 'desc');
    expect(prefs.getStringList('shelf_order_ids'), ['salon']);

    await provider.setFieldSort(SortBy.title, SortDir.desc, shelfId: 'bureau');
    expect(notifyCount, 1, reason: 'same choice must not notify');
  });

  test('picking a field sort outside a shelf leaves every shelf order',
      () async {
    SharedPreferences.setMockInitialValues({
      'shelf_order_ids': ['salon'],
    });
    final provider = SortPreferenceProvider();
    await provider.load();

    await provider.setFieldSort(SortBy.title, SortDir.asc);

    expect(provider.shelfOrderFor('salon'), isTrue);
  });

  test('shelves that no longer exist are forgotten', () async {
    SharedPreferences.setMockInitialValues({
      'shelf_order_ids': ['salon', 'gone'],
    });
    final provider = SortPreferenceProvider();
    await provider.load();

    await provider.retainShelfOrders({'salon', 'bureau'});

    expect(provider.shelfOrderFor('gone'), isFalse);
    expect(provider.shelfOrderFor('salon'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('shelf_order_ids'), ['salon']);
  });

  test('a persisted shelf value for the field is read as author', () async {
    // The field never holds the shelf order; a stray value falls back.
    SharedPreferences.setMockInitialValues({'library_sort_by': 'shelf'});
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.sortBy, SortBy.author);
  });

  test('setSortBy persists and notifies', () async {
    final provider = SortPreferenceProvider();
    await provider.load();

    var notifyCount = 0;
    provider.addListener(() => notifyCount++);

    await provider.setSortBy(SortBy.title);
    expect(provider.sortBy, SortBy.title);
    expect(notifyCount, 1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_sort_by'), 'title');

    await provider.setSortBy(SortBy.title);
    expect(notifyCount, 1, reason: 'same value must not notify');
  });

  test('toggleDirection flips and persists', () async {
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.sortDir, SortDir.asc);

    await provider.toggleDirection();
    expect(provider.sortDir, SortDir.desc);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_sort_dir'), 'desc');

    await provider.toggleDirection();
    expect(provider.sortDir, SortDir.asc);
  });
}
