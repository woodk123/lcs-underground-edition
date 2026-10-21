import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/common_display/print_creature_info.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String row(int index) =>
    engine.console.buffer[index].map((cell) => cell.glyph).join();
String get frame => List.generate(25, row).join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  test(
    'profile, skills grid and top skills agree without changing state or RNG',
    () {
      final person = game.pool.first;
      person.rawSkill.updateAll((_, _) => 0);
      person.rawSkillXP.updateAll((_, _) => 0);
      person.rawSkill[Skill.firearms] = 1;
      person.rawSkillXP[Skill.firearms] = 25;
      person.rawSkillXP[Skill.stealth] = 40;
      person.rawSkillXP[Skill.firstAid] = 34;
      person.rawSkillXP[Skill.persuasion] = 15;
      final saved = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 973);
      final rolls = List.generate(10, (_) => lcsRandom(100000));
      reseedRNG(seed: 973);
      printFullCreatureStats(person);
      final profile = frame;
      expect(profile, contains('1.22'));
      expect(
        profile.indexOf('Stealth:'),
        lessThan(profile.indexOf('First Aid:')),
      );
      expect(
        profile.indexOf('First Aid:'),
        lessThan(profile.indexOf('Persuasion:')),
      );
      engine.console.erase();
      printFullCreatureSkills(person);
      expect(frame, contains('1.22'));
      expect(frame, isNot(contains('1.23')));
      engine.console.erase();
      printTopSkills(0, 0, person, 8);
      expect(frame, contains('Firearms: 1.22'));
      expect(jsonEncode(game.gameState.toJson()), saved);
      expect(List.generate(10, (_) => lcsRandom(100000)), rolls);
    },
  );

  test('skill displays keep pending training at 99+ and never round early', () {
    final person = game.pool.first;
    person.rawSkill[Skill.firearms] = 1;
    for (final (xp, expected) in [
      (109, '1.99'),
      (110, '1.99+'),
      (165, '1.99+'),
    ]) {
      person.rawSkillXP[Skill.firearms] = xp;
      engine.console.erase();
      printSkillValue(person, Skill.firearms, 0, 0);
      expect(row(0).trimLeft(), startsWith(expected));
    }
  });

  test(
    'long Classic visit headers retain date and funds in disjoint columns',
    () {
      final site = game.sites.first
        ..name = "Ravenhill's Very Long Department Store 🛍️";
      game.activeSquad!.activity = Activity(
        ActivityType.visit,
        idString: site.idString,
      );
      for (final funds in [1312, -123456789, 123456789012345]) {
        game.ledger.forceSetFunds(funds);
        locHeader(site);
        final header = row(0);
        expect(header, contains('${game.day}, ${game.year}'));
        expect(header, contains('Visiting'));
        expect(header, contains('…'));
        expect(header.trimRight(), endsWith('Money:  \$$funds'));
        expect(engine.console.locationHeading, contains(site.name));
      }
      game.ledger.forceSetFunds(1312);
      // Header rendering must not edit any campaign fields, including orders.
      final before = jsonEncode(game.gameState.toJson());
      locHeader(site);
      expect(jsonEncode(game.gameState.toJson()), before);
    },
  );
}
