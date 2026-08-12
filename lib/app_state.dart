import 'package:flutter/material.dart';

import 'fuelwise.dart';
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
    // A service reading is also a meter reading — no reason to make the user
    // enter the same number twice. It lands on the ASSET, so every other
    // item on that car benefits from it too.
    final Asset? a = data.assetFor(item);
    if (reading != null && a != null) {
      a.readings.add(Reading(at: when, value: reading));
      a.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    }
    await upsertItem(item);
  }

  // ── the meter (lives on the asset) ───────────────────────────────

  Future<void> addReading(Asset asset, double value, {DateTime? at}) async {
    asset.readings.add(Reading(at: at ?? DateTime.now(), value: value));
    asset.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  Future<void> editReading(Asset asset, Reading old,
      {double? value, DateTime? at}) async {
    final int i = asset.readings.indexWhere((Reading r) => r.id == old.id);
    if (i < 0) return;
    asset.readings[i] = old.copyWith(value: value, at: at);
    asset.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  /// Deleting a bad reading has to actually undo its effect — otherwise a
  /// mistyped number keeps skewing the learned rate forever.
  Future<void> deleteReading(Asset asset, Reading r) async {
    asset.readings.removeWhere((Reading e) => e.id == r.id);
    asset.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  Future<void> setAssetUnit(Asset asset, String unit) async {
    asset.unit = unit;
    asset.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  /// Assets that actually have a meter worth updating.
  List<Asset> get meteredAssets {
    final Set<String> ids = data.liveItems
        .where((Item i) => i.kind == ItemKind.usage)
        .map((Item i) => i.assetId)
        .toSet();
    return data.liveAssets.where((Asset a) => ids.contains(a.id)).toList();
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

  Tracked track(Item item) => data.track(item);

  /// Worst first: overdue, then closest to due. This is the panel order.
  List<Tracked> get ranked {
    final DateTime now = DateTime.now();
    final List<Tracked> list =
        data.liveItems.map((Item i) => data.track(i)).toList();
    list.sort(
        (Tracked a, Tracked b) => b.progress(now).compareTo(a.progress(now)));
    return list;
  }

  int countIn(GaugeState s) {
    final DateTime now = DateTime.now();
    return data.liveItems
        .where((Item i) => data.track(i).state(now) == s)
        .length;
  }

  /// The worst thing on the panel — what the gremlin reacts to.
  GaugeState get worstState {
    if (countIn(GaugeState.overdue) > 0) return GaugeState.overdue;
    if (countIn(GaugeState.ready) > 0) return GaugeState.ready;
    return GaugeState.healthy;
  }

  // ── FuelWise ─────────────────────────────────────────────────────

  List<Asset> get linkedAssets => data.liveAssets
      .where((Asset a) => a.fuelwiseVehicleId != null)
      .toList();

  Future<void> linkAsset(Asset asset, String? vehicleId) async {
    asset.fuelwiseVehicleId = vehicleId;
    asset.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
  }

  /// Unlinking pulls back only the readings the bridge added. Anything you
  /// typed stays — losing your own numbers because a link was removed would
  /// be indefensible.
  Future<int> unlinkAsset(Asset asset) async {
    final int removed = removeImported(asset);
    asset.fuelwiseVehicleId = null;
    asset.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    await _commit();
    return removed;
  }

  /// Pulls fill-ups into every linked asset. Additive and idempotent, so
  /// it's safe on every launch.
  Future<ImportResult> importFromFuelWise(FuelWiseSnapshot snap) async {
    int added = 0, skipped = 0;
    for (final Asset a in linkedAssets) {
      final ImportResult r =
          importFills(a, snap.forVehicle(a.fuelwiseVehicleId!));
      added += r.added;
      skipped += r.skipped;
    }
    if (added > 0) await _commit();
    return ImportResult(added: added, skipped: skipped);
  }

  /// Silent refresh on launch. Never surfaces an error — if FuelWise isn't
  /// reachable the app simply carries on with what it already has.
  Future<void> refreshFuelWiseQuietly() async {
    if (linkedAssets.isEmpty) return;
    if (!await FuelWise.connected) return;
    final FuelWiseResult res = await FuelWise.fetch();
    if (res.ok) await importFromFuelWise(res.snapshot!);
  }

  // ── backup ───────────────────────────────────────────────────────

  /// Replaces everything with the contents of a backup. Destructive by
  /// definition, so the UI confirms with counts before calling it.
  Future<void> restore(UpkeepData incoming) async {
    data = incoming;
    await _commit();
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
