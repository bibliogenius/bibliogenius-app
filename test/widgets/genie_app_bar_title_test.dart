import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/bibliogenius_logo.dart';
import 'package:bibliogenius/widgets/genie_app_bar.dart';

/// A pushed page must say which page it is.
///
/// The header used to hide the title outright when the measured string did
/// not fit next to the logo, and on a phone the title slot is only 160px
/// wide: the back arrow and the three action buttons take the rest. So a
/// collection opened with nothing but the logo on it, and so did most pushed
/// pages, all the way up to an 820px tablet. The logo yields first now.
const _longTitle = 'Mangas essentiels de la collection';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({'en': {}});
  });

  Future<void> pump(
    WidgetTester tester, {
    required String title,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold()),
        GoRoute(
          path: '/collection',
          builder: (_, _) => Scaffold(
            appBar: GenieAppBar(title: title, transparent: true),
            body: const SizedBox(),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/collection');
    await tester.pumpAndSettle();
  }

  testWidgets('a phone shows the title, and the logo yields the room', (
    tester,
  ) async {
    await pump(tester, title: _longTitle, size: const Size(390, 844));

    expect(
      find.text(_longTitle),
      findsOneWidget,
      reason: 'A page with no name on it is the bug being fixed.',
    );
    expect(
      find.byType(BiblioGeniusLogo),
      findsNothing,
      reason: 'The logo is what pays for the title, not the other way round.',
    );
  });

  testWidgets('a tablet shows it too: the old rule hid it up to 820px', (
    tester,
  ) async {
    await pump(tester, title: _longTitle, size: const Size(820, 1180));

    expect(find.text(_longTitle), findsOneWidget);
  });

  testWidgets('a wide window keeps both, nothing yields', (tester) async {
    await pump(tester, title: 'Mangas', size: const Size(1400, 900));

    expect(find.text('Mangas'), findsOneWidget);
    expect(find.byType(BiblioGeniusLogo), findsOneWidget);
  });

  testWidgets('below the hard floor the logo alone stays', (tester) async {
    // Under 120px of title room there is no usable space for text; that
    // floor predates this fix and is deliberately left standing.
    await pump(tester, title: _longTitle, size: const Size(320, 568));

    expect(find.text(_longTitle), findsNothing);
    expect(find.byType(BiblioGeniusLogo), findsOneWidget);
  });
}
