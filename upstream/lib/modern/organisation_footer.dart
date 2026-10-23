import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_navigation_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// The journal chooses the live command; this view only renders its facts.
typedef JournalFooterCommand = ({
  String label,
  String? shortcut,
  bool continuing,
  bool detailOwnsContinue,
  VoidCallback? onPressed,
});

/// Footer layout and sizing, with no campaign or source-reader ownership.
class OrganisationFooterView extends StatelessWidget {
  const OrganisationFooterView({
    super.key,
    required this.narrow,
    required this.dateFunds,
    required this.textScale,
    required this.saveShortcut,
    required this.primary,
    required this.onHeadquartersCommands,
    required this.onSaveExit,
    required this.onTextScale,
    required this.onClassic,
    this.cancelDepartureLabel,
    this.onCancelDeparture,
  });

  final bool narrow;
  final String dateFunds;
  final double textScale;
  final String saveShortcut;
  final JournalFooterCommand primary;
  final VoidCallback? onHeadquartersCommands, onSaveExit, onCancelDeparture;
  final ValueChanged<double> onTextScale;
  final VoidCallback onClassic;
  final String? cancelDepartureLabel;

  @override
  Widget build(BuildContext context) {
    final utilities = <Widget>[
      Tooltip(
        message: 'More headquarters commands',
        child: TextButton.icon(
          key: const ValueKey('journal-more-commands'),
          onPressed: onHeadquartersCommands,
          icon: const Icon(
            Icons.menu_book,
            color: JournalPalette.brassLight,
            size: 21,
          ),
          label: Text(
            'HQ commands',
            style: JournalPalette.small.copyWith(color: JournalPalette.card),
          ),
        ),
      ),
      Expanded(
        child: Text(
          dateFunds,
          key: const ValueKey('journal-date-funds'),
          maxLines: 2,
          style: JournalPalette.small.copyWith(
            color: JournalPalette.card,
            height: textScale > 1.1 ? 1 : 1.4,
          ),
        ),
      ),
      PopupMenuButton<double>(
        tooltip: 'Reading size',
        initialValue: textScale,
        onSelected: onTextScale,
        icon: const Icon(
          Icons.text_fields,
          color: JournalPalette.brassLight,
          size: 22,
        ),
        itemBuilder: (_) => [
          for (final scale in [1.0, 1.25, 1.5])
            PopupMenuItem(
              value: scale,
              child: Text('${(scale * 100).round()}%'),
            ),
        ],
      ),
      const JournalPreferencesButton(color: JournalPalette.brassLight),
      IconButton(
        tooltip: 'Switch readable / classic view',
        onPressed: onClassic,
        icon: const Icon(
          Icons.terminal,
          color: JournalPalette.brassLight,
          size: 21,
        ),
      ),
    ];
    final commands = <Widget>[
      OutlinedButton.icon(
        key: const ValueKey('journal-save-exit'),
        onPressed: onSaveExit,
        style: OutlinedButton.styleFrom(
          backgroundColor: JournalPalette.page,
          minimumSize: const Size(44, 34),
          padding: const EdgeInsets.symmetric(horizontal: 9),
        ),
        icon: const Icon(Icons.save_outlined, size: 17),
        label: Tooltip(
          excludeFromSemantics: true,
          message:
              'At headquarters: X. '
              'Optional global shortcut: $journalSaveShortcut.',
          child: JournalCommandLabel(
            shortcut: saveShortcut,
            label: 'Save & exit',
          ),
        ),
      ),
      if (cancelDepartureLabel != null)
        IconButton(
          tooltip: cancelDepartureLabel!,
          key: const ValueKey('journal-cancel-departure'),
          onPressed: onCancelDeparture,
          icon: const Icon(
            Icons.cancel_outlined,
            color: JournalPalette.brassLight,
          ),
        ),
      if (!primary.detailOwnsContinue)
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: narrow ? 230 : 340),
          child: Tooltip(
            message: primary.continuing
                ? primary.label
                : '${primary.label}. At headquarters: W. '
                      'Optional global shortcut: $journalAdvanceShortcut.',
            child: FilledButton.icon(
              key: const ValueKey('journal-advance-day'),
              onPressed: primary.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: JournalPalette.binding,
                minimumSize: const Size(44, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: Icon(
                primary.continuing ? Icons.arrow_forward : Icons.play_arrow,
                size: 18,
              ),
              label: primary.shortcut == null
                  ? Text(
                      primary.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Semantics(
                      label: primary.label,
                      hint:
                          'Keyboard shortcut: ${journalShortcutSpokenLabel(primary.shortcut!)}',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          JournalShortcutBadge(
                            shortcut: primary.shortcut!,
                            primary: true,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              primary.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final theme = Theme.of(context);
        final saveTextStyle =
            OutlinedButtonTheme.of(context).style?.textStyle?.resolve({}) ??
            theme.textTheme.labelLarge!;
        final advanceTextStyle =
            FilledButtonTheme.of(context).style?.textStyle?.resolve({}) ??
            theme.textTheme.labelLarge!;
        final saveWidth =
            18 +
            17 +
            8 +
            _shortcutBadgeWidth(context, saveShortcut) +
            8 +
            _textWidth(context, 'Save & exit', saveTextStyle);
        final advanceWidth = primary.detailOwnsContinue
            ? 0.0
            : (20 +
                      18 +
                      8 +
                      (primary.shortcut == null
                          ? 0
                          : _shortcutBadgeWidth(context, primary.shortcut!) +
                                8) +
                      _textWidth(context, primary.label, advanceTextStyle))
                  .clamp(44.0, narrow ? 230.0 : 340.0);
        // Four utility buttons plus a readable two-line date/funds label.
        // Measure the command labels so wider fonts wrap before they overflow.
        final minimumUtilitiesWidth =
            3 * kMinInteractiveDimension +
            60 +
            _textWidth(context, 'HQ commands', JournalPalette.small) +
            _textWidth(context, dateFunds, JournalPalette.small) / 2;
        final requiredWidth =
            minimumUtilitiesWidth +
            saveWidth +
            advanceWidth +
            (cancelDepartureLabel != null ? kMinInteractiveDimension : 0) +
            commands.length * 9;
        final stacked =
            bounds.maxWidth < 760 || bounds.maxWidth < requiredWidth;
        if (stacked) {
          final utilitiesHeight = bounds.maxWidth < 550
              ? (scale * 12 * 2.8).clamp(42.0, 70.0)
              : 42.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: utilitiesHeight,
                child: Row(children: utilities),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: commands,
              ),
            ],
          );
        }
        return SizedBox(
          height: narrow ? 41 : 45,
          child: Row(
            children: [
              ...utilities,
              for (final command in commands) ...[
                const SizedBox(width: 9),
                command,
              ],
            ],
          ),
        );
      },
    );
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  double _shortcutBadgeWidth(BuildContext context, String shortcut) =>
      (_textWidth(
                context,
                journalShortcutLabel(shortcut),
                JournalShortcutBadge.textStyle,
              ) +
              12)
          .clamp(24.0, double.infinity);
}
