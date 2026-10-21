import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/tactical_snapshot.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

const _symbols = {
  TacticalTileKind.unknown: '?',
  TacticalTileKind.squad: '@',
  TacticalTileKind.wall: '#',
  TacticalTileKind.door: '+',
  TacticalTileKind.armoredEnemy: 'A',
  TacticalTileKind.enemy: 'E',
  TacticalTileKind.woundedEnemy: 'e',
  TacticalTileKind.stairsUp: '<',
  TacticalTileKind.stairsDown: '>',
  TacticalTileKind.exit: 'X',
  TacticalTileKind.fire: '!',
  TacticalTileKind.special: '*',
  TacticalTileKind.trap: '^',
  TacticalTileKind.loot: r'$',
  TacticalTileKind.blood: '~',
  TacticalTileKind.grass: ',',
  TacticalTileKind.debris: ':',
  TacticalTileKind.floor: '.',
};

/// Reuse the graphical map's already-known/visible snapshot, never raw hidden
/// tiles or a new visibility calculation. Source choices remain authoritative.
Map<String, dynamic>? tacticalObservation(
  Console console,
  List<Map<String, dynamic>> actions,
) {
  if (game.mode != GameMode.site ||
      game.activeSite == null ||
      !const {
        'tactical',
        'field_prompt',
        'full_map',
      }.contains(console.screen)) {
    return null;
  }
  final snapshot = TacticalMapSnapshot.capture(
    fullMap: console.screen == 'full_map',
  );
  final position = displayedSquadPosition;
  final cells = {for (final cell in snapshot.cells) (cell.x, cell.y): cell};
  const offsets = {
    'Left': (-1, 0),
    'Right': (1, 0),
    'Up': (0, -1),
    'Down': (0, 1),
  };
  final movement = <Map<String, dynamic>>[];
  for (final action in actions) {
    final offset = offsets[action['key']];
    if (offset == null || action['entityType'] != 'field-direction') continue;
    final x = position.x + offset.$1, y = position.y + offset.$2;
    final cell = cells[(x, y)];
    final terrain =
        cell?.underlyingKind ?? cell?.kind ?? TacticalTileKind.unknown;
    movement.add({
      'actionId': action['id'],
      'key': action['key'],
      'enabled': action['enabled'],
      'target': {'x': x, 'y': y, 'z': snapshot.floor},
      'terrain': terrain.name,
      'obstacle': switch (terrain) {
        TacticalTileKind.unknown => 'unknown',
        TacticalTileKind.wall => 'wall',
        TacticalTileKind.door => 'door',
        _ => 'none',
      },
    });
  }
  return {
    'siteId': game.activeSite!.id,
    'location': snapshot.location,
    'position': {'x': position.x, 'y': position.y, 'z': snapshot.floor},
    'xStart': snapshot.xStart,
    'yStart': snapshot.yStart,
    'width': snapshot.columnCount,
    'height': snapshot.rowCount,
    'alarm': snapshot.alarm,
    'response': snapshot.response,
    'currentDescription': snapshot.currentDescription,
    'legend': {
      for (final entry in _symbols.entries) entry.value: entry.key.name,
    },
    'ascii': [
      for (var row = 0; row < snapshot.rowCount; row++)
        snapshot.cells
            .skip(row * snapshot.columnCount)
            .take(snapshot.columnCount)
            .map((cell) => _symbols[cell.kind])
            .join(),
    ].join('\n'),
    'cells': [
      for (final cell in snapshot.cells)
        if (cell.kind != TacticalTileKind.unknown)
          {
            'x': cell.x,
            'y': cell.y,
            'kind': cell.kind.name,
            'terrain': (cell.underlyingKind ?? cell.kind).name,
            'label': cell.semanticLabel,
            'visible': cell.visible,
            'restricted': cell.restricted,
            'lootAvailable': cell.lootAvailable,
            if (cell.actionHint.isNotEmpty) 'actionHint': cell.actionHint,
          },
    ],
    'movement': movement,
    'note':
        'Only the graphical snapshot\'s known cells. Unknown cells are ?. Movement entries retain current source actions; terrain is not a prediction of the action outcome.',
  };
}
