import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/portrait.dart';

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final staticArt = jsonDecode(
    File('../assets/runtime-art/manifest.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test(
    'every compressed atlas decodes with the native Flutter image codec',
    () async {
      final dimensions = <String, List<int>>{};
      for (final item in staticArt['assets'] as List<dynamic>) {
        final record = item as Map<String, dynamic>;
        dimensions[(record['runtime_path'] as String).substring(
          'upstream/'.length,
        )] = [
          record['width'] as int,
          record['height'] as int,
        ];
      }
      for (final portrait in portraitCatalog) {
        dimensions[portrait.asset] = [1024, 1024];
      }
      dimensions['assets/modern/portraits_v2/appearance_overlays.webp'] = [
        1024,
        1024,
      ];
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final packagedImages = manifest.listAssets().where(
        (path) =>
            path.startsWith('assets/modern/') &&
            (path.endsWith('.webp') || path.endsWith('.png')),
      );
      expect(dimensions.length, greaterThanOrEqualTo(41));
      expect(packagedImages, unorderedEquals(dimensions.keys));
      for (final entry in dimensions.entries) {
        final bytes = await rootBundle.load(entry.key);
        final image = await _decode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        );
        try {
          expect([image.width, image.height], entry.value, reason: entry.key);
        } finally {
          image.dispose();
        }
      }
    },
  );

  // Keep the complete pixel comparison, with a timeout and failure name for
  // each asset instead of one shared 30-second budget for the whole catalogue.
  for (final item in staticArt['assets'] as List<dynamic>) {
    final record = item as Map<String, dynamic>;
    if (record['has_alpha'] != true) continue;
    test(
      'exact alpha and native color fidelity: ${record['runtime_path']}',
      () async {
        final images = <ui.Image>[];
        try {
          final originalImage = await _decode(
            await File('../${record['original_path']}').readAsBytes(),
          );
          images.add(originalImage);
          final runtimeImage = await _decode(
            await File('../${record['runtime_path']}').readAsBytes(),
          );
          images.add(runtimeImage);
          expect(
            [runtimeImage.width, runtimeImage.height],
            [originalImage.width, originalImage.height],
          );
          final originalPixels = (await originalImage.toByteData())!;
          final runtimePixels = (await runtimeImage.toByteData())!;
          final before = originalPixels.buffer.asUint8List(
            originalPixels.offsetInBytes,
            originalPixels.lengthInBytes,
          );
          final after = runtimePixels.buffer.asUint8List(
            runtimePixels.offsetInBytes,
            runtimePixels.lengthInBytes,
          );
          expect(after.length, before.length);
          var squaredColorDifference = 0;
          var alphaDifferences = 0;
          for (var offset = 0; offset < before.length; offset++) {
            final difference = (before[offset] - after[offset]).abs();
            if (offset % 4 == 3) {
              if (difference != 0) alphaDifferences++;
            } else {
              squaredColorDifference += difference * difference;
            }
          }
          expect(alphaDifferences, 0);
          // Colour is lossy at quality 90; alpha and atlas geometry stay exact.
          // Bound average native-decoded colour error without requiring identical RGB.
          expect(
            squaredColorDifference / (before.length * 3 / 4),
            lessThanOrEqualTo(100),
          );
        } finally {
          for (final image in images) {
            image.dispose();
          }
        }
      },
    );
  }
}
