import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/invest_in_location.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/engine/base_management_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/base_management_controller.dart';
import 'package:lcs_new_age/modern/journal_bases.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

/// The normal HQ dispatch boundary, with the real investment, overview,
/// equipment transfer and squadless base-assignment source readers.
class _BaseHarness {
  _BaseHarness() {
    done = _loop();
  }
  late Future<void> done;
  bool stopped = false;
  bool finished = false;

  Future<void> _loop() async {
    try {
      while (!stopped) {
        engine.erase();
        final site = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(site);
        baseModeOptionsDisplay(site);
        final key = await engine.getKey();
        if (stopped) break;
        switch (key) {
          case engine.Key.r:
            await reviewAssetsAndFormSquads();
          case engine.Key.z:
            final bases = organisationBases();
            if (bases.isNotEmpty) {
              final index = bases.indexOf(game.activeSafehouse ?? bases.first);
              game.activeSquad = null;
              game.activeSafehouse = bases[(index + 1) % bases.length];
            }
          case engine.Key.i:
            final base = game.activeSafehouse;
            if (base != null && base.upgradable && !base.siege.underSiege) {
              await investInLocation(base);
            }
        }
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop() async {
    stopped = true;
    for (var step = 0; step < 40 && !finished; step++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await done.timeout(const Duration(seconds: 2));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String save;
  OrganisationController? organisation;
  BaseManagementController? bases;
  _BaseHarness? harness;
  setUpAll(() async {
    await ensureGameDataLoaded();
    save = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(save).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
  });
  tearDown(() async {
    bases?.dispose();
    bases = null;
    organisation?.dispose();
    organisation = null;
    await harness?.stop();
    harness = null;
  });

  BaseManagementController start() {
    harness = _BaseHarness();
    organisation = OrganisationController(console: engine.console);
    return bases = BaseManagementController(organisation: organisation!);
  }

  Site newBase(String name) {
    final base = Site.fromJson(
      jsonDecode(jsonEncode(organisationBases().first.toJson())),
    );
    base.id = game.gameState.nextSiteId++;
    base.name = name;
    base.shortName = name;
    base.frontName = null;
    base.frontShortName = null;
    base.type = SiteType.warehouse;
    base.loot = [];
    base.siege = Siege();
    base.district.sites.add(base);
    return base;
  }

  ConsoleAction entity(String type, String id) =>
      engine.console.actions.singleWhere(
        (action) => action.entityType == type && action.entityId == id,
      );

  test('directory inspection preserves campaign, item stacks and RNG', () {
    final base = newBase('Read-only warehouse');
    final item = Item('WEAPON_22_REVOLVER');
    base.loot.addAll([item, item.clone()]);
    final before = jsonEncode(game.gameState.toJson());
    reseedRNG(seed: 61426);
    final expected = List.generate(8, (_) => lcsRandom(100000));
    reseedRNG(seed: 61426);
    for (var repeat = 0; repeat < 3; repeat++) {
      expect(organisationBases(), contains(base));
      baseResidents(base);
      expect(baseInvestmentUnavailableReason(base), isNull);
      expect(storesUnavailableReason(), isNull);
      baseAssignmentUnavailableReason();
    }
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(base.loot.length, 2);
    expect(List.generate(8, (_) => lcsRandom(100000)), expected);
  });

  test(
    'selected base purchases use original investment reader and ledger',
    () async {
      final base = newBase('Upgrade warehouse');
      game.ledger.forceSetFunds(20000);
      final routes = start();
      expect(await routes.openInvestment(base.id), isTrue);
      expect(game.activeSafehouse, same(base));
      expect(engine.console.screen, 'base-investment');
      expect(engine.console.navigation?.backKey, 'Enter');
      final rations = entity('base-supplies', 'rations');
      final originalRations = base.compound.rations;
      final funds = game.ledger.funds;
      final expense = game.ledger.expense[Expense.compoundUpgrades]!;
      final originalRevision = engine.console.revision.value;
      expect(
        await routes.sendAction(rations, revision: originalRevision),
        isTrue,
      );
      expect(base.compound.rations, originalRations + 20);
      expect(game.ledger.funds, funds - 150);
      expect(game.ledger.expense[Expense.compoundUpgrades], expense + 150);
      expect(
        await routes.sendAction(rations, revision: originalRevision),
        isFalse,
      );
      expect(base.compound.rations, originalRations + 20);
      final upgrade = entity('compound-upgrade', 'cameras');
      expect(
        await routes.sendAction(
          upgrade,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      expect(base.compound.cameras, isTrue);
      expect(
        engine.console.actions.any((action) => action.entityId == 'cameras'),
        isFalse,
      );
      expect(await routes.closeSource(), isTrue);
      expect(engine.console.screen, 'headquarters');
    },
  );

  test(
    'equipment route reaches exact page boundary then moves actual stack',
    () async {
      final source = newBase('Source warehouse');
      final destination = newBase('Destination warehouse');
      final stack = Item('WEAPON_22_REVOLVER');
      source.loot.add(stack);
      while (game.squads.length < 12) {
        game.squads.add(Squad()..name = 'Extra ${game.squads.length}');
      }
      final routes = start();
      expect(await routes.openStores(), isTrue, reason: routes.message);
      expect(engine.console.screen, 'equipment-transfer');
      final chooseDestination = engine.console.actions.singleWhere(
        (action) =>
            action.entityId == destination.idString &&
            action.entityType!.startsWith('equipment-transfer-destination'),
      );
      final funds = game.ledger.funds;
      expect(
        await routes.sendAction(
          chooseDestination,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      final item = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'equipment-transfer-item' &&
            action.entityCategory == source.idString,
      );
      expect(
        await routes.sendAction(item, revision: engine.console.revision.value),
        isTrue,
      );
      expect(source.loot, isEmpty);
      expect(destination.loot, contains(same(stack)));
      expect(stack.stackSize, 1);
      expect(game.ledger.funds, funds);
    },
  );

  test('equipment destination pages wrap back after the last page', () async {
    final source = newBase('Paged source');
    while (organisationBases().where((site) => !site.siege.underSiege).length <
        10) {
      newBase('Paged destination ${organisationBases().length}');
    }
    final destinations = organisationBases()
        .where((site) => !site.siege.underSiege)
        .toList();
    final firstDestination = destinations.first;
    final finalDestination = destinations.last;
    final stack = Item('WEAPON_22_REVOLVER');
    source.loot.add(stack);
    final routes = start();
    expect(await routes.openStores(), isTrue, reason: routes.message);
    final beforePaging = jsonEncode(game.gameState.toJson());
    Future<void> moreBases() async {
      final action = engine.console.actions.singleWhere(
        (action) => action.key == '0',
      );
      expect(
        await routes.sendAction(
          action,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
    }

    expect(
      engine.console.actions.any(
        (action) =>
            action.entityId == firstDestination.idString &&
            action.entityType!.startsWith('equipment-transfer-destination'),
      ),
      isTrue,
    );
    await moreBases();
    final lastChoice = engine.console.actions.singleWhere(
      (action) =>
          action.entityId == finalDestination.idString &&
          action.entityType!.startsWith('equipment-transfer-destination'),
    );
    expect(
      await routes.sendAction(
        lastChoice,
        revision: engine.console.revision.value,
      ),
      isTrue,
    );
    await moreBases();
    final firstChoice = engine.console.actions.singleWhere(
      (action) =>
          action.entityId == firstDestination.idString &&
          action.entityType!.startsWith('equipment-transfer-destination'),
    );
    expect(jsonEncode(game.gameState.toJson()), beforePaging);
    expect(
      await routes.sendAction(
        firstChoice,
        revision: engine.console.revision.value,
      ),
      isTrue,
    );
    final move = engine.console.actions.singleWhere(
      (action) =>
          action.entityType == 'equipment-transfer-item' &&
          action.entityCategory == source.idString,
    );
    expect(
      await routes.sendAction(move, revision: engine.console.revision.value),
      isTrue,
    );
    expect(source.loot, isEmpty);
    expect(firstDestination.loot, contains(same(stack)));
  });

  test(
    'home base assignment preserves actual location and source restrictions',
    () async {
      final destination = newBase('New home');
      final person = game.pool.first..squad = null;
      final actualLocation = person.locationId;
      final routes = start();
      expect(await routes.openSquadlessAssignment(), isTrue);
      final chooseDestination = engine.console.actions.singleWhere(
        (action) =>
            action.entityId == destination.idString &&
            action.entityType!.startsWith('base-assignment-destination'),
      );
      expect(
        await routes.sendAction(
          chooseDestination,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      final move = entity('base-assignment-person', person.id.toString());
      expect(move.entityCategory, destination.idString);
      expect(
        await routes.sendAction(move, revision: engine.console.revision.value),
        isTrue,
      );
      expect(person.base, same(destination));
      expect(person.locationId, actualLocation);
    },
  );

  test(
    'siege restrictions and insufficient funds stay source authored',
    () async {
      final base = newBase('Poor warehouse');
      base.siege.activeSiegeType = SiegeType.police;
      final routes = start();
      expect(await routes.openInvestment(base.id), isFalse);
      expect(routes.message, contains('siege'));
      base.siege.activeSiegeType = SiegeType.none;
      game.ledger.forceSetFunds(0);
      expect(await routes.openInvestment(base.id), isTrue);
      final action = entity('base-supplies', 'rations');
      expect(action.enabled, isFalse);
      final before = base.compound.rations;
      expect(
        await routes.sendAction(
          action,
          revision: engine.console.revision.value,
        ),
        isFalse,
      );
      expect(base.compound.rations, before);
      expect(game.ledger.funds, 0);
    },
  );

  testWidgets('purchase keyboard stages, cancels and confirms through source', (
    tester,
  ) async {
    final base = newBase('Keyboard warehouse');
    game.ledger.forceSetFunds(5000);
    await tester.runAsync(() async {
      final routes = start();
      expect(await routes.openInvestment(base.id), isTrue);
    });
    final key = GlobalKey<JournalBasesViewState>();
    final drafts = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: Scaffold(
          body: JournalBasesView(
            key: key,
            console: engine.console,
            controller: organisation!,
            onDraftChanged: drafts.add,
          ),
        ),
      ),
    );
    final rations = base.compound.rations;
    final funds = game.ledger.funds;
    expect(key.currentState!.handleGameShortcut('r'), isTrue);
    await tester.pump();
    expect(find.text('Confirm purchase'), findsOneWidget);
    expect(key.currentState!.hasPreparedPurchase, isTrue);
    expect(drafts, [true]);
    expect(base.compound.rations, rations);
    expect(game.ledger.funds, funds);
    expect(key.currentState!.handleGameShortcut('Escape'), isTrue);
    await tester.pump();
    expect(find.text('Confirm purchase'), findsNothing);
    expect(key.currentState!.hasPreparedPurchase, isFalse);
    expect(drafts, [true, false]);
    expect(base.compound.rations, rations);
    key.currentState!.handleGameShortcut('r');
    await tester.runAsync(() async {
      key.currentState!.handleGameShortcut('Enter');
      for (var step = 0; step < 20 && organisation!.busy; step++) {
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
    });
    await tester.pump();
    expect(base.compound.rations, rations + 20);
    expect(game.ledger.funds, funds - 150);
    expect(key.currentState!.hasPreparedPurchase, isFalse);
    expect(drafts, [true, false, true, false]);
    key.currentState!.handleGameShortcut('r');
    expect(key.currentState!.hasPreparedPurchase, isTrue);
    engine.console.revision.value++;
    await tester.pump();
    expect(key.currentState!.hasPreparedPurchase, isFalse);
    expect(drafts, [true, false, true, false, true, false]);
    expect(find.text('Confirm purchase'), findsNothing);
    expect(base.compound.rations, rations + 20);
    expect(game.ledger.funds, funds - 150);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      await harness!.stop();
    });
    harness = null;
  });

  testWidgets(
    'retained purchase confirmations cannot buy canceled, replaced or stale drafts',
    (tester) async {
      final base = newBase('Retained confirmation warehouse');
      game.ledger.forceSetFunds(5000);
      await tester.runAsync(() async {
        final routes = start();
        expect(await routes.openInvestment(base.id), isTrue);
      });
      final key = GlobalKey<JournalBasesViewState>();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: Scaffold(
            body: JournalBasesView(
              key: key,
              console: engine.console,
              controller: organisation!,
            ),
          ),
        ),
      );
      final rations = base.compound.rations;
      final diesel = base.compound.diesel;
      final funds = game.ledger.funds;
      VoidCallback currentConfirmation() => tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Confirm purchase'),
          )
          .onPressed!;

      key.currentState!.handleGameShortcut('r');
      await tester.pump();
      final canceledConfirmation = currentConfirmation();
      key.currentState!.handleGameShortcut('Escape');
      canceledConfirmation();
      await tester.pump();
      expect(base.compound.rations, rations);
      expect(game.ledger.funds, funds);
      expect(key.currentState!.hasPreparedPurchase, isFalse);

      // Re-preparing the same source action is a new draft even though the
      // original reader, action identity and revision have not changed.
      key.currentState!.handleGameShortcut('r');
      canceledConfirmation();
      await tester.pump();
      expect(key.currentState!.hasPreparedPurchase, isTrue);
      expect(base.compound.rations, rations);
      expect(game.ledger.funds, funds);
      final replacedConfirmation = currentConfirmation();
      key.currentState!.handleGameShortcut('Escape');
      final upgrade = engine.console.actions.firstWhere(
        (action) => action.entityType == 'compound-upgrade' && action.enabled,
      );
      key.currentState!.handleGameShortcut(upgrade.key);
      replacedConfirmation();
      await tester.pump();
      expect(key.currentState!.hasPreparedPurchase, isTrue);
      expect(base.compound.rations, rations);
      expect(base.compound.diesel, diesel);
      expect(game.ledger.funds, funds);

      final staleConfirmation = currentConfirmation();
      engine.console.revision.value++;
      staleConfirmation();
      await tester.pump();
      expect(key.currentState!.hasPreparedPurchase, isFalse);
      expect(base.compound.rations, rations);
      expect(base.compound.diesel, diesel);
      expect(game.ledger.funds, funds);
      expect(engine.console.lastKey, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await harness!.stop();
      });
      harness = null;
    },
  );

  testWidgets(
    'base directory fits a narrow page and shows stores without mutation',
    (tester) async {
      final base = newBase('Visible warehouse');
      base.loot.add(Item('WEAPON_22_REVOLVER'));
      baseModeOptionsDisplay(game.activeSquad?.site);
      organisation = OrganisationController(console: engine.console);
      final key = GlobalKey<JournalBasesViewState>();
      final before = jsonEncode(game.gameState.toJson());
      tester.view.physicalSize = const Size(640, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: JournalBasesView(
            key: key,
            console: engine.console,
            controller: organisation!,
          ),
        ),
      );
      expect(find.text('Bases & Stores'), findsOneWidget);
      expect(find.text('Assign home bases'), findsOneWidget);
      for (final hiddenHeadquartersKey in ['w', 'x', 'i', 'z', '?']) {
        expect(
          key.currentState!.handleGameShortcut(hiddenHeadquartersKey),
          isTrue,
        );
        expect(engine.console.lastKey, isNull);
      }
      engine.console.eventMessage = 'Required acknowledgement';
      expect(key.currentState!.handleGameShortcut('Enter'), isFalse);
      engine.console.eventMessage = null;
      expect(tester.takeException(), isNull);
      expect(jsonEncode(game.gameState.toJson()), before);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
