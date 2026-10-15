import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/inject_service_worker.dart' as injector;

void main() {
  late Directory directory;
  const files = [
    'canvaskit/canvaskit.js',
    'canvaskit/canvaskit.wasm',
    'canvaskit/chromium/canvaskit.js',
    'canvaskit/chromium/canvaskit.wasm',
    'canvaskit/skwasm.js',
    'canvaskit/skwasm.wasm',
    'canvaskit/skwasm_heavy.wasm',
    'canvaskit/wimp.wasm',
    'canvaskit/webparagraph/canvaskit.wasm',
    'assets/portrait.webp',
  ];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('lcs-renderer-test-');
    for (final name in files) {
      File('${directory.path}/$name')
        ..createSync(recursive: true)
        ..writeAsStringSync('fixture');
    }
  });
  tearDown(() => directory.deleteSync(recursive: true));

  void bootstrap(List<Map<String, String>> builds, {bool? preferWebParagraph}) {
    File('${directory.path}/flutter_bootstrap.js').writeAsStringSync(
      '_flutter.buildConfig = ${jsonEncode({'builds': builds})};\n'
      '${preferWebParagraph == null ? '' : 'config: {preferWebParagraph: $preferWebParagraph}'}',
    );
  }

  const canvasKit = {'compileTarget': 'dart2js', 'renderer': 'canvaskit'};

  test(
    'CanvasKit build prunes unused engines and preserves browser fallbacks',
    () {
      bootstrap([canvasKit], preferWebParagraph: false);
      expect(injector.pruneUnusedRenderers(directory), greaterThan(0));
      for (final name in files) {
        final retained =
            name.startsWith('assets/') ||
            name == 'canvaskit/canvaskit.js' ||
            name == 'canvaskit/canvaskit.wasm' ||
            name.startsWith('canvaskit/chromium/');
        expect(
          File('${directory.path}/$name').existsSync(),
          retained,
          reason: name,
        );
      }
      expect(injector.pruneUnusedRenderers(directory), 0);
    },
  );

  test('Wasm and unknown builds retain every renderer', () {
    for (final builds in [
      [
        canvasKit,
        {'compileTarget': 'dart2wasm', 'renderer': 'skwasm'},
      ],
      <Map<String, String>>[],
      [
        {'compileTarget': 'future', 'renderer': 'future'},
      ],
    ]) {
      bootstrap(builds, preferWebParagraph: false);
      expect(injector.pruneUnusedRenderers(directory), 0);
      for (final name in files) {
        expect(File('${directory.path}/$name').existsSync(), isTrue);
      }
    }
  });

  test('WebParagraph is retained unless explicitly disabled', () {
    bootstrap([canvasKit]);
    injector.pruneUnusedRenderers(directory);
    expect(
      File(
        '${directory.path}/canvaskit/webparagraph/canvaskit.wasm',
      ).existsSync(),
      isTrue,
    );
  });
}
