import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

const String manifestPlaceholder = 'const RESOURCES = null; // build: manifest';
const String versionPlaceholder = "const VERSION = 'dev'; // build: version";

const List<String> criticalFiles = [
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'manifest.json',
  'version.json',
  'favicon.png',
  'assets/AssetManifest.bin',
  'assets/FontManifest.json',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
];

bool excludedFromPrecache(String path) {
  if (path.endsWith('.map') || path.endsWith('.symbols')) return true;
  if (path == 'sw.js' || path == 'flutter_service_worker.js') return true;
  if (path == '.last_build_id') return true;
  if (path.startsWith('canvaskit/skwasm')) return true;
  if (path.startsWith('canvaskit/wimp')) return true;
  if (path.startsWith('canvaskit/experimental_webparagraph/')) return true;
  return false;
}

void fail(List<String> errors) {
  for (String error in errors) {
    stderr.writeln('ERROR: $error');
  }
  exit(1);
}

void main(List<String> args) {
  final String buildDir = (args.isNotEmpty ? args[0] : 'build/web')
      .replaceAll(RegExp(r'[/\\]+$'), '');
  final Directory dir = Directory(buildDir);
  if (!dir.existsSync()) {
    fail(['Build directory not found: $buildDir']);
  }

  final Map<String, String> manifest = {};
  int totalBytes = 0;
  final List<File> files =
      dir.listSync(recursive: true, followLinks: false).whereType<File>().toList();
  for (File file in files) {
    final String path = file.path
        .substring(dir.path.length + 1)
        .replaceAll('\\', '/');
    if (excludedFromPrecache(path)) continue;
    final List<int> bytes = file.readAsBytesSync();
    manifest[path] = getCrc32(bytes).toRadixString(16);
    totalBytes += bytes.length;
  }

  final List<String> errors = [];
  for (String path in criticalFiles) {
    if (!manifest.containsKey(path)) {
      errors.add('Critical file missing from $buildDir: $path');
    }
  }

  final File bootstrap = File('$buildDir/flutter_bootstrap.js');
  if (!bootstrap.existsSync()) {
    errors.add('flutter_bootstrap.js not found in $buildDir');
  } else if (!bootstrap
      .readAsStringSync()
      .contains("navigator.serviceWorker.register('sw.js')")) {
    errors.add('flutter_bootstrap.js does not register sw.js. '
        'The custom web/flutter_bootstrap.js template may have been ignored '
        'by this version of Flutter.');
  }

  final File swFile = File('$buildDir/sw.js');
  if (!swFile.existsSync()) {
    errors.add('sw.js not found in $buildDir. '
        'Is web/sw.js missing or not being copied by the build?');
  }
  if (errors.isNotEmpty) fail(errors);

  String sw = swFile.readAsStringSync();
  if (!sw.contains(manifestPlaceholder) || !sw.contains(versionPlaceholder)) {
    fail(['sw.js placeholders not found. '
        'Either the injector already ran on this build, or web/sw.js '
        'no longer matches tool/inject_service_worker.dart.']);
  }

  final List<String> sortedPaths = manifest.keys.toList()..sort();
  final Map<String, String> sortedManifest = {
    for (String path in sortedPaths) path: manifest[path]!,
  };
  final String manifestJson = jsonEncode(sortedManifest);
  final String version =
      getCrc32(utf8.encode(manifestJson)).toRadixString(16);

  sw = sw
      .replaceFirst(manifestPlaceholder, 'const RESOURCES = $manifestJson;')
      .replaceFirst(versionPlaceholder, "const VERSION = '$version';");
  swFile.writeAsStringSync(sw);

  final String megabytes = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
  stdout.writeln('Service worker manifest injected: '
      '${sortedManifest.length} files, $megabytes MB, version $version');
}
