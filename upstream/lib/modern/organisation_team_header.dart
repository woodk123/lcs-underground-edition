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
    this.compact = false,
  });

  final String teamName;
  final bool showingSkills;
  final VoidCallback onToggleSkills;
  final String memberCount;
  final String memberCountLabel;
  final String armedCount;
  final String carCount;
  final OrganisationTeamActorView? actor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return JournalSurface(
      inset: true,
      padding: const EdgeInsets.all(5),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final inlineCounters = compact && bounds.maxWidth >= 240;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: teamName,
                      excludeFromSemantics: true,
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
                  if (inlineCounters) ...[
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      // Keep some team identity beside the counters and the toggle.
                      // Longer network counts wrap rather than squeezing it away.
                      constraints: BoxConstraints(
                        maxWidth: bounds.maxWidth - 112,
                      ),
                      child: _facts(spacing: 6),
                    ),
                    const SizedBox(width: 4),
                  ],
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
              SizedBox(height: compact ? 2 : 3),
              if (actor != null)
                actor!._withCompact(compact)
              else
                const Text(
                  'No active crew selected.',
                  style: JournalPalette.small,
                ),
              if (!inlineCounters) ...[
                const SizedBox(height: 4),
                _facts(spacing: 10),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _facts({required double spacing}) => Wrap(
    spacing: spacing,
    runSpacing: 2,
    children: [
      _fact('members', Icons.people, memberCount, memberCountLabel),
      _fact('armed', Icons.shield_outlined, armedCount, 'Armed members'),
      _fact('cars', Icons.directions_car, carCount, 'Assigned cars'),
    ],
  );

  Widget _fact(String id, IconData icon, String value, String name) => Tooltip(
    message: name,
    excludeFromSemantics: true,
    child: Semantics(
      key: ValueKey('journal-team-$id'),
      container: true,
      label: '$name: $value',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: JournalPalette.brassDark),
            const SizedBox(width: 4),
            Flexible(child: Text(value, style: JournalPalette.body)),
          ],
        ),
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
    this.compact = false,
  });

  final int personId;
  final String name;
  final String location;
  final String status;
  final String statusTooltip;
  final bool statusWarning;
  final Widget portrait;
  final VoidCallback onInspect;
  final bool compact;

  OrganisationTeamActorView _withCompact(bool value) => value == compact
      ? this
      : OrganisationTeamActorView(
          key: key,
          personId: personId,
          name: name,
          location: location,
          status: status,
          statusTooltip: statusTooltip,
          statusWarning: statusWarning,
          portrait: portrait,
          onInspect: onInspect,
          compact: value,
        );

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MergeSemantics(
        child: Semantics(
          button: true,
          label: 'Inspect $name',
          child: InkWell(
            key: ValueKey('hq-portrait:$personId'),
            onTap: onInspect,
            child: ExcludeSemantics(child: portrait),
          ),
        ),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: name,
              excludeFromSemantics: true,
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
              excludeFromSemantics: true,
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
              excludeFromSemantics: true,
              child: Semantics(
                container: true,
                label:
                    '${statusWarning ? 'Health warning: ' : ''}$statusTooltip',
                child: ExcludeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (compact && statusWarning) ...[
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: JournalPalette.danger,
                          ),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Expanded(
                        child: Text(
                          status,
                          key: const ValueKey('journal-selected-status'),
                          maxLines: compact ? null : 1,
                          overflow: compact
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
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
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
