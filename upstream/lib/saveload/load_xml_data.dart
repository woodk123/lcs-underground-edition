import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/creature_type_xml.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/items/ammo_type.dart';
import 'package:lcs_new_age/items/ammo_type_xml.dart';
import 'package:lcs_new_age/items/armor_upgrade.dart';
import 'package:lcs_new_age/items/armor_upgrade_xml.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/clothing_type_xml.dart';
import 'package:lcs_new_age/items/flag_type.dart';
import 'package:lcs_new_age/items/flag_type_xml.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/items/loot_type_xml.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/items/weapon_type_xml.dart';
import 'package:lcs_new_age/saveload/required_asset.dart';
import 'package:lcs_new_age/sitemode/shop.dart';
import 'package:lcs_new_age/sitemode/shop_xml.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/sitemap_from_tabscript.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';
import 'package:lcs_new_age/vehicles/vehicle_type_xml.dart';
import 'package:xml/xml.dart';

void loadingFeedback(String fileName) {
  erase();
  mvaddstr(8, 2, "Loading Liberal Crime Squad...");
  mvaddstr(10, 2, "File: $fileName");
  refresh();
}

Future<void> loadXmlData({AssetBundle? bundle}) async {
  loadingFeedback("sitemaps.txt");
  oldMapMode = !(await readConfigFile("assets/maps/sitemaps.txt", bundle: bundle));
  loadingFeedback("clothing.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/clothing.xml', bundle: bundle));
  loadingFeedback("armor_upgrades.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/armor_upgrades.xml', bundle: bundle));
  loadingFeedback("loot.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/loot.xml', bundle: bundle));
  loadingFeedback("flags.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/flags.xml', bundle: bundle));
  loadingFeedback("creatures.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/creatures.xml', bundle: bundle));
  loadingFeedback("weapons.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/weapons.xml', bundle: bundle));
  loadingFeedback("ammo.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/ammo.xml', bundle: bundle));
  loadingFeedback("vehicles.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/vehicles.xml', bundle: bundle));
  loadingFeedback("oubliette.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/oubliette.xml', bundle: bundle));
  loadingFeedback("deptstore.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/deptstore.xml', bundle: bundle));
  loadingFeedback("armsdealer.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/armsdealer.xml', bundle: bundle));
  loadingFeedback("pawnshop.xml");
  _parseDocument(await loadRequiredAssetString('assets/xml/pawnshop.xml', bundle: bundle));
}

void _parseDocument(String xml) {
  XmlDocument doc = XmlDocument.parse(xml);
  XmlElement root = doc.rootElement;
  if (root.localName == 'shop') {
    String? id = root.getAttribute('name');
    if (id != null) {
      parseShop(shopTypes[id] ?? Shop(id), root);
    } else {
      debugPrint("Shop has no name attribute, skipping");
    }
    return;
  }
  for (XmlElement element in root.childElements) {
    String typeName = element.localName;
    String? id = element.getAttribute('idname');
    if (typeName == 'default') {
      debugPrint("Unknown default element in ${root.name.local}");
      continue;
    }
    if (id == null) {
      debugPrint("$typeName has no idname attribute, skipping");
      continue;
    }
    switch (typeName) {
      case 'clothingtype':
        parseClothingType(clothingTypes[id] ?? ClothingType(id), element);
      case 'armorupgrade':
        parseArmorUpgrade(armorUpgrades[id] ?? ArmorUpgrade(id), element);
      case 'loottype':
        parseLootType(lootTypes[id] ?? LootType(id), element);
      case 'flagtype':
        parseFlagType(flagTypes[id] ?? FlagType(id), element);
      case 'creaturetype':
        parseCreatureType(creatureTypes[id] ?? CreatureType(id), element);
      case 'weapontype':
        parseWeaponType(weaponTypes[id] ?? WeaponType(id), element);
      case 'vehicletype':
        parseVehicleType(vehicleTypes[id] ?? VehicleType(id), element);
      case 'ammotype':
        parseAmmoType(ammoTypes[id] ?? AmmoType(id), element);
      default:
        debugPrint("Unknown element $typeName in ${root.name.local}");
    }
  }
}
