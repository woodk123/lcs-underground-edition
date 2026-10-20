import 'package:flutter/material.dart' hide Alignment;
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/modern/character_attributes.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_indicator.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/politics/alignment.dart';

/// A read-only summary of this person's actual skill levels, with stable ties.
List<Skill> recruitmentStrengths(Creature person) {
  final skills = Skill.values.where((skill) => person.skill(skill) > 0).toList()
    ..sort((a, b) {
      final level = person.skill(b).compareTo(person.skill(a));
      return level != 0 ? level : a.displayName.compareTo(b.displayName);
    });
  return skills.take(3).toList(growable: false);
}

String recruitmentBackground(Creature person) {
  final strengths = recruitmentStrengths(person);
  if (!person.human) {
    return strengths.isEmpty
        ? '${person.body.typeName}. No trained skills recorded.'
        : '${person.body.typeName}, with ${strengths.map((s) => s.displayName).join(', ')} among their strongest skills.';
  }
  final profession = person.type.name;
  if (strengths.isEmpty) {
    return 'Background: $profession. They have no trained skills recorded yet.';
  }
  final names = strengths.map((skill) => skill.displayName).toList();
  final skills = names.length == 1
      ? names.single
      : '${names.take(names.length - 1).join(', ')} and ${names.last}';
  return 'Background: $profession. ${names.length == 1 ? '$skills is their strongest skill' : '$skills are their strongest skills'}.';
}

/// Introduces an existing prospect. Commands are supplied by the active reader;
/// opening the dossier never advances time or performs a recruitment roll.
class RecruitmentCard extends StatelessWidget {
  const RecruitmentCard({
    super.key,
    required this.person,
    required this.recruiter,
    required this.onInspect,
    this.onMeet,
    this.shortcut,
    this.followUp = false,
  });

  final Creature person, recruiter;
  final VoidCallback onInspect;
  final VoidCallback? onMeet;
  final String? shortcut;
  final bool followUp;

  @override
  Widget build(BuildContext context) {
    final preferences = JournalPreferences.of(context);
    final strengths = recruitmentStrengths(person);
    return Container(
      key: ValueKey('recruitment-card:${person.id}'),
      padding: EdgeInsets.all(preferences.compact ? 10 : 16),
      decoration: BoxDecoration(
        color: JournalPalette.card,
        border: Border.all(color: JournalPalette.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CrewPortrait(
                person: person,
                size: preferences.compact ? 44 : 80,
                showStatus: false,
              ),
              SizedBox(width: preferences.compact ? 9 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      followUp ? 'RECRUITMENT MEETING' : 'MEET A PROSPECT',
                      style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: JournalPalette.muted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      person.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 5),
                    Text.rich(
                      TextSpan(
                        text:
                            '${person.type.name}${person.human ? ' · Age ${person.age}' : ''} · ',
                        children: [
                          TextSpan(
                            text: switch (person.align) {
                              Alignment.liberal => 'Liberal',
                              Alignment.moderate => 'Moderate',
                              Alignment.conservative => 'Conservative',
                            },
                            style: TextStyle(
                              color: switch (person.align) {
                                Alignment.liberal => JournalPalette.olive,
                                Alignment.moderate => JournalPalette.brassDark,
                                Alignment.conservative => JournalPalette.danger,
                              },
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    JuiceBadge(person: person, compact: true),
                  ],
                ),
              ),
            ],
          ),
          if (preferences.showGuidance) ...[
            SizedBox(height: preferences.compact ? 6 : 12),
            Text(
              recruitmentBackground(person),
              style: const TextStyle(height: 1.5),
            ),
          ],
          SizedBox(height: preferences.compact ? 6 : 12),
          CharacterAttributes(person: person),
          if (strengths.isNotEmpty) ...[
            SizedBox(height: preferences.compact ? 6 : 12),
            const Text(
              'Strongest skills',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final skill in strengths)
                  MechanicsTooltip(
                    message: skillHelp(skill),
                    child: preferences.compact
                        ? Text(
                            '${skill.displayName} ${person.skill(skill)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )
                        : Chip(
                            label: Text(
                              '${skill.displayName} ${person.skill(skill)}',
                            ),
                          ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${followUp ? 'Meeting with' : 'Introduced through'} ${recruiter.name}',
            style: const TextStyle(color: JournalPalette.muted, fontSize: 12),
          ),
          SizedBox(height: preferences.compact ? 6 : 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (shortcut != null)
                FilledButton(
                  onPressed: onMeet,
                  child: Text(
                    '${shortcut!.toUpperCase()} · Meet ${person.name}',
                  ),
                ),
              OutlinedButton.icon(
                onPressed: onInspect,
                icon: const Icon(Icons.person_search_outlined, size: 18),
                label: Text('Inspect ${person.name}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
