import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/recovery_context.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_person_summary.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// A journal page for the current source-authored care or legal decision.
/// Inspectors are read-only; controls retain their original action objects.
class JournalRecoveryView extends StatelessWidget {
  const JournalRecoveryView({
    super.key,
    required this.console,
    required this.onAction,
    this.onInspect,
  });

  final Console console;
  final ValueChanged<String> onAction;
  final ValueChanged<Creature>? onInspect;

  VoidCallback? _command(
    RecoveryContext frame,
    ConsoleAction action,
    int revision,
  ) => action.enabled
      ? () {
          if (recoveryActionIsCurrent(console, frame, action, revision)) {
            onAction(action.key);
          }
        }
      : null;

  List<String> _body(RecoveryContext frame) => [
    for (final row in frame.bodyRows)
      if (row >= 0 && row < console.height)
        console.buffer[row]
            .map((cell) => cell.glyph)
            .join()
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim(),
  ].where((line) => line.isNotEmpty).toList();

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: console.revision,
    builder: (context, _) {
      final frame = recoveryContext(console);
      if (frame == null) return const SizedBox.shrink();
      final revision = console.revision.value;
      final preferences = JournalPreferences.of(context);
      final personActions = {
        for (final summary in frame.people)
          summary: frame.actions
              .where(
                (action) =>
                    action.entityType == 'person' &&
                    action.entityId == summary.person.id.toString() &&
                    action.key == summary.choiceKey,
              )
              .firstOrNull,
      };
      return JournalSurface(
        key: const ValueKey('journal-recovery'),
        lined: true,
        padding: EdgeInsets.all(preferences.compact ? 8 : 12),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                frame.title,
                key: const ValueKey('journal-recovery-title'),
                style: JournalPalette.heading,
              ),
              const SizedBox(height: 6),
              Text(frame.note, style: JournalPalette.body),
              const Divider(height: 18),
              Expanded(
                child: ListView(
                  key: ValueKey('journal-recovery-scroll:${frame.scene.name}'),
                  children: [
                    for (final line in _body(frame))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(line, style: JournalPalette.body),
                      ),
                    for (final summary in frame.people)
                      Builder(
                        builder: (context) {
                          final action = personActions[summary];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: JournalPersonCard(
                              summary: summary,
                              onSelect: action == null
                                  ? null
                                  : _command(frame, action, revision),
                              onInspect: () {
                                if (onInspect != null) {
                                  onInspect!(summary.person);
                                } else {
                                  unawaited(
                                    showCrewDossier(
                                      context,
                                      person: summary.person,
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    if (preferences.showGuidance &&
                        frame.scene != RecoveryScene.defense)
                      const Text(
                        'Admission → treatment → discharge → squad reassignment',
                        style: JournalPalette.small,
                      ),
                    if (frame.details.isNotEmpty)
                      ExpansionTile(
                        key: const PageStorageKey(
                          'journal-recovery-case-details',
                        ),
                        title: Text(
                          frame.scene == RecoveryScene.defense
                              ? 'Case details'
                              : 'Care and next steps',
                        ),
                        children: [
                          for (final line in frame.details)
                            Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(line, style: JournalPalette.body),
                            ),
                        ],
                      ),
                    if (frame.people.isNotEmpty)
                      DecisionGuideButton(
                        topic: frame.scene == RecoveryScene.defense
                            ? DecisionTopic.heat
                            : DecisionTopic.health,
                        actor: frame.people.first.person,
                      ),
                  ],
                ),
              ),
              const Divider(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: journalCommandPanelMaxHeight(context),
                ),
                child: SingleChildScrollView(
                  child: FocusTraversalGroup(
                    policy: ReadingOrderTraversalPolicy(),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in frame.actions)
                          if (!personActions.containsValue(action))
                            OutlinedButton(
                              key: ValueKey(
                                'journal-recovery-action:${action.key}',
                              ),
                              onPressed: _command(frame, action, revision),
                              child: JournalCommandLabel(
                                shortcut: action.key,
                                label: action.intentLabel ?? action.label,
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
      );
    },
  );
}
