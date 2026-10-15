import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsData;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/help_screen.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/utils/accessible_color.dart';

/// The help screen as a screen reader and a keyboard meet it: section titles
/// are headings, every card says it is a button, the FAQ entries say whether
/// they are open, the guides card warns it leaves the app, and the white
/// labels clear AA on their gradients.

const _catalogue = {
  'en': {
    'help_title': 'Help',
    'help_welcome_title': 'How can we help?',
    'help_welcome_subtitle': 'Answers and shortcuts',
    'help_faq_title': 'Frequently asked questions',
    'help_quick_actions': 'Quick actions',
    'help_quick_tour': 'Quick tour',
    'help_contact_us': 'Contact us',
    'help_report_problem': 'Report a problem',
    'help_import_app': 'Import from another app',
    'help_online_docs': 'Online guides',
    'open_in_browser': 'Open in browser',
  },
};

SemanticsData _dataOf(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder).getSemanticsData();

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'languageCode': 'en'});
    TranslationService.setPoTranslationsForTest(_catalogue);
    dotenv.testLoad(fileInput: '');
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
          ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [GoRoute(path: '/', builder: (_, _) => const HelpScreen())],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The FAQ fills several screens; the list builds the quick actions below it
  // only once they scroll into view.
  Future<void> scrollToQuickActions(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Online guides'),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('section titles are headings', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    bool isHeader(String title) =>
        _dataOf(tester, find.text(title)).flagsCollection.isHeader;

    expect(isHeader('How can we help?'), isTrue);
    expect(isHeader('Frequently asked questions'), isTrue);
    await scrollToQuickActions(tester);
    expect(isHeader('Quick actions'), isTrue);
    handle.dispose();
  });

  testWidgets('quick action cards are buttons the keyboard can reach', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester);
    await scrollToQuickActions(tester);

    for (final label in [
      'Quick tour',
      'Contact us',
      'Report a problem',
      'Import from another app',
      'Online guides',
    ]) {
      final data = _dataOf(tester, find.text(label));
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
      // Tristate.none means the node cannot take focus at all.
      expect(
        data.flagsCollection.isFocused,
        isNot(Tristate.none),
        reason: label,
      );
    }
    expect(_dataOf(tester, find.text('Online guides')).hint, 'Open in browser');
    handle.dispose();
  });

  testWidgets('a FAQ entry says whether it is open', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester);

    final faqTitle = find
        .descendant(of: find.byType(ListView), matching: find.byType(Text))
        .at(3);
    var data = _dataOf(tester, faqTitle);
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isExpanded, Tristate.isFalse);

    await tester.tap(faqTitle);
    await tester.pumpAndSettle();
    data = _dataOf(tester, faqTitle);
    expect(data.flagsCollection.isExpanded, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('white labels clear AA on every gradient they sit on', (
    tester,
  ) async {
    await pump(tester);

    final gradientBox = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).gradient != null,
    );
    void expectReadable(String label) {
      final box = tester.widget<Container>(
        find.ancestor(of: find.text(label), matching: gradientBox).first,
      );
      final gradient = (box.decoration! as BoxDecoration).gradient!;
      // The colour actually painted: a translucent white reads lower than
      // white itself once blended onto the card.
      final ink = tester.widget<Text>(find.text(label)).style?.color;
      for (final color in gradient.colors) {
        expect(
          contrastRatio(Color.alphaBlend(ink ?? Colors.white, color), color),
          greaterThanOrEqualTo(4.5),
          reason: '$label on $color',
        );
      }
    }

    expectReadable('Answers and shortcuts');
    await scrollToQuickActions(tester);
    for (final label in [
      'Quick tour',
      'Contact us',
      'Report a problem',
      'Import from another app',
      'Online guides',
    ]) {
      expectReadable(label);
    }
  });
}
