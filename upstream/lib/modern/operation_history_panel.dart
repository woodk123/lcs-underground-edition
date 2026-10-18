import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/operation_record.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

class OperationHistoryPanel extends StatelessWidget {
  const OperationHistoryPanel({super.key, required this.person});
  final Creature person;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Operation history',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          person.operationHistory.isEmpty
              ? 'No significant operations recorded yet. History starts with '
                    'operations completed in this version; earlier events are not reconstructed.'
              : 'Most recent significant operations, up to $operationHistoryLimit per person. '
                    'These are historical outcomes; current wanted status is shown above. '
                    'News coverage and evidence publication resolve separately.',
          style: const TextStyle(fontSize: 12, color: JournalPalette.muted),
        ),
        const SizedBox(height: 8),
        for (final (index, record)
            in person.operationHistory.indexed.toList().reversed)
          ExpansionTile(
            key: PageStorageKey(
              'operation-history:${person.id}:${record.date.toIso8601String()}:$index:${record.siteName}',
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 16),
            title: Text(record.siteName),
            subtitle: Text(
              '${record.date.day} ${getMonthShort(record.date.month)} ${record.date.year} · '
              '${record.siege ? 'Siege · ' : ''}${_outcome(record.outcome)}'
              '${record.juiceChange != 0 ? ' · Juice ${_signed(record.juiceChange)}' : ''}',
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            expandedAlignment: Alignment.centerLeft,
            children: [
              Text('Participants: ${record.participants.join(', ')}'),
              const SizedBox(height: 8),
              Text('Personal heat: ${record.heatBefore} → ${record.heatAfter}'),
              Text(
                record.newCharges.isEmpty
                    ? 'No new wanted counts recorded.'
                    : 'New wanted counts at the time: ${record.newCharges.entries.map((e) => '${e.key.wantedFor} ×${e.value}').join(' · ')}',
              ),
              if (record.bloodChange != 0)
                Text('Blood: ${_signed(record.bloodChange)}'),
              for (final injury in record.injuries)
                Text('Injury at return: $injury'),
              for (final xp in record.trainingXp.entries)
                Text('${xp.key.displayName}: +${xp.value} training XP'),
              if (record.squadResults.isNotEmpty ||
                  record.opinionChanges.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(
                    'Squad results',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              for (final result in record.squadResults) Text(result),
              for (final change in record.opinionChanges.entries)
                Text(
                  '${change.key.label}: ${change.value > 0 ? '+' : ''}'
                  '${change.value.toStringAsPrecision(3)} opinion points during the operation',
                ),
            ],
          ),
      ],
    ),
  );
}

String _signed(int value) => value > 0 ? '+$value' : '$value';
String _outcome(OperationOutcome outcome) => switch (outcome) {
  OperationOutcome.returned => 'Returned',
  OperationOutcome.captured => 'Captured',
  OperationOutcome.killed => 'Killed',
  OperationOutcome.missing => 'Missing',
};
