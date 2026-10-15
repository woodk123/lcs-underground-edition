import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// An account book of the original report's recorded figures and stock values.
/// It never recalculates income, expenses, sale prices or game balances.
class JournalLedgerOverview extends StatelessWidget {
  const JournalLedgerOverview({
    super.key,
    required this.console,
    required this.onAction,
  });
  final Console console;
  final ValueChanged<String> onAction;

  bool _available(LedgerReportFrame frame, ConsoleAction action) {
    if (!action.enabled) return false;
    if (const {'[', ';', ',', 'PageUp'}.contains(action.key)) {
      return frame.pageCount > 1;
    }
    if (const {']', '.', 'PageDown'}.contains(action.key)) {
      return frame.pageCount > 1;
    }
    return true;
  }

  VoidCallback? _command(
    LedgerReportFrame frame,
    ConsoleAction action,
    int revision,
  ) {
    if (!_available(frame, action)) return null;
    return () {
      if (console.revision.value == revision &&
          ledgerReportFrame(console) == frame &&
          console.actions.contains(action) &&
          console.lastKey == null) {
        onAction(action.key);
      }
    };
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: console.revision,
    builder: (context, _) {
      final frame = ledgerReportFrame(console);
      if (frame == null) return const SizedBox.shrink();
      final revision = console.revision.value;
      return LayoutBuilder(
        builder: (context, bounds) {
          final narrow = bounds.maxWidth < 650;
          final visible = frame.lines
              .where((line) => line.page == frame.page)
              .toList();
          return JournalSurface(
            key: const ValueKey('journal-ledger'),
            lined: true,
            padding: EdgeInsets.all(narrow ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    key: ValueKey('journal-ledger-scroll:${frame.page}'),
                    children: [
                      const Text(
                        'Financial ledger',
                        style: JournalPalette.title,
                      ),
                      const SizedBox(height: 5),
                      const DecisionGuideButton(topic: DecisionTopic.ledger),
                      Text(
                        frame.management
                            ? 'Recorded income, expenses & liquid assets'
                            : 'Month-end financial report',
                        style: JournalPalette.body,
                      ),
                      const Divider(
                        height: 22,
                        thickness: 2,
                        color: JournalPalette.ink,
                      ),
                      LayoutBuilder(
                        builder: (context, inner) {
                          final columns = inner.maxWidth >= 950
                              ? 4
                              : inner.maxWidth >= 510
                              ? 2
                              : 1;
                          final width =
                              (inner.maxWidth - (columns - 1) * 10) / columns;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 9,
                            children: [
                              for (final metric
                                  in <(String, int, String, bool)>[
                                    (
                                      'Cash available',
                                      frame.cash,
                                      'cash',
                                      false,
                                    ),
                                    (
                                      'Monthly net',
                                      frame.monthlyNet,
                                      'monthly-net',
                                      true,
                                    ),
                                    (
                                      'Daily net',
                                      frame.dailyNet,
                                      'daily-net',
                                      true,
                                    ),
                                    (
                                      'Liquid assets',
                                      frame.totalLiquidAssets,
                                      'assets',
                                      false,
                                    ),
                                  ])
                                SizedBox(
                                  width: width,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: JournalPalette.inset,
                                      border: Border.all(
                                        color: JournalPalette.rule,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          metric.$1,
                                          style: JournalPalette.small,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _money(metric.$2, signed: metric.$4),
                                          key: ValueKey(
                                            'journal-ledger-${metric.$3}',
                                          ),
                                          style: JournalPalette.heading
                                              .copyWith(
                                                fontSize: narrow ? 22 : 26,
                                                color: metric.$2 < 0
                                                    ? JournalPalette.danger
                                                    : JournalPalette.ink,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Inventory uses the game’s fence values for stock held at safehouses. '
                        'It is not spendable cash until sold.',
                        style: JournalPalette.small,
                      ),
                      if (!frame.management) ...[
                        const SizedBox(height: 7),
                        const Text(
                          'Review this report, then Continue to finish the month-end accounting.',
                          key: ValueKey('journal-ledger-required-note'),
                          style: JournalPalette.small,
                        ),
                      ],
                      const Divider(height: 22),
                      for (final group in <(String, LedgerLineKind)>[
                        ('Income', LedgerLineKind.income),
                        ('Expenses', LedgerLineKind.expense),
                        ('Liquid assets', LedgerLineKind.asset),
                      ])
                        if (visible.any((line) => line.kind == group.$2)) ...[
                          Text(group.$1, style: JournalPalette.heading),
                          const SizedBox(height: 7),
                          if (group.$2 != LedgerLineKind.asset)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 5),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Recorded category',
                                      style: JournalPalette.small,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 105,
                                    child: Text(
                                      'Month',
                                      textAlign: TextAlign.right,
                                      style: JournalPalette.small,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 95,
                                    child: Text(
                                      'Day',
                                      textAlign: TextAlign.right,
                                      style: JournalPalette.small,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          for (final line in visible.where(
                            (line) => line.kind == group.$2,
                          ))
                            _row(line, narrow),
                          const SizedBox(height: 13),
                        ],
                      for (final line in visible.where(
                        (line) => line.kind == LedgerLineKind.totalAssets,
                      ))
                        _row(line, narrow, total: true),
                      if (!frame.lines.any(
                        (line) =>
                            line.kind == LedgerLineKind.income ||
                            line.kind == LedgerLineKind.expense,
                      ))
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            'No income or expenses are recorded in this ledger period.',
                            key: ValueKey('journal-ledger-empty'),
                            style: JournalPalette.small,
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('journal-ledger-close'),
                      onPressed: _command(frame, frame.closeAction, revision),
                      icon: Icon(
                        frame.management ? Icons.arrow_back : Icons.check,
                        size: 17,
                      ),
                      label: Text(
                        frame.management ? 'Back to organisation' : 'Continue',
                      ),
                    ),
                    Text(
                      'Page ${frame.page + 1} of ${frame.pageCount}',
                      key: const ValueKey('journal-ledger-page'),
                      style: JournalPalette.small,
                    ),
                    for (final action in frame.controls.where(
                      (action) => action != frame.closeAction,
                    ))
                      Tooltip(
                        message: _pageHint(frame, action),
                        excludeFromSemantics: true,
                        child: OutlinedButton(
                          key: ValueKey('journal-ledger-control:${action.key}'),
                          onPressed: _command(frame, action, revision),
                          child: Semantics(
                            excludeSemantics: true,
                            label: _pageHint(frame, action),
                            child: Text(_label(action)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _row(
    LedgerReportLine line,
    bool narrow, {
    bool total = false,
  }) => MechanicsTooltip(
    message:
        '${line.label}: ${_money(line.amount)}${line.kind == LedgerLineKind.income || line.kind == LedgerLineKind.expense ? ' this ledger period; ${_money(line.dailyAmount)} recorded today. These are recorded totals, not next-day estimates.' : '. Unsold equipment values need a sale before they become cash; recorded cash is already spendable.'}\n\nOpen Money & ledger guide for category totals, recorded crew income, recurring costs and why estimates differ.',
    child: Container(
      key: ValueKey('journal-ledger-row:${line.id}'),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: JournalPalette.rule.withValues(alpha: .5)),
        ),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  line.label,
                  style: total ? JournalPalette.heading : JournalPalette.body,
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 18,
                  runSpacing: 3,
                  children: [
                    Text(
                      _money(line.amount),
                      style: JournalPalette.body.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (line.kind == LedgerLineKind.income ||
                        line.kind == LedgerLineKind.expense)
                      Text(
                        'Day ${_money(line.dailyAmount)}',
                        style: JournalPalette.small,
                      ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(
                    line.label,
                    style: total ? JournalPalette.heading : JournalPalette.body,
                  ),
                ),
                SizedBox(
                  width: 105,
                  child: Text(
                    _money(line.amount),
                    textAlign: TextAlign.right,
                    style: JournalPalette.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (line.kind == LedgerLineKind.income ||
                    line.kind == LedgerLineKind.expense)
                  SizedBox(
                    width: 95,
                    child: Text(
                      _money(line.dailyAmount),
                      textAlign: TextAlign.right,
                      style: JournalPalette.small,
                    ),
                  ),
              ],
            ),
    ),
  );

  String _label(ConsoleAction action) => stripConsoleColors(
    action.label,
  ).replaceFirst(RegExp(r'^\S+\s+-\s+'), '').trim();

  String _pageHint(LedgerReportFrame frame, ConsoleAction action) {
    final label = _label(action);
    if (const {'[', ';', ',', 'PageUp'}.contains(action.key) &&
        frame.page == 0) {
      return '$label (wraps to last)';
    }
    if (const {']', '.', 'PageDown'}.contains(action.key) &&
        frame.page == frame.pageCount - 1) {
      return '$label (wraps to first)';
    }
    return label;
  }

  String _money(int value, {bool signed = false}) =>
      '${value < 0
          ? '-'
          : signed && value > 0
          ? '+'
          : ''}\$${value.abs()}';
}
