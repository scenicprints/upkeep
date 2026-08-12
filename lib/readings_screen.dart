import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// THE METER
//
// Readings belong to the ASSET, so this is where they're seen and fixed.
// One bad number skews the learned rate and every date derived from it,
// and until this screen existed there was no way to take one back.
// ═══════════════════════════════════════════════════════════════════════

/// Saves a reading, but makes the user look twice at one that seems wrong.
/// Never blocks it outright — a swapped cluster or a repaired meter is a
/// real thing, and the app shouldn't argue with the person holding the car.
Future<bool> saveReading(
  BuildContext context,
  UpkeepController c,
  Asset asset,
  double value, {
  DateTime? at,
}) async {
  final ReadingWarning w = checkReading(asset, value, at);
  if (w != ReadingWarning.none) {
    final bool ok = await _confirmOdd(
        context, readingWarningText(w, asset, value, asset.unit));
    if (!ok) return false;
  }
  await c.addReading(asset, value, at: at);
  return true;
}

Future<bool> _confirmOdd(BuildContext context, String message) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kPanel,
      title: const Text('Check that number',
          style: TextStyle(fontSize: 16, color: kText)),
      content: Text(message,
          style: const TextStyle(fontSize: 13, color: kTextDim, height: 1.5)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: kTextDim),
          child: const Text('Let me fix it'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: kReady),
          child: const Text("It's right"),
        ),
      ],
    ),
  );
  return ok ?? false;
}

// ═══════════════════════════════════════════════════════════════════════

class AssetReadingsScreen extends StatelessWidget {
  final String assetId;

  const AssetReadingsScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);
    final Asset? asset = c.data.assets
        .cast<Asset?>()
        .firstWhere((Asset? a) => a!.id == assetId, orElse: () => null);
    if (asset == null || asset.deleted) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final List<Reading> readings = asset.sortedReadings.reversed.toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.chevron_left_rounded,
                        size: 26, color: kTextDim),
                  ),
                  Expanded(
                    child: Text(asset.name,
                        style: const TextStyle(fontSize: 15, color: kText),
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: () => _add(context, c, asset),
                    style: TextButton.styleFrom(foregroundColor: kReady),
                    child: const Text('Add',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            _paceCard(c, asset),
            Expanded(
              child: readings.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom:
                            24 + MediaQuery.of(context).viewPadding.bottom,
                      ),
                      itemCount: readings.length,
                      itemBuilder: (BuildContext context, int i) => _row(
                        context,
                        c,
                        asset,
                        readings[i],
                        // The most recent reading is the one the estimate
                        // hangs off, so a typo there does the most damage.
                        newest: i == 0,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paceCard(UpkeepController c, Asset asset) {
    // Any usage item on this asset shares the same meter, so any of them
    // gives the same learned pace.
    final Item? any = c.data.liveItems
        .cast<Item?>()
        .firstWhere((Item? i) => i!.assetId == asset.id, orElse: () => null);
    final double? rate = any == null ? null : c.track(any).unitsPerDay;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: panelBox(),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              rate == null
                  ? 'Two readings and it learns your pace.'
                  : 'About ${rate.round()} ${asset.unit} a day.',
              style: const TextStyle(fontSize: 12.5, color: kTextDim),
            ),
          ),
          Text('${asset.readings.length}',
              style: mono(size: 12, color: kTextFaint)),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('NO READINGS YET', style: eyebrow(size: 10.5)),
              const SizedBox(height: 12),
              const Text(
                'Punch in the odometer whenever you notice it. Every '
                'mileage item on this one uses the same number.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: kTextDim, height: 1.6),
              ),
            ],
          ),
        ),
      );

  Widget _row(BuildContext context, UpkeepController c, Asset asset,
      Reading r, {required bool newest}) {
    return Dismissible(
      key: ValueKey<String>(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: const Color(0xFF2A1414),
        child: const Icon(Icons.delete_outline_rounded,
            size: 18, color: kOverdue),
      ),
      confirmDismiss: (_) async => _confirmDelete(context, asset, r),
      onDismissed: (_) => c.deleteReading(asset, r),
      child: InkWell(
        onTap: () => _edit(context, c, asset, r),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: kHairline, width: 0.5)),
          ),
          child: Row(
            children: <Widget>[
              Text('${fmtNum(r.value)} ${asset.unit}',
                  style: mono(
                      size: 14, color: newest ? kText : kTextDim)),
              const Spacer(),
              Text(fmtDateFull(r.at),
                  style: mono(size: 11, color: kTextFaint)),
              const SizedBox(width: 10),
              const Icon(Icons.edit_outlined, size: 14, color: kTextFaint),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add(
      BuildContext context, UpkeepController c, Asset asset) async {
    final double? v = await promptForNumber(
      context,
      title: 'Current ${asset.unit == 'mi' ? 'mileage' : asset.unit}',
      hint: asset.latestReading?.value.round().toString(),
    );
    if (v == null || !context.mounted) return;
    await saveReading(context, c, asset, v);
  }

  Future<void> _edit(BuildContext context, UpkeepController c, Asset asset,
      Reading r) async {
    final double? v = await promptForNumber(
      context,
      title: 'Fix this reading',
      hint: r.value.round().toString(),
    );
    if (v == null) return;
    await c.editReading(asset, r, value: v);
  }

  Future<bool> _confirmDelete(
      BuildContext context, Asset asset, Reading r) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Remove this reading?',
            style: TextStyle(fontSize: 16, color: kText)),
        content: Text(
          '${fmtNum(r.value)} ${asset.unit} on ${fmtDateFull(r.at)}. '
          'The learned pace and every projected date will recalculate.',
          style: const TextStyle(fontSize: 13, color: kTextDim, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: kTextDim),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: kOverdue),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

// ═══════════════════════════════════════════════════════════════════════

/// Small number prompt. Returns null when cancelled — callers must treat
/// that as "do nothing", never as zero.
Future<double?> promptForNumber(
  BuildContext context, {
  required String title,
  String? hint,
}) async {
  final TextEditingController ctrl = TextEditingController();
  return showDialog<double>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kPanel,
      title: Text(title, style: const TextStyle(fontSize: 16, color: kText)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: mono(size: 18, color: kText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: mono(size: 18, color: kTextFaint),
          enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kPanelEdge)),
          focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kReady)),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          style: TextButton.styleFrom(foregroundColor: kTextFaint),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final double? v =
                double.tryParse(ctrl.text.replaceAll(',', '').trim());
            Navigator.pop(ctx, v);
          },
          style: TextButton.styleFrom(foregroundColor: kReady),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
