import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Detached display facts prepared by the journal, without gameplay authority.
@immutable
class OrganisationCrewMemberData {
  const OrganisationCrewMemberData({
    required this.personId,
    required this.name,
    required this.selected,
    required this.orderDescription,
    required this.location,
    required this.clothingSummary,
    required this.clothingWarning,
    required this.skillSummary,
    required this.weaponSummary,
    required this.hasAssignment,
    this.numberKey,
    this.injury,
  });

  final int personId;
  final String name;
  final bool selected;
  final String orderDescription;
  final String location;
  final String clothingSummary;
  final bool clothingWarning;
  final String skillSummary;
  final String weaponSummary;
  final bool hasAssignment;
  final String? numberKey;
  final ({String label, String details, bool urgent})? injury;
}

/// Roster layout and allocation affordances. The journal supplies live drop
/// eligibility and callbacks; the view never decides who can join a squad.
class OrganisationCrewRosterView extends StatelessWidget {
  const OrganisationCrewRosterView({
    super.key,
    required this.title,
    required this.rows,
    required this.showDone,
    required this.canAcceptPerson,
    required this.onTransfer,
    this.hint,
    this.onDone,
    this.showReorder = false,
    this.onReorder,
  });

  final String title;
  final List<OrganisationCrewMemberView> rows;
  final bool showDone;
  final bool Function(int personId) canAcceptPerson;
  final ValueChanged<int> onTransfer;
  final String? hint;
  final VoidCallback? onDone;
  final bool showReorder;
  final VoidCallback? onReorder;

  @override
  Widget build(BuildContext context) => DragTarget<int>(
    onWillAcceptWithDetails: (details) => canAcceptPerson(details.data),
    onAcceptWithDetails: (details) => onTransfer(details.data),
    builder: (context, candidates, rejected) => LayoutBuilder(
      builder: (context, bounds) => JournalSurface(
        lined: true,
        inset: true,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.attach_file,
                  size: 19,
                  color: JournalPalette.brassDark,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: JournalPalette.heading.copyWith(fontSize: 14),
                  ),
                ),
                if (showDone)
                  TextButton(onPressed: onDone, child: const Text('Done')),
                if (showReorder &&
                    bounds.maxHeight >= 112 &&
                    bounds.maxWidth >= 230)
                  Tooltip(
                    message:
                        'Change squad order and who leads. At headquarters: O.',
                    child: TextButton(
                      key: const ValueKey('journal-reorder-squad'),
                      onPressed: onReorder,
                      child: const Text('Reorder'),
                    ),
                  ),
              ],
            ),
            if (candidates.isNotEmpty)
              const Text(
                'Drop to add to this squad',
                style: JournalPalette.small,
              ),
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Text('Choose crew from the pool.'))
                  : ListView(
                      key: const ValueKey('journal-crew-list'),
                      children: rows,
                    ),
            ),
            if (hint != null) Text(hint!, style: JournalPalette.small),
          ],
        ),
      ),
    ),
  );
}

/// A roster row's presentation. Selection, draft resets, source routing and
/// allocation all remain in the journal/controller callbacks.
class OrganisationCrewMemberView extends StatelessWidget {
  const OrganisationCrewMemberView({
    super.key,
    required this.data,
    required this.showingOrders,
    required this.stacked,
    required this.allocating,
    required this.juiceBadge,
    required this.onInspect,
    this.onSelect,
    this.onRemove,
  });

  final OrganisationCrewMemberData data;
  final bool showingOrders;
  final bool stacked;
  final bool allocating;
  final Widget juiceBadge;
  final VoidCallback onInspect;
  final VoidCallback? onSelect;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final numberKey = data.numberKey;
    final injury = data.injury;
    final nameLabel = Text(
      data.name,
      key: ValueKey('journal-member-name:${data.personId}'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: JournalPalette.body.copyWith(
        fontSize: 13,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
    );
    final assignmentLabel = Tooltip(
      message:
          'Current order: ${data.orderDescription}\nLocation: ${data.location}\nStrongest skills: ${data.skillSummary}\nWeapon: ${data.weaponSummary}\nWearing: ${data.clothingSummary}',
      child: Text(
        data.orderDescription,
        key: ValueKey('journal-member-order:${data.personId}'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: JournalPalette.small.copyWith(
          fontSize: 11,
          height: 1.3,
          color: data.hasAssignment
              ? JournalPalette.olive
              : JournalPalette.small.color,
        ),
      ),
    );

    final row = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: data.selected ? JournalPalette.selected : null,
          border: Border(
            bottom: BorderSide(
              color: JournalPalette.rule.withValues(alpha: .4),
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (numberKey != null) ...[
              JournalShortcutBadge(shortcut: numberKey),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: TextButton(
                key: ValueKey('journal-member:${data.personId}'),
                onPressed: onSelect,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  minimumSize: const Size(24, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Semantics(
                  label:
                      'Select crew ${data.name}\nCurrent order: ${data.orderDescription}\nLocation: ${data.location}\nStrongest skills: ${data.skillSummary}\nWeapon: ${data.weaponSummary}\nWearing: ${data.clothingSummary}${injury == null ? '' : '\nCondition: ${injury.details}'}',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      nameLabel,
                      assignmentLabel,
                      Text(
                        'Top skills: ${data.skillSummary}',
                        key: ValueKey('journal-member-skills:${data.personId}'),
                        style: JournalPalette.small.copyWith(
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        children: [
                          Text(
                            'Weapon: ${data.weaponSummary}',
                            key: ValueKey(
                              'journal-member-weapon:${data.personId}',
                            ),
                            style: JournalPalette.small.copyWith(
                              fontSize: 11,
                              height: 1.3,
                            ),
                          ),
                          Tooltip(
                            message: 'Wearing: ${data.clothingSummary}',
                            child: Text(
                              'Clothes: ${data.clothingSummary}',
                              key: ValueKey(
                                'journal-member-clothing:${data.personId}',
                              ),
                              style: JournalPalette.small.copyWith(
                                fontSize: 11,
                                height: 1.3,
                                color: data.clothingWarning
                                    ? JournalPalette.danger
                                    : JournalPalette.small.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (injury != null)
                        Tooltip(
                          message: injury.details,
                          child: Row(
                            key: ValueKey(
                              'journal-member-injury:${data.personId}',
                            ),
                            children: [
                              Icon(
                                injury.label == 'Bleeding'
                                    ? Icons.bloodtype_outlined
                                    : Icons.healing,
                                size: 12,
                                color: injury.urgent
                                    ? JournalPalette.danger
                                    : JournalPalette.brassDark,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  injury.label,
                                  style: JournalPalette.small.copyWith(
                                    fontSize: 11,
                                    height: 1.3,
                                    fontWeight: FontWeight.w600,
                                    color: injury.urgent
                                        ? JournalPalette.danger
                                        : JournalPalette.brassDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (stacked) juiceBadge,
                    ],
                  ),
                ),
              ),
            ),
            if (!stacked) juiceBadge,
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                key: ValueKey('hq-dossier:${data.personId}'),
                tooltip: 'Dossier: ${data.name}',
                onPressed: onInspect,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(24, 24),
                ),
                icon: const Icon(Icons.person_search, size: 16),
              ),
            ),
            if (allocating)
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  key: ValueKey('journal-remove-member:${data.personId}'),
                  tooltip: 'Remove ${data.name} from this squad',
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(24, 24),
                  ),
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
    return allocating
        ? Draggable<int>(
            data: data.personId,
            feedback: Material(
              color: JournalPalette.selected,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(data.name, style: JournalPalette.body),
              ),
            ),
            childWhenDragging: Opacity(opacity: .4, child: row),
            child: row,
          )
        : row;
  }
}
