import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'gauge.dart';
import 'item_edit.dart';
import 'models.dart';
import 'summary.dart';
import 'theme.dart';

Future<void> openItem(BuildContext context, Item item) async {
  await Navigator.push<void>(
    context,
    MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(itemId: item.id)),
  );
}

// ═══════════════════════════════════════════════════════════════════════
// ITEM DETAIL
//
// Reads the item back out of the controller by id on every build so it
// stays correct after an edit, a logged service or a new reading.
// ═══════════════════════════════════════════════════════════════════════

class ItemDetailScreen extends StatelessWidget {
  final String itemId;

  const ItemDetailScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);
    final Item? item = c.data.items
        .cast<Item?>()
        .firstWhere((Item? i) => i!.id == itemId, orElse: () => null);

    if (item == null || item.deleted) {
      // Deleted from underneath us (or from the edit screen).
      return const Scaffold(body: SizedBox.shrink());
    }

    final DateTime now = DateTime.now();
    final GaugeState state = item.state(now);
    final ItemSummary s = summarise(item, now);
    final String assetName = c.data.assetName(item);
    final double? suggestion = item.intervalSuggestion;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _bar(context, c, item),
            Expanded(
              child: ListView(
                padding: EdgeInsets.only(
                  bottom: 28 + MediaQuery.of(context).viewPadding.bottom,
                ),
                children: <Widget>[
                  const SizedBox(height: 6),
                  Center(
                    child: Gauge(
                      progress: item.progress(now),
                      state: state,
                      size: 150,
                      stroke: 10,
                      centreLabel:
                          (item.progress(now) * 100).round().toString(),
                      centreCaption: s.caption,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: Text(item.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w500)),
                  ),
                  if (assetName.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Center(
                        child: Text(assetName.toUpperCase(),
                            style: eyebrow(size: 10))),
                  ],
                  const SizedBox(height: 20),

                  if (item.needsReading(now))
                    _AskForReading(item: item, assetName: assetName),

                  _facts(context, c, item, s, now),

                  if (suggestion != null)
                    _Suggestion(item: item, value: suggestion),

                  if (item.links.isNotEmpty) ...<Widget>[
                    _section('LINKS'),
                    for (final LinkRef l in item.links) _linkRow(context, l),
                  ],

                  if (item.parts.isNotEmpty) ...<Widget>[
                    _section('PART NUMBERS'),
                    for (final PartRef p in item.parts) _partRow(context, p),
                  ],

                  _section('SEND A TEXT'),
                  _TextCard(item: item, assetName: assetName),

                  const SizedBox(height: 22),
                  _doneButton(context, c, item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, UpkeepController c, Item item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.chevron_left_rounded,
                size: 26, color: kTextDim),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => ItemEditScreen(existing: item)),
            ),
            style: TextButton.styleFrom(foregroundColor: kTextDim),
            child: const Text('Edit', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  static Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
        child: Text(label, style: eyebrow()),
      );

  Widget _facts(BuildContext context, UpkeepController c, Item item,
      ItemSummary s, DateTime now) {
    final List<Widget> rows = <Widget>[];

    if (item.kind == ItemKind.usage) {
      rows.add(_factRow(
        'Due at',
        item.target == null
            ? '—'
            : '${fmtNum(item.target!)} ${item.unit}',
        emphasise: !item.monthsLeads(now),
      ));
      rows.add(_factRow(
        'Interval',
        item.intervalUnits == null
            ? '—'
            : 'every ${fmtNum(item.intervalUnits!)} ${item.unit}',
      ));
      if (item.intervalMonths != null) {
        final DateTime? byMonths = item.monthsDueDate;
        rows.add(_factRow(
          'Or after',
          byMonths == null
              ? '${item.intervalMonths} months'
              : '${item.intervalMonths} months · ${fmtDate(byMonths)}',
          // Highlight whichever limit is actually going to trip first.
          emphasise: item.monthsLeads(now),
        ));
      }
      final Reading? last = item.latestReading;
      rows.add(_factRow(
        'Last reading',
        last == null
            ? 'none yet'
            : '${fmtNum(last.value)} · ${fmtDate(last.at)}',
      ));
      final double? rate = item.unitsPerDay;
      rows.add(_factRow(
        'Your pace',
        rate == null
            ? 'needs two readings'
            : '~${rate.round()} ${item.unit}/day',
      ));
      final DateTime? due = item.dueDate(now);
      rows.add(_factRow(
          'Guessing', due == null ? 'no date yet' : '~${fmtDate(due)}'));
    } else {
      rows.add(_factRow('Next', s.headline, emphasise: true));
      rows.add(_factRow(
        item.kind == ItemKind.inspect ? 'Look every' : 'Interval',
        item.intervalDays == null ? '—' : '${item.intervalDays} days',
      ));
    }

    final ServiceLog? last = item.lastService;
    rows.add(_factRow(
      item.kind == ItemKind.inspect ? 'Last looked' : 'Last done',
      last == null
          ? 'never'
          : '${fmtDateFull(last.at)}'
              '${last.reading != null ? ' · ${fmtNum(last.reading!)}' : ''}',
    ));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: panelBox(),
      child: Column(children: rows),
    );
  }

  static Widget _factRow(String label, String value,
      {bool emphasise = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 11.5, color: kTextDim)),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: mono(
              size: emphasise ? 13.5 : 11.5,
              color: emphasise ? kReady : kText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkRow(BuildContext context, LinkRef l) {
    return InkWell(
      onTap: () async {
        final Uri? uri = Uri.tryParse(
            l.url.startsWith('http') ? l.url : 'https://${l.url}');
        if (uri == null) return;
        final bool ok =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Couldn't open that link.")));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kHairline, width: 0.5)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(l.label.isEmpty ? l.url : l.label,
                  style: const TextStyle(fontSize: 13, color: kText)),
            ),
            const Icon(Icons.north_east_rounded, size: 15, color: kTextFaint),
          ],
        ),
      ),
    );
  }

  Widget _partRow(BuildContext context, PartRef p) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: p.number));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('Copied ${p.number}')));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: kHairline, width: 0.5)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(p.number,
                  style: mono(size: 13, color: kText, spacing: 0.4)),
            ),
            if (p.label.isNotEmpty)
              Text(p.label,
                  style: const TextStyle(fontSize: 10.5, color: kTextFaint)),
            const SizedBox(width: 8),
            const Icon(Icons.copy_rounded, size: 14, color: kTextFaint),
          ],
        ),
      ),
    );
  }

  Widget _doneButton(BuildContext context, UpkeepController c, Item item) {
    final String label = switch (item.kind) {
      ItemKind.inspect => 'I looked at it',
      _ => 'I did this',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _logDone(context, c, item),
          style: OutlinedButton.styleFrom(
            foregroundColor: kHealthy,
            side: const BorderSide(color: Color(0xFF1E3B2E)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Future<void> _logDone(
      BuildContext context, UpkeepController c, Item item) async {
    double? reading;
    if (item.kind == ItemKind.usage) {
      reading = await promptForNumber(
        context,
        title: 'Done at what ${item.unit == 'mi' ? 'mileage' : item.unit}?',
        hint: item.estimatedReading()?.round().toString(),
      );
      if (reading == null) return; // cancelled
    }
    await c.logService(item, reading: reading);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Logged. Gauge reset.')));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// THE 90% ASK
//
// The one place the app admits it's been guessing. Shown only when the
// projection says you're close and the last real number has gone stale.
// ═══════════════════════════════════════════════════════════════════════

class _AskForReading extends StatelessWidget {
  final Item item;
  final String assetName;

  const _AskForReading({required this.item, required this.assetName});

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);
    final double? est = item.estimatedReading();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(15),
      decoration: panelBox(ready: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('CHECK THE ODOMETER', style: eyebrow(color: kReadyDim)),
          const SizedBox(height: 8),
          Text(
            est == null
                ? 'Getting close. What does it read now?'
                : 'Should be around ${fmtNum(est)} ${item.unit} by now — '
                    "what's it actually read?",
            style: const TextStyle(fontSize: 13, color: kText, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: FilledButton(
              onPressed: () async {
                final double? v = await promptForNumber(
                  context,
                  title: 'Current ${item.unit == 'mi' ? 'mileage' : item.unit}',
                  hint: est?.round().toString(),
                );
                if (v != null) await c.addReading(item, v);
              },
              style: FilledButton.styleFrom(
                backgroundColor: kReady,
                foregroundColor: const Color(0xFF171004),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              child: const Text('Enter a reading',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Offered once the log shows your real cadence differs from what's set.
/// Declining pins the number so it stays quiet.
class _Suggestion extends StatelessWidget {
  final Item item;
  final double value;

  const _Suggestion({required this.item, required this.value});

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);
    final String unit = item.kind == ItemKind.usage ? item.unit : 'days';
    final String current = item.kind == ItemKind.usage
        ? fmtNum(item.intervalUnits ?? 0)
        : '${item.intervalDays ?? 0}';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(15),
      decoration: panelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('YOUR ACTUAL CADENCE', style: eyebrow()),
          const SizedBox(height: 8),
          Text(
            'You do this about every ${fmtNum(value)} $unit, '
            'but it\'s set to $current $unit.',
            style: const TextStyle(fontSize: 13, color: kText, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: () => c.acceptSuggestion(item, value),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kReady,
                  side: const BorderSide(color: kReadyEdge),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Use ${fmtNum(value)}',
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => c.dismissSuggestion(item, value),
              style: TextButton.styleFrom(foregroundColor: kTextFaint),
              child: const Text('Keep mine',
                  style: TextStyle(fontSize: 12.5)),
            ),
          ]),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// TEXT HANDOFF
//
// Composes the message and opens the SMS app with it prefilled. Upkeep
// never sends anything itself — you read it and hit send.
// ═══════════════════════════════════════════════════════════════════════

class _TextCard extends StatelessWidget {
  final Item item;
  final String assetName;

  const _TextCard({required this.item, required this.assetName});

  @override
  Widget build(BuildContext context) {
    final String body = renderMessage(item, assetName);
    final bool hasContact = (item.contactPhone ?? '').trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(15),
      decoration: panelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            hasContact
                ? 'To ${item.contactName ?? item.contactPhone}'
                : 'No one picked yet — set someone under Edit.',
            style: const TextStyle(fontSize: 10.5, color: kTextDim),
          ),
          const SizedBox(height: 8),
          Text('“$body”',
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xFFC6D0DA), height: 1.6)),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            width: double.infinity,
            child: FilledButton(
              onPressed: hasContact ? () => _open(context, body) : null,
              style: FilledButton.styleFrom(
                backgroundColor: kReady,
                foregroundColor: const Color(0xFF171004),
                disabledBackgroundColor: kTrack,
                disabledForegroundColor: kTextFaint,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              child: const Text('Open Messages',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Opens your messaging app with this typed out. Nothing sends '
            'until you tap send.',
            style: TextStyle(fontSize: 10.5, color: kTextFaint, height: 1.45),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, String body) async {
    final String phone =
        (item.contactPhone ?? '').replaceAll(RegExp(r'[^0-9+]'), '');
    // smsto: with a body query is what Android's SMS apps honour; the
    // body must be encoded or anything after a & disappears.
    final Uri uri = Uri.parse(
        'smsto:$phone?body=${Uri.encodeComponent(body)}');
    final bool ok =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open a messaging app.")));
    }
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
