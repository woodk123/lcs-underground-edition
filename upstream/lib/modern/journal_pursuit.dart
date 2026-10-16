import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/pursuit_context.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_person_summary.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// The original pursuit reader in the journal. Only source-authored
/// controls can advance it; inspecting a crew member consumes no input.
class JournalPursuitView extends StatefulWidget {
  const JournalPursuitView({
    super.key,
    required this.console,
    required this.onAction,
  });

  final Console console;
  final ValueChanged<String> onAction;

  @override
  State<JournalPursuitView> createState() => _JournalPursuitViewState();
}

class _JournalPursuitViewState extends State<JournalPursuitView> {
  bool _inspecting = false;

  VoidCallback? _command(
    PursuitContext frame,
    ConsoleAction action,
    int revision,
  ) => action.enabled
      ? () {
          if (!_inspecting &&
              pursuitActionIsCurrent(widget.console, frame, action, revision)) {
            widget.onAction(action.key);
          }
        }
      : null;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.console.revision,
    builder: (context, _) {
      final frame = pursuitContext(widget.console);
      if (frame == null) return const SizedBox.shrink();
      final revision = widget.console.revision.value;
      final personActions = {
        for (final summary in frame.people)
          summary: frame.actions
              .where(
                (action) =>
                    action.entityType == 'person' &&
                    action.entityId == summary.person.id.toString(),
              )
              .firstOrNull,
      };
      return JournalSurface(
        key: const ValueKey('journal-pursuit'),
        lined: true,
        padding: const EdgeInsets.all(12),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(frame.title, style: JournalPalette.heading),
              Text(frame.location, style: JournalPalette.small),
              const SizedBox(height: 6),
              Text(frame.note, style: JournalPalette.body),
              const Divider(height: 18),
              Expanded(
                child: ListView(
                  key: const ValueKey('journal-pursuit-scroll'),
                  children: [
                    if (frame.statusLines.isNotEmpty)
                      Container(
                        key: const ValueKey('journal-pursuit-status'),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: JournalPalette.card,
                          border: Border.all(color: JournalPalette.rule),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final line in frame.statusLines)
                              Text(line, style: JournalPalette.body),
                          ],
                        ),
                      ),
                    for (final summary in frame.people)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: JournalPersonCard(
                          summary: summary,
                          onSelect: personActions[summary] == null
                              ? null
                              : _command(
                                  frame,
                                  personActions[summary]!,
                                  revision,
                                ),
                          onInspect: () async {
                            if (_inspecting ||
                                !identical(
                                  pursuitContext(widget.console),
                                  frame,
                                )) {
                              return;
                            }
                            setState(() => _inspecting = true);
                            try {
                              await showCrewDossier(
                                context,
                                person: summary.person,
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _inspecting = false);
                              }
                            }
                          },
                        ),
                      ),
                    if (frame.encounterLines.isNotEmpty) ...[
                      const Text('Pursuers', style: JournalPalette.heading),
                      const SizedBox(height: 6),
                      for (final line in frame.encounterLines)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(line, style: JournalPalette.body),
                        ),
                    ],
                    if (frame.people.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DecisionGuideButton(
                          topic: DecisionTopic.heat,
                          actor: frame.people.first.person,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 165),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in frame.actions)
                        if (!personActions.containsValue(action))
                          OutlinedButton(
                            key: ValueKey(
                              'journal-pursuit-action:${action.key}',
                            ),
                            onPressed: _command(frame, action, revision),
                            child: Text(action.intentLabel ?? action.label),
                          ),
                    ],
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
