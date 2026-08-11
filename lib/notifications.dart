import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'store.dart';

// ═══════════════════════════════════════════════════════════════════════
// NOTIFICATIONS
//
// One notification per item, fired when it reaches the point you'd want to
// know about:
//
//   time / inspect — at 90% of the interval
//   usage          — at 90% of the PROJECTED date, and it asks for a
//                    reading rather than claiming the thing is due
//
// Scheduled inexactly on purpose: exact alarms need a special permission
// on Android 14+, and nothing here is worth a to-the-minute wake-up.
// Everything is rescheduled from scratch whenever the data changes, so a
// stale notification can't outlive the item that caused it.
// ═══════════════════════════════════════════════════════════════════════

class Notifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const AndroidNotificationDetails _android =
      AndroidNotificationDetails(
    'upkeep_due',
    'Maintenance due',
    channelDescription: 'Tells you when something is ready to be done.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Upkeep: notifications unavailable: $e');
    }
  }

  static Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Wipe and rebuild the whole schedule. Cheap, and it means we never have
  /// to reason about which stale notification belongs to which edit.
  static Future<void> reschedule(UpkeepData data) async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      return;
    }

    final DateTime now = DateTime.now();
    int id = 0;
    for (final Item item in data.liveItems) {
      final DateTime? fireAt = _fireDate(item, now);
      if (fireAt == null) continue;
      if (!fireAt.isAfter(now)) continue;

      final String assetName = data.assetName(item);
      final String where = assetName.isEmpty ? '' : ' · $assetName';
      final String body = switch (item.kind) {
        // Asking for the odometer is only useful when MILEAGE is what's
        // about to trip. If the months limit gets there first, the reading
        // is beside the point.
        ItemKind.usage => item.monthsLeads(fireAt)
            ? 'Coming due on time — ${item.intervalMonths} months.'
            : "Should be near ${_targetText(item)}. What's the odometer?",
        ItemKind.inspect => 'Worth a look.',
        ItemKind.time => 'Coming due.',
      };

      try {
        await _plugin.zonedSchedule(
          id++,
          '${item.name}$where',
          body,
          tz.TZDateTime.from(_atNineAm(fireAt), tz.local),
          const NotificationDetails(android: _android),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e) {
        debugPrint('Upkeep: could not schedule ${item.name}: $e');
      }
      if (id > 60) break; // Android caps pending alarms; stay well under.
    }
  }

  static String _targetText(Item item) {
    final double? t = item.target;
    return t == null ? 'its interval' : '${fmtNum(t)} ${item.unit}';
  }

  /// The moment the item hits 90%.
  static DateTime? _fireDate(Item item, DateTime now) {
    switch (item.kind) {
      case ItemKind.time:
      case ItemKind.inspect:
        final DateTime? done = item.lastDoneAt;
        final int? days = item.intervalDays;
        if (done == null || days == null || days <= 0) return null;
        return done.add(Duration(days: (days * 0.9).round()));
      case ItemKind.usage:
        // Whichever limit trips first gets the notification.
        DateTime? byMileage;
        final double? span = item.intervalUnits;
        final double? rate = item.unitsPerDay;
        final DateTime? mileageDue = item.dueDate(now);
        if (mileageDue != null && span != null && rate != null && rate > 0) {
          // 90% of the way there is one-tenth of an interval before the
          // projected date.
          final double leadDays = span * 0.10 / rate;
          byMileage =
              mileageDue.subtract(Duration(minutes: (leadDays * 1440).round()));
        }

        DateTime? byMonths;
        final DateTime? done = item.lastDoneAt;
        final DateTime? monthsDue = item.monthsDueDate;
        if (done != null && monthsDue != null) {
          final int span90 =
              (monthsDue.difference(done).inMinutes * 0.9).round();
          byMonths = done.add(Duration(minutes: span90));
        }

        if (byMileage == null) return byMonths;
        if (byMonths == null) return byMileage;
        return byMileage.isBefore(byMonths) ? byMileage : byMonths;
    }
  }

  static DateTime _atNineAm(DateTime d) =>
      DateTime(d.year, d.month, d.day, 9);
}
