import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/legislation_context.dart';
import 'package:lcs_new_age/modern/journal_site_art.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/legislation_impact.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/utils/colors.dart' as legacy;

String _cell(Console console, int row, int start, int end) => console
    .buffer[row]
    .sublist(start, end)
    .map((cell) => cell.glyph)
    .join()
    .trim();

bool isLegislativeVoteScreen(Console console) =>
    console.legislation != null ||
    (_cell(console, 0, 0, 35).startsWith('Legislative Agenda ') &&
        _cell(console, 2, 0, 35).startsWith('Joint Resolution '));

/// Illustrated reports over the original vote sequence. Only source-owned
/// metadata and already printed counts are shown; no outcome is predicted.
class JournalLegislationView extends StatelessWidget {
  const JournalLegislationView({
    super.key,
    required this.console,
    required this.onAction,
  });
  final Console console;
  final ValueChanged<String> onAction;

  LegislationStage get stage =>
      console.legislation?.stage ?? LegislationStage.votes;
  String get _heading => switch (stage) {
    LegislationStage.agenda => 'On the floor of Congress',
    LegislationStage.votes => 'The roll call',
    LegislationStage.president => 'At the President’s desk',
    LegislationStage.results => 'Washington has decided',
  };
  String get _note => switch (stage) {
    LegislationStage.agenda =>
      'A new round of legislation is on the table. Each bill proposes one step along an issue’s political spectrum.',
    LegislationStage.votes =>
      'Both chambers must approve a bill. Watch the House and Senate count their votes before the President decides.',
    LegislationStage.president =>
      'A signature makes a bill law. A veto can be overridden by the required support in both chambers.',
    LegislationStage.results =>
      'The decisions are in. Enacted bills take effect now; defeated and vetoed proposals leave their laws unchanged.',
  };
  String get _action => switch (stage) {
    LegislationStage.agenda => 'Watch the votes',
    LegislationStage.votes => 'Watch the President',
    LegislationStage.president => 'See the outcome',
    LegislationStage.results => 'Return to the campaign',
  };

  @override
  Widget build(BuildContext context) => JournalSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('legislation-scroll'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final step in LegislationStage.values)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: step == stage
                              ? JournalPalette.olive
                              : JournalPalette.inset,
                          border: Border.all(color: JournalPalette.rule),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '${step.index + 1}  ${['Agenda', 'Roll call', 'President', 'Outcome'][step.index]}',
                          style: JournalPalette.small.copyWith(
                            color: step == stage
                                ? JournalPalette.card
                                : JournalPalette.muted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                for (var row = 2; row < 20; row += 3)
                  if (_cell(
                    console,
                    row,
                    0,
                    35,
                  ).startsWith('Joint Resolution '))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _bill(row),
                    ),
              ],
            ),
          ),
        ),
        const Divider(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: console.awaitingInput ? () => onAction('Enter') : null,
            icon: Icon(
              console.awaitingInput
                  ? Icons.arrow_forward
                  : Icons.how_to_vote_outlined,
              size: 18,
            ),
            label: Text(
              console.legislation == null
                  ? 'Continue'
                  : console.awaitingInput
                  ? _action
                  : stage == LegislationStage.president
                  ? 'President deliberating…'
                  : 'Votes unfolding…',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _hero() => LayoutBuilder(
    builder: (context, bounds) {
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            console.legislation == null
                ? _cell(console, 0, 0, 35)
                : 'LEGISLATIVE AGENDA · ${console.legislation!.year}',
            style: JournalPalette.small,
          ),
          const SizedBox(height: 8),
          Text(_heading, style: JournalPalette.title),
          const SizedBox(height: 10),
          Text(_note, style: JournalPalette.body),
        ],
      );
      return Container(
        decoration: BoxDecoration(
          color: journalSiteArtPaper,
          border: Border.all(color: JournalPalette.brass),
        ),
        child: bounds.maxWidth < 620
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 140,
                    child: JournalSiteArtwork(
                      siteType: stage.index >= 2 ? 'whiteHouse' : 'courthouse',
                    ),
                  ),
                  Padding(padding: const EdgeInsets.all(16), child: copy),
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    width: 220,
                    height: 190,
                    child: JournalSiteArtwork(
                      siteType: stage.index >= 2 ? 'whiteHouse' : 'courthouse',
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: copy,
                    ),
                  ),
                ],
              ),
      );
    },
  );

  Widget _bill(int row) {
    final index = (row - 2) ~/ 3;
    final reports = console.legislation?.bills;
    final report = reports != null && index < reports.length
        ? reports[index]
        : null;
    final liberal = report != null
        ? report.after > report.before
        : console.buffer[row + 1][0].foreground == legacy.lightGreen;
    final accent = liberal ? JournalPalette.olive : JournalPalette.danger;
    final impact = report == null
        ? null
        : legislationImpact(report.law, report.before, report.after);
    return Container(
      decoration: BoxDecoration(
        color: JournalPalette.card,
        border: Border(
          left: BorderSide(color: accent, width: 4),
          top: const BorderSide(color: JournalPalette.rule),
          right: const BorderSide(color: JournalPalette.rule),
          bottom: const BorderSide(color: JournalPalette.rule),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_cell(console, row, 0, 35), style: JournalPalette.small),
          const SizedBox(height: 4),
          Text(
            report == null
                ? _cell(console, row + 1, 0, 35)
                : billName(report.law, liberal),
            style: JournalPalette.heading.copyWith(color: accent, fontSize: 19),
          ),
          if (report != null) ...[
            const SizedBox(height: 6),
            Text(
              '${report.law.label} · ${report.before.label} to ${report.after.label}',
              style: JournalPalette.small,
            ),
            const SizedBox(height: 12),
            Text(
              report.outcome ??
                  (stage == LegislationStage.agenda
                      ? 'Proposed change'
                      : 'Decision pending'),
              style: JournalPalette.heading.copyWith(fontSize: 14),
            ),
          ],
          if (_cell(console, 0, 62, 70) == 'House') ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _branch(row, 'House', 62, 70),
                _branch(row, 'Senate', 70, 80),
                if (_cell(console, 0, 35, 62) == 'President')
                  _branch(row, 'President', 35, 62),
              ],
            ),
          ],
          if (impact != null) ...[
            const Divider(height: 24),
            Text(
              report!.outcome != null && !report.enacted
                  ? 'Law unchanged'
                  : 'Before',
              style: JournalPalette.small,
            ),
            Text(impact.beforePolicy, style: JournalPalette.body),
            const SizedBox(height: 8),
            Text(
              report.enacted
                  ? 'Now in force'
                  : report.outcome == null
                  ? 'If enacted'
                  : 'Proposal rejected',
              style: JournalPalette.small,
            ),
            Text(
              impact.afterPolicy,
              style: JournalPalette.body.copyWith(
                color: report.outcome != null && !report.enacted
                    ? JournalPalette.muted
                    : accent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              report.enacted
                  ? 'What this means for your campaign'
                  : 'What this would mean for your campaign',
              style: JournalPalette.heading.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 5),
            Text(impact.gameplayImpact, style: JournalPalette.body),
            if (report.outcome != null && !report.enacted)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'This change did not take effect.',
                  style: JournalPalette.small,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _branch(int row, String name, int start, int end) {
    final yea = _cell(console, row, start, end);
    final nay = name == 'President' ? '' : _cell(console, row + 1, start, end);
    final values = [yea, nay].where((value) => value.isNotEmpty).join(' · ');
    final yes = int.tryParse(yea.split(' ').first) ?? 0;
    final no = int.tryParse(nay.split(' ').first) ?? 0;
    return SizedBox(
      width: name == 'President' ? 210 : 180,
      child: Column(
        key: ValueKey('legislation-$row-${name.toLowerCase()}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: JournalPalette.small),
          Text(values.isEmpty ? 'Pending' : values, style: JournalPalette.body),
          if (name != 'President' && yes + no > 0) ...[
            const SizedBox(height: 5),
            Semantics(
              label: '$name: $yes yea, $no nay counted',
              child: LinearProgressIndicator(
                value: yes / (yes + no),
                minHeight: 6,
                color: JournalPalette.olive,
                backgroundColor: JournalPalette.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
