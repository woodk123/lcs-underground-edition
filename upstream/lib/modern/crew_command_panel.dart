import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_status.dart';

/// Read-only recruitment links, using the engine's exact slot accounting.
class CrewCommandPanel extends StatelessWidget {
  const CrewCommandPanel({super.key, required this.person});

  final Creature person;

  @override
  Widget build(BuildContext context) {
    final status = JuiceStatus(person);
    final reports = game.pool.where((p) => p.hireId == person.id).toList();
    final boss = person.boss;
    return Column(
      key: ValueKey('crew-command:${person.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Command capacity: ${status.recruitsUsed}/${status.recruitCap} slots used'
          ' · ${status.freeRecruitSlots} free',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          person.hireId == null
              ? 'Movement leader · no superior'
              : 'Reports to: ${boss?.name ?? 'No current contact'}',
        ),
        Text(
          'Direct reports (${reports.length}):${reports.isEmpty ? ' None' : ''}',
        ),
        for (final report in reports)
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 2),
            child: Text(
              [
                report.name,
                if (!report.alive) 'deceased',
                if (report.sleeperAgent) 'sleeper',
                if (report.seduced) 'seduced · no command slot',
                if (report.brainwashed) 'brainwashed · no command slot',
              ].join(' · '),
            ),
          ),
        const SizedBox(height: 3),
        const Text(
          'Juice rank determines capacity; movement leaders get 6 extra slots. '
          'Brainwashed people cannot command recruits. '
          'Seduced and brainwashed recruits do not use command slots.',
          style: TextStyle(fontSize: 11, color: JournalPalette.muted),
        ),
      ],
    );
  }
}
