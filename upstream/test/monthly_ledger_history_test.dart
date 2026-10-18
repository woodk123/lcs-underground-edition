import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/modern/monthly_ledger_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

LedgerReportFrame _report({
  int campaignId = 1,
  DateTime? date,
  bool management = false,
  int net = 345,
}) {
  final reportedAt = date ?? DateTime(2023, 2, 1);
  return LedgerReportFrame(
    management: management,
    campaignId: campaignId,
    reportedAt: reportedAt,
    period: DateTime(reportedAt.year, reportedAt.month - (management ? 0 : 1)),
    page: 0,
    pageCount: 2,
    cash: 500,
    monthlyNet: net,
    dailyNet: 20,
    totalLiquidAssets: 600,
    closeAction: const ConsoleAction(
      key: 'Enter',
      label: 'Continue',
      enabled: true,
      y: 24,
      x: 0,
      width: 10,
    ),
    navigation: null,
    lines: const [
      LedgerReportLine(
        id: 'income:donations',
        label: 'Donations',
        kind: LedgerLineKind.income,
        amount: 345,
        dailyAmount: 20,
        page: 0,
      ),
      LedgerReportLine(
        id: 'asset:Cash',
        label: 'Cash',
        kind: LedgerLineKind.asset,
        amount: 500,
        dailyAmount: 0,
        page: 1,
      ),
    ],
    controls: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh campaigns do not invent previous monthly accounts', () async {
    final history = MonthlyLedgerHistoryStore();
    addTearDown(history.dispose);
    await history.observe(1, DateTime(2023, 2, 2));
    expect(history.loaded, isTrue);
    expect(history.latest, isNull);
  });

  test(
    'completed source report survives reset and restart with exact values',
    () async {
      final history = MonthlyLedgerHistoryStore();
      final frame = _report();
      await history.observe(1, DateTime(2023, 2, 1), completed: frame);
      expect(history.latest!.period, DateTime(2023, 1));
      expect(history.latest!.cash, frame.cash);
      expect(history.latest!.monthlyNet, frame.monthlyNet);
      expect(history.latest!.dailyNet, frame.dailyNet);
      expect(history.latest!.totalLiquidAssets, frame.totalLiquidAssets);
      expect(history.latest!.pageCount, 2);
      history.dispose();
      final reopened = MonthlyLedgerHistoryStore();
      addTearDown(reopened.dispose);
      await reopened.observe(1, DateTime(2023, 2, 4));
      expect(reopened.latest!.lines.map((line) => line.amount), [345, 500]);
      expect(() => reopened.latest!.lines.clear(), throwsUnsupportedError);
    },
  );

  test(
    'manual reports, wrong campaigns and future observations never become history',
    () async {
      final history = MonthlyLedgerHistoryStore();
      addTearDown(history.dispose);
      await history.observe(
        1,
        DateTime(2023, 2, 1),
        completed: _report(management: true),
      );
      expect(history.latest, isNull);
      await history.observe(
        1,
        DateTime(2023, 2, 1),
        completed: _report(campaignId: 2),
      );
      expect(history.latest, isNull);
      await history.observe(1, DateTime(2023, 1, 31), completed: _report());
      expect(history.latest, isNull);
    },
  );

  test(
    'history is bounded to latest actual report, including year rollover',
    () async {
      final history = MonthlyLedgerHistoryStore();
      addTearDown(history.dispose);
      await history.observe(
        1,
        DateTime(2024, 1, 1),
        completed: _report(date: DateTime(2024, 1, 1), net: 567),
      );
      await history.observe(
        1,
        DateTime(2024, 2, 1),
        completed: _report(date: DateTime(2024, 2, 1), net: 678),
      );
      await history.observe(
        1,
        DateTime(2024, 2, 1),
        completed: _report(date: DateTime(2024, 1, 1)),
      );
      expect(history.latest!.period, DateTime(2024, 1));
      expect(history.latest!.monthlyNet, 678);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'monthlyLedgerHistory.v1.1'});
    },
  );

  test(
    'campaign switches isolate records and older save removes future history',
    () async {
      final history = MonthlyLedgerHistoryStore();
      addTearDown(history.dispose);
      await history.observe(1, DateTime(2023, 2, 1), completed: _report());
      await history.observe(2, DateTime(2023, 2, 1));
      expect(history.latest, isNull);
      await history.observe(1, DateTime(2023, 2, 1));
      expect(history.latest, isNotNull);
      await history.observe(1, DateTime(2023, 1, 15), completed: _report());
      expect(history.latest, isNull);
      final restarted = MonthlyLedgerHistoryStore();
      addTearDown(restarted.dispose);
      await restarted.observe(1, DateTime(2023, 1, 15));
      expect(restarted.latest, isNull);
    },
  );

  test(
    'late preference load from previous campaign cannot overwrite new campaign',
    () async {
      final gate = Completer<SharedPreferences>();
      var loads = 0;
      final history = MonthlyLedgerHistoryStore(
        preferences: () {
          loads++;
          return loads == 1 ? gate.future : SharedPreferences.getInstance();
        },
      );
      addTearDown(history.dispose);
      final old = history.observe(
        1,
        DateTime(2023, 2, 1),
        completed: _report(),
      );
      await Future<void>.delayed(Duration.zero);
      await history.observe(
        2,
        DateTime(2023, 2, 1),
        completed: _report(campaignId: 2, net: 222),
      );
      gate.complete(await SharedPreferences.getInstance());
      await old;
      expect(history.latest!.monthlyNet, 222);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('monthlyLedgerHistory.v1.1'), isFalse);
    },
  );

  test('unavailable preferences keep in-memory source report usable', () async {
    final history = MonthlyLedgerHistoryStore(
      preferences: () async => throw StateError('unavailable'),
    );
    addTearDown(history.dispose);
    await history.observe(1, DateTime(2023, 2, 1), completed: _report());
    expect(history.loaded, isTrue);
    expect(history.latest!.monthlyNet, 345);
  });

  test(
    'corrupt local report never blocks ledger or fabricates history',
    () async {
      SharedPreferences.setMockInitialValues({
        'monthlyLedgerHistory.v1.1': '{broken',
      });
      final history = MonthlyLedgerHistoryStore();
      addTearDown(history.dispose);
      await history.observe(1, DateTime(2023, 2, 1));
      expect(history.loaded, isTrue);
      expect(history.latest, isNull);
      await history.observe(1, DateTime(2023, 2, 1), completed: _report());
      expect(history.latest!.monthlyNet, 345);
    },
  );

  test('disposed pending load cannot emit or write a report', () async {
    final gate = Completer<SharedPreferences>();
    final history = MonthlyLedgerHistoryStore(preferences: () => gate.future);
    final observation = history.observe(
      1,
      DateTime(2023, 2, 1),
      completed: _report(),
    );
    history.dispose();
    gate.complete(await SharedPreferences.getInstance());
    await observation;
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('source completion metadata rejects replaced and manual frames', () {
    final console = Console();
    final previous = _report();
    final current = _report(net: 999);
    describeLedgerReport(console, previous);
    describeLedgerReport(console, current);
    completeLedgerReport(console, previous);
    expect(completedLedgerReport(console), isNull);
    completeLedgerReport(console, current);
    expect(completedLedgerReport(console), same(current));
    final manual = _report(management: true);
    describeLedgerReport(console, manual);
    completeLedgerReport(console, manual);
    expect(completedLedgerReport(console), same(current));
  });
}
