import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/agenda_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/law_help.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/utils/interface_options.dart';

/// Five original agenda pages, presented as live political records. The source
/// supplies all people, counts, statements, laws, percentages and commands.
class JournalAgendaView extends StatelessWidget {
  const JournalAgendaView({
    super.key,
    required this.console,
    required this.onAction,
  });
  final Console console;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: console.revision,
    builder: (context, _) {
      final frame = agendaOverviewFrame(console);
      if (frame == null) return const SizedBox.shrink();
      final revision = console.revision.value;
      return LayoutBuilder(
        builder: (context, bounds) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              frame.endingTitle ?? 'The Liberal Agenda',
              style: JournalPalette.title,
            ),
            const SizedBox(height: 4),
            Text(
              '${frame.pageTitle} · Page ${frame.page + 1} of ${frame.pageCount}',
              style: JournalPalette.body,
            ),
            const Divider(height: 18, color: JournalPalette.brassDark),
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  key: const ValueKey('journal-agenda-scroll'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final note in frame.notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(note, style: JournalPalette.body),
                        ),
                      if (frame.offices.isNotEmpty) ...[
                        _government(frame, bounds.maxWidth),
                        const SizedBox(height: 16),
                      ],
                      if (frame.laws.isNotEmpty) ...[
                        Text(
                          frame.page == 0 ? 'Current laws' : 'Law records',
                          style: JournalPalette.heading,
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Each track shows the current law, from Arch Conservative to Elite Liberal. Hover for gameplay effects; click for calculations and the full law guide.',
                          style: JournalPalette.small,
                        ),
                        const SizedBox(height: 8),
                        _lawGrid(
                          context,
                          frame.laws,
                          bounds.maxWidth,
                          detailed: frame.page != 0,
                        ),
                      ],
                      if (frame.polls.isNotEmpty) ...[
                        const DecisionGuideButton(topic: DecisionTopic.opinion),
                        const Text(
                          'Percentages show the recorded survey result. Public interest is a separate level of attention.',
                          style: JournalPalette.small,
                        ),
                        const SizedBox(height: 9),
                        _pollGrid(frame.polls, bounds.maxWidth),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final action in frame.controls)
                  OutlinedButton(
                    key: ValueKey('journal-agenda-action:${action.key}'),
                    onPressed: action.enabled
                        ? () {
                            if (console.revision.value == revision &&
                                identical(
                                  agendaOverviewFrame(console),
                                  frame,
                                ) &&
                                console.actions.contains(action)) {
                              onAction(action.key);
                            }
                          }
                        : null,
                    style: action.key.toLowerCase() == 'd'
                        ? OutlinedButton.styleFrom(
                            foregroundColor: JournalPalette.danger,
                          )
                        : null,
                    child: Text(_controlLabel(action)),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _government(AgendaOverviewFrame frame, double width) {
    final columns = width >= 1100
        ? 3
        : width >= 700
        ? 2
        : 1;
    final itemWidth = (width - 10 * (columns - 1)) / columns;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        SizedBox(
          width: itemWidth,
          child: _people('Executive branch', frame.offices),
        ),
        SizedBox(
          width: itemWidth,
          child: _people('Supreme Court', frame.court),
        ),
        SizedBox(
          width: itemWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final chamber in frame.chambers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _chamber(chamber),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _people(String heading, List<AgendaOffice> people) => JournalSurface(
    inset: true,
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(heading, style: JournalPalette.heading),
        const SizedBox(height: 6),
        for (final person in people)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!person.role.startsWith('Justice'))
                        Text(
                          person.role.replaceFirst(RegExp(r':$'), ''),
                          style: JournalPalette.small,
                        ),
                      Text(
                        person.name,
                        style: JournalPalette.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    person.alignment.label,
                    textAlign: TextAlign.right,
                    style: JournalPalette.small.copyWith(
                      color: _alignmentColor(person.alignment),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _chamber(AgendaChamber chamber) {
    final total = chamber.counts.fold<int>(0, (a, b) => a + b);
    return JournalSurface(
      inset: true,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${chamber.name} · $total seats', style: JournalPalette.heading),
          const SizedBox(height: 8),
          Semantics(
            label: '${chamber.name} seat distribution',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 9,
                child: Row(
                  children: [
                    for (var i = 0; i < chamber.counts.length; i++)
                      if (chamber.counts[i] > 0)
                        Expanded(
                          flex: chamber.counts[i],
                          child: ColoredBox(
                            color: _alignmentColor(DeepAlignment.values[i]),
                            child: const SizedBox.expand(),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          for (var i = 0; i < chamber.counts.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DeepAlignment.values[i].label,
                      style: JournalPalette.small,
                    ),
                  ),
                  Text('${chamber.counts[i]}', style: JournalPalette.body),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _lawGrid(
    BuildContext context,
    List<AgendaLaw> laws,
    double width, {
    required bool detailed,
  }) {
    final columns = detailed
        ? (width >= 850 ? 2 : 1)
        : (width >= 1050
              ? 3
              : width >= 600
              ? 2
              : 1);
    final itemWidth = (width - 8 * (columns - 1)) / columns;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final law in laws)
          SizedBox(
            width: itemWidth,
            child: MechanicsTooltip(
              message: lawHoverHelp(law),
              maxWidth: 520,
              child: Semantics(
                button: true,
                label:
                    '${law.name}. ${law.alignment.label}. ${law.description}. Open law guide.',
                child: ExcludeSemantics(
                  child: InkWell(
                    onTap: () => showLawGuide(context, law),
                    child: JournalSurface(
                      key: ValueKey('journal-law:${law.id}'),
                      inset: true,
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  law.name,
                                  style: JournalPalette.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  law.alignment.label,
                                  textAlign: TextAlign.right,
                                  style: JournalPalette.small.copyWith(
                                    color: _alignmentColor(law.alignment),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              for (final alignment in DeepAlignment.values)
                                Expanded(
                                  child: Container(
                                    height: 7,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
                                    color: alignment == law.alignment
                                        ? _alignmentColor(alignment)
                                        : JournalPalette.rule.withValues(
                                            alpha: .28,
                                          ),
                                  ),
                                ),
                            ],
                          ),
                          if (detailed) ...[
                            const SizedBox(height: 7),
                            Text(law.description, style: JournalPalette.body),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pollGrid(List<AgendaPoll> polls, double width) {
    final columns = width >= 900 ? 2 : 1;
    final itemWidth = (width - 10 * (columns - 1)) / columns;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final poll in polls)
          SizedBox(
            width: itemWidth,
            child: JournalSurface(
              inset: true,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(poll.issue, style: JournalPalette.heading),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        poll.percentLabel,
                        style: JournalPalette.heading.copyWith(fontSize: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${poll.percentLabel} ${poll.statement}',
                    style: JournalPalette.body,
                  ),
                  const SizedBox(height: 7),
                  Semantics(
                    label: '${poll.issue}: ${poll.percentLabel}',
                    child: ExcludeSemantics(
                      child: LinearProgressIndicator(
                        value: (poll.percent / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Public interest: ${poll.interestLabel} · ${poll.interest} recorded points',
                    style: JournalPalette.small,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _controlLabel(ConsoleAction action) {
    if (action.key == interfacePgUp) return 'Previous page';
    if (action.key == interfacePgDown) return 'Next page';
    if (action.key == 'Enter') return 'Back';
    final text = stripConsoleColors(
      action.label,
    ).replaceFirst(RegExp(r'^\s*[A-Za-z0-9?]+\s*[-–:]\s*'), '').trim();
    return text;
  }

  Color _alignmentColor(DeepAlignment alignment) => switch (alignment) {
    DeepAlignment.archConservative => JournalPalette.danger,
    DeepAlignment.conservative => const Color(0xFF79526E),
    DeepAlignment.moderate => const Color(0xFF71551F),
    DeepAlignment.liberal => const Color(0xFF2F6263),
    DeepAlignment.eliteLiberal => JournalPalette.olive,
  };
}
