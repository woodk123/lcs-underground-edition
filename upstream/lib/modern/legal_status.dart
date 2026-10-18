import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

class LegalStatusSummary extends StatelessWidget {
  const LegalStatusSummary({super.key, required this.person});
  final Creature person;

  @override
  Widget build(BuildContext context) {
    final charges = person.wantedForCrimes.entries.where((e) => e.value > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          charges.isEmpty
              ? 'No current wanted charges'
              : 'Wanted for: ${charges.map((e) => '${e.key.wantedFor} ×${e.value}').join(' · ')}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: charges.isEmpty ? JournalPalette.ink : JournalPalette.danger,
          ),
        ),
        Text('Personal heat: ${person.heat}'),
        LegalStatusExplanation(person: person),
        DecisionGuideButton(topic: DecisionTopic.heat, actor: person),
      ],
    );
  }
}

class LegalStatusExplanation extends StatelessWidget {
  const LegalStatusExplanation({super.key, required this.person});
  final Creature person;

  @override
  Widget build(BuildContext context) => Text(
    person.isCriminal
        ? '${person.heat == 0 ? 'Zero heat does not clear these offences. ' : ''}'
              'Wanted counts can affect sentencing if convicted. '
              'Heat measures police attention, not guilt or an arrest percentage.'
        : 'Heat measures police attention, not an arrest percentage. '
              'Wanted offences and past convictions are separate records.',
    style: const TextStyle(fontSize: 11, color: JournalPalette.muted),
  );
}
