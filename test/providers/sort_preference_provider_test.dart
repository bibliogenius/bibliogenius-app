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
