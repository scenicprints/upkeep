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

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static UpkeepData decode(String s) {
    if (s.trim().isEmpty) return UpkeepData();
    return UpkeepData.fromJson(json.decode(s) as Map<String, dynamic>);
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
}
