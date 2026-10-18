import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/console.dart';

enum LedgerLineKind { income, expense, asset, totalAssets }

@immutable
class LedgerReportLine {
  const LedgerReportLine({
    required this.id,
    required this.label,
    required this.kind,
    required this.amount,
    required this.dailyAmount,
    required this.page,
  });
  final String id;
  final String label;
  final LedgerLineKind kind;
  final int amount;
  final int dailyAmount;
  final int page;
}

/// Values and pagination computed by the original funding-report handler.
/// A manual report can be left safely; the automatic month-end report retains
/// its explicit acknowledgement before the caller resets monthly amounts.
@immutable
class LedgerReportFrame {
  LedgerReportFrame({
    required this.management,
    required this.campaignId,
    required this.reportedAt,
    required this.period,
    required this.page,
    required this.pageCount,
    required this.cash,
    required this.monthlyNet,
    required this.dailyNet,
    required this.totalLiquidAssets,
    required this.closeAction,
    required this.navigation,
    required List<LedgerReportLine> lines,
    required List<ConsoleAction> controls,
  }) : lines = List.unmodifiable(lines),
       controls = List.unmodifiable(controls);

  final bool management;
  final int campaignId;

  /// Campaign date when this source report was prepared. Monthly accounting
  /// runs on the first of the next month, after the final day's work.
  final DateTime reportedAt;
  final DateTime period;
  final int page;
  final int pageCount;
  final int cash;
  final int monthlyNet;
  final int dailyNet;
  final int totalLiquidAssets;
  final ConsoleAction closeAction;
  final ConsoleNavigation? navigation;
  final List<LedgerReportLine> lines;
  final List<ConsoleAction> controls;
}

final _ledgerFrames = Expando<LedgerReportFrame>();
final _completedLedgerReports = Expando<LedgerReportFrame>();

void describeLedgerReport(Console console, LedgerReportFrame frame) =>
    _ledgerFrames[console] = frame;

/// Called only by the original report after its acknowledgement returns. This
/// records source values, not another input reader or a replayable action.
void completeLedgerReport(Console console, LedgerReportFrame frame) {
  if (!console.awaitingInput &&
      !frame.management &&
      identical(_ledgerFrames[console], frame)) {
    _completedLedgerReports[console] = frame;
  }
}

LedgerReportFrame? completedLedgerReport(Console console) =>
    _completedLedgerReports[console];

LedgerReportFrame? ledgerReportFrame(Console console) {
  final frame = _ledgerFrames[console];
  return console.awaitingInput &&
          !console.textInput &&
          console.screen == 'ledger-report' &&
          frame != null &&
          identical(console.navigation, frame.navigation) &&
          console.actions.contains(frame.closeAction)
      ? frame
      : null;
}
