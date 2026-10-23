import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

/// Profile layout only. The shell supplies the source roster/page, dossier,
/// editor and current confirmation/actions without advancing its reader here.
class JournalProfileView extends StatelessWidget {
  const JournalProfileView({
    super.key,
    required this.name,
    required this.editing,
    required this.dossier,
    required this.controls,
  });

  final String name;
  final bool editing;
  final Widget dossier, controls;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: editing
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Rename $name', style: JournalPalette.heading),
              )
            : dossier,
      ),
      const Divider(height: 1, color: JournalPalette.rule),
      Padding(padding: const EdgeInsets.all(10), child: controls),
    ],
  );
}

class JournalProfileActionView extends StatelessWidget {
  const JournalProfileActionView({
    super.key,
    required this.shortcut,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String shortcut, label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: ValueKey('journal-profile-action:$shortcut'),
    onPressed: onPressed,
    icon: Icon(icon, size: 16),
    label: JournalCommandLabel(shortcut: shortcut, label: label),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      minimumSize: const Size(44, 44),
    ),
  );
}
