import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Team identity and counters prepared by the journal. The journal owns the
/// selected actor, source-reader interpretation and crew/skills toggle state.
class OrganisationTeamHeaderView extends StatelessWidget {
  const OrganisationTeamHeaderView({
    super.key,
    required this.teamName,
    required this.showingSkills,
    required this.onToggleSkills,
    required this.memberCount,
    required this.memberCountLabel,
    required this.armedCount,
    required this.carCount,
    this.actor,
  });

  final String teamName;
  final bool showingSkills;
  final VoidCallback onToggleSkills;
  final String memberCount;
  final String memberCountLabel;
  final String armedCount;
  final String carCount;
  final OrganisationTeamActorView? actor;

  @override
  Widget build(BuildContext context) {
    return JournalSurface(
      inset: true,
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: teamName,
                  child: Text(
                    teamName,
                    key: const ValueKey('journal-team-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JournalPalette.heading.copyWith(
                      fontSize: 14,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  key: const ValueKey('journal-skills'),
                  tooltip: 'Toggle crew and skills',
                  onPressed: onToggleSkills,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(24, 24),
                  ),
                  icon: Icon(
                    showingSkills ? Icons.groups : Icons.auto_graph,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (actor != null)
            actor!
          else
            const Text('No active crew selected.', style: JournalPalette.small),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              _fact(Icons.people, memberCount, memberCountLabel),
              _fact(Icons.shield_outlined, armedCount, 'Armed members'),
              _fact(Icons.directions_car, carCount, 'Assigned cars'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String value, String name) => Tooltip(
    message: name,
    child: Semantics(
      label: '$name: $value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: JournalPalette.brassDark),
          const SizedBox(width: 4),
          Text(value, style: JournalPalette.body),
        ],
      ),
    ),
  );
}

/// Selected-person presentation with an existing portrait supplied as a slot.
/// Character status calculations and inspection routing stay in the journal.
class OrganisationTeamActorView extends StatelessWidget {
  const OrganisationTeamActorView({
    super.key,
    required this.personId,
    required this.name,
    required this.location,
    required this.status,
    required this.statusTooltip,
    required this.statusWarning,
    required this.portrait,
    required this.onInspect,
  });

  final int personId;
  final String name;
  final String location;
  final String status;
  final String statusTooltip;
  final bool statusWarning;
  final Widget portrait;
  final VoidCallback onInspect;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        button: true,
        label: 'Inspect $name',
        child: InkWell(
          key: ValueKey('hq-portrait:$personId'),
          onTap: onInspect,
          child: portrait,
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: name,
              child: Text(
                name,
                key: const ValueKey('journal-selected-person'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JournalPalette.heading.copyWith(
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ),
            Tooltip(
              message: location,
              child: Text(
                location,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JournalPalette.small.copyWith(
                  fontSize: 10.5,
                  height: 1.15,
                ),
              ),
            ),
            Tooltip(
              message: statusTooltip,
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: JournalPalette.small.copyWith(
                  fontSize: 10.5,
                  height: 1.15,
                  color: statusWarning
                      ? JournalPalette.danger
                      : JournalPalette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
