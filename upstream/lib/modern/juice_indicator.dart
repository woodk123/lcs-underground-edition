import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_status.dart';

/// Consistent, actionable Juice disclosure anywhere a character is shown.
class JuiceBadge extends StatelessWidget {
  const JuiceBadge({
    super.key,
    required this.person,
    this.compact = false,
    this.showHelp = true,
  });
  final Creature person;
  final bool compact, showHelp;

  @override
  Widget build(BuildContext context) {
    final status = JuiceStatus(person);
    final color = status.juice < 0
        ? JournalPalette.danger
        : JournalPalette.olive;
    final label = '${person.alive ? 'Juice' : 'Final Juice'} ${status.juice}';
    final explanation =
        '${status.title} · ${status.bonusSummary}. ${status.milestone}.';
    if (!showHelp) {
      return Tooltip(
        message: '$explanation Open their dossier for Juice effects.',
        child: Container(
          key: ValueKey('juice-value:${person.id}'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .06),
            border: Border.all(color: color.withValues(alpha: .25)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: '$explanation Select for Juice effects.',
      child: TextButton.icon(
        key: ValueKey('juice-badge:${person.id}'),
        onPressed: showHelp ? () => showJuiceHelp(context, person) : null,
        style: TextButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: color,
          backgroundColor: color.withValues(alpha: .06),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 9,
            vertical: compact ? 3 : 6,
          ),
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.padded,
          side: BorderSide(color: color.withValues(alpha: .28)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
        icon: Icon(Icons.workspace_premium_outlined, size: compact ? 15 : 17),
        label: Text(
          label,
          style: TextStyle(
            fontFamily: JournalPalette.serif,
            fontSize: compact ? 10 : 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The richer dossier treatment: current benefits and progress to the next rank.
class JuiceProgress extends StatelessWidget {
  const JuiceProgress({super.key, required this.person});
  final Creature person;

  @override
  Widget build(BuildContext context) {
    final status = JuiceStatus(person);
    final color = status.juice < 0
        ? JournalPalette.danger
        : JournalPalette.olive;
    return Column(
      key: ValueKey('juice-progress:${person.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            JuiceBadge(person: person, compact: true),
            Text(
              status.bonusSummary,
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
        if (person.alive) ...[
          const SizedBox(height: 5),
          Text(
            status.milestone,
            key: ValueKey('juice-next:${person.id}'),
            style: const TextStyle(
              fontSize: 11,
              height: 1.4,
              color: JournalPalette.muted,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: status.progress,
              minHeight: 3,
              color: color,
              backgroundColor: JournalPalette.rule.withValues(alpha: .35),
              semanticsLabel: status.nextJuice == null
                  ? 'Highest Juice rank reached'
                  : 'Progress to ${status.nextTitle}',
            ),
          ),
        ],
      ],
    );
  }
}

/// Task-specific cap disclosure beside the assignment, with no promised gain.
class JuiceActivityHint extends StatelessWidget {
  const JuiceActivityHint({
    super.key,
    required this.person,
    required this.activity,
  });
  final Creature person;
  final ActivityType activity;

  @override
  Widget build(BuildContext context) {
    final cap = knownActivityJuiceCap(activity);
    if (cap == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        person.juice >= cap
            ? 'Routine Juice cap $cap · reached'
            : 'Routine Juice rewards can raise it to $cap; gains depend on the outcome.',
        style: JournalPalette.small.copyWith(color: JournalPalette.olive),
      ),
    );
  }
}

/// Read-only help, available by pointer, keyboard and touch. Never rolls dice,
/// previews a treatment, or sends input to the underlying game reader.
Future<void> showJuiceHelp(BuildContext context, Creature person) =>
    showDialog<void>(
      context: context,
      builder: (context) => _JuiceHelp(person: person),
    );

class _JuiceHelp extends StatelessWidget {
  const _JuiceHelp({required this.person});
  final Creature person;

  @override
  Widget build(BuildContext context) {
    final status = JuiceStatus(person);
    final affected = Attribute.values
        .where(status.affectsAttribute)
        .map(
          (attribute) =>
              '${attribute.name[0].toUpperCase()}${attribute.name.substring(1)}',
        )
        .join(', ');
    final exempt = Attribute.values
        .where((attribute) => !status.affectsAttribute(attribute))
        .map(
          (attribute) =>
              '${attribute.name[0].toUpperCase()}${attribute.name.substring(1)}',
        )
        .join(', ');
    return AlertDialog(
      key: const ValueKey('juice-help'),
      backgroundColor: JournalPalette.card,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Juice · experience & standing',
        style: JournalPalette.heading,
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: DefaultTextStyle.merge(
            style: JournalPalette.body,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${person.name} · ${status.juice} Juice · ${status.title}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Juice measures a person’s experience and standing. It carries over between days and can rise or fall with events. Reaching a milestone changes their rank and can make them more capable.',
                ),
                const SizedBox(height: 16),
                _heading('Current gameplay effects'),
                Text(
                  '${status.bonusSummary}, before rounding. Applies to: $affected.',
                ),
                if (exempt.isNotEmpty)
                  Text(
                    '$exempt is unaffected by Juice for this political alignment.',
                    style: JournalPalette.small,
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Higher attributes improve attribute checks and can raise skill training ceilings and maximum blood. The displayed attributes already include Juice; injuries and blood loss also affect the final values.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Direct recruits: ${status.recruitsUsed} / ${status.recruitCap} · ${status.freeRecruitSlots} free slots.',
                ),
                const Text(
                  'This is their personal recruitment capacity, separate from the six-person squad limit. Partners and brainwashed recruits use different rules.',
                  style: JournalPalette.small,
                ),
                const SizedBox(height: 8),
                const Text(
                  'More Juice also helps resist fear in encounters. Equipment, injuries and the situation still matter.',
                ),
                const SizedBox(height: 16),
                _heading(person.alive ? 'Next milestone' : 'Historical record'),
                if (!person.alive)
                  const Text(
                    'This person is deceased. Juice and rank remain in their record; they cannot act or progress.',
                  )
                else if (status.nextJuice == null)
                  const Text(
                    'Highest Juice rank reached. Further skill development depends on training and current attribute caps.',
                  )
                else ...[
                  Text(
                    '${status.remaining} more Juice → ${status.nextTitle} at ${status.nextJuice}.',
                  ),
                  Text(
                    'Direct recruit limit at that rank: ${status.nextRecruitCap}.',
                    style: JournalPalette.small,
                  ),
                ],
                if (person.alive) ...[
                  const SizedBox(height: 16),
                  _heading('Earning Juice'),
                  const Text(
                    'Successful actions can award Juice, but each activity has its own limit. Community Service can raise it to 10, Liberal Disobedience to 50, and Hacking to 200. Outcomes and risks vary.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Once you reach a task’s Juice cap, its routine Juice rewards stop. Skill XP is separate: a new Juice rank does not instantly add trained skill levels.',
                    style: JournalPalette.small,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('juice-help-close'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: JournalPalette.heading.copyWith(fontSize: 15)),
  );
}
