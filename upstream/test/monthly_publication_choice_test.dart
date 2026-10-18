import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

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
    for (final site in game.sites) {
      site.loot.clear();
    }
    game.activeSquad!.site!
      ..controller = SiteController.lcs
      ..loot.add(Loot(LootTypeIds.corpFiles, stackSize: 3));
  });

  for (final publish in [false, true]) {
    test(
      'monthly evidence decision makes ${publish ? 'publishing one copy' : 'declining and retaining files'} explicit',
      () async {
        final base = game.activeSquad!.site!;
        final before = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 11290);
        final expectedSeed = nextRngSeed;
        reseedRNG(seed: 11290);
        void choose() {
          if (!engine.console.awaitingInput || engine.console.lastKey != null) {
            return;
          }
          final text = engine.console.buffer
              .map((row) => row.map((cell) => cell.glyph).join())
              .join('\n');
          expect(
            text,
            contains('Consumes one copy; publishing may provoke retaliation'),
          );
          expect(text, contains('choose one evidence type to publish now'));
          expect(
            engine.console.actions
                .singleWhere((action) => action.key == 'Enter')
                .label,
            contains('Decline this month and keep the evidence'),
          );
          expect(base.loot.whereType<Loot>().single.stackSize, 3);
          engine.console.sendInput(publish ? 'a' : 'Enter');
        }

        engine.console.revision.addListener(choose);
        try {
          final result = await chooseSpecialEdition().timeout(
            const Duration(seconds: 5),
          );
          expect(result?.idName, publish ? LootTypeIds.corpFiles : null);
        } finally {
          engine.console.revision.removeListener(choose);
        }
        expect(base.loot.whereType<Loot>().single.stackSize, publish ? 2 : 3);
        if (!publish) expect(jsonEncode(game.gameState.toJson()), before);
        expect(nextRngSeed, expectedSeed);
      },
    );
  }
}
