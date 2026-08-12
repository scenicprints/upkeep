import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/fuelwise.dart';
import 'package:upkeep/models.dart';

DateTime day(int n) => DateTime(2026, 1, 1).add(Duration(days: n));

/// A data.json shaped exactly like FuelWise writes it — the field names are
/// copied from that app's models, and getting one wrong means a silent
/// no-op rather than an error.
String fuelwiseJson({List<Map<String, dynamic>>? fills}) =>
    json.encode(<String, dynamic>{
      'vehicles': <dynamic>[
        <String, dynamic>{
          'id': 'v1',
          'name': 'RAV4',
          'year': 2019,
          'make': 'Toyota',
          'tankGallons': 14.5,
        },
        <String, dynamic>{'id': 'v2', 'name': 'Truck'},
      ],
      'fillups': fills ??
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'f1',
              'vehicleId': 'v1',
              'date': day(0).toIso8601String(),
              'odometer': 40000,
              'gallons': 12.1,
              'pricePerGallon': 4.29,
              'partial': false,
            },
            <String, dynamic>{
              'id': 'f2',
              'vehicleId': 'v1',
              'date': day(14).toIso8601String(),
              'odometer': 40450,
              'gallons': 11.8,
              'pricePerGallon': 4.35,
              'partial': false,
            },
            <String, dynamic>{
              'id': 'f3',
              'vehicleId': 'v2',
              'date': day(3).toIso8601String(),
              'odometer': 91000,
              'gallons': 20.0,
              'pricePerGallon': 4.10,
              'partial': false,
            },
          ],
      'trips': <dynamic>[],
      'drives': <dynamic>[],
    });

void main() {
  group('reading FuelWise', () {
    test('pulls vehicles and fill-ups out of a real-shaped file', () {
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      expect(s.vehicles.length, 2);
      expect(s.vehicles.first.label, 'RAV4 · 2019 Toyota');
      expect(s.fills.length, 3);
      expect(s.forVehicle('v1').length, 2);
      expect(s.forVehicle('v2').single.odometer, 91000);
    });

    test('a vehicle with no year or make still reads properly', () {
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      expect(s.vehicles[1].label, 'Truck');
    });

    test('an unknown field from a future FuelWise is ignored, not fatal', () {
      // FuelWise keeps being developed; a new key over there must never
      // break this app.
      final Map<String, dynamic> j =
          json.decode(fuelwiseJson()) as Map<String, dynamic>;
      j['somethingNew'] = <String, dynamic>{'a': 1};
      (j['fillups'] as List<dynamic>)[0]['newField'] = 'x';
      expect(() => FuelWise.parseSnapshot(json.encode(j)), returnsNormally);
      expect(FuelWise.parseSnapshot(json.encode(j)).fills.length, 3);
    });

    test('junk fill-ups are skipped rather than throwing', () {
      final String j = fuelwiseJson(fills: <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a'}, // no vehicle, no odometer
        <String, dynamic>{
          'vehicleId': 'v1',
          'date': 'not-a-date',
          'odometer': 100
        },
        <String, dynamic>{
          'vehicleId': 'v1',
          'date': day(1).toIso8601String(),
          'odometer': 0 // placeholder, not a reading
        },
        <String, dynamic>{
          'vehicleId': 'v1',
          'date': day(2).toIso8601String(),
          'odometer': 12345
        },
      ]);
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(j);
      expect(s.fills.length, 1);
      expect(s.fills.single.odometer, 12345);
    });

    test('an empty file yields nothing rather than an error', () {
      final FuelWiseSnapshot s = FuelWise.parseSnapshot('{}');
      expect(s.vehicles, isEmpty);
      expect(s.fills, isEmpty);
    });

    test('every failure has its own message to act on', () {
      // "It didn't work" is useless; each of these needs a different fix.
      for (final FuelWiseError e in FuelWiseError.values) {
        if (e == FuelWiseError.none) continue;
        expect(fuelWiseErrorText(e), isNotEmpty);
      }
      expect(fuelWiseErrorText(FuelWiseError.notPublishedYet).toLowerCase(),
          contains('fuelwise'));
    });
  });

  group('the clipboard route', () {
    // Both apps are on one phone, so this is the default path — it has to
    // be as trustworthy as the network one.
    test('a copied log parses into the same snapshot', () {
      final FuelWiseResult r = FuelWise.parseOrError(fuelwiseJson());
      expect(r.ok, isTrue);
      expect(r.snapshot!.vehicles.length, 2);
      expect(r.snapshot!.fills.length, 3);
    });

    test('something else on the clipboard is refused, not half-read', () {
      for (final String junk in <String>[
        'hello',
        '{"unrelated": true}',
        '[]',
        '{"vehicles": [], "fillups": []}',
      ]) {
        final FuelWiseResult r = FuelWise.parseOrError(junk);
        expect(r.ok, isFalse, reason: 'should refuse: \$junk');
        expect(r.error, FuelWiseError.clipboardNotFuelWise);
      }
    });

    test('an empty log is treated as the wrong thing copied', () {
      // Silently succeeding with nothing would look like "FuelWise has no
      // fill-ups", which is a lie about his data.
      expect(FuelWise.parseOrError('{}').error,
          FuelWiseError.clipboardNotFuelWise);
    });

    test('a log with vehicles but no fills is still accepted', () {
      // A new FuelWise install with a car and no fill-ups yet is real.
      final FuelWiseResult r = FuelWise.parseOrError(
          '{"vehicles":[{"id":"v1","name":"RAV4"}],"fillups":[]}');
      expect(r.ok, isTrue);
      expect(r.snapshot!.fills, isEmpty);
    });

    test('the clipboard messages say where to copy from', () {
      expect(fuelWiseErrorText(FuelWiseError.clipboardEmpty).toLowerCase(),
          contains('fuelwise'));
      expect(
          fuelWiseErrorText(FuelWiseError.clipboardNotFuelWise).toLowerCase(),
          contains('copy'));
    });
  });

  group('importing fill-ups', () {
    Asset car() => Asset(id: 'a', name: 'RAV4', unit: 'mi');

    test('fill-ups become readings on the car', () {
      final Asset a = car();
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      final ImportResult r = importFills(a, s.forVehicle('v1'));

      expect(r.added, 2);
      expect(a.readings.length, 2);
      expect(a.latestReading!.value, 40450);
      expect(a.readings.every((Reading x) => x.source == 'fuelwise'), isTrue);
    });

    test('running it twice adds nothing — safe on every launch', () {
      final Asset a = car();
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      importFills(a, s.forVehicle('v1'));
      final ImportResult again = importFills(a, s.forVehicle('v1'));

      expect(again.added, 0);
      expect(again.skipped, 2);
      expect(a.readings.length, 2);
    });

    test('a number you already typed is not duplicated', () {
      final Asset a = car()
        ..readings.add(Reading(at: day(14), value: 40450));
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      final ImportResult r = importFills(a, s.forVehicle('v1'));

      expect(r.added, 1, reason: 'only the fill it did not already have');
      expect(r.skipped, 1);
      expect(a.readings.length, 2);
    });

    test('an import never touches a reading you entered', () {
      final Asset a = car()
        ..readings.add(Reading(at: day(30), value: 41000));
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      importFills(a, s.forVehicle('v1'));

      final Reading mine =
          a.readings.firstWhere((Reading r) => r.source == 'manual');
      expect(mine.value, 41000);
      expect(a.readings.length, 3);
    });

    test('unlinking removes imports and keeps your own numbers', () {
      final Asset a = car()
        ..readings.add(Reading(at: day(30), value: 41000));
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      importFills(a, s.forVehicle('v1'));
      expect(a.readings.length, 3);

      final int removed = removeImported(a);
      expect(removed, 2);
      expect(a.readings.length, 1);
      expect(a.readings.single.value, 41000);
      expect(a.readings.single.source, 'manual');
    });

    test('imported readings drive the learned pace like any other', () {
      final Asset a = car();
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      importFills(a, s.forVehicle('v1'));

      final Item oil = Item(
        id: 'i',
        name: 'Oil',
        assetId: 'a',
        kind: ItemKind.usage,
        intervalUnits: 5000,
        log: <ServiceLog>[ServiceLog(id: 'l', at: day(0), reading: 40000)],
      );
      // 450 miles over 14 days.
      expect(Tracked(oil, a).unitsPerDay, closeTo(450 / 14, 0.01));
      expect(Tracked(oil, a).progress(day(14)), closeTo(0.09, 0.01));
    });

    test('the source survives a save and load', () {
      final Asset a = car();
      final FuelWiseSnapshot s = FuelWise.parseSnapshot(fuelwiseJson());
      importFills(a, s.forVehicle('v1'));

      final Asset back = Asset.fromJson(a.toJson());
      expect(back.readings.every((Reading r) => r.source == 'fuelwise'),
          isTrue);
    });

    test('the link survives a save and load', () {
      final Asset a = car()..fuelwiseVehicleId = 'v1';
      expect(Asset.fromJson(a.toJson()).fuelwiseVehicleId, 'v1');
    });

    test('a reading from an older file defaults to manual', () {
      // v0.4 files have no source field; they must never be mistaken for
      // imports, or unlinking would delete hand-typed numbers.
      final Reading old = Reading.fromJson(<String, dynamic>{
        'id': 'x',
        'at': day(0).toIso8601String(),
        'value': 100,
      });
      expect(old.source, 'manual');
      expect(old.imported, isFalse);
    });
  });
}
