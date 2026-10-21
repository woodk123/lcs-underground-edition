import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/utils/game_version.dart';

void main() {
  test('package metadata matches the player-facing Underground version', () {
    final manifest = File('pubspec.yaml').readAsStringSync();
    final packageVersion = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(manifest)?.group(1);
    expect(packageVersion, gameVersion);
    expect(gameVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
  });

  test('latest versioned changelog matches the player-facing version', () {
    final changelog = File('assets/changelog.md').readAsStringSync();
    final latest = RegExp(
      r'^## Underground Edition (\d+\.\d+\.\d+) — \d{4}-\d{2}-\d{2}$',
      multiLine: true,
    ).firstMatch(changelog);
    expect(latest, isNotNull);
    expect(latest!.group(1), gameVersion);
    final unreleased = changelog.indexOf('## Unreleased');
    expect(unreleased, greaterThanOrEqualTo(0));
    expect(unreleased, lessThan(latest.start));
  });
}
