import 'package:bibliogenius/widgets/hangman_hint_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('tap area meets the 48 px minimum touch target', (tester) async {
    await tester.pumpWidget(
      _host(HangmanHintButton(remaining: 2, label: 'Hints', onPressed: () {})),
    );

    final size = tester.getSize(find.byType(HangmanHintButton));
    expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('a tap off the glyphs still triggers the hint', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        HangmanHintButton(
          remaining: 2,
          label: 'Hints',
          onPressed: () => taps++,
        ),
      ),
    );

    // Bottom-left corner of the tap area: blank space, not the icon or text.
    final rect = tester.getRect(find.byType(HangmanHintButton));
    await tester.tapAt(rect.bottomLeft + const Offset(2, -2));
    expect(taps, 1);
  });

  testWidgets('exposes a labelled button to screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(HangmanHintButton(remaining: 1, label: 'Hints', onPressed: () {})),
    );

    expect(
      tester.getSemantics(find.byType(HangmanHintButton)),
      matchesSemantics(
        label: 'Hints: 1',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });
}
