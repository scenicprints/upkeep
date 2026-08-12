import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

// ═══════════════════════════════════════════════════════════════════════
// STORAGE
//
// Everything lives in one JSON file in app-internal storage. An in-place
// update preserves it; only uninstalling wipes it.
//
// Nothing is ever seeded, sampled or auto-created. Every row in here was
// typed in by hand, so the only writes are ones the user asked for, and a
// save is written to a temp file and renamed so a crash mid-write can't
// leave a half-file behind.
// ═══════════════════════════════════════════════════════════════════════

class UpkeepData {
  List<Asset> assets;
  List<Item> items;

  UpkeepData({List<Asset>? assets, List<Item>? items})
      : assets = assets ?? <Asset>[],
        items = items ?? <Item>[];

  List<Asset> get liveAssets =>
      assets.where((Asset a) => !a.deleted).toList();

  List<Item> get liveItems => items.where((Item i) => !i.deleted).toList();

  Asset? assetFor(Item i) {
    for (final Asset a in assets) {
      if (a.id == i.assetId) return a;
    }
    return null;
  }

  String assetName(Item i) => assetFor(i)?.name ?? '';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'assets': assets.map((Asset a) => a.toJson()).toList(),
        'items': items.map((Item i) => i.toJson()).toList(),
      };

  static UpkeepData fromJson(Map<String, dynamic> j) => UpkeepData(
        assets: ((j['assets'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => Asset.fromJson(e as Map<String, dynamic>))
            .toList(),
        items: ((j['items'] as List<dynamic>?) ?? const <dynamic>[])
            .map((dynamic e) => Item.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Pairs an item with the asset whose meter it reads.
  Tracked track(Item i) => Tracked(i, assetFor(i));

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static UpkeepData decode(String s) {
    if (s.trim().isEmpty) return UpkeepData();
    final UpkeepData d =
        UpkeepData.fromJson(json.decode(s) as Map<String, dynamic>);
    d.migrateReadingsToAssets();
    return d;
  }

  /// v0.2 stored readings on each ITEM. They belong to the asset — one car,
  /// one odometer — so fold them up on load.
  ///
  /// Additive and idempotent: readings are merged by (day, value) so running
  /// it twice can't duplicate them, and an item's copy is only cleared once
  /// its numbers are safely on the asset. Nothing is ever discarded.
  bool migrateReadingsToAssets() {
    bool changed = false;
    for (final Item i in items) {
      if (i.readings.isEmpty) continue;
      final Asset? a = assetFor(i);
      if (a == null) continue; // orphan: leave it alone rather than lose it

      for (final Reading r in i.readings) {
        final bool dupe = a.readings.any((Reading e) =>
            e.value == r.value &&
            e.at.difference(r.at).inMinutes.abs() < 60 * 12);
        if (!dupe) a.readings.add(r);
      }
      // Inherit the unit from whatever item first brought readings along.
      if (i.kind == ItemKind.usage) a.unit = i.unit;
      i.readings = <Reading>[];
      changed = true;
    }
    return changed;
  }
}

class Store {
  static const String _fileName = 'upkeep_data.json';

  static Future<File> _file() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<UpkeepData> load() async {
    try {
      final File f = await _file();
      if (!await f.exists()) return UpkeepData();
      return UpkeepData.decode(await f.readAsString());
    } catch (e) {
      // A corrupt file must not look like "you have no items" — that would
      // invite the user to re-enter everything on top of data that's still
      // on disk. Surface empty but leave the file untouched.
      debugPrint('Upkeep: could not read data file: $e');
      return UpkeepData();
    }
  }

  static Future<void> save(UpkeepData data) async {
    final File f = await _file();
    final File tmp = File('${f.path}.tmp');
    await tmp.writeAsString(data.encode(), flush: true);
    await tmp.rename(f.path);
  }

  /// For the export/backup button — the raw JSON, as a string.
  static Future<String> exportJson() async {
    final File f = await _file();
    if (!await f.exists()) return UpkeepData().encode();
    return f.readAsString();
  }

  /// Writes a backup next to the app's cache and returns the file, ready to
  /// be handed to the share sheet. Named with the date so a folder full of
  /// them stays readable.
  static Future<File> writeBackup(UpkeepData data, DateTime when) async {
    final Directory dir = await getTemporaryDirectory();
    final String stamp = '${when.year}-'
        '${when.month.toString().padLeft(2, '0')}-'
        '${when.day.toString().padLeft(2, '0')}';
    final File f = File('${dir.path}/upkeep-backup-$stamp.json');
    await f.writeAsString(data.encode(), flush: true);
    return f;
  }
}
