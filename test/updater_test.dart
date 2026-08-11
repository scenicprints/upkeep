import 'package:flutter_test/flutter_test.dart';
import 'package:upkeep/updater.dart';

// The updater is the one thing that MUST be right in v0.1.0 — a version
// comparison that's wrong in either direction either strands the phone on
// an old build or nags forever. These are the cases that actually occur.
void main() {
  group('compareVersions', () {
    test('detects a newer release', () {
      expect(compareVersions('0.2.0', '0.1.0'), greaterThan(0));
      expect(compareVersions('0.1.1', '0.1.0'), greaterThan(0));
      expect(compareVersions('1.0.0', '0.9.9'), greaterThan(0));
    });

    test('detects an older release', () {
      expect(compareVersions('0.1.0', '0.2.0'), lessThan(0));
      expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
    });

    test('equal versions do not trigger an update', () {
      expect(compareVersions('0.1.0', '0.1.0'), 0);
    });

    test('tolerates a v prefix on the tag', () {
      expect(compareVersions('v0.2.0', '0.1.0'), greaterThan(0));
      expect(compareVersions('v0.1.0', '0.1.0'), 0);
    });

    test('ignores the +build suffix', () {
      // pubspec carries "0.1.0+1"; the tag carries "v0.1.0". Same release.
      expect(compareVersions('v0.1.0', '0.1.0+1'), 0);
      expect(compareVersions('v0.2.0', '0.1.0+7'), greaterThan(0));
    });

    test('handles double-digit components (10 > 9, not "10" < "9")', () {
      expect(compareVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(compareVersions('0.1.10', '0.1.9'), greaterThan(0));
      expect(compareVersions('2.0.0', '10.0.0'), lessThan(0));
    });

    test('pads missing components', () {
      expect(compareVersions('1', '1.0.0'), 0);
      expect(compareVersions('1.1', '1.0.9'), greaterThan(0));
    });

    test('garbage components degrade to 0 rather than throwing', () {
      expect(() => compareVersions('abc', '0.1.0'), returnsNormally);
      expect(compareVersions('abc', '0.1.0'), lessThan(0));
    });
  });

  test('the release repo is Upkeep, not a copy-pasted sibling app', () {
    // Every app here starts from the last one's updater; pointing at the
    // wrong repo would silently ship someone else's APK.
    expect(kRepo, 'scenicprints/upkeep');
  });
}
