import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';

@immutable
class BulkOrderPerson {
  const BulkOrderPerson({
    required this.action,
    required this.name,
    required this.order,
  });
  final ConsoleAction action;
  final String name, order;
}

/// Source choices remain authoritative; the two lists only present the current
/// task and people together. Selecting a person applies the original order now.
class JournalBulkOrdersView extends StatelessWidget {
  const JournalBulkOrdersView({
    super.key,
    required this.title,
    required this.tasks,
    required this.people,
    required this.pages,
    required this.selected,
    required this.help,
    required this.onAction,
    required this.onBack,
    required this.onDetails,
  });
  final String title;
  final List<ConsoleAction> tasks, pages;
  final List<BulkOrderPerson> people;
  final ConsoleAction selected;
  final ActivityMechanics? help;
  final ValueChanged<ConsoleAction> onAction;
  final VoidCallback onBack, onDetails;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      key: const ValueKey('journal-bulk-orders-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: JournalPalette.heading)),
            TextButton.icon(
              key: const ValueKey('bulk-orders-back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, size: 17),
              label: const JournalCommandLabel(
                shortcut: 'Escape',
                label: 'Back',
              ),
            ),
          ],
        ),
        const Text(
          'Choose a task, then select each person to apply it immediately. '
          'Back keeps applied orders. No time passes here.',
          style: JournalPalette.small,
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: JournalPalette.inset,
            border: Border.all(color: JournalPalette.rule),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Selected: ${help?.title ?? _label(selected)}',
                        style: JournalPalette.heading.copyWith(fontSize: 14),
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('bulk-orders-details'),
                      onPressed: help == null ? null : onDetails,
                      icon: const Icon(Icons.info_outline, size: 17),
                      label: const Text('Details'),
                    ),
                  ],
                ),
                if (help case final mechanics?) ...[
                  if (mechanics.cost.isNotEmpty)
                    Text(
                      'Cost: ${mechanics.cost}',
                      style: JournalPalette.small,
                    ),
                  if (mechanics.requirements.isNotEmpty)
                    Text(
                      'Needs: ${mechanics.requirements}',
                      style: JournalPalette.small,
                    ),
                  if (mechanics.risk.isNotEmpty)
                    Text(
                      mechanics.risk,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                  Text(mechanics.timing, style: JournalPalette.small),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '1. Choose a task',
                      style: JournalPalette.heading,
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: ListView(
                        key: PageStorageKey('bulk-orders-task-list:$title'),
                        children: [
                          for (final action in tasks)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: OutlinedButton(
                                key: ValueKey('bulk-task:${action.key}'),
                                onPressed: action.enabled
                                    ? () => onAction(action)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: identical(action, selected)
                                      ? JournalPalette.selected
                                      : JournalPalette.card,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  alignment: Alignment.centerLeft,
                                ),
                                child: JournalCommandLabel(
                                  shortcut: action.key,
                                  label: _label(action),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '2. Apply to people',
                      style: JournalPalette.heading,
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: ListView(
                        key: PageStorageKey(
                          'bulk-orders-people-list:$title:${people.firstOrNull?.action.entityId}',
                        ),
                        children: [
                          for (final person in people)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 5),
                              child: OutlinedButton(
                                key: ValueKey(
                                  'bulk-person:${person.action.entityId}',
                                ),
                                onPressed: person.action.enabled
                                    ? () => onAction(person.action)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: JournalPalette.card,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  alignment: Alignment.centerLeft,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    JournalCommandLabel(
                                      shortcut: person.action.key,
                                      label: person.name,
                                    ),
                                    Text(
                                      'Current: ${person.order}',
                                      style: JournalPalette.small,
                                    ),
                                    if (!person.action.enabled &&
                                        person.action.intentLabel != null)
                                      Text(
                                        person.action.intentLabel!,
                                        style: JournalPalette.small.copyWith(
                                          color: JournalPalette.danger,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (pages.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final action in pages)
                            TextButton(
                              key: ValueKey('bulk-page:${action.key}'),
                              onPressed: action.enabled
                                  ? () => onAction(action)
                                  : null,
                              child: JournalCommandLabel(
                                shortcut: action.key,
                                label: _label(action),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _label(ConsoleAction action) =>
      stripConsoleColors(action.label)
          .replaceFirst(RegExp(r'^\S+\s*-\s*'), '')
          .trim();
}
