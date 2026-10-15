import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

const journalOrderIconAsset = 'assets/modern/journal_order_icons_v1.webp';
const journalBrownieIconAsset = 'assets/modern/journal_weed_brownies_v1.webp';
const journalExtraOrderIconAsset =
    'assets/modern/journal_order_icons_extra_v1.webp';

/// Cosmetic classification of exact existing activity types. No labels are
/// parsed and no campaign state, activity, input, or random stream is changed.
int? journalOrderIconIndex(ActivityType type) => switch (type) {
  ActivityType.donations => 0,
  ActivityType.sellArt => 1,
  ActivityType.makeClothing ||
  ActivityType.sellTshirts ||
  ActivityType.makeFlag => 2,
  ActivityType.sellMusic => 3,
  ActivityType.recruiting || ActivityType.sleeperRecruit => 4,
  ActivityType.study || ActivityType.takeClass => 5,
  ActivityType.teachLiberalArts ||
  ActivityType.teachFighting ||
  ActivityType.teachCovert => 6,
  ActivityType.clinic => 7,
  ActivityType.graffiti => 8,
  ActivityType.trouble ||
  ActivityType.sleeperLiberal ||
  ActivityType.sleeperConservative => 9,
  ActivityType.writeGuardian => 10,
  ActivityType.hacking => 11,
  ActivityType.stealCars => 12,
  ActivityType.interrogation => 13,
  ActivityType.bury => 14,
  ActivityType.none => 15,
  ActivityType.communityService => 16,
  ActivityType.sellDrugs => 17,
  ActivityType.prostitution => 18,
  ActivityType.ccfraud => 19,
  ActivityType.wheelchair => 20,
  ActivityType.streamGuardian => 21,
  ActivityType.sleeperSpy => 22,
  ActivityType.sleeperEmbezzle => 23,
  ActivityType.sleeperSteal => 24,
  ActivityType.sleeperJoinLcs => 25,
  ActivityType.augment => 26,
  _ => null,
};

/// Inspected full-symbol crops. The sheet is logically 4x4, but several painted
/// objects cross equal-cell boundaries, so fixed quarter cuts would clip them.
const journalOrderIconSourceRects = <Rect>[
  Rect.fromLTWH(20, 46, 280, 273),
  Rect.fromLTWH(317, 44, 299, 287),
  Rect.fromLTWH(647, 59, 293, 276),
  Rect.fromLTWH(968, 25, 265, 320),
  Rect.fromLTWH(10, 346, 313, 289),
  Rect.fromLTWH(318, 364, 326, 257),
  Rect.fromLTWH(652, 361, 291, 273),
  Rect.fromLTWH(944, 383, 299, 235),
  Rect.fromLTWH(40, 656, 271, 251),
  Rect.fromLTWH(349, 624, 293, 306),
  Rect.fromLTWH(639, 652, 308, 255),
  Rect.fromLTWH(946, 655, 284, 246),
  Rect.fromLTWH(15, 949, 329, 254),
  Rect.fromLTWH(336, 944, 281, 272),
  Rect.fromLTWH(647, 943, 285, 274),
  Rect.fromLTWH(949, 939, 278, 285),
];

const journalExtraOrderIconSourceRects = <Rect>[
  Rect.fromLTWH(10, 4, 355, 379),
  Rect.fromLTWH(385, 62, 297, 288),
  Rect.fromLTWH(740, 56, 334, 292),
  Rect.fromLTWH(1108, 66, 321, 305),
  Rect.fromLTWH(23, 379, 335, 324),
  Rect.fromLTWH(386, 390, 327, 283),
  Rect.fromLTWH(732, 398, 345, 298),
  Rect.fromLTWH(1083, 398, 355, 288),
  Rect.fromLTWH(22, 718, 326, 327),
  Rect.fromLTWH(376, 690, 336, 347),
  Rect.fromLTWH(725, 722, 347, 323),
  Rect.fromLTWH(1075, 704, 363, 354),
];

final _orderAtlases = <String, Future<ui.Image?>>{};
Future<ui.Image?> _loadAtlas([String asset = journalOrderIconAsset]) =>
    _orderAtlases.putIfAbsent(asset, () async {
      try {
        final bytes = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      } catch (_) {
        return null;
      }
    });

/// A decorative painting inside the caller's labelled live activity control.
/// Unsupported activities retain a truthful conventional symbol; they are not
/// disguised as another activity.
class JournalOrderIcon extends StatelessWidget {
  const JournalOrderIcon({super.key, required this.type, this.size = 40});

  final ActivityType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (type == ActivityType.sellDrugs) {
      return ExcludeSemantics(
        child: IgnorePointer(
          child: Image.asset(
            journalBrownieIconAsset,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) =>
                Icon(_fallback(type), size: size),
          ),
        ),
      );
    }
    if (type == ActivityType.visit) {
      return JournalIllustratedIcon(icon: JournalIcon.city, size: size);
    }
    final index = journalOrderIconIndex(type);
    final fallback = Icon(
      _fallback(type),
      size: size * .75,
      color: JournalPalette.brassDark,
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: size,
          child: index == null
              ? Center(child: fallback)
              : FutureBuilder<ui.Image?>(
                  future: _loadAtlas(
                    index >= 16
                        ? journalExtraOrderIconAsset
                        : journalOrderIconAsset,
                  ),
                  builder: (context, snapshot) => snapshot.data == null
                      ? Center(child: fallback)
                      : CustomPaint(
                          painter: _OrderIconPainter(snapshot.data!, index),
                        ),
                ),
        ),
      ),
    );
  }

  IconData _fallback(ActivityType type) => switch (type) {
    ActivityType.visit => Icons.map_outlined,
    ActivityType.communityService => Icons.volunteer_activism,
    ActivityType.sellDrugs => Icons.cookie_outlined,
    ActivityType.prostitution => Icons.people_outline,
    ActivityType.ccfraud => Icons.credit_card_off_outlined,
    ActivityType.wheelchair => Icons.accessible_forward,
    ActivityType.streamGuardian => Icons.videocam_outlined,
    ActivityType.sleeperSpy => Icons.visibility_outlined,
    ActivityType.sleeperEmbezzle => Icons.account_balance_wallet_outlined,
    ActivityType.sleeperSteal => Icons.inventory_2_outlined,
    ActivityType.sleeperJoinLcs => Icons.exit_to_app,
    ActivityType.augment => Icons.biotech,
    _ => Icons.assignment_outlined,
  };
}

class _OrderIconPainter extends CustomPainter {
  const _OrderIconPainter(this.image, this.index);
  final ui.Image image;
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final source = index < 16
        ? journalOrderIconSourceRects[index]
        : journalExtraOrderIconSourceRects[index - 16];
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    canvas.drawImageRect(
      image,
      source,
      Alignment.center.inscribe(fitted.destination, Offset.zero & size),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _OrderIconPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.index != index;
}

/// The field-guide painting shares the companion atlas without inventing an
/// activity type or adding an input/focus target.
class JournalLocationGuideIcon extends StatelessWidget {
  const JournalLocationGuideIcon({super.key, this.size = 24});
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox.square(
        dimension: size,
        child: FutureBuilder<ui.Image?>(
          future: _loadAtlas(journalExtraOrderIconAsset),
          builder: (context, snapshot) => snapshot.data == null
              ? const Icon(Icons.menu_book_outlined)
              : CustomPaint(painter: _OrderIconPainter(snapshot.data!, 27)),
        ),
      ),
    ),
  );
}
