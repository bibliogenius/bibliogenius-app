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

  test('the shelf order sits beside the sort, leaving it untouched', () async {
    // A reader in "Title Z-A" saves a shelf order: inside a shelf the list
    // decides to honour it, and outside the shelf "Title Z-A" is still there.
    SharedPreferences.setMockInitialValues({
      'library_sort_by': 'title',
      'library_sort_dir': 'desc',
    });
    final provider = SortPreferenceProvider();
    await provider.load();
    expect(provider.shelfOrder, isFalse);

    await provider.setShelfOrder(true);
    expect(provider.shelfOrder, isTrue);
    expect(provider.sortBy, SortBy.title);
    expect(provider.sortDir, SortDir.desc);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('library_shelf_order'), isTrue);
    expect(prefs.getString('library_sort_by'), 'title');
    expect(prefs.getString('library_sort_dir'), 'desc');

    // And it survives a relaunch.
    final reloaded = SortPreferenceProvider();
    await reloaded.load();
    expect(reloaded.shelfOrder, isTrue);
    expect(reloaded.sortBy, SortBy.title);
    expect(reloaded.sortDir, SortDir.desc);
  });

  test('picking a field sort notifies once and drops the shelf order',
      () async {
    SharedPreferences.setMockInitialValues({'library_shelf_order': true});
    final provider = SortPreferenceProvider();
    await provider.load();
    var notifyCount = 0;
    provider.addListener(() => notifyCount++);

    await provider.setFieldSort(SortBy.title, SortDir.desc);
    expect(notifyCount, 1, reason: 'field, direction and flag change as one');
    expect(provider.sortBy, SortBy.title);
    expect(provider.sortDir, SortDir.desc);
    expect(provider.shelfOrder, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('library_sort_by'), 'title');
    expect(prefs.getString('library_sort_dir'), 'desc');
    expect(prefs.getBool('library_shelf_order'), isFalse);

    await provider.setFieldSort(SortBy.title, SortDir.desc);
    expect(notifyCount, 1, reason: 'same choice must not notify');
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
