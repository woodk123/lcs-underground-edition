import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/item_help_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  test(
    'all decision previews preserve the complete campaign and random stream',
    () {
      final actor = game.pool.first;
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 83927);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 83927);
      for (final topic in DecisionTopic.values) {
        expect(
          decisionDetails(topic, actor: actor, site: actor.base),
          isNotEmpty,
        );
      }
      for (final weapon in weaponTypes.values) {
        expect(weaponHelp(weapon, actor: actor), isNotEmpty);
        if (weapon.usesAmmo) {
          expect(
            weaponHelp(weapon, actor: actor),
            contains('damage comes from the loaded ammunition'),
          );
        }
      }
      for (final clothing in clothingTypes.values) {
        expect(clothingHelp(clothing, actor: actor), contains('Coverage:'));
      }
      for (final vehicle in vehicleTypes.values) {
        expect(vehicleHelp(vehicle, actor: actor), contains('driving bonus'));
      }
      for (final upgrade in CompoundUpgrade.values) {
        expect(
          compoundUpgradeHelp(upgrade, actor.base),
          contains('\$${upgrade.price}'),
        );
      }
      expect(
        recruitmentComparison(actor, game.pool[1]),
        contains('not the chance of joining'),
      );
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
    },
  );

  testWidgets(
    'inspecting an equipment choice does not dispatch its equip action',
    (tester) async {
      final actor = game.pool.first;
      final item = actor.equippedWeapon!;
      engine.addOptionText(10, 1, 'a', 'A - ${item.type.name}');
      describeChoiceItem(engine.console, 'a', item);
      final reader = engine.console.getkey();
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: Scaffold(
            body: DirectContent(console: engine.console, onAction: sent.add),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = jsonEncode(game.gameState.toJson());
      await tester.tap(find.byTooltip('Inspect ${item.type.name}'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Selected weapon'), findsOneWidget);
      expect(sent, isEmpty);
      expect(engine.console.awaitingInput, isTrue);
      expect(jsonEncode(game.gameState.toJson()), before);
      await tester.tap(find.byTooltip('Close decision guide'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      engine.console.sendInput('Enter');
      await tester.pump();
      await reader;
    },
  );

  for (final size in [
    const Size(1280, 720),
    const Size(800, 600),
    const Size(360, 640),
  ]) {
    testWidgets(
      'all guides fit and leave game input untouched at $size / 150%',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final reader = engine.console.getkey();
        final before = jsonEncode(game.gameState.toJson());
        for (final topic in DecisionTopic.values) {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildJournalTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(
                body: Center(
                  child: DecisionGuideButton(
                    topic: topic,
                    actor: game.pool.first,
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.byType(TextButton));
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsOneWidget);
          expect(
            find.byTooltip('Close decision guide').hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          expect(engine.console.awaitingInput, isTrue);
          expect(jsonEncode(game.gameState.toJson()), before);
          await tester.tap(find.byTooltip('Close decision guide'));
          await tester.pumpAndSettle();
        }
        engine.console.sendInput('Enter');
        await tester.pump();
        await reader;
      },
    );
  }
}
