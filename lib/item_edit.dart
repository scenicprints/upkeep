import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import 'app_state.dart';
import 'models.dart';
import 'summary.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// ADD / EDIT
//
// Everything in Upkeep is typed in here by hand — nothing is imported,
// guessed or pre-filled from a catalogue.
// ═══════════════════════════════════════════════════════════════════════

class ItemEditScreen extends StatefulWidget {
  final Item? existing;

  const ItemEditScreen({super.key, this.existing});

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _interval = TextEditingController(
    text: widget.existing == null
        ? ''
        : (widget.existing!.kind == ItemKind.usage
            ? (widget.existing!.intervalUnits?.round().toString() ?? '')
            : (widget.existing!.intervalDays?.toString() ?? '')),
  );
  /// The optional second limit on a usage item: "or every 6 months".
  late final TextEditingController _months = TextEditingController(
      text: widget.existing?.intervalMonths?.toString() ?? '');
  late final TextEditingController _template = TextEditingController(
      text: widget.existing?.messageTemplate ?? '');

  late ItemKind _kind = widget.existing?.kind ?? ItemKind.time;
  late String _unit = widget.existing?.unit ?? 'mi';
  late String? _assetId = widget.existing?.assetId;

  late final List<LinkRef> _links = <LinkRef>[
    for (final LinkRef l in widget.existing?.links ?? const <LinkRef>[])
      LinkRef(label: l.label, url: l.url),
  ];
  late final List<PartRef> _parts = <PartRef>[
    for (final PartRef p in widget.existing?.parts ?? const <PartRef>[])
      PartRef(number: p.number, label: p.label),
  ];

  late String? _contactName = widget.existing?.contactName;
  late String? _contactPhone = widget.existing?.contactPhone;

  /// Only asked for on a NEW item, so the gauge has a starting point.
  final TextEditingController _startReading = TextEditingController();
  bool _startNow = true;

  @override
  void dispose() {
    _name.dispose();
    _interval.dispose();
    _months.dispose();
    _template.dispose();
    _startReading.dispose();
    super.dispose();
  }

  bool get _isNew => widget.existing == null;

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            _bar(context, c),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, 28 + MediaQuery.of(context).viewPadding.bottom),
                children: <Widget>[
                  _label('WHAT IS IT'),
                  _field(_name, hint: 'Oil change'),

                  const SizedBox(height: 22),
                  _label('WHAT IT BELONGS TO'),
                  _assetPicker(c),

                  const SizedBox(height: 22),
                  _label('HOW IT COMES DUE'),
                  _kindPicker(),
                  const SizedBox(height: 10),
                  _kindHelp(),

                  const SizedBox(height: 18),
                  _label(_kind == ItemKind.usage
                      ? 'EVERY HOW MANY'
                      : _kind == ItemKind.inspect
                          ? 'LOOK EVERY (DAYS)'
                          : 'EVERY HOW MANY DAYS'),
                  Row(children: <Widget>[
                    Expanded(
                      child: _field(_interval,
                          hint: _kind == ItemKind.usage ? '5000' : '90',
                          number: true),
                    ),
                    if (_kind == ItemKind.usage) ...<Widget>[
                      const SizedBox(width: 10),
                      _unitPicker(),
                    ],
                  ]),

                  if (_kind == ItemKind.usage) ...<Widget>[
                    const SizedBox(height: 18),
                    _label('OR EVERY (MONTHS) — OPTIONAL'),
                    _field(_months, hint: '6', number: true),
                    const SizedBox(height: 6),
                    const Text(
                      'Whichever comes first. Leave blank to go by '
                      'mileage alone.',
                      style: TextStyle(
                          fontSize: 10.5, color: kTextFaint, height: 1.45),
                    ),
                  ],

                  if (_isNew) ...<Widget>[
                    const SizedBox(height: 22),
                    _label('WHERE IT STANDS NOW'),
                    _startBlock(),
                  ],

                  const SizedBox(height: 22),
                  _label('LINKS'),
                  ..._linkEditors(),
                  _addButton('Add a link', () {
                    setState(() => _links.add(LinkRef(label: '', url: '')));
                  }),

                  const SizedBox(height: 22),
                  _label('PART NUMBERS'),
                  ..._partEditors(),
                  _addButton('Add a part number', () {
                    setState(() => _parts.add(PartRef(number: '')));
                  }),

                  const SizedBox(height: 22),
                  _label('WHO TO TEXT'),
                  _contactRow(),
                  const SizedBox(height: 10),
                  _field(_template,
                      hint: _templateHint(), lines: 3),
                  const SizedBox(height: 6),
                  const Text(
                    'Leave blank for a sensible default. '
                    '{item} {asset} {target} {due} get filled in.',
                    style: TextStyle(
                        fontSize: 10.5, color: kTextFaint, height: 1.45),
                  ),

                  if (!_isNew) ...<Widget>[
                    const SizedBox(height: 30),
                    _deleteButton(context, c),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _templateHint() =>
      renderMessage(Tracked(_previewItem(), null), _assetNameFor(_assetId));

  Item _previewItem() => Item(
        id: 'preview',
        name: _name.text.trim().isEmpty ? 'this' : _name.text.trim(),
        assetId: _assetId ?? '',
        kind: _kind,
        unit: _unit,
      );

  String _assetNameFor(String? id) {
    if (id == null) return '';
    final UpkeepController c = UpkeepScope.of(context);
    for (final Asset a in c.data.assets) {
      if (a.id == id) return a.name;
    }
    return '';
  }

  // ── chrome ───────────────────────────────────────────────────────

  Widget _bar(BuildContext context, UpkeepController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, size: 22, color: kTextDim),
          ),
          Text(_isNew ? 'New item' : 'Edit',
              style: const TextStyle(fontSize: 15, color: kText)),
          const Spacer(),
          TextButton(
            onPressed: () => _save(context, c),
            style: TextButton.styleFrom(foregroundColor: kReady),
            child: const Text('Save',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: eyebrow()),
      );

  Widget _field(
    TextEditingController ctrl, {
    String? hint,
    bool number = false,
    int lines = 1,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: lines,
      keyboardType:
          number ? const TextInputType.numberWithOptions() : TextInputType.text,
      style: number
          ? mono(size: 15, color: kText)
          : const TextStyle(fontSize: 15, color: kText),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: kTextFaint),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        filled: true,
        fillColor: kPanel,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kPanelEdge, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kReadyEdge),
        ),
      ),
    );
  }

  Widget _pill(String text, bool active, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF221B0C) : kPanel,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: active ? kReadyEdge : kPanelEdge, width: 0.5),
          ),
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5, color: active ? kReady : kTextDim)),
        ),
      ),
    );
  }

  Widget _kindPicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final ItemKind k in ItemKind.values)
          _pill(kindLabel(k), _kind == k, () => setState(() => _kind = k)),
      ],
    );
  }

  Widget _kindHelp() {
    final String text = switch (_kind) {
      ItemKind.time => 'Upkeep knows exactly when this is due.',
      ItemKind.usage =>
        'Upkeep holds the exact target number and guesses the date from '
            'your readings. At 90% it asks you for a real one.',
      ItemKind.inspect =>
        "Upkeep can't know this one. It just asks you to look, on a "
            'cadence, and never claims it\'s due.',
    };
    return Text(text,
        style: const TextStyle(
            fontSize: 11.5, color: kTextFaint, height: 1.5));
  }

  Widget _unitPicker() {
    return Row(children: <Widget>[
      for (final String u in <String>['mi', 'hr'])
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: _pill(u, _unit == u, () => setState(() => _unit = u)),
        ),
    ]);
  }

  Widget _assetPicker(UpkeepController c) {
    final List<Asset> assets = c.data.liveAssets;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final Asset a in assets)
          _pill(a.name, _assetId == a.id, () => setState(() => _assetId = a.id)),
        _pill('+ New', false, () => _newAsset(c)),
      ],
    );
  }

  Future<void> _newAsset(UpkeepController c) async {
    final String? name = await _promptText(context,
        title: 'What does it belong to?', hint: "Jenny's RAV4");
    if (name == null || name.trim().isEmpty) return;
    final Asset a = await c.addAsset(name);
    if (mounted) setState(() => _assetId = a.id);
  }

  Widget _startBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(children: <Widget>[
          _pill('Just did it', _startNow, () => setState(() => _startNow = true)),
          const SizedBox(width: 8),
          _pill('Not yet — start later', !_startNow,
              () => setState(() => _startNow = false)),
        ]),
        if (_startNow && _kind == ItemKind.usage) ...<Widget>[
          const SizedBox(height: 10),
          _field(_startReading,
              hint: 'Odometer now, e.g. 38410', number: true),
        ],
        const SizedBox(height: 8),
        Text(
          _startNow
              ? 'Logs it as done today, which starts the gauge.'
              : "Nothing is logged. The gauge stays empty until you tap "
                  "\"I did this\".",
          style: const TextStyle(
              fontSize: 10.5, color: kTextFaint, height: 1.45),
        ),
      ],
    );
  }

  List<Widget> _linkEditors() {
    return <Widget>[
      for (int i = 0; i < _links.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: <Widget>[
            Expanded(
              flex: 2,
              child: _inline(
                _links[i].label,
                'Label — Book at dealer',
                (String v) => _links[i].label = v,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _inline(
                _links[i].url,
                'https://…',
                (String v) => _links[i].url = v,
              ),
            ),
            _removeButton(() => setState(() => _links.removeAt(i))),
          ]),
        ),
    ];
  }

  List<Widget> _partEditors() {
    return <Widget>[
      for (int i = 0; i < _parts.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: <Widget>[
            Expanded(
              flex: 3,
              child: _inline(
                _parts[i].number,
                '90915-YZZJ1',
                (String v) => _parts[i].number = v,
                monospace: true,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _inline(
                _parts[i].label,
                'oil filter',
                (String v) => _parts[i].label = v,
              ),
            ),
            _removeButton(() => setState(() => _parts.removeAt(i))),
          ]),
        ),
    ];
  }

  Widget _inline(String initial, String hint, ValueChanged<String> onChanged,
      {bool monospace = false}) {
    return TextFormField(
      initialValue: initial,
      onChanged: onChanged,
      style: monospace
          ? mono(size: 13, color: kText)
          : const TextStyle(fontSize: 13, color: kText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: kTextFaint),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: kPanel,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPanelEdge, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kReadyEdge),
        ),
      ),
    );
  }

  Widget _removeButton(VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: const Icon(Icons.remove_circle_outline_rounded,
            size: 18, color: kTextFaint),
      );

  Widget _addButton(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
        style: TextButton.styleFrom(foregroundColor: kTextDim),
      ),
    );
  }

  Widget _contactRow() {
    final bool has = (_contactPhone ?? '').isNotEmpty;
    return Row(children: <Widget>[
      Expanded(
        child: Text(
          has ? '${_contactName ?? ''} · ${_contactPhone!}' : 'Nobody yet',
          style: TextStyle(
              fontSize: 13, color: has ? kText : kTextFaint),
        ),
      ),
      TextButton(
        onPressed: _pickContact,
        style: TextButton.styleFrom(foregroundColor: kReady),
        child: Text(has ? 'Change' : 'Choose',
            style: const TextStyle(fontSize: 13)),
      ),
      if (has)
        IconButton(
          onPressed: () => setState(() {
            _contactName = null;
            _contactPhone = null;
          }),
          icon: const Icon(Icons.close_rounded, size: 16, color: kTextFaint),
        ),
    ]);
  }

  Future<void> _pickContact() async {
    final bool granted = await FlutterContacts.requestPermission(
        readonly: true);
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Contacts permission is needed to pick someone to text.')));
      }
      return;
    }
    final Contact? picked = await FlutterContacts.openExternalPick();
    if (picked == null) return;
    // openExternalPick returns a thin contact; fetch the phones.
    final Contact? full =
        await FlutterContacts.getContact(picked.id, withProperties: true);
    final Contact contact = full ?? picked;
    if (contact.phones.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('That contact has no phone number.')));
      }
      return;
    }
    setState(() {
      _contactName = contact.displayName;
      _contactPhone = contact.phones.first.number;
    });
  }

  Widget _deleteButton(BuildContext context, UpkeepController c) {
    return TextButton(
      onPressed: () async {
        final bool ok = await _confirm(context,
            'Delete "${widget.existing!.name}"?',
            'Its history goes too. This cannot be undone.');
        if (!ok) return;
        await c.deleteItem(widget.existing!);
        if (context.mounted) {
          // Pop the edit screen AND the detail screen behind it.
          Navigator.of(context)
            ..pop()
            ..pop();
        }
      },
      style: TextButton.styleFrom(foregroundColor: kOverdue),
      child: const Text('Delete this item', style: TextStyle(fontSize: 13)),
    );
  }

  // ── save ─────────────────────────────────────────────────────────

  Future<void> _save(BuildContext context, UpkeepController c) async {
    final String name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give it a name first.')));
      return;
    }
    if (_assetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick what it belongs to, or add a new one.')));
      return;
    }
    final double? interval =
        double.tryParse(_interval.text.replaceAll(',', '').trim());
    if (interval == null || interval <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Set how often it comes due.')));
      return;
    }

    final Item item = widget.existing ??
        Item(id: newId(), name: name, assetId: _assetId!, kind: _kind);

    item.name = name;
    item.assetId = _assetId!;
    item.kind = _kind;
    item.unit = _unit;
    if (_kind == ItemKind.usage) {
      item.intervalUnits = interval;
      item.intervalDays = null;
      // Optional second limit — blank or nonsense means mileage only.
      final int? months = int.tryParse(_months.text.trim());
      item.intervalMonths = (months != null && months > 0) ? months : null;
    } else {
      item.intervalDays = interval.round();
      item.intervalUnits = null;
      item.intervalMonths = null;
    }
    item.links = _links
        .where((LinkRef l) => l.url.trim().isNotEmpty)
        .toList();
    item.parts = _parts
        .where((PartRef p) => p.number.trim().isNotEmpty)
        .toList();
    item.contactName = _contactName;
    item.contactPhone = _contactPhone;
    item.messageTemplate =
        _template.text.trim().isEmpty ? null : _template.text.trim();

    await c.upsertItem(item);

    // A brand-new item with "just did it" gets its first log, which is what
    // starts the gauge. Existing items are never re-logged by an edit.
    if (_isNew && _startNow) {
      final double? reading = _kind == ItemKind.usage
          ? double.tryParse(_startReading.text.replaceAll(',', '').trim())
          : null;
      await c.logService(item, reading: reading);
    }

    if (context.mounted) Navigator.pop(context);
  }
}

// ═══════════════════════════════════════════════════════════════════════

Future<String?> _promptText(BuildContext context,
    {required String title, String? hint}) async {
  final TextEditingController ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kPanel,
      title: Text(title, style: const TextStyle(fontSize: 16, color: kText)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: const TextStyle(fontSize: 16, color: kText),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: kTextFaint),
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
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          style: TextButton.styleFrom(foregroundColor: kReady),
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(
    BuildContext context, String title, String body) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kPanel,
      title: Text(title, style: const TextStyle(fontSize: 16, color: kText)),
      content: Text(body,
          style: const TextStyle(fontSize: 13, color: kTextDim, height: 1.5)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: kTextDim),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: kOverdue),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
