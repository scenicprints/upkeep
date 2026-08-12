import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'app_state.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// BACKUP
//
// Everything in Upkeep is typed by hand and exists in exactly one place:
// app storage on one phone. An update preserves it; a dead phone doesn't.
//
// Export hands a JSON file to the share sheet — Drive, Gmail to yourself,
// wherever. Restore takes that file's contents back. It's a paste rather
// than a file picker on purpose: file_picker needs a newer Android
// toolchain than this project builds on, and a rare operation isn't worth
// putting the whole build at risk for.
// ═══════════════════════════════════════════════════════════════════════

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final UpkeepController c = UpkeepScope.of(context);
    final int items = c.data.liveItems.length;
    final int assets = c.data.liveAssets.length;
    final int logs = c.data.liveItems
        .fold(0, (int sum, Item i) => sum + i.log.length);
    final int readings = c.data.liveAssets
        .fold(0, (int sum, Asset a) => sum + a.readings.length);

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
                  const Text('Backup',
                      style: TextStyle(fontSize: 15, color: kText)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, 28 + MediaQuery.of(context).viewPadding.bottom),
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: panelBox(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('ON THIS PHONE', style: eyebrow()),
                        const SizedBox(height: 10),
                        _stat('$items item${items == 1 ? '' : 's'}'),
                        _stat('$assets thing${assets == 1 ? '' : 's'} '
                            'they belong to'),
                        _stat('$logs logged service${logs == 1 ? '' : 's'}'),
                        _stat('$readings reading'
                            '${readings == 1 ? '' : 's'}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'This lives in one place only. An app update keeps it; '
                    'a lost phone does not.',
                    style: TextStyle(
                        fontSize: 12, color: kTextFaint, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _export(c),
                      style: FilledButton.styleFrom(
                        backgroundColor: kReady,
                        foregroundColor: const Color(0xFF171004),
                        disabledBackgroundColor: kTrack,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save a copy',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sends a dated .json file wherever you like — Drive, '
                    'email it to yourself, anywhere off this phone.',
                    style: TextStyle(
                        fontSize: 11, color: kTextFaint, height: 1.45),
                  ),
                  const SizedBox(height: 32),
                  Text('RESTORE', style: eyebrow()),
                  const SizedBox(height: 10),
                  const Text(
                    'Open a backup file, copy everything in it, and paste '
                    'it here. This REPLACES what is on the phone.',
                    style:
                        TextStyle(fontSize: 12, color: kTextDim, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _restore(c),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kTextDim,
                        side: const BorderSide(color: kPanelEdge),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Paste a backup',
                          style: TextStyle(fontSize: 13.5)),
                    ),
                  ),
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 18),
                    Text(_message!,
                        style: const TextStyle(
                            fontSize: 12.5, color: kHealthy, height: 1.5)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(s, style: mono(size: 13, color: kText)),
      );

  Future<void> _export(UpkeepController c) async {
    setState(() => _busy = true);
    try {
      final File f = await Store.writeBackup(c.data, DateTime.now());
      await Share.shareXFiles(
        <XFile>[XFile(f.path, mimeType: 'application/json')],
        subject: 'Upkeep backup',
      );
      if (mounted) setState(() => _message = 'Copy sent.');
    } catch (e) {
      if (mounted) {
        setState(() => _message = "Couldn't save a copy: $e");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(UpkeepController c) async {
    final String? pasted = await _pasteDialog(context);
    if (pasted == null || pasted.trim().isEmpty) return;

    UpkeepData incoming;
    try {
      incoming = UpkeepData.decode(pasted);
    } catch (_) {
      if (mounted) {
        setState(() => _message = "That doesn't look like an Upkeep backup.");
      }
      return;
    }
    if (incoming.items.isEmpty && incoming.assets.isEmpty) {
      if (mounted) {
        setState(() => _message = 'That backup is empty — nothing restored.');
      }
      return;
    }
    if (!mounted) return;

    // Destructive, so show what's being traded for what.
    final bool ok = await _confirmRestore(
      context,
      have: c.data.liveItems.length,
      incoming: incoming.liveItems.length,
    );
    if (!ok) return;

    await c.restore(incoming);
    if (mounted) {
      setState(() => _message =
          'Restored ${incoming.liveItems.length} items.');
    }
  }
}

Future<String?> _pasteDialog(BuildContext context) async {
  final TextEditingController ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kPanel,
      title: const Text('Paste a backup',
          style: TextStyle(fontSize: 16, color: kText)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 8,
        style: mono(size: 11, color: kTextDim),
        decoration: const InputDecoration(
          hintText: '{ "version": 1, … }',
          hintStyle: TextStyle(color: kTextFaint, fontSize: 12),
          enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: kPanelEdge)),
          focusedBorder:
              OutlineInputBorder(borderSide: BorderSide(color: kReady)),
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
          child: const Text('Read it'),
        ),
      ],
    ),
  );
}

Future<bool> _confirmRestore(BuildContext context,
    {required int have, required int incoming}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      backgroundColor: kPanel,
      title: const Text('Replace everything?',
          style: TextStyle(fontSize: 16, color: kText)),
      content: Text(
        'The $have item${have == 1 ? '' : 's'} on this phone will be '
        'replaced by $incoming from the backup. This cannot be undone.',
        style: const TextStyle(fontSize: 13, color: kTextDim, height: 1.5),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: kTextDim),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: kOverdue),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
