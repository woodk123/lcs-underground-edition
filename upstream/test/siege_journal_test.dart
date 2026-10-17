import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/daily/siege.dart' as siege;
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

class _SiegeJournalHarness {
  _SiegeJournalHarness() {
    unawaited(_loop());
  }
  bool stopped = false, finished = false;
  final dispatched = <int>[];
  Future<void> _loop() async {
    try {
      while (!stopped) {
        engine.erase();
        final location = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(location);
        baseModeOptionsDisplay(location);
        final key = await engine.getKey();
        if (stopped) break;
        dispatched.add(key);
        // These tests exercise the real HQ dispatch boundary; consequence
        // regressions and browser journeys run the response handlers themselves.
        if (key == engine.Key.e) await equip(game.activeSquad?.site?.loot);
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    stopped = true;
    for (var i = 0; i < 100 && !finished; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Enter');
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
}

class _StopAtSiegeDecision extends Console {
  final reached = StateError('The displayed siege decision was reached');
  @override
  Future<KeyEvent> getKeyEvent() async {
    if (screen == 'pursuit' || screen == 'tactical') throw reached;
    return super.getKeyEvent();
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Site warehouse;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await serif.load();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    engine.console = Console();
    game.mode = GameMode.base;
    game.activeSquadMemberIndex = -1;
    journalReadingScale.value = 1;
    warehouse = game.sites.firstWhere((s) => s.type == SiteType.warehouse);
    warehouse.controller = SiteController.lcs;
    warehouse.siege.activeSiegeType = SiegeType.police;
    warehouse.compound
      ..rations = 30
      ..fortified = true
      ..boobyTraps = true
      ..cameras = true;
    for (final person in game.pool) {
      person.location = warehouse;
      person.base = warehouse;
    }
    game.activeSafehouse = null;
    game.activeSite = warehouse;
    reseedRNG(seed: 20261017);
  });

  void publish() {
    engine.erase();
    baseModeSquadSafehouseDisplay(
      game.activeSquad?.site ?? game.activeSafehouse,
    );
    baseModeOptionsDisplay(game.activeSquad?.site ?? game.activeSafehouse);
  }

  test(
    'source HQ snapshot retains surrender identity and read-only siege details',
    () {
      publish();
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 438);
      final expected = lcsRandom(100000);
      reseedRNG(seed: 438);
      final frame = headquartersFrame(engine.console)!;
      expect(
        frame.action('g'),
        same(engine.console.actions.singleWhere((a) => a.key == 'g')),
      );
      expect(frame.siege!.title, 'Safehouse under siege');
      expect(frame.siege!.statusLines.join(' '), contains('30 rations'));
      expect(frame.siege!.statusLines.join(' '), contains('Fortifications'));
      expect(frame.siege!.note, contains('Wanted Liberals here face arrest'));
      expect(
        () => frame.siege!.statusLines.add('Injected'),
        throwsUnsupportedError,
      );
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(lcsRandom(100000), expected);
    },
  );

  test('unsquadded local defenders can use the source fight response', () {
    for (final person in game.pool.toList()) {
      person.squad = null;
    }
    game.activeSquad = null;
    game.activeSafehouse = warehouse;
    publish();
    expect(headquartersFrame(engine.console)!.action('f')!.enabled, isTrue);
    expect(headquartersFrame(engine.console)!.siege, isNotNull);
  });

  test(
    'an attack elsewhere cannot enable a response with no local defenders',
    () {
      final remote = game.sites.firstWhere(
        (s) => s.type == SiteType.homelessEncampment,
      );
      for (final person in game.pool) {
        person.location = remote;
      }
      remote.siege
        ..activeSiegeType = SiegeType.police
        ..underAttack = true;
      game.activeSquad = null;
      game.activeSafehouse = warehouse;
      publish();
      expect(headquartersFrame(engine.console)!.action('f')!.enabled, isFalse);
      expect(
        headquartersFrame(engine.console)!.action('w')!.label,
        contains('Select Siege Location'),
      );
    },
  );

  for (final response in ['surrounded', 'attack', 'camp']) {
    test(
      'source $response response enters its displayed HQ site with a stale other safehouse',
      () async {
        final stop = _StopAtSiegeDecision();
        engine.console = stop;
        final camp = game.sites.firstWhere(
          (s) => s.type == SiteType.homelessEncampment,
        );
        final target = response == 'camp' ? camp : warehouse;
        final other = response == 'camp' ? warehouse : camp;
        for (final person in game.squad) {
          person.location = target;
          person.base = target;
        }
        target.siege
          ..activeSiegeType = SiegeType.police
          ..underAttack = response == 'attack';
        game.activeSafehouse = other;
        // Author the original HQ action for the explicitly displayed target.
        // Supplying its captured target avoids consulting stale selection again.
        baseModeOptionsDisplay(target);
        final frame = headquartersFrame(stop)!;
        final action = frame.action('f')!;
        expect(frame.locationId, target.idString);
        expect(frame.siege!.location, target.getName(includeCity: true));
        expect(action.enabled, isTrue);
        void respond() {
          if (!stop.awaitingInput || stop.lastKey != null) return;
          if (stop.screen == 'headquarters') {
            stop.sendInput(action.key);
          } else if (stop.eventMessage != null) {
            stop.sendInput('Enter');
          }
        }

        stop.revision.addListener(respond);
        Future<void> run() async {
          if (await engine.getKey() != engine.Key.f) {
            throw StateError('Wrong HQ command');
          }
          if (response == 'camp') {
            await siege.fightHomelessCampSiege(target);
          } else if (response == 'attack') {
            await siege.escapeOrEngage(target);
          } else {
            await siege.sallyForth(target);
          }
        }

        try {
          await expectLater(run(), throwsA(same(stop.reached)));
        } finally {
          stop.revision.removeListener(respond);
        }
        expect(game.activeSite, same(target));
        expect(game.activeSquad!.site, same(target));
        expect(game.squad.every((p) => p.location == target), isTrue);
      },
    );
  }

  Future<_SiegeJournalHarness> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    journalReadingScale.value = scale;
    final harness = _SiegeJournalHarness();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    expect(find.byType(OrganisationJournal), findsOneWidget);
    return harness;
  }

  testWidgets(
    'siege response keeps left squad leaders and dispatches exact HQ actions',
    (tester) async {
      final harness = await mount(tester);
      expect(_key('journal-squad:${game.activeSquad!.id}'), findsOneWidget);
      expect(find.text('Safehouse under siege'), findsOneWidget);
      final before = jsonEncode(game.gameState.toJson());
      for (final key in ['f', 'g', 'w']) {
        final action = _key('journal-siege-action:$key');
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(harness.dispatched.last, key.codeUnitAt(0));
      }
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'siege callbacks reject earlier revisions and nested equipment readers',
    (tester) async {
      final harness = await mount(tester);
      final old = tester
          .widget<OutlinedButton>(_key('journal-siege-action:g'))
          .onPressed!;
      engine.console.flush();
      old();
      await tester.pumpAndSettle();
      expect(harness.dispatched, isEmpty);
      final current = tester
          .widget<OutlinedButton>(_key('journal-siege-action:g'))
          .onPressed!;
      engine.console.sendInput('e');
      await tester.pumpAndSettle();
      expect(engine.console.screen, isNot('headquarters'));
      current();
      await tester.pumpAndSettle();
      expect(harness.dispatched, [engine.Key.e]);
      expect(engine.console.lastKey, isNull);
      engine.console.sendInput('Enter');
      await tester.pumpAndSettle();
      expect(_key('journal-siege-action:g').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'siege dossier blocks surrender and battle keys without consuming rolls',
    (tester) async {
      final harness = await mount(tester);
      final retained = tester
          .widget<OutlinedButton>(_key('journal-siege-action:g'))
          .onPressed!;
      final before = jsonEncode(game.gameState.toJson());
      final revision = engine.console.revision.value;
      reseedRNG(seed: 2386);
      final expected = lcsRandom(100000);
      reseedRNG(seed: 2386);
      await tester.tap(_key('hq-dossier:${game.squad.first.id}'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close crew inspection'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG, character: 'g');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF, character: 'f');
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW, character: 'w');
      retained();
      await tester.pumpAndSettle();
      expect(harness.dispatched, isEmpty);
      expect(engine.console.revision.value, revision);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(lcsRandom(100000), expected);
      await tester.tap(find.byTooltip('Close crew inspection'));
      await tester.pumpAndSettle();
      expect(_key('journal-siege-action:g').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'attack response is usable at 800x600 with 150 percent reading size',
    (tester) async {
      warehouse.siege.underAttack = true;
      await mount(tester, size: const Size(800, 600), scale: 1.5);
      expect(find.text('Safehouse under attack'), findsOneWidget);
      for (final key in ['f', 'g']) {
        expect(_key('journal-siege-action:$key').hitTestable(), findsOneWidget);
      }
      expect(_key('journal-siege-action:w'), findsNothing);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const PageStorageKey('journal-siege-details')),
      );
      await tester.tap(
        find.byKey(const PageStorageKey('journal-siege-details')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('30 rations'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1200, 800), const Size(800, 600)]) {
    testWidgets(
      'actual police surrender has one current journal Continue at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        journalReadingScale.value = size.width == 800 ? 1.5 : 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final crew = game.squad.toList();
        for (final person in crew) {
          person.wantedForCrimes.updateAll((_, _) => 0);
          person.wantedForCrimes[Crime.disturbingThePeace] = 1;
        }
        final car = Vehicle(VehicleTypeIds.van)..location = warehouse;
        game.vehiclePool.add(car);
        final funds = game.ledger.funds;
        var finished = false;
        publish();
        // Dispatch the exact HQ action into the original surrender handler.
        Future<void> run() async {
          if (await engine.getKey() != engine.Key.g) {
            throw StateError('The siege surrender action was not dispatched.');
          }
          await giveUp(warehouse);
          finished = true;
        }

        final surrender = run();
        await tester.pumpWidget(const MainApp());
        await tester.pumpAndSettle();
        final oldGiveUp = tester
            .widget<OutlinedButton>(_key('journal-siege-action:g'))
            .onPressed!;
        await tester.tap(_key('journal-siege-action:g'));
        await tester.pumpAndSettle();
        expect(engine.console.awaitingInput, isTrue);
        expect(engine.console.eventTitle, 'Safehouse siege');
        expect(
          engine.console.eventMessage,
          contains(
            'The police confiscate everything, including Squad weapons.',
          ),
        );
        expect(
          engine.console.eventMessage,
          contains('${crew.length} Liberals are arrested.'),
        );
        expect(find.text('Continue').hitTestable(), findsOneWidget);
        expect(crew.any((p) => p.imprisoned), isFalse);
        expect(finished, isFalse);
        oldGiveUp();
        await tester.pumpAndSettle();
        expect(finished, isFalse);
        expect(engine.console.lastKey, isNull);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        await surrender;
        expect(finished, isTrue);
        expect(engine.console.awaitingInput, isFalse);
        expect(crew.every((p) => p.imprisoned && p.squad == null), isTrue);
        expect(
          crew.every((p) => p.equippedWeapon == null && p.spareAmmo == null),
          isTrue,
        );
        expect(game.vehiclePool, isNot(contains(car)));
        expect(game.ledger.funds, funds);
        expect(warehouse.siege.underSiege, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
