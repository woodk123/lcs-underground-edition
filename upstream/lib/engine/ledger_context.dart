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

void describeLedgerReport(Console console, LedgerReportFrame frame) =>
    _ledgerFrames[console] = frame;

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
