import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_snapshot.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

TacticalMapCell _cellAt(TacticalMapSnapshot snapshot, int x, int y) =>
    snapshot.cells.singleWhere((cell) => cell.x == x && cell.y == y);

SiteTile _replaceCurrent() => levelMap[game.locx][game.locy][game.locz] =
    SiteTile(game.locx, game.locy, game.locz)
      ..known = true
      ..inLOS = true;

TacticalMapCell _squad(TacticalMapSnapshot snapshot) =>
    _cellAt(snapshot, game.locx, game.locy);

void main() {
  setUp(() {
    game.gameState = game.GameState();
    game.locx = 35;
    game.locy = 11;
    game.locz = 0;
    game.siteAlarmTimer = -1;
    levelMap = List.generate(
      MAPX,
      (x) => List.generate(
        MAPY,
        (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
      ),
    );
    _replaceCurrent();
  });

  test('unexplored tiles expose no underlying content or action metadata', () {
    final hidden = levelMap[36][11][0]
      ..special = TileSpecial.ceoSafe
      ..wall = true
      ..door = true
      ..locked = true
      ..knownLock = true
      ..outdoor = true
      ..grass = true
      ..loot = true
      ..debris = true
      ..restricted = true
      ..firePeak = true
      ..megaBloody = true
      ..siegeTrap = true
      ..siegeHeavyUnit = true
      ..inLOS = true;
    final cell = _cellAt(TacticalMapSnapshot.capture(), 36, 11);
    expect(cell.kind, TacticalTileKind.unknown);
    expect(cell.label, 'Unexplored');
    expect(cell.featureLabel, 'Unexplored');
    expect(cell.semanticLabel, 'Unexplored');
    expect(cell.underlyingKind, isNull);
    expect(cell.underlyingLabel, isNull);
    expect(cell.objectSprite, isNull);
    expect(cell.hazardSprite, isNull);
    expect(cell.groundSprite, isNull);
    expect(cell.hazardLabel, isNull);
    expect(cell.actionHint, isEmpty);
    expect(cell.pointOfInterest, isFalse);
    expect(cell.restricted, isFalse);
    expect(cell.burning, isFalse);
    expect(cell.visible, isFalse);
    expect(cell.horizontalDoor, isFalse);
    expect(hidden.known, isFalse);
  });

  test(
    'squad retains a safe, fire, restriction and manual-use instruction',
    () {
      _replaceCurrent()
        ..special = TileSpecial.ceoSafe
        ..firePeak = true
        ..restricted = true;
      final snapshot = TacticalMapSnapshot.capture();
      final cell = _squad(snapshot);
      expect(cell.kind, TacticalTileKind.squad);
      expect(cell.label, 'Squad');
      expect(cell.underlyingKind, TacticalTileKind.special);
      expect(cell.featureLabel, 'Safe');
      expect(cell.objectSprite, TacticalObjectCell.safe);
      expect(cell.hazardSprite, TacticalHazardCell.intenseFire);
      expect(cell.hazardLabel, 'Intense fire');
      expect(cell.burning, isTrue);
      expect(cell.restricted, isTrue);
      expect(cell.pointOfInterest, isTrue);
      expect(cell.actionHint, contains('press U'));
      expect(snapshot.currentDescription, 'Safe · Fire · Restricted area');
      expect(cell.semanticLabel, contains('Squad · Safe'));
      expect(cell.semanticLabel, contains('In view'));
      expect(cell.semanticLabel, contains('Restricted area'));
      expect(cell.semanticLabel, contains('Intense fire'));
      expect(cell.semanticLabel, contains(cell.actionHint));
    },
  );

  test('squad retains both stair directions and U changes floors', () {
    for (final (special, kind, description, hint) in [
      (
        TileSpecial.stairsUp,
        TacticalTileKind.stairsUp,
        'Stairs up',
        'upstairs',
      ),
      (
        TileSpecial.stairsDown,
        TacticalTileKind.stairsDown,
        'Stairs down',
        'downstairs',
      ),
    ]) {
      _replaceCurrent().special = special;
      final snapshot = TacticalMapSnapshot.capture();
      final cell = _squad(snapshot);
      expect(cell.kind, TacticalTileKind.squad);
      expect(cell.underlyingKind, kind);
      expect(cell.featureLabel, description);
      expect(cell.pointOfInterest, isTrue);
      expect(cell.actionHint, contains('press U'));
      expect(cell.actionHint, contains(hint));
      expect(snapshot.currentDescription, description);
      expect(game.locz, 0, reason: 'Capture must not use the stairs.');
    }
  });

  test('loot beneath the squad retains its sprite and G instruction', () {
    _replaceCurrent().loot = true;
    final snapshot = TacticalMapSnapshot.capture();
    final cell = _squad(snapshot);
    expect(cell.kind, TacticalTileKind.squad);
    expect(cell.underlyingKind, TacticalTileKind.loot);
    expect(cell.featureLabel, 'Loot');
    expect(cell.objectSprite, TacticalObjectCell.crate);
    expect(cell.pointOfInterest, isFalse);
    expect(cell.actionHint, contains('press G'));
    expect(cell.actionHint, isNot(contains('press U')));
    expect(snapshot.currentDescription, 'Loot');
  });

  test('squad on defensive trap is not told it is a movement hazard', () {
    final tile = _replaceCurrent()..siegeTrap = true;
    final snapshot = TacticalMapSnapshot.capture();
    final cell = _squad(snapshot);
    expect(cell.underlyingKind, TacticalTileKind.trap);
    expect(cell.featureLabel, 'Defensive boobytrap');
    expect(cell.hazardSprite, TacticalHazardCell.trap);
    expect(cell.actionHint, contains('against siege enemies'));
    expect(cell.actionHint, contains('squad movement does not trigger it'));
    expect(snapshot.currentDescription, 'Defensive boobytrap');
    expect(tile.siegeTrap, isTrue, reason: 'Capture must not trigger traps.');
  });

  test(
    'squad floor description retains grass, debris, blood and restriction',
    () {
      _replaceCurrent()
        ..grass = true
        ..debris = true
        ..bloody = true
        ..restricted = true;
      final snapshot = TacticalMapSnapshot.capture();
      final cell = _squad(snapshot);
      expect(cell.groundSprite, TacticalTerrainCell.grass);
      expect(cell.hazardSprite, TacticalHazardCell.rubble);
      expect(cell.restricted, isTrue);
      expect(cell.hazardLabel, contains('Bloodstained grass'));
      expect(snapshot.currentDescription, contains('Debris'));
      expect(snapshot.currentDescription, contains('Bloodstained grass'));
      expect(snapshot.currentDescription, contains('Restricted area'));
      expect(snapshot.currentDescription, isNot(contains('Open floor')));
    },
  );

  test('visible siege units retain underlying objects and fire', () {
    final tile = levelMap[36][11][0]
      ..known = true
      ..inLOS = true
      ..siegeUnit = true
      ..special = TileSpecial.corporateFiles
      ..restricted = true
      ..fireStart = true;
    var cell = _cellAt(TacticalMapSnapshot.capture(), 36, 11);
    expect(cell.kind, TacticalTileKind.enemy);
    expect(cell.underlyingKind, TacticalTileKind.special);
    expect(cell.featureLabel, 'Corporate files');
    expect(cell.objectSprite, TacticalObjectCell.files);
    expect(cell.hazardSprite, TacticalHazardCell.spreadingFire);
    expect(cell.restricted, isTrue);
    expect(cell.burning, isTrue);
    expect(cell.semanticLabel, contains('Enemy · Corporate files'));
    tile.inLOS = false;
    cell = _cellAt(TacticalMapSnapshot.capture(), 36, 11);
    expect(cell.kind, TacticalTileKind.fire);
    expect(cell.underlyingKind, TacticalTileKind.special);
    expect(cell.featureLabel, 'Corporate files');
    expect(cell.semanticLabel, contains('Previously explored'));
    expect(cell.semanticLabel, isNot(contains('Enemy')));
  });

  test('legacy terminal in a wall has no fixture art or interaction hint', () {
    final tile = levelMap[36][11][0]
      ..known = true
      ..wall = true
      ..special = TileSpecial.insuranceClaimsTerminal;
    reseedRNG(seed: 915);
    final expectedRoll = lcsRandom(100000);
    reseedRNG(seed: 915);
    for (final fullMap in [false, true]) {
      final cell = _cellAt(
        TacticalMapSnapshot.capture(fullMap: fullMap),
        36,
        11,
      );
      expect(cell.kind, TacticalTileKind.wall);
      expect(cell.objectSprite, isNull);
      expect(cell.pointOfInterest, isFalse);
      expect(cell.actionHint, 'Solid wall. You cannot move onto this tile.');
      expect(cell.semanticLabel, isNot(contains('press U')));
    }
    expect(tile.wall, isTrue);
    expect(tile.special, TileSpecial.insuranceClaimsTerminal);
    expect(lcsRandom(100000), expectedRoll);
  });

  test('hidden neighboring marks do not decorate a known wall', () {
    levelMap[36][11][0]
      ..known = true
      ..wall = true;
    final neighbor = levelMap[37][11][0]
      ..megaBloody = true
      ..graffitiLCS = true
      ..graffitiCCS = true
      ..graffitiOther = true;
    var cell = _cellAt(TacticalMapSnapshot.capture(), 36, 11);
    expect(cell.label, 'Wall');
    expect(cell.icon, isNull);
    expect(cell.hazardSprite, isNull);
    neighbor.known = true;
    cell = _cellAt(TacticalMapSnapshot.capture(), 36, 11);
    expect(cell.label, 'Bloodstained wall');
    neighbor.megaBloody = false;
    expect(
      _cellAt(TacticalMapSnapshot.capture(), 36, 11).label,
      'LCS graffiti',
    );
  });

  test('door orientation ignores hidden neighboring walls', () {
    levelMap[36][12][0]
      ..known = true
      ..door = true;
    final left = levelMap[35][12][0]..wall = true;
    levelMap[37][12][0].wall = true;
    var cell = _cellAt(TacticalMapSnapshot.capture(), 36, 12);
    expect(cell.horizontalDoor, isFalse);
    expect(cell.actionHint, contains('try the door'));
    expect(cell.actionHint, contains('leaves the squad in place'));
    left.known = true;
    cell = _cellAt(TacticalMapSnapshot.capture(), 36, 12);
    expect(cell.horizontalDoor, isTrue);
  });

  test(
    'manual-use specials and entry fixtures give different instructions',
    () {
      final tile = levelMap[36][11][0]..known = true;
      for (final special in [
        TileSpecial.ceoSafe,
        TileSpecial.radioBroadcastStudio,
        TileSpecial.signOne,
        TileSpecial.policeStationLockup,
        TileSpecial.nursingHomePatient,
      ]) {
        tile.special = special;
        final cell = _cellAt(TacticalMapSnapshot.capture(), 36, 11);
        expect(cell.pointOfInterest, isTrue);
        expect(cell.actionHint, contains('press U'));
      }
      for (final special in [
        TileSpecial.computer,
        TileSpecial.table,
        TileSpecial.tent,
        TileSpecial.parkBench,
        TileSpecial.securityCheckpoint,
        TileSpecial.clubBouncerSecondVisit,
        TileSpecial.ceoOffice,
        TileSpecial.bankTeller,
      ]) {
        tile.special = special;
        final cell = _cellAt(TacticalMapSnapshot.capture(), 36, 11);
        expect(cell.pointOfInterest, isTrue);
        expect(cell.actionHint, contains('on entry'));
        expect(cell.actionHint, contains('U does not activate'));
        expect(cell.actionHint, isNot(contains('press U')));
      }
      tile
        ..special = TileSpecial.none
        ..exit = true;
      expect(
        _cellAt(TacticalMapSnapshot.capture(), 36, 11).actionHint,
        'Entering this tile leaves the site.',
      );
    },
  );

  test('every known special remains a point of interest under the squad', () {
    final tile = _replaceCurrent();
    for (final special in TileSpecial.values.where(
      (special) => special != TileSpecial.none,
    )) {
      tile.special = special;
      final cell = _squad(TacticalMapSnapshot.capture());
      expect(cell.kind, TacticalTileKind.squad);
      expect(cell.pointOfInterest, isTrue, reason: special.name);
      expect(cell.featureLabel, isNot('Squad'), reason: special.name);
      expect(cell.actionHint, isNotEmpty, reason: special.name);
    }
  });

  test('capture copies presentation state and consumes no campaign RNG', () {
    final tile = _replaceCurrent()
      ..special = TileSpecial.ceoSafe
      ..firePeak = true
      ..restricted = true;
    final before = (tile.flag, tile.siegeflag, tile.special, tile.inLOS);
    reseedRNG(seed: 41917);
    final expectedRoll = lcsRandom(1000000);
    reseedRNG(seed: 41917);
    final snapshot = TacticalMapSnapshot.capture();
    expect(lcsRandom(1000000), expectedRoll);
    expect((tile.flag, tile.siegeflag, tile.special, tile.inLOS), before);
    final captured = _squad(snapshot);
    tile
      ..special = TileSpecial.none
      ..firePeak = false
      ..restricted = false;
    expect(captured.featureLabel, 'Safe');
    expect(captured.burning, isTrue);
    expect(captured.restricted, isTrue);
    expect(captured.semanticLabel, contains('Safe'));
    expect(captured.semanticLabel, contains('Intense fire'));
    expect(() => snapshot.cells.add(captured), throwsUnsupportedError);
  });
}
