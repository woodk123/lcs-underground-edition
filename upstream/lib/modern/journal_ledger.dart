import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/monthly_ledger_history.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/utils/interface_options.dart';

/// An account book of the original report's recorded figures and stock values.
/// It never recalculates income, expenses, sale prices or game balances.
class JournalLedgerOverview extends StatefulWidget {
  const JournalLedgerOverview({
    super.key,
    required this.console,
    required this.onAction,
    this.history,
  });
  final Console console;
  final ValueChanged<String> onAction;
  final MonthlyLedgerHistoryStore? history;

  @override
  State<JournalLedgerOverview> createState() => JournalLedgerOverviewState();
}

class JournalLedgerOverviewState extends State<JournalLedgerOverview> {
  bool _previous = false;
  int _historyPage = 0;
  Console get console => widget.console;
  MonthlyLedgerSnapshot? get _snapshot =>
      _previous && ledgerReportFrame(console)?.management == true
      ? widget.history?.latest
      : null;

  /// Historical accounts are a local reader. Keyboard page and close keys must
  /// not reach the live ledger waiting underneath them.
  bool handleGameShortcut(KeyEvent event) {
    final snapshot = _snapshot;
    if (snapshot == null) return false;
    final key = event.logicalKey;
    final character = event.character;
    final code = character != null && character.length == 1
        ? character.toLowerCase().codeUnitAt(0)
        : null;
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space ||
        code != null && isBackKey(code)) {
      setState(() => _previous = false);
    } else if (code != null && isPageUp(code) ||
        {
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.pageUp,
        }.contains(key)) {
      _turnHistoryPage(-1, snapshot);
    } else if (code != null && isPageDown(code) ||
        {
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.pageDown,
        }.contains(key)) {
      _turnHistoryPage(1, snapshot);
    }
    return true;
  }

  void _turnHistoryPage(int delta, MonthlyLedgerSnapshot snapshot) {
    if (!identical(_snapshot, snapshot)) return;
    setState(() {
      _historyPage = (_historyPage + delta) % snapshot.pageCount;
    });
  }

  String _period(DateTime date) => '${getMonth(date.month)} ${date.year}';

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
      if (_snapshot == null &&
          console.revision.value == revision &&
          ledgerReportFrame(console) == frame &&
          console.actions.contains(action) &&
          console.lastKey == null) {
        widget.onAction(action.key);
      }
    };
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      console.revision,
      if (widget.history != null) widget.history!,
    ]),
    builder: (context, _) {
      final frame = ledgerReportFrame(console);
      if (frame == null) return const SizedBox.shrink();
      final revision = console.revision.value;
      final preferences = JournalPreferences.of(context);
      final snapshot = _snapshot;
      final lines = snapshot?.lines ?? frame.lines;
      final pageCount = snapshot?.pageCount ?? frame.pageCount;
      final page = snapshot == null ? frame.page : _historyPage % pageCount;
      return LayoutBuilder(
        builder: (context, bounds) {
          final narrow = bounds.maxWidth < 650;
          final visible = lines.where((line) => line.page == page).toList();
          return JournalSurface(
            key: const ValueKey('journal-ledger'),
            lined: true,
            padding: EdgeInsets.all(
              preferences.compact
                  ? 8
                  : narrow
                  ? 12
                  : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    key: ValueKey(
                      'journal-ledger-scroll:${snapshot == null ? 'current' : 'history'}:$page',
                    ),
                    children: [
                      const Text(
                        'Financial ledger',
                        style: JournalPalette.title,
                      ),
                      const SizedBox(height: 5),
                      const DecisionGuideButton(topic: DecisionTopic.ledger),
                      Text(
                        snapshot != null
                            ? '${_period(snapshot.period)} · completed month'
                            : frame.management
                            ? '${_period(frame.period)} · current month'
                            : '${_period(frame.period)} · month-end financial report',
                        key: const ValueKey('journal-ledger-period'),
                        style: JournalPalette.body,
                      ),
                      if (frame.management &&
                          widget.history?.latest != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          children: [
                            ChoiceChip(
                              key: const ValueKey('journal-ledger-current-tab'),
                              label: const Text('Current month'),
                              selected: snapshot == null,
                              onSelected: (_) =>
                                  setState(() => _previous = false),
                            ),
                            ChoiceChip(
                              key: const ValueKey('journal-ledger-history-tab'),
                              label: Text(
                                'Last closed · ${_period(widget.history!.latest!.period)}',
                              ),
                              selected: snapshot != null,
                              onSelected: (_) => setState(() {
                                _previous = true;
                                _historyPage = 0;
                              }),
                            ),
                          ],
                        ),
                      ],
                      if (snapshot != null) ...[
                        const SizedBox(height: 7),
                        Text(
                          'Read-only copy recorded ${snapshot.reportedAt.day} ${_period(snapshot.reportedAt)}. '
                          'Cash and stock values are from that report. The latest completed report is kept locally on this device.',
                          key: const ValueKey('journal-ledger-history-note'),
                          style: JournalPalette.small,
                        ),
                      ],
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
                                      snapshot == null
                                          ? 'Cash available'
                                          : 'Cash at close',
                                      snapshot?.cash ?? frame.cash,
                                      'cash',
                                      false,
                                    ),
                                    (
                                      'Monthly net',
                                      snapshot?.monthlyNet ?? frame.monthlyNet,
                                      'monthly-net',
                                      true,
                                    ),
                                    (
                                      'Daily net',
                                      snapshot?.dailyNet ?? frame.dailyNet,
                                      'daily-net',
                                      true,
                                    ),
                                    (
                                      'Liquid assets',
                                      snapshot?.totalLiquidAssets ??
                                          frame.totalLiquidAssets,
                                      'assets',
                                      false,
                                    ),
                                  ])
                                SizedBox(
                                  width: width,
                                  child: Container(
                                    padding: EdgeInsets.all(
                                      preferences.compact ? 6 : 10,
                                    ),
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
                      if (frame.management && snapshot == null) ...[
                        const Text(
                          'Month totals restart after monthly accounting. Day figures show the latest processed day, which may belong to the previous month.',
                          key: ValueKey('journal-ledger-reset-note'),
                          style: JournalPalette.small,
                        ),
                        const SizedBox(height: 7),
                      ],
                      const Text(
                        'Inventory uses the game’s fence values for stock held at safehouses. '
                        'It is not spendable cash until sold.',
                        style: JournalPalette.small,
                      ),
                      if (!frame.management) ...[
                        const SizedBox(height: 7),
                        const Text(
                          'Review this report, then Continue to finish the month-end accounting. '
                          'The new month’s totals start from zero. This completed report remains available in Ledger on this device.',
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
                            _row(line, narrow, compact: preferences.compact),
                          const SizedBox(height: 13),
                        ],
                      for (final line in visible.where(
                        (line) => line.kind == LedgerLineKind.totalAssets,
                      ))
                        _row(
                          line,
                          narrow,
                          total: true,
                          compact: preferences.compact,
                        ),
                      if (!lines.any(
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
                    if (snapshot != null) ...[
                      FilledButton.icon(
                        key: const ValueKey('journal-ledger-history-close'),
                        onPressed: () => setState(() => _previous = false),
                        icon: const Icon(Icons.arrow_back, size: 17),
                        label: const Text('Return to current ledger'),
                      ),
                      Text(
                        'Page ${page + 1} of $pageCount',
                        style: JournalPalette.small,
                      ),
                      if (pageCount > 1) ...[
                        OutlinedButton(
                          key: const ValueKey(
                            'journal-ledger-history-previous',
                          ),
                          onPressed: () => _turnHistoryPage(-1, snapshot),
                          child: const Text('Previous page'),
                        ),
                        OutlinedButton(
                          key: const ValueKey('journal-ledger-history-next'),
                          onPressed: () => _turnHistoryPage(1, snapshot),
                          child: const Text('Next page'),
                        ),
                      ],
                    ] else ...[
                      FilledButton.icon(
                        key: const ValueKey('journal-ledger-close'),
                        onPressed: _command(frame, frame.closeAction, revision),
                        icon: Icon(
                          frame.management ? Icons.arrow_back : Icons.check,
                          size: 17,
                        ),
                        label: JournalCommandLabel(
                          shortcut: frame.closeAction.key,
                          primary: true,
                          label: frame.management
                              ? 'Back to organisation'
                              : 'Continue',
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
                            key: ValueKey(
                              'journal-ledger-control:${action.key}',
                            ),
                            onPressed: _command(frame, action, revision),
                            child: Semantics(
                              excludeSemantics: true,
                              label: _pageHint(frame, action),
                              hint:
                                  'Keyboard shortcut: ${journalShortcutSpokenLabel(action.key)}',
                              child: JournalCommandLabel(
                                shortcut: action.key,
                                label: _label(action),
                              ),
                            ),
                          ),
                        ),
                    ],
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
    bool compact = false,
  }) => MechanicsTooltip(
    message:
        '${line.label}: ${_money(line.amount)}${line.kind == LedgerLineKind.income || line.kind == LedgerLineKind.expense ? ' this ledger period; ${_money(line.dailyAmount)} recorded today. These are recorded totals, not next-day estimates.' : '. Unsold equipment values need a sale before they become cash; recorded cash is already spendable.'}\n\nOpen Money & ledger guide for category totals, recorded crew income, recurring costs and why estimates differ.',
    child: Container(
      key: ValueKey('journal-ledger-row:${line.id}'),
      padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8, horizontal: 4),
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
