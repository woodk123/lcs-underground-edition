import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/monthly_ledger_history.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

/// Keep the real R -> V caller alive so closing a report must return one level.
class _FinanceJourney {
  _FinanceJourney() {
    unawaited(_run());
  }

  bool stopped = false, finished = false;

  Future<void> _run() async {
    try {
      while (!stopped) {
        engine.erase();
        final site = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(site);
        baseModeOptionsDisplay(site);
        final key = await engine.getKey();
        if (stopped) break;
        if (key == engine.Key.r) await reviewAssetsAndFormSquads();
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    stopped = true;
    for (var step = 0; step < 60 && !finished; step++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Escape');
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));
String _snapshot() => jsonEncode(game.gameState.toJson());

const _pageKeys = <(LogicalKeyboardKey, String?, int)>[
  (LogicalKeyboardKey.bracketLeft, '[', -1),
  (LogicalKeyboardKey.bracketRight, ']', 1),
  (LogicalKeyboardKey.semicolon, ';', -1),
  (LogicalKeyboardKey.period, '.', 1),
  (LogicalKeyboardKey.comma, ',', -1),
  (LogicalKeyboardKey.period, '.', 1),
  (LogicalKeyboardKey.arrowLeft, null, -1),
  (LogicalKeyboardKey.arrowRight, null, 1),
  (LogicalKeyboardKey.arrowUp, null, -1),
  (LogicalKeyboardKey.arrowDown, null, 1),
  (LogicalKeyboardKey.pageUp, null, -1),
  (LogicalKeyboardKey.pageDown, null, 1),
];
const _backKeys = <(LogicalKeyboardKey, String?)>[
  (LogicalKeyboardKey.enter, null),
  (LogicalKeyboardKey.escape, null),
  (LogicalKeyboardKey.keyX, 'x'),
  (LogicalKeyboardKey.keyX, 'X'),
  (LogicalKeyboardKey.space, ' '),
];

Future<void> _settle(WidgetTester tester) async {
  for (var step = 0; step < 25; step++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _gameKey(
  WidgetTester tester,
  LogicalKeyboardKey key, [
  String? character,
]) async {
  final gameFocus = tester
      .widgetList<Focus>(find.byType(Focus))
      .singleWhere((widget) => widget.focusNode?.debugLabel == 'Game keyboard')
      .focusNode!;
  gameFocus.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(key, character: character);
  await _settle(tester);
}

Future<void> _openLedger(WidgetTester tester) async {
  if (engine.console.screen == 'headquarters') {
    await _gameKey(tester, LogicalKeyboardKey.keyR, 'r');
  }
  expect(engine.console.screen, 'organisation');
  await _gameKey(tester, LogicalKeyboardKey.keyV, 'v');
  expect(ledgerReportFrame(engine.console)?.management, isTrue);
}

void _populatePages() {
  for (final income in Income.values) {
    game.ledger.income[income] = income.index + 1;
  }
  for (final expense in Expense.values) {
    game.ledger.expense[expense] = expense.index + 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      sans.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await Future.wait([serif.load(), sans.load()]);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    journalReadingScale.value = 1;
    journalPresentation.value = const JournalPreferenceValues();
  });

  Future<void> mount(WidgetTester tester, {bool classic = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final journey = _FinanceJourney();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await journey.stop(tester);
      journalReadingScale.value = 1;
      journalPresentation.value = const JournalPreferenceValues();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
    if (classic) {
      await tester.tap(find.byTooltip('Switch readable / classic view'));
      await _settle(tester);
    }
  }

  for (final classic in [false, true]) {
    testWidgets(
      '${classic ? 'Classic' : 'Graphical'} ledger retains all source page and Back keys and its caller',
      (tester) async {
        _populatePages();
        await mount(tester, classic: classic);
        final before = _snapshot();
        reseedRNG(seed: 20261021);
        final expectedRolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 20261021);
        await _openLedger(tester);
        final pageCount = ledgerReportFrame(engine.console)!.pageCount;
        expect(pageCount, greaterThan(1));
        var page = 0;
        for (final key in _pageKeys) {
          await _gameKey(tester, key.$1, key.$2);
          page = (page + key.$3) % pageCount;
          expect(ledgerReportFrame(engine.console)?.page, page);
        }
        for (final key in _backKeys) {
          await _gameKey(tester, key.$1, key.$2);
          expect(ledgerReportFrame(engine.console), isNull);
          expect(engine.console.screen, 'organisation');
          expect(engine.console.navigation?.section, 'people');
          await _openLedger(tester);
        }
        expect(_snapshot(), before);
        expect(List.generate(8, (_) => lcsRandom(100000)), expectedRolls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('focused ledger page controls retain source Enter and Space', (
    tester,
  ) async {
    _populatePages();
    await mount(tester);
    final before = _snapshot();
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      await _openLedger(tester);
      final next = ledgerReportFrame(engine.console)!.controls.singleWhere(
        (action) => const {']', '.', 'PageDown'}.contains(action.key),
      );
      final label = find.descendant(
        of: _key('journal-ledger-control:${next.key}'),
        matching: find.byType(JournalCommandLabel),
      );
      Focus.of(tester.element(label)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(
        key,
        character: key == LogicalKeyboardKey.space ? ' ' : null,
      );
      await _settle(tester);
      expect(ledgerReportFrame(engine.console), isNull);
      expect(engine.console.screen, 'organisation');
    }
    expect(_snapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one-page ledger preserves the source any-key acknowledgement', (
    tester,
  ) async {
    await mount(tester);
    final before = _snapshot();
    for (final key in [
      (LogicalKeyboardKey.keyQ, 'q'),
      (LogicalKeyboardKey.bracketRight, ']'),
      (LogicalKeyboardKey.space, ' '),
    ]) {
      await _openLedger(tester);
      expect(ledgerReportFrame(engine.console)?.pageCount, 1);
      await _gameKey(tester, key.$1, key.$2);
      expect(ledgerReportFrame(engine.console), isNull);
      expect(engine.console.screen, 'organisation');
    }
    expect(_snapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'historical ledger uses source aliases without answering live accounts',
    (tester) async {
      _populatePages();
      game.gameState.date = DateTime(2023, 2, 1);
      final report = fundReport(false);
      await _settle(tester);
      expect(engine.console.sendInput('Enter'), isTrue);
      await _settle(tester);
      await report;
      final history = MonthlyLedgerHistoryStore();
      await history.observe(
        game.gameState.uniqueGameId,
        game.date,
        completed: completedLedgerReport(engine.console),
      );
      expect(history.latest?.pageCount, greaterThan(1));
      history.dispose();
      game.ledger.resetMonthlyAmounts();
      await mount(tester);
      await _openLedger(tester);
      final live = ledgerReportFrame(engine.console)!;
      final revision = engine.console.revision.value;
      final before = _snapshot();
      final tab = _key('journal-ledger-history-tab');
      await tester.ensureVisible(tab);
      await tester.tap(tab);
      await _settle(tester);
      final pageCount = completedLedgerReport(engine.console)!.pageCount;
      var page = 0;
      for (final key in _pageKeys) {
        await _gameKey(tester, key.$1, key.$2);
        page = (page + key.$3) % pageCount;
        expect(find.text('Page ${page + 1} of $pageCount'), findsOneWidget);
        expect(ledgerReportFrame(engine.console), same(live));
        expect(engine.console.revision.value, revision);
      }
      for (final key in _backKeys) {
        await _gameKey(tester, key.$1, key.$2);
        expect(_key('journal-ledger-history-close'), findsNothing);
        expect(ledgerReportFrame(engine.console), same(live));
        expect(engine.console.revision.value, revision);
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await _settle(tester);
      }
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
