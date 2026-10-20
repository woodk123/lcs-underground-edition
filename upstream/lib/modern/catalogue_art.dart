import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'catalogue_art_supplement.dart';

/// A painting of a catalogue type, never an item's condition, ammunition count,
/// installed armour or a vehicle's generated colour/year. Live text owns those.
@immutable
class CatalogueArtEntry {
  const CatalogueArtEntry(this.asset, this.source);

  final String asset;
  final Rect source;
}

const _weapons = 'assets/modern/journal_equipment_weapons_v1.webp';
const _gear = 'assets/modern/journal_equipment_gear_v1.webp';
const _vehicles = 'assets/modern/journal_vehicles_v1.webp';

// Full-object rectangles inspected against the transparent masters. These are
// deliberately independent of equal atlas cells, so no object is clipped.
const _weaponRects = <Rect>[
  Rect.fromLTWH(61, 75, 275, 162),
  Rect.fromLTWH(460, 70, 241, 165),
  Rect.fromLTWH(816, 68, 276, 165),
  Rect.fromLTWH(1169, 106, 323, 98),
  Rect.fromLTWH(25, 349, 341, 108),
  Rect.fromLTWH(415, 328, 342, 140),
  Rect.fromLTWH(787, 327, 340, 143),
  Rect.fromLTWH(1194, 320, 295, 161),
  Rect.fromLTWH(28, 557, 338, 148),
  Rect.fromLTWH(410, 563, 347, 136),
  Rect.fromLTWH(806, 585, 315, 93),
  Rect.fromLTWH(1189, 567, 313, 99),
  Rect.fromLTWH(41, 793, 314, 129),
  Rect.fromLTWH(418, 776, 325, 159),
  Rect.fromLTWH(827, 765, 284, 191),
  Rect.fromLTWH(1200, 771, 276, 177),
];

const _gearRects = <Rect>[
  Rect.fromLTWH(91, 60, 266, 190),
  Rect.fromLTWH(461, 58, 275, 193),
  Rect.fromLTWH(860, 48, 201, 213),
  Rect.fromLTWH(1206, 57, 269, 198),
  Rect.fromLTWH(88, 289, 268, 204),
  Rect.fromLTWH(459, 291, 291, 209),
  Rect.fromLTWH(867, 277, 183, 235),
  Rect.fromLTWH(1243, 285, 201, 216),
  Rect.fromLTWH(98, 520, 219, 225),
  Rect.fromLTWH(458, 524, 250, 212),
  Rect.fromLTWH(825, 531, 294, 214),
  Rect.fromLTWH(1302, 530, 84, 209),
  Rect.fromLTWH(96, 767, 252, 207),
  Rect.fromLTWH(514, 763, 122, 207),
  Rect.fromLTWH(818, 777, 269, 189),
  Rect.fromLTWH(1208, 770, 268, 201),
];

const _vehicleRects = <Rect>[
  Rect.fromLTWH(69, 47, 391, 205),
  Rect.fromLTWH(551, 40, 438, 213),
  Rect.fromLTWH(1080, 38, 393, 216),
  Rect.fromLTWH(48, 296, 441, 204),
  Rect.fromLTWH(538, 286, 462, 212),
  Rect.fromLTWH(1062, 311, 436, 186),
  Rect.fromLTWH(48, 542, 435, 185),
  Rect.fromLTWH(537, 525, 463, 198),
  Rect.fromLTWH(1063, 522, 433, 217),
  Rect.fromLTWH(47, 765, 436, 207),
  Rect.fromLTWH(550, 759, 439, 220),
];

const _weaponIds = <String>[
  'WEAPON_22_REVOLVER',
  'WEAPON_9MM_HANDGUN',
  'WEAPON_DESERT_EAGLE',
  'WEAPON_22_RIFLE',
  'WEAPON_PUMP_SHOTGUN',
  'WEAPON_AR15',
  'WEAPON_AK102',
  'WEAPON_MP5',
  'WEAPON_TOMMYGUN',
  'WEAPON_M250_MACHINEGUN',
  'WEAPON_COMBATKNIFE',
  'WEAPON_BASEBALLBAT',
  'WEAPON_CROWBAR',
  'WEAPON_AXE',
  'AMMO_9MM',
  'AMMO_BUCKSHOT',
];
const _gearIds = <String>[
  'CLOTHING_CLOTHES',
  'CLOTHING_CHEAPSUIT',
  'CLOTHING_LABCOAT',
  'CLOTHING_POLICEUNIFORM',
  'CLOTHING_CAMOSUIT',
  'CLOTHING_SWATARMOR',
  'CLOTHING_PRISONER',
  'CLOTHING_OVERALLS',
  'CLOTHING_BLACKROBE',
  'CLOTHING_LEATHER',
  'WEAPON_GUITAR',
  'WEAPON_SPRAYCAN',
  'LOOT_COMPUTER',
  'LOOT_MICROPHONE',
  'LOOT_FINECLOTH',
  'LOOT_SECRETDOCUMENTS',
];
const _vehicleIds = <String>[
  'BUG',
  'HMMWV',
  'JEEP',
  'PICKUP',
  'POLICECAR',
  'AGENTCAR',
  'SPORTSCAR',
  'STATIONWAGON',
  'SUV',
  'TAXICAB',
  'VAN',
];

/// Exact stable type IDs only: absence sentinels and body attacks keep text.
CatalogueArtEntry? equipmentArtwork(String? typeId) {
  var index = _weaponIds.indexOf(typeId ?? '');
  if (index >= 0) return CatalogueArtEntry(_weapons, _weaponRects[index]);
  index = _gearIds.indexOf(typeId ?? '');
  return index < 0
      ? _supplementalEquipment[typeId]
      : CatalogueArtEntry(_gear, _gearRects[index]);
}

CatalogueArtEntry? vehicleArtwork(String? typeId) {
  final index = _vehicleIds.indexOf(typeId ?? '');
  return index < 0 ? null : CatalogueArtEntry(_vehicles, _vehicleRects[index]);
}

final _atlases = <String, Future<ui.Image?>>{};
Future<ui.Image?> _loadAtlas(String asset) =>
    _atlases.putIfAbsent(asset, () async {
      try {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } catch (_) {
        return null;
      }
    });

/// Decoration within an existing labelled control: no new input or focus stop.
class CatalogueIllustration extends StatelessWidget {
  const CatalogueIllustration({
    super.key,
    required this.art,
    this.width = 56,
    this.height = 40,
  });

  final CatalogueArtEntry art;
  final double width, height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox(
        width: width,
        height: height,
        child: FutureBuilder<ui.Image?>(
          future: _loadAtlas(art.asset),
          builder: (context, snapshot) => snapshot.data == null
              ? const SizedBox.shrink()
              : CustomPaint(
                  painter: _CataloguePainter(snapshot.data!, art.source),
                ),
        ),
      ),
    ),
  );
}

class _CataloguePainter extends CustomPainter {
  const _CataloguePainter(this.image, this.source);
  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = applyBoxFit(BoxFit.contain, source.size, size);
    canvas.drawImageRect(
      image,
      source,
      Alignment.center.inscribe(fit.destination, Offset.zero & size),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _CataloguePainter oldDelegate) =>
      image != oldDelegate.image || source != oldDelegate.source;
}
