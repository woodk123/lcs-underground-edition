import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/item_help_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/utils/colors.dart' as legacy;

const _ink = JournalPalette.ink;
const _muted = JournalPalette.muted;
const _teal = JournalPalette.olive;
const _red = JournalPalette.danger;
const _rule = JournalPalette.rule;
const _card = JournalPalette.card;

/// Presents engine-authored content as directly interactive management UI.
///
/// Coordinates describe the relationship between labels, values and columns;
/// only [ConsoleAction] supplies command identity and availability. The caller
/// owns vertical scrolling and rebuilds this widget on console revisions.
class DirectContent extends StatelessWidget {
  const DirectContent({
    super.key,
    required this.console,
    required this.onAction,
    this.onInspect,
    this.textInput,
    this.hiddenRows = const {},
    this.leadingActionRows = const {},
    this.maxColumn = CONSOLE_WIDTH,
  });

  final Console console;
  final ValueChanged<String> onAction;
  final ValueChanged<Creature>? onInspect;
  final bool? textInput;
  final Set<int> hiddenRows;
  final Set<int> leadingActionRows;
  final int maxColumn;

  @override
  Widget build(BuildContext context) {
    final assignment = console.actions
        .where(
          (action) => const {
            'activity-confirm',
            'sleeper-activity-confirm',
          }.contains(action.entityType),
        )
        .firstOrNull;
    final bulkSelection = console.actions
        .where(
          (action) => const {
            'bulk-activity-selected',
            'sleeper-bulk-selected',
          }.contains(action.entityType),
        )
        .firstOrNull;
    final actor = assignment == null ? null : _activityActor(assignment);
    final selection = assignment ?? bulkSelection;
    final activity = selection == null
        ? null
        : activityTypeForAction(selection);
    final help = selection == null
        ? null
        : selection.entityType == 'bulk-activity-selected'
        ? bulkActivityMechanics(selection.entityId)
        : activity == null
        ? null
        : activityMechanics(
            activity,
            actor: actor,
            activity: actor?.activity,
            sleeper: selection.entityType?.startsWith('sleeper-') == true
                ? true
                : null,
          );
    final omittedRows = {
      ...hiddenRows,
      if (assignment != null && help != null) ...[22, 23, 24],
      if (assignment != null && actor != null && help != null)
        for (var row = 0; row < 10; row++) row,
    };
    final frame = _ContentFrame(console, omittedRows, maxColumn);
    final content = <Widget>[];
    final guideActor =
        actor ?? game.activeSquadMember ?? game.squad.firstOrNull;
    final guideTopics = <DecisionTopic>{
      if (console.navigation?.section == 'equipment') ...[
        DecisionTopic.weapons,
        DecisionTopic.clothing,
      ],
      if (console.navigation?.section == 'vehicles') DecisionTopic.vehicles,
      if (console.actions.any((a) => a.entityType == 'compound-upgrade'))
        DecisionTopic.upgrades,
      if (help != null) ...[
        DecisionTopic.availability,
        DecisionTopic.recruitment,
      ],
    };
    if (guideTopics.isNotEmpty && assignment == null) {
      content.add(
        Wrap(
          children: [
            for (final topic in guideTopics)
              DecisionGuideButton(topic: topic, actor: guideActor),
          ],
        ),
      );
    }
    final used = <ConsoleAction>{};
    if (leadingActionRows.isNotEmpty) {
      final commands = console.actions
          .where((action) => leadingActionRows.contains(action.y))
          .toList();
      content.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final action in commands)
                _choice(
                  context,
                  frame,
                  action,
                  const [],
                  compact: true,
                  dense: true,
                ),
            ],
          ),
        ),
      );
      used.addAll(commands);
    }
    if (assignment != null && actor != null && help != null) {
      used.add(assignment);
      content.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CrewPortrait(person: actor, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        actor.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${actor.title} · ${actor.blood}/${actor.maxBlood} blood',
                        style: const TextStyle(fontSize: 12, color: _muted),
                      ),
                      if (actor.income > 0)
                        Text(
                          'Earned \$${actor.income} yesterday',
                          style: const TextStyle(fontSize: 12, color: _teal),
                        ),
                    ],
                  ),
                ),
                _choice(context, frame, assignment, const [], compact: true),
              ],
            ),
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: const ValueKey('assignment-person-details'),
                tilePadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                title: const Text(
                  'Equipment, attributes & skills',
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                children: [_report(frame, 1, 9)],
              ),
            ),
          ],
        ),
      );
    }
    final notes = <String>[];
    if (guideTopics.isNotEmpty && assignment != null) {
      content.add(
        Wrap(
          children: [
            for (final topic in guideTopics)
              DecisionGuideButton(topic: topic, actor: guideActor),
          ],
        ),
      );
    }
    var needsAssignmentHelp = help != null;
    var y = 0;
    while (y < frame.rows.length) {
      if (omittedRows.contains(y) ||
          leadingActionRows.contains(y) ||
          frame.rows[y].trim().isEmpty) {
        y++;
        continue;
      }
      final columns = frame.columnsAt(y);
      if (columns.length > 1) {
        final records = <int>[];
        var next = y + 1;
        while (next < frame.rows.length && !omittedRows.contains(next)) {
          final actions = frame.at(next).where(frame.embedded).toList();
          if (frame.rows[next].trim().isEmpty ||
              frame.isRule(next) ||
              actions.length > 1 ||
              !columns
                  .skip(1)
                  .any(
                    (column) => frame
                        .slice(next, column.start, column.end)
                        .trim()
                        .isNotEmpty,
                  )) {
            break;
          }
          records.add(next++);
        }
        if (records.isNotEmpty) {
          content.add(_table(context, frame, columns, records));
          for (final row in records) {
            used.addAll(frame.at(row).where(frame.embedded));
          }
          y = next;
          continue;
        }
      }
      if (frame.isRule(y)) {
        y++;
        continue;
      }
      final actions = frame.at(y).where(frame.embedded).toList();
      if (actions.isNotEmpty) {
        if (needsAssignmentHelp) {
          content.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActivityMechanicsPanel(
                mechanics: help!,
                assignment: assignment != null,
                bulk: bulkSelection != null,
              ),
            ),
          );
          needsAssignmentHelp = false;
        }
        var end = y;
        while (end + 1 < frame.rows.length &&
            !omittedRows.contains(end + 1) &&
            frame.rows[end + 1].trim().isNotEmpty &&
            !frame.isRule(end + 1)) {
          end++;
        }
        final cluster = frame.actions
            .where(
              (action) =>
                  action.y >= y && action.y <= end && frame.embedded(action),
            )
            .where((action) => !used.contains(action))
            .toList();
        content.add(_choices(context, frame, cluster, y, end));
        used.addAll(cluster);
        y = end + 1;
        continue;
      }
      final line = frame.rows[y].trim();
      if (_isKeyboardNote(line)) {
        notes.add(line);
        y++;
        continue;
      }
      final start = y;
      var end = y;
      while (end + 1 < frame.rows.length &&
          !omittedRows.contains(end + 1) &&
          frame.rows[end + 1].trim().isNotEmpty &&
          !frame.isRule(end + 1) &&
          frame.columnsAt(end + 1).length < 2 &&
          !frame.at(end + 1).any(frame.embedded) &&
          !_isKeyboardNote(frame.rows[end + 1].trim())) {
        end++;
      }
      content.add(_report(frame, start, end));
      y = end + 1;
    }
    final remaining = frame.actions
        .where((action) => !used.contains(action))
        .toList();
    if (remaining.isNotEmpty) {
      content.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final action in remaining)
                _choice(context, frame, action, const [], compact: true),
            ],
          ),
        ),
      );
    }
    if (notes.isNotEmpty) {
      content.add(
        Material(
          color: Colors.transparent,
          child: ExpansionTile(
            key: const ValueKey('direct-keyboard-notes'),
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'Keyboard & game notes',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    notes.join('\n'),
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return DefaultTextStyle.merge(
      style: TextStyle(
        fontFamily:
            Theme.of(context).textTheme.bodyMedium?.fontFamily ?? 'ModernSans',
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 15,
        height: 1.45,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < content.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            content[i],
          ],
        ],
      ),
    );
  }

  Widget _table(
    BuildContext context,
    _ContentFrame frame,
    List<_Column> columns,
    List<int> records,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final y in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _record(context, frame, columns, y, compact: true),
                ),
            ],
          );
        }
        return Container(
          key: const ValueKey('direct-data-table'),
          decoration: BoxDecoration(
            border: Border.all(color: _rule),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: JournalPalette.inset,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    if (records.any(
                      (y) =>
                          frame.at(y).any((action) => _person(action) != null),
                    ))
                      const SizedBox(width: 64),
                    for (final column in columns)
                      Expanded(
                        flex: column.end - column.start,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                            _sentenceCase(column.label),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _muted,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(width: 22),
                  ],
                ),
              ),
              for (var i = 0; i < records.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: _rule),
                _record(context, frame, columns, records[i]),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _record(
    BuildContext context,
    _ContentFrame frame,
    List<_Column> columns,
    int y, {
    bool compact = false,
  }) {
    final actions = frame.at(y).where(frame.embedded).toList();
    final action = actions.isEmpty ? null : actions.first;
    final title = action == null
        ? frame.slice(y, columns.first.start, columns.first.end).trim()
        : _title(action);
    Widget value(_Column column) {
      final spans = frame.spans(y, column.start, column.end, trim: true);
      if (column.label.contains('ACTIVITY') || column.label == 'HEALTH') {
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: .075),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text.rich(
              TextSpan(children: spans),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        );
      }
      final text = Text.rich(
        TextSpan(children: spans),
        style: const TextStyle(fontSize: 14, height: 1.4),
      );
      if (game.mode == GameMode.site && column.label == 'SKILL') {
        return Tooltip(
          message: 'Total learned skill levels / equipped weapon skill.',
          child: text,
        );
      }
      return text;
    }

    final identity = Row(
      children: [
        if (action != null) ...[
          _shortcut(action.key),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
    final body = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              identity,
              if (action?.intentLabel != null) ...[
                const SizedBox(height: 8),
                Text(
                  action!.intentLabel!,
                  style: const TextStyle(
                    color: _red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, bounds) {
                  final count = bounds.maxWidth >= 250 ? 2 : 1;
                  final fieldWidth =
                      (bounds.maxWidth - 22 * (count - 1)) / count;
                  return Wrap(
                    spacing: 22,
                    runSpacing: 12,
                    children: [
                      for (final column in columns.skip(1))
                        SizedBox(
                          width: fieldWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _sentenceCase(column.label),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              value(column),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          )
        : Row(
            children: [
              Expanded(
                flex: columns.first.end - columns.first.start,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: identity,
                ),
              ),
              for (final column in columns.skip(1))
                Expanded(
                  flex: column.end - column.start,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: value(column),
                  ),
                ),
              if (action?.intentLabel != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    action!.intentLabel!,
                    style: const TextStyle(
                      color: _red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Icon(
                action == null ? Icons.horizontal_rule : Icons.chevron_right,
                size: 22,
                color: action?.enabled == true ? _teal : _muted,
              ),
            ],
          );
    if (action == null) {
      return Padding(padding: const EdgeInsets.all(18), child: body);
    }
    return _withDossier(
      context,
      action,
      _interactive(
        context,
        frame,
        action,
        body,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: compact,
        description: columns
            .skip(1)
            .map(
              (column) =>
                  '${_sentenceCase(column.label)}: ${frame.slice(y, column.start, column.end).trim()}',
            )
            .join('. '),
      ),
    );
  }

  Widget _choices(
    BuildContext context,
    _ContentFrame frame,
    List<ConsoleAction> actions,
    int start,
    int end,
  ) {
    if (actions.any(_isActivityCategory) &&
        frame.actions.any(
          (action) => const {
            'activity-confirm',
            'sleeper-activity-confirm',
          }.contains(action.entityType),
        )) {
      return _assignmentChoices(context, frame, actions);
    }
    if (start >= 22) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final action in actions)
            _choice(context, frame, action, const [], compact: true),
        ],
      );
    }
    final origins = actions.map((action) => action.x).toSet().toList()..sort();
    // The original two/three-column menus carry independent lists. Retain that
    // relationship rather than interleaving a category with an unrelated task.
    final split = origins.length > 1 && origins.last - origins.first >= 20;
    if (!split) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final count = constraints.maxWidth >= 1000
              ? 3
              : constraints.maxWidth >= 600
              ? 2
              : 1;
          final width = (constraints.maxWidth - (count - 1) * 12) / count;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < actions.length; i++)
                SizedBox(
                  width: width,
                  child: _choice(
                    context,
                    frame,
                    actions[i],
                    frame.details(
                      actions[i],
                      0,
                      frame.width,
                      i + 1 < actions.length ? actions[i + 1].y : end + 1,
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }
    final groups = <Widget>[];
    for (var i = 0; i < origins.length; i++) {
      final left = i == 0 ? 0 : origins[i];
      final right = i + 1 < origins.length ? origins[i + 1] : frame.width;
      final columnActions = actions
          .where((action) => action.x == origins[i])
          .toList();
      groups.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (columnActions.first.y > start)
              _report(
                frame,
                start,
                columnActions.first.y - 1,
                left: left,
                right: right,
                maskActions: true,
              ),
            for (var a = 0; a < columnActions.length; a++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _choice(
                  context,
                  frame,
                  columnActions[a],
                  frame.details(
                    columnActions[a],
                    left,
                    right,
                    a + 1 < columnActions.length
                        ? columnActions[a + 1].y
                        : end + 1,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                groups[i],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < groups.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: groups[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _assignmentChoices(
    BuildContext context,
    _ContentFrame frame,
    List<ConsoleAction> actions,
  ) {
    final groups = actions.where(_isActivityCategory).toList();
    final tasks = actions
        .where(
          (action) =>
              activityTypeForAction(action) != null &&
              !action.entityType!.endsWith('-confirm') &&
              action.x >= 40,
        )
        .toList();
    final utilities = actions
        .where((action) => !groups.contains(action) && !tasks.contains(action))
        .toList();
    final selectedGroup = groups
        .where(
          (action) =>
              action.entityType == 'sleeper-category-selected' ||
              frame.selected(action),
        )
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final group in groups)
              Tooltip(
                message: activityCategorySummary(group.entityId) ?? '',
                child: _choice(context, frame, group, const [], compact: true),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            '${selectedGroup == null ? 'Choose a group of tasks.' : activityCategorySummary(selectedGroup.entityId)} '
            'Opening a group may choose a suggested task.',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ),
        if (tasks.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 540
                  ? 2
                  : 1;
              final width = (constraints.maxWidth - (count - 1) * 10) / count;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final task in tasks)
                    SizedBox(
                      width: width,
                      child: _choice(context, frame, task, const []),
                    ),
                ],
              );
            },
          ),
        if (tasks.isNotEmpty) const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final action in utilities)
              _choice(context, frame, action, const [], compact: true),
          ],
        ),
      ],
    );
  }

  Widget _choice(
    BuildContext context,
    _ContentFrame frame,
    ConsoleAction action,
    List<_Detail> details, {
    bool compact = false,
    bool dense = false,
  }) {
    final activityType = activityTypeForAction(action);
    final activityActor = _activityActor(action);
    final bulk = action.entityType?.contains('bulk') == true;
    final selected =
        frame.selected(action) ||
        action.entityType?.endsWith('-selected') == true ||
        (!bulk &&
            activityType != null &&
            action.entityType?.endsWith('-confirm') != true &&
            activityActor?.activity.type == activityType);
    final mechanics = action.entityType?.startsWith('bulk-activity') == true
        ? bulkActivityMechanics(action.entityId)
        : activityType != null &&
              action.entityType?.endsWith('-confirm') != true
        ? activityMechanics(
            activityType,
            actor: activityActor,
            sleeper: action.entityType?.startsWith('sleeper-') == true
                ? true
                : null,
          )
        : null;
    final category = _isActivityCategory(action)
        ? activityCategorySummary(action.entityId)
        : null;
    final explanation = mechanics?.summary ?? category;
    final disabledReason = !action.enabled
        ? mechanics?.unavailableReason ?? mechanics?.requirements
        : null;
    final primary =
        action.key == 'Enter' && !_title(action).toLowerCase().contains('back');
    final control = _interactive(
      context,
      frame,
      action,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _shortcut(action.key, primary: primary),
              SizedBox(width: dense ? 6 : 12),
              if (compact)
                Flexible(
                  child: Text(
                    _title(action),
                    style: TextStyle(
                      fontSize: dense ? 11 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    _title(action),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              SizedBox(width: dense ? 4 : 10),
              Icon(
                selected ? Icons.check_circle : Icons.chevron_right,
                size: dense ? 13 : 19,
                color: primary
                    ? Colors.white
                    : selected
                    ? _teal
                    : _muted,
              ),
            ],
          ),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 5),
              child: Text(
                mechanics == null
                    ? 'Selected'
                    : bulk
                    ? 'Selected bulk task'
                    : action.entityType?.startsWith('sleeper-') == true &&
                          activityType != ActivityType.sleeperJoinLcs
                    ? 'Assigned · month end'
                    : 'Assigned · next day',
                style: TextStyle(
                  fontSize: 11,
                  color: primary ? Colors.white70 : _teal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (!compact && explanation != null)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 6),
              child: Text(
                explanation,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: primary ? Colors.white70 : _muted,
                ),
              ),
            ),
          if (disabledReason?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 5),
              child: Text(
                disabledReason!,
                style: const TextStyle(
                  fontSize: 12,
                  color: _red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          for (final detail in details)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 40),
              child: Text.rich(
                TextSpan(children: detail.spans),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: primary ? Colors.white70 : _muted,
                ),
              ),
            ),
        ],
      ),
      primary: primary,
      selected: selected,
      border: true,
      dense: dense,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 16,
        vertical: dense
            ? 6
            : compact
            ? 12
            : 17,
      ),
      description: [
        if (explanation != null) explanation,
        if (disabledReason?.isNotEmpty == true) disabledReason!,
        ...details.map((detail) => detail.text),
      ].join('. '),
    );
    final inspectedItem = choiceItem(action);
    if (action.entityType == 'compound-upgrade') {
      final upgrade = CompoundUpgrade.values
          .where((u) => u.name == action.entityId)
          .firstOrNull;
      final site = game.sites
          .where((s) => s.idString == action.entityCategory)
          .firstOrNull;
      if (upgrade != null) {
        return Row(
          children: [
            Expanded(
              child: MechanicsTooltip(
                message: compoundUpgradeHelp(upgrade, site),
                excludeFromSemantics: true,
                child: control,
              ),
            ),
            DecisionGuideButton(
              topic: DecisionTopic.upgrades,
              site: site,
              compact: true,
              label: 'Inspect ${upgrade.name} upgrade',
            ),
          ],
        );
      }
    }
    final inspectedVehicle = choiceVehicle(action);
    if (inspectedItem is Weapon ||
        inspectedItem is Ammo ||
        inspectedItem is Clothing ||
        inspectedVehicle != null) {
      final topic = inspectedVehicle != null
          ? DecisionTopic.vehicles
          : inspectedItem is Weapon || inspectedItem is Ammo
          ? DecisionTopic.weapons
          : DecisionTopic.clothing;
      final actor = game.activeSquadMember ?? game.squad.firstOrNull;
      final preview = inspectedItem is Ammo
          ? ammoHelp(inspectedItem)
          : inspectedItem is Weapon
          ? weaponHelp(inspectedItem.type, actor: actor)
          : inspectedItem is Clothing
          ? clothingHelp(
              inspectedItem.type,
              actual: inspectedItem,
              actor: actor,
            )
          : vehicleHelp(inspectedVehicle!.type, actor: actor);
      return Row(
        children: [
          Expanded(
            child: MechanicsTooltip(
              message: preview.split('\n\n').take(2).join('\n\n'),
              excludeFromSemantics: true,
              child: control,
            ),
          ),
          DecisionGuideButton(
            topic: topic,
            actor: actor,
            compact: true,
            item: inspectedItem,
            label:
                'Inspect ${inspectedItem?.type.name ?? inspectedVehicle!.fullName()}',
            itemType: inspectedVehicle?.typeName ?? inspectedItem?.typeName,
          ),
        ],
      );
    }
    return _withDossier(context, action, control);
  }

  Creature? _activityActor(ConsoleAction action) {
    final id = int.tryParse(action.entityCategory ?? '');
    if (id == null) return null;
    for (final person in game.pool) {
      if (person.id == id) return person;
    }
    return null;
  }

  Creature? _person(ConsoleAction action) {
    if (action.entityType != 'person') return null;
    final id = int.tryParse(action.entityId ?? '');
    if (id == null) return null;
    for (final person in game.pool) {
      if (person.id == id) return person;
    }
    return null;
  }

  Widget _withDossier(
    BuildContext context,
    ConsoleAction action,
    Widget control,
  ) {
    final person = _person(action);
    if (person == null) return control;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Semantics(
            label: 'Inspect ${person.name} dossier',
            button: true,
            child: ExcludeSemantics(
              child: Tooltip(
                message: 'Inspect ${person.name}',
                child: TextButton(
                  key: ValueKey(
                    'direct-dossier:${action.y}:${action.x}:${person.id}',
                  ),
                  onPressed: () {
                    if (onInspect != null) {
                      onInspect!(person);
                    } else {
                      unawaited(showCrewDossier(context, person: person));
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(60, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: CrewPortrait(person: person, size: 46),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: control),
      ],
    );
  }

  Widget _interactive(
    BuildContext context,
    _ContentFrame frame,
    ConsoleAction action,
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(16),
    bool primary = false,
    bool selected = false,
    bool border = false,
    bool dense = false,
    String description = '',
  }) {
    void activate() {
      if (console.revision.value == frame.revision &&
          action.enabled &&
          console.actions.any((current) => identical(current, action))) {
        onAction(action.key);
      }
    }

    final enabled = action.enabled;
    return Semantics(
      key: ValueKey('direct-action:${action.y}:${action.x}:${action.key}'),
      container: true,
      button: true,
      enabled: enabled,
      selected: selected,
      label:
          '${_spokenKey(action.key)} ${_title(action)}${action.intentLabel == null ? '' : ' · ${action.intentLabel}'}',
      value: description.isEmpty ? null : description,
      onTap: enabled ? activate : null,
      child: ExcludeSemantics(
        child: TextButton(
          onPressed: enabled ? activate : null,
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            minimumSize: Size(44, dense ? 36 : 52),
            padding: padding,
            foregroundColor: primary ? Colors.white : _ink,
            disabledForegroundColor: _muted,
            backgroundColor: !enabled
                ? JournalPalette.inset
                : primary
                ? _red
                : selected
                ? JournalPalette.selected
                : _card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(border ? 7 : 0),
              side: border
                  ? BorderSide(
                      color: selected ? _teal : _rule,
                      width: selected ? 1.5 : 1,
                    )
                  : BorderSide.none,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _report(
    _ContentFrame frame,
    int start,
    int end, {
    int left = 0,
    int? right,
    bool maskActions = false,
  }) {
    final lines = <Widget>[];
    for (var y = start; y <= end; y++) {
      var row = frame.rows[y];
      if (maskActions) {
        for (final action in frame.at(y).where(frame.embedded)) {
          final actionEnd = math.min(frame.width, action.x + action.width);
          row = row.replaceRange(
            action.x,
            actionEnd,
            ' ' * (actionEnd - action.x),
          );
        }
      }
      final clean = row
          .substring(left, right ?? frame.width)
          .replaceAllMapped(
            RegExp(r'[—═─━]{3,}'),
            (match) => ' ' * match.group(0)!.length,
          );
      final fragments = RegExp(
        r'\S(?:.*?\S)?(?=\s{2,}|\s*$)',
      ).allMatches(clean).toList();
      if (fragments.isEmpty) continue;
      lines.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 22,
            runSpacing: 8,
            children: [
              for (final fragment in fragments)
                Text.rich(
                  TextSpan(
                    children: frame.spans(
                      y,
                      fragment.start + left,
                      fragment.end + left,
                      trim: true,
                    ),
                  ),
                  style: const TextStyle(fontSize: 15, height: 1.5),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  Widget _shortcut(String key, {bool primary = false}) => Container(
    constraints: const BoxConstraints(minWidth: 27),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: primary
          ? Colors.white.withValues(alpha: .15)
          : _ink.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      _visualKey(key),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: primary ? Colors.white : _muted,
      ),
    ),
  );
}

class _ContentFrame {
  _ContentFrame(this.console, Set<int> hiddenRows, int maxColumn)
    : width = maxColumn.clamp(1, console.width),
      revision = console.revision.value {
    rows = [
      for (final row in console.buffer)
        row.take(width).map((cell) => cell.glyph).join(),
    ];
    final indices = {
      for (var i = 0; i < console.actions.length; i++) console.actions[i]: i,
    };
    actions =
        console.actions
            .where(
              (action) =>
                  !hiddenRows.contains(action.y) &&
                  action.x < width &&
                  action.y >= 0 &&
                  action.y < rows.length,
            )
            .toList()
          ..sort((a, b) {
            final order = a.y.compareTo(b.y);
            if (order != 0) return order;
            final horizontal = a.x.compareTo(b.x);
            return horizontal == 0
                ? indices[a]!.compareTo(indices[b]!)
                : horizontal;
          });
  }
  final Console console;
  final int width;
  final int revision;
  late final List<String> rows;
  late final List<ConsoleAction> actions;

  List<ConsoleAction> at(int y) =>
      actions.where((action) => action.y == y).toList();
  String slice(int y, int start, int end) => rows[y].substring(
    start.clamp(0, width),
    end.clamp(start.clamp(0, width), width),
  );
  bool isRule(int y) => RegExp(r'^[\s—═─━=░▒▓█▀▄▌▐]+$').hasMatch(rows[y]);

  bool embedded(ConsoleAction action) {
    final length = math.min(12, math.min(action.width, action.label.length));
    return length > 0 &&
        slice(action.y, action.x, action.x + length) ==
            action.label.substring(0, length);
  }

  bool selected(ConsoleAction action) {
    if (!embedded(action)) return false;
    // The engine marks the actual selected activity with its cyan base color.
    // Ignore the blue shortcut character that appears on every available item.
    final end = math.min(width, action.x + action.width);
    return console.buffer[action.y]
        .sublist(action.x.clamp(0, width), end)
        .where((cell) => cell.glyph.trim().isNotEmpty)
        .any((cell) => cell.foreground == legacy.lightBlue);
  }

  List<_Column> columnsAt(int y) {
    final row = rows[y];
    if (!RegExp(r'[—═─━]{3}').hasMatch(row)) return const [];
    final labels = RegExp(r'[^\s—═─━][^—═─━]*')
        .allMatches(row)
        .where((match) => RegExp(r'[A-Za-z]').hasMatch(match.group(0)!))
        .toList();
    if (labels.length < 2) return const [];
    return [
      for (var i = 0; i < labels.length; i++)
        _Column(
          labels[i].group(0)!.trim(),
          i == 0 ? 0 : labels[i].start,
          i + 1 < labels.length ? labels[i + 1].start : width,
        ),
    ];
  }

  List<InlineSpan> spans(int y, int start, int end, {bool trim = false}) {
    var left = start.clamp(0, width);
    var right = end.clamp(left, width);
    if (trim) {
      while (left < right && rows[y][left].trim().isEmpty) {
        left++;
      }
      while (right > left && rows[y][right - 1].trim().isEmpty) {
        right--;
      }
    }
    final spans = <InlineSpan>[];
    var run = '';
    Color? foreground;
    Color? background;
    void append() {
      if (run.isNotEmpty) {
        spans.add(
          TextSpan(
            text: run,
            style: TextStyle(color: foreground, backgroundColor: background),
          ),
        );
      }
      run = '';
    }

    for (var x = left; x < right; x++) {
      final cell = console.buffer[y][x];
      final color = _readableColor(cell.foreground);
      final bg = cell.background == legacy.black
          ? null
          : _readableColor(cell.background).withValues(alpha: .15);
      if (foreground != color || background != bg) append();
      foreground = color;
      background = bg;
      run += cell.glyph;
    }
    append();
    return spans;
  }

  List<_Detail> details(ConsoleAction action, int left, int right, int endY) {
    final details = <_Detail>[];
    for (var y = action.y; y < endY && y < rows.length; y++) {
      final ranges = <(int, int)>[];
      if (y == action.y) {
        if (action.x > left) ranges.add((left, action.x));
        if (action.x + action.width < right) {
          ranges.add((action.x + action.width, right));
        }
      } else {
        ranges.add((left, right));
      }
      for (final (start, end) in ranges) {
        final text = slice(y, start, end).trim();
        if (text.isNotEmpty && !RegExp(r'^[—═─━=\s]+$').hasMatch(text)) {
          details.add(_Detail(text, spans(y, start, end, trim: true)));
        }
      }
    }
    return details;
  }
}

class _Column {
  const _Column(this.label, this.start, this.end);
  final String label;
  final int start;
  final int end;
}

class _Detail {
  const _Detail(this.text, this.spans);
  final String text;
  final List<InlineSpan> spans;
}

String _title(ConsoleAction action) {
  if (const {
    'activity-confirm',
    'sleeper-activity-confirm',
  }.contains(action.entityType)) {
    return 'Done';
  }
  final label = stripConsoleColors(action.label).trim();
  final prefix = RegExp(r'^\(?[A-Za-z0-9?\[\]]+\s*[-–:]\s*');
  var title = label.replaceFirst(prefix, '').trim();
  if (RegExp(r'^\d$').hasMatch(action.key)) {
    title = title.replaceFirst(RegExp('^${RegExp.escape(action.key)}\\s+'), '');
  }
  return title;
}

bool _isActivityCategory(ConsoleAction action) => const {
  'activity-category',
  'sleeper-category',
  'sleeper-category-selected',
}.contains(action.entityType);

String _spokenKey(String key) => key.length == 1 ? key.toUpperCase() : key;
String _visualKey(String key) => switch (key) {
  'Enter' => '↵',
  'Escape' => 'Esc',
  'PageUp' => '[',
  'PageDown' => ']',
  'Up' => '↑',
  'Down' => '↓',
  'Left' => '←',
  'Right' => '→',
  _ => _spokenKey(key),
};
String _sentenceCase(String text) => text.isEmpty
    ? text
    : text[0].toUpperCase() + text.substring(1).toLowerCase();
bool _isKeyboardNote(String text) => RegExp(
  r'^(Press |Capitalize |Any [Oo]ther [Kk]ey|[Ww],\s*[Aa],)',
).hasMatch(text);
Color _readableColor(Color color) {
  if (color == legacy.red || color == legacy.darkRed) return _red;
  if (color == legacy.orange ||
      color == legacy.yellow ||
      color == legacy.halfYellow ||
      color == legacy.brown) {
    return const Color(0xFF8F6421);
  }
  if (color == legacy.green ||
      color == legacy.lightGreen ||
      color == legacy.lightBlue) {
    return _teal;
  }
  if (color == legacy.blue || color == legacy.darkBlue) {
    return const Color(0xFF315B7A);
  }
  if (color == legacy.purple || color == legacy.pink) {
    return const Color(0xFF805777);
  }
  if (color == legacy.darkGray || color == legacy.midGray) return _muted;
  return _ink;
}
