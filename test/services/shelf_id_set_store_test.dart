import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/services/shelf_id_set_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShelfIdSetStore.prefs = SharedPreferences.getInstance;
  });

  test('a set comes back as saved', () async {
    const store = ShelfIdSetStore.collapsed;
    expect(await store.load(), isEmpty);

    await store.save({'u2', 'u1'});

    expect(await store.load(), {'u1', 'u2'});
  });

  test('each set lives under its own key', () async {
    await ShelfIdSetStore.collapsed.save({'u1'});
    await ShelfIdSetStore.shelfOrder.save({'u2', 'u3'});
    await ShelfIdSetStore.shelfOrder.save({'u3'});

    expect(await ShelfIdSetStore.collapsed.load(), {'u1'});
    expect(await ShelfIdSetStore.shelfOrder.load(), {'u3'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('shelf_order_ids'), ['u3']);
  });

  test('storage that fails keeps nothing and throws nothing', () async {
    ShelfIdSetStore.prefs = () async => throw Exception('no storage');

    await ShelfIdSetStore.shelfOrder.save({'u1'});
    expect(await ShelfIdSetStore.shelfOrder.load(), isEmpty);
  });
}
