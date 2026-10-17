import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/level.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/juice_status.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature person;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    person = game.pool.first;
    person.hireId = 999991;
    person.brainwashed = false;
    person.align = Alignment.liberal;
  });

  test('fixed daily activity Juice caps retain source values and unknown rewards remain unspecified', () {
    expect(knownActivityJuiceCap(ActivityType.communityService), 10);
    expect(knownActivityJuiceCap(ActivityType.trouble), 50);
    expect(knownActivityJuiceCap(ActivityType.hacking), 200);
    expect(knownActivityJuiceCap(ActivityType.stealCars), 100);
    expect(knownActivityJuiceCap(ActivityType.graffiti), isNull,
        reason: 'Mural rewards have a variable power-based cap.');
    expect(knownActivityJuiceCap(ActivityType.none), isNull);
    expect(knownActivityJuiceCap(ActivityType.sellArt), isNull);
  });

  final cases = <int, (int, int?)>{
    -100: (-2, -49),
    -51: (-2, -49),
    -50: (-2, -49),
    -49: (-1, -9),
    -11: (-1, -9),
    -10: (-1, -9),
    -9: (0, 0),
    -1: (0, 0),
    0: (1, 10),
    9: (1, 10),
    10: (2, 50),
    49: (2, 50),
    50: (3, 100),
    99: (3, 100),
    100: (4, 200),
    199: (4, 200),
    200: (5, 500),
    499: (5, 500),
    500: (6, 1000),
    999: (6, 1000),
    1000: (7, null),
    1200: (7, null),
  };
  for (final entry in cases.entries) {
    test('Juice ${entry.key} has exact source rank and next milestone', () {
      person.juice = entry.key;
      final status = JuiceStatus(person);
      expect(status.juice, entry.key);
      expect(status.level, person.level);
      expect(status.level, entry.value.$1);
      expect(status.title, person.title);
      expect(status.nextJuice, entry.value.$2);
      expect(
        status.remaining,
        entry.value.$2 == null ? null : entry.value.$2! - entry.key,
      );
      expect(
        status.nextTitle,
        entry.value.$2 == null
            ? null
            : levelTitle(levelFromXP(entry.value.$2!), person.align),
      );
      expect(status.progress, inInclusiveRange(0, 1));
    });
  }

  test('rank percentage changes include negative penalties and crisis reset', () {
    final bonuses = {
      -50: null,
      -49: -40,
      -10: -40,
      -9: -20,
      -1: -20,
      0: 0,
      10: 10,
      50: 20,
      100: 30,
      200: 40,
      500: 50,
      1000: 60,
    };
    for (final entry in bonuses.entries) {
      person.juice = entry.key;
      expect(
        JuiceStatus(person).bonusPercent,
        entry.value,
        reason:
            'Juice ${entry.key} must describe levelAttribute, including penalties.',
      );
    }
  });

  test('alignment exemptions persist even through every negative rank', () {
    for (final alignment in Alignment.values) {
      person.align = alignment;
      for (final juice in [-50, -49, -9, 0, 10, 1000]) {
        person.juice = juice;
        final status = JuiceStatus(person);
        for (final attribute in Attribute.values) {
          final exempt =
              alignment == Alignment.liberal && attribute == Attribute.wisdom ||
              alignment == Alignment.conservative &&
                  attribute == Attribute.heart;
          expect(
            status.affectsAttribute(attribute),
            !exempt,
            reason: '$alignment / Juice $juice / $attribute',
          );
          if (exempt) {
            expect(
              levelAttribute(person, attribute),
              person.permanentAttribute(attribute),
            );
          }
        }
      }
    }
  });

  test(
    'current and next recruitment capacity match source for every rank and founder',
    () {
      for (final founder in [false, true]) {
        person.hireId = founder ? null : 999991;
        for (final juice in [-50, -49, -9, 0, 10, 50, 100, 200, 500, 1000]) {
          person.juice = juice;
          final status = JuiceStatus(person);
          expect(status.recruitCap, person.maxSubordinates);
          final next = status.nextJuice;
          if (next == null) {
            expect(status.nextRecruitCap, isNull);
          } else {
            person.juice = next;
            final nextCap = person.maxSubordinates;
            person.juice = juice;
            expect(status.nextRecruitCap, nextCap);
          }
        }
      }
      person
        ..brainwashed = true
        ..juice = 500
        ..hireId = null;
      expect(JuiceStatus(person).recruitCap, 0);
      expect(JuiceStatus(person).nextRecruitCap, 0);
      for (final alignment in [Alignment.moderate, Alignment.conservative]) {
        person
          ..brainwashed = false
          ..align = alignment
          ..juice = 0;
        expect(
          JuiceStatus(person).recruitCap,
          0,
          reason: 'The founder bonus belongs to Liberals only.',
        );
      }
    },
  );

  test(
    'recruit slots use source exclusions without inventing alive or squad filters',
    () {
      person.juice = 100;
      final initialUsed = person.maxSubordinates - person.subordinatesLeft;
      for (final (index, seduced, brainwashed, alive) in [
        (0, false, false, true),
        (1, true, false, true),
        (2, false, true, true),
        (3, false, false, false),
      ]) {
        final recruit = Creature.fromJson(
          jsonDecode(jsonEncode(person.toJson())) as Map<String, dynamic>,
        );
        recruit
          ..id = 99000 + index
          ..hireId = person.id
          ..seduced = seduced
          ..brainwashed = brainwashed
          ..alive = alive;
        game.pool.add(recruit);
      }
      final status = JuiceStatus(person);
      expect(status.recruitsUsed, initialUsed + 2);
      expect(status.freeRecruitSlots, math.max(0, person.subordinatesLeft));
    },
  );

  test('stage progress uses the active rank interval and remains bounded', () {
    for (final (juice, progress) in [
      (0, 0.0),
      (5, .5),
      (10, 0.0),
      (30, .5),
      (50, 0.0),
      (75, .5),
      (350, .5),
      (750, .5),
      (1000, 1.0),
    ]) {
      person.juice = juice;
      expect(JuiceStatus(person).progress, closeTo(progress, .00001));
    }
  });

  test(
    'all explanatory getters leave full campaign, actor and RNG unchanged',
    () {
      for (final juice in [-50, -49, -9, 0, 160, 999, 1000]) {
        person.juice = juice;
        final before = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 987161);
        final rolls = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 987161);
        final status = JuiceStatus(person);
        expect(status.juice, juice);
        expect(status.title, isNotEmpty);
        expect(status.bonusSummary, isNotEmpty);
        final displayed = [
          status.level,
          status.nextJuice,
          status.nextTitle,
          status.remaining,
          status.progress,
          status.bonusPercent,
          status.recruitCap,
          status.nextRecruitCap,
          status.recruitsUsed,
          status.freeRecruitSlots,
          for (final attribute in Attribute.values)
            status.affectsAttribute(attribute),
        ];
        expect(displayed.length, 10 + Attribute.values.length);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      }
    },
  );
}
