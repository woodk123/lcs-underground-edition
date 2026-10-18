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
}
