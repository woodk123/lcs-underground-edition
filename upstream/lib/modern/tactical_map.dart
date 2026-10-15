import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

const _ink = JournalPalette.ink;
const _fog = Color(0xFFD4CFB7);
const _wall = Color(0xFF8E8774);
const _teal = JournalPalette.olive;
const _amber = JournalPalette.brassDark;
const _danger = JournalPalette.danger;
const _paper = JournalPalette.card;

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
  });

  final int x, y;
  final TacticalTileKind kind;
  final String label;
  final IconData? icon;
  final Color color;
  final bool visible, horizontalDoor, restricted, burning;
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
  });

  factory TacticalMapSnapshot.capture({bool fullMap = false}) {
    final columnCount = fullMap ? MAPX : columns;
    final rowCount = fullMap ? MAPY : rows;
    final xStart = fullMap ? 0 : (game.locx - 11).clamp(0, MAPX - columns);
    final yStart = fullMap ? 0 : (game.locy - 4).clamp(0, MAPY - rows);
    final floor = game.locz;
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
    final current = levelMapTileOrNull(game.locx, game.locy, floor);
    final currentDescription = current?.known == true
        ? [
            if (current!.special != TileSpecial.none)
              _specialPresentation(current.special).$1
            else if (current.exit)
              'Exit'
            else if (current.restricted)
              'Restricted area'
            else
              'Open floor',
            if (current.burning) 'Fire',
          ].join(' · ')
        : 'Unexplored';
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
          : 'No alarm',
      cameras: cameras,
      response: game.postAlarmTimer > 80
          ? 'Response force arriving'
          : game.postAlarmTimer > 60
          ? 'Reinforcements incoming'
          : '',
    );
  }

  static const int columns = 23, rows = 10;
  final int xStart, yStart, floor;
  final int columnCount, rowCount;
  final List<TacticalMapCell> cells;
  final String location, currentDescription, alarm, response;
  final bool cameras;
}

// Keep this priority order aligned with drawTileContent in site_display.dart.
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
  TacticalMapCell cell(
    TacticalTileKind kind,
    String label,
    IconData? icon,
    Color color, {
    bool horizontalDoor = false,
    bool restricted = false,
    bool burning = false,
  }) => TacticalMapCell(
    x: x,
    y: y,
    kind: kind,
    label: label,
    icon: icon,
    color: color,
    visible: visible,
    horizontalDoor: horizontalDoor,
    restricted: restricted,
    burning: burning,
  );

  if (tile.x == game.locx && tile.y == game.locy) {
    return cell(TacticalTileKind.squad, 'Squad', Icons.groups_rounded, _teal);
  }
  if (tile.wall) {
    if (tile.burning) {
      return cell(
        TacticalTileKind.wall,
        'Burning wall',
        Icons.local_fire_department_rounded,
        _danger,
        burning: true,
      );
    }
    if (tile.neighbors().any((neighbor) => neighbor.megaBloody)) {
      return cell(TacticalTileKind.wall, 'Bloodstained wall', null, _danger);
    }
    if (tile.neighbors().any((neighbor) => neighbor.graffitiLCS)) {
      return cell(
        TacticalTileKind.wall,
        'LCS graffiti',
        Icons.brush_rounded,
        _teal,
      );
    }
    if (tile.neighbors().any((neighbor) => neighbor.graffitiCCS)) {
      return cell(
        TacticalTileKind.wall,
        'CCS graffiti',
        Icons.brush_rounded,
        _danger,
      );
    }
    if (tile.neighbors().any((neighbor) => neighbor.graffitiOther)) {
      return cell(
        TacticalTileKind.wall,
        'Graffiti',
        Icons.brush_rounded,
        const Color(0xFF98A6AE),
      );
    }
    return cell(TacticalTileKind.wall, 'Wall', null, _wall);
  }
  if (tile.door) {
    final String label;
    final IconData icon;
    final Color color;
    // Metal and burning doors precede lock information in the original view.
    if (tile.metal) {
      label = 'Metal door';
      icon = Icons.door_front_door_rounded;
      color = const Color(0xFFD6E0E5);
    } else if (tile.burning) {
      label = 'Burning door';
      icon = Icons.local_fire_department_rounded;
      color = _danger;
    } else if (tile.cantUnlock && tile.locked) {
      label = 'Door · cannot unlock';
      icon = Icons.lock_rounded;
      color = _danger;
    } else if (tile.knownLock && tile.locked) {
      label = 'Locked door';
      icon = Icons.lock_rounded;
      color = const Color(0xFFA9B3B8);
    } else {
      label = 'Door';
      icon = Icons.door_front_door_rounded;
      color = _amber;
    }
    return cell(
      TacticalTileKind.door,
      label,
      icon,
      color,
      horizontalDoor: tile.left?.wall == true || tile.right?.wall == true,
      burning: !tile.metal && tile.burning,
    );
  }
  if (tile.siegeHeavyUnit && visible) {
    return cell(
      TacticalTileKind.armoredEnemy,
      'Armored enemy',
      Icons.local_shipping_rounded,
      _danger,
    );
  }
  if (tile.siegeUnit && visible) {
    return cell(TacticalTileKind.enemy, 'Enemy', Icons.person_rounded, _danger);
  }
  if (tile.siegeUnitDamaged && visible) {
    return cell(
      TacticalTileKind.woundedEnemy,
      'Wounded enemy',
      Icons.personal_injury_rounded,
      const Color(0xFFB66C61),
    );
  }
  if (tile.special == TileSpecial.stairsUp) {
    return cell(
      TacticalTileKind.stairsUp,
      'Stairs up',
      Icons.stairs_rounded,
      _amber,
    );
  }
  if (tile.special == TileSpecial.stairsDown) {
    return cell(
      TacticalTileKind.stairsDown,
      'Stairs down',
      Icons.stairs_rounded,
      _amber,
    );
  }
  if (tile.exit) {
    return cell(
      TacticalTileKind.exit,
      'Exit',
      Icons.exit_to_app_rounded,
      _amber,
    );
  }
  if (tile.burning) {
    return cell(
      TacticalTileKind.fire,
      tile.firePeak
          ? 'Intense fire'
          : tile.fireEnd
          ? 'Dying fire'
          : 'Spreading fire',
      Icons.local_fire_department_rounded,
      tile.fireEnd ? _amber : _danger,
      burning: true,
    );
  }
  if (tile.special != TileSpecial.none) {
    final (label, icon, color) = _specialPresentation(tile.special);
    return cell(TacticalTileKind.special, label, icon, color);
  }
  if (tile.siegeTrap) {
    return cell(TacticalTileKind.trap, 'Trap', Icons.warning_rounded, _amber);
  }
  if (tile.loot) {
    return cell(
      TacticalTileKind.loot,
      'Loot',
      Icons.inventory_2_rounded,
      const Color(0xFFC4A5E0),
    );
  }
  if (tile.megaBloody) {
    return cell(
      TacticalTileKind.blood,
      'Bloodstained floor',
      Icons.water_drop_rounded,
      _danger,
    );
  }
  if (tile.grass) {
    return cell(
      TacticalTileKind.grass,
      tile.bloody ? 'Bloodstained grass' : 'Grass',
      Icons.grass_rounded,
      tile.bloody ? _danger : const Color(0xFF86A991),
    );
  }
  if (tile.debris) {
    return cell(
      TacticalTileKind.debris,
      'Debris',
      Icons.texture_rounded,
      const Color(0xFFACB5B5),
    );
  }
  return cell(
    TacticalTileKind.floor,
    tile.bloody
        ? 'Bloodstained floor'
        : tile.restricted
        ? 'Restricted floor'
        : 'Open floor',
    tile.bloody ? Icons.water_drop_rounded : null,
    tile.bloody ? _danger : const Color(0xFF7595AE),
    restricted: tile.restricted,
  );
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

/// Fits square cells to the actual pane, without changing the engine viewport.
Size fittedFieldPlanSize(BoxConstraints constraints, int columns, int rows) {
  final availableWidth = constraints.maxWidth.isFinite
      ? math.max(0, constraints.maxWidth)
      : columns * 30.0;
  final width = constraints.maxHeight.isFinite
      ? math.min(
          availableWidth,
          math.max(0, constraints.maxHeight) * columns / rows,
        )
      : availableWidth;
  return Size(width.toDouble(), width * rows / columns);
}

class TacticalMapView extends StatelessWidget {
  const TacticalMapView({
    super.key,
    required this.onMove,
    this.showMovementControls = true,
    this.movementEnabled = true,
    this.showHeading = true,
  });

  final void Function(String) onMove;
  final bool showMovementControls;
  final bool movementEnabled;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final snapshot = TacticalMapSnapshot.capture();
    return JournalSurface(
      key: const ValueKey('tactical-field-plan'),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final header = _header(snapshot);
          final footer = _footer(snapshot);
          if (bounds.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                Expanded(child: _grid(snapshot)),
                const SizedBox(height: 8),
                footer,
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 10),
              _grid(snapshot),
              const SizedBox(height: 10),
              footer,
            ],
          );
        },
      ),
    );
  }

  Widget _header(TacticalMapSnapshot snapshot) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(
            Icons.map_outlined,
            size: 18,
            color: JournalPalette.brassDark,
          ),
          const SizedBox(width: 7),
          Text(
            'TACTICAL VIEW',
            style: JournalPalette.small.copyWith(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            'LEVEL ${snapshot.floor + 1}',
            style: JournalPalette.small.copyWith(fontSize: 11),
          ),
        ],
      ),
      if (showHeading) ...[
        const SizedBox(height: 5),
        Text(
          snapshot.location,
          style: JournalPalette.heading.copyWith(fontSize: 18),
        ),
      ],
      const SizedBox(height: 6),
      Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          _status(
            Icons.notifications_outlined,
            snapshot.alarm,
            game.siteAlarm ? _danger : JournalPalette.muted,
          ),
          if (snapshot.cameras)
            _status(Icons.videocam_outlined, 'Working cameras', _teal),
          if (snapshot.response.isNotEmpty)
            _status(Icons.warning_amber_rounded, snapshot.response, _danger),
        ],
      ),
    ],
  );

  Widget _grid(TacticalMapSnapshot snapshot) => LayoutBuilder(
    builder: (context, constraints) {
      final size = fittedFieldPlanSize(
        constraints,
        snapshot.columnCount,
        snapshot.rowCount,
      );
      return Center(
        key: const ValueKey('tactical-plan-fit'),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: movementEnabled
                ? (details) {
                    final cellSize = size.width / snapshot.columnCount;
                    if (cellSize <= 0) return;
                    final column = (details.localPosition.dx / cellSize)
                        .floor();
                    final row = (details.localPosition.dy / cellSize).floor();
                    if (column < 0 ||
                        column >= snapshot.columnCount ||
                        row < 0 ||
                        row >= snapshot.rowCount) {
                      return;
                    }
                    final direction = _adjacentDirection(
                      snapshot,
                      snapshot.cells[row * snapshot.columnCount + column],
                    );
                    if (direction != null) onMove(direction);
                  }
                : null,
            child: CustomPaint(
              key: const ValueKey('tactical-map-grid'),
              painter: TacticalMapPainter(
                snapshot,
                onMove: movementEnabled ? onMove : null,
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _footer(TacticalMapSnapshot snapshot) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Icon(Icons.groups_rounded, color: _teal, size: 17),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Your squad · ${snapshot.currentDescription}',
              style: JournalPalette.small.copyWith(color: JournalPalette.ink),
            ),
          ),
        ],
      ),
      const SizedBox(height: 7),
      const FieldPlanLegend(),
      if (showMovementControls) ...[
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _moveButton('Left', Icons.arrow_back_rounded),
            _moveButton('Up', Icons.arrow_upward_rounded),
            _moveButton('Down', Icons.arrow_downward_rounded),
            _moveButton('Right', Icons.arrow_forward_rounded),
            const Text(
              'Move one tile · arrow keys',
              style: JournalPalette.small,
            ),
          ],
        ),
      ],
    ],
  );

  Widget _moveButton(String direction, IconData icon) => IconButton.outlined(
    key: ValueKey('tactical-move:${direction.toLowerCase()}'),
    tooltip: 'Move ${direction.toLowerCase()}',
    onPressed: movementEnabled ? () => onMove(direction) : null,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      foregroundColor: JournalPalette.ink,
      backgroundColor: JournalPalette.card,
      minimumSize: const Size(44, 44),
      side: const BorderSide(color: JournalPalette.brassDark),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
  );

  Widget _status(IconData icon, String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: 15),
      const SizedBox(width: 5),
      Text(
        label,
        style: JournalPalette.small.copyWith(color: color, fontSize: 11),
      ),
    ],
  );
}

/// Shared legend for the operation and read-only full-floor plan.
class FieldPlanLegend extends StatelessWidget {
  const FieldPlanLegend({super.key});
  @override
  Widget build(BuildContext context) => const Wrap(
    key: ValueKey('field-plan-legend'),
    spacing: 12,
    runSpacing: 5,
    children: [
      _Legend(Icons.door_front_door_rounded, 'Door', _amber),
      _Legend(Icons.exit_to_app_rounded, 'Exit', _teal),
      _Legend(Icons.stairs_rounded, 'Stairs ↑ / ↓', _amber),
      _Legend(Icons.inventory_2_rounded, 'Loot', _amber),
      _Legend(Icons.person_rounded, 'Enemy', _danger),
      _Legend(
        Icons.visibility_off_outlined,
        'Unexplored',
        JournalPalette.muted,
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: JournalPalette.small.copyWith(fontSize: 10.5, height: 1.2),
      ),
    ],
  );
}

String? _adjacentDirection(
  TacticalMapSnapshot snapshot,
  TacticalMapCell target,
) {
  if (target.kind == TacticalTileKind.unknown ||
      target.kind == TacticalTileKind.wall) {
    return null;
  }
  TacticalMapCell? squad;
  for (final cell in snapshot.cells) {
    if (cell.kind == TacticalTileKind.squad) {
      squad = cell;
      break;
    }
  }
  if (squad == null) return null;
  final dx = target.x - squad.x, dy = target.y - squad.y;
  if (dx.abs() + dy.abs() != 1) return null;
  return dx < 0
      ? 'Left'
      : dx > 0
      ? 'Right'
      : dy < 0
      ? 'Up'
      : 'Down';
}

class TacticalMapPainter extends CustomPainter {
  TacticalMapPainter(this.snapshot, {this.onMove});
  final TacticalMapSnapshot snapshot;
  final ValueChanged<String>? onMove;

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / snapshot.columnCount;
    if (cellSize <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = _fog);
    for (int i = 0; i < snapshot.cells.length; i++) {
      final cell = snapshot.cells[i];
      final rect = Rect.fromLTWH(
        (i % snapshot.columnCount) * cellSize,
        (i ~/ snapshot.columnCount) * cellSize,
        cellSize,
        cellSize,
      );
      // Only captured presentation data is available here. Unknown cells always
      // receive the same opaque crosshatch, independent of hidden terrain/units.
      if (cell.kind == TacticalTileKind.unknown) {
        canvas.drawRect(rect, Paint()..color = _fog);
        final hatch = Paint()
          ..color = JournalPalette.rule.withValues(alpha: .28)
          ..strokeWidth = .5;
        canvas.drawLine(
          rect.topLeft + Offset(cellSize * .15, cellSize * .15),
          rect.bottomRight - Offset(cellSize * .15, cellSize * .15),
          hatch,
        );
        canvas.drawLine(
          rect.topRight + Offset(-cellSize * .15, cellSize * .15),
          rect.bottomLeft + Offset(cellSize * .15, -cellSize * .15),
          hatch,
        );
        _gridRule(canvas, rect);
        continue;
      }
      canvas.save();
      canvas.clipRect(rect);
      _terrain(canvas, rect, cell);
      if (cell.restricted) {
        final hatch = Paint()
          ..color = JournalPalette.brassDark.withValues(alpha: .22)
          ..strokeWidth = .7;
        for (double line = -cellSize; line < cellSize; line += cellSize / 3) {
          canvas.drawLine(
            rect.topLeft + Offset(line, 0),
            rect.bottomLeft + Offset(line + cellSize, 0),
            hatch,
          );
        }
      }
      var iconColor = _iconColor(cell);
      if (cell.kind == TacticalTileKind.door) {
        final door = cell.horizontalDoor
            ? Rect.fromCenter(
                center: rect.center,
                width: cellSize * .94,
                height: cellSize * .3,
              )
            : Rect.fromCenter(
                center: rect.center,
                width: cellSize * .3,
                height: cellSize * .94,
              );
        final metal = cell.label == 'Metal door';
        canvas.drawRect(
          door,
          Paint()
            ..color = metal ? const Color(0xFF929788) : const Color(0xFFAD9161),
        );
        canvas.drawRect(
          door.deflate(cellSize * .03),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8
            ..color = JournalPalette.brassDark,
        );
      }
      if (cell.kind == TacticalTileKind.squad) {
        canvas.drawCircle(
          rect.center,
          cellSize * .42,
          Paint()..color = JournalPalette.brassLight,
        );
        canvas.drawCircle(rect.center, cellSize * .34, Paint()..color = _teal);
        canvas.drawCircle(
          rect.center,
          cellSize * .35,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = _paper,
        );
        iconColor = _paper;
      }
      if (cell.kind == TacticalTileKind.enemy ||
          cell.kind == TacticalTileKind.armoredEnemy ||
          cell.kind == TacticalTileKind.woundedEnemy) {
        canvas.drawCircle(
          rect.center,
          cellSize * .35,
          Paint()..color = _danger,
        );
        iconColor = _paper;
      }
      if (cell.icon != null) {
        _drawIcon(
          canvas,
          rect,
          cell.icon!,
          iconColor,
          cellSize * (cell.kind == TacticalTileKind.squad ? .55 : .61),
        );
      }
      if (cell.kind == TacticalTileKind.stairsUp ||
          cell.kind == TacticalTileKind.stairsDown) {
        _drawIcon(
          canvas,
          Rect.fromLTWH(
            rect.right - cellSize * .42,
            rect.top,
            cellSize * .42,
            cellSize * .42,
          ),
          cell.kind == TacticalTileKind.stairsUp
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          _ink,
          cellSize * .31,
        );
      }
      if (cell.burning && cell.kind != TacticalTileKind.fire) {
        canvas.drawCircle(
          rect.bottomRight - Offset(cellSize * .18, cellSize * .18),
          cellSize * .1,
          Paint()..color = _danger,
        );
      }
      if (onMove != null && _adjacentDirection(snapshot, cell) != null) {
        canvas.drawRect(
          rect.deflate(cellSize * .08),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(.8, cellSize * .045)
            ..color = _teal,
        );
      }
      _gridRule(canvas, rect);
      canvas.restore();
    }
  }

  void _gridRule(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .55
        ..color = JournalPalette.brassDark.withValues(alpha: .3),
    );
  }

  void _terrain(Canvas canvas, Rect rect, TacticalMapCell cell) {
    final faded = !cell.visible;
    final fill = cell.kind == TacticalTileKind.wall
        ? _wall
        : cell.kind == TacticalTileKind.grass
        ? const Color(0xFFC7CFAB)
        : cell.kind == TacticalTileKind.debris
        ? const Color(0xFFDAD1B9)
        : _paper;
    canvas.drawRect(
      rect,
      Paint()..color = faded ? Color.lerp(fill, _fog, .35)! : fill,
    );
    final detail = Paint()
      ..color = JournalPalette.brassDark.withValues(alpha: faded ? .18 : .32)
      ..strokeWidth = math.max(.5, rect.width * .02);
    if (cell.kind == TacticalTileKind.wall) {
      // A masonry plan symbol, rather than additional engine terrain metadata.
      final mid = rect.center.dy;
      canvas.drawLine(Offset(rect.left, mid), Offset(rect.right, mid), detail);
      canvas.drawLine(
        Offset(rect.center.dx, rect.top),
        Offset(rect.center.dx, mid),
        detail,
      );
      canvas.drawLine(
        Offset(rect.left + rect.width * .25, mid),
        Offset(rect.left + rect.width * .25, rect.bottom),
        detail,
      );
      if (cell.label == 'Bloodstained wall') {
        canvas.drawCircle(
          rect.center,
          rect.width * .18,
          Paint()..color = _danger.withValues(alpha: .55),
        );
      }
    } else if (cell.kind == TacticalTileKind.grass) {
      for (final x in [.27, .65]) {
        final stem = Offset(
          rect.left + rect.width * x,
          rect.bottom - rect.height * .2,
        );
        canvas.drawLine(
          stem,
          stem - Offset(rect.width * .08, rect.height * .35),
          detail,
        );
        canvas.drawLine(
          stem,
          stem + Offset(rect.width * .1, -rect.height * .3),
          detail,
        );
      }
    } else if (cell.kind == TacticalTileKind.debris) {
      canvas.drawPath(
        Path()
          ..moveTo(rect.left + rect.width * .2, rect.top + rect.height * .6)
          ..lineTo(rect.left + rect.width * .42, rect.top + rect.height * .35)
          ..lineTo(rect.left + rect.width * .6, rect.top + rect.height * .7)
          ..close(),
        Paint()..color = JournalPalette.muted.withValues(alpha: .4),
      );
      canvas.drawCircle(
        rect.topRight + Offset(-rect.width * .23, rect.height * .3),
        rect.width * .07,
        Paint()..color = JournalPalette.brassDark,
      );
    } else {
      canvas.drawLine(
        Offset(rect.left + rect.width * .12, rect.bottom - rect.height * .17),
        Offset(rect.right - rect.width * .12, rect.bottom - rect.height * .17),
        detail..color = JournalPalette.rule.withValues(alpha: .22),
      );
    }
  }

  Color _iconColor(TacticalMapCell cell) {
    final hazardous =
        cell.color == _danger ||
        cell.burning ||
        cell.kind == TacticalTileKind.fire ||
        cell.kind == TacticalTileKind.blood ||
        cell.label.contains('Bloodstained') ||
        cell.label == 'CCS graffiti' ||
        cell.label.contains('cannot unlock');
    if (hazardous) return _danger;
    if (cell.kind == TacticalTileKind.exit ||
        cell.kind == TacticalTileKind.grass ||
        cell.label == 'LCS graffiti') {
      return _teal;
    }
    return cell.visible ? JournalPalette.brassDark : JournalPalette.muted;
  }

  void _drawIcon(
    Canvas canvas,
    Rect rect,
    IconData icon,
    Color color,
    double size,
  ) {
    final text = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: math.max(7, size),
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, rect.center - Offset(text.width / 2, text.height / 2));
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final cellSize = size.width / snapshot.columnCount;
    return [
      for (int i = 0; i < snapshot.cells.length; i++)
        if (snapshot.cells[i].kind != TacticalTileKind.unknown)
          CustomPainterSemantics(
            rect: Rect.fromLTWH(
              (i % snapshot.columnCount) * cellSize,
              (i ~/ snapshot.columnCount) * cellSize,
              cellSize,
              cellSize,
            ),
            properties: SemanticsProperties(
              label:
                  '${snapshot.cells[i].label}, '
                  'column ${snapshot.cells[i].x + 1}, '
                  'row ${snapshot.cells[i].y + 1}',
              textDirection: TextDirection.ltr,
              button:
                  onMove != null &&
                  _adjacentDirection(snapshot, snapshot.cells[i]) != null,
              onTap:
                  onMove != null &&
                      _adjacentDirection(snapshot, snapshot.cells[i]) != null
                  ? () => onMove!(
                      _adjacentDirection(snapshot, snapshot.cells[i])!,
                    )
                  : null,
            ),
          ),
    ];
  };

  @override
  bool shouldRepaint(covariant TacticalMapPainter oldDelegate) => true;

  @override
  bool shouldRebuildSemantics(covariant TacticalMapPainter oldDelegate) => true;
}
