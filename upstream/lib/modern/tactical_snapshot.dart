import 'package:flutter/material.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/catalogue_art.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_symbols.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

const _wall = Color(0xFF8E8774);
const _teal = JournalPalette.olive;
const _amber = JournalPalette.brassDark;
const _danger = JournalPalette.danger;
const _paper = JournalPalette.card;

/// A frozen description of an already-created dropped stack, never a loot roll
/// or a reference to a mutable inventory item.
@immutable
class TacticalLootItem {
  const TacticalLootItem({
    required this.typeId,
    required this.title,
    required this.quantity,
    this.money = false,
  });

  final String typeId, title;
  final int quantity;
  final bool money;
  CatalogueArtEntry? get artwork => equipmentArtwork(typeId);
  String get label => money || quantity == 1 ? title : '$title ×$quantity';
}

enum TacticalTileKind {
  unknown,
  squad,
  wall,
  door,
  armoredEnemy,
  enemy,
  woundedEnemy,
  stairsUp,
  stairsDown,
  exit,
  fire,
  special,
  trap,
  loot,
  blood,
  grass,
  debris,
  floor,
}

/// Presentation data only. Hidden terrain and units are never copied here.
@immutable
class TacticalMapCell {
  const TacticalMapCell({
    required this.x,
    required this.y,
    required this.kind,
    required this.label,
    this.icon,
    this.color = _paper,
    this.visible = false,
    this.horizontalDoor = false,
    this.restricted = false,
    this.burning = false,
    this.objectSprite,
    this.objectQuadrant,
    this.hazardSprite,
    this.groundSprite,
    this.underlyingKind,
    this.underlyingLabel,
    this.hazardLabel,
    this.actionHint = '',
    this.pointOfInterest = false,
    this.lootAvailable = false,
    this.graffiti,
    this.visited = false,
    this.droppedItems = const [],
    this.unsearchedLoot = false,
  });

  final int x, y;
  final TacticalTileKind kind;
  final String label;
  final IconData? icon;
  final Color color;
  final bool visible, horizontalDoor, restricted, burning;
  final int? objectSprite, hazardSprite, groundSprite;

  /// A known quadrant of the original two-by-two presidential desk.
  final int? objectQuadrant;
  final TacticalTileKind? underlyingKind;
  final String? underlyingLabel, hazardLabel;
  final String actionHint;
  final bool pointOfInterest;
  final bool lootAvailable;
  final TacticalGraffiti? graffiti;
  final bool visited;
  final List<TacticalLootItem> droppedItems;
  final bool unsearchedLoot;

  CatalogueArtEntry? get lootArtwork =>
      !unsearchedLoot &&
          droppedItems.isNotEmpty &&
          droppedItems.every((item) => item.typeId == droppedItems.first.typeId)
      ? droppedItems.first.artwork
      : null;

  String get lootSummary => [
    if (droppedItems.isNotEmpty)
      'Dropped loot: ${droppedItems.length} ${droppedItems.length == 1 ? 'stack' : 'stacks'}',
    if (unsearchedLoot) 'Unsearched loot',
  ].join(' · ');

  /// A unit marker never replaces the known room, fixture or terrain beneath it.
  String get featureLabel => underlyingLabel ?? label;

  /// Composed solely from captured presentation data, including the content
  /// beneath a unit. Unknown tiles expose no state, hint or visibility detail.
  String get semanticLabel {
    if (kind == TacticalTileKind.unknown) return 'Unexplored';
    final parts = <String>{
      label,
      if (underlyingLabel != null) underlyingLabel!,
      if (kind == TacticalTileKind.squad) 'Current position',
      if (visible || kind == TacticalTileKind.squad)
        'In view'
      else
        'Previously explored',
      if (restricted) 'Restricted area',
      if (lootAvailable) 'Loot available (G)',
      if (lootSummary.isNotEmpty) lootSummary,
      for (final item in droppedItems) item.label,
      if (hazardLabel != null) ...hazardLabel!.split(' · '),
      if (burning && hazardLabel == null) 'Fire',
      if (actionHint.isNotEmpty) actionHint,
    };
    return parts.join(' · ');
  }
}

/// A read-only frame using exactly printSiteMapSmall's 23 by 10 viewport.
/// Visibility is owned by the engine, which updates it before presenting input.
@immutable
class TacticalMapSnapshot {
  const TacticalMapSnapshot({
    required this.xStart,
    required this.yStart,
    required this.floor,
    required this.cells,
    required this.location,
    required this.currentDescription,
    required this.alarm,
    required this.cameras,
    required this.response,
    this.columnCount = columns,
    this.rowCount = rows,
    this.siteType = '',
  });

  factory TacticalMapSnapshot.capture({bool fullMap = false}) {
    final position = displayedSquadPosition;
    final columnCount = fullMap ? MAPX : columns;
    final rowCount = fullMap ? MAPY : rows;
    final xStart = fullMap ? 0 : (position.x - 11).clamp(0, MAPX - columns);
    final yStart = fullMap ? 0 : (position.y - 4).clamp(0, MAPY - rows);
    final floor = position.z;
    final site = game.activeSite;
    final cameras =
        site != null && site.compound.cameras && !site.siege.camerasOff;
    final cells = <TacticalMapCell>[];
    for (int row = 0; row < rowCount; row++) {
      for (int column = 0; column < columnCount; column++) {
        final x = xStart + column, y = yStart + row;
        final tile = levelMapTileOrNull(x, y, floor);
        cells.add(_describeTile(tile, x, y, cameras));
      }
    }
    final current = levelMapTileOrNull(position.x, position.y, floor);
    final currentDescription = _currentDescription(current);
    return TacticalMapSnapshot(
      xStart: xStart,
      yStart: yStart,
      floor: floor,
      columnCount: columnCount,
      rowCount: rowCount,
      cells: List.unmodifiable(cells),
      location: site?.getName() ?? 'Site operation',
      currentDescription: currentDescription,
      alarm: game.siteAlarm
          ? 'Alarm raised'
          : game.siteAlarmTimer == 0
          ? 'Suspicion raised'
          : game.siteAlarmTimer > 0
          ? 'Suspicion building'
          : 'No alarm',
      cameras: cameras,
      response: game.postAlarmTimer > 80
          ? 'Response force arriving'
          : game.postAlarmTimer > 60
          ? 'Reinforcements incoming'
          : '',
      siteType: site?.type.name ?? '',
    );
  }

  static const int columns = 23, rows = 10;
  final int xStart, yStart, floor;
  final int columnCount, rowCount;
  final List<TacticalMapCell> cells;
  final String location, currentDescription, alarm, response;
  final bool cameras;
  final String siteType;
}

// Keep foreground priority aligned with drawTileContent in site_display.dart.
// Known terrain, objects, restrictions and hazards are independent layers.
TacticalMapCell _describeTile(SiteTile? tile, int x, int y, bool cameras) {
  if (tile == null || !tile.known) {
    return TacticalMapCell(
      x: x,
      y: y,
      kind: TacticalTileKind.unknown,
      label: 'Unexplored',
    );
  }
  final visible = tile.inLOS || cameras;
  final position = displayedSquadPosition;
  final droppedLoot =
      tile.x == position.x &&
      tile.y == position.y &&
      tile.z == position.z &&
      game.groundLoot.any((item) => item.stackSize > 0);
  // groundLoot belongs to the standing squad, including while the engine
  // temporarily points locx/locy at a door. Never copy the tile's unrolled loot.
  final droppedItems = droppedLoot
      ? List<TacticalLootItem>.unmodifiable([
          for (final item in game.groundLoot)
            if (item.stackSize > 0)
              TacticalLootItem(
                typeId: item.type.idName,
                title: item.equipTitle(),
                quantity: item.stackSize,
                money: item.type.isMoney,
              ),
        ])
      : const <TacticalLootItem>[];
  final base = _baseFeature(tile);
  var foreground = base;
  if (tile.x == position.x && tile.y == position.y && tile.z == position.z) {
    foreground = (
      kind: TacticalTileKind.squad,
      label: 'Squad',
      icon: Icons.groups_rounded,
      color: _teal,
    );
  } else if (base.kind != TacticalTileKind.wall &&
      base.kind != TacticalTileKind.door) {
    if (tile.siegeHeavyUnit && visible) {
      foreground = (
        kind: TacticalTileKind.armoredEnemy,
        label: 'Armored enemy',
        icon: Icons.local_shipping_rounded,
        color: _danger,
      );
    } else if (tile.siegeUnit && visible) {
      foreground = (
        kind: TacticalTileKind.enemy,
        label: 'Enemy',
        icon: Icons.person_rounded,
        color: _danger,
      );
    } else if (tile.siegeUnitDamaged && visible) {
      foreground = (
        kind: TacticalTileKind.woundedEnemy,
        label: 'Wounded enemy',
        icon: Icons.personal_injury_rounded,
        color: const Color(0xFFB66C61),
      );
    } else if (base.kind != TacticalTileKind.stairsUp &&
        base.kind != TacticalTileKind.stairsDown &&
        base.kind != TacticalTileKind.exit &&
        tile.burning) {
      foreground = (
        kind: TacticalTileKind.fire,
        label: _fireLabel(tile),
        icon: Icons.local_fire_department_rounded,
        color: tile.fireEnd ? _amber : _danger,
      );
    }
  }
  final hasOverlay = foreground.kind != base.kind;
  final knownLeftWall = tile.left?.known == true && tile.left!.wall;
  final knownRightWall = tile.right?.known == true && tile.right!.wall;
  return TacticalMapCell(
    x: x,
    y: y,
    kind: foreground.kind,
    label: foreground.label,
    icon: foreground.icon,
    color: foreground.color,
    visible: visible,
    underlyingKind: hasOverlay ? base.kind : null,
    underlyingLabel: hasOverlay ? base.label : null,
    horizontalDoor: tile.door && (knownLeftWall || knownRightWall),
    restricted: tile.restricted,
    burning: tile.burning,
    pointOfInterest: tile.special != TileSpecial.none,
    lootAvailable: tile.loot || droppedLoot,
    droppedItems: droppedItems,
    unsearchedLoot: tile.loot,
    actionHint: _actionHint(tile, droppedLoot: droppedLoot),
    graffiti: switch (base.label) {
      'LCS graffiti' => TacticalGraffiti.lcs,
      'CCS graffiti' => TacticalGraffiti.ccs,
      'Graffiti' => TacticalGraffiti.other,
      _ => null,
    },
    visited: tile.special == TileSpecial.nursingHomePatientDone,
    objectSprite:
        _objectSprite(tile.special) ??
        (tile.loot || droppedLoot ? TacticalObjectCell.crate : null),
    objectQuadrant: switch (tile.special) {
      TileSpecial.ovalOfficeNW => 0,
      TileSpecial.ovalOfficeNE => 1,
      TileSpecial.ovalOfficeSW => 2,
      TileSpecial.ovalOfficeSE => 3,
      _ => null,
    },
    hazardSprite: tile.burning
        ? tile.firePeak
              ? TacticalHazardCell.intenseFire
              : tile.fireEnd
              ? TacticalHazardCell.embers
              : TacticalHazardCell.spreadingFire
        : tile.siegeTrap
        ? TacticalHazardCell.trap
        : tile.debris
        ? TacticalHazardCell.rubble
        : tile.megaBloody
        ? TacticalHazardCell.heavyBlood
        : tile.bloody
        ? TacticalHazardCell.blood
        : null,
    hazardLabel: _hazardLabel(tile),
    groundSprite: tile.grass
        ? TacticalTerrainCell.grass
        : tile.outdoor
        ? TacticalTerrainCell.pavement
        : null,
  );
}

typedef _TileFeature = ({
  TacticalTileKind kind,
  String label,
  IconData? icon,
  Color color,
});

_TileFeature _baseFeature(SiteTile tile) {
  _TileFeature feature(
    TacticalTileKind kind,
    String label,
    IconData? icon,
    Color color,
  ) => (kind: kind, label: label, icon: icon, color: color);
  if (tile.wall) {
    if (tile.burning) {
      return feature(
        TacticalTileKind.wall,
        'Burning wall',
        Icons.local_fire_department_rounded,
        _danger,
      );
    }
    // Neighboring marks decorate a known wall only after those neighbors have
    // themselves been explored. No hidden neighbor flags enter presentation.
    final knownNeighbors = tile.neighbors().where((neighbor) => neighbor.known);
    if (knownNeighbors.any((neighbor) => neighbor.megaBloody)) {
      return feature(TacticalTileKind.wall, 'Bloodstained wall', null, _danger);
    }
    if (knownNeighbors.any((neighbor) => neighbor.graffitiLCS)) {
      return feature(
        TacticalTileKind.wall,
        'LCS graffiti',
        Icons.brush_rounded,
        _teal,
      );
    }
    if (knownNeighbors.any((neighbor) => neighbor.graffitiCCS)) {
      return feature(
        TacticalTileKind.wall,
        'CCS graffiti',
        Icons.brush_rounded,
        _danger,
      );
    }
    if (knownNeighbors.any((neighbor) => neighbor.graffitiOther)) {
      return feature(
        TacticalTileKind.wall,
        'Graffiti',
        Icons.brush_rounded,
        const Color(0xFF98A6AE),
      );
    }
    return feature(TacticalTileKind.wall, 'Wall', null, _wall);
  }
  if (tile.door) {
    if (tile.metal) {
      return feature(
        TacticalTileKind.door,
        'Metal door',
        Icons.door_front_door_rounded,
        const Color(0xFFD6E0E5),
      );
    }
    if (tile.burning) {
      return feature(
        TacticalTileKind.door,
        'Burning door',
        Icons.local_fire_department_rounded,
        _danger,
      );
    }
    if (tile.cantUnlock && tile.locked) {
      return feature(
        TacticalTileKind.door,
        'Door · cannot unlock',
        Icons.lock_rounded,
        _danger,
      );
    }
    if (tile.knownLock && tile.locked) {
      return feature(
        TacticalTileKind.door,
        'Locked door',
        Icons.lock_rounded,
        const Color(0xFFA9B3B8),
      );
    }
    return feature(
      TacticalTileKind.door,
      'Door',
      Icons.door_front_door_rounded,
      _amber,
    );
  }
  if (tile.special == TileSpecial.stairsUp) {
    return feature(
      TacticalTileKind.stairsUp,
      'Stairs up',
      Icons.stairs_rounded,
      _amber,
    );
  }
  if (tile.special == TileSpecial.stairsDown) {
    return feature(
      TacticalTileKind.stairsDown,
      'Stairs down',
      Icons.stairs_rounded,
      _amber,
    );
  }
  if (tile.exit) {
    return feature(
      TacticalTileKind.exit,
      'Exit',
      Icons.exit_to_app_rounded,
      _amber,
    );
  }
  if (tile.special != TileSpecial.none) {
    final (label, icon, color) = _specialPresentation(tile.special);
    return feature(TacticalTileKind.special, label, icon, color);
  }
  if (tile.siegeTrap) {
    return feature(
      TacticalTileKind.trap,
      'Defensive boobytrap',
      Icons.warning_rounded,
      _amber,
    );
  }
  if (tile.loot) {
    return feature(
      TacticalTileKind.loot,
      'Loot',
      Icons.inventory_2_rounded,
      const Color(0xFFC4A5E0),
    );
  }
  if (tile.megaBloody) {
    return feature(
      TacticalTileKind.blood,
      'Bloodstained floor',
      Icons.water_drop_rounded,
      _danger,
    );
  }
  if (tile.grass) {
    return feature(
      TacticalTileKind.grass,
      tile.bloody ? 'Bloodstained grass' : 'Grass',
      Icons.grass_rounded,
      tile.bloody ? _danger : const Color(0xFF86A991),
    );
  }
  if (tile.debris) {
    return feature(
      TacticalTileKind.debris,
      'Debris',
      Icons.texture_rounded,
      const Color(0xFFACB5B5),
    );
  }
  return feature(
    TacticalTileKind.floor,
    tile.bloody
        ? 'Bloodstained floor'
        : tile.restricted
        ? 'Restricted floor'
        : 'Open floor',
    tile.bloody ? Icons.water_drop_rounded : null,
    tile.bloody ? _danger : const Color(0xFF7595AE),
  );
}

String _fireLabel(SiteTile tile) => tile.firePeak
    ? 'Intense fire'
    : tile.fireEnd
    ? 'Dying fire'
    : 'Spreading fire';

String? _hazardLabel(SiteTile tile) {
  final hazards = <String>[
    if (tile.burning) _fireLabel(tile),
    if (tile.siegeTrap) 'Defensive boobytrap',
    if (tile.debris) 'Debris',
    if (tile.megaBloody || tile.bloody)
      if (tile.grass) 'Bloodstained grass' else 'Bloodstained floor',
  ];
  return hazards.isEmpty ? null : hazards.join(' · ');
}

String _currentDescription(SiteTile? tile) {
  if (tile == null || !tile.known) return 'Unexplored';
  final parts = <String>[
    if (tile.special != TileSpecial.none) _specialPresentation(tile.special).$1,
    if (tile.exit) 'Exit',
    if (tile.loot) 'Loot',
    if (game.groundLoot.isNotEmpty) 'Dropped loot',
    if (tile.siegeTrap) 'Defensive boobytrap',
    if (tile.debris) 'Debris',
    if (tile.grass)
      if (tile.bloody || tile.megaBloody) 'Bloodstained grass' else 'Grass'
    else if (tile.bloody || tile.megaBloody)
      'Bloodstained floor',
    if (tile.burning) 'Fire',
    if (tile.restricted) 'Restricted area',
  ];
  return parts.isEmpty ? 'Open floor' : parts.join(' · ');
}

String _actionHint(SiteTile tile, {bool droppedLoot = false}) {
  if (tile.door) {
    if (tile.metal) {
      return 'Impenetrable vault door. Find another route or a vault control.';
    }
    return 'Move toward this tile to try the door; opening it leaves the squad in place.';
  }
  if (tile.exit) return 'Entering this tile leaves the site.';
  final hints = <String>[];
  if (tile.special == TileSpecial.stairsUp) {
    hints.add('Stand here, then press U to go upstairs.');
  } else if (tile.special == TileSpecial.stairsDown) {
    hints.add('Stand here, then press U to go downstairs.');
  } else if (tile.special.activatesOnEntry) {
    hints.add(
      'Events here resolve on entry; U does not activate this fixture.',
    );
  } else if (tile.special != TileSpecial.none) {
    hints.add('Stand here, then press U to use / interact.');
  }
  if (tile.loot || droppedLoot) {
    hints.add('Stand here, then press G to get loot.');
  }
  if (tile.siegeTrap) {
    hints.add(
      'Defensive boobytrap against siege enemies; squad movement does not trigger it.',
    );
  }
  return hints.join(' ');
}

(String, IconData, Color) _specialPresentation(
  TileSpecial special,
) => switch (special) {
  TileSpecial.none => ('Open floor', Icons.circle, _paper),
  TileSpecial.cagedRabbits => ('Caged animals', Icons.pets_rounded, _amber),
  TileSpecial.cagedMonsters => ('Caged "animals"', Icons.pets_rounded, _amber),
  TileSpecial.policeStationLockup => (
    'Police detention room',
    Icons.grid_on_rounded,
    _amber,
  ),
  TileSpecial.courthouseLockup => (
    'Courthouse jail',
    Icons.grid_on_rounded,
    _amber,
  ),
  TileSpecial.courthouseJuryRoom => ('Jury room', Icons.gavel_rounded, _amber),
  TileSpecial.prisonControl ||
  TileSpecial.prisonControlLow ||
  TileSpecial.prisonControlMedium ||
  TileSpecial.prisonControlHigh => (
    'Prison control room',
    Icons.settings_remote_rounded,
    _amber,
  ),
  TileSpecial.intelSupercomputer => (
    'Supercomputer',
    Icons.dns_rounded,
    _amber,
  ),
  TileSpecial.sweatshopEquipment => (
    'Textile equipment',
    Icons.precision_manufacturing_rounded,
    _amber,
  ),
  TileSpecial.polluterEquipment => (
    'Factory equipment',
    Icons.factory_rounded,
    _amber,
  ),
  TileSpecial.labEquipment => ('Lab equipment', Icons.science_rounded, _amber),
  TileSpecial.nuclearControlRoom => (
    'Reactor control room',
    Icons.settings_remote_rounded,
    _amber,
  ),
  TileSpecial.ceoSafe => ('Safe', Icons.lock_outline_rounded, _amber),
  TileSpecial.ceoOffice => ('CEO’s study', Icons.desk_rounded, _danger),
  TileSpecial.corporateFiles => (
    'Corporate files',
    Icons.folder_copy_rounded,
    _amber,
  ),
  TileSpecial.radioBroadcastStudio => (
    'Radio studio',
    Icons.radio_rounded,
    _amber,
  ),
  TileSpecial.cableBroadcastStudio => (
    'News studio',
    Icons.live_tv_rounded,
    _amber,
  ),
  TileSpecial.apartmentLandlord => (
    'Landlord’s office',
    Icons.desk_rounded,
    _amber,
  ),
  TileSpecial.signOne ||
  TileSpecial.signTwo ||
  TileSpecial.signThree => ('Sign', Icons.signpost_rounded, _amber),
  TileSpecial.table => ('Table', Icons.table_restaurant_rounded, _amber),
  TileSpecial.computer => ('Computer', Icons.computer_rounded, _amber),
  TileSpecial.tent => ('Tent', Icons.cabin_rounded, _amber),
  TileSpecial.parkBench => ('Bench', Icons.event_seat_rounded, _amber),
  TileSpecial.stairsUp => ('Stairs up', Icons.stairs_rounded, _amber),
  TileSpecial.stairsDown => ('Stairs down', Icons.stairs_rounded, _amber),
  TileSpecial.clubBouncer || TileSpecial.clubBouncerSecondVisit => (
    'Club bouncer',
    Icons.security_rounded,
    _danger,
  ),
  TileSpecial.armory => ('Armory', Icons.shield_rounded, _amber),
  TileSpecial.displayCase => ('Display case', Icons.window_rounded, _amber),
  TileSpecial.securityCheckpoint => (
    'Security checkpoint',
    Icons.security_rounded,
    _danger,
  ),
  TileSpecial.securityMetalDetectors => (
    'Metal detectors',
    Icons.sensor_door_rounded,
    _danger,
  ),
  TileSpecial.securitySecondVisit => (
    'Security checkpoint',
    Icons.security_rounded,
    _amber,
  ),
  TileSpecial.bankVault => ('Bank vault', Icons.lock_outline_rounded, _amber),
  TileSpecial.bankTeller => (
    'Bank teller',
    Icons.account_balance_rounded,
    _amber,
  ),
  TileSpecial.bankMoney => ('Bank money', Icons.payments_rounded, _amber),
  TileSpecial.ccsBoss => ('CCS boss', Icons.priority_high_rounded, _danger),
  TileSpecial.ovalOfficeNW ||
  TileSpecial.ovalOfficeNE ||
  TileSpecial.ovalOfficeSW ||
  TileSpecial.ovalOfficeSE => (
    'President’s office',
    Icons.account_balance_rounded,
    _amber,
  ),
  TileSpecial.nursingHomeFiles => (
    'Patient files',
    Icons.folder_copy_rounded,
    _amber,
  ),
  TileSpecial.nursingHomeManager => (
    'Manager’s office',
    Icons.desk_rounded,
    _amber,
  ),
  TileSpecial.nursingHomePatient => (
    'Patient’s room',
    Icons.bed_rounded,
    _amber,
  ),
  TileSpecial.nursingHomePatientDone => (
    'Patient’s room · visited',
    Icons.bed_rounded,
    const Color(0xFF7595AE),
  ),
  TileSpecial.insuranceFiles => (
    'Insurance files',
    Icons.folder_copy_rounded,
    _amber,
  ),
  TileSpecial.insuranceCEO => ('CEO’s office', Icons.desk_rounded, _amber),
  TileSpecial.insuranceClaimsTerminal => (
    'Claims terminal',
    Icons.computer_rounded,
    _amber,
  ),
};

// Only called after the tile has passed the engine's known-tile gate.
int? _objectSprite(TileSpecial special) => switch (special) {
  TileSpecial.radioBroadcastStudio => TacticalObjectCell.radioConsole,
  TileSpecial.computer => TacticalObjectCell.workstation,
  TileSpecial.intelSupercomputer => TacticalObjectCell.serverRack,
  TileSpecial.insuranceClaimsTerminal => TacticalObjectCell.claimsTerminal,
  TileSpecial.cableBroadcastStudio => TacticalObjectCell.tvCamera,
  TileSpecial.ceoSafe => TacticalObjectCell.safe,
  TileSpecial.bankVault => TacticalObjectCell.bankVault,
  TileSpecial.corporateFiles ||
  TileSpecial.insuranceFiles ||
  TileSpecial.nursingHomeFiles => TacticalObjectCell.files,
  TileSpecial.sweatshopEquipment => TacticalObjectCell.sewingMachine,
  TileSpecial.polluterEquipment => TacticalObjectCell.machinery,
  TileSpecial.labEquipment => TacticalObjectCell.labBench,
  TileSpecial.prisonControl ||
  TileSpecial.prisonControlLow ||
  TileSpecial.prisonControlMedium ||
  TileSpecial.prisonControlHigh => TacticalObjectCell.prisonConsole,
  TileSpecial.nuclearControlRoom => TacticalObjectCell.reactorConsole,
  TileSpecial.cagedRabbits ||
  TileSpecial.cagedMonsters => TacticalObjectCell.cage,
  TileSpecial.table => TacticalObjectCell.table,
  TileSpecial.ceoOffice ||
  TileSpecial.insuranceCEO => TacticalObjectCell.executiveDesk,
  TileSpecial.apartmentLandlord ||
  TileSpecial.nursingHomeManager => TacticalObjectCell.officeDesk,
  TileSpecial.armory => TacticalObjectCell.weaponRack,
  TileSpecial.policeStationLockup ||
  TileSpecial.courthouseLockup => TacticalObjectCell.detentionCell,
  TileSpecial.courthouseJuryRoom => TacticalObjectCell.juryTable,
  TileSpecial.nursingHomePatient ||
  TileSpecial.nursingHomePatientDone => TacticalObjectCell.nursingBed,
  TileSpecial.ovalOfficeNW ||
  TileSpecial.ovalOfficeNE ||
  TileSpecial.ovalOfficeSW ||
  TileSpecial.ovalOfficeSE => TacticalObjectCell.presidentialDesk,
  TileSpecial.bankTeller => TacticalObjectCell.tellerCounter,
  TileSpecial.signOne ||
  TileSpecial.signTwo ||
  TileSpecial.signThree => TacticalObjectCell.signboard,
  TileSpecial.bankMoney => TacticalObjectCell.cash,
  TileSpecial.parkBench => TacticalObjectCell.bench,
  TileSpecial.tent => TacticalObjectCell.tent,
  TileSpecial.displayCase => TacticalObjectCell.displayCase,
  TileSpecial.securityCheckpoint ||
  TileSpecial.securityMetalDetectors ||
  TileSpecial.securitySecondVisit => TacticalObjectCell.checkpoint,
  _ => null,
};
