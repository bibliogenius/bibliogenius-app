import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/widgets/scaffold_with_nav.dart';

/// The navigation-style preference (bottom bar vs side menu) only has an
/// effect below the rail breakpoint: above it the shell always shows the
/// NavigationRail. The Settings screen relies on this predicate to hide the
/// selector instead of offering a control that silently does nothing.
void main() {
  Future<bool> railAtWidth(WidgetTester tester, double width) async {
    late bool result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Builder(
          builder: (context) {
            result = usesNavigationRail(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('phone widths let the navigation-style preference apply', (
    tester,
  ) async {
    expect(await railAtWidth(tester, 390), isFalse);
    expect(await railAtWidth(tester, navRailBreakpoint), isFalse);
  });

  testWidgets('tablet and desktop widths force the rail', (tester) async {
    expect(await railAtWidth(tester, navRailBreakpoint + 1), isTrue);
    expect(await railAtWidth(tester, 1280), isTrue);
  });
}
