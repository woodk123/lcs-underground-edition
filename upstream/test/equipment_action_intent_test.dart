import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

Finder intentControl(ConsoleAction action) =>
    find.byKey(ValueKey('direct-action:${action.y}:${action.x}:${action.key}'));

Future<void> mountIntentFlow(
  WidgetTester tester,
  Future<void> operation, {
  Size size = const Size(1280, 800),
}) async {
  var completed = false;
  unawaited(operation.then((_) => completed = true));
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    for (var i = 0; i < 8 && !completed; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Enter');
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const MainApp());
  await tester.pumpAndSettle();
}

void expectVisibleIntent(
  WidgetTester tester,
  ConsoleAction action,
  String actor,
  String intent,
) {
  expect(action.label, contains(actor));
  expect(action.intentLabel, intent);
  final control = intentControl(action);
  expect(control, findsOneWidget);
  expect(
    find.descendant(of: control, matching: find.text(intent)),
    findsOneWidget,
  );
  final accessible = tester.widget<Semantics>(control).properties.label!;
  expect(accessible, contains(actor));
  expect(accessible, contains(intent));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureGameDataLoaded();
    final modern = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      modern.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    final original = FontLoader('SourceCodePro')
      ..addFont(rootBundle.load('fonts/SourceCodePro-Regular.ttf'));
    await Future.wait([modern.load(), original.load()]);
  });
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.mode = GameMode.base;
    game.activeSquad!.members.removeRange(2, game.squad.length);
    game.activeSquadMember = game.squad[1];
  });

  testWidgets(
    'numbered equipment row declares unequip and drops that actor weapon',
    (tester) async {
      final first = game.squad[0];
      final second = game.squad[1];
      final selected = game.activeSquadMember;
      final weapon = Weapon('WEAPON_9MM_HANDGUN');
      first.giveWeapon(weapon);
      first.spareAmmo = Ammo('AMMO_9MM', stackSize: 15);
      second.giveWeapon(Weapon('WEAPON_DESERT_EAGLE'));
      final secondWeapon = second.equippedWeapon;
      final clothing = first.equippedClothing;
      final loot = <Item>[];
      // The wide overview exposes both numbered rows together. Narrow views
      // keep these original actions behind the selected crew's loadout.
      await mountIntentFlow(tester, equip(loot), size: const Size(2200, 1200));
      final firstAction = engine.console.actions.singleWhere(
        (action) => action.key == '1',
      );
      final secondAction = engine.console.actions.singleWhere(
        (action) => action.key == '2',
      );
      expectVisibleIntent(tester, firstAction, first.name, 'Unequip weapon');
      expectVisibleIntent(tester, secondAction, second.name, 'Unequip weapon');
      expect([firstAction.key, secondAction.key], ['1', '2']);
      await tester.tap(intentControl(firstAction));
      await tester.pumpAndSettle();
      expect(first.equippedWeapon, isNull);
      expect(first.spareAmmo, isNull);
      expect(loot, contains(weapon));
      expect(loot.whereType<Ammo>().single.stackSize, 15);
      expect(first.equippedClothing, same(clothing));
      expect(second.equippedWeapon, same(secondWeapon));
      expect(game.activeSquadMember, same(selected));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'numbered vehicle row declares removal and clears only that actor preference',
    (tester) async {
      final first = game.squad[0];
      final second = game.squad[1];
      final selected = game.activeSquadMember;
      final car = Vehicle(vehicleTypes.keys.first);
      game.vehiclePool.add(car);
      first.preferredCarId = car.id;
      first.preferredDriver = false;
      second.preferredCarId = car.id;
      second.preferredDriver = true;
      await mountIntentFlow(tester, setVehicles());
      final firstAction = engine.console.actions.singleWhere(
        (action) => action.key == '1',
      );
      final secondAction = engine.console.actions.singleWhere(
        (action) => action.key == '2',
      );
      expectVisibleIntent(tester, firstAction, first.name, 'Remove vehicle');
      expectVisibleIntent(tester, secondAction, second.name, 'Remove vehicle');
      expect([firstAction.key, secondAction.key], ['1', '2']);
      await tester.tap(intentControl(secondAction));
      await tester.pumpAndSettle();
      expect(second.preferredCarId, isNull);
      expect(second.preferredDriver, isFalse);
      expect(first.preferredCarId, car.id);
      expect(first.preferredDriver, isFalse);
      expect(game.activeSquadMember, same(selected));
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'recipient selection keeps actor names without inheriting unequip intents',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      final selected = game.activeSquadMember;
      final loot = <Item>[Clothing('CLOTHING_CATSUIT')];
      final console = engine.console;
      List<ConsoleAction>? recipients;
      var step = 0;
      void respond() {
        if (!console.awaitingInput || console.lastKey != null) return;
        if (step == 0) {
          expect(
            console.actions.where(
              (action) => action.intentLabel == 'Unequip weapon',
            ),
            hasLength(2),
          );
          step++;
          console.sendInput('a');
        } else if (step == 1) {
          recipients = List.of(console.actions);
          step++;
          console.sendInput('2');
        } else {
          console.sendInput('Enter');
        }
      }

      console.revision.addListener(respond);
      try {
        await equip(loot).timeout(const Duration(seconds: 5));
      } finally {
        console.revision.removeListener(respond);
      }
      expect(recipients!.map((action) => action.key), ['1', '2', 'Enter']);
      expect(recipients!.map((action) => action.label), [...names, 'Cancel']);
      expect(recipients!.every((action) => action.intentLabel == null), isTrue);
      expect(game.squad[1].clothing.typeName, 'CLOTHING_CATSUIT');
      expect(game.activeSquadMember, same(selected));
    },
  );
}
