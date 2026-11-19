import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/theme/app_design.dart';
import 'package:bibliogenius/themes/base/theme_registry.dart';
import 'package:bibliogenius/utils/accessible_color.dart';

/// The side-question panel (the web cover dialog's offer) washes the accent
/// over the dialog's ground: its text and its answers must still read at
/// 4.5:1 there, and the panel must stand apart from the dialog, in every
/// theme and for the default, a pale or a mid accent.
void main() {
  setUpAll(ThemeRegistry.initialize);

  for (final style in const ['default', 'dark', 'minimal']) {
    for (final accent in const [null, Colors.amber, Colors.blue]) {
      test('$style, accent $accent: text and answers read on the panel', () {
        final theme = ThemeRegistry.get(style)!.buildTheme(accentColor: accent);
        final panel = AppDesign.questionPanel(theme);

        final inks = {
          'text': theme.colorScheme.onSurface,
          'answers': panel.ink,
        };
        for (final entry in inks.entries) {
          final ratio = contrastRatio(entry.value, panel.ground);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$style/$accent ${entry.key}: $ratio',
          );
        }
        final dialog =
            theme.dialogTheme.backgroundColor ??
            theme.colorScheme.surfaceContainerHigh;
        expect(panel.ground, isNot(dialog), reason: '$style/$accent');
      });
    }
  }
}
