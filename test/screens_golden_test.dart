import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/app_state.dart';
import 'package:upkeep/item_detail.dart';
import 'package:upkeep/backup_screen.dart';
import 'package:upkeep/fuelwise.dart';
import 'package:upkeep/fuelwise_screen.dart';
import 'package:upkeep/item_edit.dart';
import 'package:upkeep/main.dart';
import 'package:upkeep/mascot.dart';
import 'package:upkeep/models.dart';
import 'package:upkeep/readings_screen.dart';
import 'package:upkeep/store.dart';
import 'package:upkeep/theme.dart';

// Renders the real screens with real data to PNGs so they can be LOOKED at.
// There's no Android SDK on this machine, so this is the only way to see
// the app short of shipping a build.
//
//     flutter test --update-goldens test/screens_golden_test.dart
//
// Windows-only: golden rasterisation differs between platforms and this
// must never be the reason a CI release build fails.

/// Golden tests normally render every glyph as a box, which makes them
/// useless for judging a screen. Load real system fonts instead.
Future<void> loadFonts() async {
  Future<void> reg(String family, List<String> candidates) async {
    for (final String path in candidates) {
      final File f = File(path);
      if (!f.existsSync()) continue;
      final FontLoader loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(
            ByteData.sublistView(f.readAsBytesSync())));
      await loader.load();
      return;
    }
  }

  await reg('Roboto', <String>[
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ]);
  await reg('monospace', <String>[
    r'C:\Windows\Fonts\consola.ttf',
    r'C:\Windows\Fonts\cour.ttf',
  ]);
}

DateTime ago(int days) => DateTime.now().subtract(Duration(days: days));

/// A panel with one of everything, so every state is visible at once.
/// Test-only — the app itself never seeds a single row.
UpkeepController demoController() {
  // The odometer belongs to the CAR — every mileage item on it reads this
  // one meter.
  final Asset car = Asset(
    id: 'car',
    name: "Jenny's RAV4",
    unit: 'mi',
    readings: <Reading>[
      Reading(at: ago(120), value: 38410),
      Reading(at: ago(30), value: 41300),
      Reading(at: ago(4), value: 42950),
    ],
  );
  final Asset house = Asset(id: 'house', name: 'The House');
  final Asset me = Asset(id: 'me', name: 'Me');

  final Item oil = Item(
    id: 'oil',
    name: 'Oil change',
    assetId: car.id,
    kind: ItemKind.usage,
    intervalUnits: 5000,
    intervalMonths: 6, // whichever comes first
    unit: 'mi',
    log: <ServiceLog>[
      ServiceLog(id: 'l1', at: ago(120), reading: 38410),
    ],
    links: <LinkRef>[
      LinkRef(label: 'Toyota of Clovis — book', url: 'https://example.test'),
      LinkRef(label: 'Mobil 1 0W-20 · Amazon', url: 'https://example.test'),
    ],
    parts: <PartRef>[PartRef(number: '90915-YZZJ1', label: 'oil filter')],
    contactName: 'Jenny',
    contactPhone: '555-0100',
  );

  final Item smoke = Item(
    id: 'smoke',
    name: 'Smoke detector batteries',
    assetId: house.id,
    kind: ItemKind.time,
    intervalDays: 365,
    log: <ServiceLog>[ServiceLog(id: 'l2', at: ago(399))],
  );

  final Item filter = Item(
    id: 'filter',
    name: 'Furnace filter',
    assetId: house.id,
    kind: ItemKind.time,
    intervalDays: 90,
    log: <ServiceLog>[ServiceLog(id: 'l3', at: ago(68))],
  );

  final Item dentist = Item(
    id: 'dentist',
    name: 'Dentist — cleaning',
    assetId: me.id,
    kind: ItemKind.time,
    intervalDays: 180,
    log: <ServiceLog>[ServiceLog(id: 'l4', at: ago(115))],
  );

  final Item brakes = Item(
    id: 'brakes',
    name: 'Brake pads',
    assetId: car.id,
    kind: ItemKind.inspect,
    intervalDays: 120,
    log: <ServiceLog>[ServiceLog(id: 'l5', at: ago(50))],
  );

  return UpkeepController()
    ..loaded = true
    ..data = UpkeepData(
      assets: <Asset>[car, house, me],
      items: <Item>[oil, smoke, filter, dentist, brakes],
    );
}

void main() {
  setUpAll(loadFonts);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding =
        const FakeViewPadding(top: 36 * 3, bottom: 48 * 3);
    tester.view.viewPadding =
        const FakeViewPadding(top: 36 * 3, bottom: 48 * 3);
    addTearDown(tester.view.reset);
  }

  testWidgets('cluster with real items', (WidgetTester tester) async {
    await phone(tester);
    await tester.pumpWidget(UpkeepApp(controller: demoController()));
    // Pump frame by frame: one big pump fires the stagger timers but never
    // advances the arc animations, so every gauge renders empty.
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byType(ClusterScreen),
      matchesGoldenFile('goldens/cluster.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('item detail', (WidgetTester tester) async {
    await phone(tester);
    final UpkeepController c = demoController();
    await tester.pumpWidget(
      UpkeepScope(
        notifier: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const ItemDetailScreen(itemId: 'oil'),
        ),
      ),
    );
    for (int i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byType(ItemDetailScreen),
      matchesGoldenFile('goldens/item_detail.png'),
    );
  }, skip: !Platform.isWindows);

  Widget wrap(UpkeepController c, Widget home) => UpkeepScope(
        notifier: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: home,
        ),
      );

  testWidgets('the meter', (WidgetTester tester) async {
    await phone(tester);
    final UpkeepController c = demoController();
    await tester.pumpWidget(
        wrap(c, const AssetReadingsScreen(assetId: 'car')));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(AssetReadingsScreen),
      matchesGoldenFile('goldens/readings.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('backup', (WidgetTester tester) async {
    await phone(tester);
    final UpkeepController c = demoController();
    await tester.pumpWidget(wrap(c, const BackupScreen()));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(BackupScreen),
      matchesGoldenFile('goldens/backup.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('gremlin — every mood', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kBg,
          body: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                for (final MascotMood m in MascotMood.values)
                  Mascot(size: 132, mood: m),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await expectLater(
      find.byType(Row).first,
      matchesGoldenFile('goldens/gremlin_moods.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('gremlin — mid-poke', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: kBg,
          body: Center(child: Mascot(size: 300, mood: MascotMood.alert)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.byType(Mascot));
    // Land near the top of the hop.
    for (int i = 0; i < 7; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await expectLater(
      find.byType(Mascot),
      matchesGoldenFile('goldens/gremlin_poke.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('fuelwise — connected with a linked car',
      (WidgetTester tester) async {
    await phone(tester);
    final UpkeepController c = demoController();
    c.data.liveAssets.first.fuelwiseVehicleId = 'v1';
    final FuelWiseSnapshot snap = FuelWise.parseSnapshot(
      '{"vehicles":[{"id":"v1","name":"RAV4","year":2019,"make":"Toyota"},'
      '{"id":"v2","name":"The Truck"}],'
      '"fillups":[{"vehicleId":"v1","date":"2026-07-02T00:00:00.000",'
      '"odometer":41300},{"vehicleId":"v1",'
      '"date":"2026-08-08T00:00:00.000","odometer":42950},'
      '{"vehicleId":"v2","date":"2026-08-01T00:00:00.000",'
      '"odometer":91000}]}',
    );
    await tester.pumpWidget(wrap(
      c,
      FuelWiseScreen(debugSnapshot: snap, debugConnected: true),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(FuelWiseScreen),
      matchesGoldenFile('goldens/fuelwise.png'),
    );
  }, skip: !Platform.isWindows);

  testWidgets('add item', (WidgetTester tester) async {
    await phone(tester);
    final UpkeepController c = demoController();
    await tester.pumpWidget(
      UpkeepScope(
        notifier: c,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const ItemEditScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(ItemEditScreen),
      matchesGoldenFile('goldens/item_edit.png'),
    );
  }, skip: !Platform.isWindows);
}
