import 'package:flutter/material.dart';

import 'models.dart';
import 'notifications.dart';
import 'store.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// APP STATE
//
// One controller holding the whole (small) dataset. Every mutation goes
// through here so there is exactly one place that writes to disk and
// reschedules notifications — and so nothing can quietly save without a
// user action behind it.
// ═══════════════════════════════════════════════════════════════════════

class UpkeepController extends ChangeNotifier {
  UpkeepData data = UpkeepData();
  bool loaded = false;

  Future<void> load() async {
    data = await Store.load();
    loaded = true;
    notifyListeners();
    await Notifications.reschedule(data);
  }

  Future<void> _commit() async {
    notifyListeners();
    await Store.save(data);
    await Notifications.reschedule(data);
  }

  // ── assets ───────────────────────────────────────────────────────

  Future<Asset> addAsset(String name) async {
    final Asset a = Asset(id: newId(), name: name.trim());
    data.assets.add(a);
    await _commit();
    return a;
  }

  Future<void> renameAsset(Asset a, String name) async {
    a.name = name.trim();
    a.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  /// Assets are only removable once nothing points at them — otherwise
  /// items would silently lose their heading.
  bool assetInUse(Asset a) =>
      data.liveItems.any((Item i) => i.assetId == a.id);

  Future<void> deleteAsset(Asset a) async {
    if (assetInUse(a)) return;
    a.deleted = true;
    a.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  // ── items ────────────────────────────────────────────────────────

  Future<void> upsertItem(Item item) async {
    item.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final int idx = data.items.indexWhere((Item i) => i.id == item.id);
    if (idx >= 0) {
      data.items[idx] = item;
    } else {
      data.items.add(item);
    }
    await _commit();
  }

  Future<void> deleteItem(Item item) async {
    item.deleted = true;
    item.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  /// "I did this." Logs the service, which also resets the gauge (progress
  /// is measured from the last log) and feeds interval learning.
  Future<void> logService(Item item,
      {double? reading, DateTime? at, String? note}) async {
    final DateTime when = at ?? DateTime.now();
    item.log.add(ServiceLog(
      id: newId(),
      at: when,
      reading: reading,
      note: note,
    ));
    // A service reading is also a reading — no reason to make the user
    // enter the same number twice.
    if (reading != null) {
      item.readings.add(Reading(at: when, value: reading));
    }
    await upsertItem(item);
  }

  Future<void> addReading(Item item, double value, {DateTime? at}) async {
    item.readings.add(Reading(at: at ?? DateTime.now(), value: value));
    await upsertItem(item);
  }

  Future<void> deleteLog(Item item, ServiceLog entry) async {
    item.log.removeWhere((ServiceLog l) => l.id == entry.id);
    await upsertItem(item);
  }

  Future<void> acceptSuggestion(Item item, double value) async {
    if (item.kind == ItemKind.usage) {
      item.intervalUnits = value;
    } else {
      item.intervalDays = value.round();
    }
    item.dismissedSuggestion = null;
    await upsertItem(item);
  }

  Future<void> dismissSuggestion(Item item, double value) async {
    item.dismissedSuggestion = value;
    await upsertItem(item);
  }

  // ── derived ──────────────────────────────────────────────────────

  /// Worst first: overdue, then closest to due. This is the panel order.
  List<Item> get ranked {
    final DateTime now = DateTime.now();
    final List<Item> list = data.liveItems;
    list.sort((Item a, Item b) => b.progress(now).compareTo(a.progress(now)));
    return list;
  }

  int countIn(GaugeState s) {
    final DateTime now = DateTime.now();
    return data.liveItems.where((Item i) => i.state(now) == s).length;
  }
}

/// Plumbing so any screen can reach the controller.
class UpkeepScope extends InheritedNotifier<UpkeepController> {
  const UpkeepScope({
    super.key,
    required UpkeepController super.notifier,
    required super.child,
  });

  static UpkeepController of(BuildContext context) {
    final UpkeepScope? scope =
        context.dependOnInheritedWidgetOfExactType<UpkeepScope>();
    assert(scope != null, 'No UpkeepScope in the tree');
    return scope!.notifier!;
  }
}
