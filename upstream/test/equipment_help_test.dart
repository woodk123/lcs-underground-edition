import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/items/armor_upgrade.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/item_type.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/modern/equipment_help.dart';
import 'package:lcs_new_age/sitemode/shop.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);

  test('every shop item has help generated from its loaded definition', () {
    void check(Shop shop) {
      for (final item in shop.items) {
        final type = itemTypes[item.itemId];
        expect(type, isNotNull, reason: item.itemId);
        expect(equipmentHelp(type!), startsWith(type.name));
      }
      shop.departments.forEach(check);
    }

    shopTypes.values.forEach(check);
    final dagger = weaponTypes['WEAPON_DAGGER']!;
    final help = equipmentHelp(dagger);
    expect(help, contains(dagger.attack!.skill.displayName));
    expect(help, contains('Base damage ${dagger.attack!.damage}'));
    expect(help, contains('Can sneak attack'));
  });

  test('equipped armor overrides catalogue protection', () {
    final outfit = clothingTypes.values.first;
    final upgrade = armorUpgrades.values.firstWhere((a) => a.bodyArmor > 0);
    final help = equipmentHelp(outfit, armor: upgrade);
    expect(
      help,
      contains('${upgrade.name} base protection: body ${upgrade.bodyArmor}'),
    );
    expect(
      help,
      contains('Conceals weapons up to size ${outfit.concealWeaponSize}'),
    );
  });

  testWidgets('equipment help appears on hover and on long press', (
    tester,
  ) async {
    final type = weaponTypes['WEAPON_DAGGER']!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: EquipmentTooltip(
              type: type,
              child: const Text('Dagger stock row'),
            ),
          ),
        ),
      ),
    );
    final row = find.text('Dagger stock row');
    final message = equipmentHelp(type);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text(message), findsNothing);
    await tester.longPress(row);
    await tester.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });
}
