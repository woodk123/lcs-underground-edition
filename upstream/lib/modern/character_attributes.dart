import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// Effective scores are the decision; modifier explanations stay on demand.
class CharacterAttributes extends StatelessWidget {
  const CharacterAttributes({super.key, required this.person});

  final Creature person;

  @override
  Widget build(BuildContext context) => Column(
    key: ValueKey('character-attributes:${person.id}'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Attributes', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      LayoutBuilder(
        builder: (context, bounds) {
          final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final columns = (bounds.maxWidth / (135 * scale)).floor().clamp(1, 4);
          final width = (bounds.maxWidth - (columns - 1) * 8) / columns;
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final attribute in Attribute.values)
                SizedBox(
                  width: width,
                  child: AttributeTooltip(
                    attribute: attribute,
                    actor: person,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: JournalPalette.inset,
                        border: Border.all(color: JournalPalette.rule),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${attribute.name[0].toUpperCase()}${attribute.name.substring(1)}',
                              style: JournalPalette.small,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${person.attribute(attribute)}',
                            key: ValueKey(
                              'character-attribute:${attribute.name}',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 4),
      MechanicsTooltip(
        message: ageHelp(person),
        child: const Text(
          'Effective scores · age and other modifiers included',
          style: JournalPalette.small,
        ),
      ),
    ],
  );
}
