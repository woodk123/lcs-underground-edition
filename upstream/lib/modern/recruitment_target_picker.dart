import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/engine/recruitment_context.dart';
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/character_attributes.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

String _range((int, int) range) =>
    range.$1 == range.$2 ? '${range.$1}' : '${range.$1}–${range.$2}';

/// Reads generation definitions without rolling characters or consuming RNG.
String recruitmentProfessionHelp(CreatureType type) {
  final skills = type.skillPoints.entries.where((s) => s.value.$2 > 0);
  return '${type.name}\n'
      'Base attribute ranges: ${characterAttributeDisplayOrder.where(type.attributePoints.containsKey).map((attribute) => '${attribute.name[0].toUpperCase()}${attribute.name.substring(1)} ${_range(type.attributePoints[attribute]!)}').join(', ')}.\n'
      'Profession skills: ${skills.isEmpty ? 'No guaranteed trained skills' : skills.map((s) => '${s.key.displayName} ${_range(s.value)}').join(', ')}.\n'
      'Age: ${_range(type.age)}. Alignment: ${type.alignment.name == 'any' ? 'varies with the political climate' : type.alignment.name}.\n'
      '${type.tank ? 'No age attribute modifiers for tanks.' : ageRangeHelp(type.age)}\n'
      'These are generation ranges, not promised final stats. Attribute totals are rebalanced; alignment changes Heart and Wisdom. Skills are capped by attributes and may gain random background training.';
}

class RecruitmentTargetPreview extends StatelessWidget {
  const RecruitmentTargetPreview({super.key, required this.target});
  final RecruitmentTargetContext target;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CreatureType>(
    valueListenable: target.preview,
    builder: (context, type, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Recruiting · ${target.recruiter.name}',
          style: JournalPalette.heading,
        ),
        const Text('Today’s recruitment · choose a profession'),
        const SizedBox(height: 8),
        Text(
          '${type.name}: ${target.meetings(type)} meetings',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        if (JournalPreferences.of(context).showGuidance)
          const Text(
            'Based on current Street Smarts. Meetings are contacts; convincing someone to join happens in conversation.',
          ),
        const SizedBox(height: 8),
        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            key: PageStorageKey(
              'recruitment-profession-details:${type.id}:${JournalPreferences.of(context).showGuidance}',
            ),
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: JournalPreferences.of(context).showGuidance,
            title: const Text(
              'Profession ranges and rules',
              style: JournalPalette.small,
            ),
            children: [
              Text(
                recruitmentProfessionHelp(type),
                style: JournalPalette.small,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class RecruitmentTargetPicker extends StatelessWidget {
  const RecruitmentTargetPicker({
    super.key,
    required this.target,
    required this.onAction,
  });
  final RecruitmentTargetContext target;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final start = target.page * 20;
    final end = (start + 20).clamp(0, target.targets.length);
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferences = JournalPreferences.of(context);
        final narrow =
            constraints.maxWidth /
                (MediaQuery.textScalerOf(context).scale(14) / 14) <
            600;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (preferences.showGuidance)
              const Text(
                'Select a profession to search today. Meeting difficulty is about finding contacts; persuasion comes afterward.',
              ),
            const SizedBox(height: 8),
            Text(
              'Page ${target.page + 1} of ${target.pageCount} · Professions ${start + 1}–$end of ${target.targets.length}',
            ),
            if (!narrow)
              const Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      'Profession',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Meeting difficulty',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Meetings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  SizedBox(width: 48),
                ],
              ),
            for (var i = start; i < end; i++)
              Builder(
                builder: (context) {
                  final (type, difficulty) = target.targets[i];
                  final shortcut = String.fromCharCode(65 + i - start);
                  const label = [
                    'Trivial',
                    'Very Easy',
                    'Easy',
                    'Below Average',
                    'Average',
                    'Above Average',
                    'Hard',
                    'Very Hard',
                    'Extremely Difficult',
                    'Almost Impossible',
                  ];
                  final help = recruitmentProfessionHelp(type);
                  return MouseRegion(
                    onEnter: (_) => target.preview.value = type,
                    child: Focus(
                      onFocusChange: (focused) {
                        if (focused) target.preview.value = type;
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: help,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: preferences.compact ? 6 : 12,
                                    vertical: preferences.compact ? 6 : 10,
                                  ),
                                ),
                                onPressed: () =>
                                    onAction(shortcut.toLowerCase()),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: narrow
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '$shortcut  ${type.name}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              'Meeting difficulty: ${difficulty >= 10 ? 'Impossible' : label[difficulty.clamp(0, 9)]}',
                                            ),
                                            Text(
                                              '${target.meetings(type)} meetings',
                                            ),
                                          ],
                                        )
                                      : Row(
                                          children: [
                                            Expanded(
                                              flex: 5,
                                              child: Row(
                                                children: [
                                                  Text('$shortcut  '),
                                                  Expanded(
                                                    child: Text(type.name),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 3,
                                              child: Text(
                                                difficulty >= 10
                                                    ? 'Impossible'
                                                    : label[difficulty.clamp(
                                                        0,
                                                        9,
                                                      )],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                '${target.meetings(type)}',
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: help,
                            icon: const Icon(Icons.info_outline, size: 18),
                            onPressed: () async {
                              target.preview.value = type;
                              await showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: JournalPalette.card,
                                  title: Text(type.name),
                                  content: SingleChildScrollView(
                                    child: Text(help),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: target.page > 0 ? () => onAction('[') : null,
                  child: const JournalCommandLabel(
                    shortcut: '[',
                    label: 'Previous page',
                  ),
                ),
                OutlinedButton(
                  onPressed: target.page + 1 < target.pageCount
                      ? () => onAction(']')
                      : null,
                  child: const JournalCommandLabel(
                    shortcut: ']',
                    label: 'Next page',
                  ),
                ),
                OutlinedButton(
                  onPressed: () => onAction('Escape'),
                  child: const JournalCommandLabel(
                    shortcut: 'Escape',
                    label: 'Skip recruitment today',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
