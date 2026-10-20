import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// Classic character-sheet order, with the retired Health attribute omitted.
/// Keep this separate from Attribute.values: enum identity belongs to gameplay.
/// Source: King-Drake/Liberal-Crime-Squad, commondisplay.cpp,
/// printCreatureAttributes (Heart, Intelligence, Wisdom, Health, Agility,
/// Strength, Charisma).
const List<Attribute> characterAttributeDisplayOrder = [
  Attribute.heart,
  Attribute.intelligence,
  Attribute.wisdom,
  Attribute.agility,
  Attribute.strength,
  Attribute.charisma,
];

/// Effective scores are the decision; modifier explanations stay on demand.
class CharacterAttributes extends StatelessWidget {
  const CharacterAttributes({super.key, required this.person});

  final Creature person;

  @override
  Widget build(BuildContext context) {
    final preferences = JournalPreferences.of(context);
    return Column(
      key: ValueKey('character-attributes:${person.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Attributes',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: ValueKey('character-attribute-help:${person.id}'),
              tooltip: 'Attribute details and modifiers',
              visualDensity: VisualDensity.compact,
              onPressed: () => _showDetails(context),
              icon: const Icon(Icons.info_outline, size: 17),
            ),
          ],
        ),
        SizedBox(height: preferences.compact ? 2 : 6),
        LayoutBuilder(
          builder: (context, bounds) {
            final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
            final columns =
                (bounds.maxWidth / ((preferences.compact ? 125 : 135) * scale))
                    .floor()
                    .clamp(1, 3);
            final width = (bounds.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: preferences.compact ? 3 : 6,
              children: [
                for (final attribute in characterAttributeDisplayOrder)
                  SizedBox(
                    key: ValueKey('character-attribute-cell:${attribute.name}'),
                    width: width,
                    child: AttributeTooltip(
                      attribute: attribute,
                      actor: person,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: preferences.compact ? 6 : 8,
                          vertical: preferences.compact ? 3 : 6,
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
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
        SizedBox(height: preferences.compact ? 2 : 4),
        MechanicsTooltip(
          message: ageHelp(person),
          child: Text(
            preferences.showGuidance
                ? 'Effective scores · age and other modifiers included'
                : 'Effective scores',
            style: JournalPalette.small,
          ),
        ),
      ],
    );
  }

  Future<void> _showDetails(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Attributes · ${person.name}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ageHelp(person)),
            for (final attribute in characterAttributeDisplayOrder) ...[
              const SizedBox(height: 16),
              Text(
                '${attribute.name[0].toUpperCase()}${attribute.name.substring(1)} ${person.attribute(attribute)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(attributeHelp(attribute, actor: person)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
