import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/main.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';

const Map<String, String> _enKeys = {
  'page_not_found_title': 'Page not found',
  'page_not_found_message': "The page you're looking for doesn't exist.",
  'back_to_library': 'Back to library',
  'help_report_problem': 'Report a Problem',
};

GoRouter _router() => GoRouter(
  initialLocation: '/missing',
  routes: [
    GoRoute(path: '/books', builder: (_, _) => const Text('books')),
    GoRoute(path: '/feedback', builder: (_, _) => const Text('feedback')),
  ],
  errorBuilder: (_, _) => const PageNotFoundScreen(),
);

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = _router();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({'en': _enKeys});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('shows both the way home and the report action', (tester) async {
    await _pump(tester);

    expect(find.text('Page not found'), findsOneWidget);
    expect(find.text('Back to library'), findsOneWidget);
    expect(find.text('Report a Problem'), findsOneWidget);
  });

  testWidgets('report action opens the feedback form', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Report a Problem'));
    await tester.pumpAndSettle();

    expect(find.text('feedback'), findsOneWidget);
  });

  testWidgets('back action still returns to the library', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Back to library'));
    await tester.pumpAndSettle();

    expect(find.text('books'), findsOneWidget);
  });
}
