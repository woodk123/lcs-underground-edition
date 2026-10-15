import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// Read-only explanations; never roll dice while displaying a preview.
String attributeHelp(Attribute attribute, {Creature? actor}) {
  final description = switch (attribute) {
    Attribute.strength =>
      'Physical power. Helps force doors, affects melee damage and contributes to health.',
    Attribute.agility =>
      'Speed and coordination. Helps escape on foot and adds to Dodge for melee defense.',
    Attribute.intelligence =>
      'Reasoning and knowledge. Helps with technical tasks and recruitment discussions.',
    Attribute.charisma =>
      'Personal presence. Supports social skills and contributes to relationship capacity.',
    Attribute.wisdom =>
      'Conservative conviction. Helps resist liberal persuasion and contributes to conservative characters’ health.',
    Attribute.heart =>
      'Compassion and liberal conviction. Helps resist conservative persuasion, contributes to liberal characters’ health and relationship capacity.',
  };
  final skills = Skill.values
      .where((skill) => skill.attribute == attribute)
      .map((skill) => skill.displayName)
      .join(', ');
  final lines = <String>[
    description,
    if (skills.isNotEmpty)
      'Sets the training cap for: $skills. Skills can train up to the current effective attribute value.'
    else
      'Does not set a skill training cap.',
    'Ordinary checks: 2d6 (two six-sided dice) + attribute − 5, passing at the task difficulty. Some tasks use different formulas.',
  ];
  if (actor != null) {
    final value = actor.attribute(attribute);
    final modifier = value - 5;
    lines.add(
      'Current effective value: $value. Check modifier: ${modifier >= 0 ? '+' : ''}$modifier. Default total: ${2 + modifier}–${12 + modifier}. Fixed-roll total: ${7 + modifier}.',
    );
    if (!actor.alive) {
      lines.add('A deceased character cannot pass an attribute check.');
    }
  }
  return lines.join('\n\n');
}

class AttributeTooltip extends StatelessWidget {
  const AttributeTooltip({
    super.key,
    required this.attribute,
    required this.child,
    this.actor,
  });

  final Attribute attribute;
  final Creature? actor;
  final Widget child;

  @override
  Widget build(BuildContext context) => MechanicsTooltip(
    message: attributeHelp(attribute, actor: actor),
    child: child,
  );
}
