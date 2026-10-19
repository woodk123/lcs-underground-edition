import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

class ModalRun<T> {
  ModalRun(this.result, this.actions);
  final T result;
  final List<List<ConsoleAction>> actions;
}

Future<ModalRun<T>> choose<T>(
  Future<T> Function() operation,
  List<String> keys,
) async {
  final console = engine.console;
  final prompts = <List<ConsoleAction>>[];
  final failed = Completer<T>();
  var index = 0;
  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    prompts.add(List.of(console.actions));
    if (index >= keys.length) {
      if (!failed.isCompleted) {
        failed.completeError(
          StateError('Unexpected modal prompt after $index choices'),
        );
      }
      return;
    }
    console.sendInput(keys[index++]);
  }

  console.revision.addListener(respond);
  try {
    final result = await Future.any([
      operation(),
      failed.future,
    ]).timeout(const Duration(seconds: 5));
    expect(index, keys.length);
    return ModalRun(result, prompts);
  } finally {
    console.revision.removeListener(respond);
  }
}

void expectMembersOnly(List<ConsoleAction> actions, List<String> names) {
  expect(actions.map((action) => action.key), ['1', '2', 'Enter']);
  expect(
    actions.map(
      (action) => action.label.replaceFirst(RegExp(r'^(\d|Enter) - '), ''),
    ),
    [...names, 'Cancel'],
  );
  expect(actions.every((action) => action.enabled), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    final save = SaveFile.fromJson(
      jsonDecode(await File('test/saves/felix_1_0.json').readAsString())
          as Map<String, dynamic>,
    );
    game.gameState = game.GameState.fromJson(save.saveData);
    applyBugFixes(save.version);
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    game.activeSquad!.members.removeRange(2, game.squad.length);
  });

  test(
    'ammo allocation presents only recipient choices and equips member two',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      final receiver = game.squad[1];
      receiver.giveWeapon(Weapon('WEAPON_9MM_HANDGUN'));
      receiver.spareAmmo = null;
      final firstAmmo = game.squad.first.spareAmmo?.stackSize;
      final capacity = receiver.weapon.type.ammoCapacity;
      final loot = <Item>[Ammo('AMMO_9MM', stackSize: capacity * 3)];
      final run = await choose(() => equip(loot), ['Up', '2', 'Enter']);
      expectMembersOnly(run.actions[1], names);
      expect(receiver.spareAmmo?.stackSize, capacity);
      expect(game.squad.first.spareAmmo?.stackSize, firstAmmo);
      expect(loot.single.stackSize, capacity * 2);
    },
  );

  test(
    'dropping ammo uses the chosen member and returns exactly one magazine',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      final receiver = game.squad[1];
      receiver.giveWeapon(Weapon('WEAPON_9MM_HANDGUN'));
      final capacity = receiver.weapon.type.ammoCapacity;
      receiver.spareAmmo = Ammo('AMMO_9MM', stackSize: capacity * 2);
      final loot = <Item>[];
      final run = await choose(() => equip(loot), ['Down', '2', 'Enter']);
      expectMembersOnly(run.actions[1], names);
      expect(receiver.spareAmmo?.stackSize, capacity);
      expect(loot.single, isA<Ammo>());
      expect(loot.single.stackSize, capacity);
    },
  );

  test(
    'strip selection replaces inventory actions and only strips member two',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      final first = game.squad.first.clothing.type;
      final second = game.squad[1].clothing.type;
      final loot = <Item>[];
      final run = await choose(() => equip(loot), ['s', '2', 'Enter']);
      expectMembersOnly(run.actions[1], names);
      expect(game.squad.first.clothing.type, first);
      expect(game.squad[1].equippedClothing, isNull);
      expect(loot.whereType<Clothing>().single.type, second);
    },
  );

  test(
    'canceling an equipment recipient leaves the outfit and inventory intact',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      final outfits = game.squad.map((person) => person.clothing.type).toList();
      final outfit = Clothing('CLOTHING_CATSUIT');
      final loot = <Item>[outfit];
      final run = await choose(() => equip(loot), ['a', 'Enter', 'Enter']);
      expectMembersOnly(run.actions[1], names);
      expect(game.squad.map((person) => person.clothing.type), outfits);
      expect(loot, [outfit]);
    },
  );

  for (final (key, driver) in [('A', true), ('a', false)]) {
    test(
      'vehicle $key selection offers only members and preserves driver=$driver',
      () async {
        final names = game.squad.map((person) => person.name).toList();
        final car = Vehicle(vehicleTypes.keys.first);
        game.vehiclePool.add(car);
        final previous = game.squad.first.preferredCarId;
        final run = await choose(setVehicles, [key, '2', 'Enter']);
        expectMembersOnly(run.actions[1], names);
        expect(game.squad[1].preferredCarId, car.id);
        expect(game.squad[1].preferredDriver, driver);
        expect(game.squad.first.preferredCarId, previous);
      },
    );
  }

  test(
    'canceling a vehicle recipient does not assign a driver or passenger',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      game.vehiclePool.add(Vehicle(vehicleTypes.keys.first));
      final preferences = game.squad
          .map((person) => (person.preferredCarId, person.preferredDriver))
          .toList();
      final run = await choose(setVehicles, ['A', 'Enter', 'Enter']);
      expectMembersOnly(run.actions[1], names);
      expect(
        game.squad.map(
          (person) => (person.preferredCarId, person.preferredDriver),
        ),
        preferences,
      );
    },
  );

  test(
    'reorder prompts expose current members and preserve the original swap',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      final ids = game.squad.map((person) => person.id).toList();
      engine.addOptionText(19, 1, 'a', 'A - Old inventory action');
      final run = await choose(orderparty, ['1', '2', 'Enter']);
      expectMembersOnly(run.actions[0], names);
      expectMembersOnly(run.actions[1], names);
      expectMembersOnly(run.actions[2], names.reversed.toList());
      expect(game.squad.map((person) => person.id), ids.reversed);
    },
  );

  test(
    'canceling the second reorder prompt leaves the squad order unchanged',
    () async {
      final names = game.squad.map((person) => person.name).toList();
      final ids = game.squad.map((person) => person.id).toList();
      final run = await choose(orderparty, ['1', 'Enter']);
      expectMembersOnly(run.actions[0], names);
      expectMembersOnly(run.actions[1], names);
      expect(game.squad.map((person) => person.id), ids);
    },
  );

  test(
    'amount entry removes old item actions and confirms the typed quantity',
    () async {
      engine.addOptionText(19, 1, 'a', 'A - Old inventory action');
      final run = await choose(() => promptAmount(0, 20), ['3', 'Enter']);
      expect(run.result, 3);
      for (final actions in run.actions) {
        expect(actions.map((action) => action.key), ['Enter']);
        expect(actions.single.label, 'Confirm amount');
      }
    },
  );
}
