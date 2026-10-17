import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/daily/activities/recruiting.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() {
    game.gameState = game.GameState();
    game.laws[Law.pollution] = DeepAlignment.moderate;
    game.laws[Law.nuclearPower] = DeepAlignment.moderate;
  });

  test(
    'law transitions restore mutant recruitment and its current difficulty',
    () {
      expect(
        recruitableCreatures.map((r) => r.type.id),
        isNot(contains(CreatureTypeIds.mutant)),
      );

      for (final enablingLaw in [Law.pollution, Law.nuclearPower]) {
        game.laws[enablingLaw] = DeepAlignment.archConservative;
        expect(
          recruitableCreatures
              .singleWhere((r) => r.type.id == CreatureTypeIds.mutant)
              .difficulty,
          6,
        );
        game.laws[Law.pollution] = DeepAlignment.archConservative;
        game.laws[Law.nuclearPower] = DeepAlignment.archConservative;
        expect(
          recruitableCreatures
              .singleWhere((r) => r.type.id == CreatureTypeIds.mutant)
              .difficulty,
          2,
        );
        game.laws[Law.pollution] = DeepAlignment.moderate;
        game.laws[Law.nuclearPower] = DeepAlignment.moderate;
        expect(
          recruitableCreatures.map((r) => r.type.id),
          isNot(contains(CreatureTypeIds.mutant)),
        );
      }
    },
  );

  test('each campaign receives all currently available professions once', () {
    final expected = creatureTypes.values
        .where(
          (type) =>
              type.recruitActivityDifficulty != null &&
              type.id != CreatureTypeIds.mutant,
        )
        .map((type) => type.id)
        .toSet();
    expect(expected, isNotEmpty);
    final targets = recruitableCreatures;
    expect(targets.map((r) => r.type.id).toSet(), expected);
    expect(targets.length, expected.length);

    game.laws[Law.pollution] = DeepAlignment.archConservative;
    expect(recruitableCreatures.length, expected.length + 1);
    game.gameState = game.GameState();
    game.laws[Law.pollution] = DeepAlignment.moderate;
    game.laws[Law.nuclearPower] = DeepAlignment.moderate;
    expect(recruitableCreatures.map((r) => r.type.id).toSet(), expected);
  });

  test(
    'difficulty dominates alphabetical order and reads keep paging stable',
    () {
      final targets = recruitableCreatures;
      final ids = targets.map((r) => r.type.id).toList();
      for (var i = 1; i < targets.length; i++) {
        final previous = targets[i - 1];
        final current = targets[i];
        expect(previous.difficulty, lessThanOrEqualTo(current.difficulty));
        if (previous.difficulty == current.difficulty) {
          expect(previous.name.compareTo(current.name), lessThanOrEqualTo(0));
        }
      }
      for (var i = 0; i < targets.length * 2; i++) {
        expect(recruitableCreatures.map((r) => r.type.id), orderedEquals(ids));
      }
    },
  );

  test(
    'a later law change cannot mutate an already displayed target snapshot',
    () {
      game.laws[Law.pollution] = DeepAlignment.archConservative;
      final displayed = recruitableCreatures;
      final displayedIds = displayed.map((r) => r.type.id).toList();
      final mutant = displayed.singleWhere(
        (r) => r.type.id == CreatureTypeIds.mutant,
      );
      expect(mutant.difficulty, 6);

      game.laws[Law.nuclearPower] = DeepAlignment.archConservative;
      expect(
        recruitableCreatures
            .singleWhere((r) => r.type.id == CreatureTypeIds.mutant)
            .difficulty,
        2,
      );
      expect(mutant.difficulty, 6);
      game.laws[Law.pollution] = DeepAlignment.moderate;
      game.laws[Law.nuclearPower] = DeepAlignment.moderate;
      expect(
        recruitableCreatures.map((r) => r.type.id),
        isNot(contains(CreatureTypeIds.mutant)),
      );
      expect(displayed.map((r) => r.type.id), orderedEquals(displayedIds));
    },
  );
}
