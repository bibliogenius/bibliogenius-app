import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';
import 'package:bibliogenius/utils/accessible_color.dart';
import 'package:bibliogenius/widgets/shelf_actions.dart';

/// "First level" in the parent picker of the new shelf dialog, read on the
/// ground it is drawn on, in every theme: a fixed grey sat at about 3:1 on
/// the dark dialog.

class _Repo implements TagRepository {
  @override
  Future<List<Tag>> getTags() async => const [];

  @override
  Future<int> countUnshelvedBooks() async => 0;

  @override
  Future<Tag> createTag(String name, {String? parentId}) async =>
      Tag(id: 'new', name: name, parentId: parentId, count: 0);

  @override
  Future<Tag> updateTag(String uuid, String name, {String? parentId}) async =>
      Tag(id: uuid, name: name, parentId: parentId, count: 0);

  @override
  Future<void> deleteTag(String uuid) async {}

  @override
  Future<void> deleteShelf(Tag tag) async {}
}

/// The colour of the nearest painted Material under [text].
Color _groundOf(WidgetTester tester, Finder text) {
  final grounds = tester
      .widgetList<Material>(
        find.ancestor(of: text, matching: find.byType(Material)),
      )
      .where((m) => m.type != MaterialType.transparency && m.color != null);
  final material = grounds.first;
  // A Material 3 surface may be lifted by a tint of the primary colour.
  final tint = material.surfaceTintColor;
  if (tint == null || tint.a == 0 || material.elevation == 0) {
    return material.color!;
  }
  return ElevationOverlay.applySurfaceTint(
    material.color!,
    tint,
    material.elevation,
  );
}

void main() {
  setUpAll(ThemeRegistry.initialize);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'create_shelf': 'Create a shelf',
        'shelf_name': 'Shelf name',
        'parent_shelf': 'Parent shelf',
        'first_level': 'First level',
        'create': 'Create',
        'cancel': 'Cancel',
      },
    });
  });

  tearDown(() => TranslationService.setPoTranslationsForTest({}));

  for (final style in const ['default', 'dark', 'minimal']) {
    testWidgets('$style: "First level" reads at 4.5:1 in the field and in '
        'its menu', (tester) async {
      final theme = ThemeRegistry.get(
        style,
      )!.buildTheme(accentColor: Colors.blue);
      late BuildContext host;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
            Provider<TagRepository>.value(value: _Repo()),
          ],
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  host = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      );
      showNewShelfDialog(
        host,
        shownTags: [Tag(id: 'a', name: 'Attic', count: 1)],
        onCreated: () {},
      );
      await tester.pumpAndSettle();

      void expectReadable(Finder text, {Color? ground}) {
        final color = tester.widget<Text>(text).style?.color;
        expect(color, isNotNull);
        final ratio = contrastRatio(ground ?? _groundOf(tester, text), color!);
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '$style: $ratio');
      }

      expectReadable(find.text('First level'));

      await tester.tap(find.text('First level'));
      await tester.pumpAndSettle();
      // The field's copy, then the menu's. A dropdown menu paints its own
      // ground, the theme's canvas, without a Material.
      expectReadable(find.text('First level').last, ground: theme.canvasColor);
    });
  }
}
