import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/modern/squad_readiness.dart';
import 'package:lcs_new_age/modern/tactical_snapshot.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/operation_history.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/stealth.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    engine.console = Console();
    game.activeSite = game.activeSquad!.site;
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
  });

  test(
    'readiness uses actual ammo and per-patient medical eligibility without changing state or RNG',
    () {
      final patient = game.squad[0];
      final medic = game.squad[1];
      patient.giveWeapon(Weapon('WEAPON_9MM_HANDGUN'));
      patient.weapon.ammo = 0;
      patient.spareAmmo = Ammo('AMMO_9MM', stackSize: 12);
      (patient.body as HumanoidBody).missingRightEye = true;
      for (final person in game.squad) {
        person.rawSkill[Skill.firstAid] = 0;
      }
      medic.rawSkill[Skill.firstAid] = 5;
      medic.stunned = 0;
      medic.blood = medic.maxBlood;
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 793);
      final expected = List.generate(5, (_) => lcsRandom(100000));
      reseedRNG(seed: 793);
      final readiness = SquadReadiness(game.squad);
      expect(readiness.emptyGuns, greaterThan(0));
      expect(
        readiness.details(patient).join(' '),
        contains('0 loaded · 12 compatible'),
      );
      expect(readiness.details(patient).join(' '), contains('Right eye'));
      expect(readiness.medicsFor(patient), [medic]);
      expect(
        readiness.medicsFor(medic),
        isEmpty,
        reason: 'A medic cannot treat their own bleeding.',
      );
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(List.generate(5, (_) => lcsRandom(100000)), expected);
      medic.stunned = 1;
      expect(readiness.medicsFor(patient), isEmpty);
      medic.stunned = 0;
      medic.blood = 40;
      expect(readiness.medicsFor(patient), isEmpty);
    },
  );

  for (final alarm in [false, true]) {
    test(
      'successful stealth explains check without resetting alarm=$alarm or suspicion',
      () async {
        game.siteAlarm = alarm;
        game.siteAlarmTimer = 7;
        game.encounter.clear();
        game.encounter.add(
          Creature()
            ..type = game.squad.first.type
            ..align = Alignment.conservative,
        );
        for (final person in game.squad) {
          person.rawSkill[Skill.stealth] = 50;
        }
        reseedRNG(seed: 771);
        var reports = 0;
        await playChoices(() => disguisecheck(1), (_, _, _) {
          final message = engine.console.eventMessage ?? '';
          expect(message, contains('passed this stealth check'));
          expect(message, contains('does not remove anyone'));
          expect(
            message,
            contains(
              alarm ? 'alarm is still raised' : 'Suspicion remains active',
            ),
          );
          reports++;
          return 'Enter';
        });
        expect(reports, 1);
        expect(game.siteAlarm, alarm);
        expect(game.siteAlarmTimer, 7);
        expect(game.encounter.length, 1);
        expect(
          TacticalMapSnapshot.capture().alarm,
          alarm ? 'Alarm raised' : 'Suspicion building',
        );
      },
    );
  }

  test(
    'operation summary separates carried loot, actual cash and later costs; history round-trips',
    () {
      final person = game.squad.first;
      person.operationHistory.clear();
      final capture = OperationHistoryCapture(game.activeSite!);
      game.activeSquad!.loot.add(Loot(LootTypeIds.cheapJewelry, stackSize: 2));
      game.ledger.addFunds(125, Income.thievery);
      game.ledger.subtractFunds(20, Expense.shopping);
      (person.body as HumanoidBody).missingRightEye = true;
      final before = jsonEncode(game.gameState.toJson());
      capture.finish();
      expect(capture.returnReport, contains('Carried out:'));
      expect(
        capture.returnReport,
        contains('Cash received during operation: \$125 (pawn sales: \$0)'),
      );
      expect(capture.returnReport, contains('Expenses during operation: \$20'));
      expect(
        capture.returnReport,
        contains('Net cash during operation: +\$105'),
      );
      expect(
        capture.returnReport,
        contains('later medical bills are separate'),
      );
      final record = person.operationHistory.single;
      expect(record.squadResults.join(' '), contains('+\$105'));
      final saved = jsonEncode(game.gameState.toJson());
      game.gameState = game.GameState.fromJson(jsonDecode(saved));
      expect(jsonEncode(game.gameState.toJson()), saved);
      game.ledger.subtractFunds(500, Expense.hospitalBills);
      expect(capture.returnReport, isNot(contains('\$500')));
      expect(
        before,
        isNot(saved),
      ); // Only recorded history was appended by capture.
    },
  );
}
