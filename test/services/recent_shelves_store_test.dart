import 'package:bibliogenius/services/recent_shelves_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('pushRecentShelves', () {
    test('the last shelf chosen comes first', () {
      expect(pushRecentShelves(['Bureau'], ['Salon', 'Polar']), [
        'Polar',
        'Salon',
        'Bureau',
      ]);
    });

    test('keeps five names at most, dropping the oldest', () {
      final result = pushRecentShelves(['E', 'D', 'C', 'B', 'A'], ['F', 'G']);
      expect(result, ['G', 'F', 'E', 'D', 'C']);
      expect(result, hasLength(RecentShelvesStore.limit));
    });

    test('a name chosen again moves to the front, without a duplicate', () {
      expect(pushRecentShelves(['Salon', 'Polar', 'Cave'], ['Polar ']), [
        'Polar',
        'Salon',
        'Cave',
      ]);
    });

    test('names compare exactly: "polar" is not "Polar"', () {
      // Shelf names are unique byte for byte in the database, so two
      // shelves can differ by case or accents alone; each is its own entry.
      expect(pushRecentShelves(['Polar', 'Etagere'], ['polar', 'Étagère']), [
        'Étagère',
        'polar',
        'Polar',
        'Etagere',
      ]);
    });

    test('a name repeated in one save counts once', () {
      expect(pushRecentShelves([], ['Salon', 'Polar', 'Salon']), [
        'Salon',
        'Polar',
      ]);
    });

    test('blank names are ignored', () {
      expect(pushRecentShelves(['Salon'], ['', '  ']), ['Salon']);
    });
  });

  group('RecentShelvesStore', () {
    test('starts empty', () async {
      expect(await RecentShelvesStore.load(), isEmpty);
    });

    test('records under its own local preference', () async {
      await RecentShelvesStore.record(['Salon', 'Polar']);
      await RecentShelvesStore.record(['Cave']);

      expect(await RecentShelvesStore.load(), ['Cave', 'Polar', 'Salon']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_shelf_names'), [
        'Cave',
        'Polar',
        'Salon',
      ]);
    });

    test(
      'a failing write is swallowed: the shortcut never fails a save',
      () async {
        RecentShelvesStore.prefs = () async => throw StateError('disk full');
        addTearDown(
          () => RecentShelvesStore.prefs = SharedPreferences.getInstance,
        );

        await expectLater(RecentShelvesStore.record(['Salon']), completes);
        expect(await RecentShelvesStore.load(), isEmpty);
      },
    );

    test('recording nothing leaves the list as it was', () async {
      await RecentShelvesStore.record(['Salon']);
      await RecentShelvesStore.record(const []);
      expect(await RecentShelvesStore.load(), ['Salon']);
    });
  });
}
