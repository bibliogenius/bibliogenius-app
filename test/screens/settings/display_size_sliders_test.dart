import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/settings/theme_section.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/cover_grid_delegate.dart';
import 'package:bibliogenius/widgets/cover_size_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Settings > Display: text size and cover size share one slider, each with a
// preview above it. The cover slider has a step per column count and its
// preview says, and draws, how many covers a library row holds.
void main() {
  late ThemeProvider theme;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeProvider();
    TranslationService.setPoTranslationsForTest({
      'en': {
        'home_cover_size': 'Cover size',
        'home_cover_size_per_row': '{count} covers per row',
        'text_size': 'Text size',
        'text_size_default': 'Default',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pumpSection(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider(create: (_) => OwnershipPreferenceProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ThemeSettingsSection()),
          ),
        ),
      ),
    );
  }

  Finder sliderWithKey(String key) =>
      find.descendant(of: find.byKey(Key(key)), matching: find.byType(Slider));

  testWidgets('text and covers use the same slider', (tester) async {
    await pumpSection(tester);

    final text = tester.widget<Slider>(sliderWithKey('text_size_slider'));
    final covers = tester.widget<Slider>(sliderWithKey('cover_size_slider'));
    expect(covers.divisions, ThemeProvider.homeCoverExtentSteps.length - 1);
    expect(covers.activeColor, text.activeColor);
    expect(find.byType(SegmentedButton<double>), findsNothing);
  });

  testWidgets('each text size step is read out with a label of its own', (
    tester,
  ) async {
    await pumpSection(tester);

    final text = tester.widget<Slider>(sliderWithKey('text_size_slider'));
    final labels = {
      for (var i = 0; i <= text.max; i++)
        text.semanticFormatterCallback!(i.toDouble()),
    };
    expect(labels, hasLength(text.max.toInt() + 1));
  });

  testWidgets('the cover slider starts on the default size', (tester) async {
    await pumpSection(tester);

    final covers = tester.widget<Slider>(sliderWithKey('cover_size_slider'));
    expect(
      covers.value,
      ThemeProvider.homeCoverExtentSteps
          .indexOf(ThemeProvider.homeCoverExtentDefault)
          .toDouble(),
    );
    expect(find.text('3 covers per row'), findsOneWidget);
  });

  testWidgets('moving the slider changes the size and the preview', (
    tester,
  ) async {
    await pumpSection(tester);
    final slider = sliderWithKey('cover_size_slider');

    // To the far left: the smallest size.
    await tester.drag(slider, const Offset(-1000, 0));
    await tester.pumpAndSettle();

    expect(theme.homeCoverExtent, ThemeProvider.homeCoverExtentSteps.first);
    expect(find.text('6 covers per row'), findsOneWidget);
    final preview = tester.widget<GridView>(
      find.descendant(
        of: find.byType(CoverSizePreview),
        matching: find.byType(GridView),
      ),
    );
    // A miniature of the library grid itself: same delegate, same size.
    final delegate = preview.gridDelegate as CoverGridDelegate;
    expect(delegate.coverSize, ThemeProvider.homeCoverExtentSteps.first);
    expect(delegate.phone, isTrue);

    // To the far right: the largest size.
    await tester.drag(slider, const Offset(1000, 0));
    await tester.pumpAndSettle();

    expect(theme.homeCoverExtent, ThemeProvider.homeCoverExtentSteps.last);
    expect(find.text('2 covers per row'), findsOneWidget);
  });

  testWidgets('the preview keeps its height, so the slider stays put', (
    tester,
  ) async {
    await pumpSection(tester);
    final slider = sliderWithKey('cover_size_slider');
    final before = tester.getTopLeft(slider);

    await tester.drag(slider, const Offset(-1000, 0));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(slider), before);
  });

  testWidgets('a screen reader hears the cover count, not a percentage', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSection(tester);

    expect(
      tester.getSemantics(sliderWithKey('cover_size_slider')),
      matchesSemantics(
        label: 'Cover size',
        value: '3 covers per row',
        increasedValue: '2 covers per row',
        decreasedValue: '4 covers per row',
        isSlider: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a screen reader hears which setting each slider changes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSection(tester);

    expect(
      tester.getSemantics(sliderWithKey('text_size_slider')),
      matchesSemantics(
        label: 'Text size',
        value: 'Default',
        isSlider: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
        increasedValue: 'text_size_large',
        decreasedValue: 'text_size_small',
      ),
    );
    handle.dispose();
  });
}
