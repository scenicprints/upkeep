import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/main.dart';

// The bottom nav labels once sat UNDER the phone's gesture bar. A golden
// won't catch that (the test view has no system bars) and neither will
// "it compiles" — so inject real insets and assert the geometry.
void main() {
  const double dpr = 3.0;
  const double barLogical = 48.0; // 3-button nav bar, worst case

  Future<void> pumpWithSystemBars(WidgetTester tester) async {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = const Size(1080, 2160);
    // Both are needed: SafeArea reads padding, and viewPadding is what
    // survives when the keyboard is up.
    tester.view.padding =
        const FakeViewPadding(bottom: barLogical * dpr, top: 24 * dpr);
    tester.view.viewPadding =
        const FakeViewPadding(bottom: barLogical * dpr, top: 24 * dpr);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const UpkeepApp());
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('bottom nav labels clear the system navigation bar',
      (WidgetTester tester) async {
    await pumpWithSystemBars(tester);

    final double screenBottom = tester.view.physicalSize.height / dpr;
    final double barTop = screenBottom - barLogical;

    for (final String label in <String>['CLUSTER', 'HISTORY', 'ADD']) {
      final Rect r = tester.getRect(find.text(label));
      expect(
        r.bottom,
        lessThanOrEqualTo(barTop),
        reason: '"$label" (bottom ${r.bottom}) is under the system nav bar, '
            'which starts at $barTop',
      );
    }
  });

  testWidgets('the nav bar background still fills the inset strip',
      (WidgetTester tester) async {
    // The labels must clear the bar, but the coloured panel must run all
    // the way down — otherwise there's a black gutter under the nav.
    await pumpWithSystemBars(tester);

    final double screenBottom = tester.view.physicalSize.height / dpr;
    final Finder navPanel = find
        .ancestor(
          of: find.text('CLUSTER'),
          matching: find.byType(Container),
        )
        .last;

    expect(tester.getRect(navPanel).bottom, closeTo(screenBottom, 0.5));
  });

  testWidgets('the header clears the status bar', (WidgetTester tester) async {
    await pumpWithSystemBars(tester);
    expect(tester.getRect(find.text('UPKEEP')).top, greaterThanOrEqualTo(24.0));
  });
}
