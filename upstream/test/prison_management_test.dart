import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/prison_management.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/prison_activity.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature prisoner;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    engine.console = Console();
    prisoner = game.pool.first
      ..location = game.sites.firstWhere((site) => site.type == SiteType.prison)
      ..sentence = 12
      ..align = Alignment.liberal
      ..sleeperAgent = false
      ..deathPenalty = false
      ..prisonActivity = null;
    game.laws[Law.prisons] = DeepAlignment.moderate;
  });

  test(
    'inspect, cancel and revisit preserves whole campaign and RNG',
    () async {
      final before = jsonEncode(game.gameState);
      reseedRNG(seed: 38123);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 38123);
      final frames = await playChoices(managePrisoners, (
        frame,
        actions,
        prompt,
      ) {
        expect(engine.console.navigation?.section, 'people');
        if (prompt == 0 || prompt == 2) {
          expect(engine.console.screen, 'prison-management');
          expect(
            actions
                .singleWhere((action) => action.entityType == 'prisoner-person')
                .entityId,
            prisoner.id.toString(),
          );
          return 'a';
        }
        if (prompt == 1 || prompt == 3) {
          expect(engine.console.screen, 'prison-order');
          expect(frame, contains('Keep your head down'));
          expect(frame, contains('monthly'));
          expect(
            actions
                .where((action) => action.entityType == 'prison-order')
                .length,
            5,
          );
          expect(
            actions
                .singleWhere((action) => action.entityId == 'studyLaw')
                .entityCategory,
            prisoner.id.toString(),
          );
          return 'Escape';
        }
        return 'Enter';
      });
      expect(frames.length, 5);
      expect(jsonEncode(game.gameState), before);
      expect(prisoner.prisonActivity, isNull);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'source choice changes only selected prisoner order and can be reversed',
    () async {
      final activity = jsonEncode(prisoner.activity);
      final other = game.pool.firstWhere((person) => person != prisoner);
      final otherBefore = jsonEncode(other);
      final frames = await playChoices(
        () => managePrisoners(personId: prisoner.id),
        (frame, actions, prompt) {
          if (prompt == 0) {
            expect(
              actions
                  .singleWhere((action) => action.entityId == 'studyLaw')
                  .enabled,
              isTrue,
            );
            return 'b';
          }
          if (prompt == 1) {
            expect(frame, contains('Current order: Study Law'));
            expect(prisoner.prisonActivity!.order, PrisonOrder.studyLaw);
            return 'a';
          }
          expect(frame, contains('Current order: Keep your head down'));
          return 'Enter';
        },
      );
      expect(frames.length, 3);
      expect(prisoner.prisonActivity!.order, PrisonOrder.keepHeadDown);
      expect(jsonEncode(prisoner.activity), activity);
      expect(jsonEncode(other), otherBefore);
    },
  );

  test(
    'ineligible prisoners expose restriction and reject keyboard bypass',
    () async {
      prisoner.deathPenalty = true;
      final before = jsonEncode(game.gameState);
      await playChoices(() => managePrisoners(personId: prisoner.id), (
        frame,
        actions,
        prompt,
      ) {
        expect(frame, contains('Death row does not allow prison projects'));
        expect(
          actions
              .where((action) => action.entityType == 'prison-order')
              .every((action) => !action.enabled),
          isTrue,
        );
        return prompt == 0 ? 'b' : 'Enter';
      });
      expect(jsonEncode(game.gameState), before);
    },
  );

  test(
    'law restriction is visible and source rejects unavailable study',
    () async {
      game.laws[Law.prisons] = DeepAlignment.archConservative;
      await playChoices(() => managePrisoners(personId: prisoner.id), (
        frame,
        actions,
        prompt,
      ) {
        expect(frame, contains('Labor camps do not provide study materials'));
        expect(
          actions
              .singleWhere((action) => action.entityId == 'studyLaw')
              .enabled,
          isFalse,
        );
        return prompt == 0 ? 'b' : 'Enter';
      });
      expect(prisoner.prisonActivity, isNull);
    },
  );

  test(
    'roster pages retain their page after selected prisoner returns',
    () async {
      prisoner.name = 'Prisoner 00';
      for (int i = 1; i < 18; i++) {
        final person = Creature.fromJson(jsonDecode(jsonEncode(prisoner)))
          ..id = game.gameState.nextCreatureId++
          ..name = 'Prisoner ${i.toString().padLeft(2, '0')}';
        game.pool.add(person);
      }
      final before = jsonEncode(game.gameState);
      await playChoices(managePrisoners, (frame, actions, prompt) {
        if (prompt == 0) {
          expect(
            actions
                .where((action) => action.entityType == 'prisoner-person')
                .length,
            16,
          );
          return ']';
        }
        if (prompt == 1) {
          expect(frame, contains('Prisoner 16'));
          expect(frame, isNot(contains('Prisoner 00')));
          return 'a';
        }
        if (prompt == 2) {
          expect(frame, contains('Prison orders: Prisoner 16'));
          return 'Enter';
        }
        expect(frame, contains('Prisoner 16'));
        expect(frame, isNot(contains('Prisoner 00')));
        return 'Enter';
      });
      expect(jsonEncode(game.gameState), before);
    },
  );
}
