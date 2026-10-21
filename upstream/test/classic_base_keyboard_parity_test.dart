import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/invest_in_location.dart';
import 'package:lcs_new_age/engine/base_management_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/console_widget.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/location/compound.dart';
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_bases.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

/// The normal HQ I dispatch with the original investment reader underneath it.
class _BaseJourney {
  _BaseJourney() {
    unawaited(_run());
  }

  bool stopped = false, finished = false;
  final dispatched = <int>[];

  Future<void> _run() async {
    try {
      while (!stopped) {
        engine.erase();
        final site = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(site);
        baseModeOptionsDisplay(site);
        final key = await engine.getKey();
        if (stopped) break;
        dispatched.add(key);
        if (key == engine.Key.i) {
          final safehouse = game.activeSafehouse;
          if (safehouse != null &&
              safehouse.upgradable &&
              !safehouse.siege.underSiege) {
            await investInLocation(safehouse);
          }
        }
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

typedef _Checkpoint = ({
  Object campaign,
  Map<String, Object?> reader,
  List<int> rolls,
});

const _keys = [
  'i',
  'r',
  'c',
  'x',
  'i',
  'r',
  'Space',
  'i',
  'r',
  'Escape',
  'i',
  'r',
  'Enter',
];

Future<void> _settle(WidgetTester tester) async {
  for (var step = 0; step < 35; step++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _physicalKey(
  WidgetTester tester,
  String key, {
  required bool classic,
  bool restoreFocus = true,
}) async {
  if (restoreFocus) {
    if (classic) {
      tester.widget<ConsoleWidget>(find.byType(ConsoleWidget)).requestFocus();
    } else {
      tester
          .widgetList<Focus>(find.byType(Focus))
          .singleWhere(
            (widget) => widget.focusNode?.debugLabel == 'Game keyboard',
          )
          .focusNode!
          .requestFocus();
    }
    await tester.pump();
  }
  final logical = switch (key) {
    'Enter' => LogicalKeyboardKey.enter,
    'Escape' => LogicalKeyboardKey.escape,
    'Space' => LogicalKeyboardKey.space,
    _ => LogicalKeyboardKey(key.codeUnitAt(0)),
  };
  await tester.sendKeyEvent(
    logical,
    character: key.length == 1
        ? key
        : key == 'Space'
        ? ' '
        : null,
  );
  await _settle(tester);
}

Future<void> _click(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await _settle(tester);
}

_Checkpoint _capture(_BaseJourney source) {
  final console = engine.console;
  final navigation = console.navigation;
  return (
    campaign: jsonDecode(jsonEncode(game.gameState.toJson())) as Object,
    reader: {
      'screen': console.screen,
      'awaitingInput': console.awaitingInput,
      'textInput': console.textInput,
      'pendingKey': console.lastKey != null,
      'navigation': navigation == null
          ? null
          : [navigation.section, navigation.backKey, navigation.note],
      'actions': [
        for (final action in console.actions)
          [
            action.key,
            action.label,
            action.enabled,
            action.entityType,
            action.entityId,
            action.entityCategory,
          ],
      ],
      'buffer': [
        for (final row in console.buffer) row.map((cell) => cell.glyph).join(),
      ],
      'dispatched': List<int>.of(source.dispatched),
    },
    rolls: List.generate(8, (_) => lcsRandom(1000000)),
  );
}

void _compare(_Checkpoint actual, _Checkpoint expected, String step) {
  expect(actual.reader, expected.reader, reason: '$step: original next reader');
  expect(
    actual.campaign,
    expected.campaign,
    reason: '$step: complete campaign',
  );
  expect(actual.rolls, expected.rolls, reason: '$step: gameplay RNG');
}

/// Declared fixture preparation: an empty, eligible warehouse with funds.
/// No purchase, upgrade or source outcome is supplied by the test.
Site _prepareWarehouse(String fixture) {
  SharedPreferences.setMockInitialValues({});
  engine.console = Console();
  game.gameState = decodeSaveContents(fixture).gameState!;
  game.mode = GameMode.base;
  game.activeSquadMember = null;
  final base =
      Site.fromJson(
          jsonDecode(jsonEncode(organisationBases().first.toJson()))
              as Map<String, dynamic>,
        )
        ..id = game.gameState.nextSiteId++
        ..name = 'Keyboard parity warehouse'
        ..shortName = 'Keyboard parity warehouse'
        ..frontName = null
        ..frontShortName = null
        ..type = SiteType.warehouse
        ..compound = Compound()
        ..siege = Siege()
        ..loot = []
        ..heat = 0;
  base.district.sites.add(base);
  game.activeSquad = null;
  game.activeSafehouse = base;
  game.ledger.forceSetFunds(5000);
  return base;
}

Future<List<_Checkpoint>> _run(
  WidgetTester tester,
  String fixture, {
  required bool classic,
  required double scale,
  bool pointerInvestment = false,
  List<_Checkpoint>? oracle,
}) async {
  final base = _prepareWarehouse(fixture);
  journalReadingScale.value = scale;
  journalPresentation.value = const JournalPreferenceValues();
  reseedRNG(seed: 20261021);
  final source = _BaseJourney();
  final checkpoints = <_Checkpoint>[];
  final initialFunds = game.ledger.funds;
  final initialExpense = game.ledger.expense[Expense.compoundUpgrades] ?? 0;
  final initialDate = game.date;
  var purchases = 0;
  var cameras = false;
  try {
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
    if (classic) {
      await _click(tester, find.byTooltip('Switch readable / classic view'));
    }
    checkpoints.add(_capture(source));
    if (oracle != null) _compare(checkpoints.first, oracle.first, 'Initial HQ');
    for (var index = 0; index < _keys.length; index++) {
      final key = _keys[index];
      if (pointerInvestment && index == 0) {
        await _click(tester, find.byKey(const ValueKey('journal-section:10')));
        expect(find.byType(JournalBasesView), findsOneWidget);
        await _click(tester, find.text(base.getName(includeCity: true)).first);
        await _click(
          tester,
          find.widgetWithText(OutlinedButton, 'Buy supplies & improve base'),
        );
      } else {
        await _physicalKey(
          tester,
          key,
          classic: classic,
          // Let the actual pointer-opened view retain focus for raw R.
          restoreFocus: !(pointerInvestment && index == 1),
        );
      }
      if (key == 'r') purchases++;
      if (key == 'c') cameras = true;
      final spent =
          purchases * 150 + (cameras ? CompoundUpgrade.cameras.price : 0);
      expect(base.compound.rations, purchases * 20);
      expect(base.compound.cameras, cameras);
      expect(game.ledger.funds, initialFunds - spent);
      expect(
        game.ledger.expense[Expense.compoundUpgrades] ?? 0,
        initialExpense + spent,
      );
      expect(game.date, initialDate);
      expect(engine.console.awaitingInput, isTrue);
      final back = const {'x', 'Space', 'Escape', 'Enter'}.contains(key);
      expect(
        engine.console.screen,
        back ? 'headquarters' : 'base-investment',
        reason:
            'Original ${classic ? 'Classic' : 'graphical'} key $index: $key',
      );
      if (!back) {
        expect(engine.console.navigation?.section, 'bases');
        expect(engine.console.navigation?.backKey, 'Enter');
        expect(
          engine.console.actions.any(
            (action) =>
                action.entityType == 'base-supplies' &&
                action.entityId == 'rations' &&
                action.entityCategory == base.idString,
          ),
          isTrue,
        );
      }
      if (!classic) expect(find.text('Confirm purchase'), findsNothing);
      checkpoints.add(_capture(source));
      if (oracle != null) {
        _compare(checkpoints.last, oracle[index + 1], 'Key $index: $key');
      }
    }
    expect(purchases, 4);
    expect(tester.takeException(), isNull);
    return checkpoints;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    await source.stop(tester);
    await _settle(tester);
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

  for (final layout in [
    (const Size(1440, 1000), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    testWidgets(
      'Bases original purchases and Back keys match Classic at $layout',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.$1;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(() {
          tester.view.resetDevicePixelRatio();
          tester.view.resetPhysicalSize();
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
          journalReadingScale.value = 1;
          journalPresentation.value = const JournalPreferenceValues();
        });
        final classic = await _run(
          tester,
          fixture,
          classic: true,
          scale: layout.$2,
        );
        await _run(
          tester,
          fixture,
          classic: false,
          scale: layout.$2,
          oracle: classic,
        );
        await _run(
          tester,
          fixture,
          classic: false,
          scale: layout.$2,
          pointerInvestment: true,
          oracle: classic,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
