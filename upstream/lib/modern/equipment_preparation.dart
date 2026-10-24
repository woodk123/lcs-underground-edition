import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/modern/injury_status.dart';
import 'package:lcs_new_age/modern/squad_readiness.dart';

enum EquipmentFilter { all, weapons, outfits, ammo, other }

bool equipmentMatchesFilter(Item item, EquipmentFilter filter) =>
    switch (filter) {
      EquipmentFilter.all => true,
      EquipmentFilter.weapons => item is Weapon,
      EquipmentFilter.outfits => item is Clothing,
      EquipmentFilter.ammo => item is Ammo,
      EquipmentFilter.other =>
        item is! Weapon && item is! Clothing && item is! Ammo,
    };

String equipmentCondition(Clothing outfit) => [
  if (outfit.quality > outfit.type.qualityLevels) 'Tattered',
  if (outfit.bloody) 'Bloody' else 'Clean',
  if (outfit.damaged) 'Damaged' else 'Intact',
].join(' · ');

String equipmentStockSummary(Item item) => switch (item) {
  Weapon() =>
    item.type.usesAmmo
        ? 'Loaded: ${item.ammo} rounds'
        : item.type.thrown
        ? 'Thrown equipment'
        : 'No cartridge ammunition',
  Clothing() =>
    '${equipmentCondition(item)} · Quality ${item.quality} (1 is best)',
  Ammo() => '${item.stackSize} rounds · ${item.type.cartridge}',
  _ => item.type.isMoney ? '\$${item.stackSize} cash' : 'Stored item',
};

/// Read-only current values. No attack selection, skill roll, item cloning or
/// equipment handler is used to prepare these labels or comparisons.
class EquipmentLoadout {
  EquipmentLoadout(this.person, SquadReadiness readiness)
    : warnings = List.unmodifiable([
        if (person.equippedWeapon == null) 'No equipped weapon',
        if (person.weapon.type.usesAmmo && person.weapon.ammo == 0)
          'Weapon empty',
        if (person.spareAmmo is Ammo &&
            !person.weapon.acceptableAmmo.contains(person.spareAmmo!.type))
          'Spare ammunition does not fit this weapon',
        if (person.body.armok == 0) 'No functioning arms to wield a weapon',
        if (person.indecent) 'No outfit equipped',
        if (person.clothing.alarming) 'Alarming outfit',
        if (crewInjurySummary(person) case final injury?) injury.label,
        if (person.body.parts.any((part) => part.bleeding > 0) &&
            readiness.medicsFor(person).isEmpty)
          'No eligible First Aid helper',
      ]);

  final Creature person;
  final List<String> warnings;

  String get weaponName => person.weapon.type.name;
  String get skill =>
      '${person.weapon.skill.displayName} skill: ${person.weaponSkill} (base)';
  int get totalSkillLevels => person.rawSkill.values.fold(0, (a, b) => a + b);
  int get compatibleSpare =>
      person.weapon.acceptableAmmo.contains(person.spareAmmo?.type)
      ? person.spareAmmo?.stackSize ?? 0
      : 0;
  String get ammunition => person.weapon.type.usesAmmo
      ? 'Loaded: ${person.weapon.ammo} · Spare: $compatibleSpare rounds'
      : person.weapon.type.thrown
      ? 'Carried: ${person.weapon.stackSize} · Reserve: ${person.spareAmmo is Weapon && person.spareAmmo!.type == person.weapon.type ? person.spareAmmo!.stackSize : 0}'
      : person.spareAmmo is Weapon && (person.spareAmmo! as Weapon).type.thrown
      ? 'Thrown reserve: ${person.spareAmmo!.stackSize} ${person.spareAmmo!.type.name}'
      : 'No cartridge ammunition';
  String get outfitName => person.clothing.longName.replaceAll(' (d)', '');
  String get condition => equipmentCondition(person.clothing);
}

List<String> equipmentFacts(Item item, {Creature? person}) {
  if (item is Weapon) {
    return [
      if (person != null)
        '${item.skill.displayName} skill: ${person.rawSkill[item.skill] ?? 0} (base)',
      if (item.type.usesAmmo)
        'Loaded: ${item.ammo} rounds · Capacity: ${item.type.ammoCapacity}'
            '${item.type.canKeepOneInTheChamber ? ' + 1 chambered' : ''}'
      else if (item.type.thrown)
        'Carried: ${item.stackSize}'
      else
        'No cartridge ammunition',
      if (person != null && item.type.usesAmmo)
        'Compatible spare: ${item.acceptableAmmo.contains(person.spareAmmo?.type) ? person.spareAmmo?.stackSize ?? 0 : 0} rounds',
      'Weapon size: ${item.type.size}',
    ];
  }
  if (item is Clothing) {
    return [
      equipmentCondition(item),
      'Protection remaining: body ${item.bodyArmor}/${item.maxBodyArmor} · '
          'head ${item.headArmor}/${item.maxHeadArmor}',
      if (person != null)
        'Limb protection remaining: ${person.body.parts.where((part) => !part.weakSpot && !part.critical).map((part) => '${part.name} ${item.getLimbArmor(part)}/${item.maxLimbArmor}').join(' · ')}',
      'Outfit quality: ${item.quality} (1 is best)',
      'Conceals weapon sizes up to ${item.type.concealWeaponSize}',
      if (item.alarming) 'Alarming outfit',
    ];
  }
  if (item is Ammo) {
    return [
      '${item.stackSize} rounds · ${item.type.cartridge}',
      if (person != null)
        if (person.weapon.acceptableAmmo.contains(item.type))
          'Fits ${person.weapon.type.name}'
        else
          'Does not fit ${person.weapon.type.name}',
    ];
  }
  return ['${item.stackSize} in stock', 'This item is not a weapon or outfit.'];
}

Item? equipmentReplacedBy(Creature person, Item candidate) =>
    switch (candidate) {
      Weapon() => person.weapon,
      Clothing() => person.clothing,
      Ammo() => person.spareAmmo,
      _ => null,
    };
