import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/creature/unique_creatures.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/flag_type.dart';
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/modern/activity_calculations.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String _snapshot() => jsonEncode(game.gameState.toJson());

void _mood(double value) {
  for (final view in View.values.where(
    (view) => view.index < View.amRadio.index,
  )) {
    game.publicOpinion[view] = value;
  }
}

void _skills(Creature person, Map<Skill, int> values) {
  for (final skill in Skill.values) {
    person.rawSkill[skill] = values[skill] ?? 0;
  }
}

void main() {
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
  });

  test(
    'all calculations preserve the actual campaign, pending input and RNG',
    () {
      final actor = game.pool.first;
      final assigned = actor.activity;
      final cloth = clothingTypes.values.firstWhere(
        (type) => type.makeDifficulty >= 0,
      );
      final flag = flagTypes.values.first;
      final target = creatureTypes.values.firstWhere(
        (type) => type.recruitActivityDifficulty != null,
      );
      final before = _snapshot();
      final consoleRevision = engine.console.revision.value;
      reseedRNG(seed: 189431);
      final rolls = List.generate(30, (_) => lcsRandom(100000));
      reseedRNG(seed: 189431);
      for (final type in ActivityType.values) {
        final parameter = switch (type) {
          ActivityType.makeClothing => '${cloth.idName}:ARMOR0',
          ActivityType.makeFlag => flag.idName,
          ActivityType.recruiting => target.id,
          ActivityType.visit => actor.site!.idString,
          _ => null,
        };
        final order = Activity(type, skill: Skill.art, idString: parameter);
        for (final undercover in [false, true]) {
          final calculation = calculationForActivity(
            type,
            actor: actor,
            activity: order,
            sleeper: undercover,
          );
          expect(calculation.formula, isNotEmpty, reason: type.name);
          expect(calculation.result, isNotEmpty, reason: type.name);
          expect(calculation.source, isNotEmpty, reason: type.name);
          expect(
            _snapshot(),
            before,
            reason: '${type.name} preview must be read-only',
          );
          expect(actor.activity, same(assigned));
          calculationForActivity(
            type,
            activity: Activity(type),
            sleeper: undercover,
          );
        }
      }
      expect(_snapshot(), before);
      expect(engine.console.revision.value, consoleRevision);
      expect(engine.console.awaitingInput, isFalse);
      expect(List.generate(30, (_) => lcsRandom(100000)), rolls);
    },
  );

  test('donations use the actual strict mood boundaries and raw skills', () {
    final actor = game.pool.first;
    actor.equippedClothing = null;
    expect(actor.clothing.type.professionalism, 0);
    _skills(actor, {Skill.persuasion: 20, Skill.streetSmarts: 20});
    for (final (mood, multiplier, income) in [
      (10.0, 1.0, 14),
      (10.01, .5, 7),
      (35.0, .5, 7),
      (35.01, .25, 3),
      (65.0, .25, 3),
      (65.01, .125, 2),
      (90.0, .125, 2),
      (90.01, .0625, 1),
    ]) {
      _mood(mood);
      final calculation = calculationForActivity(
        ActivityType.donations,
        actor: actor,
      );
      expect(calculation.quantities['baselineRoll'], 27);
      expect(calculation.quantities['moodMultiplier'], multiplier);
      expect(calculation.quantities['estimatedIncome'], income);
      expect(calculation.estimated, isTrue);
    }
  });

  test('music uses Street Smarts and the equipped instrument factor', () {
    final actor = game.pool.first;
    _mood(0);
    _skills(actor, {Skill.music: 6, Skill.streetSmarts: 4, Skill.business: 20});
    actor.equippedWeapon = null;
    final without = calculationForActivity(
      ActivityType.sellMusic,
      actor: actor,
    );
    expect(without.quantities['baselineRoll'], 12);
    expect(without.quantities['instrumentMultiplier'], .25);
    expect(without.quantities['estimatedIncome'], 3);
    final instrument = weaponTypes.values.firstWhere((type) => type.instrument);
    actor.equippedWeapon = Weapon(instrument.idName);
    final withInstrument = calculationForActivity(
      ActivityType.sellMusic,
      actor: actor,
    );
    expect(withInstrument.quantities['instrumentMultiplier'], 1);
    expect(withInstrument.quantities['estimatedIncome'], 12);
    expect(withInstrument.formula, contains('Music + Street Smarts'));
  });

  test(
    'legal public work exposes current 0, 2, 50 and 51 percent interruption gates',
    () {
      final actor = game.pool.first;
      final clothes = actor.equippedClothing;
      actor.rawSkill[Skill.streetSmarts] = 2;
      for (final (indecent, heat, chance) in [
        (false, 20, 0),
        (false, 21, 2),
        (true, 20, 50),
        (true, 21, 51),
      ]) {
        actor.equippedClothing = indecent ? null : clothes;
        actor.heat = heat;
        final calculation = calculationForActivity(
          ActivityType.donations,
          actor: actor,
        );
        expect(calculation.quantities['policeInterruptPercent'], chance);
        expect(
          calculation.qualifiers.join(' '),
          contains('not guaranteed arrest'),
        );
        expect(
          calculation.qualifiers.join(' '),
          contains('If that draw does not trigger'),
        );
      }
      expect(
        calculationForActivity(ActivityType.sellDrugs, actor: actor).quantities,
        isNot(contains('policeInterruptPercent')),
      );
    },
  );

  test(
    'brownies use drug law and prostitution retains its real rounded work gate',
    () {
      final actor = game.pool.first;
      _skills(actor, {
        Skill.persuasion: 3,
        Skill.business: 3,
        Skill.streetSmarts: 3,
      });
      for (final (law, income) in [
        (DeepAlignment.archConservative, 120),
        (DeepAlignment.conservative, 60),
        (DeepAlignment.moderate, 30),
        (DeepAlignment.liberal, 15),
        (DeepAlignment.eliteLiberal, 8),
      ]) {
        game.laws[Law.drugs] = law;
        expect(
          calculationForActivity(
            ActivityType.sellDrugs,
            actor: actor,
          ).quantities['estimatedIncome'],
          income,
        );
      }
      _skills(actor, {
        Skill.seduction: 4,
        Skill.streetSmarts: 2,
        Skill.business: 2,
      });
      final sexWork = calculationForActivity(
        ActivityType.prostitution,
        actor: actor,
      );
      expect(sexWork.quantities['baselineRoll'], 10);
      expect(sexWork.quantities['estimatedIncome'], 14);
      expect(sexWork.quantities['workingDayIncomeBaseline'], 42);
      expect(
        sexWork.qualifiers.join(' '),
        contains('sting branch pays no income'),
      );
    },
  );

  test(
    'pending learning skill has no inferred old target and training respects storage/caps',
    () {
      final actor = game.pool.first;
      actor.activity = Activity(ActivityType.study, skill: Skill.art);
      actor.rawSkill[Skill.art] = 3;
      actor.rawAttributes[Attribute.heart] = 10;
      actor.juice = 0;
      actor.heartDamage = 0;
      actor.rawSkillXP[Skill.art] = 190;
      final pending = calculationForActivity(
        ActivityType.study,
        actor: actor,
        activity: Activity(ActivityType.study),
      );
      expect(pending.quantities, isNot(contains('requestedXp')));
      expect(pending.result, contains('Choose the skill'));
      final classOrder = Activity(ActivityType.takeClass, skill: Skill.art);
      final course = calculationForActivity(
        ActivityType.takeClass,
        actor: actor,
        activity: classOrder,
      );
      expect(course.quantities['requestedXp'], 35);
      expect(
        course.quantities['storedXpGain'],
        5,
      ); // level-3 storage cap is 195.
      expect(course.quantities['dailyFee'], 30);
      expect(course.result, contains('cannot cover'));
      actor.rawSkill[Skill.art] = 10;
      expect(
        calculationForActivity(
          ActivityType.takeClass,
          actor: actor,
          activity: classOrder,
        ).quantities['storedXpGain'],
        0,
      );
      actor.rawSkill[Skill.art] = 2;
      actor.rawAttributes[Attribute.heart] = 1;
      final capLimited = calculationForActivity(
        ActivityType.study,
        actor: actor,
        activity: Activity(ActivityType.study, skill: Skill.art),
      );
      expect(capLimited.quantities['skillLevel'], 2);
      expect(capLimited.quantities['skillCap'], 1);
      expect(capLimited.quantities['storedXpGain'], 0);
      expect(
        actor.skill(Skill.art),
        2,
        reason: 'A reduced cap must not reduce raw skill.',
      );
    },
  );

  test(
    'teaching counts skill/student pairs, applies integer overload and sleeper eligibility',
    () {
      final teacher = game.pool.first;
      for (final person in game.pool) {
        _skills(person, {});
        for (final attribute in Attribute.values) {
          person.rawAttributes[attribute] = 20;
        }
        person.juice = 0;
        person.blood = person.maxBlood;
      }
      _skills(teacher, {
        Skill.law: 3,
        Skill.persuasion: 2,
        Skill.writing: 4,
        Skill.teaching: 2,
      });
      var result = calculationForActivity(
        ActivityType.teachLiberalArts,
        actor: teacher,
      );
      expect(result.quantities['learnerCount'], 4);
      expect(result.quantities['workload'], 12);
      expect(result.quantities['dailyFee'], 20);
      expect(result.quantities['exampleRequestedXp'], 7); // ((9*30~/12)+9)~/4.
      final police = game.sites.firstWhere(
        (site) =>
            site.city == teacher.site!.city &&
            site.type == SiteType.policeStation,
      );
      final student = game.pool[1];
      student.location = police;
      result = calculationForActivity(
        ActivityType.teachLiberalArts,
        actor: teacher,
      );
      expect(result.quantities['workload'], 9);
      expect(result.quantities['dailyFee'], 18);
      student.sleeperAgent = true;
      result = calculationForActivity(
        ActivityType.teachLiberalArts,
        actor: teacher,
      );
      expect(result.quantities['workload'], 12);
      teacher.rawSkill[Skill.teaching] = 20;
      expect(
        calculationForActivity(
          ActivityType.teachLiberalArts,
          actor: teacher,
        ).quantities['exampleRequestedXp'],
        50,
      );
    },
  );

  test('a class reaching exactly 100 XP can promote at common day end', () {
    final actor = game.pool.first;
    actor.rawAttributes[Attribute.heart] = 10;
    actor.heartDamage = 0;
    actor.juice = 0;
    actor.rawSkill[Skill.art] = 0;
    actor.rawSkillXP[Skill.art] = 50;
    game.ledger.forceSetFunds(100);
    final order = Activity(ActivityType.takeClass, skill: Skill.art);
    final calculation = calculationForActivity(
      ActivityType.takeClass,
      actor: actor,
      activity: order,
    );
    expect(calculation.quantities['storedXpGain'], 50);
    expect(calculation.quantities['xpAfterTraining'], 100);
    expect(calculation.quantities['dayEndLevelThreshold'], 100);
    expect(
      calculation.qualifiers.join(' '),
      contains('XP ≥ 100 + 10 × current'),
    );
    // Verify the stated boundary against the actual retained training/leveling.
    actor.train(Skill.art, 50);
    expect(actor.skill(Skill.art), 0);
    actor.skillUp();
    expect(actor.skill(Skill.art), 1);
    expect(actor.skillXP(Skill.art), 0);
  });

  test(
    'hacking/fraud use the entire source pool and different Hacker Den filters',
    () {
      final actor = game.pool[0];
      for (final person in game.pool) {
        _skills(person, {});
        person.activity = Activity.none();
      }
      actor.base!.compound.hackerDen = true;
      actor.rawSkill[Skill.computers] = 8;
      game.pool[1].rawSkill[Skill.computers] = 6;
      game.pool[1].activity = Activity(ActivityType.hacking);
      game.pool[2].rawSkill[Skill.computers] = 20;
      game.pool[2].activity = Activity(ActivityType.hacking);
      game.pool[2].alive = false;
      game.pool[3].rawSkill[Skill.computers] = 10;
      game.pool[3].activity = Activity(ActivityType.ccfraud);
      game.pool[3].squad = null;
      game.pool[4].rawSkill[Skill.computers] = 4;
      game.pool[4].activity = Activity(ActivityType.hacking);
      game.pool[4].sleeperAgent = true;
      var hacking = calculationForActivity(ActivityType.hacking, actor: actor);
      expect(hacking.quantities['teamSize'], 3);
      expect(hacking.quantities['baselineBestRoll'], 15);
      expect(hacking.quantities['baselineTeamScore'], 17);
      expect(hacking.qualifiers.join(' '), contains('unboosted best roll'));
      final fraud = calculationForActivity(ActivityType.ccfraud, actor: actor);
      expect(fraud.quantities['teamSize'], 2);
      expect(fraud.quantities['baselineTeamScore'], 32);
      expect(fraud.quantities['baselineCashDraws'], 11);
      expect(fraud.quantities['conditionalMeanCash'], 275);
      expect(
        fraud.result,
        contains('not the expected payout across all skill rolls'),
      );
      actor.base!.compound.hackerDen = false;
      hacking = calculationForActivity(ActivityType.hacking, actor: actor);
      expect(hacking.quantities['teamSize'], 0);
      expect(
        calculationForActivity(
          ActivityType.ccfraud,
          actor: actor,
        ).quantities['teamSize'],
        2,
      );
      actor.base!.siege.activeSiegeType = SiegeType.police;
      actor.base!.siege.lightsOff = true;
      expect(
        calculationForActivity(
          ActivityType.ccfraud,
          actor: actor,
        ).quantities['teamSize'],
        0,
      );
    },
  );

  test(
    'a queued squad destination excludes personal preview from its daily team',
    () {
      final actor = game.pool.first;
      actor.base!.compound.hackerDen = true;
      actor.squad!.activity = Activity(
        ActivityType.visit,
        idString: actor.site!.idString,
      );
      final assigned = actor.activity;
      final before = _snapshot();
      expect(
        calculationForActivity(
          ActivityType.hacking,
          actor: actor,
        ).quantities['teamSize'],
        0,
      );
      expect(actor.activity, same(assigned));
      expect(_snapshot(), before);
    },
  );

  test(
    'Guardian exposes raw influence power and the implemented fourfold stream',
    () {
      final actor = game.pool.first;
      _skills(actor, {
        Skill.writing: 4,
        Skill.persuasion: 2,
        Skill.law: 2,
        Skill.science: 3,
        Skill.religion: 1,
        Skill.business: 5,
      });
      final writing = calculationForActivity(
        ActivityType.writeGuardian,
        actor: actor,
      );
      expect(writing.quantities['baselineInfluencePower'], 17);
      final streaming = calculationForActivity(
        ActivityType.streamGuardian,
        actor: actor,
      );
      expect(streaming.quantities['baselineInfluencePower'], 60);
      expect(
        streaming.qualifiers.join(' '),
        contains('not a direct percentage-point'),
      );
    },
  );

  test(
    'flag check probability is exact and hover never consumes recycled cloth',
    () {
      final actor = game.pool.first;
      final flag = flagTypes.values.firstWhere(
        (type) => type.makeDifficulty == 6,
      );
      actor.rawSkill[Skill.tailoring] = 0;
      actor.site!.loot.clear();
      final cloth = Loot(LootTypeIds.recycledCloth, stackSize: 2);
      actor.site!.loot.add(cloth);
      final order = Activity(ActivityType.makeFlag, idString: flag.idName);
      final before = _snapshot();
      final calculation = calculationForActivity(
        ActivityType.makeFlag,
        actor: actor,
        activity: order,
      );
      expect(calculation.quantities['adjustedDifficulty'], 6);
      var successfulDraws = 0;
      for (var first = 0; first < 10; first++) {
        for (var second = 0; second < 10; second++) {
          if (first >= 6 || second >= 6) successfulDraws++;
        }
      }
      expect(calculation.quantities['flagSuccessPercent'], successfulDraws);
      expect(calculation.quantities['supplyCost'], flag.makePrice ~/ 2);
      expect(cloth.stackSize, 2);
      expect(_snapshot(), before);
      actor.rawSkill[Skill.tailoring] = 6;
      expect(
        calculationForActivity(
          ActivityType.makeFlag,
          actor: actor,
          activity: order,
        ).quantities['flagSuccessPercent'],
        100,
      );
    },
  );

  test(
    'community service uses integer awareness gates and does not lower Juice at cap',
    () {
      final actor = game.pool.first;
      game.publicOpinion[View.lcsKnown] = .25;
      actor.juice = 10;
      final atCap = calculationForActivity(
        ActivityType.communityService,
        actor: actor,
      );
      expect(atCap.quantities['awarenessTriggerPercent'], 1);
      expect(atCap.quantities['juiceGain'], 0);
      actor.juice = 9;
      expect(
        calculationForActivity(
          ActivityType.communityService,
          actor: actor,
        ).quantities['juiceGain'],
        1,
      );
      actor.rawSkill[Skill.art] = 20;
      expect(
        calculationForActivity(
          ActivityType.graffiti,
          actor: actor,
        ).quantities['muralStartDenominator'],
        5,
      );
    },
  );

  test(
    'recruit meetings read the target metadata without using the mutable recruit cache',
    () {
      final actor = game.pool.first;
      actor.rawSkill[Skill.streetSmarts] = 5;
      final target = creatureTypes.values.firstWhere(
        (type) =>
            type.recruitActivityDifficulty == 2 &&
            type.id != CreatureTypeIds.mutant,
      );
      final result = calculationForActivity(
        ActivityType.recruiting,
        actor: actor,
        activity: Activity(ActivityType.recruiting, idString: target.id),
      );
      expect(result.quantities['meetingCount'], 6);
      expect(result.result, contains('not a recruit count'));
      expect(
        calculationForActivity(
          ActivityType.recruiting,
          actor: actor,
          activity: Activity(ActivityType.recruiting),
        ).quantities,
        isNot(contains('meetingCount')),
      );
      game.laws[Law.pollution] = DeepAlignment.archConservative;
      game.laws[Law.nuclearPower] = DeepAlignment.archConservative;
      final mutant = Activity(
        ActivityType.recruiting,
        idString: CreatureTypeIds.mutant,
      );
      expect(
        calculationForActivity(
          ActivityType.recruiting,
          actor: actor,
          activity: mutant,
        ).quantities['meetingDifficulty'],
        2,
      );
      game.laws[Law.nuclearPower] = DeepAlignment.moderate;
      expect(
        calculationForActivity(
          ActivityType.recruiting,
          actor: actor,
          activity: mutant,
        ).quantities['meetingDifficulty'],
        6,
      );
    },
  );

  test(
    'sleeper notice boundaries count exact draws and embezzlement distinguishes capture',
    () {
      final actor = game.pool.first;
      actor.typeId = CreatureTypeIds.corporateCEO;
      actor.infiltration = 1;
      final embezzle = calculationForActivity(
        ActivityType.sleeperEmbezzle,
        actor: actor,
      );
      expect(embezzle.quantities['quietIncome'], 50000);
      expect(embezzle.quantities['noticedIncome'], 40000);
      expect(embezzle.quantities['noticePercent'], 9);
      actor.typeId = CreatureTypeIds.teacher;
      for (final trust in [0.0, .2, .505, .7, 1.0]) {
        actor.infiltration = trust;
        for (final (type, coefficient) in [
          (ActivityType.sleeperEmbezzle, 90),
          (ActivityType.sleeperSteal, 95),
          (ActivityType.sleeperSpy, 100),
        ]) {
          final failing = List.generate(
            100,
            (draw) => draw,
          ).where((draw) => draw > coefficient * trust).length;
          expect(
            calculationForActivity(
              type,
              actor: actor,
            ).quantities['noticePercent'],
            failing,
          );
        }
      }
      actor.infiltration = .2;
      final exactlyZero = calculationForActivity(
        ActivityType.sleeperEmbezzle,
        actor: actor,
      );
      expect(exactlyZero.quantities['noticedIncome'], 0);
      expect(exactlyZero.result, contains('If noticed: \$0'));
      actor.infiltration = .1999;
      expect(
        calculationForActivity(
          ActivityType.sleeperEmbezzle,
          actor: actor,
        ).result,
        contains('capture and no payout'),
      );
      actor.infiltration = .98;
      final resting = calculationForActivity(
        ActivityType.none,
        actor: actor,
        sleeper: true,
      );
      expect(resting.quantities['minimumNextInfiltration'], .99);
      expect(resting.quantities['maximumNextInfiltration'], 1);
    },
  );

  test(
    'sleeper influence includes profession weights and post-step media attenuation',
    () {
      final actor = game.pool.first;
      actor.juice = 0;
      actor.typeId = CreatureTypeIds.author;
      actor.infiltration = .4;
      _skills(actor, {Skill.persuasion: 5, Skill.writing: 3});
      final base =
          actor.attribute(Attribute.charisma) +
          actor.attribute(Attribute.heart) +
          actor.attribute(Attribute.intelligence) +
          5;
      var result = calculationForActivity(
        ActivityType.sleeperLiberal,
        actor: actor,
      );
      expect(result.quantities['professionBonus'], 15);
      expect(result.quantities['professionMultiplier'], 2);
      expect(
        result.quantities['monthlyInfluencePower'],
        ((base + 15) * 2 * .4).round(),
      );
      actor.typeId = CreatureTypeIds.radioPersonality;
      actor.infiltration = .8;
      game.publicOpinion[View.amRadio] = 18.3;
      game.politics.publicInterest[View.amRadio] = 8;
      result = calculationForActivity(
        ActivityType.sleeperLiberal,
        actor: actor,
      );
      const postStep = 18.3 + (100 - 18.3) * 2 / 100;
      final rawPower = (base * 2 * .8).round();
      expect(
        result.quantities['mediaOpinionAfterEffect'],
        closeTo(postStep, 1e-10),
      );
      expect(
        result.quantities['monthlyInfluencePower'],
        rawPower * (100 - postStep) ~/ 100,
      );
      actor.typeId = CreatureTypeIds.punk;
      expect(
        calculationForActivity(
          ActivityType.sleeperLiberal,
          actor: actor,
        ).quantities['monthlyInfluencePower'],
        0,
      );
    },
  );

  test(
    'cabinet preview reads only an existing unique president, never creates one',
    () {
      final actor = game.pool.first;
      actor.typeId = CreatureTypeIds.president;
      game.gameState.uniqueCreatures = UniqueCreatures();
      expect(game.uniqueCreatures.toJson()['_president'], isNull);
      final before = _snapshot();
      reseedRNG(seed: 78841);
      final roll = lcsRandom(100000);
      reseedRNG(seed: 78841);
      final impostor = calculationForActivity(
        ActivityType.sleeperRecruit,
        actor: actor,
      );
      expect(impostor.quantities, isNot(contains('cabinetBonusVotes')));
      expect(_snapshot(), before);
      expect(lcsRandom(100000), roll);
      final serializedActor =
          jsonDecode(jsonEncode(actor.toJson())) as Map<String, dynamic>;
      game.gameState.uniqueCreatures = UniqueCreatures.fromJson({
        '_president': serializedActor,
      });
      game.uniqueCreatures.syncWithPool();
      expect(
        identical(game.uniqueCreatures.toJson()['_president'], actor),
        isTrue,
      );
      actor.juice = 275;
      final existing = calculationForActivity(
        ActivityType.sleeperRecruit,
        actor: actor,
      );
      expect(
        existing.quantities['cabinetBonusVotes'],
        (actor.attribute(Attribute.charisma) / 10).round() + 3,
      );
    },
  );

  test(
    'opaque encounter calculations never invent a payout or overall success chance',
    () {
      for (final type in [ActivityType.stealCars, ActivityType.clinic]) {
        final result = calculationForActivity(
          type,
          actor: game.pool.first,
          activity: Activity(type),
        );
        expect(result.quantities, isEmpty);
        expect(
          result.result,
          contains('no single fixed payout or overall success percentage'),
        );
        expect(result.estimated, isFalse);
      }
      final unavailable = calculationForActivity(ActivityType.augment);
      expect(unavailable.formula, contains('not offered'));
      expect(unavailable.quantities, isEmpty);
    },
  );

  test(
    'wheelchair is free and burial reads existing bodies without disposing any',
    () {
      final actor = game.pool.first;
      actor.rawSkill[Skill.streetSmarts] = 4;
      game.pool[1].alive = false;
      final body = game.pool[1];
      final before = _snapshot();
      final wheelchair = calculationForActivity(
        ActivityType.wheelchair,
        actor: actor,
      );
      expect(wheelchair.quantities['dailyFee'], 0);
      expect(wheelchair.quantities['completedAssignmentsNeeded'], 1);
      final burial = calculationForActivity(ActivityType.bury, actor: actor);
      expect(burial.quantities['localBodies'], 1);
      expect(burial.quantities['localBuriers'], 1);
      expect(burial.quantities['baselineCheck'], 11);
      expect(burial.quantities['checkDifficulty'], 7);
      expect(burial.quantities['requestedXpPerBody'], 50);
      expect(game.pool, contains(same(body)));
      expect(_snapshot(), before);
    },
  );

  test(
    'hostage lead selection and effective demand check ignore unused knowledge power',
    () {
      final actor = game.pool[0];
      final other = game.pool[2];
      final hostage = game.pool[4];
      actor.equippedClothing = null;
      other.equippedClothing = null;
      _skills(actor, {Skill.psychology: 3});
      _skills(other, {Skill.psychology: 4});
      other.activity = Activity(ActivityType.interrogation, idInt: hostage.id);
      final order = Activity(ActivityType.interrogation, idInt: hostage.id);
      final before = _snapshot();
      var calculation = calculationForActivity(
        ActivityType.interrogation,
        actor: actor,
        activity: order,
      );
      expect(calculation.quantities['actorLeadSelectionBase'], 6);
      expect(calculation.quantities['leadSelectionBase'], 8);
      expect(calculation.quantities['sameLocationTenders'], 2);
      expect(calculation.quantities['demandInformationBaseline'], 11);
      expect(_snapshot(), before);
      actor.rawSkill[Skill.business] = 20;
      actor.rawSkill[Skill.religion] = 20;
      actor.rawSkill[Skill.science] = 20;
      calculation = calculationForActivity(
        ActivityType.interrogation,
        actor: actor,
        activity: order,
      );
      expect(calculation.quantities['demandInformationBaseline'], 11);
      actor.rawSkill[Skill.psychology] = 4;
      calculation = calculationForActivity(
        ActivityType.interrogation,
        actor: actor,
        activity: order,
      );
      expect(
        calculation.inputs.join(' '),
        contains('Current lead: ${actor.name}'),
      );
    },
  );
}
