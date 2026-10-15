import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/portrait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'every compressed atlas decodes with the native Flutter image codec',
    () async {
      final staticArt =
          jsonDecode(
                await File(
                  '../assets/runtime-art/manifest.json',
                ).readAsString(),
              )
              as Map<String, dynamic>;
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
      expect(dimensions.length, 41);
      expect(packagedImages, unorderedEquals(dimensions.keys));
      for (final entry in dimensions.entries) {
        final bytes = await rootBundle.load(entry.key);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final image = (await codec.getNextFrame()).image;
        expect([image.width, image.height], entry.value, reason: entry.key);
        image.dispose();
        codec.dispose();
      }
    },
  );

  test('transparent art retains exact alpha and native color fidelity', () async {
    final manifest =
        jsonDecode(
              await File('../assets/runtime-art/manifest.json').readAsString(),
            )
            as Map<String, dynamic>;
    for (final item in manifest['assets'] as List<dynamic>) {
      final record = item as Map<String, dynamic>;
      if (record['lossless'] != true) continue;
      final original = await ui.instantiateImageCodec(
        await File('../${record['original_path']}').readAsBytes(),
      );
      final runtime = await ui.instantiateImageCodec(
        await File('../${record['runtime_path']}').readAsBytes(),
      );
      final originalImage = (await original.getNextFrame()).image;
      final runtimeImage = (await runtime.getNextFrame()).image;
      final originalPixels = await originalImage.toByteData();
      final runtimePixels = await runtimeImage.toByteData();
      final before = originalPixels!.buffer.asUint8List();
      final after = runtimePixels!.buffer.asUint8List();
      var maximumColorDifference = 0;
      var alphaDifferences = 0;
      for (var offset = 0; offset < before.length; offset++) {
        final difference = (before[offset] - after[offset]).abs();
        if (offset % 4 == 3) {
          if (difference != 0) alphaDifferences++;
        } else if (difference > maximumColorDifference) {
          maximumColorDifference = difference;
        }
      }
      expect(alphaDifferences, 0, reason: record['runtime_path'] as String);
      // PNG and WebP codecs round premultiplied RGB independently at alpha edges.
      // The encoded straight-RGBA pixels are verified identical by the generator.
      expect(
        maximumColorDifference,
        lessThanOrEqualTo(1),
        reason: record['runtime_path'] as String,
      );
      originalImage.dispose();
      runtimeImage.dispose();
      original.dispose();
      runtime.dispose();
    }
  });
}
