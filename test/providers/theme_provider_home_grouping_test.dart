import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The home page groups its covers either by collection or by reading status,
// never both: the reading-status sections only exist in the plain covers
// grid, so a library opening grouped by collection would hide them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('grouping by reading status turns grouping by collection off', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    await provider.setGroupByCollections(true);

    await provider.setGroupByReadingStatus(true);

    expect(provider.groupByReadingStatus, isTrue);
    expect(provider.groupByCollections, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('groupByCollections'), isFalse);
  });

  test('grouping by collection turns grouping by reading status off', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    await provider.setGroupByReadingStatus(true);

    await provider.setGroupByCollections(true);

    expect(provider.groupByCollections, isTrue);
    expect(provider.groupByReadingStatus, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('groupByReadingStatus'), isFalse);
  });

  test('turning one grouping off leaves the other alone', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider();
    await provider.setGroupByReadingStatus(true);

    await provider.setGroupByCollections(false);

    expect(provider.groupByReadingStatus, isTrue);
  });

  test('stored with both on, reading status wins at load', () async {
    // Grouping by collection is on by default, so a reader who turned the
    // reading-status sections on before the two became exclusive has both
    // stored; only the sections were a deliberate choice.
    SharedPreferences.setMockInitialValues({
      'groupByReadingStatus': true,
      'groupByCollections': true,
    });
    final provider = ThemeProvider();

    await provider.loadSettings();

    expect(provider.groupByReadingStatus, isTrue);
    expect(provider.groupByCollections, isFalse);
  });
}
