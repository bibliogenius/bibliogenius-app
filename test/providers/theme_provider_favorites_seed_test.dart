import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ADR-064 seeding gate, Flutter side: ONLY the Reader preset pre-creates the
// favorites collection (the eligibility conditions themselves live Rust-side
// and have their own tests). Librarian and Bookseller never seed, and no
// startup path calls the seam.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int seedCalls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // The preset setters reach ApiService, which reads dotenv (unloaded in
    // unit tests and throwing NotInitializedError otherwise).
    dotenv.testLoad();
    seedCalls = 0;
    ThemeProvider.seedFavoritesOverride = () async {
      seedCalls++;
      return true;
    };
  });

  tearDown(() => ThemeProvider.seedFavoritesOverride = null);

  test('the Reader preset seeds the favorites collection', () async {
    final provider = ThemeProvider();
    await provider.applyPreset('reader');
    expect(seedCalls, 1);
  });

  test('the Librarian and Bookseller presets never seed', () async {
    final provider = ThemeProvider();
    await provider.applyPreset('librarian');
    await provider.applyPreset('bookseller');
    expect(seedCalls, 0);
  });
}
