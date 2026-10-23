import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

const _ink = JournalPalette.ink;
const _paper = JournalPalette.page;
const _muted = JournalPalette.muted;
const _vermilion = JournalPalette.binding;
const _teal = JournalPalette.olive;
const _line = JournalPalette.rule;

/// Detached shell navigation: availability and routing belong to the shell.
@immutable
class ModernShellSection {
  const ModernShellSection({
    required this.id,
    required this.icon,
    required this.label,
    required this.shortLabel,
    required this.selected,
    required this.onSelect,
  });
  final int id;
  final IconData icon;
  final String label, shortLabel;
  final bool selected;
  final VoidCallback? onSelect;
}

class ModernShellTopBar extends StatelessWidget {
  const ModernShellTopBar({
    super.key,
    required this.date,
    required this.funds,
    required this.textScale,
    required this.classic,
    required this.onTextScale,
    required this.onClassic,
    required this.onHelp,
  });
  final String? date, funds;
  final double textScale;
  final bool classic;
  final ValueChanged<double> onTextScale;
  final VoidCallback onClassic, onHelp;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final narrow = bounds.maxWidth < 650;
      return Container(
        height: 60,
        padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 18),
        color: _ink,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _vermilion,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.bolt, color: _paper, size: 23),
            ),
            const SizedBox(width: 10),
            Text(
              narrow ? 'LCS' : 'LIBERAL CRIME SQUAD',
              style: TextStyle(
                color: _paper,
                fontSize: narrow ? 13 : 14,
                fontWeight: FontWeight.w800,
                letterSpacing: narrow ? 0 : 1,
              ),
            ),
            const Spacer(),
            if (date != null) ...[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    date!,
                    key: const ValueKey('campaign-date'),
                    style: const TextStyle(color: _paper, fontSize: 12),
                  ),
                  Text(
                    funds!,
                    key: const ValueKey('campaign-funds'),
                    style: const TextStyle(
                      color: Color(0xFFB2C1BA),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(width: narrow ? 4 : 18),
            ],
            PopupMenuButton<double>(
              tooltip: 'Reading size',
              initialValue: textScale,
              onSelected: onTextScale,
              icon: const Icon(Icons.text_fields, color: _paper, size: 22),
              itemBuilder: (_) => [
                for (final scale in [1.0, 1.25, 1.5])
                  PopupMenuItem(
                    value: scale,
                    child: Text('${(scale * 100).round()}%'),
                  ),
              ],
            ),
            const JournalPreferencesButton(color: _paper),
            IconButton(
              tooltip: 'Switch readable / classic view',
              onPressed: onClassic,
              icon: Icon(
                classic ? Icons.view_agenda_outlined : Icons.terminal,
                color: _paper,
                size: 22,
              ),
            ),
            IconButton(
              tooltip: 'Field guide',
              onPressed: onHelp,
              icon: const Icon(Icons.help_outline, color: _paper, size: 22),
            ),
          ],
        ),
      );
    },
  );
}

class ModernShellSectionStrip extends StatelessWidget {
  const ModernShellSectionStrip({super.key, required this.sections});
  final List<ModernShellSection> sections;

  @override
  Widget build(BuildContext context) => Container(
    height: 44,
    decoration: const BoxDecoration(
      color: JournalPalette.inset,
      border: Border(bottom: BorderSide(color: _line)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final section in sections)
            TextButton(
              key: ValueKey('section:${section.id}'),
              onPressed: section.onSelect,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: section.selected ? _teal : _ink,
                backgroundColor: section.selected
                    ? _teal.withValues(alpha: .1)
                    : null,
              ),
              child: Text(
                section.shortLabel,
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
}

class ModernShellSidebar extends StatelessWidget {
  const ModernShellSidebar({
    super.key,
    required this.sections,
    required this.note,
    this.onSaveExit,
  });
  final List<ModernShellSection> sections;
  final String note;
  final VoidCallback? onSaveExit;

  @override
  Widget build(BuildContext context) => Container(
    width: 190,
    height: double.infinity,
    decoration: const BoxDecoration(
      color: JournalPalette.inset,
      border: Border(right: BorderSide(color: _line)),
    ),
    padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'THE MOVEMENT',
            style: TextStyle(
              color: _muted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          for (final section in sections) _nav(section),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              note,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ),
          if (onSaveExit != null)
            TextButton.icon(
              onPressed: onSaveExit,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save & exit'),
            ),
        ],
      ),
    ),
  );
  Widget _nav(ModernShellSection section) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextButton(
        key: ValueKey('section:${section.id}'),
        onPressed: section.onSelect,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          backgroundColor: section.selected
              ? _teal.withValues(alpha: .1)
              : Colors.transparent,
          foregroundColor: section.selected ? _teal : _ink,
          disabledForegroundColor: _muted.withValues(alpha: .65),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        child: Row(
          children: [
            Icon(section.icon, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                section.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ModernShellStatusBar extends StatelessWidget {
  const ModernShellStatusBar({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: JournalPalette.inset,
      border: Border(top: BorderSide(color: _line)),
    ),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: _muted),
          ),
        ),
        const Text(
          'F1  FIELD GUIDE',
          style: TextStyle(fontSize: 9, letterSpacing: 1, color: _muted),
        ),
      ],
    ),
  );
}
