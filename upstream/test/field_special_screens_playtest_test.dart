import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/map_specials.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'screen_capture_support.dart';
import 'test_support.dart';

/// Real map-special readers with declared flat-map geometry and original squad
/// skills. Safe refusal paths inspect these scenes without claiming a heist.
void main() {
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.site;
    game.activeSite = game.squad.first.site;
    game.sitestory = NewsStory.unpublished(NewsStories.squadSiteAction)
      ..loc = game.activeSite;
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)..known = true),
      ),
    );
    engine.console = Console()..screen = 'tactical';
    reseedRNG(seed: 20261017);
    journalReadingScale.value = 1;
  });
  final scenes = <String, Future<void> Function()>{
    'club bouncer': () async {
      specialBouncerGreetSquad();
      await specialBouncerAssessSquad();
    },
    'graffiti opportunity': specialGraffiti,
    'ground loot at headquarters': lootGroundBase,
    'ground loot in operation': lootGroundSite,
    'cosmetics laboratory cages': specialLabCosmeticsCagedAnimals,
    'nuclear controls': specialNuclearOnOff,
    'genetic laboratory cages': specialLabGeneticCagedAnimals,
    'police lockup': specialPoliceStationLockup,
    'courthouse lockup': specialCourthouseLockup,
    'jury room': specialCourthouseJury,
    'prison controls': () => specialPrisonControl(TileSpecial.prisonControl),
    'low security prison controls': () =>
        specialPrisonControl(TileSpecial.prisonControlLow),
    'medium security prison controls': () =>
        specialPrisonControl(TileSpecial.prisonControlMedium),
    'high security prison controls': () =>
        specialPrisonControl(TileSpecial.prisonControlHigh),
    'intelligence supercomputer': specialIntelSupercomputer,
    'sweatshop machinery': specialSweatshopEquipment,
    'polluter machinery': specialPolluterEquipment,
    'laboratory machinery': specialLabEquipment,
    'CEO safe': specialCEOSafe,
    'nursing home files': specialNursingHomeSafe,
    'nursing home patient': specialNursingHomePatient,
    'nursing home patient revisited': () =>
        specialNursingHomePatient(done: true),
    'nursing home manager': specialNursingHomeManager,
    'insurance files': specialInsuranceSafe,
    'insurance claims terminal': specialInsuranceClaimsTerminal,
    'insurance CEO': specialInsuranceCEO,
    'armory': specialArmory,
    'corporate safe': specialCorporateSafe,
    'radio studio': specialRadioBroadcastStudio,
    'cable studio': specialCableBroadcastStudio,
    'museum display': specialDisplayCase,
    'security checkpoint': specialSecurityCheckpoint,
    'metal detector': specialSecurityMetaldetectors,
    'bank vault': specialBankVault,
    'bank teller': specialBankTeller,
    'bank cash': specialBankMoney,
    'Oval Office': specialOvalOffice,
    'CCS boss': specialCCSBoss,
    'first sign': () => specialReadSign(TileSpecial.signOne),
    'second sign': () => specialReadSign(TileSpecial.signTwo),
    'third sign': () => specialReadSign(TileSpecial.signThree),
    'prison rehabilitation report': () => rehabilitation(game.pool.first),
    'prison labor camp report': () => laborCamp(game.pool.first),
    'prison routine report': () => prisonScene(game.pool.first),
  };
  for (final (size, scale) in [
    (const Size(1280, 800), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    for (final scene in scenes.entries) {
      testWidgets('${scene.key} original reader at ${size.width} / $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        journalReadingScale.value = scale;
        var done = false;
        Object? error;
        final flow = scene.value().then(
          (_) => done = true,
          onError: (Object e) {
            error = e;
            done = true;
          },
        );
        try {
          await tester.pumpWidget(
            const RepaintBoundary(key: screenCaptureKey, child: MainApp()),
          );
          await tester.pumpAndSettle();
          for (var step = 0; step < 35 && !done; step++) {
            await capturePlaytestScreen(tester, 'field-special');
            expect(error, isNull);
            expect(tester.takeException(), isNull);
            expect(engine.console.awaitingInput, isTrue);
            final actions = engine.console.actions
                .where((a) => a.enabled)
                .toList();
            final no = actions.where((a) => a.key == 'n').firstOrNull;
            final source =
                no ??
                actions
                    .where((a) => a.key == 'Escape' || a.key == 'Enter')
                    .firstOrNull;
            if (source != null && engine.console.eventMessage == null) {
              final direct = find.byKey(
                ValueKey('direct-action:${source.y}:${source.x}:${source.key}'),
              );
              final label =
                  source.intentLabel ??
                  source.label.replaceFirst(RegExp(r'^\S+\s+-\s*'), '').trim();
              final candidates = find.text(label, findRichText: true);
              final finder = direct.evaluate().isNotEmpty
                  ? direct
                  : candidates.first;
              expect(
                finder,
                findsOneWidget,
                reason: 'Source choice ${source.label} must render',
              );
              await tester.ensureVisible(finder);
              await tester.pumpAndSettle();
              await tester.tap(finder);
            } else {
              final continuation = find.text('Continue');
              expect(
                continuation,
                findsWidgets,
                reason: 'A real source report needs an operable Continue',
              );
              await tester.ensureVisible(continuation.first);
              await tester.tap(continuation.first);
            }
            await tester.pumpAndSettle();
          }
          expect(error, isNull);
          expect(
            done,
            isTrue,
            reason: '${scene.key} must resolve its refusal/report reader',
          );
          expect(tester.takeException(), isNull);
        } finally {
          // Refuse any reader left behind by a failed visual assertion.
          for (var i = 0; i < 35 && !done; i++) {
            if (engine.console.awaitingInput) {
              engine.console.sendInput(
                engine.console.actions.any((a) => a.key == 'n') ? 'n' : 'Enter',
              );
            }
            await tester.pump();
          }
          if (done) await flow;
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          journalReadingScale.value = 1;
        }
      });
    }
  }
}
