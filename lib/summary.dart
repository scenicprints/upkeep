import 'models.dart';

// ═══════════════════════════════════════════════════════════════════════
// WHAT AN ITEM SAYS
//
// Kept apart from the widgets so the wording can be tested. The rule that
// matters: for a usage item the HEADLINE is the exact target number, and
// anything derived from a guess is clearly marked with "~" and pushed into
// the smaller line underneath. The app never dresses an estimate up as a
// fact.
// ═══════════════════════════════════════════════════════════════════════

class ItemSummary {
  /// The one line you'd read off the panel. Exact wherever possible.
  final String headline;

  /// Supporting detail. May be a guess; says so when it is.
  final String sub;

  /// Short status word under the gauge.
  final String caption;

  const ItemSummary({
    required this.headline,
    required this.sub,
    required this.caption,
  });
}

ItemSummary summarise(Item item, [DateTime? now]) {
  final DateTime n = now ?? DateTime.now();

  switch (item.kind) {
    case ItemKind.usage:
      return _usage(item, n);
    case ItemKind.time:
      return _time(item, n);
    case ItemKind.inspect:
      return _inspect(item, n);
  }
}

String _captionFor(Item item, DateTime n) {
  final GaugeStateName s = _stateName(item, n);
  return switch (s) {
    GaugeStateName.overdue => 'OVERDUE',
    GaugeStateName.ready =>
      item.kind == ItemKind.inspect ? 'TAKE A LOOK' : 'READY',
    GaugeStateName.healthy => 'ON SCHEDULE',
  };
}

enum GaugeStateName { healthy, ready, overdue }

GaugeStateName _stateName(Item item, DateTime n) {
  final double p = item.progress(n);
  // Mirrors Item.state(): an inspect item never reads as overdue, because
  // the app has no way of knowing that.
  if (item.kind == ItemKind.inspect) {
    return p >= 0.9 ? GaugeStateName.ready : GaugeStateName.healthy;
  }
  if (p >= 1.0) return GaugeStateName.overdue;
  if (p >= 0.9) return GaugeStateName.ready;
  return GaugeStateName.healthy;
}

ItemSummary _usage(Item item, DateTime n) {
  final double? target = item.target;
  final String caption = _captionFor(item, n);
  final DateTime? byMonths = item.monthsDueDate;

  if (target == null) {
    final String every = item.intervalUnits == null
        ? 'No interval set'
        : 'Every ${fmtNum(item.intervalUnits!)} ${item.unit}';
    return ItemSummary(
      headline: item.intervalMonths == null
          ? every
          : '$every or ${_months(item.intervalMonths!)}',
      sub: 'Log it once to set the target.',
      caption: caption,
    );
  }

  // Both limits belong in the headline: "whichever comes first" means both
  // numbers are things you'd check. Both are exact — the months date is
  // calendar arithmetic off the last service, not a projection.
  final String headline = byMonths == null
      ? '${fmtNum(target)} ${item.unit}'
      : '${fmtNum(target)} ${item.unit} or ${fmtDate(byMonths)}';

  // Sub-line: where we think you are, and roughly when. Guesses, marked.
  final double? est = item.estimatedReading(n);
  final DateTime? due = item.dueDate(n);
  final List<String> bits = <String>[];

  if (est != null) {
    final double remaining = target - est;
    if (remaining > 0) {
      bits.add('~${fmtNum(remaining)} ${item.unit} to go');
    } else {
      bits.add('past it by ~${fmtNum(-remaining)} ${item.unit}');
    }
  }
  if (due != null) {
    final int days = due.difference(n).inDays;
    // Only the mileage side is a guess. When the calendar is what trips
    // first, the date is exact and the "~" would be a lie.
    final bool exact = item.monthsLeads(n);
    final String when = days <= 0 ? 'now' : fmtRelativeDays(days);
    bits.add(exact ? when : (days <= 0 ? 'now' : '~$when'));
  }
  if (byMonths != null && item.monthsLeads(n)) {
    bits.add('months first');
  }
  if (bits.isEmpty) {
    bits.add('Add a reading and it starts guessing the date.');
  }

  return ItemSummary(
    headline: headline,
    sub: bits.join(' · '),
    caption: caption,
  );
}

String _months(int m) => m == 1 ? '1 month' : '$m months';

ItemSummary _time(Item item, DateTime n) {
  final DateTime? due = item.dueDate(n);
  final String caption = _captionFor(item, n);

  if (due == null) {
    return ItemSummary(
      headline: item.intervalDays == null
          ? 'No interval set'
          : 'Every ${_days(item.intervalDays!)}',
      sub: 'Log it once to start the clock.',
      caption: caption,
    );
  }

  final int days = due.difference(n).inDays;
  return ItemSummary(
    headline: 'Due ${fmtDate(due)}',
    sub: days < 0
        ? '${-days} days overdue · every ${_days(item.intervalDays ?? 0)}'
        : '${fmtRelativeDays(days)} · every ${_days(item.intervalDays ?? 0)}',
    caption: caption,
  );
}

ItemSummary _inspect(Item item, DateTime n) {
  final DateTime? due = item.dueDate(n);
  final String caption = _captionFor(item, n);

  if (due == null) {
    return ItemSummary(
      headline: item.intervalDays == null
          ? 'No cadence set'
          : 'Look every ${_days(item.intervalDays!)}',
      sub: "Mark it looked-at once and the cadence starts.",
      caption: caption,
    );
  }

  final int days = due.difference(n).inDays;
  return ItemSummary(
    // Deliberately never "due" — the app cannot know that this needs doing.
    headline: days <= 0 ? 'Worth a look' : 'Look ${fmtDate(due)}',
    sub: days < 0
        ? 'last looked ${-days + (item.intervalDays ?? 0)} days ago'
        : '${fmtRelativeDays(days)} · every ${_days(item.intervalDays ?? 0)}',
    caption: caption,
  );
}

String _days(int d) {
  if (d <= 0) return '—';
  if (d % 365 == 0) {
    final int y = d ~/ 365;
    return y == 1 ? 'year' : '$y years';
  }
  if (d % 30 == 0) {
    final int m = d ~/ 30;
    return m == 1 ? 'month' : '$m months';
  }
  if (d % 7 == 0) {
    final int w = d ~/ 7;
    return w == 1 ? 'week' : '$w weeks';
  }
  return d == 1 ? 'day' : '$d days';
}

/// The text that goes into the SMS app. Placeholders are filled from the
/// item so the message carries the actual numbers.
///
///   {item}   Oil Change
///   {asset}  Jenny's RAV4
///   {target} 48,000 mi
///   {due}    Sep 14
String renderMessage(Item item, String assetName, [DateTime? now]) {
  final DateTime n = now ?? DateTime.now();
  final String template = (item.messageTemplate ?? '').trim().isEmpty
      ? _defaultTemplate(item)
      : item.messageTemplate!;
  final double? t = item.target;
  final DateTime? due = item.dueDate(n);

  return template
      .replaceAll('{item}', item.name)
      .replaceAll('{asset}', assetName)
      .replaceAll('{target}', t == null ? '' : '${fmtNum(t)} ${item.unit}')
      .replaceAll('{due}', due == null ? '' : fmtDate(due))
      .replaceAll('  ', ' ')
      .trim();
}

String _defaultTemplate(Item item) => switch (item.kind) {
      ItemKind.usage =>
        'Hey — {asset} is coming up on {item} at {target}. Want me to book it?',
      ItemKind.time => 'Reminder: {item} for {asset} is due {due}.',
      ItemKind.inspect => 'Can you take a look at {item} on {asset}?',
    };
