import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

// ═══════════════════════════════════════════════════════════════════════
// FUELWISE BRIDGE
//
// FuelWise records an odometer on every fill-up. Those are readings Upkeep
// would otherwise have to ask for, so a linked car stops being asked.
//
// TWO WAYS IN, and the simple one is the default:
//
//   CLIPBOARD — both apps are on the same phone, so the shortest pipe
//   between them isn't GitHub at all. Copy in FuelWise, paste here. No
//   token, no expiry, no network, nothing to leak.
//
//   GITHUB — optional, for people who want it automatic. Reads
//   fuelwise-data/data.json with a token entered by hand into secure
//   storage. NEVER baked into the build: this repo is public, so anything
//   compiled in can be pulled straight out of the APK, and that repo holds
//   GPS traces.
//
// Both are STRICTLY READ-ONLY. FuelWise owns its data; a stray write from
// here would clobber the app that actually maintains it.
// ═══════════════════════════════════════════════════════════════════════

const String kFuelWiseRepo = 'scenicprints/fuelwise-data';
const String kFuelWisePath = 'data.json';

/// A car as FuelWise knows it.
class FuelWiseVehicle {
  final String id;
  final String name;
  final int? year;
  final String? make;

  const FuelWiseVehicle({
    required this.id,
    required this.name,
    this.year,
    this.make,
  });

  String get label {
    final String prefix = <String>[
      if (year != null) '$year',
      if (make != null && make!.isNotEmpty) make!,
    ].join(' ');
    return prefix.isEmpty ? name : '$name · $prefix';
  }
}

/// One fill-up, reduced to the only part Upkeep cares about.
class FuelWiseFill {
  final String vehicleId;
  final DateTime date;
  final double odometer;

  const FuelWiseFill({
    required this.vehicleId,
    required this.date,
    required this.odometer,
  });
}

class FuelWiseSnapshot {
  final List<FuelWiseVehicle> vehicles;
  final List<FuelWiseFill> fills;

  const FuelWiseSnapshot({required this.vehicles, required this.fills});

  List<FuelWiseFill> forVehicle(String vehicleId) =>
      fills.where((FuelWiseFill f) => f.vehicleId == vehicleId).toList();
}

/// Why a fetch didn't produce data. Each maps to a different thing for the
/// user to do, so they're kept apart rather than collapsed into "failed".
enum FuelWiseError {
  none,
  noToken,
  badToken,
  notPublishedYet,
  network,
  malformed,
  clipboardEmpty,
  clipboardNotFuelWise,
}

String fuelWiseErrorText(FuelWiseError e) => switch (e) {
      FuelWiseError.none => '',
      FuelWiseError.noToken => 'Add a token to connect.',
      FuelWiseError.badToken =>
        "That token can't read fuelwise-data. It needs Contents: Read on "
            'that repository.',
      FuelWiseError.notPublishedYet =>
        "FuelWise hasn't published anything yet. Open FuelWise, connect "
            'its sync, and it will push data.json — then try again.',
      FuelWiseError.network => "Couldn't reach GitHub. Are you online?",
      FuelWiseError.malformed => "data.json isn't in a shape Upkeep knows.",
      FuelWiseError.clipboardEmpty =>
        'Nothing on the clipboard. In FuelWise: Settings → '
            'Copy log for Upkeep, then come back and tap Paste.',
      FuelWiseError.clipboardNotFuelWise =>
        "What's on the clipboard isn't a FuelWise log. Copy it again from "
            'FuelWise → Settings → Copy log for Upkeep.',
    };

class FuelWiseResult {
  final FuelWiseSnapshot? snapshot;
  final FuelWiseError error;

  const FuelWiseResult({this.snapshot, this.error = FuelWiseError.none});

  bool get ok => snapshot != null && error == FuelWiseError.none;
}

class FuelWise {
  static const String _tokenKey = 'upkeep.fuelwise_token';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Future<String?> token() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> get connected async {
    final String? t = await token();
    return t != null && t.trim().isNotEmpty;
  }

  static Future<void> setToken(String value) =>
      _storage.write(key: _tokenKey, value: value.trim());

  static Future<void> clearToken() => _storage.delete(key: _tokenKey);

  /// Reads a snapshot straight off the clipboard.
  ///
  /// Both apps live on the same phone, so the shortest pipe between them
  /// isn't GitHub at all — it's copy over there, paste here. No token, no
  /// expiry, no network, nothing to configure, and nothing to leak.
  static Future<FuelWiseResult> fromClipboard() async {
    ClipboardData? d;
    try {
      d = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      return const FuelWiseResult(error: FuelWiseError.clipboardEmpty);
    }
    final String text = (d?.text ?? '').trim();
    if (text.isEmpty) {
      return const FuelWiseResult(error: FuelWiseError.clipboardEmpty);
    }
    return parseOrError(text);
  }

  /// Shared by the clipboard and network paths. A payload that parses but
  /// contains nothing is treated as "wrong thing copied", not as success —
  /// otherwise a stray clipboard would silently look like an empty log.
  static FuelWiseResult parseOrError(String text) {
    try {
      final FuelWiseSnapshot snap = parseSnapshot(text);
      if (snap.vehicles.isEmpty && snap.fills.isEmpty) {
        return const FuelWiseResult(
            error: FuelWiseError.clipboardNotFuelWise);
      }
      return FuelWiseResult(snapshot: snap);
    } catch (_) {
      return const FuelWiseResult(error: FuelWiseError.clipboardNotFuelWise);
    }
  }

  /// The optional automatic path: fetches data.json from the private repo.
  /// Read-only; no writes, ever.
  static Future<FuelWiseResult> fetch() async {
    final String? t = await token();
    if (t == null || t.trim().isEmpty) {
      return const FuelWiseResult(error: FuelWiseError.noToken);
    }

    http.Response res;
    try {
      res = await http.get(
        Uri.parse(
            'https://api.github.com/repos/$kFuelWiseRepo/contents/$kFuelWisePath'),
        headers: <String, String>{
          'Authorization': 'Bearer ${t.trim()}',
          'Accept': 'application/vnd.github.raw',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 20));
    } catch (_) {
      return const FuelWiseResult(error: FuelWiseError.network);
    }

    if (res.statusCode == 401 || res.statusCode == 403) {
      return const FuelWiseResult(error: FuelWiseError.badToken);
    }
    if (res.statusCode == 404) {
      // Either the token can't see the repo, or FuelWise has never pushed.
      // The second is far likelier and is the actionable one.
      return const FuelWiseResult(error: FuelWiseError.notPublishedYet);
    }
    if (res.statusCode != 200) {
      return const FuelWiseResult(error: FuelWiseError.network);
    }

    try {
      return FuelWiseResult(snapshot: parseSnapshot(res.body));
    } catch (e) {
      debugPrint('Upkeep: could not parse FuelWise data: $e');
      return const FuelWiseResult(error: FuelWiseError.malformed);
    }
  }

  /// Pulled out so it can be tested without a network.
  ///
  /// Defensive on purpose: FuelWise is a separate app that will keep
  /// changing, and a new field over there must never break Upkeep. A
  /// fill-up missing an odometer or a date is skipped, not fatal.
  static FuelWiseSnapshot parseSnapshot(String body) {
    final Map<String, dynamic> j =
        json.decode(body) as Map<String, dynamic>;

    final List<FuelWiseVehicle> vehicles = <FuelWiseVehicle>[];
    for (final dynamic v in (j['vehicles'] as List<dynamic>? ?? const [])) {
      if (v is! Map<String, dynamic>) continue;
      final String? id = v['id'] as String?;
      if (id == null) continue;
      vehicles.add(FuelWiseVehicle(
        id: id,
        name: (v['name'] as String?) ?? 'Vehicle',
        year: (v['year'] as num?)?.toInt(),
        make: v['make'] as String?,
      ));
    }

    final List<FuelWiseFill> fills = <FuelWiseFill>[];
    for (final dynamic f in (j['fillups'] as List<dynamic>? ?? const [])) {
      if (f is! Map<String, dynamic>) continue;
      final String? vehicleId = f['vehicleId'] as String?;
      final num? odo = f['odometer'] as num?;
      final String? date = f['date'] as String?;
      if (vehicleId == null || odo == null || date == null) continue;
      final DateTime? at = DateTime.tryParse(date);
      if (at == null) continue;
      // A zero or negative odometer is a placeholder, not a reading.
      if (odo <= 0) continue;
      fills.add(FuelWiseFill(
        vehicleId: vehicleId,
        date: at,
        odometer: odo.toDouble(),
      ));
    }

    return FuelWiseSnapshot(vehicles: vehicles, fills: fills);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// IMPORT
// ═══════════════════════════════════════════════════════════════════════

class ImportResult {
  final int added;
  final int skipped;

  const ImportResult({required this.added, required this.skipped});
}

/// Folds a vehicle's fill-ups into an asset's meter.
///
/// Purely additive: it never removes or edits a reading you entered, and
/// re-running it can't duplicate anything, so it's safe to call on every
/// launch. A fill-up matching an existing reading (same value, same day) is
/// treated as already known — that's the case where you typed the number in
/// yourself before the sync caught up.
ImportResult importFills(Asset asset, List<FuelWiseFill> fills) {
  int added = 0, skipped = 0;

  for (final FuelWiseFill f in fills) {
    final bool known = asset.readings.any((Reading r) =>
        (r.value - f.odometer).abs() < 0.5 &&
        r.at.difference(f.date).inHours.abs() < 24);
    if (known) {
      skipped++;
      continue;
    }
    asset.readings.add(Reading(
      at: f.date,
      value: f.odometer,
      source: 'fuelwise',
    ));
    added++;
  }

  if (added > 0) {
    asset.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
  }
  return ImportResult(added: added, skipped: skipped);
}

/// Removes only what the bridge put there. Unlinking must not take your own
/// numbers with it.
int removeImported(Asset asset) {
  final int before = asset.readings.length;
  asset.readings.removeWhere((Reading r) => r.source == 'fuelwise');
  return before - asset.readings.length;
}
