import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/creation_bonus_help.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  test(
    'Computers choice projects level, learning ceiling and hacking access',
    () {
      final founder = game.pool.first
        ..body = HumanoidBody()
        ..birthDate = DateTime(game.gameState.date.year - 25)
        ..juice = 0;
      founder.rawSkill[Skill.computers] = 0;
      founder.rawAttributes[Attribute.intelligence] = 5;
      founder.blood = founder.maxBlood;
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 531291);
      final rolls = List.generate(15, (_) => lcsRandom(100000));
      reseedRNG(seed: 531291);
      final preview = CreationBonusPreview(
        founder,
        const CreationBonuses(
          skills: {Skill.computers: 1},
          attributes: {Attribute.intelligence: 1},
        ),
      );
      final help = preview.skill(Skill.computers);
      expect(help, contains('Computers 0 → 1'));
      expect(help, contains('Training cap (Intelligence): 5 → 6'));
      expect(help, contains('Meets the skill requirement'));
      expect(help, contains('Hacker Den'));
      expect(help, contains('any success 0% → 2.8%'));
      expect(preview.after.rawSkill, isNot(same(founder.rawSkill)));
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(List.generate(15, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'attribute forecasts include raw gains, effective modifiers and caps',
    () {
      final founder = game.pool.first;
      final preview = CreationBonusPreview(
        founder,
        const CreationBonuses(attributes: {Attribute.agility: 3}, juice: 50),
      );
      expect(
        preview.after.rawAttributes[Attribute.agility],
        founder.rawAttributes[Attribute.agility]! + 3,
      );
      final help = preview.attribute(Attribute.agility);
      expect(
        help,
        contains(
          '${founder.attribute(Attribute.agility)} → '
          '${preview.after.attribute(Attribute.agility)} effective',
        ),
      );
      expect(help, contains('Training caps'));
      expect(help, contains('Dodge'));
      expect(help, contains('Firearms'));
    },
  );

  test('starting bonuses can exceed a skill cap without being clamped', () {
    final founder = game.pool.first;
    founder.rawAttributes[Attribute.intelligence] = 1;
    founder.rawSkill[Skill.computers] = 10;
    final preview = CreationBonusPreview(
      founder,
      const CreationBonuses(skills: {Skill.computers: 2}),
    );
    expect(preview.after.skill(Skill.computers), 12);
    expect(preview.skill(Skill.computers), contains('Further training waits'));
    expect(founder.skill(Skill.computers), 10);
  });
}
