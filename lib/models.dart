import 'dart:math' as math;

import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// THE MODEL
//
// Three kinds of item, and the app never pretends one is another:
//
//   time    — it knows exactly. Filter every 3 months.
//   usage   — it holds an EXACT target ("rotation at 48,000") and only
//             *guesses* the date, from a rate learned off your readings.
//   inspect — it can't know at all. It asks you to look, on a cadence,
//             and never claims the thing is due.
//
// Everything here is pure Dart so the arithmetic can be tested without a
// device — which matters, because the arithmetic IS the product.
// ═══════════════════════════════════════════════════════════════════════

enum ItemKind { time, usage, inspect }

String kindLabel(ItemKind k) => switch (k) {
      ItemKind.time => 'Time',
      ItemKind.usage => 'Mileage / hours',
      ItemKind.inspect => 'Reminder to look',
    };

/// A thing that owns items — a car, the house, you.
class Asset {
  String id;
  String name;
  bool deleted;
  int updatedAtMs;

  Asset({
    required this.id,
    required this.name,
    this.deleted = false,
    int? updatedAtMs,
  }) : updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'deleted': deleted,
        'updated_at_ms': updatedAtMs,
      };

  static Asset fromJson(Map<String, dynamic> j) => Asset(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        deleted: (j['deleted'] as bool?) ?? false,
        updatedAtMs: (j['updated_at_ms'] as num?)?.toInt(),
      );
}

/// An odometer/hour-meter reading you punched in.
class Reading {
  final DateTime at;
  final double value;

  const Reading({required this.at, required this.value});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at.toIso8601String(),
        'value': value,
      };

  static Reading fromJson(Map<String, dynamic> j) => Reading(
        at: DateTime.parse(j['at'] as String),
        value: (j['value'] as num).toDouble(),
      );
}

/// A time the job actually got done. Drives history AND interval learning.
class ServiceLog {
  final String id;
  final DateTime at;

  /// Odometer at the time, for usage items.
  final double? reading;
  final String? note;

  const ServiceLog({
    required this.id,
    required this.at,
    this.reading,
    this.note,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'at': at.toIso8601String(),
        'reading': reading,
        'note': note,
      };

  static ServiceLog fromJson(Map<String, dynamic> j) => ServiceLog(
        id: (j['id'] as String?) ?? newId(),
        at: DateTime.parse(j['at'] as String),
        reading: (j['reading'] as num?)?.toDouble(),
        note: j['note'] as String?,
      );
}

class LinkRef {
  String label;
  String url;

  LinkRef({required this.label, required this.url});

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'label': label, 'url': url};

  static LinkRef fromJson(Map<String, dynamic> j) => LinkRef(
        label: (j['label'] as String?) ?? '',
        url: (j['url'] as String?) ?? '',
      );
}

class PartRef {
  String number;
  String label;

  PartRef({required this.number, this.label = ''});

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'number': number, 'label': label};

  static PartRef fromJson(Map<String, dynamic> j) => PartRef(
        number: (j['number'] as String?) ?? '',
        label: (j['label'] as String?) ?? '',
      );
}

int _idCounter = 0;
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

// ═══════════════════════════════════════════════════════════════════════

class Item {
  String id;
  String name;
  String assetId;
  ItemKind kind;

  /// time / inspect: how many days between services (or between looks).
  int? intervalDays;

  /// usage: how many units between services. 5000 miles.
  double? intervalUnits;

  /// usage: an optional SECOND limit in months — "every 5,000 miles or 6
  /// months, whichever comes first". Whichever limit is further along drives
  /// the gauge, so a car that barely moves still comes due on time.
  ///
  /// Months rather than days on purpose: "6 months from Feb 2" means Aug 2,
  /// not Feb 2 plus 180 days.
  int? intervalMonths;

  /// Unit label for a usage item: "mi", "hr".
  String unit;

  List<Reading> readings;
  List<ServiceLog> log;
  List<LinkRef> links;
  List<PartRef> parts;

  String? contactName;
  String? contactPhone;
  String? messageTemplate;

  /// Set once the user declines a learned-interval suggestion, so it stays
  /// quiet instead of nagging every time the screen opens.
  double? dismissedSuggestion;

  bool deleted;
  int updatedAtMs;

  Item({
    required this.id,
    required this.name,
    required this.assetId,
    required this.kind,
    this.intervalDays,
    this.intervalUnits,
    this.intervalMonths,
    this.unit = 'mi',
    List<Reading>? readings,
    List<ServiceLog>? log,
    List<LinkRef>? links,
    List<PartRef>? parts,
    this.contactName,
    this.contactPhone,
    this.messageTemplate,
    this.dismissedSuggestion,
    this.deleted = false,
    int? updatedAtMs,
  })  : readings = readings ?? <Reading>[],
        log = log ?? <ServiceLog>[],
        links = links ?? <LinkRef>[],
        parts = parts ?? <PartRef>[],
        updatedAtMs = updatedAtMs ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'asset_id': assetId,
        'kind': kind.name,
        'interval_days': intervalDays,
        'interval_units': intervalUnits,
        'interval_months': intervalMonths,
        'unit': unit,
        'readings': readings.map((Reading r) => r.toJson()).toList(),
        'log': log.map((ServiceLog l) => l.toJson()).toList(),
        'links': links.map((LinkRef l) => l.toJson()).toList(),
        'parts': parts.map((PartRef p) => p.toJson()).toList(),
        'contact_name': contactName,
        'contact_phone': contactPhone,
        'message_template': messageTemplate,
        'dismissed_suggestion': dismissedSuggestion,
        'deleted': deleted,
        'updated_at_ms': updatedAtMs,
      };

  static Item fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? '',
        assetId: (j['asset_id'] as String?) ?? '',
        kind: ItemKind.values.firstWhere(
          (ItemKind k) => k.name == j['kind'],
          orElse: () => ItemKind.time,
        ),
        intervalDays: (j['interval_days'] as num?)?.toInt(),
        intervalUnits: (j['interval_units'] as num?)?.toDouble(),
        intervalMonths: (j['interval_months'] as num?)?.toInt(),
        unit: (j['unit'] as String?) ?? 'mi',
        readings: ((j['readings'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => Reading.fromJson(e as Map<String, dynamic>))
            .toList(),
        log: ((j['log'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => ServiceLog.fromJson(e as Map<String, dynamic>))
            .toList(),
        links: ((j['links'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => LinkRef.fromJson(e as Map<String, dynamic>))
            .toList(),
        parts: ((j['parts'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => PartRef.fromJson(e as Map<String, dynamic>))
            .toList(),
        contactName: j['contact_name'] as String?,
        contactPhone: j['contact_phone'] as String?,
        messageTemplate: j['message_template'] as String?,
        dismissedSuggestion: (j['dismissed_suggestion'] as num?)?.toDouble(),
        deleted: (j['deleted'] as bool?) ?? false,
        updatedAtMs: (j['updated_at_ms'] as num?)?.toInt(),
      );

  // ── the last time this got done ──────────────────────────────────

  ServiceLog? get lastService {
    if (log.isEmpty) return null;
    final List<ServiceLog> sorted = <ServiceLog>[...log]
      ..sort((ServiceLog a, ServiceLog b) => a.at.compareTo(b.at));
    return sorted.last;
  }

  DateTime? get lastDoneAt => lastService?.at;
  double? get lastDoneReading => lastService?.reading;

  /// The exact number that matters for a usage item. This is the headline —
  /// you read your own odometer and compare. It is never an estimate.
  double? get target {
    if (kind != ItemKind.usage) return null;
    final double? base = lastDoneReading;
    if (base == null || intervalUnits == null) return null;
    return base + intervalUnits!;
  }

  // ── readings and the learned rate ────────────────────────────────

  List<Reading> get sortedReadings {
    final List<Reading> r = <Reading>[...readings]
      ..sort((Reading a, Reading b) => a.at.compareTo(b.at));
    return r;
  }

  Reading? get latestReading {
    final List<Reading> r = sortedReadings;
    return r.isEmpty ? null : r.last;
  }

  /// Units per day, learned from your readings. Uses the most recent handful
  /// so a change in driving habits shows up instead of being averaged away
  /// against a reading from a year ago.
  ///
  /// Null when there isn't enough to say — in which case the app shows the
  /// target and no date, rather than inventing one.
  double? get unitsPerDay {
    final List<Reading> r = sortedReadings;
    if (r.length < 2) return null;
    final List<Reading> recent =
        r.length > 6 ? r.sublist(r.length - 6) : r;
    final double days =
        recent.last.at.difference(recent.first.at).inMinutes / 1440.0;
    final double delta = recent.last.value - recent.first.value;
    if (days < 0.5 || delta <= 0) return null;
    return delta / days;
  }

  /// Where the odometer probably sits right now. Falls back to the last
  /// number you actually gave it when there's no rate to project with.
  double? estimatedReading([DateTime? now]) {
    final Reading? last = latestReading;
    if (last == null) return null;
    final double? rate = unitsPerDay;
    if (rate == null) return last.value;
    final DateTime n = now ?? DateTime.now();
    final double days = n.difference(last.at).inMinutes / 1440.0;
    if (days <= 0) return last.value;
    return last.value + rate * days;
  }

  // ── progress ─────────────────────────────────────────────────────

  /// The calendar date the months limit lands on, if there is one.
  /// Calendar arithmetic, not 30-day approximations.
  DateTime? get monthsDueDate {
    final DateTime? done = lastDoneAt;
    final int? months = intervalMonths;
    if (done == null || months == null || months <= 0) return null;
    return addMonths(done, months);
  }

  /// How far through the MILEAGE limit, ignoring any months limit.
  double usageProgress([DateTime? now]) {
    if (kind != ItemKind.usage) return 0;
    final double? base = lastDoneReading;
    final double? span = intervalUnits;
    if (base == null || span == null || span <= 0) return 0;
    final double? est = estimatedReading(now ?? DateTime.now());
    if (est == null) return 0;
    return math.max(0, (est - base) / span);
  }

  /// How far through the MONTHS limit, ignoring mileage.
  double monthsProgress([DateTime? now]) {
    final DateTime n = now ?? DateTime.now();
    final DateTime? done = lastDoneAt;
    final DateTime? due = monthsDueDate;
    if (done == null || due == null) return 0;
    final double span = due.difference(done).inMinutes / 1440.0;
    if (span <= 0) return 0;
    return math.max(0, (n.difference(done).inMinutes / 1440.0) / span);
  }

  /// True when the months limit is the one that will trip first. Only
  /// meaningful on a usage item that has both.
  bool monthsLeads([DateTime? now]) =>
      kind == ItemKind.usage &&
      intervalMonths != null &&
      monthsProgress(now) > usageProgress(now);

  /// 0..1+ — how much of the interval is used up. Past 1.0 is overdue.
  ///
  /// A usage item with a months limit takes whichever is further along:
  /// that's what "every 5,000 miles or 6 months, whichever comes first"
  /// means. A car that barely gets driven still comes due on time.
  double progress([DateTime? now]) {
    final DateTime n = now ?? DateTime.now();
    switch (kind) {
      case ItemKind.time:
      case ItemKind.inspect:
        final DateTime? done = lastDoneAt;
        final int? days = intervalDays;
        if (done == null || days == null || days <= 0) return 0;
        final double elapsed = n.difference(done).inMinutes / 1440.0;
        return math.max(0, elapsed / days);
      case ItemKind.usage:
        return math.max(usageProgress(n), monthsProgress(n));
    }
  }

  GaugeState state([DateTime? now]) {
    final double p = progress(now);
    // An inspect item can never go red. Red means "you are past due", and
    // the whole point of this kind is that the app CANNOT know that — it
    // only knows you haven't looked lately. Amber is the honest ceiling.
    if (kind == ItemKind.inspect) {
      return p >= 0.9 ? GaugeState.ready : GaugeState.healthy;
    }
    if (p >= 1.0) return GaugeState.overdue;
    if (p >= 0.9) return GaugeState.ready;
    return GaugeState.healthy;
  }

  /// When it's expected to come due. For a time item this is exact; for a
  /// usage item it's a projection off the learned rate, and null when
  /// there's no rate yet.
  DateTime? dueDate([DateTime? now]) {
    final DateTime n = now ?? DateTime.now();
    switch (kind) {
      case ItemKind.time:
      case ItemKind.inspect:
        final DateTime? done = lastDoneAt;
        final int? days = intervalDays;
        if (done == null || days == null) return null;
        return done.add(Duration(days: days));
      case ItemKind.usage:
        // Whichever comes first. Either side may be unknown — a mileage
        // date needs a learned rate, and the months limit is optional.
        final DateTime? byMonths = monthsDueDate;
        DateTime? byMileage;
        final double? t = target;
        final double? est = estimatedReading(n);
        final double? rate = unitsPerDay;
        if (t != null && est != null && rate != null && rate > 0) {
          final double remaining = t - est;
          byMileage = remaining <= 0
              ? n
              : n.add(Duration(minutes: (remaining / rate * 1440).round()));
        }
        if (byMileage == null) return byMonths;
        if (byMonths == null) return byMileage;
        return byMileage.isBefore(byMonths) ? byMileage : byMonths;
    }
  }

  /// True when the app should stop guessing and ask for a real number.
  /// Only ever true for usage items, and only once the guess says you're
  /// close AND the last number you gave it has gone stale.
  bool needsReading([DateTime? now]) {
    if (kind != ItemKind.usage) return false;
    if (lastDoneReading == null || intervalUnits == null) return false;
    final DateTime n = now ?? DateTime.now();
    // Deliberately usageProgress, not progress: if the MONTHS limit is what's
    // about to trip, the odometer is beside the point and asking for it is
    // just noise.
    if (usageProgress(n) < 0.9) return false;
    final Reading? last = latestReading;
    if (last == null) return true;
    return n.difference(last.at).inDays >= 2;
  }

  // ── interval learning ────────────────────────────────────────────

  /// What your actual cadence looks like, from the last few times you did
  /// this. Returns null until there are two services to compare.
  ///
  /// Usage items learn in units; time and inspect items learn in days.
  double? get learnedInterval {
    final List<ServiceLog> sorted = <ServiceLog>[...log]
      ..sort((ServiceLog a, ServiceLog b) => a.at.compareTo(b.at));
    if (sorted.length < 2) return null;

    final List<double> deltas = <double>[];
    for (int i = 1; i < sorted.length; i++) {
      if (kind == ItemKind.usage) {
        final double? a = sorted[i - 1].reading, b = sorted[i].reading;
        if (a == null || b == null) continue;
        final double d = b - a;
        if (d > 0) deltas.add(d);
      } else {
        final double d =
            sorted[i].at.difference(sorted[i - 1].at).inMinutes / 1440.0;
        if (d > 0) deltas.add(d);
      }
    }
    if (deltas.isEmpty) return null;
    final List<double> recent =
        deltas.length > 3 ? deltas.sublist(deltas.length - 3) : deltas;
    return recent.reduce((double a, double b) => a + b) / recent.length;
  }

  /// The learned interval, but only when it's worth interrupting you about:
  /// more than 10% off what's set, and not something you already waved away.
  double? get intervalSuggestion {
    final double? learned = learnedInterval;
    if (learned == null) return null;
    final double? current = kind == ItemKind.usage
        ? intervalUnits
        : intervalDays?.toDouble();
    if (current == null || current <= 0) return null;
    final double rounded = kind == ItemKind.usage
        ? (learned / 100).round() * 100.0
        : learned.roundToDouble();
    if (rounded <= 0) return null;
    if ((rounded - current).abs() / current < 0.10) return null;
    if (dismissedSuggestion != null &&
        (dismissedSuggestion! - rounded).abs() < 0.5) {
      return null;
    }
    return rounded;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FORMATTING
// ═══════════════════════════════════════════════════════════════════════

/// Calendar month arithmetic. Six months from Aug 31 is Feb 28/29, not a
/// rolled-over Mar 3 — clamps to the last valid day of the target month.
DateTime addMonths(DateTime d, int n) {
  final int total = d.month - 1 + n;
  final int year = d.year + (total >= 0 ? total ~/ 12 : ((total - 11) ~/ 12));
  final int month = total % 12 < 0 ? total % 12 + 12 : total % 12;
  final int lastDay = DateTime(year, month + 2, 0).day;
  return DateTime(
    year,
    month + 1,
    math.min(d.day, lastDay),
    d.hour,
    d.minute,
  );
}

const List<String> kMonthsShort = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' //
];

String fmtDate(DateTime d) => '${kMonthsShort[d.month - 1]} ${d.day}';

String fmtDateFull(DateTime d) =>
    '${kMonthsShort[d.month - 1]} ${d.day}, ${d.year}';

/// 43030 -> "43,030". Readings are always whole numbers on screen; a
/// fractional odometer is noise.
String fmtNum(double v) {
  final String s = v.round().abs().toString();
  final StringBuffer out = StringBuffer(v < 0 ? '-' : '');
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "in 12 days" / "3 days ago" / "today"
String fmtRelativeDays(int days) {
  if (days == 0) return 'today';
  if (days > 0) return days == 1 ? 'tomorrow' : 'in $days days';
  final int a = -days;
  return a == 1 ? 'yesterday' : '$a days ago';
}
