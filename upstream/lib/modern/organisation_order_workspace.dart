import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/modern/journal_order_icon.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// Presentation of the task browser and its retained optional map pane.
/// The journal supplies already-filtered choices and owns all navigation.
class OrganisationOrderWorkspace extends StatelessWidget {
  const OrganisationOrderWorkspace({
    super.key,
    required this.heading,
    required this.showMap,
    required this.categories,
    required this.taskStorageId,
    required this.taskScrollController,
    required this.tasks,
    required this.emptyMessage,
    required this.map,
    this.onToggleMap,
    this.leadingTask,
    this.search,
  });

  final String heading;
  final bool showMap;
  final List<OrganisationOrderCategoryView> categories;
  final String taskStorageId;
  final ScrollController taskScrollController;
  final List<Widget> tasks;
  final String emptyMessage;
  final Widget map;
  final VoidCallback? onToggleMap;
  final Widget? leadingTask;
  final Widget? search;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              heading,
              key: const ValueKey('journal-orders-heading'),
              style: JournalPalette.heading,
            ),
          ),
          if (onToggleMap != null)
            TextButton.icon(
              key: const ValueKey('journal-orders-map-toggle'),
              onPressed: onToggleMap,
              icon: Icon(showMap ? Icons.list : Icons.map_outlined, size: 17),
              label: Text(showMap ? 'Tasks' : 'Map'),
            ),
        ],
      ),
      Expanded(
        key: const ValueKey('journal-order-workspace'),
        child: IndexedStack(
          index: showMap ? 1 : 0,
          sizing: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: showMap,
              // Task-only headings keep their height while this pane is
              // hidden, so map browsing cannot clamp the task scroll offset.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3, bottom: 6),
                    child: Text(
                      'Click: prepare, then confirm · Task key: assign immediately',
                      key: ValueKey('journal-orders-keyboard-help'),
                      style: JournalPalette.small,
                    ),
                  ),
                  if (search != null) search!,
                  if (categories.length > 1)
                    Wrap(spacing: 4, runSpacing: 3, children: categories),
                  if (categories.length > 1) const SizedBox(height: 6),
                  Expanded(
                    child: tasks.isNotEmpty || leadingTask != null
                        ? ListView(
                            key: PageStorageKey(taskStorageId),
                            controller: taskScrollController,
                            padding: EdgeInsets.zero,
                            children: [
                              if (leadingTask != null) leadingTask!,
                              ...tasks,
                            ],
                          )
                        : Center(
                            child: Text(
                              emptyMessage,
                              style: JournalPalette.small,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            ExcludeFocus(
              excluding: !showMap,
              child: KeyedSubtree(
                key: const ValueKey('journal-order-map'),
                child: map,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// A source category's display values, with navigation supplied by the journal.
class OrganisationOrderCategoryView extends StatelessWidget {
  const OrganisationOrderCategoryView({
    super.key,
    required this.label,
    required this.shortcut,
    required this.selected,
    this.onSelect,
  });

  final String label;
  final String shortcut;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onSelect,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: const Size(44, 32),
      backgroundColor: selected ? JournalPalette.selected : null,
    ),
    child: Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        JournalShortcutBadge(shortcut: shortcut),
        Text(label, style: JournalPalette.small),
      ],
    ),
  );
}

/// One task's precomputed mechanics and assignment/preparation presentation.
/// Source availability controls its appearance; a null callback also disables
/// a cached but otherwise available choice while the journal is navigating.
class OrganisationOrderTaskView extends StatelessWidget {
  const OrganisationOrderTaskView({
    super.key,
    required this.taskId,
    required this.type,
    required this.label,
    required this.shortcut,
    required this.enabled,
    required this.selected,
    required this.prepared,
    required this.tooltip,
    required this.summary,
    required this.factors,
    required this.cost,
    required this.unavailableReason,
    required this.compact,
    required this.showGuidance,
    this.onPrepare,
    this.categoryLabel,
  });

  final String? taskId;
  final ActivityType type;
  final String label;
  final String shortcut;
  final bool enabled;
  final bool selected;
  final bool prepared;
  final String tooltip;
  final String summary;
  final String factors;
  final String cost;
  final String? unavailableReason;
  final bool compact;
  final bool showGuidance;
  final VoidCallback? onPrepare;

  /// Search results open another source category; its keys are not active yet.
  final String? categoryLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: MechanicsTooltip(
        message: tooltip,
        maxWidth: 520,
        child: DecoratedBox(
          decoration: journalTabDecoration(
            selected: selected,
            enabled: enabled,
          ),
          child: TextButton(
            key: ValueKey('journal-activity:$taskId'),
            onPressed: onPrepare,
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: 8,
                vertical: compact ? 6 : 10,
              ),
              minimumSize: const Size(48, 48),
              shape: const RoundedRectangleBorder(),
            ),
            child: Semantics(
              label:
                  'Prepare $label${categoryLabel == null ? ' · Assign immediately with ${journalShortcutSpokenLabel(shortcut)}' : ' · $categoryLabel'}${selected
                      ? prepared
                            ? ' · Prepared, awaiting confirmation'
                            : ' · Currently assigned'
                      : ''}${!enabled ? ' · Unavailable${unavailableReason == null ? '' : ': $unavailableReason'}' : ''}',
              selected: selected,
              excludeSemantics: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) ...[
                    JournalOrderIcon(type: type, size: 28),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: JournalPalette.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: enabled
                                ? JournalPalette.ink
                                : JournalPalette.muted,
                          ),
                        ),
                        if (categoryLabel != null)
                          Text(categoryLabel!, style: JournalPalette.small),
                        Wrap(
                          spacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Text(
                              'Click: Prepare order',
                              style: JournalPalette.small,
                            ),
                            if (categoryLabel == null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Assign now: ',
                                    style: JournalPalette.small,
                                  ),
                                  JournalShortcutBadge(shortcut: shortcut),
                                ],
                              ),
                          ],
                        ),
                        if (selected)
                          Text(
                            prepared ? 'Prepared' : 'Currently assigned',
                            style: JournalPalette.small.copyWith(
                              color: prepared
                                  ? JournalPalette.binding
                                  : JournalPalette.olive,
                            ),
                          ),
                        if (factors.isNotEmpty)
                          Text('Uses: $factors', style: JournalPalette.small),
                        if (cost.isNotEmpty && cost != 'No activity fee')
                          Text('Cost: $cost', style: JournalPalette.small),
                        if (showGuidance && selected)
                          Text(summary, style: JournalPalette.small),
                        if (!enabled)
                          Text(
                            unavailableReason == null
                                ? 'Unavailable'
                                : 'Unavailable: $unavailableReason',
                            style: JournalPalette.small.copyWith(
                              color: JournalPalette.danger,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
