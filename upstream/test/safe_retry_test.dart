import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/map_specials.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

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
    engine.console = Console()..screen = 'tactical';
    game.mode = GameMode.site;
    game.activeSite = game.squad.first.site;
    game.sitestory = NewsStory.unpublished(NewsStories.squadSiteAction)
      ..loc = game.activeSite;
    game.encounter.clear();
    game.siteAlarm = false;
    game.siteCrime = 0;
    game.lcsGotDeagle = false;
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
    game.activeSquad!.loot.clear();
  });

  Future<List<String>> useSafe() async {
    var done = false;
    Object? error;
    final reports = <String>[];
    final flow = useTileSpecial().then<void>(
      (_) => done = true,
      onError: (Object e) {
        error = e;
        done = true;
      },
    );
    for (var step = 0; step < 100 && !done; step++) {
      await Future<void>.delayed(Duration.zero);
      final console = engine.console;
      if (!console.awaitingInput) continue;
      if (console.eventMessage != null) reports.add(console.eventMessage!);
      expect(
        console.sendInput(
          console.actions.any((a) => a.key == 'y') ? 'y' : 'Enter',
        ),
        isTrue,
      );
    }
    expect(done, isTrue);
    expect(error, isNull);
    await flow;
    return reports;
  }

  for (final special in [
    TileSpecial.ceoSafe,
    TileSpecial.nursingHomeFiles,
    TileSpecial.insuranceFiles,
    TileSpecial.corporateFiles,
  ]) {
    test(
      '${special.name} retains failure and consumes a successful retry once',
      () async {
        currentTile.special = special;
        // Declared skills guarantee failure (2d6 + 1 < 15), then success.
        for (final person in game.activeSquad!.livingMembers) {
          person.rawSkill[Skill.security] = 1;
        }
        final failed = await useSafe();
        expect(failed.join(' '), contains("can't figure the lock out"));
        expect(currentTile.special, special);
        expect(game.activeSquad!.loot, isEmpty);
        expect(game.siteCrime, 0);
        for (final person in game.activeSquad!.livingMembers) {
          person.rawSkill[Skill.security] = 50;
        }
        final opened = await useSafe();
        expect(opened.join(' '), contains('cracks the safe!'));
        expect(currentTile.special, TileSpecial.none);
        expect(game.activeSquad!.loot, isNotEmpty);
        final count = game.activeSquad!.loot.length;
        final crime = game.siteCrime;
        await useSafe();
        expect(game.activeSquad!.loot, hasLength(count));
        expect(game.siteCrime, crime);
      },
    );
  }
}
