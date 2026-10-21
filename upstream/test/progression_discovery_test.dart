import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/base_rent_summary.dart';
import 'package:lcs_new_age/modern/campaign_progress.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_agenda.dart';
import 'package:lcs_new_age/modern/journal_bases.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/monthly/advance_month.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
  });

  String snapshot() => jsonEncode(game.gameState.toJson());

  void qualifyForVictory() {
    game.laws.updateAll((_, _) => DeepAlignment.eliteLiberal);
    game.exec.updateAll((_, _) => DeepAlignment.eliteLiberal);
    for (final body in [game.house, game.senate, game.court]) {
      body.fillRange(0, body.length, DeepAlignment.eliteLiberal);
    }
    game.ccsState = game.CCSStrength.defeated;
  }

  Site rentedBase() {
    final site = game.pool.first.base!
      ..type = SiteType.apartment
      ..controller = SiteController.lcs
      ..rent = 650
      ..newRental = false;
    return site;
  }

  test(
    'each unmet campaign objective agrees with the actual victory gate',
    () async {
      for (final id in [
        'laws',
        'court',
        'house',
        'senate',
        'executive',
        'ccs',
      ]) {
        qualifyForVictory();
        switch (id) {
          case 'laws':
            game.laws[Law.abortion] = DeepAlignment.liberal;
          case 'court':
          case 'house':
          case 'senate':
            final body = switch (id) {
              'court' => game.court,
              'house' => game.house,
              _ => game.senate,
            };
            body.fillRange(0, body.length, DeepAlignment.liberal);
            body.fillRange(0, body.length ~/ 2, DeepAlignment.eliteLiberal);
          case 'executive':
            game.exec[game.exec.keys.first] = DeepAlignment.liberal;
          case 'ccs':
            game.ccsState = game.CCSStrength.active;
        }
        final requirements = campaignVictoryRequirements();
        expect(requirements.where((condition) => !condition.met).single.id, id);
        await winCheck();
        expect(engine.console.awaitingInput, isFalse);
      }
      qualifyForVictory();
      expect(
        campaignVictoryRequirements().every((condition) => condition.met),
        isTrue,
      );
    },
  );

  test('an exact Senate half is insufficient and the next seat qualifies', () {
    qualifyForVictory();
    game.senate.fillRange(0, game.senate.length, DeepAlignment.liberal);
    game.senate.fillRange(0, 50, DeepAlignment.eliteLiberal);
    var senate = campaignVictoryRequirements().singleWhere(
      (condition) => condition.id == 'senate',
    );
    expect(senate.met, isFalse);
    expect(senate.detail, '50/100 Elite Liberal · needs 51 for a majority');
    game.senate[50] = DeepAlignment.eliteLiberal;
    senate = campaignVictoryRequirements().singleWhere(
      (condition) => condition.id == 'senate',
    );
    expect(senate.met, isTrue);
    expect(senate.detail, startsWith('51/100'));
  });

  test(
    'rent collection distinguishes the current third, new leases and year rollover',
    () {
      final site = rentedBase();
      game.gameState.date = DateTime(2023, 1, 3);
      expect(baseRentSummary(site).collectionDate, DateTime(2023, 1, 3));
      expect(
        baseRentSummary(site).detail,
        contains('advance from 3 January 2023'),
      );
      game.gameState.date = DateTime(2023, 1, 4);
      expect(baseRentSummary(site).collectionDate, DateTime(2023, 2, 3));
      game.gameState.date = DateTime(2023, 12, 1);
      site.newRental = true;
      final lease = baseRentSummary(site);
      expect(lease.collectionDate, DateTime(2024, 1, 3));
      expect(lease.detail, contains('exempt from collection until next month'));
    },
  );

  test(
    'an alive landlord sleeper must work at this base for the rent waiver',
    () {
      final site = rentedBase();
      final landlord = game.pool.last
        ..typeId = CreatureTypeIds.landlord
        ..sleeperAgent = true
        ..workLocation = site;
      expect(baseRentSummary(site).title, 'Rent waived by undercover landlord');
      expect(site.rent, 650);
      landlord.alive = false;
      expect(baseRentSummary(site).title, startsWith('Rent \$650'));
      landlord.alive = true;
      landlord.workLocation = game.sites.firstWhere((other) => other != site);
      expect(baseRentSummary(site).title, startsWith('Rent \$650'));
      landlord.workLocation = site;
      landlord.sleeperAgent = false;
      expect(baseRentSummary(site).title, startsWith('Rent \$650'));
    },
  );

  test('invalid leases expose eviction rather than sentinel rent amounts', () {
    final site = rentedBase()..rent = 100000000000;
    var rent = baseRentSummary(site);
    expect(rent.forcedEviction, isTrue);
    expect(rent.title, 'Lease no longer valid');
    expect(
      '${rent.title} ${rent.detail} ${rent.warning}',
      isNot(contains('100000000000')),
    );
    expect(rent.warning, contains('stored gear to the local homeless camp'));
    expect(rent.warning, contains('upgrades are lost'));
    site.rent = 0;
    expect(baseRentSummary(site).forcedEviction, isTrue);
    site.type = SiteType.warehouse;
    rent = baseRentSummary(site);
    expect(rent.forcedEviction, isFalse);
    expect(rent.title, 'No monthly rent');
    expect(rent.collectionDate, isNull);
  });

  test(
    'cash warnings are a current shortfall, not a guaranteed future eviction',
    () {
      final site = rentedBase();
      game.ledger.forceSetFunds(600);
      final warning = baseRentSummary(site).warning!;
      expect(warning, contains('Current cash is \$50 short'));
      expect(
        warning,
        contains('Income and other expenses before collection can change that'),
      );
      game.ledger.forceSetFunds(650);
      expect(baseRentSummary(site).warning, isNot(contains('Current cash is')));
    },
  );

  test(
    'food help explains rounding up a partial final day of stored supplies',
    () {
      final base = game.pool.first.base!;
      for (final person in game.pool) {
        person.location = base;
      }
      final eaters = base.numberEating;
      expect(eaters, greaterThan(1));
      base.compound.rations = eaters + 1;
      final help = decisionDetails(
        DecisionTopic.upgrades,
        site: base,
      ).join('\n');
      expect(base.foodDaysLeft, 2);
      expect(help, contains('approximate food days 2'));
      expect(
        help,
        contains('rounded up; a partial final supply prevents starvation'),
      );
      expect(help, isNot(contains('Food days = round(')));
    },
  );

  test('campaign and rent previews preserve the full save and RNG', () {
    final base = rentedBase();
    final before = snapshot();
    reseedRNG(seed: 418277);
    final expected = List.generate(8, (_) => lcsRandom(100000));
    reseedRNG(seed: 418277);
    campaignVictoryRequirements();
    baseRentSummary(base);
    expect(snapshot(), before);
    expect(List.generate(8, (_) => lcsRandom(100000)), expected);
  });

  testWidgets(
    'Agenda exposes the live objective before the law grid at 1024x720 / 150%',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final done = liberalAgenda();
      final before = snapshot();
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: JournalAgendaView(
              console: engine.console,
              onAction: sent.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Campaign objective').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('campaign-requirement:laws')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('campaign-requirement:ccs')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Conservative Crime Squad').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(sent, isEmpty);
      expect(snapshot(), before);
      engine.console.sendInput('Enter');
      await tester.pumpAndSettle();
      expect(await done, isFalse);
    },
  );

  testWidgets(
    'Bases keeps rent timing and shortfall visible without dispatching input',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final base = rentedBase();
      for (final other in game.sites.where((other) => other != base)) {
        other.controller = SiteController.unaligned;
      }
      game.gameState.date = DateTime(2023, 1, 2);
      game.ledger.forceSetFunds(600);
      engine.console.screen = 'headquarters';
      final reader = engine.console.getkey();
      final controller = OrganisationController(console: engine.console);
      final before = snapshot();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: JournalBasesView(
              console: engine.console,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rent = find.byKey(ValueKey('base-rent:${base.id}'));
      await tester.ensureVisible(rent);
      await tester.pumpAndSettle();
      expect(
        find.text('Rent \$650/month · collected on the 3rd').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.textContaining('advance from 3 January 2023'),
        findsOneWidget,
      );
      expect(find.textContaining('Current cash is \$50 short'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(engine.console.lastKey, isNull);
      expect(snapshot(), before);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      engine.console.sendInput('Enter');
      await reader;
    },
  );
}
