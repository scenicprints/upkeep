import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/main.dart';
import 'package:upkeep/mascot.dart';
import 'package:upkeep/theme.dart';

void main() {
  testWidgets('the empty cluster shows the gremlin and no seeded items',
      (WidgetTester tester) async {
    await tester.pumpWidget(const UpkeepApp());
    await tester.pump(const Duration(milliseconds: 100));

    // The mascot is the empty state — if he ever stops rendering, the
    // screen is blank and nobody notices from a green test run.
    expect(find.byType(Mascot), findsOneWidget);
    expect(find.text('NOTHING ON THE PANEL'), findsOneWidget);
    expect(find.text('UPKEEP'), findsOneWidget);
  });

  testWidgets('mascot animates without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        backgroundColor: kBg,
        body: Center(child: Mascot(size: 148, mood: MascotMood.alert)),
      ),
    ));
    // Walk through a full 6s idle loop; a bad painter throws mid-frame.
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(tester.takeException(), isNull);
  });

  test('every mood maps to a gauge colour', () {
    expect(gaugeColor(GaugeState.healthy), kHealthy);
    expect(gaugeColor(GaugeState.ready), kReady);
    expect(gaugeColor(GaugeState.overdue), kOverdue);
  });
}
