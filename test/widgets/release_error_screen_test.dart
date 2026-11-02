import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:bibliogenius/main.dart';
import 'package:bibliogenius/services/translation_service.dart';

const Map<String, String> _enKeys = {
  'error_unexpected_title': 'Something went wrong',
  'error_unexpected_message':
      'The app encountered an unexpected error. Please try again.',
  'retry': 'Retry',
  'help_report_problem': 'Report a Problem',
};

void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({'en': _enKeys});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('release fallback shows sober copy with no exception or stack', (
    tester,
  ) async {
    await tester.pumpWidget(const ReleaseErrorScreen());
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(
      find.text('The app encountered an unexpected error. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Report a Problem'), findsOneWidget);

    // Privacy guard: no exception class names, no stack frame markers,
    // no source paths.
    final stackMarkers = ['Exception', 'package:', '#0', '#1', '.dart:'];
    for (final marker in stackMarkers) {
      expect(
        find.textContaining(marker),
        findsNothing,
        reason: 'Release fallback must never expose "$marker"',
      );
    }
  });

  testWidgets('retry button is inert when no router is registered', (
    tester,
  ) async {
    await tester.pumpWidget(const ReleaseErrorScreen());
    await tester.pumpAndSettle();

    // Tapping must not throw even though no GoRouter is registered.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('report button is inert when no router is registered', (
    tester,
  ) async {
    await tester.pumpWidget(const ReleaseErrorScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Report a Problem'));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('report button opens the feedback route on the app router', (
    tester,
  ) async {
    final appRouter = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/feedback', builder: (_, _) => const Text('feedback')),
      ],
    );
    addTearDown(appRouter.dispose);

    // The fallback lives in its own MaterialApp; the app router is
    // rendered next to it, as when an error replaces a subtree.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            Expanded(child: ReleaseErrorScreen(router: appRouter)),
            Expanded(child: MaterialApp.router(routerConfig: appRouter)),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);

    await tester.tap(find.text('Report a Problem'));
    await tester.pumpAndSettle();

    expect(find.text('feedback'), findsOneWidget);
  });
}
