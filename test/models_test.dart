import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/models.dart';
import 'package:upkeep/summary.dart';
import 'package:upkeep/theme.dart';

// The arithmetic IS the product. If the target number is wrong, the app is
// worse than useless — you'd trust it and miss the service.

DateTime day(int n) => DateTime(2026, 1, 1).add(Duration(days: n));

/// Readings live on the ASSET now, so tests build a pair. `car` is the
/// meter every usage item in these tests reads from.
late Asset car;

Item usageItem({
  double interval = 5000,
  List<Reading> readings = const <Reading>[],
  List<ServiceLog> log = const <ServiceLog>[],
}) {
  car = Asset(id: 'a', name: 'Car', unit: 'mi', readings: <Reading>[...readings]);
  return Item(
    id: 'i',
    name: 'Oil change',
    assetId: 'a',
    kind: ItemKind.usage,
    intervalUnits: interval,
    unit: 'mi',
    log: <ServiceLog>[...log],
  );
}

/// The item paired with the meter it reads.
Tracked tr(Item i, [Asset? a]) => Tracked(i, a ?? car);

void main() {
  group('usage items — the target is exact', () {
    test('target is last service reading plus the interval', () {
      final Item i = usageItem(log: <ServiceLog>[
        ServiceLog(id: '1', at: day(0), reading: 38410),
      ]);
      expect(i.target, 43410);
    });

    test('no target until it has been logged once', () {
      expect(usageItem().target, isNull);
    });

    test('the target never moves when the guess does', () {
      // Two readings a long way apart would swing any estimate wildly; the
      // headline number must not budge.
      final Item i = usageItem(log: <ServiceLog>[
        ServiceLog(id: '1', at: day(0), reading: 38410),
      ]);
      expect(i.target, 43410);
      car.readings.addAll(<Reading>[
        Reading(at: day(1), value: 38500),
        Reading(at: day(60), value: 42000),
      ]);
      expect(i.target, 43410);
    });
  });

  group('learned rate', () {
    test('needs two readings before it will guess', () {
      final Item i = usageItem(
          readings: <Reading>[Reading(at: day(0), value: 100)]);
      expect(tr(i).unitsPerDay, isNull);
      // With no rate it still reports the last real number, not a guess.
      expect(tr(i).estimatedReading(day(30)), 100);
    });

    test('computes miles per day across the readings', () {
      final Item i = usageItem(readings: <Reading>[
        Reading(at: day(0), value: 1000),
        Reading(at: day(10), value: 1320),
      ]);
      expect(tr(i).unitsPerDay, closeTo(32, 0.01));
    });

    test('projects the current odometer forward from the last reading', () {
      final Item i = usageItem(readings: <Reading>[
        Reading(at: day(0), value: 1000),
        Reading(at: day(10), value: 1320),
      ]);
      expect(tr(i).estimatedReading(day(20)), closeTo(1640, 0.5));
    });

    test('a backwards reading does not produce a negative rate', () {
      // Odometer swap, or a typo. Guessing backwards would be nonsense.
      final Item i = usageItem(readings: <Reading>[
        Reading(at: day(0), value: 5000),
        Reading(at: day(10), value: 400),
      ]);
      expect(tr(i).unitsPerDay, isNull);
    });

    test('uses recent readings so a habit change shows up', () {
      final Item i = usageItem(readings: <Reading>[
        for (int d = 0; d <= 60; d += 10) Reading(at: day(d), value: 1000.0 + d * 10),
        // then a burst of driving
        Reading(at: day(70), value: 2600),
      ]);
      // Recent window is steeper than the lifetime average of 10/day.
      expect(tr(i).unitsPerDay!, greaterThan(12));
    });
  });

  group('progress and state', () {
    test('progress is measured from the last service', () {
      final Item i = usageItem(
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0), reading: 40000)],
        readings: <Reading>[
          Reading(at: day(0), value: 40000),
          Reading(at: day(10), value: 40500),
        ],
      );
      // 500 of 5000 used.
      expect(tr(i).progress(day(10)), closeTo(0.10, 0.001));
      expect(tr(i).state(day(10)), GaugeState.healthy);
    });

    test('turns ready at 90% and overdue past 100%', () {
      final Item i = usageItem(
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0), reading: 40000)],
        readings: <Reading>[
          Reading(at: day(0), value: 40000),
          Reading(at: day(10), value: 44500), // 4500 of 5000 = 90%
        ],
      );
      expect(tr(i).state(day(10)), GaugeState.ready);

      car.readings.add(Reading(at: day(11), value: 45500));
      expect(tr(i).state(day(11)), GaugeState.overdue);
    });

    test('a time item is exact, no readings involved', () {
      final Item i = Item(
        id: 't',
        name: 'Furnace filter',
        assetId: 'h',
        kind: ItemKind.time,
        intervalDays: 90,
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0))],
      );
      expect(Tracked(i, null).progress(day(45)), closeTo(0.5, 0.01));
      expect(Tracked(i, null).dueDate(day(0)), day(90));
      expect(Tracked(i, null).state(day(81)), GaugeState.ready);
      expect(Tracked(i, null).state(day(95)), GaugeState.overdue);
    });

    test('an unlogged item sits at zero rather than reading as overdue', () {
      final Item i = Item(
          id: 'x',
          name: 'New',
          assetId: 'a',
          kind: ItemKind.time,
          intervalDays: 30);
      expect(Tracked(i, null).progress(day(500)), 0);
      expect(Tracked(i, null).state(day(500)), GaugeState.healthy);
    });
  });

  group('mileage OR months — whichever comes first', () {
    Item both({double interval = 5000, int months = 6}) {
      car = Asset(
        id: 'a',
        name: 'Car',
        unit: 'mi',
        readings: <Reading>[Reading(at: day(0), value: 40000)],
      );
      return Item(
        id: 'i',
        name: 'Oil change',
        assetId: 'a',
        kind: ItemKind.usage,
        intervalUnits: interval,
        intervalMonths: months,
        unit: 'mi',
        log: <ServiceLog>[
          ServiceLog(id: '1', at: day(0), reading: 40000),
        ],
      );
    }

    test('months drives the gauge when the car barely moves', () {
      final Item i = both();
      // 200 miles in five months — mileage is nowhere near, the calendar is.
      car.readings.add(Reading(at: day(150), value: 40200));
      expect(tr(i).usageProgress(day(150)), closeTo(0.04, 0.01));
      expect(i.monthsProgress(day(150)), greaterThan(0.8));
      expect(tr(i).progress(day(150)), i.monthsProgress(day(150)));
      expect(tr(i).monthsLeads(day(150)), isTrue);
    });

    test('mileage drives it when the car gets hammered', () {
      final Item i = both();
      car.readings.add(Reading(at: day(30), value: 44700)); // 4,700 in a month
      expect(tr(i).usageProgress(day(30)), closeTo(0.94, 0.01));
      expect(i.monthsProgress(day(30)), lessThan(0.2));
      expect(tr(i).progress(day(30)), closeTo(0.94, 0.01));
      expect(tr(i).monthsLeads(day(30)), isFalse);
    });

    test('the due date is the earlier of the two', () {
      final Item i = both();
      car.readings.add(Reading(at: day(100), value: 40500)); // 5 mi/day
      // At 5 mi/day, 4,500 more miles is ~900 days away. Six months isn't.
      final DateTime? due = tr(i).dueDate(day(100));
      expect(due, isNotNull);
      expect(due!.isBefore(day(200)), isTrue);
      expect(due, i.monthsDueDate);
    });

    test('goes overdue on the calendar even with no miles driven', () {
      final Item i = both();
      expect(tr(i).state(day(200)), GaugeState.overdue);
    });

    test('with no months limit it behaves exactly as before', () {
      final Item i = both(months: 0)..intervalMonths = null;
      expect(i.monthsProgress(day(400)), 0);
      expect(tr(i).progress(day(400)), tr(i).usageProgress(day(400)));
      expect(tr(i).monthsLeads(day(400)), isFalse);
    });

    test('it never asks for an odometer when the calendar is what trips', () {
      final Item i = both();
      car.readings.add(Reading(at: day(150), value: 40200));
      expect(tr(i).progress(day(175)), greaterThan(0.9));
      // Mileage is at 4% — an odometer reading would tell it nothing.
      expect(tr(i).needsReading(day(175)), isFalse);
    });

    test('the headline carries both limits', () {
      final Item i = both();
      final ItemSummary s = summarise(tr(i), day(10));
      expect(s.headline, contains('45,000 mi'));
      expect(s.headline, contains(' or '));
    });

    test('the months date is exact, so it is not marked as a guess', () {
      final Item i = both();
      car.readings.add(Reading(at: day(150), value: 40200));
      final ItemSummary s = summarise(tr(i), day(150));
      expect(s.sub, contains('months first'));
    });

    test('survives a round trip', () {
      final Item back = Item.fromJson(both(months: 6).toJson());
      expect(back.intervalMonths, 6);
      expect(back.monthsDueDate, isNotNull);
    });
  });

  group('calendar month arithmetic', () {
    test('six months from Feb 2 is Aug 2, not plus-180-days', () {
      expect(addMonths(DateTime(2026, 2, 2), 6), DateTime(2026, 8, 2));
    });

    test('rolls the year over', () {
      expect(addMonths(DateTime(2026, 10, 15), 6), DateTime(2027, 4, 15));
      expect(addMonths(DateTime(2026, 12, 1), 1), DateTime(2027, 1, 1));
    });

    test('clamps to the last day of a shorter month', () {
      // Aug 31 + 6 months is Feb 28, not a rolled-over Mar 3.
      expect(addMonths(DateTime(2026, 8, 31), 6), DateTime(2027, 2, 28));
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    });

    test('handles a leap year', () {
      expect(addMonths(DateTime(2027, 8, 31), 6), DateTime(2028, 2, 29));
    });
  });

  group('the 90% ask', () {
    test('asks once the guess says close and the reading is stale', () {
      final Item i = usageItem(
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0), reading: 40000)],
        readings: <Reading>[
          Reading(at: day(0), value: 40000),
          Reading(at: day(10), value: 44500),
        ],
      );
      expect(tr(i).needsReading(day(10)), isFalse, reason: 'reading is fresh');
      expect(tr(i).needsReading(day(13)), isTrue);
    });

    test('never asks below 90%', () {
      final Item i = usageItem(
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0), reading: 40000)],
        readings: <Reading>[
          Reading(at: day(0), value: 40000),
          Reading(at: day(10), value: 40100),
        ],
      );
      expect(tr(i).needsReading(day(60)), isFalse);
    });

    test('time items never ask for a reading', () {
      final Item i = Item(
        id: 't',
        name: 'Filter',
        assetId: 'h',
        kind: ItemKind.time,
        intervalDays: 90,
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0))],
      );
      expect(Tracked(i, null).needsReading(day(89)), isFalse);
    });
  });

  group('interval learning', () {
    test('learns the real cadence from two services', () {
      final Item i = usageItem(interval: 5000, log: <ServiceLog>[
        ServiceLog(id: '1', at: day(0), reading: 30000),
        ServiceLog(id: '2', at: day(100), reading: 36500),
      ]);
      expect(i.learnedInterval, closeTo(6500, 0.1));
      expect(i.intervalSuggestion, 6500);
    });

    test('stays quiet when your cadence matches what is set', () {
      final Item i = usageItem(interval: 5000, log: <ServiceLog>[
        ServiceLog(id: '1', at: day(0), reading: 30000),
        ServiceLog(id: '2', at: day(100), reading: 35100),
      ]);
      expect(i.intervalSuggestion, isNull);
    });

    test('stays quiet once waved away', () {
      final Item i = usageItem(interval: 5000, log: <ServiceLog>[
        ServiceLog(id: '1', at: day(0), reading: 30000),
        ServiceLog(id: '2', at: day(100), reading: 36500),
      ]);
      i.dismissedSuggestion = 6500;
      expect(i.intervalSuggestion, isNull);
    });

    test('needs two services — one tells you nothing', () {
      final Item i = usageItem(log: <ServiceLog>[
        ServiceLog(id: '1', at: day(0), reading: 30000),
      ]);
      expect(i.learnedInterval, isNull);
    });

    test('time items learn in days', () {
      final Item i = Item(
        id: 't',
        name: 'Dentist',
        assetId: 'me',
        kind: ItemKind.time,
        intervalDays: 180,
        log: <ServiceLog>[
          ServiceLog(id: '1', at: day(0)),
          ServiceLog(id: '2', at: day(240)),
        ],
      );
      expect(i.learnedInterval, closeTo(240, 0.1));
      expect(i.intervalSuggestion, 240);
    });
  });

  group('what it says', () {
    test('a usage headline is the exact target, never the guess', () {
      final Item i = usageItem(
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0), reading: 43000)],
        readings: <Reading>[
          Reading(at: day(0), value: 43000),
          Reading(at: day(10), value: 43320),
        ],
      );
      final ItemSummary s = summarise(tr(i), day(10));
      expect(s.headline, '48,000 mi');
      // Everything derived from the rate is marked as approximate.
      expect(s.sub, contains('~'));
    });

    test('an inspect item never claims to be due', () {
      final Item i = Item(
        id: 'b',
        name: 'Brake pads',
        assetId: 'c',
        kind: ItemKind.inspect,
        intervalDays: 60,
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0))],
      );
      final ItemSummary s = summarise(Tracked(i, null), day(70));
      expect(s.headline.toLowerCase(), contains('look'));
      expect(s.headline.toLowerCase(), isNot(contains('due')));
      expect(s.caption, 'TAKE A LOOK');
    });

    test('an inspect item never goes red, however long it is ignored', () {
      // Red means "past due". The app cannot know that brake pads are
      // past due — only that nobody has looked. Amber is the ceiling.
      final Item i = Item(
        id: 'b',
        name: 'Brake pads',
        assetId: 'c',
        kind: ItemKind.inspect,
        intervalDays: 60,
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0))],
      );
      expect(Tracked(i, null).progress(day(600)), greaterThan(5.0));
      expect(Tracked(i, null).state(day(600)), GaugeState.ready);
      expect(summarise(Tracked(i, null), day(600)).caption, 'TAKE A LOOK');
    });

    test('a usage item with no log tells you to log it', () {
      final ItemSummary s = summarise(tr(usageItem()), day(0));
      expect(s.headline, 'Every 5,000 mi');
      expect(s.sub.toLowerCase(), contains('log it once'));
    });
  });

  group('the message', () {
    test('fills the real numbers into the template', () {
      final Item i = usageItem(
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0), reading: 43000)],
      );
      i.messageTemplate = '{asset} needs {item} at {target}.';
      expect(
        renderMessage(tr(i), "Jenny's RAV4", day(5)),
        "Jenny's RAV4 needs Oil change at 48,000 mi.",
      );
    });

    test('the default template still reads properly with no target yet', () {
      final Item i = usageItem();
      final String msg = renderMessage(tr(i), 'The Truck', day(0));
      expect(msg, isNot(contains('{')));
      expect(msg, contains('The Truck'));
    });
  });

  group('formatting', () {
    test('thousands separators', () {
      expect(fmtNum(48000), '48,000');
      expect(fmtNum(999), '999');
      expect(fmtNum(1000), '1,000');
      expect(fmtNum(1234567), '1,234,567');
      expect(fmtNum(43029.6), '43,030');
    });

    test('relative days reads like a person wrote it', () {
      expect(fmtRelativeDays(0), 'today');
      expect(fmtRelativeDays(1), 'tomorrow');
      expect(fmtRelativeDays(12), 'in 12 days');
      expect(fmtRelativeDays(-1), 'yesterday');
      expect(fmtRelativeDays(-5), '5 days ago');
    });
  });

  group('round trip', () {
    test('an item survives being written and read back', () {
      final Item i = usageItem(
        log: <ServiceLog>[ServiceLog(id: '1', at: day(0), reading: 40000)],
      )
        ..links = <LinkRef>[LinkRef(label: 'Book', url: 'https://x.test')]
        ..parts = <PartRef>[PartRef(number: '90915-YZZJ1', label: 'filter')]
        ..contactName = 'Jenny'
        ..contactPhone = '555-0100';

      final Item back = Item.fromJson(i.toJson());
      expect(back.name, i.name);
      expect(back.kind, ItemKind.usage);
      expect(back.target, i.target);
      expect(back.links.first.url, 'https://x.test');
      expect(back.parts.first.number, '90915-YZZJ1');
      expect(back.contactPhone, '555-0100');
      expect(back.log.first.reading, 40000);
    });
  });
}
