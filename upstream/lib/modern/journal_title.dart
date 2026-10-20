import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/utils/game_version.dart';

/// The title menu is a live campaign desk inside the journal. Its choices are
/// exactly the current original-engine actions; artwork never supplies input.
class JournalTitlePage extends StatelessWidget {
  const JournalTitlePage({
    super.key,
    required this.console,
    required this.onAction,
    required this.onHelp,
  });

  final Console console;
  final ValueChanged<String> onAction;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) => Theme(
    data: buildJournalTheme(),
    child: AnimatedBuilder(
      animation: console.revision,
      builder: (context, _) => LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth >= 860;
          final padding = bounds.maxWidth < 650 ? 8.0 : 20.0;
          final revision = console.revision.value;
          final actions = List<ConsoleAction>.unmodifiable(console.actions);
          final hasContinue = actions.any(
            (action) => action.key.toLowerCase() == 'c' && action.enabled,
          );
          final ordered = [
            ...actions.where((action) => action.key.toLowerCase() == 'c'),
            ...actions.where((action) => action.key.toLowerCase() == 'n'),
            ...actions.where(
              (action) => !const {'c', 'n'}.contains(action.key.toLowerCase()),
            ),
          ];
          final menu = _menu(ordered, revision, hasContinue);
          return DecoratedBox(
            decoration: const BoxDecoration(
              color: JournalPalette.leather,
              image: DecorationImage(
                image: AssetImage(JournalPalette.leatherAsset),
                fit: BoxFit.cover,
                opacity: .7,
              ),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                key: const ValueKey('journal-title-scroll'),
                padding: EdgeInsets.all(padding),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(0, bounds.maxHeight - padding * 2),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _masthead(wide),
                          const SizedBox(height: 8),
                          if (wide)
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 5, child: _newspaper()),
                                  const JournalBinding(width: 28),
                                  Expanded(flex: 6, child: menu),
                                ],
                              ),
                            )
                          else ...[
                            menu,
                            const SizedBox(height: 10),
                            _newspaper(),
                          ],
                          const SizedBox(height: 8),
                          _credits(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _masthead(bool wide) => JournalSurface(
    padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 14, vertical: 12),
    child: Column(
      children: [
        Text(
          'THE UNDERGROUND EDITION',
          textAlign: TextAlign.center,
          style: JournalPalette.small.copyWith(fontSize: 11, letterSpacing: 1),
        ),
        const SizedBox(height: 5),
        Semantics(
          header: true,
          child: Text(
            'Liberal Crime Squad: New Age',
            key: const ValueKey('journal-product-title'),
            textAlign: TextAlign.center,
            style: JournalPalette.title.copyWith(
              fontSize: wide ? 39 : 28,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Divider(height: 4, thickness: 2, color: JournalPalette.ink),
        const Divider(height: 4, thickness: .5, color: JournalPalette.ink),
        const SizedBox(height: 5),
        const Text(
          'Political strategy. Personal consequences.',
          textAlign: TextAlign.center,
          style: JournalPalette.small,
        ),
      ],
    ),
  );

  Widget _menu(List<ConsoleAction> actions, int revision, bool hasContinue) =>
      JournalSurface(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: [
                const Text('Campaign desk', style: JournalPalette.heading),
                const JournalPreferencesButton(),
                TextButton.icon(
                  key: const ValueKey('journal-title-help'),
                  onPressed: onHelp,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const JournalCommandLabel(
                    shortcut: 'F1',
                    label: 'How to play',
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            if (actions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Preparing the campaign desk…',
                  style: JournalPalette.body,
                ),
              ),
            for (var i = 0; i < actions.length; i++) ...[
              _choice(
                actions[i],
                revision,
                primary:
                    actions[i].key.toLowerCase() == (hasContinue ? 'c' : 'n'),
              ),
              if (i != actions.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      );

  Widget _choice(ConsoleAction action, int revision, {required bool primary}) {
    final key = action.key.toLowerCase();
    final label = _clean(action.label);
    final caption = _caption(action);
    void activate() {
      // A retained callback from a previous frame cannot act on a new prompt.
      if (console.revision.value != revision ||
          console.screen != 'title' ||
          !console.actions.contains(action) ||
          !action.enabled) {
        return;
      }
      onAction(action.key);
    }

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Opacity(
          opacity: action.enabled ? 1 : .45,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: JournalPalette.card,
              border: Border.all(color: JournalPalette.brassDark),
              borderRadius: BorderRadius.circular(2),
            ),
            child: JournalIllustratedIcon(icon: _icon(key), size: 30),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              if (caption.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  caption,
                  style: const TextStyle(fontSize: 11.5, height: 1.3),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        JournalShortcutBadge(
          shortcut: action.key,
          primary: primary && action.enabled,
        ),
        if (action.enabled) ...[
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward, size: 17),
        ],
      ],
    );
    final actionKey = ValueKey('journal-title-action:${action.key}');
    return Tooltip(
      message: action.enabled
          ? '$label · Shortcut: ${journalShortcutSpokenLabel(action.key)}'
          : caption.isEmpty
          ? '$label is unavailable.'
          : caption,
      child: primary && action.enabled
          ? FilledButton(
              key: actionKey,
              onPressed: activate,
              style: FilledButton.styleFrom(
                backgroundColor: key == 'n'
                    ? JournalPalette.binding
                    : JournalPalette.olive,
                foregroundColor: JournalPalette.card,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                alignment: Alignment.centerLeft,
              ),
              child: content,
            )
          : OutlinedButton(
              key: actionKey,
              onPressed: action.enabled ? activate : null,
              style: OutlinedButton.styleFrom(
                disabledForegroundColor: JournalPalette.muted,
                disabledBackgroundColor: JournalPalette.inset,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                alignment: Alignment.centerLeft,
              ),
              child: content,
            ),
    );
  }

  String _caption(ConsoleAction action) {
    final key = action.key.toLowerCase();
    if (!action.enabled) {
      return switch (key) {
        'c' => 'No recent campaign is available to continue.',
        'l' => 'No saved campaigns are available.',
        'h' => 'No scores have been recorded yet.',
        _ => 'This option is unavailable.',
      };
    }
    return switch (key) {
      'c' => 'Return to your most recent saved campaign.',
      'n' => 'Create your founder and begin a new campaign.',
      'l' => 'Choose, export or manage a saved campaign.',
      'i' => 'Bring an exported New Age save into this game.',
      'o' => 'Adjust gameplay, interface and content settings.',
      'h' => 'Review your completed campaigns.',
      'v' => 'Read the game’s latest changes.',
      'm' => 'Open the game’s tools.',
      _ => '',
    };
  }

  JournalIcon _icon(String key) => switch (key) {
    'c' || 'h' => JournalIcon.reports,
    'n' => JournalIcon.crew,
    'l' => JournalIcon.accounts,
    'i' || 'o' || 'm' => JournalIcon.options,
    'v' => JournalIcon.newspaper,
    _ => JournalIcon.city,
  };

  Widget _newspaper() => JournalSurface(
    padding: const EdgeInsets.all(18),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'The organisation starts with you.',
          style: JournalPalette.title,
        ),
        const Divider(height: 20, thickness: 1.5),
        const Center(
          child: JournalIllustratedIcon(icon: JournalIcon.crew, size: 126),
        ),
        const SizedBox(height: 12),
        const Text(
          'Build a movement in a country sliding toward authoritarianism. '
          'Recruit supporters, form squads and decide how far your campaign will go.',
          style: JournalPalette.body,
        ),
        const SizedBox(height: 16),
        _brief(
          'People',
          'Recruit, train and equip your crew.',
          JournalIcon.personnel,
        ),
        _brief(
          'Orders',
          'Plan daily assignments and squad operations.',
          JournalIcon.operations,
        ),
        _brief(
          'Consequences',
          'Follow public opinion, law changes and the stories your actions create.',
          JournalIcon.newspaper,
        ),
      ],
    ),
  );

  Widget _brief(String title, String body, JournalIcon icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JournalIllustratedIcon(icon: icon, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: JournalPalette.body.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(body, style: JournalPalette.small),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _credits() => const JournalSurface(
    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    child: Text(
      'Original game by Tarn Adams · New Age by Ashley S. Fox\n'
      'The Underground Edition by Kevin Wood\n'
      'Open source · GPL-2.0\n'
      '$gameVersionLabel',
      textAlign: TextAlign.center,
      style: JournalPalette.small,
    ),
  );

  String _clean(String label) => stripConsoleColors(
    label,
  ).replaceFirst(RegExp(r'^\s*\(?[A-Za-z0-9?]+\)?\s*[-–:]\s*'), '').trim();
}
