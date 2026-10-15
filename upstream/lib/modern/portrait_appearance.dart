import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/portrait_overlay_geometry.dart';

enum PortraitClothing {
  none,
  casual,
  work,
  formal,
  medical,
  uniform,
  armor,
  robe,
}

/// An immutable snapshot: mutable body/equipment objects must not be retained by
/// a painter, otherwise an injury can make both old and new delegates identical.
@immutable
class PortraitAppearance {
  const PortraitAppearance({
    this.headWound = false,
    this.missingLeftEye = false,
    this.missingRightEye = false,
    this.missingNose = false,
    this.agingDecades = 0,
    this.clothing = PortraitClothing.none,
    this.clothingName = '',
    this.helmet = false,
    this.faceCovering = false,
    this.variant = 0,
  });

  factory PortraitAppearance.fromPerson(Creature person) {
    // Animal portraits have different facial landmarks, even where their model
    // inherits HumanoidBody. Never put human eye/nose dressings on those faces.
    if (person.body.type != BodyType.human || !person.human) {
      return PortraitAppearance(variant: person.portraitVariant ?? 0);
    }
    final body = person.body as HumanoidBody;
    final equipped = person.equippedClothing;
    final id = equipped?.type.idName ?? '';
    final clothing = switch (id) {
      '' || 'CLOTHING_NONE' => PortraitClothing.none,
      _
          when equipped?.armor?.visible == true &&
              (equipped?.armor?.bodyArmor ?? 0) > 0 =>
        PortraitClothing.armor,
      'CLOTHING_LABCOAT' || 'CLOTHING_SCRUBS' => PortraitClothing.medical,
      _
          when id.contains('ARMOR') ||
              id == 'CLOTHING_SEALSUIT' ||
              id == 'CLOTHING_PMC' ||
              id == 'CLOTHING_TACHARNESS' ||
              id == 'CLOTHING_MITHRIL' ||
              id == 'CLOTHING_STEELHAUBERK' =>
        PortraitClothing.armor,
      _
          when id.contains('UNIFORM') ||
              id == 'CLOTHING_CAMOSUIT' ||
              id == 'CLOTHING_MILITARY' ||
              id == 'CLOTHING_PRISONGUARD' =>
        PortraitClothing.uniform,
      'CLOTHING_BLACKROBE' ||
      'CLOTHING_HABIT' ||
      'CLOTHING_CASSOCK' ||
      'CLOTHING_TOGA' => PortraitClothing.robe,
      'CLOTHING_CHEAPSUIT' ||
      'CLOTHING_EXPENSIVESUIT' ||
      'CLOTHING_BLACKSUIT' ||
      'CLOTHING_BLACKSUIT_AGENT' => PortraitClothing.formal,
      _
          when id.contains('WORK') ||
              id.contains('OVERALL') ||
              id == 'CLOTHING_BUNKERGEAR' ||
              id == 'CLOTHING_HARDHAT' ||
              id == 'CLOTHING_CHEF' ||
              id == 'CLOTHING_APRON' =>
        PortraitClothing.work,
      _ => PortraitClothing.casual,
    };
    return PortraitAppearance(
      headWound: body.head.wounded && !body.head.missing,
      missingLeftEye: body.missingLeftEye,
      missingRightEye: body.missingRightEye,
      missingNose: body.missingNose,
      agingDecades:
          ((person.age - (person.portraitAssignedAge ?? person.age)) ~/ 10)
              .clamp(0, 4),
      clothing: clothing,
      clothingName: equipped?.type.shortName ?? '',
      helmet:
          const {
            'CLOTHING_ARMYARMOR',
            'CLOTHING_HEAVYARMOR',
            'CLOTHING_SWATARMOR',
            'CLOTHING_SEALSUIT',
          }.contains(id) &&
          equipped!.type.coversHead,
      faceCovering: equipped?.type.concealsFace ?? false,
      variant: person.portraitVariant ?? 0,
    );
  }

  final bool headWound, missingLeftEye, missingRightEye, missingNose;
  final int agingDecades, variant;
  final PortraitClothing clothing;
  final String clothingName;
  final bool helmet, faceCovering;

  String get description => [
    if (headWound) 'Head wound indicated by a dressing',
    if (missingLeftEye) 'Left eye missing',
    if (missingRightEye) 'Right eye missing',
    if (missingNose) 'Nose missing',
    if (agingDecades > 0) 'Aged since this portrait was assigned',
    if (clothing != PortraitClothing.none) 'Stylised clothing: $clothingName',
    if (faceCovering) 'Face-concealing clothing equipped',
    if (variant > 0) 'Alternate portrait border',
  ].join('. ');

  List<Object> get _values => [
    headWound,
    missingLeftEye,
    missingRightEye,
    missingNose,
    agingDecades,
    variant,
    clothing,
    clothingName,
    helmet,
    faceCovering,
  ];

  @override
  bool operator ==(Object other) =>
      other is PortraitAppearance &&
      List.generate(
        _values.length,
        (i) => _values[i] == other._values[i],
      ).every((v) => v);
  @override
  int get hashCode => Object.hashAll(_values);
}

/// Small, intentionally stylised updates over a persistent painted identity.
/// Coordinates are normalised to the human head-and-shoulders portrait framing.
class PortraitAppearancePainter extends CustomPainter {
  const PortraitAppearancePainter(
    this.appearance, {
    this.faceFrame,
    this.overlayAtlas,
  });
  final PortraitAppearance appearance;
  final Rect? faceFrame;
  final ui.Image? overlayAtlas;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width, size.height);
    final a = appearance;
    if (overlayAtlas != null) {
      _paintIllustrated(canvas);
      _paintVariant(canvas);
      canvas.restore();
      return;
    }
    if (a.clothing != PortraitClothing.none) {
      final color = switch (a.clothing) {
        PortraitClothing.medical => const Color(0xffd7d4c4),
        PortraitClothing.formal => const Color(0xff303432),
        PortraitClothing.work => const Color(0xff77664e),
        PortraitClothing.uniform => const Color(0xff4c5946),
        PortraitClothing.armor => const Color(0xff3c4745),
        PortraitClothing.robe => const Color(0xff292926),
        _ => const Color(0xff68644f),
      };
      final shoulders = Path()
        ..moveTo(0, 1)
        ..lineTo(0, .90)
        ..quadraticBezierTo(.13, .83, .34, .81)
        ..lineTo(.5, .94)
        ..lineTo(.66, .81)
        ..quadraticBezierTo(.87, .83, 1, .90)
        ..lineTo(1, 1)
        ..close();
      canvas.drawPath(
        shoulders,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, .83),
            const Offset(1, 1),
            [
              Color.lerp(color, Colors.white, .12)!,
              color,
              Color.lerp(color, Colors.black, .28)!,
            ],
            const [0, .45, 1],
          ),
      );
      canvas.save();
      canvas.clipPath(shoulders);
      final weave = Paint()
        ..color = Colors.black.withValues(alpha: .065)
        ..strokeWidth = .002;
      for (var i = 0; i < 90; i++) {
        final x = i * .017;
        canvas.drawLine(Offset(x, .80), Offset(x - .15, 1), weave);
      }
      canvas.restore();
      final seam = Paint()
        ..color = const Color(0xffb4ad91).withValues(alpha: .50)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .009;
      canvas.drawLine(const Offset(.34, .83), const Offset(.5, .96), seam);
      canvas.drawLine(const Offset(.66, .83), const Offset(.5, .96), seam);
      if (a.clothing == PortraitClothing.armor) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(.26, .94, .48, .10),
            const Radius.circular(.015),
          ),
          Paint()..color = const Color(0xff252c2b),
        );
      }
    }
    canvas.save();
    final frame = faceFrame;
    if (frame != null) {
      canvas.translate(frame.left, frame.top);
      canvas.scale(frame.width, frame.height);
    }
    final dressing = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(1, 1),
        const [Color(0xffeee5ca), Color(0xffbab19b)],
      );
    final edge = Paint()
      ..color = const Color(0xff6b6250)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .009;
    void bandage(Rect rect) {
      final shape = RRect.fromRectAndRadius(rect, const Radius.circular(.015));
      canvas.drawRRect(shape, dressing);
      canvas.drawRRect(shape, edge);
      canvas.save();
      canvas.clipRRect(shape);
      final gauze = Paint()
        ..color = const Color(0xff82765d).withValues(alpha: .16)
        ..strokeWidth = .003;
      for (var x = rect.left; x < rect.right; x += .012) {
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gauze);
      }
      for (var y = rect.top; y < rect.bottom; y += .012) {
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gauze);
      }
      canvas.restore();
      final stitch = Paint()
        ..color = const Color(0xffb2a98f)
        ..strokeWidth = .006;
      canvas.drawLine(
        Offset(rect.left + .015, rect.center.dy),
        Offset(rect.right - .015, rect.center.dy),
        stitch,
      );
    }

    if (frame != null && a.agingDecades > 0) {
      _paintAging(canvas);
    }
    if (frame != null && a.headWound) {
      bandage(const Rect.fromLTWH(.10, .04, .46, .12));
    }
    // Anatomical left appears on the viewer's right in a front-facing portrait.
    if (frame != null && a.missingLeftEye) {
      bandage(const Rect.fromLTWH(.56, .27, .32, .20));
    }
    if (frame != null && a.missingRightEye) {
      bandage(const Rect.fromLTWH(.10, .27, .32, .20));
    }
    if (frame != null && a.missingNose) {
      bandage(const Rect.fromLTWH(.41, .49, .22, .27));
    }
    if (frame != null && a.helmet) {
      canvas.drawPath(
        Path()
          ..moveTo(-.12, .16)
          ..quadraticBezierTo(-.12, -.42, .5, -.42)
          ..quadraticBezierTo(1.12, -.42, 1.12, .16)
          ..close(),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, -.4),
            const Offset(1, .2),
            const [Color(0xff687263), Color(0xff303a31)],
          ),
      );
      canvas.drawLine(const Offset(-.12, .16), const Offset(1.12, .16), edge);
    }
    if (frame != null && a.faceCovering) {
      canvas.drawPath(
        Path()
          ..moveTo(.04, .52)
          ..lineTo(.96, .52)
          ..lineTo(.82, .89)
          ..quadraticBezierTo(.5, 1.04, .18, .89)
          ..close(),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, .52),
            const Offset(0, 1),
            const [Color(0xff515b50), Color(0xff252c26)],
          ),
      );
    }
    canvas.restore();
    _paintVariant(canvas);
    canvas.restore();
  }

  void _paintIllustrated(Canvas canvas) {
    final image = overlayAtlas!;
    final a = appearance;
    void draw(int cell, Rect target, {double opacity = 1}) {
      final content = portraitOverlayContentRects[cell];
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(
          content.left * image.width,
          content.top * image.height,
          content.width * image.width,
          content.height * image.height,
        ),
        target,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Colors.white.withValues(alpha: opacity),
      );
    }

    if (a.clothing != PortraitClothing.none) {
      final cell = switch (a.clothing) {
        PortraitClothing.medical => 8,
        PortraitClothing.formal => 9,
        PortraitClothing.work => 10,
        PortraitClothing.uniform => 11,
        PortraitClothing.armor => 12,
        PortraitClothing.robe => 13,
        _ => 14,
      };
      draw(cell, const Rect.fromLTWH(0, .74, 1, .28));
    }
    final frame = faceFrame;
    if (frame == null) return;
    canvas.save();
    canvas.translate(frame.left, frame.top);
    canvas.scale(frame.width, frame.height);
    if (a.agingDecades > 0) {
      _paintAging(canvas);
    }
    if (a.headWound) draw(0, const Rect.fromLTWH(.10, .04, .46, .12));
    if (a.missingLeftEye) draw(1, const Rect.fromLTWH(.56, .27, .32, .20));
    if (a.missingRightEye) draw(2, const Rect.fromLTWH(.10, .27, .32, .20));
    if (a.missingNose) draw(3, const Rect.fromLTWH(.41, .49, .22, .27));
    if (a.helmet) draw(4, const Rect.fromLTWH(-.12, -.42, 1.24, .60));
    if (a.faceCovering) draw(5, const Rect.fromLTWH(.04, .52, .92, .48));
    canvas.restore();
  }

  // Conservative forehead lines preserve the existing hairstyle, including
  // baldness. Painted hair additions need reliable hair segmentation first.
  void _paintAging(Canvas canvas) {
    final wrinkle = Paint()
      ..color = const Color(
        0xff665a4e,
      ).withValues(alpha: .15 + .035 * appearance.agingDecades)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .006;
    for (var i = 0; i < appearance.agingDecades.clamp(0, 3); i++) {
      canvas.drawArc(
        Rect.fromLTWH(.30, .08 + i * .035, .4, .06),
        3.4,
        2.5,
        false,
        wrinkle,
      );
    }
  }

  void _paintVariant(Canvas canvas) {
    final a = appearance;
    if (a.variant > 0) {
      const accents = [
        Color(0xff80774c),
        Color(0xff57716c),
        Color(0xff8b6450),
        Color(0xff75647e),
        Color(0xff4f6179),
      ];
      final ink = Paint()
        ..color = accents[(a.variant - 1) % accents.length]
        ..strokeWidth = .025;
      canvas.drawLine(const Offset(.012, .02), const Offset(.012, .98), ink);
      // Additional small corner strokes distinguish repeated palette cycles.
      for (var i = 0; i < 1 + (a.variant ~/ accents.length) % 4; i++) {
        canvas.drawLine(
          Offset(.045 + i * .045, .975),
          Offset(.07 + i * .045, .975),
          ink,
        );
      }
    }
  }

  @override
  bool shouldRepaint(PortraitAppearancePainter oldDelegate) =>
      oldDelegate.appearance != appearance ||
      oldDelegate.faceFrame != faceFrame ||
      oldDelegate.overlayAtlas != overlayAtlas;
}
