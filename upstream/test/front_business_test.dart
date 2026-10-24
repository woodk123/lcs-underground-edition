import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/front_business_management.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/front_business.dart';
import 'package:lcs_new_age/daily/activities/solo_activities.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/front_business.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  late String fixture;
  late Site site;
  late List<Creature> crew;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    final save = SaveFile.fromJson(jsonDecode(fixture) as Map<String, dynamic>);
    game.gameState = game.GameState.fromJson(save.saveData);
    site = game.sites.firstWhere((s) => s.type == SiteType.warehouse);
    site.controller = SiteController.lcs;
    site.siege = Siege();
    site.closed = 0;
    site.businessFront = true;
    site.frontBusiness = FrontBusiness();
    game.pool.clear();
    game.squads.clear();
    crew = List.generate(
      3,
      (index) =>
          Creature.fromId(
              CreatureTypeIds.officeWorker,
              align: Alignment.liberal,
            )
            ..name = 'Printer $index'
            ..base = site
            ..location = site
            // Training assertions require a declared cap above the prepared
            // Writing level; randomly generated office workers can cap at 3.
            ..rawAttributes.updateAll((attribute, value) => 20)
            ..rawSkillXP.updateAll((skill, value) => 0)
            ..rawSkill[Skill.business] = 0
            ..rawSkill[Skill.writing] = 0,
    );
    game.pool.addAll(crew);
    game.gameState.ledger = Ledger()..forceSetFunds(1000);
  });

  test('older site saves default to no working shop and keep their cover', () {
    final json = jsonDecode(jsonEncode(site.toJson())) as Map<String, dynamic>;
    json.remove('frontBusiness');
    final loaded = Site.fromJson(json);
    expect(loaded.frontBusiness, isNull);
    expect(loaded.businessFront, isTrue);
    expect(loaded.heatProtection, site.heatProtection);
  });

  test('shop mode, staff, date and report survive campaign round trip', () {
    assignPrintShopWorker(site, crew.first);
    setFrontBusinessMode(site, FrontBusinessMode.movement);
    processFrontBusinesses();
    final expected = site.frontBusiness!.toJson();
    final saved =
        jsonDecode(jsonEncode(game.gameState.toJson())) as Map<String, dynamic>;
    game.gameState = game.GameState.fromJson(saved);
    final loaded = game.sites.firstWhere((s) => s.id == site.id);
    expect(loaded.frontBusiness!.toJson(), expected);
    expect(game.pool.first.activity.type, ActivityType.workPrintShop);
    expect(game.pool.first.activity.idString, loaded.idString);
    final funds = game.ledger.funds;
    processFrontBusinesses();
    expect(
      game.ledger.funds,
      funds,
      reason: 'Saved day guard prevents duplicate costs and rewards.',
    );
  });

  test('commercial work has bounded sales and explicit costs; never passive income', () {
    processFrontBusinesses();
    expect(game.ledger.funds, 1000);
    game.gameState.date = game.date.add(const Duration(days: 1));
    expect(assignPrintShopWorker(site, crew[0]), isTrue);
    expect(assignPrintShopWorker(site, crew[1]), isTrue);
    expect(assignPrintShopWorker(site, crew[2]), isFalse);
    crew[1].rawSkill[Skill.business] = 50;
    crew[1].rawSkill[Skill.writing] = 50;
    expect(printShopInfluenceFor(crew[1]), 8);
    game.ledger.forceSetFunds(0);
    processFrontBusinesses();
    expect(site.frontBusiness!.lastGross, 178); // 45 + capped 133
    expect(site.frontBusiness!.lastCost, 40);
    expect(game.ledger.funds, 138);
    expect(game.ledger.dailyIncome[Income.printShop], 178);
    expect(game.ledger.dailyExpense[Expense.printShop], 40);
    processFrontBusinesses();
    expect(game.ledger.funds, 138);
    expect(crew[0].skillXP(Skill.business), greaterThan(0));
  });

  test(
    'daily dispatch replaces fundraising rather than earning both',
    () async {
      crew.first.activity = Activity(ActivityType.donations);
      expect(assignPrintShopWorker(site, crew.first), isTrue);
      await soloActivities(false);
      expect(game.ledger.income[Income.donations], 0);
      expect(game.ledger.income[Income.printShop], 45);
      expect(crew.first.income, 25);
    },
  );

  test('a new ordinary daily order immediately frees the shop slot', () {
    assignPrintShopWorker(site, crew[0]);
    assignPrintShopWorker(site, crew[1]);
    crew[0].activity = Activity(ActivityType.donations);
    expect(assignPrintShopWorker(site, crew[2]), isTrue);
    processFrontBusinesses();
    expect(site.frontBusiness!.staffIds, [crew[1].id, crew[2].id]);
    expect(site.frontBusiness!.lastWorkers, 2);
    expect(crew[0].activity.type, ActivityType.donations);
  });

  test('squad orders prevent a shop shift even before departure', () {
    final team = Squad();
    game.squads.add(team);
    crew.first.squad = team;
    expect(assignPrintShopWorker(site, crew.first), isTrue);
    team.activity = Activity(ActivityType.visit, idString: site.idString);
    expect(assignPrintShopWorker(site, crew[0]), isFalse);
    processFrontBusinesses();
    expect(site.frontBusiness!.lastWorkers, 0);
    expect(game.ledger.funds, 1000);
  });

  test(
    'travel, absence, hospital, custody, sleepers and dead crew cannot earn',
    () {
      for (final unavailable in [
        'visit',
        'absent',
        'hospital',
        'prison',
        'sleeper',
        'dead',
        'hiding',
      ]) {
        final worker = crew.first;
        worker.alive = true;
        worker.sleeperAgent = false;
        worker.hidingDaysLeft = 0;
        worker.location = site;
        worker.activity = Activity.none();
        expect(assignPrintShopWorker(site, worker), isTrue);
        switch (unavailable) {
          case 'visit':
            worker.activity = Activity(ActivityType.visit);
          case 'absent':
            worker.location = game.sites.firstWhere((s) => s != site);
          case 'hospital':
            worker.location = game.sites.firstWhere(
              (s) => s.type == SiteType.universityHospital,
            );
          case 'prison':
            worker.location = game.sites.firstWhere(
              (s) => s.type == SiteType.prison,
            );
          case 'sleeper':
            worker.sleeperAgent = true;
          case 'dead':
            worker.alive = false;
          case 'hiding':
            worker.hidingDaysLeft = -1;
        }
        final funds = game.ledger.funds;
        processFrontBusinesses();
        expect(game.ledger.funds, funds, reason: unavailable);
        expect(site.frontBusiness!.lastWorkers, 0, reason: unavailable);
        game.gameState.date = game.date.add(const Duration(days: 1));
      }
    },
  );

  test(
    'movement printing funds only affordable staff and produces real influence',
    () {
      for (final worker in crew.take(2)) {
        assignPrintShopWorker(site, worker);
        worker.rawSkill[Skill.writing] = 3;
      }
      setFrontBusinessMode(site, FrontBusinessMode.movement);
      game.ledger.forceSetFunds(25);
      final before = game.politics.backgroundInfluence[View.freeSpeech]!;
      final xp = crew.first.skillXP(Skill.writing);
      processFrontBusinesses();
      expect(game.ledger.funds, 5);
      expect(site.frontBusiness!.lastWorkers, 1);
      expect(game.politics.backgroundInfluence[View.freeSpeech], before + 3);
      expect(crew.first.skillXP(Skill.writing), xp + 5);
      expect(game.ledger.dailyIncome[Income.printShop], 0);
      game.gameState.date = game.date.add(const Duration(days: 1));
      processFrontBusinesses();
      expect(site.frontBusiness!.lastWorkers, 0);
      expect(game.ledger.funds, 5);
      expect(game.politics.backgroundInfluence[View.freeSpeech], before + 3);
    },
  );

  test(
    'closing releases staff and siege or dispersal stops trading without costs',
    () {
      assignPrintShopWorker(site, crew.first);
      setFrontBusinessMode(site, FrontBusinessMode.closed);
      expect(crew.first.activity.type, ActivityType.none);
      expect(site.frontBusiness!.staffIds, isEmpty);
      processFrontBusinesses();
      expect(game.ledger.funds, 1000);
      setFrontBusinessMode(site, FrontBusinessMode.commercial);
      assignPrintShopWorker(site, crew.first);
      game.gameState.date = game.date.add(const Duration(days: 1));
      site.siege.activeSiegeType = SiegeType.police;
      processFrontBusinesses();
      expect(game.ledger.funds, 1000);
      site.siege.activeSiegeType = SiegeType.none;
      game.gameState.date = game.date.add(const Duration(days: 1));
      processFrontBusinesses(disbanding: true);
      expect(game.ledger.funds, 1000);
    },
  );

  test(
    'losing premises or dismantling cover removes shop and its standing orders',
    () {
      assignPrintShopWorker(site, crew.first);
      site.controller = SiteController.unaligned;
      expect(site.frontBusiness, isNull);
      expect(crew.first.activity.type, ActivityType.none);
      site.controller = SiteController.lcs;
      site.frontBusiness = FrontBusiness();
      assignPrintShopWorker(site, crew.first);
      site.businessFront = false;
      expect(site.frontBusiness, isNull);
      expect(crew.first.activity.type, ActivityType.none);
    },
  );

  test('removing a base from the campaign clears stranded shop orders', () {
    assignPrintShopWorker(site, crew.first);
    site.district.sites.remove(site);
    processFrontBusinesses();
    expect(crew.first.activity.type, ActivityType.none);
    expect(game.ledger.funds, 1000);
  });

  test(
    'setup preserves existing cover and checks funds before any purchase',
    () {
      site.frontBusiness = null;
      game.ledger.forceSetFunds(1499);
      expect(setUpPrintShop(site), isFalse);
      expect(site.frontBusiness, isNull);
      expect(game.ledger.funds, 1499);
      game.ledger.forceSetFunds(1500);
      final protection = site.heatProtection;
      expect(setUpPrintShop(site), isTrue);
      expect(game.ledger.funds, 0);
      expect(site.heatProtection, protection);
      expect(setUpPrintShop(site), isFalse);
    },
  );

  test(
    'optional model tolerates missing fields and caps duplicate staffing',
    () {
      expect(FrontBusiness.fromJson({}).mode, FrontBusinessMode.commercial);
      final shop = FrontBusiness.fromJson({
        'mode': 'futureMode',
        'staffIds': [1, 1, 2, 3],
      });
      expect(shop.mode, FrontBusinessMode.commercial);
      expect(shop.staffIds, [1, 2]);
    },
  );

  test(
    'seven staffed days produce one rush offer, paid only on the next shift',
    () {
      assignPrintShopWorker(site, crew.first);
      setFrontBusinessMode(site, FrontBusinessMode.movement);
      for (var day = 0; day < FrontBusiness.rushOrderInterval; day++) {
        processFrontBusinesses();
        expect(site.frontBusiness!.rushOrderPending, day == 6);
        game.gameState.date = game.date.add(const Duration(days: 1));
      }
      final funds = game.ledger.funds;
      final influence = game.politics.backgroundInfluence[View.freeSpeech];
      expect(acceptPrintShopRushOrder(site), isTrue);
      expect(acceptPrintShopRushOrder(site), isFalse);
      expect(
        game.ledger.funds,
        funds,
        reason: 'Accepting an offer is not a payout.',
      );
      processFrontBusinesses();
      expect(game.ledger.funds, funds + 125); // 45 sales + 100 bonus - 20 costs
      expect(site.frontBusiness!.lastGross, 145);
      expect(site.frontBusiness!.lastInfluence, 0);
      expect(game.politics.backgroundInfluence[View.freeSpeech], influence);
      expect(site.frontBusiness!.mode, FrontBusinessMode.movement);
      expect(site.frontBusiness!.rushOrderPending, isFalse);
      processFrontBusinesses();
      expect(game.ledger.funds, funds + 125);
    },
  );

  test('rush offers survive saves and suspension without unstaffed rewards or stacking', () {
    final shop = site.frontBusiness!;
    shop.rushOrderPending = true;
    expect(acceptPrintShopRushOrder(site), isTrue);
    site.frontBusiness = FrontBusiness.fromJson(
      jsonDecode(jsonEncode(shop.toJson())) as Map<String, dynamic>,
    );
    expect(site.frontBusiness!.rushOrderAccepted, isTrue);
    processFrontBusinesses();
    expect(site.frontBusiness!.rushOrderPending, isTrue);
    expect(game.ledger.funds, 1000);
    setFrontBusinessMode(site, FrontBusinessMode.closed);
    game.gameState.date = game.date.add(const Duration(days: 1));
    processFrontBusinesses();
    expect(site.frontBusiness!.rushOrderAccepted, isTrue);
    expect(game.ledger.funds, 1000);
    setFrontBusinessMode(site, FrontBusinessMode.commercial);
    assignPrintShopWorker(site, crew.first);
    site.siege.activeSiegeType = SiegeType.police;
    game.gameState.date = game.date.add(const Duration(days: 1));
    processFrontBusinesses();
    expect(site.frontBusiness!.rushOrderAccepted, isTrue);
    expect(game.ledger.funds, 1000);
    site.siege.activeSiegeType = SiegeType.none;
    game.gameState.date = game.date.add(const Duration(days: 1));
    processFrontBusinesses();
    expect(game.ledger.funds, 1125);
    site.frontBusiness = FrontBusiness.fromJson(
      jsonDecode(jsonEncode(site.frontBusiness!.toJson()))
          as Map<String, dynamic>,
    );
    expect(site.frontBusiness!.rushOrderPending, isFalse);
    expect(site.frontBusiness!.rushOrderAccepted, isFalse);
    processFrontBusinesses();
    expect(game.ledger.funds, 1125);
    site.frontBusiness!.rushOrderPending = true;
    site.frontBusiness!.operatingDaysSinceOffer = 6;
    expect(declinePrintShopRushOrder(site), isTrue);
    expect(site.frontBusiness!.operatingDaysSinceOffer, 0);
    expect(site.frontBusiness!.rushOrderPending, isFalse);
    expect(game.ledger.funds, 1125);
  });
}
