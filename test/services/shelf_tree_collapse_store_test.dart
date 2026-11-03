import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/services/shelf_tree_collapse_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ShelfTreeCollapseStore.prefs = SharedPreferences.getInstance;
  });

  test('the folded shelves come back as saved', () async {
    expect(await ShelfTreeCollapseStore.load(), isEmpty);

    await ShelfTreeCollapseStore.save({'u2', 'u1'});

    expect(await ShelfTreeCollapseStore.load(), {'u1', 'u2'});
  });

  test('storage that fails folds nothing and throws nothing', () async {
    ShelfTreeCollapseStore.prefs = () async => throw Exception('no storage');

    await ShelfTreeCollapseStore.save({'u1'});
    expect(await ShelfTreeCollapseStore.load(), isEmpty);
  });
}
