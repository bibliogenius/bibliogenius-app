import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/move_shelf_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_repositories.dart';

// The move itself runs on the real routes in
// test/architecture/tap_target_semantics_guard_test.dart. This file covers
// what those fixtures cannot reach: a dismissed sheet, a shelf that only
// lives in the books' subjects, and a write that fails.

class _FailingTagRepository extends MockTagRepository {
  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async =>
      throw Exception('refused');
}

final _tags = [
  Tag(id: 'salon', name: 'Salon', count: 0),
  Tag(id: 'romans', name: 'Romans', parentId: 'salon', count: 0),
  Tag(id: 'bureau', name: 'Bureau', count: 0),
  // A name found in the books' subjects, with no tags row behind it.
  Tag(id: 'legacy:-1', name: 'Old', count: 2),
];

Future<List<bool>> _pump(
  WidgetTester tester,
  MockTagRepository repo,
  Tag shelf,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final results = <bool>[];
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        Provider<TagRepository>.value(value: repo),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => results.add(
                await showMoveShelfSheet(context, shelf: shelf, allTags: _tags),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'filter_shelves_hint': 'Filter shelves',
        'move_shelf_to_title': 'Move “{name}” to…',
        'move_shelf_to_subtitle': 'One tap moves the shelf there',
        'move_shelf_to_first_level': 'At the first level',
        'shelf_current_place': 'Current place',
        'shelf_moved_under': '{name} moved under {parent}',
        'shelf_moved_to_first_level': '{name} moved to the first level',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  testWidgets('a dismissed sheet moves nothing', (tester) async {
    final repo = MockTagRepository();
    final results = await _pump(tester, repo, _tags[1]);
    expect(find.text('Move “Romans” to…'), findsOneWidget);

    await tester.tapAt(const Offset(195, 10));
    await tester.pumpAndSettle();

    expect(find.text('Move “Romans” to…'), findsNothing);
    expect(repo.updated, isEmpty);
    expect(repo.created, isEmpty);
    expect(results, [false]);
  });

  testWidgets('a shelf known only from subjects gets its row, in place', (
    tester,
  ) async {
    final repo = MockTagRepository();
    final results = await _pump(tester, repo, _tags[3]);

    await tester.tap(find.byKey(const ValueKey('placementRow:Bureau')));
    await tester.pumpAndSettle();

    expect(repo.created, ['Old < bureau']);
    expect(repo.updated, isEmpty);
    expect(find.text('Old moved under Bureau'), findsOneWidget);
    expect(results, [true]);
  });

  testWidgets('a parent known only from subjects gets its row first', (
    tester,
  ) async {
    final repo = MockTagRepository();
    final results = await _pump(tester, repo, _tags[1]);

    await tester.tap(find.byKey(const ValueKey('placementRow:Old')));
    await tester.pumpAndSettle();

    // Its legacy id names no row: filed under it, Romans would point
    // nowhere and show back at the first level.
    expect(repo.created, ['Old']);
    expect(repo.updated, ['romans: Romans < 1']);
    expect(find.text('Romans moved under Old'), findsOneWidget);
    expect(results, [true]);
  });

  testWidgets('a failed move says so, never that the shelf moved', (
    tester,
  ) async {
    final repo = _FailingTagRepository();
    final results = await _pump(tester, repo, _tags[1]);

    await tester.tap(find.text('At the first level'));
    await tester.pumpAndSettle();

    expect(find.textContaining('moved'), findsNothing);
    expect(find.textContaining('refused'), findsOneWidget);
    expect(results, [false]);
  });
}
