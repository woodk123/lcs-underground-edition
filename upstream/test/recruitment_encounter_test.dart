import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/recruiting.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/recruitment_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

Future<void> _respond(String key) async {
  expect(engine.console.awaitingInput, isTrue);
  expect(engine.console.sendInput(key), isTrue);
  // Let the real asynchronous engine reach its next decision.
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late Creature recruiter;
  late RecruitData target;
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    recruiter = game.pool.first;
    target = recruitableCreatures.firstWhere((r) => !r.type.animal);
    recruiter.activity = Activity(
      ActivityType.recruiting,
      idString: target.type.id,
    );
    recruiter.rawSkill[Skill.streetSmarts] = 0;
    game.siteAlarm = true;
    game.siteAlienated = game.SiteAlienation.alienatedEveryone;
  });

  void setCandidateCount(int count) {
    final baseRoll = recruiter.skillRoll(Skill.streetSmarts, take10: true);
    recruiter.rawSkill[Skill.streetSmarts] =
        count * target.difficulty - baseRoll;
  }

  test(
    'zero candidates clears stale recruitment context on returning',
    () async {
      setCandidateCount(0);
      engine.console.recruitment = RecruitmentContext(
        recruiter: recruiter,
        prospects: [],
      );
      final flow = doActivityRecruit(recruiter);
      await _respond('Enter');
      expect(game.encounter, isEmpty);
      await _respond('Enter');
      await flow;
      expect(engine.console.recruitment, isNull);
      expect(engine.console.awaitingInput, isFalse);
    },
  );

  test(
    'single meeting resets stale site hostility and clears context',
    () async {
      setCandidateCount(1);
      final flow = doActivityRecruit(recruiter);
      await _respond('Enter');
      expect(engine.console.recruitment!.prospects, hasLength(1));
      await _respond('Enter');
      expect(game.siteAlarm, isFalse);
      expect(game.siteAlienated, game.SiteAlienation.none);
      expect(
        engine.console.actions.any(
          (a) => a.label.contains('Strike up a conversation'),
        ),
        isTrue,
      );
      expect(engine.console.recruitment!.prospects, hasLength(1));
      await _respond('c');
      await flow;
      expect(engine.console.recruitment, isNull);
      expect(engine.console.awaitingInput, isFalse);
    },
  );

  test(
    'multiple meetings return to remaining prospects and clean up on exit',
    () async {
      setCandidateCount(3);
      final flow = doActivityRecruit(recruiter);
      await _respond('Enter');
      expect(engine.console.recruitment!.prospects, hasLength(3));
      final first = game.encounter.first;
      await _respond('a');
      expect(game.siteAlarm, isFalse);
      expect(game.siteAlienated, game.SiteAlienation.none);
      expect(engine.console.recruitment!.prospects, hasLength(1));
      await _respond('c');
      expect(engine.console.recruitment!.prospects, hasLength(2));
      expect(game.encounter, isNot(contains(first)));
      await _respond('Escape');
      await flow;
      expect(game.encounter, isEmpty);
      expect(engine.console.recruitment, isNull);
      expect(engine.console.awaitingInput, isFalse);
    },
  );

  test(
    'declining the multiple-candidate list clears context without a meeting',
    () async {
      setCandidateCount(3);
      final flow = doActivityRecruit(recruiter);
      await _respond('Enter');
      expect(engine.console.recruitment!.prospects, hasLength(3));
      await _respond('Enter');
      await flow;
      expect(game.encounter, isEmpty);
      expect(engine.console.recruitment, isNull);
    },
  );
}
