import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/modern/journal_ledger.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/monthly_ledger_history.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _key(String key) => find.byKey(ValueKey(key));
typedef _Step = String Function(LedgerReportFrame frame);

Future<void> _drive(
  List<_Step> steps, {
  bool management = true,
  Future<void> Function()? run,
}) async {
  var index = 0;
  void respond() {
    if (!engine.console.awaitingInput || engine.console.lastKey != null) return;
    expect(index, lessThan(steps.length));
    final frame = ledgerReportFrame(engine.console)!;
    expect(engine.console.sendInput(steps[index++](frame)), isTrue);
  }

  engine.console.revision.addListener(respond);
  try {
    await (run?.call() ?? fundReport(false, management: management)).timeout(
      const Duration(seconds: 5),
    );
  } finally {
    engine.console.revision.removeListener(respond);
  }
  expect(index, steps.length);
}

ConsoleAction _page(LedgerReportFrame frame, {bool forward = true}) =>
    frame.controls.singleWhere(
      (action) =>
          (forward
                  ? const {']', '.', 'PageDown'}
                  : const {'[', ';', ',', 'PageUp'})
              .contains(action.key),
    );

class _LedgerHarness {
  _LedgerHarness(bool management) {
    unawaited(_run(management));
  }
  bool returned = false, finished = false;
  Future<void> _run(bool management) async {
    try {
      await fundReport(false, management: management);
      returned = true;
      engine.erase();
      engine.console.screen = 'headquarters';
      await engine.getKey();
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    for (var i = 0; i < 50 && !finished; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Escape');
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    engine.console = Console();
  });

  test(
    'legacy missing categories are zero for presentation and never written into saves',
    () async {
      expect(game.ledger.income.containsKey(Income.ransom), isFalse);
      expect(game.ledger.expense.containsKey(Expense.hospitalBills), isFalse);
      final before = _snapshot();
      reseedRNG(seed: 80912);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 80912);
      await _drive([
        (frame) {
          expect(frame.pageCount, 1);
          expect(frame.cash, 7);
          expect(frame.monthlyNet, 0);
          expect(frame.dailyNet, 0);
          expect(
            frame.lines.any(
              (line) =>
                  line.kind == LedgerLineKind.income ||
                  line.kind == LedgerLineKind.expense,
            ),
            isFalse,
          );
          expect(
            engine.console.buffer
                .expand((row) => row)
                .map((cell) => cell.glyph)
                .join(),
            isNot(contains('null')),
          );
          expect(engine.console.navigation?.section, 'ledger');
          expect(frame.navigation, same(engine.console.navigation));
          return frame.closeAction.key;
        },
      ]);
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'report captures original net, daily values and stock valuation without UI formulas',
    () async {
      game.ledger.income[Income.donations] = 1500;
      game.ledger.income[Income.artSales] = 300;
      game.ledger.expense[Expense.rent] = 500;
      game.ledger.expense[Expense.training] = 100;
      game.ledger.dailyIncome[Income.donations] = 90;
      game.ledger.dailyIncome[Income.artSales] = 30;
      game.ledger.dailyExpense[Expense.training] = 20;
      final stock = Weapon(game.squad.first.weapon.typeName, stackSize: 2);
      final base = game.activeSquad!.site!;
      base.loot.clear();
      base.loot.add(stock);
      final before = _snapshot();
      await _drive([
        (frame) {
          expect(frame.monthlyNet, 1200);
          expect(frame.dailyNet, 100);
          final weapons = frame.lines.singleWhere(
            (line) => line.label == 'Tools and Weapons',
          );
          expect(weapons.amount, (stock.type.fenceValue * 2).round());
          expect(frame.totalLiquidAssets, 7 + weapons.amount);
          expect(
            frame.lines
                .singleWhere((line) => line.id == 'income:donations')
                .dailyAmount,
            90,
          );
          return frame.closeAction.key;
        },
      ]);
      expect(_snapshot(), before);
    },
  );

  test(
    'source report pages and original keyboard wrap remain intact',
    () async {
      for (final income in Income.values) {
        game.ledger.income[income] = income.index + 1;
      }
      for (final expense in Expense.values) {
        game.ledger.expense[expense] = expense.index + 1;
      }
      final before = _snapshot();
      await _drive([
        (frame) {
          expect(frame.page, 0);
          expect(frame.pageCount, 3);
          expect(
            frame.lines
                .where((line) => line.kind == LedgerLineKind.income)
                .length,
            Income.values.length,
          );
          return _page(frame, forward: false).key;
        },
        (frame) {
          expect(frame.page, 2);
          expect(
            frame.lines
                .where((line) => line.page == frame.page)
                .every(
                  (line) =>
                      line.kind == LedgerLineKind.asset ||
                      line.kind == LedgerLineKind.totalAssets,
                ),
            isTrue,
          );
          return _page(frame).key;
        },
        (frame) {
          expect(frame.page, 0);
          return frame.closeAction.key;
        },
      ]);
      expect(_snapshot(), before);
    },
  );

  test(
    'new month retains actual latest-day figures after monthly totals reset',
    () async {
      game.gameState.date = DateTime(2023, 2, 1);
      game.ledger.resetMonthlyAmounts();
      game.ledger.dailyIncome[Income.donations] = 7;
      game.ledger.dailyIncome[Income.embezzlement] = 127;
      game.ledger.dailyExpense[Expense.groceries] = 5;
      game.ledger.dailyExpense[Expense.rent] = 20;
      final before = _snapshot();
      reseedRNG(seed: 48901);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 48901);
      await _drive([
        (frame) {
          expect(frame.monthlyNet, 0);
          expect(frame.dailyNet, 109);
          final entries = frame.lines
              .where(
                (line) =>
                    line.kind == LedgerLineKind.income ||
                    line.kind == LedgerLineKind.expense,
              )
              .toList();
          expect(entries.map((line) => line.id), [
            'income:donations',
            'income:embezzlement',
            'expense:groceries',
            'expense:rent',
          ]);
          expect(entries.map((line) => line.amount), [0, 0, 0, 0]);
          expect(entries.map((line) => line.dailyAmount), [7, 127, 5, 20]);
          return frame.closeAction.key;
        },
      ]);
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'month-end report remains untagged and monthly reset waits for explicit acknowledgement',
    () async {
      game.ledger.income[Income.donations] = 345;
      var reset = false;
      await _drive(
        [
          (frame) {
            expect(frame.management, isFalse);
            expect(frame.navigation, isNull);
            expect(engine.console.navigation, isNull);
            expect(reset, isFalse);
            expect(game.ledger.income[Income.donations], 345);
            return frame.closeAction.key;
          },
        ],
        management: false,
        run: () async {
          await fundReport(false);
          game.ledger.resetMonthlyAmounts();
          reset = true;
        },
      );
      expect(reset, isTrue);
      expect(game.ledger.income[Income.donations], 0);
    },
  );

  Future<_LedgerHarness> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 560),
    double scale = 1,
    bool management = true,
    ValueChanged<String>? onAction,
    MonthlyLedgerHistoryStore? history,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final harness = _LedgerHarness(management);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: JournalLedgerOverview(
              console: engine.console,
              onAction: onAction ?? (key) => engine.console.sendInput(key),
              history: history,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    return harness;
  }

  testWidgets(
    'ledger renders typed values without dot rows, null values or a giant Back card',
    (tester) async {
      final before = _snapshot();
      final harness = await mount(tester);
      expect(tester.widget<Text>(_key('journal-ledger-cash')).data, '\$7');
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('. . .'), findsNothing);
      expect(_key('journal-ledger-close').hitTestable(), findsOneWidget);
      expect(tester.getRect(_key('journal-ledger-close')).height, lessThan(70));
      expect(
        find.descendant(
          of: _key('journal-ledger-close'),
          matching: _key('journal-ledger-cash'),
        ),
        findsNothing,
      );
      await tester.tap(_key('journal-ledger-close'));
      await _settle(tester);
      expect(harness.returned, isTrue);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'only acknowledged required source reports become locally retained accounts',
    () async {
      game.gameState.date = DateTime(2023, 2, 1);
      game.ledger.income[Income.donations] = 345;
      final controller = OrganisationController(console: engine.console);
      addTearDown(controller.dispose);
      LedgerReportFrame? actual;
      await _drive([
        (frame) {
          actual = frame;
          expect(frame.period, DateTime(2023, 1));
          expect(frame.reportedAt, DateTime(2023, 2, 1));
          completeLedgerReport(engine.console, frame);
          expect(completedLedgerReport(engine.console), isNull);
          expect(controller.monthlyLedgerHistory.latest, isNull);
          return frame.closeAction.key;
        },
      ], management: false);
      expect(completedLedgerReport(engine.console), same(actual));
      game.ledger.resetMonthlyAmounts();
      final before = _snapshot();
      reseedRNG(seed: 91288);
      final expectedRolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 91288);
      await _drive([
        (frame) {
          expect(frame.period, DateTime(2023, 2));
          expect(frame.monthlyNet, 0);
          return frame.closeAction.key;
        },
      ]);
      // Drain the same source metadata observation used on the next HQ reader.
      await controller.monthlyLedgerHistory.observe(
        game.gameState.uniqueGameId,
        game.date,
        completed: completedLedgerReport(engine.console),
      );
      expect(controller.monthlyLedgerHistory.latest!.monthlyNet, 345);
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), expectedRolls);
      expect(completedLedgerReport(engine.console), same(actual));
    },
  );

  testWidgets(
    'last closed accounts are a separate read-only reader after monthly reset',
    (tester) async {
      game.gameState.date = DateTime(2023, 2, 1);
      for (final income in Income.values) {
        game.ledger.income[income] = 10;
      }
      for (final expense in Expense.values) {
        game.ledger.expense[expense] = 5;
      }
      await _drive([(frame) => frame.closeAction.key], management: false);
      final history = MonthlyLedgerHistoryStore();
      addTearDown(history.dispose);
      await history.observe(
        game.gameState.uniqueGameId,
        game.date,
        completed: completedLedgerReport(engine.console),
      );
      final historicNet = history.latest!.monthlyNet;
      expect(history.latest!.pageCount, 3);
      game.ledger.resetMonthlyAmounts();
      final before = _snapshot();
      final received = <String>[];
      await mount(
        tester,
        size: const Size(760, 500),
        scale: 1.5,
        history: history,
        onAction: received.add,
      );
      expect(find.text('February 2023 · current month'), findsOneWidget);
      final oldClose = tester
          .widget<FilledButton>(_key('journal-ledger-close'))
          .onPressed!;
      final liveRevision = engine.console.revision.value;
      await tester.tap(_key('journal-ledger-history-tab'));
      await _settle(tester);
      expect(find.text('January 2023 · completed month'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('journal-ledger-monthly-net')).data,
        '+\$$historicNet',
      );
      expect(_key('journal-ledger-close'), findsNothing);
      expect(
        _key('journal-ledger-history-close').hitTestable(),
        findsOneWidget,
      );
      oldClose();
      expect(received, isEmpty);
      final view = tester.state<JournalLedgerOverviewState>(
        find.byType(JournalLedgerOverview),
      );
      expect(
        view.handleGameShortcut(
          const KeyDownEvent(
            logicalKey: LogicalKeyboardKey.keyW,
            physicalKey: PhysicalKeyboardKey.keyW,
            character: 'w',
            timeStamp: Duration.zero,
          ),
        ),
        isTrue,
      );
      await tester.tap(_key('journal-ledger-history-next'));
      await _settle(tester);
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(engine.console.revision.value, liveRevision);
      expect(ledgerReportFrame(engine.console)!.page, 0);
      expect(received, isEmpty);
      expect(_snapshot(), before);
      await tester.tap(_key('journal-ledger-history-close'));
      await _settle(tester);
      expect(find.text('February 2023 · current month'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('journal-ledger-monthly-net')).data,
        '\$0',
      );
      expect(received, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ledger UI keeps actual wrap with explicit boundary explanations',
    (tester) async {
      for (final income in Income.values) {
        game.ledger.income[income] = 10;
      }
      for (final expense in Expense.values) {
        game.ledger.expense[expense] = 5;
      }
      await mount(tester);
      final first = ledgerReportFrame(engine.console)!;
      final previous = _key(
        'journal-ledger-control:${_page(first, forward: false).key}',
      );
      final next = _key('journal-ledger-control:${_page(first).key}');
      expect(tester.widget<OutlinedButton>(previous).onPressed, isNotNull);
      expect(find.byTooltip('Previous Page (wraps to last)'), findsOneWidget);
      await tester.tap(previous);
      await _settle(tester);
      expect(ledgerReportFrame(engine.console)?.page, first.pageCount - 1);
      expect(find.byTooltip('Next Page (wraps to first)'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(next).onPressed, isNotNull);
      expect(tester.widget<OutlinedButton>(previous).onPressed, isNotNull);
      await tester.tap(next);
      await _settle(tester);
      expect(ledgerReportFrame(engine.console)?.page, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('historical ledger closes locally at 360px and 150 percent', (
    tester,
  ) async {
    game.gameState.date = DateTime(2023, 2, 1);
    await _drive([(frame) => frame.closeAction.key], management: false);
    final first = MonthlyLedgerHistoryStore();
    await first.observe(
      game.gameState.uniqueGameId,
      game.date,
      completed: completedLedgerReport(engine.console),
    );
    first.dispose();
    // The UI receives a fresh store, as after restarting the application.
    final reopened = MonthlyLedgerHistoryStore();
    addTearDown(reopened.dispose);
    await reopened.observe(game.gameState.uniqueGameId, game.date);
    final received = <String>[];
    await mount(
      tester,
      size: const Size(360, 500),
      scale: 1.5,
      history: reopened,
      onAction: received.add,
    );
    await tester.ensureVisible(_key('journal-ledger-history-tab'));
    await tester.tap(_key('journal-ledger-history-tab'));
    await _settle(tester);
    expect(_key('journal-ledger-history-close').hitTestable(), findsOneWidget);
    expect(
      tester.getRect(_key('journal-ledger-history-close')).bottom,
      lessThanOrEqualTo(500),
    );
    final view = tester.state<JournalLedgerOverviewState>(
      find.byType(JournalLedgerOverview),
    );
    expect(
      view.handleGameShortcut(
        const KeyDownEvent(
          logicalKey: LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    await _settle(tester);
    expect(received, isEmpty);
    expect(_key('journal-ledger-close').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale financial report callback cannot acknowledge another reader',
    (tester) async {
      final received = <String>[];
      await mount(tester, onAction: received.add);
      final old = tester
          .widget<FilledButton>(_key('journal-ledger-close'))
          .onPressed!;
      engine.console.flush();
      old();
      expect(received, isEmpty);
      await _settle(tester);
      final fresh = tester
          .widget<FilledButton>(_key('journal-ledger-close'))
          .onPressed!;
      engine.console.actions.remove(
        ledgerReportFrame(engine.console)!.closeAction,
      );
      fresh();
      expect(received, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(760, 500), const Size(360, 500)]) {
    testWidgets('required Continue stays visible at150percent and $size', (
      tester,
    ) async {
      game.ledger.income[Income.donations] = 345;
      await mount(tester, size: size, scale: 1.5, management: false);
      expect(find.text('Continue'), findsOneWidget);
      expect(_key('journal-ledger-close').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(_key('journal-ledger-close')).bottom,
        lessThanOrEqualTo(size.height),
      );
      expect(engine.console.navigation, isNull);
      expect(game.ledger.income[Income.donations], 345);
      expect(tester.takeException(), isNull);
    });
  }
}
