import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';

void main() {
  group('Translation fallback chain (Chinese)', () {
    setUp(() {
      // Seed PO translations to simulate loaded .po files
      TranslationService.setPoTranslationsForTest({
        'en': {'hello': 'Hello', 'goodbye': 'Goodbye', 'settings': 'Settings'},
        'zh': {'hello': '你好', 'goodbye': '再见'},
        'zh-CN': {'hello': '你好 (简体)'},
        'zh-TW': {'hello': '你好 (繁體)'},
      });
    });

    tearDown(() {
      TranslationService.setPoTranslationsForTest({});
    });

    Widget buildTestApp(Locale locale, void Function(BuildContext) callback) {
      final provider = ThemeProvider()..setLocaleSync(locale);
      return MaterialApp(
        home: ChangeNotifierProvider<ThemeProvider>.value(
          value: provider,
          child: Builder(
            builder: (context) {
              callback(context);
              return const SizedBox();
            },
          ),
        ),
      );
    }

    testWidgets('zh-CN uses zh-CN specific translation', (tester) async {
      late String result;
      await tester.pumpWidget(
        buildTestApp(
          const Locale('zh', 'CN'),
          (ctx) => result = TranslationService.translate(ctx, 'hello'),
        ),
      );
      expect(result, '你好 (简体)');
    });

    testWidgets('zh-TW uses zh-TW specific translation', (tester) async {
      late String result;
      await tester.pumpWidget(
        buildTestApp(
          const Locale('zh', 'TW'),
          (ctx) => result = TranslationService.translate(ctx, 'hello'),
        ),
      );
      expect(result, '你好 (繁體)');
    });

    testWidgets('zh-CN falls back to zh for missing key', (tester) async {
      late String result;
      await tester.pumpWidget(
        buildTestApp(
          const Locale('zh', 'CN'),
          (ctx) => result = TranslationService.translate(ctx, 'goodbye'),
        ),
      );
      // 'goodbye' not in zh-CN, should fall back to zh
      expect(result, '再见');
    });

    testWidgets('zh-TW falls back to zh then to en for missing key', (
      tester,
    ) async {
      late String result;
      await tester.pumpWidget(
        buildTestApp(
          const Locale('zh', 'TW'),
          (ctx) => result = TranslationService.translate(ctx, 'settings'),
        ),
      );
      // 'settings' not in zh-TW or zh, should fall back to en
      expect(result, 'Settings');
    });

    testWidgets('plain zh locale uses zh translations', (tester) async {
      late String result;
      await tester.pumpWidget(
        buildTestApp(
          const Locale('zh'),
          (ctx) => result = TranslationService.translate(ctx, 'hello'),
        ),
      );
      expect(result, '你好');
    });

    testWidgets('completely unknown key returns the key itself', (
      tester,
    ) async {
      late String result;
      await tester.pumpWidget(
        buildTestApp(
          const Locale('zh', 'CN'),
          (ctx) =>
              result = TranslationService.translate(ctx, 'nonexistent_key'),
        ),
      );
      expect(result, 'nonexistent_key');
    });
  });

  group('Translation fallback chain (Portuguese)', () {
    setUp(() {
      TranslationService.setPoTranslationsForTest({
        'en': {'app_name': 'BiblioGenius'},
        'pt-BR': {'app_name': 'BiblioGenius (BR)'},
        'pt': {'app_name': 'BiblioGenius (PT)'},
      });
    });

    tearDown(() {
      TranslationService.setPoTranslationsForTest({});
    });

    testWidgets('pt-BR gets its own translation, not generic pt', (
      tester,
    ) async {
      late String result;
      final provider = ThemeProvider()..setLocaleSync(const Locale('pt', 'BR'));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ThemeProvider>.value(
            value: provider,
            child: Builder(
              builder: (context) {
                result = TranslationService.translate(context, 'app_name');
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(result, 'BiblioGenius (BR)');
    });

    testWidgets('plain pt gets generic pt translation', (tester) async {
      late String result;
      final provider = ThemeProvider()..setLocaleSync(const Locale('pt'));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ThemeProvider>.value(
            value: provider,
            child: Builder(
              builder: (context) {
                result = TranslationService.translate(context, 'app_name');
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(result, 'BiblioGenius (PT)');
    });

    testWidgets('pt-PT falls back to pt when no pt-PT key exists', (
      tester,
    ) async {
      late String result;
      final provider = ThemeProvider()..setLocaleSync(const Locale('pt', 'PT'));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<ThemeProvider>.value(
            value: provider,
            child: Builder(
              builder: (context) {
                result = TranslationService.translate(context, 'app_name');
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      // No pt-PT.po loaded, falls back to pt
      expect(result, 'BiblioGenius (PT)');
    });
  });
}
