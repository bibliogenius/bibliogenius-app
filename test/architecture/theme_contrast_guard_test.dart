// Guard: the themes clear WCAG AA contrast on their own text styles.
//
// Measured on rendered pixels by Flutter's own `textContrastGuideline`, not
// computed from colour constants: the guideline knows the text size and weight
// and applies the 3:1 large-text threshold where it is due, which a hand
// calculation gets wrong as soon as a style changes.
//
// The probe deliberately paints each style on the surface it really sits on
// (scaffold background for body copy, card for list content, primary for the
// filled button label), because a ratio is a property of the pair and not of
// the colour.
//
// The accent matters as much as the theme. `ThemeProvider` always passes its
// banner colour into `buildTheme`, and that colour follows the avatar the
// reader picked, so the button contrast is not one value but twenty.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/models/avatar_config.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';

/// Every accent an avatar can hand to `ThemeProvider.setBannerColor`.
Map<String, Color> _accents() {
  final seen = <String, Color>{};
  for (final entry in {
    ...AvatarOptions.robotColors,
    ...AvatarOptions.genieColors,
  }.entries) {
    seen[entry.value] = Color(int.parse('FF${entry.key}', radix: 16));
  }
  return seen;
}

/// A page exercising the text styles the app actually reads from the theme.
Widget _probe(ThemeData theme) {
  return MaterialApp(
    theme: theme,
      home: Scaffold(
        appBar: AppBar(title: const Text('Library')),
        // The app's primary navigation, and the widget a reader looks at most.
        // It reads its own background from `colorScheme.surface` rather than the
        // scaffold, which is why a ratio worked out against the cream page
        // background gets it wrong.
        body: Row(children: [
          NavigationRail(
            selectedIndex: 0,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.book),
                label: Text('Books'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people),
                label: Text('Peers'),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Body large', style: theme.textTheme.bodyLarge),
                  Text('Body medium', style: theme.textTheme.bodyMedium),
                  Text('Body small', style: theme.textTheme.bodySmall),
                  Text('Title large', style: theme.textTheme.titleLarge),
                  Text('Title medium', style: theme.textTheme.titleMedium),
                  Text('Label small', style: theme.textTheme.labelSmall),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('On card, body medium',
                              style: theme.textTheme.bodyMedium),
                          Text('On card, body small',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  // Every filled shape the accent can reach. FilledButton earns its
                  // place the hard way: the first version of this probe held only
                  // ElevatedButton, so the guard went green while the button the app
                  // actually uses in 57 files stayed at 3.1:1.
                  ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
                  FilledButton(onPressed: () {}, child: const Text('Filled')),
                  FilledButton.tonal(onPressed: () {}, child: const Text('Tonal')),
                  OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                  TextButton(onPressed: () {}, child: const Text('Flat')),
                  const Chip(label: Text('Chip')),
                  // Counted by how often the app reaches for them: FilterChip in 14
                  // files, Badge in 27, DropdownButton and TabBar in 9 each. Every
                  // widget missing from this list is a place the guard cannot see,
                  // which is how FilledButton shipped at 3.1:1 under a green test.
                  FilterChip(
                    label: const Text('Filter on'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('Filter off'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  const Badge(label: Text('9'), child: Icon(Icons.book)),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('One')),
                      ButtonSegment(value: 2, label: Text('Two')),
                    ],
                    selected: const {1},
                    onSelectionChanged: (_) {},
                  ),
                  DropdownButton<int>(
                    value: 1,
                    items: const [DropdownMenuItem(value: 1, child: Text('Item'))],
                    onChanged: (_) {},
                  ),
                  const DefaultTabController(
                    length: 2,
                    child: TabBar(tabs: [Tab(text: 'One'), Tab(text: 'Two')]),
                  ),
                  const ListTile(title: Text('Tile title'), subtitle: Text('Sub')),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  void main() {
    setUpAll(ThemeRegistry.initialize);

    for (final theme in ['default', 'minimal', 'dark']) {
      testWidgets('$theme theme clears AA on its own text styles', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        // The shipped accent, not the parameter default: `ThemeProvider` starts
        // on `Colors.blue` and always passes it, so `_headerBlue` in the default
        // theme is never the colour a reader actually sees. Only the default
        // theme reads the argument; minimal and dark take it and ignore it, so
        // this pins their fixed palettes rather than their behaviour under an
        // accent.
        await tester.pumpWidget(
          _probe(ThemeRegistry.get(theme)!.buildTheme(accentColor: Colors.blue)),
        );
        await tester.pumpAndSettle();

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    // `textContrastGuideline` only looks at nodes carrying text, so a switch or
    // a field border it colours goes unmeasured. WCAG asks 3:1 of those, and
    // `CustomMinimumContrastGuideline` is the tool for it.
    //
    // Every theme, not just the one being worked on: this ran against `default`
    // alone at first and passed, while minimal sat at 2.1 and dark at 1.8 on the
    // same defect.
    for (final theme in ['default', 'minimal', 'dark']) {
      testWidgets('$theme clears 3:1 where the accent paints a control', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeRegistry.get(theme)!.buildTheme(
              accentColor: Colors.blue,
            ),
          home: Scaffold(
            body: Column(
              children: [
                Switch(value: true, onChanged: (_) {}),
                const TextField(autofocus: true),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        tester,
        meetsGuideline(
          CustomMinimumContrastGuideline(
            finder: find.byType(Switch),
            minimumRatio: 3,
            description: 'a switch coloured by the accent needs 3:1',
          ),
        ),
      );
      // The focused field draws its outline in the accent. The field above is
      // autofocused so that the focused border, not the resting one, is what
      // gets measured.
      await expectLater(
        tester,
        meetsGuideline(
          CustomMinimumContrastGuideline(
            finder: find.byType(TextField),
            minimumRatio: 3,
            description: 'a focused field outline needs 3:1',
          ),
        ),
      );
      handle.dispose();
    });
  }

  // One test per accent would drown the report; this one names every accent
  // that fails so the list arrives in a single run.
  testWidgets('every avatar accent clears AA once it becomes the primary', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final offenders = <String>[];

    for (final entry in _accents().entries) {
      await tester.pumpWidget(
        _probe(ThemeRegistry.get('default')!.buildTheme(
          accentColor: entry.value,
        )),
      );
      await tester.pumpAndSettle();
      final evaluation = await textContrastGuideline.evaluate(tester);
      if (!evaluation.passed) {
        offenders.add(
          '${entry.key} '
          '(#${entry.value.toARGB32().toRadixString(16).substring(2)})',
        );
      }
    }

    handle.dispose();
    expect(
      offenders,
      isEmpty,
      reason:
          'these accents fail AA on the widgets they colour, and a reader '
          'picks one by choosing an avatar:\n${offenders.join('\n')}',
    );
  });
}
