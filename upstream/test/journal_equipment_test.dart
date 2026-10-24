import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/equipment_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/equipment_preparation.dart';
import 'package:lcs_new_age/modern/journal_equipment.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/squad_readiness.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'support/campaign_fixture.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _action(ConsoleAction action) =>
    _key('direct-action:${action.y}:${action.x}:${action.key}');

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _Reader {
  _Reader(List<Item> loot) {
    unawaited(equip(loot).whenComplete(() => finished = true));
  }
  bool finished = false;

  Future<void> stop(WidgetTester tester) async {
    for (var step = 0; step < 10 && !finished; step++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Escape');
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(finished, isTrue);
  }
}

Future<void> _mount(
  WidgetTester tester, {
  required _Reader reader,
  Size size = const Size(1440, 1000),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  journalReadingScale.value = scale;
  journalPresentation.value = JournalPreferenceValues(compact: scale > 1);
  addTearDown(() async {
    await reader.stop(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    journalReadingScale.value = 1;
    journalPresentation.value = const JournalPreferenceValues();
  });
  await tester.pumpWidget(const MainApp());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampaignFixture fixture;

  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
    final font = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      font.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await Future.wait([font.load(), serif.load()]);
  });

  setUp(() {
    fixture.restoreHeadquarters(console: Console());
    game.activeSquad!.members.removeRange(2, game.squad.length);
    game.activeSquadMember = game.squad[1];
  });

  for (final (size, scale) in [
    (const Size(1440, 1000), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    testWidgets('six-person loadout layout at ${size.width} / $scale', (
      tester,
    ) async {
      while (game.squad.length < 6) {
        addTestCrewMember(name: 'Preparation crew ${game.squad.length + 1}')
                .squad =
            game.activeSquad;
      }
      final stock = <Item>[
        Weapon('WEAPON_AK102'),
        Clothing('CLOTHING_CATSUIT'),
        Ammo('AMMO_556', stackSize: 90),
      ];
      final reader = _Reader(stock);
      await _mount(tester, reader: reader, size: size, scale: scale);
      expect(find.byType(JournalEquipmentView), findsOneWidget);
      expect(_key('equipment-readiness'), findsOneWidget);
      final loadouts = find.byKey(
        const PageStorageKey('equipment-loadout-scroll'),
      );
      expect(tester.getSize(loadouts).height, lessThanOrEqualTo(285));
      expect(find.textContaining('Filter this page'), findsOneWidget);
      expect(find.textContaining('22/7'), findsNothing);
      expect(find.textContaining('30/8'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'browsing, comparison, filters and details preserve campaign, reader and RNG',
    (tester) async {
      final candidate = Weapon('WEAPON_AK102');
      final stock = <Item>[
        candidate,
        Clothing('CLOTHING_CATSUIT'),
        Ammo('AMMO_556', stackSize: 90),
      ];
      final reader = _Reader(stock);
      await _mount(tester, reader: reader);
      final frame = equipmentContext(engine.console)!;
      final revision = engine.console.revision.value;
      final actions = List.of(engine.console.actions);
      final before = campaignSnapshot();
      final inventory = jsonEncode(stock.map((item) => item.toJson()).toList());
      reseedRNG(seed: 92581);
      final expectedRolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 92581);

      final person = game.squad[1];
      await _tap(tester, _key('equipment-person:${person.id}'));
      expect(
        tester.widget<Text>(_key('equipment-selected-person')).data,
        person.name,
      );
      final choice = frame.stock.singleWhere(
        (choice) => identical(choice.item, candidate),
      );
      expect(
        tester.widget<Semantics>(_action(choice.action)).properties.label,
        'Equip ${candidate.type.name}, shortcut ${choice.action.key.toUpperCase()}',
      );
      await _tap(tester, _key('equipment-stock:${choice.action.key}'));
      expect(_key('equipment-compare'), findsOneWidget);
      expect(find.text('Compare equipment for ${person.name}'), findsOneWidget);
      await _tap(tester, find.text('Equipment details'));
      await _tap(tester, find.text('Equipment details'));
      await _tap(tester, find.text('Preparation details'));
      await _tap(tester, find.text('Preparation details'));
      await _tap(tester, _key('equipment-filter:outfits'));
      expect(_key('equipment-stock:${choice.action.key}'), findsNothing);
      await _tap(tester, _key('equipment-filter:all'));
      await tester.ensureVisible(_key('equipment-search'));
      await tester.enterText(_key('equipment-search'), 'unfindable');
      await tester.pumpAndSettle();
      expect(find.textContaining('No matches on this page'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.pump();
      expect(
        equipmentContext(engine.console),
        same(frame),
        reason: 'A focused filter must own typing.',
      );
      await tester.enterText(_key('equipment-search'), '');
      await tester.pumpAndSettle();

      expect(campaignSnapshot(), before);
      expect(
        jsonEncode(stock.map((item) => item.toJson()).toList()),
        inventory,
      );
      expect(engine.console.revision.value, revision);
      expect(engine.console.actions, orderedEquals(actions));
      expect(engine.console.lastKey, isNull);
      expect(List.generate(12, (_) => lcsRandom(100000)), expectedRolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview Apply uses original recipient, cancel is neutral, stale Apply cannot reach a later reader',
    (tester) async {
      final candidate = Clothing('CLOTHING_CATSUIT');
      final stock = <Item>[candidate];
      final reader = _Reader(stock);
      await _mount(
        tester,
        reader: reader,
        size: const Size(1024, 720),
        scale: 1.5,
      );
      final original = equipmentContext(engine.console)!;
      final key = original.stock.single.action.key;
      final before = campaignSnapshot();
      final beforeStock = jsonEncode(
        stock.map((item) => item.toJson()).toList(),
      );
      await _tap(tester, _key('equipment-stock:$key'));
      final apply = _key('equipment-apply:$key');
      final retained = tester.widget<OutlinedButton>(
        find.descendant(of: apply, matching: find.byType(OutlinedButton)),
      );
      await _tap(tester, apply);
      final recipient = equipmentContext(engine.console)!;
      expect(recipient.phase, EquipmentPhase.giveItem);
      expect(recipient.pendingItem, same(candidate));
      expect(engine.console.actions.map((action) => action.key), [
        '1',
        '2',
        'Enter',
      ]);
      expect(engine.console.navigation, isNull);
      for (final action in recipient.actions) {
        expect(
          _action(action).hitTestable(),
          findsOneWidget,
          reason: '${action.key} must be visible on recipient entry',
        );
      }
      await _tap(tester, _action(recipient.actions.last));
      expect(campaignSnapshot(), before);
      expect(
        jsonEncode(stock.map((item) => item.toJson()).toList()),
        beforeStock,
      );
      retained.onPressed!();
      await tester.pumpAndSettle();
      expect(equipmentContext(engine.console)!.phase, EquipmentPhase.inventory);
      expect(engine.console.lastKey, isNull);
      expect(campaignSnapshot(), before);

      final current = equipmentContext(engine.console)!;
      await _tap(tester, _action(current.stock.single.action));
      final receiving = equipmentContext(engine.console)!;
      final target = receiving.actions.singleWhere(
        (action) => action.entityId == game.squad[1].id.toString(),
      );
      final firstOutfit = game.squad.first.equippedClothing;
      final selected = game.activeSquadMember;
      await _tap(tester, _action(target));
      expect(game.squad.first.equippedClothing, same(firstOutfit));
      expect(game.squad[1].clothing.typeName, candidate.typeName);
      expect(game.activeSquadMember, same(selected));
      expect(stock, isNot(contains(candidate)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source paging retains exact letters and filtering cannot renumber stock',
    (tester) async {
      final stock = <Item>[
        for (final type in weaponTypes.values.take(23)) Weapon(type.idName),
      ];
      final reader = _Reader(stock);
      await _mount(tester, reader: reader);
      final first = equipmentContext(engine.console)!;
      final before = campaignSnapshot();
      final inventory = jsonEncode(stock.map((item) => item.toJson()).toList());
      expect(first.stock, hasLength(18));
      final next = first.actions.singleWhere(
        (action) => action.key == 'PageDown',
      );
      await _tap(tester, _action(next));
      final second = equipmentContext(engine.console)!;
      expect(second.page, 1);
      expect(second.stock.first.action.key, 'a');
      expect(second.stock.first.action.entityId, '18');
      expect(second.stock.first.item, same(stock[18]));
      final choice = second.stock.last;
      final secondActions = List.of(engine.console.actions);
      await tester.ensureVisible(_key('equipment-search'));
      await tester.enterText(_key('equipment-search'), choice.item.type.name);
      await tester.pumpAndSettle();
      expect(_key('equipment-stock:${choice.action.key}'), findsOneWidget);
      expect(equipmentContext(engine.console), same(second));
      expect(engine.console.actions, orderedEquals(secondActions));
      expect(campaignSnapshot(), before);
      expect(
        jsonEncode(stock.map((item) => item.toJson()).toList()),
        inventory,
      );
      await _tap(
        tester,
        _action(second.actions.singleWhere((action) => action.key == 'PageUp')),
      );
      expect(equipmentContext(engine.console)!.page, 0);
      expect(
        equipmentContext(engine.console)!.stock.first.item,
        same(stock.first),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsupported stock stays inspectable without promising an equip action',
    (tester) async {
      final other = Item('LOOT_COMPUTER');
      final unsupportedAmmo = Ammo('AMMO_BUCKSHOT', stackSize: 12);
      final stock = <Item>[other, unsupportedAmmo, Weapon('WEAPON_AK102')];
      final reader = _Reader(stock);
      await _mount(tester, reader: reader);
      final frame = equipmentContext(engine.console)!;
      final before = campaignSnapshot();
      final inventory = jsonEncode(stock.map((item) => item.toJson()).toList());
      final actions = List.of(engine.console.actions);
      final revision = engine.console.revision.value;
      reseedRNG(seed: 50291);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 50291);
      for (final item in [other, unsupportedAmmo]) {
        final choice = frame.stock.singleWhere(
          (choice) => identical(choice.item, item),
        );
        expect(choice.canEquip, isFalse);
        expect(
          choice.action.enabled,
          isTrue,
          reason: 'Original invalid keyboard choices remain authored.',
        );
        await _tap(tester, _key('equipment-stock:${choice.action.key}'));
        expect(
          tester.widget<Semantics>(_action(choice.action)).properties.enabled,
          isFalse,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.descendant(
                  of: _action(choice.action),
                  matching: find.byType(OutlinedButton),
                ),
              )
              .onPressed,
          isNull,
        );
        expect(_key('equipment-apply:${choice.action.key}'), findsNothing);
        expect(
          find.text('This item cannot be equipped by the current squad.'),
          findsOneWidget,
        );
      }
      expect(equipmentContext(engine.console), same(frame));
      expect(engine.console.actions, orderedEquals(actions));
      expect(engine.console.revision.value, revision);
      expect(campaignSnapshot(), before);
      expect(
        jsonEncode(stock.map((item) => item.toJson()).toList()),
        inventory,
      );
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);

      final invalid = frame.stock.singleWhere(
        (choice) => identical(choice.item, other),
      );
      engine.console.sendInput(invalid.action.key);
      await tester.pumpAndSettle();
      expect(equipmentContext(engine.console)!.notice, "You can't equip that.");
      expect(find.text("You can't equip that."), findsOneWidget);
      expect(campaignSnapshot(), before);
      expect(
        jsonEncode(stock.map((item) => item.toJson()).toList()),
        inventory,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ammo controls retain recipient ownership and amount entry uses the source text reader',
    (tester) async {
      final receiver = game.squad.first;
      final other = game.squad[1];
      receiver.equippedWeapon = Weapon('WEAPON_AK102')..ammo = 7;
      receiver.spareAmmo = null;
      final selected = game.activeSquadMember;
      final stock = <Item>[Ammo('AMMO_556', stackSize: 120)];
      final reader = _Reader(stock);
      await _mount(
        tester,
        reader: reader,
        size: const Size(1024, 720),
        scale: 1.5,
      );
      final before = campaignSnapshot();
      final otherBefore = jsonEncode(other.toJson());

      Future<void> allocation(String key, EquipmentPhase phase) async {
        final action = equipmentContext(engine.console)!.actions
            .singleWhere((action) => action.key == key);
        await _tap(tester, _action(action));
        final recipients = equipmentContext(engine.console)!;
        expect(recipients.phase, phase);
        final target = recipients.actions.singleWhere(
          (action) => action.entityId == receiver.id.toString(),
        );
        await _tap(tester, _action(target));
      }

      await allocation('Up', EquipmentPhase.increaseAmmo);
      expect(receiver.spareAmmo!.stackSize, 30);
      expect(receiver.weapon.ammo, 7);
      expect(stock.single.stackSize, 90);
      expect(jsonEncode(other.toJson()), otherBefore);
      expect(game.activeSquadMember, same(selected));
      await allocation('Down', EquipmentPhase.decreaseAmmo);
      expect(receiver.spareAmmo, isNull);
      expect(stock.single.stackSize, 120);
      expect(campaignSnapshot(), before);

      final ammunition = equipmentContext(engine.console)!.stock.single;
      await _tap(tester, _action(ammunition.action));
      final recipients = equipmentContext(engine.console)!;
      await _tap(
        tester,
        _action(
          recipients.actions.singleWhere(
            (action) => action.entityId == receiver.id.toString(),
          ),
        ),
      );
      expect(engine.console.textInput, isTrue);
      expect(equipmentContext(engine.console), isNull);
      expect(find.byType(JournalEquipmentView), findsNothing);
      expect(engine.console.actions.single.label, 'Confirm amount');
      await tester.enterText(find.byType(TextField), '12');
      await _tap(tester, find.text('Confirm text'));
      expect(equipmentContext(engine.console)!.phase, EquipmentPhase.inventory);
      expect(receiver.spareAmmo!.stackSize, 12);
      expect(receiver.weapon.ammo, 7);
      expect(stock.single.stackSize, 108);
      expect(jsonEncode(other.toJson()), otherBefore);
      expect(game.activeSquadMember, same(selected));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'page browsing restores on revisit and stays separate from another campaign',
    (tester) async {
      final stock = <Item>[
        Weapon('WEAPON_AK102'),
        Clothing('CLOTHING_CATSUIT'),
      ];
      final first = _Reader(stock);
      await _mount(tester, reader: first);
      await _tap(tester, _key('equipment-filter:weapons'));
      await tester.ensureVisible(_key('equipment-search'));
      await tester.enterText(_key('equipment-search'), 'AK-102');
      await tester.pumpAndSettle();
      final weapon = equipmentContext(engine.console)!.stock
          .singleWhere((choice) => choice.item is Weapon);
      await _tap(tester, _key('equipment-stock:${weapon.action.key}'));
      await _tap(
        tester,
        _action(
          equipmentContext(engine.console)!.actions
              .singleWhere((action) => action.key == 'Enter'),
        ),
      );
      expect(first.finished, isTrue);
      await tester.pumpAndSettle();

      final second = _Reader(stock);
      addTearDown(() => second.stop(tester));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_key('equipment-search')).controller!.text,
        'AK-102',
      );
      expect(
        tester.widget<ChoiceChip>(_key('equipment-filter:weapons')).selected,
        isTrue,
      );
      expect(_key('equipment-compare'), findsOneWidget);
      await _tap(
        tester,
        _action(
          equipmentContext(engine.console)!.actions
              .singleWhere((action) => action.key == 'Enter'),
        ),
      );
      expect(second.finished, isTrue);
      await tester.pumpAndSettle();

      final oldCampaign = game.gameState.uniqueGameId;
      fixture.restoreHeadquarters(console: engine.console);
      game.gameState.uniqueGameId = oldCampaign + 1;
      final third = _Reader(<Item>[Weapon('WEAPON_AK102')]);
      addTearDown(() => third.stop(tester));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_key('equipment-search')).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<ChoiceChip>(_key('equipment-filter:all')).selected,
        isTrue,
      );
      expect(_key('equipment-compare'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('loadout labels separate base skill, compatible rounds, thrown reserves and real armor condition', () {
    final person = game.squad.first;
    person.equippedWeapon = Weapon('WEAPON_AK102')..ammo = 7;
    person.spareAmmo = Ammo('AMMO_556', stackSize: 60);
    final readiness = SquadReadiness(game.squad);
    final loadout = EquipmentLoadout(person, readiness);
    expect(loadout.skill, contains('skill: ${person.weaponSkill} (base)'));
    expect(loadout.ammunition, 'Loaded: 7 · Spare: 60 rounds');
    expect(
      loadout.totalSkillLevels,
      person.rawSkill.values.fold<int>(0, (a, b) => a + b),
    );
    final thrownType = weaponTypes.values.firstWhere((type) => type.thrown);
    person.equippedWeapon = Weapon(thrownType.idName, stackSize: 1);
    person.spareAmmo = Weapon(thrownType.idName, stackSize: 4);
    final thrown = EquipmentLoadout(person, readiness);
    expect(thrown.ammunition, 'Carried: 1 · Reserve: 4');
    expect(
      thrown.warnings,
      isNot(contains('Spare ammunition does not fit this weapon')),
    );
    person.equippedWeapon = null;
    expect(
      EquipmentLoadout(person, readiness).ammunition,
      contains('Thrown reserve: 4'),
    );
    final outfit = Clothing('CLOTHING_SWATARMOR')..bloody = true;
    final limb = person.body.parts.firstWhere(
      (part) => !part.weakSpot && !part.critical,
    );
    outfit.setLimbArmor(limb, 2);
    outfit.bodyArmor = 3;
    outfit.headArmor = 1;
    expect(equipmentCondition(outfit), contains('Bloody'));
    expect(equipmentCondition(outfit), contains('Damaged'));
    final facts = equipmentFacts(outfit, person: person).join('\n');
    expect(facts, contains('body 3/${outfit.maxBodyArmor}'));
    expect(facts, contains('head 1/${outfit.maxHeadArmor}'));
    expect(facts, contains('${limb.name} 2/${outfit.maxLimbArmor}'));
  });
}
