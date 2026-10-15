import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/modern/portrait_appearance.dart';
import 'package:lcs_new_age/modern/portrait_face_frames.dart';
import 'package:lcs_new_age/modern/portrait_overlay_geometry.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  Creature person() => Creature()
    ..birthDate = DateTime(1985)
    ..portraitVariant = 0;

  test('dressings follow actual injuries and disappear after healing', () {
    final p = person();
    final body = p.body as HumanoidBody;
    final healthy = PortraitAppearance.fromPerson(p);
    body.head.cut = true;
    body.missingLeftEye = true;
    final injured = PortraitAppearance.fromPerson(p);
    expect(injured.headWound, isTrue);
    expect(injured.missingLeftEye, isTrue);
    expect(injured.missingRightEye, isFalse);
    expect(healthy.headWound, isFalse);
    expect(
      PortraitAppearancePainter(
        injured,
      ).shouldRepaint(PortraitAppearancePainter(healthy)),
      isTrue,
    );
    body.head.heal();
    final healed = PortraitAppearance.fromPerson(p);
    expect(healed.headWound, isFalse);
    expect(healed.missingLeftEye, isTrue);
  });

  test('only human faces receive facial overlays', () {
    final p = person();
    p.body = dogBody();
    (p.body as HumanoidBody)
      ..missingLeftEye = true
      ..head.cut = true;
    final animal = PortraitAppearance.fromPerson(p);
    expect(animal.headWound, isFalse);
    expect(animal.missingLeftEye, isFalse);
  });

  test(
    'equipment and elapsed age change appearance without changing identity',
    () {
      final p = person()..portraitId = 24;
      p.portraitAssignedAge = p.age;
      expect(PortraitAppearance.fromPerson(p).agingDecades, 0);
      p.portraitAssignedAge = p.age - 20;
      p.equippedClothing = Clothing('CLOTHING_LABCOAT');
      var a = PortraitAppearance.fromPerson(p);
      expect(a.agingDecades, 2);
      expect(a.clothing, PortraitClothing.medical);
      p.equippedClothing = Clothing('CLOTHING_SWATARMOR');
      a = PortraitAppearance.fromPerson(p);
      expect(a.clothing, PortraitClothing.armor);
      expect(p.portraitId, 24);
      p.equippedClothing = Clothing('CLOTHING_HEAVYARMOR');
      expect(PortraitAppearance.fromPerson(p).helmet, isTrue);
      p.equippedClothing = Clothing('CLOTHING_MILITARY');
      expect(
        PortraitAppearance.fromPerson(p).clothing,
        PortraitClothing.uniform,
      );
      expect(PortraitAppearance.fromPerson(p).helmet, isFalse);
      p.equippedClothing = Clothing('CLOTHING_HABIT');
      expect(PortraitAppearance.fromPerson(p).clothing, PortraitClothing.robe);
      expect(PortraitAppearance.fromPerson(p).helmet, isFalse);
      p.equippedClothing = null;
      expect(PortraitAppearance.fromPerson(p).clothing, PortraitClothing.none);
    },
  );

  test('anatomical eye dressings cover opposite viewer sides', () async {
    Future<ui.Image> render(PortraitAppearance a) async {
      final recorder = ui.PictureRecorder();
      PortraitAppearancePainter(
        a,
        faceFrame: const Rect.fromLTWH(.25, .2, .5, .5),
      ).paint(Canvas(recorder), const Size(200, 200));
      final picture = recorder.endRecording();
      final image = await picture.toImage(200, 200);
      picture.dispose();
      return image;
    }

    final left = await render(const PortraitAppearance(missingLeftEye: true));
    final bytes = (await left.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int alpha(int x, int y) => bytes.getUint8((y * 200 + x) * 4 + 3);
    expect(alpha(120, 77), greaterThan(0));
    expect(alpha(75, 77), 0);
    left.dispose();
  });

  test('ageing preserves bald temples and only adds forehead cues', () async {
    final recorder = ui.PictureRecorder();
    const PortraitAppearancePainter(
      PortraitAppearance(agingDecades: 3),
      faceFrame: Rect.fromLTWH(.25, .2, .5, .5),
    ).paint(Canvas(recorder), const Size(200, 200));
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 200);
    final pixels = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var marks = 0;
    for (var y = 0; y < 200; y++) {
      for (var x = 0; x < 200; x++) {
        if (pixels.getUint8((y * 200 + x) * 4 + 3) > 0) {
          marks++;
          expect(x, inInclusiveRange(78, 122));
          expect(y, inInclusiveRange(44, 64));
        }
      }
    }
    expect(marks, greaterThan(0));
    image.dispose();
    picture.dispose();
  });

  test('painted overlay geometry matches packed manifest content', () async {
    final manifest =
        jsonDecode(
              await File(
                'assets/modern/portraits_v2/manifest-v3.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final overlays = manifest['appearanceOverlays'] as Map<String, dynamic>;
    final dimensions = overlays['runtimeSize'] as List<dynamic>;
    final rows = overlays['overlays'] as List<dynamic>;
    expect(portraitOverlayContentRects.length, rows.length);
    for (var i = 0; i < rows.length; i++) {
      final rect =
          (rows[i] as Map<String, dynamic>)['contentRect'] as List<dynamic>;
      final actual = portraitOverlayContentRects[i];
      expect(
        actual.left,
        closeTo((rect[0] as num) / (dimensions[0] as num), .000001),
      );
      expect(
        actual.top,
        closeTo((rect[1] as num) / (dimensions[1] as num), .000001),
      );
      expect(
        actual.width,
        closeTo((rect[2] as num) / (dimensions[0] as num), .000001),
      );
      expect(
        actual.height,
        closeTo((rect[3] as num) / (dimensions[1] as num), .000001),
      );
    }
  });

  test('render appearance review sheet', () async {
    final bytes = await File(
      'assets/modern/portraits_v2/batch_00.png',
    ).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final atlas = (await codec.getNextFrame()).image;
    codec.dispose();
    ui.Image? overlays;
    final overlayFile = File(
      'assets/modern/portraits_v2/appearance_overlays.png',
    );
    if (overlayFile.existsSync()) {
      final overlayCodec = await ui.instantiateImageCodec(
        await overlayFile.readAsBytes(),
      );
      overlays = (await overlayCodec.getNextFrame()).image;
      overlayCodec.dispose();
    }
    const examples = [
      PortraitAppearance(),
      PortraitAppearance(headWound: true),
      PortraitAppearance(missingLeftEye: true),
      PortraitAppearance(missingRightEye: true, missingNose: true),
      PortraitAppearance(clothing: PortraitClothing.medical),
      PortraitAppearance(clothing: PortraitClothing.formal),
      PortraitAppearance(clothing: PortraitClothing.armor, helmet: true),
      PortraitAppearance(
        clothing: PortraitClothing.uniform,
        faceCovering: true,
      ),
      PortraitAppearance(agingDecades: 1),
      PortraitAppearance(agingDecades: 3),
      PortraitAppearance(variant: 1),
      PortraitAppearance(variant: 12),
    ];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < examples.length; i++) {
      canvas.save();
      canvas.translate((i % 4) * 200.0, (i ~/ 4) * 200.0);
      final cell = i.isEven ? 0 : 5;
      canvas.drawImageRect(
        atlas,
        Rect.fromLTWH(
          (cell % 4) * atlas.width / 4,
          (cell ~/ 4) * atlas.height / 4,
          atlas.width / 4,
          atlas.height / 4,
        ),
        const Rect.fromLTWH(0, 0, 200, 200),
        Paint(),
      );
      PortraitAppearancePainter(
        examples[i],
        faceFrame: portraitFaceFrames[cell],
        overlayAtlas: overlays,
      ).paint(canvas, const Size(200, 200));
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final result = await picture.toImage(800, 600);
    final png = await result.toByteData(format: ui.ImageByteFormat.png);
    final output = File('../reports/portrait-appearance-preview.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(png!.buffer.asUint8List());
    result.dispose();
    picture.dispose();
    atlas.dispose();
    overlays?.dispose();
  });
}
