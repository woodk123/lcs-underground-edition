import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/portrait_appearance.dart';
import 'package:lcs_new_age/modern/portrait_face_frames.dart';

// Actual native-codec renders for independent visual review, not golden images.
void main() {
  test(
    'expanded atlases decode and render with existing appearance layers',
    () async {
      final manifest = jsonDecode(
        await File('assets/modern/portraits_v2/manifest-v4.json')
            .readAsString(),
      ) as Map<String, dynamic>;
      final atlases = manifest['atlases'] as List<dynamic>;
      expect(atlases.length, 64);
      final overlayCodec = await ui.instantiateImageCodec(
        await File('assets/modern/portraits_v2/appearance_overlays.webp')
            .readAsBytes(),
      );
      final overlay = (await overlayCodec.getNextFrame()).image;
      overlayCodec.dispose();
      const examples = [
        PortraitAppearance(),
        PortraitAppearance(headWound: true, missingLeftEye: true),
        PortraitAppearance(missingRightEye: true, missingNose: true),
        PortraitAppearance(clothing: PortraitClothing.medical),
        PortraitAppearance(clothing: PortraitClothing.armor, helmet: true),
        PortraitAppearance(
          clothing: PortraitClothing.uniform,
          faceCovering: true,
        ),
        PortraitAppearance(agingDecades: 3),
      ];
      final output = Directory('../reports/portraits-v4/appearance');
      await output.create(recursive: true);
      for (final value in atlases) {
        final atlas = value as Map<String, dynamic>;
        final batch = atlas['batch'] as int;
        final codec = await ui.instantiateImageCodec(
          await File(atlas['asset'] as String).readAsBytes(),
        );
        final image = (await codec.getNextFrame()).image;
        codec.dispose();
        expect(image.width, 1024);
        expect(image.height, 1024);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (var row = 0; row < 4; row++) {
          final cell = row * 5;
          final identity = 378 + (batch - 24) * 16 + cell;
          for (var column = 0; column < examples.length; column++) {
            canvas.save();
            canvas.translate(column * 128.0, row * 148.0);
            canvas.clipRect(const Rect.fromLTWH(0, 0, 128, 128));
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(cell % 4 * 256.0, cell ~/ 4 * 256.0, 256, 256),
              const Rect.fromLTWH(0, 0, 128, 128),
              Paint(),
            );
            // Dogs never receive human equipment or medical facial overlays.
            if (batch != 87) {
              PortraitAppearancePainter(
                examples[column],
                faceFrame: portraitFaceFrames[identity],
                overlayAtlas: overlay,
              ).paint(canvas, const Size(128, 128));
            }
            canvas.restore();
            final label = TextPainter(
              text: TextSpan(
                text: '$identity / $column',
                style: const TextStyle(color: Colors.black, fontSize: 12),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            label.paint(canvas, Offset(column * 128.0 + 4, row * 148.0 + 130));
            label.dispose();
          }
        }
        final picture = recorder.endRecording();
        final rendered = await picture.toImage(896, 592);
        final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/batch_$batch.png')
            .writeAsBytes(png!.buffer.asUint8List());
        rendered.dispose();
        picture.dispose();
        image.dispose();
      }
      overlay.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
