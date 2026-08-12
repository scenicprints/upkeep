import 'package:flutter/material.dart';

import 'app_state.dart';
import 'fuelwise.dart';
import 'models.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// FUELWISE
//
// Connect once, link each car to its FuelWise vehicle, and the odometer
// stops being something Upkeep has to ask about.
// ═══════════════════════════════════════════════════════════════════════

class FuelWiseScreen extends StatefulWidget {
  /// Test seam: lets a render skip the secure-storage and network round
  /// trip so the connected state can actually be looked at. Null in the app.
  final FuelWiseSnapshot? debugSnapshot;
  final bool? debugConnected;

  const FuelWiseScreen({
    super.key,
    this.debugSnapshot,
    this.debugConnected,
  });

  @override
  State<FuelWiseScreen> createState() => _FuelWiseScreenState();
}

class _FuelWiseScreenState extends State<FuelWiseScreen> {
  bool _connected = false;
  bool _busy = false;
  FuelWiseSnapshot? _snap;
  bool _onDevice = false;
  FuelWiseError _error = FuelWiseError.none;
  String? _note;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    if (widget.debugSnapshot != null || widget.debugConnected != null) {
      setState(() {
        _connected = widget.debugConnected ?? true;
        _snap = widget.debugSnapshot;
      });
      return;
    }
    final bool c = await FuelWise.connected;
    if (!mounted) return;
    setState(() => _connected = c);

    // Try the phone first — it's the route that needs nothing set up.
    await _readDevice(quiet: true);
    if (_snap == null && c) await _refresh();
  }

  /// Reads FuelWise directly off the device. [quiet] is for the automatic
  /// attempt on open, where an unavailable neighbour isn't worth an error.
  Future<void> _readDevice({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _busy = true;
        _note = null;
      });
    }
    final FuelWiseResult res = await FuelWise.fromDevice();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _snap = res.snapshot;
        _error = FuelWiseError.none;
        _onDevice = true;
      } else if (!quiet) {
        _error = res.error;
      }
    });
    // Nothing to link yet is not a failure worth shouting about.
    if (res.ok && !quiet) await _pull(UpkeepScope.of(context));
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final FuelWiseResult res = await FuelWise.fetch();
    if (!mounted) return;
    setState(() {
      _snap = res.snapshot;
      _error = res.error;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);

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
                  const Text('FuelWise',
                      style: TextStyle(fontSize: 15, color: kText)),
                  const Spacer(),
                  if (_busy)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kReady),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, 28 + MediaQuery.of(context).viewPadding.bottom),
                children: <Widget>[
                  const Text(
                    'FuelWise records an odometer on every fill-up. Link a '
                    'car and Upkeep will use those instead of asking you.',
                    style:
                        TextStyle(fontSize: 13, color: kTextDim, height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  _onPhone(),
                  // The fallbacks only exist for when the direct route
                  // can't work. Once it does, showing three ways to do the
                  // same thing is just noise.
                  if (!_onDevice) ...<Widget>[
                    const SizedBox(height: 22),
                    _paste(),
                    const SizedBox(height: 22),
                    _connection(),
                  ],
                  if (_error != FuelWiseError.none) ...<Widget>[
                    const SizedBox(height: 18),
                    _problem(),
                  ],
                  if (_snap != null) ...<Widget>[
                    const SizedBox(height: 26),
                    Text('YOUR CARS', style: eyebrow()),
                    const SizedBox(height: 6),
                    ..._links(c),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: _busy ? null : () => _pull(c),
                        style: FilledButton.styleFrom(
                          backgroundColor: kReady,
                          foregroundColor: const Color(0xFF171004),
                          disabledBackgroundColor: kTrack,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Pull fill-ups now',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                  if (_note != null) ...<Widget>[
                    const SizedBox(height: 18),
                    Text(_note!,
                        style: const TextStyle(
                            fontSize: 12.5, color: kHealthy, height: 1.5)),
                  ],
                  const SizedBox(height: 26),
                  const Text(
                    'Upkeep only reads. It never writes to FuelWise, and '
                    'the token is kept on this phone — never in the app '
                    'build, which anyone could unpack.',
                    style: TextStyle(
                        fontSize: 11, color: kTextFaint, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The route that needs nothing at all: FuelWise is on this phone, so
  /// just ask it.
  Widget _onPhone() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: panelBox(ready: !_onDevice),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_onDevice ? 'ON THIS PHONE — WORKING' : 'ON THIS PHONE',
              style: eyebrow(color: _onDevice ? kTextFaint : kReadyDim)),
          const SizedBox(height: 8),
          Text(
            _onDevice
                ? 'Upkeep reads the odometer straight from FuelWise. '
                    'Nothing to set up, and it stays current by itself.'
                : 'If FuelWise is installed and up to date, Upkeep can read '
                    'the odometer straight from it — no token, no copying.',
            style:
                const TextStyle(fontSize: 12.5, color: kTextDim, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : () => _readDevice(),
              style: FilledButton.styleFrom(
                backgroundColor: kReady,
                foregroundColor: const Color(0xFF171004),
                disabledBackgroundColor: kTrack,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              child: Text(_onDevice ? 'Read it again' : 'Read from FuelWise',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// Fallback for when the two apps aren't on the same phone.
  Widget _paste() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: panelBox(ready: _snap == null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('OR PASTE IT', style: eyebrow()),
          const SizedBox(height: 8),
          const Text(
            'In FuelWise: Settings → Copy log for Upkeep. Then come back '
            'and tap this.',
            style: TextStyle(fontSize: 12.5, color: kTextDim, height: 1.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _pasteFromClipboard,
              style: FilledButton.styleFrom(
                backgroundColor: kReady,
                foregroundColor: const Color(0xFF171004),
                disabledBackgroundColor: kTrack,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              child: const Text('Paste FuelWise log',
                  style:
                      TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final FuelWiseResult res = await FuelWise.fromClipboard();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (res.ok) {
        _snap = res.snapshot;
        _error = FuelWiseError.none;
        _note = 'Read ${res.snapshot!.vehicles.length} vehicle'
            '${res.snapshot!.vehicles.length == 1 ? '' : 's'} and '
            '${res.snapshot!.fills.length} fill-ups. Link a car below.';
      } else {
        _error = res.error;
      }
    });
  }

  Widget _connection() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: panelBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_connected ? 'AUTOMATIC — CONNECTED' : 'AUTOMATIC — OPTIONAL',
              style: eyebrow()),
          const SizedBox(height: 8),
          Text(
            _connected
                ? 'A read token is stored on this phone, so linked cars top '
                    'themselves up on every launch.'
                : 'Optional. With a GitHub token that can read '
                    'fuelwise-data, Upkeep pulls fill-ups by itself and you '
                    'never have to copy anything. Needs FuelWise sync '
                    'switched on first.',
            style: const TextStyle(fontSize: 12.5, color: kTextDim, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(children: <Widget>[
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: _enterToken,
                style: OutlinedButton.styleFrom(
                  foregroundColor: kReady,
                  side: const BorderSide(color: kReadyEdge),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(_connected ? 'Replace token' : 'Add token',
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            if (_connected) ...<Widget>[
              const SizedBox(width: 8),
              TextButton(
                onPressed: _disconnect,
                style: TextButton.styleFrom(foregroundColor: kTextFaint),
                child:
                    const Text('Disconnect', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _problem() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: panelBox(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.info_outline_rounded, size: 16, color: kOverdue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(fuelWiseErrorText(_error),
                style: const TextStyle(
                    fontSize: 12.5, color: kTextDim, height: 1.5)),
          ),
        ],
      ),
    );
  }

  List<Widget> _links(UpkeepController c) {
    // Only offer cars that actually track mileage. Offering to link a truck
    // to "The House" is nonsense, and a meter on something with no mileage
    // item would never be read.
    final List<Asset> assets = c.meteredAssets;
    final List<FuelWiseVehicle> vehicles = _snap!.vehicles;

    if (vehicles.isEmpty) {
      return <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('FuelWise has no vehicles in it yet.',
              style: TextStyle(fontSize: 12.5, color: kTextFaint)),
        ),
      ];
    }
    if (assets.isEmpty) {
      return <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Nothing in Upkeep tracks mileage yet. Add a mileage item to a '
            'car and it will show up here to link.',
            style: TextStyle(fontSize: 12.5, color: kTextFaint, height: 1.5),
          ),
        ),
      ];
    }

    return <Widget>[
      for (final FuelWiseVehicle v in vehicles)
        _vehicleRow(c, v, assets),
    ];
  }

  Widget _vehicleRow(
      UpkeepController c, FuelWiseVehicle v, List<Asset> assets) {
    // Look across ALL assets for the link, not just the linkable ones — an
    // asset whose last mileage item was deleted must still show as linked
    // rather than silently appearing free.
    final Asset? linked = c.data.liveAssets
        .cast<Asset?>()
        .firstWhere((Asset? a) => a!.fuelwiseVehicleId == v.id,
            orElse: () => null);
    final int fills = _snap!.forVehicle(v.id).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: panelBox(radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(
              child: Text(v.label,
                  style: const TextStyle(fontSize: 13.5, color: kText)),
            ),
            Text('$fills fill-up${fills == 1 ? '' : 's'}',
                style: mono(size: 10.5, color: kTextFaint)),
          ]),
          const SizedBox(height: 10),
          if (linked == null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final Asset a in assets)
                  if (a.fuelwiseVehicleId == null)
                    _pill('Link to ${a.name}', () => c.linkAsset(a, v.id)),
              ],
            )
          else
            Row(children: <Widget>[
              const Icon(Icons.link_rounded, size: 14, color: kHealthy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(linked.name,
                    style: const TextStyle(fontSize: 12.5, color: kHealthy)),
              ),
              TextButton(
                onPressed: () => _unlink(c, linked),
                style: TextButton.styleFrom(foregroundColor: kTextFaint),
                child: const Text('Unlink',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ]),
        ],
      ),
    );
  }

  Widget _pill(String label, VoidCallback onTap) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kPanelEdge, width: 0.5),
            ),
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: kTextDim)),
          ),
        ),
      );

  Future<void> _pull(UpkeepController c) async {
    if (_snap == null) return;
    setState(() => _busy = true);
    final ImportResult r = await c.importFromFuelWise(_snap!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _note = r.added == 0
          ? 'Nothing new — already up to date.'
          : 'Added ${r.added} reading${r.added == 1 ? '' : 's'}'
              '${r.skipped > 0 ? ', ${r.skipped} already known' : ''}.';
    });
  }

  Future<void> _unlink(UpkeepController c, Asset a) async {
    final int removed = await c.unlinkAsset(a);
    if (!mounted) return;
    setState(() => _note = removed == 0
        ? 'Unlinked.'
        : 'Unlinked and removed $removed imported reading'
            '${removed == 1 ? '' : 's'}. Anything you typed is untouched.');
  }

  Future<void> _enterToken() async {
    final String? t = await _tokenDialog(context);
    if (t == null || t.trim().isEmpty) return;
    await FuelWise.setToken(t);
    if (!mounted) return;
    setState(() => _connected = true);
    await _refresh();
  }

  Future<void> _disconnect() async {
    await FuelWise.clearToken();
    if (!mounted) return;
    setState(() {
      _connected = false;
      _snap = null;
      _error = FuelWiseError.none;
      _note = 'Token removed. Imported readings are still here.';
    });
  }
}

Future<String?> _tokenDialog(BuildContext context) async {
  final TextEditingController ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kPanel,
      title: const Text('GitHub token',
          style: TextStyle(fontSize: 16, color: kText)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'A fine-grained token with Contents: Read on '
            'scenicprints/fuelwise-data.',
            style: TextStyle(fontSize: 12, color: kTextDim, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            obscureText: true,
            style: mono(size: 13, color: kText),
            decoration: const InputDecoration(
              hintText: 'github_pat_…',
              hintStyle: TextStyle(color: kTextFaint, fontSize: 12),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: kPanelEdge)),
              focusedBorder:
                  UnderlineInputBorder(borderSide: BorderSide(color: kReady)),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          style: TextButton.styleFrom(foregroundColor: kTextFaint),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          style: TextButton.styleFrom(foregroundColor: kReady),
          child: const Text('Connect'),
        ),
      ],
    ),
  );
}
