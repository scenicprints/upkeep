import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/app_state.dart';
import 'package:upkeep/main.dart';
import 'package:upkeep/mascot.dart';
import 'package:upkeep/theme.dart';

// Renders the gremlin to a PNG so he can actually be LOOKED at — there is
// no Android SDK on this machine, so this is the only way to see him
// without shipping a build. Regenerate with:
//
//     flutter test --update-goldens
//
// Windows-only: golden rasterisation differs subtly between platforms and
// this must never be the reason a CI release build fails.
void main() {
  testWidgets('gremlin — detail', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kBg,
          body: Center(child: Mascot(size: 340, mood: MascotMood.content)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await expectLater(
      find.byType(Mascot),
      matchesGoldenFile('goldens/gremlin_detail.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('empty cluster screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(UpkeepApp(controller: UpkeepController()..loaded = true));
    await tester.pump(const Duration(milliseconds: 1500));
    await expectLater(
      find.byType(ClusterScreen),
      matchesGoldenFile('goldens/empty_cluster.png'),
    );
  }, skip: !Platform.isWindows);
}
