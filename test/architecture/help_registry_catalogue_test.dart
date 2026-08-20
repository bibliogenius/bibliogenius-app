// Guard: every key referenced by the help catalogue must exist in the
// translation catalogues.
//
// `HelpRegistry` addresses its strings by key (`titleKey`, `descKey`,
// `ctaKey`), so a topic added without its `.po` entries compiles, ships, and
// shows the raw key to the user. This test is a textual scan of the registry
// against `fr.po` (the reference catalogue) and `en.po` (the fallback the app
// falls back to when a locale lacks the key).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Set<String> _msgIds(String poPath) {
  final content = File(poPath).readAsStringSync();
  return RegExp(
    r'^msgid "([^"]+)"',
    multiLine: true,
  ).allMatches(content).map((m) => m.group(1)!).toSet();
}

void main() {
  test('every HelpRegistry string key exists in fr.po and en.po', () {
    final registry = File('lib/services/help_registry.dart').readAsStringSync();

    final keys = RegExp(
      r"(?:titleKey|descKey|ctaKey): '([a-z0-9_]+)'",
    ).allMatches(registry).map((m) => m.group(1)!).toSet();

    expect(
      keys,
      isNotEmpty,
      reason: 'the key scan matched nothing, the registry shape changed',
    );

    for (final lang in ['fr', 'en']) {
      final ids = _msgIds('assets/i18n/$lang.po');
      final missing = keys.where((k) => !ids.contains(k)).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason: 'missing in $lang.po: ${missing.join(', ')}',
      );
    }
  });

  test('help topics with a CTA point at a declared route', () {
    final registry = File('lib/services/help_registry.dart').readAsStringSync();
    final router = File('lib/main.dart').readAsStringSync();

    // Nested GoRoutes declare a relative path ('migration-wizard'), so a CTA
    // route counts as declared when the full path matches, or when its last
    // segment matches a nested declaration.
    final routes = RegExp(
      r"path: '([a-z0-9\-/]+)'",
    ).allMatches(router).map((m) => m.group(1)!).toSet();

    final ctaRoutes = RegExp(
      r"ctaRoute: '([^']+)'",
    ).allMatches(registry).map((m) => m.group(1)!.split('?').first).toSet();

    final unknown =
        ctaRoutes
            .where(
              (r) => !routes.contains(r) && !routes.contains(r.split('/').last),
            )
            .toList()
          ..sort();
    expect(
      unknown,
      isEmpty,
      reason: 'help CTA routes absent from the router: ${unknown.join(', ')}',
    );
  });
}
