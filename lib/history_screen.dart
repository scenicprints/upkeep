import 'package:flutter/material.dart';

import 'app_state.dart';
import 'models.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// HISTORY
//
// Everything that's actually been done, newest first. This is also what
// teaches the app your real intervals, so it's worth being able to see
// and correct.
// ═══════════════════════════════════════════════════════════════════════

class _Entry {
  final Item item;
  final ServiceLog log;
  final String assetName;

  const _Entry(this.item, this.log, this.assetName);
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);

    final List<_Entry> entries = <_Entry>[
      for (final Item i in c.data.liveItems)
        for (final ServiceLog l in i.log) _Entry(i, l, c.data.assetName(i)),
    ]..sort((_Entry a, _Entry b) => b.log.at.compareTo(a.log.at));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.chevron_left_rounded,
                        size: 26, color: kTextDim),
                  ),
                  const Text('History',
                      style: TextStyle(fontSize: 15, color: kText)),
                  const Spacer(),
                  Text('${entries.length}',
                      style: mono(size: 12, color: kTextFaint)),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? _empty()
                  : ListView.builder(
                      padding: EdgeInsets.only(
                        bottom: 24 +
                            MediaQuery.of(context).viewPadding.bottom,
                      ),
                      itemCount: entries.length,
                      itemBuilder: (BuildContext context, int i) =>
                          _row(context, c, entries[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('NOTHING LOGGED YET', style: eyebrow(size: 10.5)),
              const SizedBox(height: 12),
              const Text(
                'Every time you tap "I did this", it lands here — and the '
                'app learns your real interval from it.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13, color: kTextDim, height: 1.6),
              ),
            ],
          ),
        ),
      );

  Widget _row(BuildContext context, UpkeepController c, _Entry e) {
    return Dismissible(
      key: ValueKey<String>(e.log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: const Color(0xFF2A1414),
        child: const Icon(Icons.delete_outline_rounded,
            size: 18, color: kOverdue),
      ),
      confirmDismiss: (_) async => _confirmDelete(context, e),
      onDismissed: (_) => c.deleteLog(e.item, e.log),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kHairline, width: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(e.item.name,
                      style: const TextStyle(fontSize: 13.5, color: kText)),
                  const SizedBox(height: 3),
                  Text(
                    e.assetName.isEmpty
                        ? fmtDateFull(e.log.at)
                        : '${e.assetName.toUpperCase()} · '
                            '${fmtDateFull(e.log.at)}',
                    style: mono(size: 10.5, color: kTextFaint),
                  ),
                ],
              ),
            ),
            if (e.log.reading != null)
              Text('${fmtNum(e.log.reading!)} ${e.item.unit}',
                  style: mono(size: 12, color: kTextDim)),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, _Entry e) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Remove this entry?',
            style: TextStyle(fontSize: 16, color: kText)),
        content: Text(
          '${e.item.name} on ${fmtDateFull(e.log.at)}. '
          'The gauge and the learned interval will recalculate.',
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
