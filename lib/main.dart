import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'backup_screen.dart';
import 'fuelwise_screen.dart';
import 'gauge.dart';
import 'history_screen.dart';
import 'item_detail.dart';
import 'item_edit.dart';
import 'mascot.dart';
import 'models.dart';
import 'notifications.dart';
import 'readings_screen.dart';
import 'summary.dart';
import 'theme.dart';
import 'updater.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Android 15+ forces edge-to-edge regardless, and ignores
  // systemNavigationBarColor. Opt in explicitly so the insets are reported
  // properly and the app paints its own background behind the bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const UpkeepApp());
}

class UpkeepApp extends StatefulWidget {
  /// Tests inject a ready-made controller so they don't depend on plugin
  /// channels resolving inside a pump. Production leaves it null.
  final UpkeepController? controller;

  const UpkeepApp({super.key, this.controller});

  @override
  State<UpkeepApp> createState() => _UpkeepAppState();
}

class _UpkeepAppState extends State<UpkeepApp> {
  late final UpkeepController _controller =
      widget.controller ?? UpkeepController();

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      Notifications.init().then((_) => _controller.load());
    }
  }

  @override
  void dispose() {
    // Only dispose what we made; an injected one belongs to the caller.
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return UpkeepScope(
      notifier: _controller,
      child: MaterialApp(
        title: 'Upkeep',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const ClusterScreen(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// THE CLUSTER — home screen
// ═══════════════════════════════════════════════════════════════════════

class ClusterScreen extends StatefulWidget {
  const ClusterScreen({super.key});

  @override
  State<ClusterScreen> createState() => _ClusterScreenState();
}

class _ClusterScreenState extends State<ClusterScreen> {
  Timer? _launchCheck;

  @override
  void initState() {
    super.initState();
    // Silent check on launch — only interrupts if there's genuinely a
    // newer release. Held so it can be cancelled if the screen goes away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launchCheck = Timer(const Duration(milliseconds: 900), () {
        if (mounted) autoCheck(context);
      });
      Notifications.requestPermission();
      // Quietly top up any linked car's meter. Additive and idempotent, and
      // it never surfaces an error — if FuelWise can't be reached the app
      // just carries on with the readings it already has.
      UpkeepScope.of(context).refreshFuelWiseQuietly();
    });
  }

  @override
  void dispose() {
    _launchCheck?.cancel();
    super.dispose();
  }

  static const List<String> _days = <String>[
    'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN' //
  ];
  static const List<String> _months = <String>[
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC' //
  ];

  String get _today {
    final DateTime n = DateTime.now();
    return '${_days[n.weekday - 1]} ${_months[n.month - 1]} ${n.day}';
  }

  Future<void> _add() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const ItemEditScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);
    final List<Tracked> items = c.ranked;

    return Scaffold(
      // No SafeArea around the whole column: the nav bar's background has to
      // run underneath the system bar while its LABELS stay above it, so each
      // end insets itself. See _nav().
      body: Column(
        children: <Widget>[
          SafeArea(bottom: false, child: _header(c)),
          Expanded(
            child: !c.loaded
                ? const SizedBox.shrink()
                : items.isEmpty
                    ? const _EmptyCluster()
                    : _panel(c, items),
          ),
          _nav(),
        ],
      ),
    );
  }

  Widget _header(UpkeepController c) {
    // The gremlin rides in the header, sized down. He carries no
    // information of his own — the counts below already say it — but his
    // eyes take the worst state on the panel, so the screen has a pulse
    // before you've read a word of it.
    final MascotMood mood = moodFor(
      c.worstState,
      anyItems: c.data.liveItems.isNotEmpty,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 0),
      child: Row(
        children: <Widget>[
          Mascot(size: 42, mood: mood),
          const SizedBox(width: 4),
          Text('UPKEEP',
              style: eyebrow(size: 11, color: kTextDim)
                  .copyWith(letterSpacing: 2.4)),
          const Spacer(),
          Text(_today, style: mono(size: 11, color: kTextFaint)),
          IconButton(
            onPressed: () => showSettingsSheet(context),
            icon: const Icon(Icons.tune_rounded, size: 19, color: kTextFaint),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  /// The panel proper: a status strip, the worst item as a hero, then
  /// everything else as compact rows.
  Widget _panel(UpkeepController c, List<Tracked> items) {
    final Tracked hero = items.first;
    final List<Tracked> rest = items.skip(1).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        _statusStrip(c),
        _HeroCard(tracked: hero, assetName: c.data.assetName(hero.item)),
        if (rest.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 8),
            child: Text('EVERYTHING ELSE', style: eyebrow()),
          ),
          for (int i = 0; i < rest.length; i++)
            _ItemRow(
              tracked: rest[i],
              assetName: c.data.assetName(rest[i].item),
              delay: Duration(milliseconds: 90 + i * 70),
            ),
        ],
        _meters(context, c),
      ],
    );
  }

  /// One odometer entry per CAR, not per item. Parked at the bottom rather
  /// than the top: it's a thing you do occasionally, not something that
  /// should compete with the gauges for attention.
  Widget _meters(BuildContext context, UpkeepController c) {
    final List<Asset> metered = c.meteredAssets;
    if (metered.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 26, 16, 8),
          child: Text('ODOMETERS', style: eyebrow()),
        ),
        for (final Asset a in metered)
          InkWell(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => AssetReadingsScreen(assetId: a.id)),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(a.name,
                        style:
                            const TextStyle(fontSize: 13, color: kTextDim)),
                  ),
                  Text(
                    a.latestReading == null
                        ? 'add one'
                        : '${fmtNum(a.latestReading!.value)} ${a.unit}',
                    style: mono(size: 12, color: kText),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: kTextFaint),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusStrip(UpkeepController c) {
    final int overdue = c.countIn(GaugeState.overdue);
    final int ready = c.countIn(GaugeState.ready);
    final int ok = c.countIn(GaugeState.healthy);

    Widget dot(Color col, String text) => Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: col, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(fontSize: 11, color: kTextDim)),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Row(children: <Widget>[
        if (overdue > 0) dot(kOverdue, '$overdue overdue'),
        if (ready > 0) dot(kReady, '$ready ready'),
        if (ok > 0) dot(kHealthy, '$ok on schedule'),
      ]),
    );
  }

  Widget _nav() {
    Widget item(String label, {bool active = false, VoidCallback? onTap}) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: eyebrow(size: 9.5, color: active ? kReady : kTextFaint)
                  .copyWith(letterSpacing: 1.4),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: kNavBg,
        border: Border(top: BorderSide(color: kHairline, width: 0.5)),
      ),
      // SafeArea INSIDE the coloured container: the background fills the
      // gesture-bar strip while the labels are pushed clear of it. Reading
      // MediaQuery padding by hand here is what put the labels under the
      // system nav bar — under Android 15's forced edge-to-edge that value
      // can't be trusted from an ancestor context.
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            item('CLUSTER', active: true),
            item('HISTORY', onTap: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const HistoryScreen()),
              );
            }),
            item('ADD', onTap: _add),
          ],
        ),
      ),
    );
  }
}

/// The empty state. The gremlin is the whole screen — there is nothing to
/// read yet, so there is nothing else on it.
class _EmptyCluster extends StatelessWidget {
  const _EmptyCluster();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Mascot(size: 148, mood: MascotMood.idle),
            const SizedBox(height: 26),
            Text('NOTHING ON THE PANEL', style: eyebrow(size: 10.5)),
            const SizedBox(height: 12),
            const Text(
              'Add the first thing you want to stay on top of — '
              'it becomes a gauge.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: kTextDim, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════

class _HeroCard extends StatelessWidget {
  final Tracked tracked;
  final String assetName;

  const _HeroCard({required this.tracked, required this.assetName});

  Item get item => tracked.item;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final GaugeState state = tracked.state(now);
    final ItemSummary s = summarise(tracked, now);
    final double pct = tracked.progress(now) * 100;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openItem(context, item),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: panelBox(ready: state != GaugeState.healthy),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (assetName.isNotEmpty)
                  Text(assetName.toUpperCase(), style: eyebrow()),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Gauge(
                      progress: tracked.progress(now),
                      state: state,
                      size: 106,
                      centreLabel: pct.isFinite ? pct.round().toString() : '0',
                      centreCaption: s.caption,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(s.headline,
                              style: mono(size: 13.5, color: kText)),
                          const SizedBox(height: 4),
                          Text(s.sub,
                              style: mono(size: 11, color: kTextFaint)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Tracked tracked;
  final String assetName;
  final Duration delay;

  const _ItemRow({
    required this.tracked,
    required this.assetName,
    required this.delay,
  });

  Item get item => tracked.item;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final GaugeState state = tracked.state(now);
    final ItemSummary s = summarise(tracked, now);
    final double pct = tracked.progress(now) * 100;

    return InkWell(
      onTap: () => openItem(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: <Widget>[
            Gauge(
              progress: tracked.progress(now),
              state: state,
              size: 34,
              stroke: 4,
              delay: delay,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(item.name,
                      style: const TextStyle(fontSize: 13.5, color: kText)),
                  const SizedBox(height: 2),
                  Text(
                    assetName.isEmpty
                        ? s.headline
                        : '${assetName.toUpperCase()} · ${s.headline}',
                    style: mono(size: 10.5, color: kTextFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('${pct.round()}%',
                style: mono(size: 12, color: gaugeColor(state))),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SETTINGS SHEET
// ═══════════════════════════════════════════════════════════════════════

Future<void> showSettingsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (BuildContext ctx) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    currentVersion().then((String v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: kPanelEdge, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 16 + MediaQuery.of(context).viewPadding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                  color: kPanelEdge, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text('APP UPDATES', style: eyebrow()),
              Text(_version.isEmpty ? '' : 'v$_version',
                  style: mono(size: 11, color: kTextFaint)),
            ],
          ),
          const SizedBox(height: 14),
          _row(
            icon: Icons.refresh_rounded,
            label: 'Check for updates',
            onTap: () {
              Navigator.pop(context);
              manualCheck(context);
            },
          ),
          const Divider(height: 1, color: kHairline),
          _row(
            // Always available, and independent of everything the in-app
            // installer does. If updating ever misbehaves again, this is
            // the way through.
            icon: Icons.download_rounded,
            label: 'Download latest in browser',
            onTap: () {
              Navigator.pop(context);
              openLatestApkInBrowser();
            },
          ),
          const Divider(height: 1, color: kHairline),
          _row(
            icon: Icons.open_in_new_rounded,
            label: 'Release history on GitHub',
            onTap: () {
              Navigator.pop(context);
              openReleases();
            },
          ),
          const SizedBox(height: 22),
          Text('YOUR DATA', style: eyebrow()),
          const SizedBox(height: 6),
          _row(
            icon: Icons.local_gas_station_rounded,
            label: 'FuelWise',
            onTap: () {
              Navigator.pop(context);
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => const FuelWiseScreen()),
              );
            },
          ),
          const Divider(height: 1, color: kHairline),
          _row(
            icon: Icons.save_alt_rounded,
            label: 'Backup & restore',
            onTap: () {
              Navigator.pop(context);
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
              );
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Updates install over the top — nothing you enter is ever '
            'wiped by one. Never uninstall to update.',
            style: TextStyle(fontSize: 11.5, color: kTextFaint, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: kTextDim),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 14, color: kText)),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: kTextFaint),
          ],
        ),
      ),
    );
  }
}
