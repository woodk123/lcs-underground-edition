import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Field spread layout only. The shell supplies the current reader's widgets
/// and owns action revisions, input, inspection and the report scroll lifetime.
class JournalFieldOperationView extends StatelessWidget {
  const JournalFieldOperationView({
    super.key,
    required this.narrow,
    required this.maxHeight,
    required this.reportScrollController,
    required this.map,
    required this.heading,
    required this.body,
    required this.movement,
    this.actorStatus,
    this.crew,
    this.choices,
    this.input,
  });

  final bool narrow;
  final double maxHeight;
  final ScrollController reportScrollController;
  final Widget map, heading, body, movement;
  final Widget? actorStatus, crew, choices, input;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: narrow ? 3 : 5, child: map),
            JournalBinding(width: narrow ? 16 : 26),
            Expanded(
              flex: narrow ? 2 : 3,
              child: JournalSurface(
                key: const ValueKey('journal-operation-report'),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: reportScrollController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: reportScrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: heading),
                                  ?actorStatus,
                                ],
                              ),
                              const SizedBox(height: 8),
                              ?crew,
                              const SizedBox(height: 10),
                              body,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (choices != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxHeight * .45),
                        child: SingleChildScrollView(child: choices),
                      ),
                    ?input,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      JournalSurface(
        key: const ValueKey('journal-operation-controls'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: movement,
      ),
    ],
  );
}
