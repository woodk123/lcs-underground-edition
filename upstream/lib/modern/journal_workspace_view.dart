import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Shared fallback layout; the shell selects readers and supplies their content
/// and live controls. These views own no campaign objects or command routing.
class JournalWorkspaceView extends StatelessWidget {
  const JournalWorkspaceView({
    super.key,
    required this.classic,
    required this.compact,
    required this.planning,
    required this.heading,
    required this.content,
    this.returnControl,
    this.movement,
    this.choices,
    this.input,
  });

  final bool classic, compact, planning;
  final String heading;
  final Widget content;
  final Widget? returnControl, movement, choices, input;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(compact ? 12 : 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!planning) ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.6,
                      ),
                    ),
                  ],
                ),
              ),
              ?returnControl,
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (movement != null) ...[movement!, const SizedBox(height: 14)],
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: classic
                    ? const SizedBox()
                    : Material(
                        color: JournalPalette.card,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(color: JournalPalette.rule),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: content,
                      ),
              ),
              if (classic && !compact) ...[
                const SizedBox(width: 22),
                SizedBox(width: 286, child: choices),
              ],
            ],
          ),
        ),
        if (classic && compact) SizedBox(height: 180, child: choices),
        if (input != null) ...[const SizedBox(height: 10), input!],
      ],
    ),
  );
}

class JournalProcessingView extends StatelessWidget {
  const JournalProcessingView({super.key});

  @override
  Widget build(BuildContext context) => JournalSurface(
    key: const ValueKey('journal-processing'),
    lined: true,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top, color: JournalPalette.brassDark),
            SizedBox(height: 12),
            Text(
              'Preparing the next report',
              textAlign: TextAlign.center,
              style: JournalPalette.heading,
            ),
            SizedBox(height: 10),
            Text(
              'The campaign is still processing. The next report or decision will appear here.',
              textAlign: TextAlign.center,
              style: JournalPalette.small,
            ),
          ],
        ),
      ),
    ),
  );
}

class JournalLiveGraphicView extends StatelessWidget {
  const JournalLiveGraphicView({super.key, required this.graphic});
  final Widget graphic;

  @override
  Widget build(BuildContext context) => JournalSurface(
    key: const ValueKey('journal-live-graphic'),
    lined: true,
    child: Center(child: SingleChildScrollView(child: graphic)),
  );
}

class JournalManagementView extends StatelessWidget {
  const JournalManagementView({
    super.key,
    required this.heading,
    required this.scrollStorageId,
    required this.content,
    this.backControl,
    this.input,
  });

  final String heading, scrollStorageId;
  final Widget content;
  final Widget? backControl, input;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('journal-management-page'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 4, 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                heading,
                key: const ValueKey('journal-management-heading'),
                style: JournalPalette.heading,
              ),
            ),
            ?backControl,
          ],
        ),
      ),
      const Divider(height: 1, color: JournalPalette.rule),
      Expanded(
        child: SingleChildScrollView(
          key: PageStorageKey(scrollStorageId),
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: content,
        ),
      ),
      ?input,
    ],
  );
}
