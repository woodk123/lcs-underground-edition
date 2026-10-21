import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// Read-only skill display facts, ordered and calculated by the journal.
@immutable
class OrganisationSkillData {
  const OrganisationSkillData({
    required this.id,
    required this.label,
    required this.level,
    required this.help,
  });

  final String id;
  final String label;
  final int level;
  final String help;
}

/// The passive skill paper has no actor, reader or gameplay authority.
class OrganisationSkillsPaperView extends StatelessWidget {
  const OrganisationSkillsPaperView({
    super.key,
    required this.title,
    required this.skills,
  });

  final String title;
  final List<OrganisationSkillData> skills;

  @override
  Widget build(BuildContext context) => JournalSurface(
    lined: true,
    inset: true,
    padding: const EdgeInsets.all(9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: JournalPalette.heading.copyWith(fontSize: 14)),
        const SizedBox(height: 5),
        Expanded(
          child: ListView(
            children: [
              for (final skill in skills)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: MechanicsTooltip(
                    key: ValueKey('journal-skill:${skill.id}'),
                    message: skill.help,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(skill.label, style: JournalPalette.small),
                        ),
                        const SizedBox(width: 8),
                        Text('${skill.level}', style: JournalPalette.body),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
