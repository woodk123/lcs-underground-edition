import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/utils/colors.dart' as legacy;

Color _printedColor(Color color) =>
    color == legacy.red || color == legacy.darkRed
    ? JournalPalette.danger
    : color == legacy.lightGreen || color == legacy.green
    ? JournalPalette.olive
    : JournalPalette.ink;

String _cell(Console console, int row, int start, int end) => console
    .buffer[row]
    .sublist(start, end)
    .map((cell) => cell.glyph)
    .join()
    .trim();

/// Recognizes the original congress printer, including its initial blank slots.
bool isLegislativeVoteScreen(Console console) =>
    _cell(console, 0, 0, 35).startsWith('Legislative Agenda ') &&
    _cell(console, 2, 0, 35).startsWith('Joint Resolution ');

/// Reads already printed cells only. No vote, status or outcome is predicted.
class JournalLegislationView extends StatelessWidget {
  const JournalLegislationView({
    super.key,
    required this.console,
    required this.onAction,
  });

  final Console console;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => JournalSurface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_cell(console, 0, 0, 35), style: JournalPalette.heading),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var row = 2; row < 20; row += 3)
                  if (_cell(
                    console,
                    row,
                    0,
                    35,
                  ).startsWith('Joint Resolution '))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: JournalSurface(
                        inset: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _cell(console, row, 0, 35),
                              style: JournalPalette.small,
                            ),
                            Text(
                              _cell(console, row + 1, 0, 35),
                              style: JournalPalette.heading.copyWith(
                                fontSize: 17,
                                color: _printedColor(
                                  console.buffer[row + 1][0].foreground,
                                ),
                              ),
                            ),
                            if (_cell(console, 0, 62, 70) == 'House') ...[
                              const SizedBox(height: 10),
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
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          [
            for (var row = 23; row < 25; row++) _cell(console, row, 0, 80),
          ].where((text) => text.isNotEmpty).join('\n'),
          style: JournalPalette.small,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: console.awaitingInput ? () => onAction('Enter') : null,
            child: const Text('Continue'),
          ),
        ),
      ],
    ),
  );

  Widget _branch(int row, String name, int start, int end) {
    final values = [
      _cell(console, row, start, end),
      if (name != 'President') _cell(console, row + 1, start, end),
    ].where((value) => value.isNotEmpty).join(' · ');
    return Semantics(
      label: '$name: ${values.isEmpty ? 'Pending' : values}',
      excludeSemantics: true,
      child: SizedBox(
        width: name == 'President' ? 210 : 160,
        child: Column(
          key: ValueKey('legislation-$row-${name.toLowerCase()}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: JournalPalette.small),
            Text(values.isEmpty ? 'Pending' : values),
          ],
        ),
      ),
    );
  }
}
