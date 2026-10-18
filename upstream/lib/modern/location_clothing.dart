import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/sitemode/stealth.dart';

typedef LocationOutfit = ({ClothingType type, DisguiseQuality quality});

/// Catalogue clothing in its original armor, clean, undamaged and quality 1.
/// Uses the live clothing rules with an explicit destination and area; never
/// borrows the current operation's map, equips a person or consumes game RNG.
List<LocationOutfit> locationClothing(Site site, {required bool restricted}) {
  final outfits = <LocationOutfit>[
    for (final type in clothingTypes.values)
      if (type.idName != 'CLOTHING_NONE' &&
          (type.makeDifficulty >= 0 || type.fenceValue > 0))
        (
          type: type,
          quality: clothingDisguiseQuality(
            Clothing(type.idName),
            site: site,
            restricted: restricted,
            deathSquads: game.deathSquadsActive,
            dystopianPrison: game.nineteenEightyFour,
          ),
        ),
  ];
  const familiar = [
    'CLOTHING_CLOTHES',
    'CLOTHING_WORKCLOTHES',
    'CLOTHING_CHEAPSUIT',
    'CLOTHING_CHEAPDRESS',
    'CLOTHING_LABCOAT',
    'CLOTHING_SCRUBS',
    'CLOTHING_OVERALLS',
    'CLOTHING_SECURITYUNIFORM',
  ];
  int priority(ClothingType type) {
    final index = familiar.indexOf(type.idName);
    return index < 0 ? familiar.length : index;
  }

  outfits.sort((a, b) {
    final order = priority(a.type).compareTo(priority(b.type));
    return order != 0 ? order : a.type.name.compareTo(b.type.name);
  });
  return outfits;
}

String clothingFitSummary(List<LocationOutfit> outfits) {
  final normal = outfits
      .where((outfit) => outfit.quality == DisguiseQuality.inconspicuous)
      .map((outfit) => outfit.type.name)
      .toSet();
  if (normal.isEmpty) return 'No listed outfit blends in here.';
  return 'Blends in: ${normal.take(4).join(' · ')}'
      '${normal.length > 4 ? ' · +${normal.length - 4} more' : ''}';
}

String clothingFitLabel(DisguiseQuality quality) => switch (quality) {
  DisguiseQuality.inconspicuous => 'Blends in · no clothing penalty',
  DisguiseQuality.authorityFigure => 'Authority role · −2 to Disguise',
  DisguiseQuality.unusual => 'Unusual · −4 to Disguise',
  DisguiseQuality.disturbing => 'Disturbing · −8 to Disguise',
  DisguiseQuality.trespassing => 'Trespassing · −100 to Disguise',
  DisguiseQuality.alarming => 'Alarming · −100 to Disguise',
  DisguiseQuality.hidden => 'Hidden · no clothing penalty',
};

const clothingDisguiseLimits =
    'These are clothing ratings, not success chances or permission to enter. '
    'Guards can still test Disguise; each squad member’s outfit and weapons '
    'matter. Poor-quality or damaged clothing can worsen the rating, and '
    'added visible armor can make an outfit alarming. Blood and less-than-best '
    'condition can get you turned away at checkpoints or by bouncers. '
    'Suspicious weapons and metal detectors have separate checks. '
    'Security, site control, sieges and current laws can change which outfits fit.';
