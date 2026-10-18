import 'dart:convert';

import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

/// Projects only the source-authored stat changes. Never runs an option's
/// equipment/world callback or consumes campaign IDs, RNG, money or inventory.
class CreationBonusPreview {
  CreationBonusPreview(this.before, CreationBonuses bonuses) {
    final state = game.gameState;
    final nextCreature = state.nextCreatureId;
    try {
      after = withIsolatedRng(
        () => Creature.fromJson(
          jsonDecode(jsonEncode(before)) as Map<String, dynamic>,
        ),
      );
      bonuses.apply(after);
    } finally {
      state.nextCreatureId = nextCreature;
    }
  }

  final Creature before;
  late final Creature after;

  String skill(Skill skill) {
    final old = before.skill(skill), next = after.skill(skill);
    final combat = const {
      Skill.firearms,
      Skill.heavyWeapons,
      Skill.martialArts,
      Skill.throwing,
    }.contains(skill);
    final lines = [
      'Choosing this: ${skill.displayName} $old → $next.',
      'Helps with ${skillUses(skill)}',
      if (combat)
        'Attack baseline (d20 + skill): ${1 + old}–${20 + old} → ${1 + next}–${20 + next}, before equipment and injury modifiers.'
      else
        'Unmodified checks (2d6 + skill): ${2 + old}–${12 + old} → ${2 + next}–${12 + next}.',
      'Training cap (${_capitalized(skill.attribute.name)}): ${before.skillCap(skill)} → ${after.skillCap(skill)}.'
          '${next >= after.skillCap(skill) ? ' Further training waits for a higher attribute; this starting bonus is still granted.' : ''}',
    ];
    if (skill == Skill.computers) {
      lines.add(
        old == 0 && next > 0
            ? 'Meets the skill requirement for hacking and credit-card fraud. Both still require a Hacker Den.'
            : 'Hacking and credit-card fraud still require a Hacker Den. Higher Computers also improves fraud rolls.',
      );
      lines.add(
        'Solo hacking before trace risk: any success ${_chance(old, 13)} → ${_chance(next, 13)}; '
        'major hack ${_chance(old, 15)} → ${_chance(next, 15)}. Extra hackers can improve these odds.',
      );
    }
    return lines.join('\n\n');
  }

  String attribute(Attribute attribute) {
    final old = before.attribute(attribute), next = after.attribute(attribute);
    final caps = <String, List<String>>{};
    for (final skill in Skill.values.where(
      (skill) => skill.attribute == attribute,
    )) {
      final change = '${before.skillCap(skill)} → ${after.skillCap(skill)}';
      caps.putIfAbsent(change, () => []).add(skill.displayName);
    }
    return [
      'Choosing this: ${_capitalized(attribute.name)} $old → $next effective.',
      'Base score: ${before.rawAttributes[attribute]} → ${after.rawAttributes[attribute]}. Age, blood and Juice affect the effective score.',
      'Age ${after.age}: ${ageAttributeEffect(after, attribute)}. Already included in these effective values.',
      attributeDescription(attribute),
      for (final cap in caps.entries)
        'Training caps ${cap.key}: ${cap.value.join(', ')}.',
      'Unmodified checks (2d6 + attribute − 5): ${old - 3}–${old + 7} → ${next - 3}–${next + 7}.',
    ].join('\n\n');
  }

  static String _chance(int skill, int threshold) {
    if (skill <= 0) return '0%';
    var successes = 0;
    for (var first = 1; first <= 6; first++) {
      for (var second = 1; second <= 6; second++) {
        if (first + second + skill >= threshold) successes++;
      }
    }
    return '${(100 * successes / 36).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}%';
  }

  static String _capitalized(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)}';
}
