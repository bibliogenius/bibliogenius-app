// The contract of the contrast helpers, stated as numbers.
//
// The theme guard exercises these end to end, but only along the path that
// passes. What matters here is the pair of promises the functions make: a
// colour that already clears the ratio comes back BIT IDENTICAL, so a palette
// entry nobody needs to touch is never nudged, and a colour that fails comes
// back clearing it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/utils/accessible_color.dart';

const _cream = Color(0xFFFDFBF7);
const _blue = Color(0xFF2196F3); // ThemeProvider's starting accent.
const _indigo = Color(0xFF3F51B5); // Already readable, white on it and as ink.

void main() {
  group('contrastRatio', () {
    test('is symmetric and matches the WCAG bounds', () {
      expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
      expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrastRatio(_blue, _blue), closeTo(1, 0.001));
    });

    test('reports the shipped default that started this work', () {
      // White on the starting accent: the 3.1:1 that failed AA on button
      // labels, and the reason the derivation exists at all.
      expect(contrastRatio(Colors.white, _blue), closeTo(3.12, 0.02));
    });
  });

  group('shiftUntilReadable', () {
    test('returns a conforming surface untouched', () {
      expect(shiftUntilReadable(_indigo, Colors.white), same(_indigo));
    });

    test('darkens a failing surface until white reads on it', () {
      final shifted = shiftUntilReadable(_blue, Colors.white);

      expect(shifted, isNot(_blue));
      expect(
        contrastRatio(Colors.white, shifted),
        greaterThanOrEqualTo(4.5),
      );
      // Hue survives: it is still blue, not a grey or a violet.
      expect(
        HSLColor.fromColor(shifted).hue,
        closeTo(HSLColor.fromColor(_blue).hue, 1),
      );
      expect(
        HSLColor.fromColor(shifted).lightness,
        lessThan(HSLColor.fromColor(_blue).lightness),
      );
    });

    test('honours a ratio lower than the text default', () {
      // A border is a UI component: WCAG asks 3:1 of it, and the looser bar
      // must cost less darkening than the text one.
      final forText = shiftUntilReadable(_blue, Colors.white);
      final forBorder = shiftUntilReadable(_blue, Colors.white,
          minimumRatio: 3);

      expect(
        HSLColor.fromColor(forBorder).lightness,
        greaterThan(HSLColor.fromColor(forText).lightness),
      );
    });
  });

  group('inkOn', () {
    test('returns a conforming accent untouched', () {
      expect(inkOn(_cream, _indigo), same(_indigo));
    });

    test('darkens a failing accent until it reads on the page', () {
      final ink = inkOn(_cream, _blue);

      expect(ink, isNot(_blue));
      expect(contrastRatio(ink, _cream), greaterThanOrEqualTo(4.5));
      expect(
        HSLColor.fromColor(ink).hue,
        closeTo(HSLColor.fromColor(_blue).hue, 1),
      );
    });

    test('hands back the original when no shade can reach the bar', () {
      // 21 is the ceiling of the scale, so 25 is unreachable even at black.
      // The walk runs out, and what comes back must be the colour the caller
      // passed in: a non-conforming label stays visible, where the previous
      // black floor would have painted it onto a light page as pure black or,
      // on a dark one, into invisibility.
      expect(inkOn(Colors.white, _blue, minimumRatio: 25), same(_blue));
      expect(
        shiftUntilReadable(_blue, Colors.white, minimumRatio: 25),
        same(_blue),
      );
    });

    test('every palette-shaped hue reaches the bar on the page', () {
      // The ones that needed the most darkening: a pale yellow has to travel
      // far, and the loop must still land rather than fall through to black.
      for (final accent in [
        const Color(0xFFFFEB3B), // yellow
        const Color(0xFFCDDC39), // lime
        const Color(0xFFFFC107), // amber
      ]) {
        final ink = inkOn(_cream, accent);
        expect(
          contrastRatio(ink, _cream),
          greaterThanOrEqualTo(4.5),
          reason: 'failed for $accent',
        );
        expect(ink, isNot(Colors.black), reason: 'fell through for $accent');
      }
    });
  });
}
