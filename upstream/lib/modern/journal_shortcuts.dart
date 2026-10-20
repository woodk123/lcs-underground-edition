import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Labels for an exact source key or a registered presentation shortcut.
/// Rendering a badge never registers or remaps input by itself.
String journalShortcutLabel(String shortcut) => switch (shortcut) {
  _ when shortcut.startsWith('HQ: ') =>
    'HQ: ${journalShortcutLabel(shortcut.substring(4))}',
  _ when shortcut.contains(' → ') =>
    shortcut.split(' → ').map(journalShortcutLabel).join(' → '),
  'Escape' => 'Esc',
  'Up' => '↑',
  'Down' => '↓',
  'Left' => '←',
  'Right' => '→',
  'PageUp' => 'PgUp',
  'PageDown' => 'PgDn',
  'Backspace' => 'Back',
  _ =>
    _requiresShift(shortcut)
        ? 'Shift+$shortcut'
        : shortcut.length == 1
        ? shortcut.toUpperCase()
        : shortcut,
};

String journalShortcutSpokenLabel(String shortcut) => switch (shortcut) {
  _ when shortcut.startsWith('HQ: ') =>
    'At headquarters, ${journalShortcutSpokenLabel(shortcut.substring(4))}',
  _ when shortcut.contains(' → ') =>
    shortcut.split(' → ').map(journalShortcutSpokenLabel).join(', then '),
  'Up' => 'Up arrow',
  'Down' => 'Down arrow',
  'Left' => 'Left arrow',
  'Right' => 'Right arrow',
  'PageUp' => 'Page up',
  'PageDown' => 'Page down',
  _ =>
    _requiresShift(shortcut)
        ? 'Shift $shortcut'
        : shortcut.length == 1
        ? shortcut.toUpperCase()
        : shortcut,
};

bool _requiresShift(String shortcut) =>
    shortcut.length == 1 &&
    shortcut.toUpperCase() == shortcut &&
    shortcut.toLowerCase() != shortcut;

/// Keep the current encounter/report readable when scaled controls wrap. The
/// action area remains scrollable, and focus traversal reveals later choices.
double journalCommandPanelMaxHeight(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600 &&
        MediaQuery.textScalerOf(context).scale(14) > 20
    ? 96
    : 165;

/// A key label inside an existing control, without another focus or semantics
/// stop. The containing control supplies its command and accessible name.
class JournalShortcutBadge extends StatelessWidget {
  const JournalShortcutBadge({
    super.key,
    required this.shortcut,
    this.primary = false,
  });

  final String shortcut;
  final bool primary;

  static const textStyle = TextStyle(
    fontFamily: 'ModernSans',
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      key: ValueKey('journal-shortcut:$shortcut'),
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: primary
            ? Colors.white.withValues(alpha: .13)
            : JournalPalette.ink.withValues(alpha: .055),
        border: Border.all(
          color: primary
              ? Colors.white.withValues(alpha: .4)
              : JournalPalette.rule,
        ),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        journalShortcutLabel(shortcut),
        textAlign: TextAlign.center,
        style: textStyle.copyWith(
          color: primary ? Colors.white : JournalPalette.ink,
        ),
      ),
    ),
  );
}

/// A visible source key and choice label, sharing their parent's activation.
/// Long labels wrap, including in enlarged reading layouts.
class JournalCommandLabel extends StatelessWidget {
  const JournalCommandLabel({
    super.key,
    required this.shortcut,
    required this.label,
    this.primary = false,
  });

  final String shortcut, label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final prefix = RegExp(
      '^${RegExp.escape(shortcut)}\\s*[-–:]\\s*',
      caseSensitive: false,
    );
    final title = label.replaceFirst(prefix, '').trim();
    return Semantics(
      label: title,
      hint: 'Keyboard shortcut: ${journalShortcutSpokenLabel(shortcut)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          JournalShortcutBadge(shortcut: shortcut, primary: primary),
          const SizedBox(width: 8),
          Flexible(child: Text(title)),
        ],
      ),
    );
  }
}
