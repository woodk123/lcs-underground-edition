import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/dice.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/modern/age_help.dart';

/// Gameplay uses shared by current-stat help and background-choice previews.
String skillUses(Skill skill) => switch (skill) {
  Skill.art => 'selling artwork, graffiti and creative activism.',
  Skill.business =>
    'selling art or clothing, other fundraising, economic debates and newspaper articles.',
  Skill.computers =>
    'hacking, credit-card fraud and accessing computer systems during operations.',
  Skill.disguise =>
    'passing as someone who belongs at a site; appropriate clothing also matters.',
  Skill.dodge => 'avoiding incoming attacks during combat.',
  Skill.driving => 'handling vehicles during car chases and escapes.',
  Skill.firstAid =>
    'treating wounded crew and stopping bleeding during operations.',
  Skill.heavyWeapons =>
    'attacking with weapons that require Heavy Weapons, including machine guns and flamethrowers.',
  Skill.law =>
    'courtroom defense, legal arguments, recruitment discussions and newspaper articles.',
  Skill.martialArts => 'unarmed fighting and attacks with melee weapons.',
  Skill.music =>
    'playing live music to raise funds and spread the movement’s message.',
  Skill.persuasion =>
    'recruiting people, collecting donations, political discussions and courtroom arguments.',
  Skill.firearms => 'attacking with guns that require Firearms.',
  Skill.psychology =>
    'interrogation and efforts to influence or convert prisoners.',
  Skill.religion =>
    'discussions about faith, recruitment, influencing prisoners and newspaper articles.',
  Skill.science =>
    'scientific arguments, recruitment, influencing prisoners and newspaper articles.',
  Skill.security =>
    'opening locks, bypassing security systems and stealing cars.',
  Skill.stealth => 'moving through sites without being noticed.',
  Skill.streetSmarts =>
    'finding recruits or cars, fundraising and avoiding police attention during daily activities.',
  Skill.tailoring =>
    'making or repairing clothing, creating flags and selling clothing to raise funds.',
  Skill.teaching =>
    'helping other crew learn skills the teacher already knows.',
  Skill.throwing => 'attacks with thrown weapons, including Molotov cocktails.',
  Skill.writing => 'producing articles for the movement’s newspaper.',
  Skill.seduction =>
    'romantic approaches, relationships and related fundraising.',
};

/// Read-only explanations of the retained game's actual skill uses.
String skillHelp(Skill skill, {Creature? actor}) {
  final uses = skillUses(skill);
  final attribute = skill.attribute.name;
  final capLabel = attribute[0].toUpperCase() + attribute.substring(1);
  final lines = <String>[
    skill.description,
    'Useful for: $uses',
    'Ordinary checks: 2d6 (two six-sided dice) + skill, passing at the task difficulty. Activities can use different formulas.',
  ];
  if (actor == null) {
    lines.add(
      'Training cap = current $capLabel. Level-up XP = 100 + 10 × current skill level.',
    );
  } else {
    final level = actor.skill(skill);
    int modify(int roll) {
      if (skill == Skill.stealth) return actor.stealthMod(roll);
      if (skill == Skill.dodge) {
        return roll - (actor.clothing.armor?.dodgePenalty ?? 0);
      }
      return roll;
    }

    final lower = modify(2 + level);
    final upper = modify(12 + level);
    final fixed = modify(Dice.r2d6.take10() + level);
    if (const {
      Skill.firearms,
      Skill.heavyWeapons,
      Skill.martialArts,
      Skill.throwing,
    }.contains(skill)) {
      lines.add(
        'Physical attack baseline: d20 + $level = ${1 + level}–${20 + level}. Equipment, wounds, position and the opponent modify combat results.',
      );
    } else {
      lines.add(
        'Current default total: $lower–$upper. Fixed-roll total: $fixed (7 + skill, including clothing modifiers).',
      );
    }
    if (skill == Skill.dodge) {
      lines.add(
        'Combat defense baseline: ranged = Dodge + 10 = ${level + 10}; melee = Dodge + Agility = ${level + actor.attribute(Attribute.agility)}. Situational modifiers apply.',
      );
    }
    final cap = actor.skillCap(skill);
    lines.add(
      'Age ${actor.age}: ${ageAttributeEffect(actor, skill.attribute)}. Already included in the attribute used for this training cap; age does not directly add to the current skill level.',
    );
    final needed = skillXpNeeded(level);
    lines.add(
      'Training cap: $capLabel $cap. XP: ${actor.skillXP(skill)}/$needed (100 + 10 × $level). Levels update during daily processing.',
    );
    if (level >= cap) {
      lines.add('At the current attribute cap: further training is paused.');
    }
    if (actor.blood < actor.maxBlood && actor.maxBlood > 0) {
      final bloodPenalty = (actor.maxBlood - actor.blood) * 2 ~/ actor.maxBlood;
      lines.add(
        'Checks that enable injury penalties also subtract $bloodPenalty for blood loss and ${actor.body.combatRollModifier} for injuries.',
      );
    }
    if (!actor.alive) {
      lines.add('A deceased character cannot pass a skill check.');
    }
  }
  return lines.join('\n\n');
}

/// A passive hover/long-press hint. It never consumes game input or opens a modal.
class SkillTooltip extends StatelessWidget {
  const SkillTooltip({
    super.key,
    required this.skill,
    required this.child,
    this.actor,
  });

  final Skill skill;
  final Creature? actor;
  final Widget child;

  @override
  Widget build(BuildContext context) => MechanicsTooltip(
    message: skillHelp(skill, actor: actor),
    child: child,
  );
}

/// Long mechanics hints fit the window and keep underlying controls clickable.
class MechanicsTooltip extends StatelessWidget {
  const MechanicsTooltip({
    super.key,
    required this.message,
    required this.child,
    this.maxWidth = 420,
    this.excludeFromSemantics = false,
  });

  final String message;
  final Widget child;
  final double maxWidth;
  final bool excludeFromSemantics;

  @override
  Widget build(BuildContext context) {
    final readingScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final availableWidth = math
        .max(1, MediaQuery.sizeOf(context).width - 24)
        .toDouble();
    return Tooltip(
      excludeFromSemantics: excludeFromSemantics,
      message: message,
      waitDuration: const Duration(milliseconds: 300),
      exitDuration: const Duration(milliseconds: 100),
      showDuration: const Duration(seconds: 8),
      constraints: BoxConstraints(
        maxWidth: math.min(maxWidth * readingScale, availableWidth),
      ),
      padding: const EdgeInsets.all(12),
      ignorePointer: true,
      positionDelegate: _fitTooltip,
      child: child,
    );
  }

  static Offset _fitTooltip(TooltipPositionContext context) {
    const margin = 12.0;
    final child = context.tooltipSize;
    final window = context.overlaySize;
    final below = context.target.dy + context.verticalOffset;
    final above = context.target.dy - context.verticalOffset - child.height;
    final fitsAbove = above >= margin;
    final fitsBelow = below + child.height <= window.height - margin;
    final preferBelow = fitsAbove == fitsBelow
        ? context.preferBelow
        : fitsBelow;
    return Offset(
      (context.target.dx - child.width / 2)
          .clamp(margin, math.max(margin, window.width - child.width - margin))
          .toDouble(),
      (preferBelow ? below : above)
          .clamp(
            margin,
            math.max(margin, window.height - child.height - margin),
          )
          .toDouble(),
    );
  }
}
