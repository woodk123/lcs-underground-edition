import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/injury_status.dart';

const injuryAnatomyAsset = 'assets/modern/injury_anatomy_front_v1.webp';
const double injuryAnatomyAspectRatio = 979 / 1607;

/// Physical locations on the full front-view plate, before callout layout.
///
/// Sides belong to the character: their right is the viewer's left. These
/// anchors describe the illustration and do not define damage or game rules.
const injuryOrganAnchors = <String, Offset>{
  'right-eye': Offset(457 / 979, 146 / 1607),
  'left-eye': Offset(521 / 979, 146 / 1607),
  'nose': Offset(489 / 979, 177 / 1607),
  'tongue': Offset(490 / 979, 207 / 1607),
  'teeth': Offset(490 / 979, 200 / 1607),
  'neck': Offset(490 / 979, 259 / 1607),
  'upper-spine': Offset(490 / 979, 365 / 1607),
  'right-lung': Offset(430 / 979, 420 / 1607),
  'left-lung': Offset(550 / 979, 420 / 1607),
  'heart': Offset(519 / 979, 459 / 1607),
  'ribs': Offset(582 / 979, 479 / 1607),
  'liver': Offset(430 / 979, 567 / 1607),
  'stomach': Offset(541 / 979, 574 / 1607),
  'right-kidney': Offset(430 / 979, 619 / 1607),
  'left-kidney': Offset(550 / 979, 619 / 1607),
  'spleen': Offset(591 / 979, 554 / 1607),
  'lower-spine': Offset(490 / 979, 685 / 1607),
};

/// Traces the selected anatomy plate for both colour overlays and hit testing.
///
/// Coordinates are authored in the original 979 by 1607 image so its transparent
/// margins remain aligned at every display size. Narrow gaps between adjacent
/// regions keep hit targets independent. Hands and feet belong to their limbs.
Path injuryRegionPath(InjuryRegion region, Size size) {
  final trace = _PlateTrace(
    size,
    mirrored: region == InjuryRegion.leftArm || region == InjuryRegion.leftLeg,
  );
  switch (region) {
    case InjuryRegion.head:
      trace
        ..move(490, 49)
        ..curve(452, 49, 426, 77, 426, 112)
        ..curve(426, 125, 428, 133, 424, 140)
        ..curve(419, 135, 414, 144, 416, 163)
        ..curve(418, 179, 427, 190, 433, 187)
        ..curve(438, 202, 442, 215, 445, 231)
        ..line(445, 248)
        ..curve(444, 261, 438, 271, 425, 277)
        ..curve(448, 280, 471, 281, 490, 281)
        ..curve(509, 281, 532, 280, 555, 277)
        ..curve(542, 271, 536, 261, 535, 248)
        ..line(535, 231)
        ..curve(538, 215, 542, 202, 547, 187)
        ..curve(554, 190, 563, 179, 564, 163)
        ..curve(566, 144, 561, 135, 556, 140)
        ..curve(552, 133, 554, 125, 554, 112)
        ..curve(554, 77, 527, 49, 490, 49)
        ..close();
    case InjuryRegion.torso:
      trace
        ..move(425, 285)
        ..curve(400, 291, 375, 299, 357, 309)
        ..line(363, 330)
        ..curve(370, 365, 366, 403, 363, 444)
        ..curve(362, 480, 361, 509, 371, 543)
        ..curve(378, 561, 379, 575, 375, 592)
        ..curve(369, 617, 366, 643, 362, 661)
        ..curve(354, 696, 344, 731, 340, 755)
        ..curve(337, 776, 335, 792, 336, 804)
        ..curve(371, 803, 421, 812, 481, 813)
        ..line(498, 813)
        ..curve(558, 812, 607, 803, 643, 804)
        ..curve(644, 781, 641, 759, 636, 740)
        ..curve(629, 712, 621, 684, 617, 662)
        ..curve(613, 642, 610, 617, 604, 592)
        ..curve(600, 575, 603, 561, 609, 543)
        ..curve(619, 509, 618, 480, 617, 444)
        ..curve(614, 403, 610, 365, 617, 330)
        ..line(623, 309)
        ..curve(605, 299, 580, 291, 555, 285)
        ..close();
    case InjuryRegion.rightArm:
    case InjuryRegion.leftArm:
      trace
        ..move(343, 317)
        ..curve(321, 312, 300, 328, 291, 351)
        ..curve(281, 376, 282, 414, 281, 448)
        ..curve(280, 478, 272, 509, 264, 540)
        ..curve(260, 556, 254, 567, 249, 578)
        ..curve(237, 599, 230, 619, 225, 641)
        ..curve(219, 673, 214, 706, 205, 732)
        ..line(198, 750)
        ..curve(192, 764, 180, 775, 169, 790)
        ..curve(159, 800, 145, 817, 140, 829)
        ..curve(138, 837, 142, 841, 149, 839)
        ..line(171, 821)
        ..curve(171, 840, 165, 864, 161, 883)
        ..curve(158, 901, 156, 916, 163, 917)
        ..curve(166, 918, 170, 906, 175, 894)
        ..curve(172, 910, 172, 921, 178, 922)
        ..curve(185, 923, 192, 897, 194, 887)
        ..curve(190, 906, 190, 914, 197, 913)
        ..curve(204, 912, 211, 886, 216, 870)
        ..curve(217, 883, 223, 876, 227, 862)
        ..line(241, 815)
        ..curve(244, 801, 243, 787, 243, 775)
        ..curve(247, 751, 262, 726, 275, 706)
        ..curve(288, 686, 309, 662, 317, 639)
        ..curve(328, 614, 332, 592, 330, 574)
        ..curve(332, 551, 345, 528, 350, 500)
        ..curve(355, 477, 359, 448, 357, 419)
        ..line(357, 370)
        ..curve(355, 345, 352, 326, 343, 317)
        ..close();
    case InjuryRegion.rightLeg:
    case InjuryRegion.leftLeg:
      trace
        ..move(337, 817)
        ..curve(355, 812, 449, 818, 482, 825)
        ..curve(482, 868, 481, 900, 470, 948)
        ..curve(466, 969, 474, 996, 470, 1020)
        ..curve(468, 1048, 458, 1080, 459, 1101)
        ..curve(458, 1133, 463, 1178, 465, 1199)
        ..curve(467, 1233, 453, 1272, 445, 1300)
        ..curve(439, 1321, 440, 1348, 442, 1367)
        ..curve(447, 1384, 451, 1398, 449, 1420)
        ..line(449, 1450)
        ..curve(449, 1468, 458, 1495, 452, 1510)
        ..curve(447, 1524, 421, 1527, 400, 1520)
        ..curve(388, 1520, 364, 1515, 365, 1500)
        ..curve(364, 1485, 380, 1457, 383, 1445)
        ..curve(390, 1427, 382, 1407, 386, 1390)
        ..curve(394, 1364, 385, 1347, 382, 1326)
        ..curve(376, 1294, 360, 1252, 354, 1204)
        ..curve(350, 1176, 354, 1150, 364, 1120)
        ..curve(373, 1097, 370, 1070, 371, 1049)
        ..curve(374, 1028, 369, 1001, 363, 980)
        ..curve(354, 952, 342, 910, 337, 875)
        ..curve(333, 855, 333, 833, 337, 817)
        ..close();
  }
  return trace.path;
}

class _PlateTrace {
  _PlateTrace(this.size, {this.mirrored = false});

  final Size size;
  final bool mirrored;
  final Path path = Path();

  double _x(double value) =>
      (mirrored ? 979 - value : value) / 979 * size.width;
  double _y(double value) => value / 1607 * size.height;

  void move(double x, double y) => path.moveTo(_x(x), _y(y));
  void line(double x, double y) => path.lineTo(_x(x), _y(y));
  void curve(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(_x(x1), _y(y1), _x(x2), _y(y2), _x(x3), _y(y3));
  void close() => path.close();
}
