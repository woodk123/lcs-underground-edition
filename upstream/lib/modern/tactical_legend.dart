import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_snapshot.dart';
import 'package:lcs_new_age/modern/tactical_symbols.dart';

/// The compact field-plan key and its scrollable, complete reference.
/// [art] may borrow the map's decoded atlases; otherwise the shared cache is used.
class FieldPlanLegend extends StatefulWidget {
  const FieldPlanLegend({super.key, this.art, this.showPrimary = true});

  final TacticalArt? art;
  final bool showPrimary;

  @override
  State<FieldPlanLegend> createState() => _FieldPlanLegendState();
}

class _FieldPlanLegendState extends State<FieldPlanLegend> {
  bool _showingKey = false;

  Future<void> _openKey() async {
    if (_showingKey) return;
    setState(() => _showingKey = true);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('field-plan-key-dialog'),
          backgroundColor: JournalPalette.card,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 20,
          ),
          title: const Text('Tactical map key', style: JournalPalette.heading),
          content: SizedBox(
            width: 600,
            child: TacticalArtwork(
              builder: (context, loaded) => Scrollbar(
                child: SingleChildScrollView(
                  key: const ValueKey('field-plan-key-scroll'),
                  child: _FullKey(art: widget.art ?? loaded),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('field-plan-key-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close map key'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _showingKey = false);
    }
  }

  Widget _compact(TacticalArt? art) => Wrap(
    key: const ValueKey('field-plan-legend'),
    spacing: 11,
    runSpacing: 5,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      if (widget.showPrimary)
        for (final entry in _primary)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: CustomPaint(
                  size: const Size(18, 18),
                  painter: _MarkPainter(entry, art),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                entry.title,
                style: JournalPalette.small.copyWith(
                  fontSize: 10.5,
                  height: 1.2,
                ),
              ),
            ],
          ),
      TextButton(
        key: const ValueKey('field-plan-key-open'),
        onPressed: _showingKey ? null : _openKey,
        style: TextButton.styleFrom(
          foregroundColor: JournalPalette.olive,
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          minimumSize: const Size(44, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: JournalPalette.small.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
          ),
        ),
        child: const Text('Map key'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => widget.art != null
      ? _compact(widget.art)
      : TacticalArtwork(builder: (context, art) => _compact(art));
}

const _primary = [
  _Entry('Your squad', TacticalTileKind.squad),
  _Entry('Door', TacticalTileKind.door),
  _Entry('Exit', TacticalTileKind.exit),
  _Entry('Stairs up / down', TacticalTileKind.stairsUp),
  _Entry('Loot', TacticalTileKind.loot),
  _Entry('Unexplored', TacticalTileKind.unknown),
];

const _navigation = [
  _Entry(
    'Your squad',
    TacticalTileKind.squad,
    detail: 'Your current position; the green circle contains the whole squad.',
  ),
  _Entry(
    'Door',
    TacticalTileKind.door,
    detail: 'The bar shows the door’s orientation.',
  ),
  _Entry(
    'Locked door',
    TacticalTileKind.door,
    locked: true,
    detail: 'A discovered lock. Unknown lock states are not shown.',
  ),
  _Entry(
    'Cannot unlock door',
    TacticalTileKind.door,
    blocked: true,
    locked: true,
    detail: 'The red cross marks a lock the squad cannot unlock.',
  ),
  _Entry(
    'Metal door',
    TacticalTileKind.door,
    metal: true,
    detail: 'A reinforced door with metal plates and rivets.',
  ),
  _Entry(
    'Burning door',
    TacticalTileKind.door,
    burning: true,
    detail: 'The flame badge marks a burning door.',
  ),
  _Entry('Exit', TacticalTileKind.exit, detail: 'A way out of the site.'),
  _Entry('Stairs up', TacticalTileKind.stairsUp),
  _Entry('Stairs down', TacticalTileKind.stairsDown),
];

const _threats = [
  _Entry(
    'Siege enemy',
    TacticalTileKind.enemy,
    detail: 'A visible siege unit, shown as a red diamond.',
  ),
  _Entry(
    'Wounded siege enemy',
    TacticalTileKind.woundedEnemy,
    detail: 'A damaged siege unit; the clipped shape carries a medical cross.',
  ),
  _Entry(
    'Armored siege enemy',
    TacticalTileKind.armoredEnemy,
    detail: 'A heavy siege unit, shown as a shield with a tracked vehicle.',
  ),
];

const _objects = [
  _Entry(
    'Loot',
    TacticalTileKind.loot,
    detail: 'A crate marks loot on a known tile.',
  ),
  _Entry(
    'Point of interest',
    TacticalTileKind.special,
    detail:
        'A brass corner dot identifies a special site feature. Inspect the tile for its exact name and use / interact instructions.',
  ),
  _Entry(
    'Restricted area',
    TacticalTileKind.floor,
    restricted: true,
    detail: 'Diagonal hatching marks restricted ground.',
  ),
  _Entry(
    'Fire',
    TacticalTileKind.fire,
    detail: 'Flames mark a burning tile; glowing embers mark dying fire.',
  ),
  _Entry(
    'Defensive booby trap',
    TacticalTileKind.trap,
    detail: 'A known defensive trap on this tile; inspect it for details.',
  ),
  _Entry(
    'Bloodstains',
    TacticalTileKind.blood,
    detail: 'Blood is an overlay on the known surface.',
  ),
  _Entry(
    'Debris',
    TacticalTileKind.debris,
    detail: 'Rubble left on the floor.',
  ),
];

const _visibility = [
  _Entry(
    'In view',
    TacticalTileKind.floor,
    detail: 'Known ground currently seen by the squad or working cameras.',
  ),
  _Entry(
    'Previously explored',
    TacticalTileKind.floor,
    remembered: true,
    detail:
        'Remembered ground is dimmed. Siege units outside current visibility are hidden.',
  ),
  _Entry(
    'Unexplored',
    TacticalTileKind.unknown,
    detail:
        'Opaque parchment hides terrain, objects, hazards, and units until discovered.',
  ),
];

const _rooms = [
  _Entry(
    'Detention room',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.detentionCell,
  ),
  _Entry(
    'Patient’s room',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.nursingBed,
  ),
  _Entry(
    'Patient’s room · visited',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.nursingBed,
    visited: true,
    detail: 'The green check records a patient room already visited.',
  ),
  _Entry(
    'Executive office',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.executiveDesk,
  ),
  _Entry(
    'President’s office',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.presidentialDesk,
  ),
  _Entry(
    'Bank teller',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.tellerCounter,
  ),
  _Entry(
    'Bank vault',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.bankVault,
  ),
  _Entry(
    'Jury room',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.juryTable,
  ),
  _Entry(
    'Sign',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.signboard,
    detail: 'Stand on the sign tile and use / interact to read its wording.',
  ),
  _Entry(
    'News studio',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.tvCamera,
  ),
  _Entry(
    'Supercomputer',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.serverRack,
  ),
  _Entry(
    'Textile equipment',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.sewingMachine,
  ),
  _Entry(
    'Reactor control room',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.reactorConsole,
  ),
  _Entry(
    'Armory',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.weaponRack,
  ),
  _Entry(
    'Prison control room',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.prisonConsole,
  ),
  _Entry(
    'Manager / landlord office',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.officeDesk,
  ),
  _Entry(
    'Claims terminal',
    TacticalTileKind.special,
    objectSprite: TacticalObjectCell.claimsTerminal,
  ),
  _Entry('LCS graffiti', TacticalTileKind.wall, graffiti: TacticalGraffiti.lcs),
  _Entry('CCS graffiti', TacticalTileKind.wall, graffiti: TacticalGraffiti.ccs),
  _Entry(
    'Other graffiti',
    TacticalTileKind.wall,
    graffiti: TacticalGraffiti.other,
  ),
];

class _Entry {
  const _Entry(
    this.title,
    this.kind, {
    this.detail,
    this.locked = false,
    this.blocked = false,
    this.metal = false,
    this.burning = false,
    this.restricted = false,
    this.remembered = false,
    this.objectSprite,
    this.graffiti,
    this.visited = false,
  });
  final String title;
  final TacticalTileKind kind;
  final String? detail;
  final bool locked, blocked, metal, burning, restricted, remembered;
  final int? objectSprite;
  final TacticalGraffiti? graffiti;
  final bool visited;
}

class _FullKey extends StatelessWidget {
  const _FullKey({required this.art});
  final TacticalArt? art;

  Widget _section(String title, List<_Entry> entries) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 18),
      Text(
        title,
        style: JournalPalette.small.copyWith(
          fontWeight: FontWeight.w700,
          color: JournalPalette.ink,
        ),
      ),
      const Divider(color: JournalPalette.rule, height: 14),
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: CustomPaint(
                  size: const Size(34, 34),
                  painter: _MarkPainter(entry, art),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: JournalPalette.small.copyWith(
                        fontWeight: FontWeight.w700,
                        color: JournalPalette.ink,
                      ),
                    ),
                    if (entry.detail != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        entry.detail!,
                        style: JournalPalette.small.copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Map foe tokens show visible siege units only. Other people appear in the encounter list beside the map; they do not have plotted map positions.',
        style: JournalPalette.small,
      ),
      _section('Your squad and navigation', _navigation),
      _section('Siege threats', _threats),
      _section('Objects and hazards', _objects),
      _section('Rooms and equipment', _rooms),
      _section('Visibility', _visibility),
    ],
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.entry, this.art);
  final _Entry entry;
  final TacticalArt? art;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (entry.kind == TacticalTileKind.unknown) {
      TacticalSymbols.drawFog(canvas, rect);
      return;
    }
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = JournalPalette.card);
    art?.drawTerrain(
      canvas,
      rect,
      entry.graffiti != null
          ? TacticalTerrainCell.brickWall
          : TacticalTerrainCell.studioCarpet,
      opacity: entry.graffiti != null ? .72 : .52,
    );
    switch (entry.kind) {
      case TacticalTileKind.squad:
        TacticalSymbols.drawUnit(canvas, rect, kind: TacticalUnitSymbol.squad);
      case TacticalTileKind.enemy:
        TacticalSymbols.drawUnit(canvas, rect, kind: TacticalUnitSymbol.enemy);
      case TacticalTileKind.woundedEnemy:
        TacticalSymbols.drawUnit(
          canvas,
          rect,
          kind: TacticalUnitSymbol.wounded,
        );
      case TacticalTileKind.armoredEnemy:
        TacticalSymbols.drawUnit(
          canvas,
          rect,
          kind: TacticalUnitSymbol.armored,
        );
      case TacticalTileKind.door:
        TacticalSymbols.drawDoor(
          canvas,
          rect,
          horizontal: true,
          locked: entry.locked,
          blocked: entry.blocked,
          metal: entry.metal,
          burning: entry.burning,
        );
      case TacticalTileKind.exit:
        TacticalSymbols.drawExit(canvas, rect);
      case TacticalTileKind.stairsUp || TacticalTileKind.stairsDown:
        TacticalSymbols.drawStairs(
          canvas,
          rect,
          up: entry.kind == TacticalTileKind.stairsUp,
        );
      case TacticalTileKind.loot:
        if (art != null) {
          art!.drawObject(
            canvas,
            rect.deflate(rect.width * .04),
            TacticalObjectCell.crate,
          );
        } else {
          TacticalSymbols.drawLoot(canvas, rect);
        }
      case TacticalTileKind.special:
        art?.drawObject(
          canvas,
          rect.deflate(rect.width * .04),
          entry.objectSprite ?? TacticalObjectCell.radioConsole,
        );
        if (art != null && entry.objectSprite == TacticalObjectCell.signboard) {
          TacticalSymbols.drawSignLettering(canvas, rect);
        }
        if (!entry.visited) {
          canvas.drawCircle(
            rect.topRight + Offset(-rect.width * .13, rect.height * .13),
            rect.width * .07,
            Paint()..color = JournalPalette.brassDark,
          );
        }
      case TacticalTileKind.fire:
        if (art != null) {
          art!.drawHazard(
            canvas,
            rect.deflate(rect.width * .04),
            TacticalHazardCell.spreadingFire,
          );
        } else {
          TacticalSymbols.drawFire(canvas, rect);
        }
      case TacticalTileKind.trap:
        if (art != null) {
          art!.drawHazard(
            canvas,
            rect.deflate(rect.width * .04),
            TacticalHazardCell.trap,
          );
        } else {
          TacticalSymbols.drawTrap(canvas, rect);
        }
        TacticalSymbols.drawTrapMarker(canvas, rect);
      case TacticalTileKind.blood:
        if (art != null) {
          art!.drawHazard(canvas, rect, TacticalHazardCell.heavyBlood);
        } else {
          canvas.drawCircle(
            rect.center,
            rect.width * .18,
            Paint()..color = JournalPalette.danger,
          );
        }
      case TacticalTileKind.debris:
        if (art != null) {
          art!.drawHazard(canvas, rect, TacticalHazardCell.rubble);
        }
      default:
        break;
    }
    if (entry.graffiti != null) {
      TacticalSymbols.drawGraffiti(canvas, rect, entry.graffiti!);
    }
    if (entry.visited) {
      TacticalSymbols.drawVisitedMarker(canvas, rect);
    }
    if (entry.restricted) {
      final hatch = Paint()
        ..color = JournalPalette.brassDark.withValues(alpha: .28)
        ..strokeWidth = .8;
      for (
        double line = -rect.width;
        line < rect.width;
        line += rect.width / 3
      ) {
        canvas.drawLine(
          rect.topLeft + Offset(line, 0),
          rect.bottomLeft + Offset(line + rect.width, 0),
          hatch,
        );
      }
    }
    if (entry.remembered) {
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xFFD4CFB7).withValues(alpha: .42),
      );
    }
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..color = JournalPalette.brassDark.withValues(alpha: .25),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) =>
      oldDelegate.entry != entry || oldDelegate.art != art;
}
