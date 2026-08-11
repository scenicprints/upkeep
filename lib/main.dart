import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mascot.dart';
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

class UpkeepApp extends StatelessWidget {
  const UpkeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Upkeep',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const ClusterScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// THE CLUSTER — home screen
//
// v0.1.0 ships it empty on purpose. Nothing is seeded, no sample items:
// everything in here will be typed in by hand and must survive every
// future update. This build's job is to prove the OTA path end to end
// before there is any data worth losing.
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
    // newer release. Delayed so it never fights the first frame, and held
    // so it can be cancelled if the screen goes away first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _launchCheck = Timer(const Duration(milliseconds: 900), () {
        if (mounted) autoCheck(context);
      });
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

  void _soon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what lands in the next update.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No SafeArea around the whole column: the nav bar's background has to
      // run underneath the system bar while its LABELS stay above it, so each
      // end insets itself. See _nav().
      body: Column(
        children: <Widget>[
          SafeArea(bottom: false, child: _header()),
          const Expanded(child: _EmptyCluster()),
          _nav(),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
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
            item('HISTORY', onTap: () => _soon('History')),
            item('ADD', onTap: () => _soon('Adding items')),
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
            icon: Icons.open_in_new_rounded,
            label: 'Release history on GitHub',
            onTap: () {
              Navigator.pop(context);
              openReleases();
            },
          ),
          const SizedBox(height: 18),
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
