import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_city_plan.dart';
import 'package:lcs_new_age/modern/journal_order_icon.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// A display label and the journal-owned callback for a current planner action.
typedef OrganisationMapCommand = ({String label, VoidCallback? onPressed});

/// Map composition only; source actions, routing and selection belong to the journal.
class OrganisationMapView extends StatelessWidget {
  const OrganisationMapView({
    super.key,
    required this.planning,
    required this.compact,
    required this.places,
    required this.selectedId,
    required this.title,
    required this.onSelect,
    required this.commands,
    this.destination,
    this.message,
    this.onCityOverview,
  });

  final bool planning, compact;
  final List<JournalMapPlace> places;
  final String? selectedId, message;
  final String title;
  final ValueChanged<String> onSelect;
  final List<OrganisationMapCommand> commands;
  final Widget? destination;
  final VoidCallback? onCityOverview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (planning)
          const Text(
            'Letters browse · Enter queues visit · Esc cancels',
            key: ValueKey('journal-visit-keys'),
            style: JournalPalette.small,
          ),
        Expanded(
          child: JournalCityPlan(
            places: places,
            onSelect: onSelect,
            selectedId: selectedId,
            allowUnavailableInspection: true,
            showLegend: !compact,
            title: title,
          ),
        ),
        ?destination,
        if (message != null)
          Text(
            message!,
            key: const ValueKey('journal-visit-message'),
            style: JournalPalette.small.copyWith(color: JournalPalette.danger),
          ),
        if (planning)
          Wrap(
            spacing: 4,
            children: [
              for (final command in commands)
                TextButton(
                  onPressed: command.onPressed,
                  child: Text(command.label, style: JournalPalette.small),
                ),
            ],
          )
        else if (onCityOverview != null)
          TextButton.icon(
            style: compact
                ? TextButton.styleFrom(
                    minimumSize: const Size(44, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
                  )
                : null,
            onPressed: onCityOverview,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(
              'City overview',
              style: compact ? JournalPalette.small : null,
            ),
          ),
      ],
    );
  }
}

/// Detached destination facts; no campaign objects or eligibility rules live here.
class OrganisationDestinationCard extends StatelessWidget {
  const OrganisationDestinationCard({
    super.key,
    required this.compact,
    required this.cityMapVisit,
    required this.name,
    required this.squadName,
    required this.purpose,
    required this.access,
    required this.peopleSummary,
    required this.queued,
    required this.onDetails,
    this.onQueueVisit,
  });

  final bool compact, cityMapVisit, queued;
  final String name, squadName, purpose, access, peopleSummary;
  final VoidCallback onDetails;
  final VoidCallback? onQueueVisit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 7),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: compact || MediaQuery.sizeOf(context).height < 700
              ? cityMapVisit
                    ? 150
                    : 110
              : cityMapVisit
              ? 260
              : 220,
        ),
        child: SingleChildScrollView(
          child: JournalSurface(
            key: const ValueKey('journal-selected-destination'),
            inset: true,
            padding: EdgeInsets.all(compact ? 4 : 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        key: const ValueKey('journal-destination-name'),
                        style: JournalPalette.heading.copyWith(fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('journal-location-details'),
                      onPressed: onDetails,
                      icon: const JournalLocationGuideIcon(size: 22),
                      label: const Text('Location guide'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                      ),
                    ),
                  ],
                ),
                if (cityMapVisit) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Squad: $squadName',
                          key: const ValueKey('journal-city-map-squad'),
                          style: JournalPalette.small,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey('journal-city-map-prepare-visit'),
                        onPressed: onQueueVisit,
                        icon: const Icon(Icons.place_outlined, size: 17),
                        label: const Text('Queue visit · Enter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                MechanicsTooltip(
                  message: '$purpose\n\n$access',
                  child: Text(
                    purpose,
                    key: const ValueKey('journal-destination-purpose'),
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: JournalPalette.small,
                  ),
                ),
                Text(
                  access,
                  key: const ValueKey('journal-destination-access'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JournalPalette.small,
                ),
                Text(
                  peopleSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JournalPalette.small,
                ),
                if (queued)
                  const Text(
                    'Visit queued',
                    key: ValueKey('journal-queued-visit'),
                    style: JournalPalette.small,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
