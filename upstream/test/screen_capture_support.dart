import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const screenCaptureKey = ValueKey('screen-playtest-capture');
int _captureIndex = 0;

/// Optional evidence for real rendered menu playthroughs, not golden tests.
Future<void> capturePlaytestScreen(WidgetTester tester, String family) async {
  if (Platform.environment['LCS_CAPTURE_SCREENS'] != '1') return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(screenCaptureKey),
  );
  final name = tester.testDescription.replaceAll(
    RegExp(r'[^A-Za-z0-9_-]+'),
    '-',
  );
  final sequence = (++_captureIndex).toString().padLeft(4, '0');
  await tester.runAsync(() async {
    final directory = await Directory(
      '../reports/$family-captures',
    ).create(recursive: true);
    final pixels = await boundary.toImage();
    try {
      final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${directory.path}/$sequence-$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      pixels.dispose();
    }
  });
}
