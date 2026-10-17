import 'package:flutter/material.dart';
import 'package:lcs_new_age/items/ammo_type.dart';
import 'package:lcs_new_age/items/armor_upgrade.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/item_type.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

String _signed(int value) => value >= 0 ? '+$value' : '$value';

/// Describes catalogue defaults, or the specified armor on an equipped outfit.
String equipmentHelp(ItemType type, {ArmorUpgrade? armor}) {
  final lines = <String>[type.name];
  if (type is WeaponType) {
    if (type.description?.isNotEmpty == true) lines.add(type.description!);
    for (final attack in type.attacks) {
      final mode = attack.socialDamage
          ? 'Social attack'
          : attack.thrown
          ? 'Thrown attack'
          : attack.ranged
          ? 'Ranged attack'
          : 'Melee attack';
      lines.add('$mode · ${attack.skill.displayName}');
      lines.add(
        [
          if (!attack.usesAmmo) 'Base damage ${attack.damage}',
          'Accuracy ${_signed(attack.accuracyBonus)}',
          if (attack.numberOfAttacks > 1)
            'Up to ${attack.numberOfAttacks} hits',
          if (attack.canBackstab) 'Can sneak attack',
          if (attack.bleeds) 'Can cause bleeding',
          if (attack.stuns) 'Can stun',
          if (attack.fire != null) 'Can start fires',
        ].join(' · '),
      );
    }
    if (type.usesAmmo) {
      lines.add(
        'Capacity: ${type.ammoCapacity} rounds'
        '${type.canKeepOneInTheChamber ? ' + 1 in the chamber' : ''}.',
      );
      lines.add(
        'Ammunition: ${type.acceptableAmmo.map((a) => a.name).join(', ')}.',
      );
    }
    lines.add(
      'Size ${type.size} · ${type.suspicious ? 'Suspicious when visible' : 'Not inherently suspicious'}.',
    );
    if (type.canGraffiti) lines.add('Can be used for graffiti.');
    if (type.autoBreakLock) {
      lines.add('Can pry open doors that allow forced entry.');
    }
    if (type.instrument) lines.add('Instrument for music fundraising.');
    if (type.canTakeHostages) lines.add('Can take hostages quietly.');
    lines.add(
      'Damage and hit chances also depend on the user, target and ammunition.',
    );
  } else if (type is ClothingType) {
    if (type.description.isNotEmpty) lines.add(type.description);
    final protection = armor ?? type.intrinsicArmor;
    if (protection != null) {
      lines.add(
        '${protection.name} base protection: body ${protection.bodyArmor}, head ${protection.headArmor}, limbs ${protection.limbArmor}.',
      );
      lines.add(
        'Dodge penalty ${protection.dodgePenalty} · Accuracy penalty ${protection.accuracyPenalty}.',
      );
      if (protection.fireResistant) lines.add('Fire resistant.');
    } else {
      lines.add('No built-in armor.');
    }
    final traits = type.traitsList(false, specifiedArmorUpgrade: protection);
    if (traits.isNotEmpty) lines.add('Traits: ${traits.join(', ')}.');
    lines.add('Conceals weapons up to size ${type.concealWeaponSize}.');
    if (type.alarming) lines.add('Alarming outfit: can attract attention.');
    lines.add(
      'Disguise suitability depends on the location. Condition and armor upgrades can change effectiveness.',
    );
  } else if (type is AmmoType) {
    lines.add('${type.boxSize} rounds per box · Cartridge: ${type.cartridge}.');
    lines.add(
      'Base damage ${type.damage} · Recoil ${type.recoil}'
      '${type.multihit > 1 ? ' · ${type.multihit} projectiles' : ''}.',
    );
    final compatible = weaponTypes.values
        .where((weapon) => weapon.acceptableCartridge.contains(type.cartridge))
        .map((weapon) => weapon.name);
    if (compatible.isNotEmpty) lines.add('Fits: ${compatible.join(', ')}.');
  } else {
    lines.add('Resale value: \$${type.fenceValue.toStringAsFixed(0)}.');
  }
  return lines.join('\n');
}

class EquipmentTooltip extends StatelessWidget {
  const EquipmentTooltip({
    super.key,
    required this.type,
    required this.child,
    this.armor,
  });

  final ItemType? type;
  final ArmorUpgrade? armor;
  final Widget child;

  @override
  Widget build(BuildContext context) => type == null
      ? child
      : MechanicsTooltip(
          message: equipmentHelp(type!, armor: armor),
          child: child,
        );
}
