import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/aging.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

String _name(Attribute attribute) =>
    attribute.name[0].toUpperCase() + attribute.name.substring(1);

String _signed(int value) => value > 0 ? '+$value' : '$value';

/// Mirrors the body's age step, before injuries, the minimum of 1, Juice and
/// blood loss. In particular, young children's Strength is halved, not -3.
String ageAttributeEffect(Creature person, Attribute attribute) {
  if (person.body is! HumanoidBody) return 'No age modifier';
  if (attribute == Attribute.strength && person.age < childAge) {
    return 'Strength ×½ (rounded)';
  }
  final modifier = ageModifierForAttribute(attribute, person.age);
  return modifier == 0
      ? '${_name(attribute)} unchanged'
      : '${_name(attribute)} ${_signed(modifier)}';
}

String ageAttributeSummary(Creature person) {
  if (person.body is! HumanoidBody) {
    return 'No age attribute modifiers for this body.';
  }
  return _modifiersAtAge(person.age);
}

String _modifiersAtAge(int age) {
  final effects = <String>[
    for (final attribute in Attribute.values)
      if (attribute == Attribute.strength && age < childAge)
        'Strength ×½ (rounded)'
      else if (ageModifierForAttribute(attribute, age) case final value
          when value != 0)
        '${_name(attribute)} ${_signed(value)}',
  ];
  return effects.isEmpty ? 'No age attribute modifiers.' : effects.join(' · ');
}

/// Generation ranges only: does not construct a creature or make any rolls.
String ageRangeHelp((int, int) range) {
  const starts = [0, childAge, teenAge, middleAge, oldAge, elderlyAge];
  final lines = <String>[];
  for (var index = 0; index < starts.length; index++) {
    final low = range.$1 > starts[index] ? range.$1 : starts[index];
    final end = index + 1 < starts.length ? starts[index + 1] - 1 : range.$2;
    final high = range.$2 < end ? range.$2 : end;
    if (low > high) continue;
    lines.add(
      '${low == high ? '$low' : '$low–$high'}: ${_modifiersAtAge(low)}',
    );
  }
  return 'Age modifiers by generated age (before other modifiers):\n${lines.join('\n')}';
}

String ageHelp(Creature person) {
  final next = [
    childAge,
    teenAge,
    middleAge,
    oldAge,
    elderlyAge,
  ].where((age) => age > person.age).firstOrNull;
  // The daily handler makes one health-loss check per started five-year band
  // strictly after 60. This is a risk, not a scheduled loss on a birthday.
  final checks = person.age <= 60 ? 0 : (person.age - 61) ~/ 5 + 1;
  return [
    'Age ${person.age}: ${ageAttributeSummary(person)}',
    if (person.body is HumanoidBody) ...[
      'Already included in displayed attributes and their skill training caps. Unlisted attributes are unchanged by age. Injuries, Juice, blood loss and the minimum attribute of 1 can change the final values; do not add these modifiers again.',
      'Health and maximum blood also reflect age through Strength and, for conservatives, Wisdom. Moderates use the lower of Heart and Wisdom alongside Strength.',
      if (next != null)
        'Next attribute age band at $next: ${_modifiersAtAge(next)}',
    ],
    'Starting skills: generated characters gain one extra random background skill point per full five years over 20, or lose one per full two years under 20. This only affects character generation; birthdays do not award skill points. Profession skills and training caps also apply.',
    if (checks == 0)
      'Old-age Health decline starts at 61. There is no old-age Health-loss roll at this age.'
    else
      'Old-age Health risk: $checks independent ${checks == 1 ? 'check' : 'checks'} per day, each with a 1 in 1,825 chance to permanently lose 1 Health. One extra check starts every five years after 61. At 1 Health, a successful decline roll causes death.',
    if (person.human)
      'Age gaps affect seduction difficulty. Some activities and venues have minimum ages, such as 18 for prostitution and 21 for the nightclub.',
  ].join('\n\n');
}

/// Visible summary plus pointer, touch and keyboard-accessible details. The
/// expansion is local UI state and does not dispatch an engine command.
class AgeEffects extends StatelessWidget {
  const AgeEffects({super.key, required this.person});

  final Creature person;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Age modifiers: ${ageAttributeSummary(person)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const Text(
        'Already included in displayed stats.',
        style: JournalPalette.small,
      ),
      Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: ValueKey('age-details:${person.id}'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: const Text('How age affects this character'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(ageHelp(person), style: JournalPalette.small),
            ),
          ],
        ),
      ),
    ],
  );
}
