import 'package:flutter/material.dart';

/// Contrast helpers for colours the reader chooses.
///
/// The accent is not a designer's decision here: it follows the avatar the
/// reader picked, so any of two dozen values can end up colouring buttons and
/// labels. Two of those uses have different contrast needs, and conflating
/// them is what left the shipped default at 3.1:1.
///
/// As a BACKGROUND (filled button, badge), the accent carries a foreground
/// that must not move, because flipping a white icon to black is a visible
/// change and not a contrast fix. The surface deepens instead: see
/// [shiftUntilReadable].
///
/// As INK (flat button label, active field label), the accent is the text, so
/// the hue itself has to be dark enough against the page: see [inkOn]. No
/// choice of foreground can rescue that case.

/// WCAG 2.1 contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// How finely the searches below walk HSL lightness.
///
/// 64 steps land within about 1.5% of lightness, finer than the eye resolves
/// on a label, and keep the work cheap enough to run inside `buildTheme`.
const _steps = 64;

/// [surface], darkened just enough that [foreground] reads on it.
///
/// Returns [surface] untouched when the pair already clears [minimumRatio], so
/// an accent that was fine keeps its exact value. Darkening runs on HSL
/// lightness to hold the hue.
///
/// Only supports a light [foreground]. A dark one would need the surface to
/// lighten instead, and no accent in the palette lands there: every avatar
/// colour that Flutter pairs with black text already clears AA by a wide
/// margin. See [_darkenUntil] for how that precondition is guarded.
Color shiftUntilReadable(
  Color surface,
  Color foreground, {
  double minimumRatio = 4.5,
}) {
  if (contrastRatio(foreground, surface) >= minimumRatio) return surface;
  return _darkenUntil(surface, foreground, minimumRatio);
}

/// [accent], darkened just enough to be readable as text on [background].
///
/// Returns [accent] untouched when it already clears [minimumRatio], so a
/// palette entry that was fine keeps its exact value. Darkening runs on HSL
/// lightness to hold the hue: the result reads as the same colour, deeper.
Color inkOn(Color background, Color accent, {double minimumRatio = 4.5}) {
  if (contrastRatio(accent, background) >= minimumRatio) return accent;
  return _darkenUntil(accent, background, minimumRatio);
}

/// [moving], walked down in HSL lightness until it clears [minimumRatio]
/// against [fixed].
///
/// Both public entry points reduce to this: contrast is symmetric, so moving
/// the surface away from its foreground and moving the ink away from its page
/// are the same search.
///
/// Returns [moving] unchanged when the walk runs out. That is unreachable
/// while [fixed] is light, since the last step is black and black clears any
/// ratio against a light colour. It matters for the case the assertion below
/// catches in debug and cannot catch in release, where returning the original
/// hands back a colour that is merely non-conforming rather than minting one
/// that is invisible.
Color _darkenUntil(Color moving, Color fixed, double minimumRatio) {
  assert(
    fixed.computeLuminance() > 0.5,
    'Darkening only closes the gap against a light counterpart. A dark one '
    'reaching here needs the lightening branch, deliberately unwritten '
    'because no palette colour lands on it.',
  );

  final hsl = HSLColor.fromColor(moving);
  for (var step = 1; step <= _steps; step++) {
    final candidate = hsl.withLightness(hsl.lightness * (1 - step / _steps));
    final color = candidate.toColor();
    if (contrastRatio(color, fixed) >= minimumRatio) return color;
  }
  return moving;
}
