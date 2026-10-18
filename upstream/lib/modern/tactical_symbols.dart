import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Shape as well as colour identifies units on the field plan.
enum TacticalUnitSymbol { squad, enemy, wounded, armored }

/// Resolution-independent marks for a journal field plan.
///
/// These painters only receive presentation state. They never inspect the map,
/// reveal hidden terrain, or decide whether an action is available. Geometry is
/// drawn on a 24-unit grid, keeping its silhouette legible in small map cells.
abstract final class TacticalSymbols {
  static void drawDoor(
    Canvas canvas,
    Rect rect, {
    required bool horizontal,
    required bool locked,
    required bool blocked,
    required bool metal,
    bool burning = false,
  }) {
    _local(canvas, rect, () {
      final ink = metal ? JournalPalette.ink : JournalPalette.brassDark;
      canvas.save();
      if (!horizontal) {
        canvas.translate(24, 0);
        canvas.rotate(math.pi / 2);
      }
      // Broad jambs and a narrower leaf make orientation visible independently
      // of the optional status badge.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2.5, 8, 19, 8),
          const Radius.circular(1),
        ),
        _fill(JournalPalette.card),
      );
      canvas.drawLine(
        const Offset(3.5, 7),
        const Offset(3.5, 17),
        _stroke(ink, 2),
      );
      canvas.drawLine(
        const Offset(20.5, 7),
        const Offset(20.5, 17),
        _stroke(ink, 2),
      );
      const leaf = Rect.fromLTWH(6, 9.5, 12, 5);
      canvas.drawRect(
        leaf,
        _fill(metal ? JournalPalette.rule : JournalPalette.brassLight),
      );
      canvas.drawRect(leaf, _stroke(ink, 1.5));
      if (metal) {
        canvas.drawLine(
          const Offset(7, 12),
          const Offset(17, 12),
          _stroke(ink, 1),
        );
        canvas.drawCircle(
          const Offset(8, 10.8),
          .7,
          _fill(JournalPalette.card),
        );
        canvas.drawCircle(
          const Offset(16, 13.2),
          .7,
          _fill(JournalPalette.card),
        );
      } else {
        canvas.drawCircle(const Offset(15, 12), .9, _fill(ink));
      }
      canvas.restore();
      if (burning) {
        _badge(canvas, const Offset(18.5, 18), JournalPalette.danger);
        _flame(
          canvas,
          const Rect.fromLTWH(15.2, 14.2, 6.6, 7.5),
          JournalPalette.card,
        );
      } else if (blocked) {
        _badge(canvas, const Offset(18.5, 18), JournalPalette.danger);
        final cross = _stroke(JournalPalette.card, 1.8);
        canvas.drawLine(const Offset(16.5, 16), const Offset(20.5, 20), cross);
        canvas.drawLine(const Offset(20.5, 16), const Offset(16.5, 20), cross);
      } else if (locked) {
        _badge(canvas, const Offset(18.5, 18), JournalPalette.brassDark);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(16, 17.3, 5, 3.8),
            const Radius.circular(.6),
          ),
          _fill(JournalPalette.card),
        );
        canvas.drawArc(
          const Rect.fromLTWH(16.8, 14.6, 3.4, 5.3),
          math.pi,
          math.pi,
          false,
          _stroke(JournalPalette.card, 1.3),
        );
      }
    });
  }

  static void drawStairs(Canvas canvas, Rect rect, {required bool up}) {
    _local(canvas, rect, () {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 2, 20, 20),
          const Radius.circular(2),
        ),
        _fill(JournalPalette.card),
      );
      final ink = _stroke(JournalPalette.brassDark, 1.6);
      final steps = Path()
        ..moveTo(4, 18)
        ..lineTo(8, 18)
        ..lineTo(8, 14)
        ..lineTo(12, 14)
        ..lineTo(12, 10)
        ..lineTo(16, 10)
        ..lineTo(16, 6)
        ..lineTo(20, 6);
      canvas.drawPath(steps, ink);
      // A separate arrow stays recognisable when stair tread details are tiny.
      canvas.drawLine(const Offset(6, 5), const Offset(6, 11), ink);
      final arrow = up
          ? (Path()
              ..moveTo(3.6, 7.4)
              ..lineTo(6, 5)
              ..lineTo(8.4, 7.4))
          : (Path()
              ..moveTo(3.6, 8.6)
              ..lineTo(6, 11)
              ..lineTo(8.4, 8.6));
      canvas.drawPath(arrow, ink);
    });
  }

  static void drawExit(Canvas canvas, Rect rect) {
    _local(canvas, rect, () {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 2, 20, 20),
          const Radius.circular(2),
        ),
        _fill(JournalPalette.card),
      );
      final ink = _stroke(JournalPalette.olive, 1.9);
      final doorway = Path()
        ..moveTo(11, 19)
        ..lineTo(5, 19)
        ..lineTo(5, 5)
        ..lineTo(13, 5)
        ..lineTo(13, 8);
      canvas.drawPath(doorway, ink);
      canvas.drawLine(const Offset(10, 12), const Offset(20, 12), ink);
      canvas.drawPath(
        Path()
          ..moveTo(16.3, 8.3)
          ..lineTo(20, 12)
          ..lineTo(16.3, 15.7),
        ink,
      );
    });
  }

  static void drawUnit(
    Canvas canvas,
    Rect rect, {
    required TacticalUnitSymbol kind,
  }) {
    _local(canvas, rect, () {
      final friendly = kind == TacticalUnitSymbol.squad;
      final colour = friendly ? JournalPalette.olive : JournalPalette.danger;
      final shape = Path();
      switch (kind) {
        case TacticalUnitSymbol.squad:
          shape.addOval(const Rect.fromLTWH(2.5, 2.5, 19, 19));
        case TacticalUnitSymbol.enemy:
          shape
            ..moveTo(12, 1.5)
            ..lineTo(22.5, 12)
            ..lineTo(12, 22.5)
            ..lineTo(1.5, 12)
            ..close();
        case TacticalUnitSymbol.wounded:
          shape
            ..moveTo(8, 2.5)
            ..lineTo(16, 2.5)
            ..lineTo(21.5, 8)
            ..lineTo(21.5, 16)
            ..lineTo(16, 21.5)
            ..lineTo(8, 21.5)
            ..lineTo(2.5, 16)
            ..lineTo(2.5, 8)
            ..close();
        case TacticalUnitSymbol.armored:
          shape
            ..moveTo(12, 1.5)
            ..lineTo(21.5, 5)
            ..lineTo(20, 15)
            ..quadraticBezierTo(18, 20, 12, 22)
            ..quadraticBezierTo(6, 20, 4, 15)
            ..lineTo(2.5, 5)
            ..close();
      }
      canvas.drawPath(shape, _stroke(JournalPalette.card, 3));
      canvas.drawPath(shape, _fill(colour));
      canvas.drawPath(shape, _stroke(colour, .8));
      switch (kind) {
        case TacticalUnitSymbol.squad:
          _person(canvas, const Offset(7, 10.5), 1.6, JournalPalette.card);
          _person(canvas, const Offset(17, 10.5), 1.6, JournalPalette.card);
          _person(canvas, const Offset(12, 9), 2.1, JournalPalette.card);
        case TacticalUnitSymbol.enemy:
          _person(canvas, const Offset(12, 8.8), 2.2, JournalPalette.card);
        case TacticalUnitSymbol.wounded:
          _person(canvas, const Offset(10, 8.5), 1.9, JournalPalette.card);
          final cross = _stroke(JournalPalette.card, 1.8);
          canvas.drawLine(
            const Offset(15.5, 13.5),
            const Offset(15.5, 18.5),
            cross,
          );
          canvas.drawLine(const Offset(13, 16), const Offset(18, 16), cross);
        case TacticalUnitSymbol.armored:
          // A tracked vehicle distinguishes heavy units from human threats.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(6, 12, 12, 5),
              const Radius.circular(2),
            ),
            _fill(JournalPalette.card),
          );
          canvas.drawRect(
            const Rect.fromLTWH(8, 9, 8, 4),
            _fill(JournalPalette.card),
          );
          canvas.drawLine(
            const Offset(12, 9),
            const Offset(18, 7),
            _stroke(JournalPalette.card, 1.9),
          );
          for (final x in <double>[8, 12, 16]) {
            canvas.drawCircle(Offset(x, 15), .9, _fill(colour));
          }
      }
    });
  }

  /// Opaque unexplored paper, without a cross pattern suggesting known terrain.
  static void drawFog(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, _fill(JournalPalette.inset));
    _local(canvas, rect, () {
      final grain = _fill(JournalPalette.brassDark.withValues(alpha: .12));
      canvas.drawCircle(const Offset(7, 7), .45, grain);
      canvas.drawCircle(const Offset(17, 16), .35, grain);
      canvas.drawLine(
        const Offset(15, 5),
        const Offset(17, 5),
        _stroke(JournalPalette.brassDark.withValues(alpha: .08), .5),
      );
    });
  }

  static void drawFire(Canvas canvas, Rect rect) {
    _local(canvas, rect, () {
      _flame(
        canvas,
        const Rect.fromLTWH(4, 2.5, 16, 19),
        JournalPalette.danger,
      );
      _flame(
        canvas,
        const Rect.fromLTWH(9, 12, 7, 8.5),
        JournalPalette.brassLight,
      );
    });
  }

  /// A closed supply crate, also used while the loot atlas is loading.
  static void drawLoot(Canvas canvas, Rect rect) {
    _local(canvas, rect, () {
      const box = Rect.fromLTWH(4, 6, 16, 13);
      canvas.drawRect(box, _fill(JournalPalette.brassLight));
      canvas.drawRect(box, _stroke(JournalPalette.brassDark, 1.6));
      canvas.drawLine(
        const Offset(4, 10),
        const Offset(20, 10),
        _stroke(JournalPalette.brassDark, 1.4),
      );
      canvas.drawLine(
        const Offset(8, 6),
        const Offset(8, 19),
        _stroke(JournalPalette.brassDark, 1.4),
      );
      canvas.drawLine(
        const Offset(16, 6),
        const Offset(16, 19),
        _stroke(JournalPalette.brassDark, 1.4),
      );
    });
  }

  /// A ring-shaped defensive trap; state and warnings remain separate layers.
  static void drawTrap(Canvas canvas, Rect rect) {
    _local(canvas, rect, () {
      final ink = _stroke(JournalPalette.brassDark, 1.6);
      canvas.drawOval(const Rect.fromLTWH(4, 5, 15, 14), ink);
      for (final angle in <double>[0, .75, 1.5, 2.25, 3, 3.75, 4.5, 5.25]) {
        final edge = Offset(
          11.5 + math.cos(angle) * 7.2,
          12 + math.sin(angle) * 6.7,
        );
        final tooth = Offset(
          11.5 + math.cos(angle) * 5.2,
          12 + math.sin(angle) * 4.8,
        );
        canvas.drawLine(edge, tooth, ink);
      }
      canvas.drawLine(const Offset(15, 17), const Offset(21, 20), ink);
      canvas.drawCircle(
        const Offset(21, 20),
        1.3,
        _fill(JournalPalette.brassDark),
      );
    });
  }

  /// Small warning mark shared by the map and key, separate from the trap art.
  static void drawTrapMarker(Canvas canvas, Rect rect) {
    final side = rect.width * .42;
    final badge = Rect.fromLTWH(rect.right - side, rect.top, side, side);
    canvas.drawRect(badge, _fill(JournalPalette.card));
    _local(canvas, badge, () {
      final shape = Path()
        ..moveTo(12, 2)
        ..lineTo(23, 22)
        ..lineTo(1, 22)
        ..close();
      canvas.drawPath(shape, _fill(JournalPalette.brassDark));
      canvas.drawLine(
        const Offset(12, 8),
        const Offset(12, 14),
        _stroke(JournalPalette.card, 2.5),
      );
      canvas.drawCircle(const Offset(12, 18), 1.3, _fill(JournalPalette.card));
    });
  }

  static void _flame(Canvas canvas, Rect rect, Color colour) {
    final flame = Path()
      ..moveTo(rect.left + rect.width * .48, rect.top)
      ..cubicTo(
        rect.right,
        rect.top + rect.height * .36,
        rect.left + rect.width * .65,
        rect.top + rect.height * .4,
        rect.right,
        rect.top + rect.height * .33,
      )
      ..cubicTo(
        rect.right + rect.width * .1,
        rect.bottom,
        rect.left + rect.width * .7,
        rect.bottom,
        rect.left + rect.width * .5,
        rect.bottom,
      )
      ..cubicTo(
        rect.left,
        rect.bottom,
        rect.left - rect.width * .08,
        rect.top + rect.height * .65,
        rect.left + rect.width * .23,
        rect.top + rect.height * .38,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * .22,
        rect.top + rect.height * .7,
        rect.left + rect.width * .43,
        rect.top + rect.height * .57,
      )
      ..quadraticBezierTo(
        rect.left + rect.width * .65,
        rect.top + rect.height * .38,
        rect.left + rect.width * .48,
        rect.top,
      )
      ..close();
    canvas.drawPath(flame, _fill(colour));
  }

  static void _person(Canvas canvas, Offset head, double radius, Color colour) {
    canvas.drawCircle(head, radius, _fill(colour));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          head.dx - radius * 1.35,
          head.dy + radius + .8,
          radius * 2.7,
          radius * 2.05,
        ),
        Radius.circular(radius),
      ),
      _fill(colour),
    );
  }

  static void _badge(Canvas canvas, Offset center, Color colour) {
    canvas.drawCircle(center, 5.2, _fill(JournalPalette.card));
    canvas.drawCircle(center, 4.3, _fill(colour));
  }

  static void _local(Canvas canvas, Rect rect, VoidCallback draw) {
    if (rect.isEmpty) return;
    final side = rect.shortestSide;
    canvas.save();
    canvas.translate(rect.center.dx - side / 2, rect.center.dy - side / 2);
    canvas.scale(side / 24);
    draw();
    canvas.restore();
  }

  static Paint _fill(Color colour) => Paint()..color = colour;

  static Paint _stroke(Color colour, double width) => Paint()
    ..color = colour
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
}
