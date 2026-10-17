import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/journal_context.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

class JournalPersonCard extends StatelessWidget {
  const JournalPersonCard({
    super.key,
    required this.summary,
    this.onSelect,
    this.onInspect,
  });

  final JournalPersonSummary summary;
  final VoidCallback? onSelect, onInspect;

  @override
  Widget build(BuildContext context) => Material(
    color: JournalPalette.card,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: JournalPalette.rule),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CrewPortrait(person: summary.person, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (onSelect != null)
                      TextButton(
                        onPressed: onSelect,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(summary.name),
                      )
                    else
                      Text(
                        summary.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    Text(
                      summary.role,
                      style: const TextStyle(color: JournalPalette.muted),
                    ),
                    if (summary.health.isNotEmpty)
                      Text('Health: ${summary.health}'),
                  ],
                ),
              ),
              if (onInspect != null && summary.inspectable)
                IconButton(
                  tooltip: 'Inspect ${summary.name}',
                  onPressed: onInspect,
                  icon: const Icon(Icons.badge_outlined, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [for (final line in summary.equipment) Text(line)],
          ),
          if (summary.details.isNotEmpty)
            ExpansionTile(
              key: PageStorageKey(
                'journal-person-details:${summary.person.id}',
              ),
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Attributes, skills & condition',
                style: TextStyle(fontSize: 13),
              ),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [for (final line in summary.details) Text(line)],
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}
