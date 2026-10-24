import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

/// Called once per landed combat hit, even when armour absorbs the injury.
/// Misses never reach this rule. Uncovered targets consume no extra RNG.
bool exposeFaceFromHit(
  Creature target, {
  required bool ranged,
  int Function(int)? roll,
}) {
  if ((!gameState.siteIdentities.active && mode != GameMode.site) ||
      !target.human ||
      !target.clothing.concealsFace) {
    return false;
  }
  if ((roll ?? lcsRandom)(100) >= (ranged ? 10 : 25)) return false;
  target.clothing.damaged = true;
  target.clothing.faceCoveringDamaged = true;
  gameState.siteIdentities.identify(target);
  return true;
}
