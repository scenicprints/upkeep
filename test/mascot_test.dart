import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/app_state.dart';
import 'package:upkeep/main.dart';
import 'package:upkeep/mascot.dart';
import 'package:upkeep/theme.dart';

void main() {
  testWidgets('the empty cluster shows the gremlin and no seeded items',
      (WidgetTester tester) async {
    await tester.pumpWidget(UpkeepApp(controller: UpkeepController()..loaded = true));
    await tester.pump(const Duration(milliseconds: 100));

    // Two gremlins on an empty panel: the big one that IS the empty state,
    // and the small one riding in the header. If he ever stops rendering,
    // the screen is blank and nobody notices from a green test run.
    expect(find.byType(Mascot), findsNWidgets(2));
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

  test('the gremlin reads the worst thing on the panel', () {
    // His eyes are the fastest read on the screen — they must never be
    // calmer than the panel actually is.
    expect(moodFor(GaugeState.healthy, anyItems: false), MascotMood.idle);
    expect(moodFor(GaugeState.overdue, anyItems: false), MascotMood.idle,
        reason: 'nothing tracked means nothing to be worried about');
    expect(moodFor(GaugeState.healthy, anyItems: true), MascotMood.content);
    expect(moodFor(GaugeState.ready, anyItems: true), MascotMood.alert);
    expect(moodFor(GaugeState.overdue, anyItems: true), MascotMood.overdue);
  });

  test('every mood maps to a gauge colour', () {
    expect(gaugeColor(GaugeState.healthy), kHealthy);
    expect(gaugeColor(GaugeState.ready), kReady);
    expect(gaugeColor(GaugeState.overdue), kOverdue);
  });
}
