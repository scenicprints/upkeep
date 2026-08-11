import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

// ═══════════════════════════════════════════════════════════════════════
// IN-APP OTA UPDATER
//
// Checks this repo's latest GitHub Release, compares its tag to the
// installed version, and if it's newer downloads the APK and hands it to
// Android's package installer.
//
// Deliberately does NOT use the ota_update package: that plugin needs a
// hand-declared FileProvider in the manifest or the app hard-crashes the
// instant a download completes. Plain http + open_filex has no such trap.
//
// The repo is PUBLIC, so the releases API needs no token (60 unauthenticated
// requests/hour per IP — plenty for one phone).
// ═══════════════════════════════════════════════════════════════════════

const String kRepo = 'scenicprints/upkeep';

class UpdateInfo {
  final String version; // tag minus any leading "v"
  final String tag;
  final String? apkUrl; // direct download URL of the .apk asset
  final String releaseUrl; // fallback: the release page in a browser
  final String? notes; // release body — the "What's New" text

  UpdateInfo({
    required this.version,
    required this.tag,
    required this.apkUrl,
    required this.releaseUrl,
    this.notes,
  });
}

String _stripV(String s) {
  s = s.trim();
  return s.startsWith('v') ? s.substring(1) : s;
}

/// Compares two semantic versions. Returns >0 if [a] is newer than [b].
/// Tolerates "v" prefixes, "+build" suffixes and missing components.
int compareVersions(String a, String b) {
  List<int> parse(String s) {
    s = _stripV(s).split('+').first.split('-').first;
    final List<int> parts =
        s.split('.').map((String e) => int.tryParse(e.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  final List<int> pa = parse(a), pb = parse(b);
  for (int i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i].compareTo(pb[i]);
  }
  return 0;
}

Future<String> currentVersion() async =>
    (await PackageInfo.fromPlatform()).version;

Future<UpdateInfo?> fetchLatestRelease() async {
  final http.Response res = await http.get(
    Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'),
    headers: <String, String>{'Accept': 'application/vnd.github+json'},
  ).timeout(const Duration(seconds: 12));
  if (res.statusCode != 200) return null;
  final Map<String, dynamic> data =
      json.decode(res.body) as Map<String, dynamic>;
  final String tag = (data['tag_name'] as String?) ?? '';
  if (tag.isEmpty) return null;

  String? apkUrl;
  for (final dynamic a in (data['assets'] as List<dynamic>? ?? const [])) {
    final String name = (a['name'] as String?) ?? '';
    if (name.toLowerCase().endsWith('.apk')) {
      apkUrl = a['browser_download_url'] as String?;
      break;
    }
  }
  return UpdateInfo(
    version: _stripV(tag),
    tag: tag,
    apkUrl: apkUrl,
    releaseUrl:
        (data['html_url'] as String?) ?? 'https://github.com/$kRepo/releases',
    notes: data['body'] as String?,
  );
}

/// Returns the release only if it is strictly newer than what's installed.
Future<UpdateInfo?> checkForUpdate() async {
  try {
    final String current = await currentVersion();
    final UpdateInfo? latest = await fetchLatestRelease();
    if (latest == null) return null;
    return compareVersions(latest.version, current) > 0 ? latest : null;
  } catch (_) {
    return null;
  }
}

/// Silent check on launch — surfaces a sheet only when there's something new.
Future<void> autoCheck(BuildContext context) async {
  final UpdateInfo? info = await checkForUpdate();
  if (info != null && context.mounted) {
    await showUpdateSheet(context, info);
  }
}

/// Explicit check from the settings sheet — always says something.
Future<void> manualCheck(BuildContext context) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
      const SnackBar(content: Text('Checking for updates…')));
  final String current = await currentVersion();
  UpdateInfo? latest;
  try {
    latest = await fetchLatestRelease();
  } catch (_) {}
  if (!context.mounted) return;
  messenger.hideCurrentSnackBar();
  if (latest == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Could not reach GitHub. Check your connection.')));
    return;
  }
  if (compareVersions(latest.version, current) > 0) {
    await showUpdateSheet(context, latest);
  } else {
    messenger.showSnackBar(
        SnackBar(content: Text("You're on the latest version (v$current).")));
  }
}

Future<void> downloadAndInstall(
  UpdateInfo info, {
  void Function(double? progress, String status)? onStatus,
}) async {
  final String url = info.apkUrl ?? info.releaseUrl;
  final http.Client client = http.Client();
  try {
    onStatus?.call(null, 'Connecting…');
    final http.StreamedResponse resp =
        await client.send(http.Request('GET', Uri.parse(url)));
    final int total = resp.contentLength ?? 0;
    final Directory dir =
        await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    // Clear out any previous download so the folder can't grow forever.
    try {
      for (final FileSystemEntity f in dir.listSync()) {
        if (f is File && f.path.toLowerCase().endsWith('.apk')) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
    final File file = File('${dir.path}/upkeep-update.apk');
    final IOSink sink = file.openWrite();
    int received = 0;
    await for (final List<int> chunk in resp.stream) {
      received += chunk.length;
      sink.add(chunk);
      final double? p = total > 0 ? received / total : null;
      onStatus?.call(
          p, 'Downloading… ${p != null ? '${(p * 100).round()}%' : ''}');
    }
    await sink.close();
    onStatus?.call(1.0, 'Opening installer…');
    await OpenFilex.open(file.path,
        type: 'application/vnd.android.package-archive');
  } finally {
    client.close();
  }
}

Future<void> openReleases() async {
  await launchUrl(Uri.parse('https://github.com/$kRepo/releases'),
      mode: LaunchMode.externalApplication);
}

// ═══════════════════════════════════════════════════════════════════════
// UPDATE SHEET
// ═══════════════════════════════════════════════════════════════════════

Future<void> showUpdateSheet(BuildContext context, UpdateInfo info) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _UpdateSheet(info: info),
  );
}

class _UpdateSheet extends StatefulWidget {
  final UpdateInfo info;
  const _UpdateSheet({required this.info});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  bool _busy = false;
  double? _progress;
  String _status = '';
  String? _error;

  Future<void> _install() async {
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Connecting…';
    });
    try {
      await downloadAndInstall(widget.info,
          onStatus: (double? p, String s) {
        if (mounted) {
          setState(() {
            _progress = p;
            _status = s;
          });
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Download failed. Try again, or open the release page.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String notes = (widget.info.notes ?? '').trim();
    return Container(
      decoration: const BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: kReadyEdge, width: 0.5)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
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
          const SizedBox(height: 18),
          Text('UPDATE AVAILABLE', style: eyebrow(color: kReadyDim)),
          const SizedBox(height: 8),
          Text('Upkeep ${widget.info.tag}',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w500, color: kReady)),
          if (notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text("WHAT'S NEW", style: eyebrow()),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(notes,
                    style: const TextStyle(
                        fontSize: 13.5, color: kTextDim, height: 1.6)),
              ),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(_error!,
                style: const TextStyle(fontSize: 12.5, color: kOverdue)),
          ],
          const SizedBox(height: 20),
          if (_busy) ...<Widget>[
            Text(_status, style: mono(size: 12, color: kTextDim)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 5,
                backgroundColor: kTrack,
                valueColor: const AlwaysStoppedAnimation<Color>(kReady),
              ),
            ),
            const SizedBox(height: 10),
            const Text('The installer opens by itself when it lands.',
                style: TextStyle(fontSize: 11.5, color: kTextFaint)),
          ] else
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _install,
                      style: FilledButton.styleFrom(
                        backgroundColor: kReady,
                        foregroundColor: const Color(0xFF171004),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Download & install',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kTextDim,
                      side: const BorderSide(color: kPanelEdge),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Later'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
