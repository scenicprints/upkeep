import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/models.dart';
import 'package:upkeep/store.dart';

DateTime day(int n) => DateTime(2026, 1, 1).add(Duration(days: n));

// Two things here can lose or corrupt a hand-typed dataset: the migration
// that moves readings onto the asset, and a bad number that poisons the
// learned rate. Both get hammered.

void main() {
  group('migrating v0.2 readings onto the asset', () {
    /// A file written by v0.2, where readings hung off each ITEM.
    String legacyJson() => json.encode(<String, dynamic>{
          'version': 1,
          'assets': <dynamic>[
            <String, dynamic>{'id': 'car', 'name': "Jenny's RAV4"},
          ],
          'items': <dynamic>[
            <String, dynamic>{
              'id': 'oil',
              'name': 'Oil change',
              'asset_id': 'car',
              'kind': 'usage',
              'interval_units': 5000,
              'unit': 'mi',
              'readings': <dynamic>[
                <String, dynamic>{
                  'at': day(0).toIso8601String(),
                  'value': 40000
                },
                <String, dynamic>{
                  'at': day(10).toIso8601String(),
                  'value': 40320
                },
              ],
              'log': <dynamic>[],
            },
            <String, dynamic>{
              'id': 'rot',
              'name': 'Tire rotation',
              'asset_id': 'car',
              'kind': 'usage',
              'interval_units': 6000,
              'unit': 'mi',
              // The same car, a DIFFERENT set of readings — exactly the mess
              // the move to per-asset readings is meant to end.
              'readings': <dynamic>[
                <String, dynamic>{
                  'at': day(20).toIso8601String(),
                  'value': 40900
                },
              ],
              'log': <dynamic>[],
            },
          ],
        });

    test('folds every item’s readings up onto the shared asset', () {
      final UpkeepData d = UpkeepData.decode(legacyJson());
      final Asset car = d.assets.first;

      expect(car.readings.length, 3);
      expect(d.items.every((Item i) => i.readings.isEmpty), isTrue,
          reason: 'items should no longer carry their own readings');
      expect(car.unit, 'mi');
    });

    test('both items now read the same meter', () {
      final UpkeepData d = UpkeepData.decode(legacyJson());
      final Tracked oil = d.track(d.items[0]);
      final Tracked rot = d.track(d.items[1]);

      expect(oil.latestReading!.value, 40900);
      expect(rot.latestReading!.value, 40900);
      expect(oil.unitsPerDay, rot.unitsPerDay);
    });

    test('is idempotent — running it twice cannot duplicate readings', () {
      final UpkeepData d = UpkeepData.decode(legacyJson());
      final int after = d.assets.first.readings.length;
      d.migrateReadingsToAssets();
      d.migrateReadingsToAssets();
      expect(d.assets.first.readings.length, after);
    });

    test('survives a save/load round trip with the readings intact', () {
      final UpkeepData d = UpkeepData.decode(legacyJson());
      final UpkeepData back = UpkeepData.decode(d.encode());
      expect(back.assets.first.readings.length, 3);
      expect(back.track(back.items[0]).latestReading!.value, 40900);
    });

    test('an orphaned item keeps its readings rather than losing them', () {
      // asset_id points at nothing. Dropping the readings would be silent
      // data loss, so they stay put.
      final String orphan = json.encode(<String, dynamic>{
        'assets': <dynamic>[],
        'items': <dynamic>[
          <String, dynamic>{
            'id': 'x',
            'name': 'Orphan',
            'asset_id': 'gone',
            'kind': 'usage',
            'readings': <dynamic>[
              <String, dynamic>{
                'at': day(0).toIso8601String(),
                'value': 123
              },
            ],
          },
        ],
      });
      final UpkeepData d = UpkeepData.decode(orphan);
      expect(d.items.first.readings.length, 1);
    });

    test('a v0.3 file is untouched by the migration', () {
      final UpkeepData fresh = UpkeepData(
        assets: <Asset>[
          Asset(
            id: 'car',
            name: 'Car',
            readings: <Reading>[Reading(at: day(0), value: 100)],
          )
        ],
        items: <Item>[
          Item(id: 'i', name: 'X', assetId: 'car', kind: ItemKind.usage)
        ],
      );
      expect(fresh.migrateReadingsToAssets(), isFalse);
      expect(fresh.assets.first.readings.length, 1);
    });

    test('empty and garbage files do not throw', () {
      expect(UpkeepData.decode('').items, isEmpty);
      expect(UpkeepData.decode('   ').assets, isEmpty);
    });
  });

  group('one meter, many items', () {
    test('a single reading moves every item on that car', () {
      final Asset car = Asset(id: 'car', name: 'RAV4', unit: 'mi');
      final Item oil = Item(
        id: 'oil',
        name: 'Oil',
        assetId: 'car',
        kind: ItemKind.usage,
        intervalUnits: 5000,
        log: <ServiceLog>[ServiceLog(id: 'a', at: day(0), reading: 40000)],
      );
      final Item rot = Item(
        id: 'rot',
        name: 'Rotation',
        assetId: 'car',
        kind: ItemKind.usage,
        intervalUnits: 6000,
        log: <ServiceLog>[ServiceLog(id: 'b', at: day(0), reading: 40000)],
      );
      final UpkeepData d =
          UpkeepData(assets: <Asset>[car], items: <Item>[oil, rot]);

      expect(d.track(oil).progress(day(10)), 0);

      car.readings.add(Reading(at: day(0), value: 40000));
      car.readings.add(Reading(at: day(10), value: 43000));

      // One number entered; both gauges moved.
      expect(d.track(oil).progress(day(10)), closeTo(0.6, 0.01));
      expect(d.track(rot).progress(day(10)), closeTo(0.5, 0.01));
    });
  });

  group('reading sanity', () {
    Asset carAt(double v) => Asset(
          id: 'c',
          name: 'Car',
          readings: <Reading>[Reading(at: day(0), value: v)],
        );

    test('a lower number is flagged as a likely typo', () {
      expect(checkReading(carAt(43030), 4303, day(1)),
          ReadingWarning.wentBackwards);
    });

    test('a wild jump is flagged — the classic extra digit', () {
      // 43,030 typed as 430,300 the day after.
      expect(checkReading(carAt(43030), 430300, day(1)),
          ReadingWarning.implausibleJump);
    });

    test('an ordinary week of driving is not flagged', () {
      expect(checkReading(carAt(43030), 43350, day(7)), ReadingWarning.none);
    });

    test('a genuinely long road trip is not flagged', () {
      // 600 miles in two days is a real drive, not a typo.
      expect(checkReading(carAt(43030), 43630, day(2)), ReadingWarning.none);
    });

    test('the first ever reading is never flagged', () {
      expect(checkReading(Asset(id: 'c', name: 'Car'), 999999, day(0)),
          ReadingWarning.none);
    });

    test('the warning text names the number it is arguing with', () {
      final Asset a = carAt(43030);
      final String msg = readingWarningText(
          ReadingWarning.wentBackwards, a, 4303, 'mi');
      expect(msg, contains('43,030'));
    });
  });

  group('deleting a bad reading undoes its damage', () {
    test('the learned rate returns to what it was', () {
      final Asset car = Asset(id: 'c', name: 'Car', readings: <Reading>[
        Reading(at: day(0), value: 40000),
        Reading(at: day(10), value: 40320),
      ]);
      final Item i = Item(
        id: 'i',
        name: 'Oil',
        assetId: 'c',
        kind: ItemKind.usage,
        intervalUnits: 5000,
        log: <ServiceLog>[ServiceLog(id: 'a', at: day(0), reading: 40000)],
      );
      final double? before = Tracked(i, car).unitsPerDay;
      expect(before, closeTo(32, 0.01));

      // Fat finger: an extra zero.
      final Reading bad = Reading(at: day(11), value: 403200);
      car.readings.add(bad);
      expect(Tracked(i, car).unitsPerDay!, greaterThan(1000));

      car.readings.removeWhere((Reading r) => r.id == bad.id);
      expect(Tracked(i, car).unitsPerDay, closeTo(before!, 0.001));
    });

    test('readings carry stable ids across a round trip', () {
      final Reading r = Reading(at: day(0), value: 1);
      final Reading back = Reading.fromJson(r.toJson());
      expect(back.id, r.id);
    });
  });
}
