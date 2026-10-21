import 'dart:convert';
import 'dart:io';

import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/saveload/save_load.dart';

import '../test_support.dart';

/// Retains fixture bytes, decoding a fresh campaign for every test.
/// Scenario-specific changes (orders, extra crew, injuries) stay in the suite.
class CampaignFixture {
  CampaignFixture._(this.contents);

  final String contents;

  static Future<CampaignFixture> load(String path) async {
    await ensureGameDataLoaded();
    return CampaignFixture._(await File(path).readAsString());
  }

  void restoreState() {
    game.gameState = decodeSaveContents(contents).gameState!;
  }

  void restoreHeadquarters({required Console console}) {
    engine.console = console;
    restoreState();
    game.mode = GameMode.base;
    game.activeSquadMember = null;
  }
}

/// Clones the first fixture person, allocating a fresh ID without game rolls.
/// Deliberately retains their other data; callers declare any further changes.
Creature addTestCrewMember({String? name}) {
  final person = Creature.fromJson(
    jsonDecode(jsonEncode(game.pool.first.toJson())) as Map<String, dynamic>,
  );
  person.id = game.gameState.nextCreatureId++;
  person.name = name ?? 'Crew ${person.id}';
  person.squadId = null;
  game.pool.add(person);
  return person;
}

String campaignSnapshot() => jsonEncode(game.gameState.toJson());
