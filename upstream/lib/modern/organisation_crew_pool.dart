import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// The allocation pool's presentation. The journal owns selection and sorting,
/// including their existing retention and reset rules.
/// Transfers and live drop eligibility remain owned by the source controller.
class OrganisationCrewPoolView extends StatelessWidget {
  const OrganisationCrewPoolView({
    super.key,
    required this.allocationPool,
    required this.members,
    required this.sortSkill,
    required this.selectedPersonId,
    required this.busy,
    required this.blockReason,
    required this.canRemoveMember,
    required this.onSortChanged,
    required this.onSelectPerson,
    required this.onTransfer,
  });

  final List<Creature> allocationPool;
  final List<Creature> members;
  final Skill sortSkill;
  final int? selectedPersonId;
  final bool busy;
  final String? Function(int personId) blockReason;
  final bool Function(int personId) canRemoveMember;
  final ValueChanged<Skill> onSortChanged;
  final ValueChanged<int> onSelectPerson;
  final ValueChanged<int> onTransfer;

  @override
  Widget build(BuildContext context) {
    final memberIds = members.map((member) => member.id).toSet();
    final candidates =
        allocationPool.where((p) => !memberIds.contains(p.id)).toList()
          ..sort((a, b) {
            final rating = b.skill(sortSkill).compareTo(a.skill(sortSkill));
            return rating != 0 ? rating : a.name.compareTo(b.name);
          });
    final preview = candidates
        .where((p) => p.id == selectedPersonId)
        .firstOrNull;
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => canRemoveMember(d.data),
      onAcceptWithDetails: (d) => onTransfer(d.data),
      builder: (context, incoming, rejected) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Assign to squads', style: JournalPalette.heading),
          DropdownButton<Skill>(
            value: sortSkill,
            isExpanded: true,
            items: [
              for (final skill in Skill.values)
                DropdownMenuItem(
                  value: skill,
                  child: SkillTooltip(
                    skill: skill,
                    actor: preview,
                    child: Text(
                      'Sort: ${skill.displayName}',
                      style: JournalPalette.small,
                    ),
                  ),
                ),
            ],
            onChanged: (skill) {
              if (skill != null) onSortChanged(skill);
            },
          ),
          Text(
            incoming.isNotEmpty
                ? 'Drop to remove from this squad'
                : 'Select a portrait to inspect; add with the arrow or drag onto the left page.',
            style: JournalPalette.small,
          ),
          const SizedBox(height: 7),
          Expanded(
            child: candidates.isEmpty
                ? const Center(
                    child: Text(
                      'All eligible crew are already in this squad.\nRemove a name on the left to return them to the pool.',
                      textAlign: TextAlign.center,
                      style: JournalPalette.body,
                    ),
                  )
                : ListView(
                    children: [
                      for (final candidate in candidates) _poolRow(candidate),
                    ],
                  ),
          ),
          if (preview != null)
            SizedBox(
              height: 165,
              child: JournalSurface(
                inset: true,
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      preview.name,
                      style: JournalPalette.heading.copyWith(fontSize: 15),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final skill in _bestSkills(preview))
                              SkillTooltip(
                                skill: skill,
                                actor: preview,
                                child: Text(
                                  '${skill.displayName}  ${preview.skill(skill)}',
                                  style: JournalPalette.small,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (blockReason(preview.id) case final reason?)
                      Text(
                        reason,
                        style: JournalPalette.small.copyWith(
                          color: JournalPalette.danger,
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: busy || blockReason(preview.id) != null
                          ? null
                          : () => onTransfer(preview.id),
                      icon: Icon(
                        members.any((p) => p.id == preview.id)
                            ? Icons.arrow_forward
                            : Icons.arrow_back,
                        size: 17,
                      ),
                      label: Text(
                        members.any((p) => p.id == preview.id)
                            ? 'Return to pool'
                            : 'Add to this squad',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _poolRow(Creature candidate) {
    final inSquad = members.any((p) => p.id == candidate.id);
    final reason = blockReason(candidate.id);
    void select() => onSelectPerson(candidate.id);
    final row = Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.all(5),
        decoration: journalTabDecoration(
          selected: selectedPersonId == candidate.id,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                key: ValueKey('journal-pool-person:${candidate.id}'),
                onPressed: select,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Semantics(
                  label: 'Inspect pool member ${candidate.name}',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      CrewPortrait(person: candidate, size: 46),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JournalPalette.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              candidate.squad?.name ?? 'Unassigned',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JournalPalette.small,
                            ),
                            Text(
                              '${sortSkill.displayName} ${candidate.skill(sortSkill)} · ${candidate.blood}/${candidate.maxBlood} blood',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JournalPalette.small,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Tooltip(
              message:
                  reason ??
                  (inSquad ? 'Remove from this squad' : 'Add to this squad'),
              child: IconButton(
                key: ValueKey('journal-transfer:${candidate.id}'),
                tooltip: inSquad
                    ? 'Remove ${candidate.name} from this squad'
                    : 'Add ${candidate.name} to this squad',
                onPressed: reason == null && !busy
                    ? () => onTransfer(candidate.id)
                    : null,
                icon: Icon(
                  inSquad ? Icons.arrow_forward : Icons.arrow_back,
                  color: reason == null
                      ? JournalPalette.olive
                      : JournalPalette.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return reason == null
        ? Draggable<int>(
            data: candidate.id,
            feedback: Material(
              color: JournalPalette.selected,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(candidate.name, style: JournalPalette.body),
              ),
            ),
            childWhenDragging: Opacity(opacity: .4, child: row),
            child: row,
          )
        : row;
  }

  Iterable<Skill> _bestSkills(Creature actor) {
    final values = Skill.values.toList()
      ..sort((a, b) => actor.skill(b).compareTo(actor.skill(a)));
    return values.take(8);
  }
}
