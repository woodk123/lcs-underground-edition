import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_legend.dart';
import 'package:lcs_new_age/modern/tactical_snapshot.dart';
import 'package:lcs_new_age/modern/tactical_symbols.dart';

export 'package:lcs_new_age/modern/tactical_legend.dart';
export 'package:lcs_new_age/modern/tactical_snapshot.dart';

const _ink = JournalPalette.ink;
const _fog = Color(0xFFD4CFB7);
const _wall = Color(0xFF8E8774);
const _teal = JournalPalette.olive;
const _danger = JournalPalette.danger;
const _paper = JournalPalette.card;

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

class TacticalMapView extends StatefulWidget {
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
  State<TacticalMapView> createState() => _TacticalMapViewState();
}

class _TacticalMapViewState extends State<TacticalMapView> {
  final _transform = TransformationController();
  (int, int, int)? _hovered, _selected;
  Object? _cameraKey;
  bool _inspectMode = false, _fit = false;
  double? _chosenScale;
  Size _viewport = Size.zero;
  double _fitScale = 1;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  TacticalMapCell? _inspected(TacticalMapSnapshot snapshot) {
    final position = _hovered ?? _selected;
    if (position != null && position.$3 == snapshot.floor) {
      for (final cell in snapshot.cells) {
        if (cell.x == position.$1 && cell.y == position.$2) return cell;
      }
    }
    for (final cell in snapshot.cells) {
      if (cell.kind == TacticalTileKind.squad) return cell;
    }
    return null;
  }

  void _zoom(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      _fitScale,
      5.0,
    );
    final oldScale = _transform.value.getMaxScaleOnAxis();
    if (oldScale <= 0) return;
    final ratio = scale / oldScale;
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final old = _transform.value;
    final next = Matrix4.diagonal3Values(scale, scale, 1);
    next[12] = center.dx - (center.dx - old[12]) * ratio;
    next[13] = center.dy - (center.dy - old[13]) * ratio;
    setState(() {
      _fit = false;
      _chosenScale = scale;
    });
    _transform.value = next;
  }

  void _focus({bool fit = false}) => setState(() {
    _fit = fit;
    _chosenScale = null;
    _cameraKey = null;
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = TacticalMapSnapshot.capture();
    return TacticalArtwork(
      builder: (context, art) => JournalSurface(
        key: const ValueKey('tactical-field-plan'),
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final short = bounds.hasBoundedHeight && bounds.maxHeight < 420;
            final header = short && !widget.showHeading
                ? Wrap(
                    spacing: 10,
                    runSpacing: 3,
                    children: [
                      _status(
                        Icons.notifications_outlined,
                        snapshot.alarm,
                        snapshot.alarm == 'Alarm raised'
                            ? _danger
                            : JournalPalette.muted,
                      ),
                      if (snapshot.cameras)
                        _status(
                          Icons.videocam_outlined,
                          'Working cameras',
                          _teal,
                        ),
                      if (snapshot.response.isNotEmpty)
                        _status(
                          Icons.warning_amber_rounded,
                          snapshot.response,
                          _danger,
                        ),
                    ],
                  )
                : _header(snapshot);
            final tools = _tools();
            final inspector = TacticalTileInspector(
              key: const ValueKey('tactical-tile-inspector'),
              snapshot: snapshot,
              cell: _inspected(snapshot),
              art: art,
              compact:
                  short || (bounds.hasBoundedHeight && bounds.maxHeight < 540),
              movementEnabled: widget.movementEnabled,
              inspectMode: _inspectMode,
            );
            if (bounds.hasBoundedHeight && bounds.maxHeight >= 180) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (short) ...[
                    if (widget.showHeading) header,
                    _compactTools(snapshot, art),
                  ] else ...[
                    header,
                    const SizedBox(height: 6),
                    tools,
                  ],
                  const SizedBox(height: 6),
                  Expanded(child: _grid(snapshot, art)),
                  const SizedBox(height: 6),
                  TacticalTileInspector(
                    key: const ValueKey('tactical-tile-inspector'),
                    snapshot: snapshot,
                    cell: _inspected(snapshot),
                    art: art,
                    compact: short || bounds.maxHeight < 540,
                    minimal: short,
                    movementEnabled: widget.movementEnabled,
                    inspectMode: _inspectMode,
                  ),
                  if (!short) ...[
                    const SizedBox(height: 6),
                    _footer(
                      snapshot,
                      art,
                      compact: bounds.maxHeight < 600 || bounds.maxWidth < 650,
                    ),
                  ],
                ],
              );
            }
            final content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 6),
                tools,
                const SizedBox(height: 6),
                _grid(snapshot, art),
                const SizedBox(height: 8),
                inspector,
                const SizedBox(height: 6),
                _footer(snapshot, art, compact: bounds.maxWidth < 650),
              ],
            );
            return bounds.hasBoundedHeight
                ? Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      primary: false,
                      child: content,
                    ),
                  )
                : content;
          },
        ),
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
          Expanded(
            child: Text(
              'TACTICAL VIEW',
              style: JournalPalette.small.copyWith(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            'LEVEL ${snapshot.floor + 1}',
            style: JournalPalette.small.copyWith(fontSize: 11),
          ),
        ],
      ),
      if (widget.showHeading) ...[
        const SizedBox(height: 4),
        Text(
          snapshot.location,
          style: JournalPalette.heading.copyWith(fontSize: 18),
        ),
      ],
      const SizedBox(height: 4),
      Wrap(
        spacing: 12,
        runSpacing: 3,
        children: [
          _status(
            Icons.notifications_outlined,
            snapshot.alarm,
            snapshot.alarm == 'Alarm raised' ? _danger : JournalPalette.muted,
          ),
          if (snapshot.cameras)
            _status(Icons.videocam_outlined, 'Working cameras', _teal),
          if (snapshot.response.isNotEmpty)
            _status(Icons.warning_amber_rounded, snapshot.response, _danger),
        ],
      ),
    ],
  );

  Widget _inspectChip() => FilterChip(
    key: const ValueKey('tactical-inspect-mode'),
    label: const Text('Inspect'),
    selected: _inspectMode,
    tooltip: 'Inspect mode: map taps never move. Arrows move when available.',
    onSelected: (value) => setState(() => _inspectMode = value),
  );

  Widget _compactTools(TacticalMapSnapshot snapshot, TacticalArt? art) => Wrap(
    spacing: 8,
    runSpacing: 3,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      _status(
        Icons.notifications_outlined,
        snapshot.alarm,
        snapshot.alarm == 'Alarm raised' ? _danger : JournalPalette.muted,
      ),
      if (snapshot.cameras)
        _status(Icons.videocam_outlined, 'Working cameras', _teal),
      if (snapshot.response.isNotEmpty)
        _status(Icons.warning_amber_rounded, snapshot.response, _danger),
      PopupMenuButton<String>(
        tooltip: 'Map controls',
        icon: const Icon(Icons.tune, size: 20),
        onSelected: (value) {
          switch (value) {
            case 'in':
              _zoom(1.3);
            case 'out':
              _zoom(1 / 1.3);
            case 'fit':
              _focus(fit: true);
            case 'center':
              _focus();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'in', child: Text('Zoom tactical map in')),
          PopupMenuItem(value: 'out', child: Text('Zoom tactical map out')),
          PopupMenuItem(value: 'fit', child: Text('Fit area')),
          PopupMenuItem(
            value: 'center',
            child: Text('Center squad at readable size'),
          ),
        ],
      ),
      _inspectChip(),
      FieldPlanLegend(art: art, showPrimary: false),
    ],
  );

  Widget _tools() => Wrap(
    spacing: 5,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      IconButton.outlined(
        key: const ValueKey('tactical-zoom-out'),
        tooltip: 'Zoom tactical map out',
        onPressed: () => _zoom(1 / 1.3),
        icon: const Icon(Icons.remove, size: 18),
      ),
      IconButton.outlined(
        key: const ValueKey('tactical-zoom-in'),
        tooltip: 'Zoom tactical map in',
        onPressed: () => _zoom(1.3),
        icon: const Icon(Icons.add, size: 18),
      ),
      IconButton.outlined(
        key: const ValueKey('tactical-center'),
        tooltip: 'Center squad at readable size',
        onPressed: _focus,
        icon: const Icon(Icons.my_location, size: 18),
      ),
      TextButton(
        key: const ValueKey('tactical-fit'),
        onPressed: () => _focus(fit: true),
        child: const Text('Fit area'),
      ),
      FilterChip(
        key: const ValueKey('tactical-inspect-mode'),
        label: const Text('Inspect'),
        selected: _inspectMode,
        tooltip:
            'Inspect mode: map taps never move. Arrows move when available.',
        onSelected: (value) => setState(() => _inspectMode = value),
      ),
    ],
  );

  Widget _grid(TacticalMapSnapshot snapshot, TacticalArt? art) => LayoutBuilder(
    builder: (context, bounds) {
      final width = bounds.maxWidth.isFinite ? bounds.maxWidth : 690.0;
      final sceneSize = Size(
        width,
        width * snapshot.rowCount / snapshot.columnCount,
      );
      final height = bounds.hasBoundedHeight
          ? math.max(1, bounds.maxHeight)
          : sceneSize.height;
      final viewport = Size(width, height.toDouble());
      _viewport = viewport;
      _fitScale = math.min(1, height / sceneSize.height);
      final squad = snapshot.cells
          .where((cell) => cell.kind == TacticalTileKind.squad)
          .firstOrNull;
      final cameraKey = (
        viewport,
        sceneSize,
        snapshot.floor,
        snapshot.location,
        snapshot.xStart,
        snapshot.yStart,
        squad?.x,
        squad?.y,
      );
      if (_cameraKey != cameraKey) {
        _cameraKey = cameraKey;
        final scale = _fit
            ? _fitScale
            : _chosenScale ??
                  (32 / (width / snapshot.columnCount)).clamp(1.0, 5.0);
        final target = _fit || squad == null
            ? sceneSize.center(Offset.zero)
            : Offset(
                (squad.x - snapshot.xStart + .5) * width / snapshot.columnCount,
                (squad.y - snapshot.yStart + .5) * width / snapshot.columnCount,
              );
        final next = Matrix4.diagonal3Values(scale, scale, 1);
        next[12] = viewport.width / 2 - target.dx * scale;
        next[13] = viewport.height / 2 - target.dy * scale;
        _transform.value = next;
      }
      TacticalMapCell? hit(Offset point) {
        final cellSize = sceneSize.width / snapshot.columnCount;
        if (cellSize <= 0) return null;
        final column = (point.dx / cellSize).floor();
        final row = (point.dy / cellSize).floor();
        if (column < 0 ||
            column >= snapshot.columnCount ||
            row < 0 ||
            row >= snapshot.rowCount) {
          return null;
        }
        return snapshot.cells[row * snapshot.columnCount + column];
      }

      void select(Offset point, {bool hover = false}) {
        final cell = hit(point);
        if (cell == null) return;
        final position = (cell.x, cell.y, snapshot.floor);
        if (hover) {
          if (_hovered != position) setState(() => _hovered = position);
        } else {
          setState(() {
            _hovered = null;
            _selected = position;
          });
        }
      }

      return Align(
        key: const ValueKey('tactical-plan-fit'),
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: SizedBox(
          key: const ValueKey('tactical-map-viewport'),
          width: viewport.width,
          height: viewport.height,
          child: ClipRect(
            child: InteractiveViewer(
              key: const ValueKey('tactical-map-viewer'),
              transformationController: _transform,
              constrained: false,
              minScale: _fitScale,
              maxScale: 5,
              boundaryMargin: const EdgeInsets.all(40),
              onInteractionStart: (_) => setState(() {
                _hovered = null;
              }),
              child: SizedBox(
                width: sceneSize.width,
                height: sceneSize.height,
                child: MouseRegion(
                  cursor: _inspectMode
                      ? SystemMouseCursors.help
                      : SystemMouseCursors.basic,
                  onHover: (event) => select(event.localPosition, hover: true),
                  onExit: (_) => setState(() => _hovered = null),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPressStart: (details) async {
                      select(details.localPosition);
                      await showTacticalTileDetails(
                        context,
                        snapshot: snapshot,
                        cell: hit(details.localPosition),
                        art: art,
                      );
                    },
                    onSecondaryTapUp: (details) async {
                      select(details.localPosition);
                      await showTacticalTileDetails(
                        context,
                        snapshot: snapshot,
                        cell: hit(details.localPosition),
                        art: art,
                      );
                    },
                    onTapUp: (details) async {
                      select(details.localPosition);
                      final cell = hit(details.localPosition);
                      if (_inspectMode && cell != null) {
                        await showTacticalTileDetails(
                          context,
                          snapshot: snapshot,
                          cell: cell,
                          art: art,
                        );
                        return;
                      }
                      if (cell == null ||
                          _inspectMode ||
                          !widget.movementEnabled) {
                        return;
                      }
                      final direction = _adjacentDirection(snapshot, cell);
                      if (direction != null) widget.onMove(direction);
                    },
                    child: CustomPaint(
                      key: const ValueKey('tactical-map-grid'),
                      painter: TacticalMapPainter(
                        snapshot,
                        art: art,
                        inspected: _inspected(snapshot),
                        onMove: widget.movementEnabled && !_inspectMode
                            ? widget.onMove
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _footer(
    TacticalMapSnapshot snapshot,
    TacticalArt? art, {
    bool compact = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (compact)
        Wrap(
          spacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              !widget.movementEnabled
                  ? 'Movement unavailable. Inspect tiles or resolve the current decision.'
                  : _inspectMode
                  ? 'Inspect: taps inspect; arrows move.'
                  : 'Tap outlines to move. Hold to inspect. Drag to pan.',
              style: JournalPalette.small.copyWith(fontSize: 10),
            ),
            FieldPlanLegend(art: art, showPrimary: false),
          ],
        )
      else ...[
        Text(
          !widget.movementEnabled
              ? 'Movement unavailable. Inspect tiles or resolve the current decision.'
              : _inspectMode
              ? 'Inspect mode: tap any tile safely. Arrows still move. Drag to pan.'
              : 'Tap an outlined tile to move. Hover or hold to inspect safely. Drag to pan.',
          style: JournalPalette.small.copyWith(fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          'Your squad · ${snapshot.currentDescription}',
          style: JournalPalette.small.copyWith(color: _ink),
        ),
        const SizedBox(height: 4),
        FieldPlanLegend(art: art),
      ],
      if (widget.showMovementControls) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _moveButton('Left', Icons.arrow_back_rounded),
            _moveButton('Up', Icons.arrow_upward_rounded),
            _moveButton('Down', Icons.arrow_downward_rounded),
            _moveButton('Right', Icons.arrow_forward_rounded),
          ],
        ),
      ],
    ],
  );

  Widget _moveButton(String direction, IconData icon) => IconButton.outlined(
    key: ValueKey('tactical-move:${direction.toLowerCase()}'),
    tooltip: 'Move ${direction.toLowerCase()}',
    onPressed: widget.movementEnabled ? () => widget.onMove(direction) : null,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      foregroundColor: _ink,
      minimumSize: const Size(44, 44),
    ),
  );

  Widget _status(IconData icon, String label, Color color) => Tooltip(
    triggerMode: TooltipTriggerMode.tap,
    message: switch (label) {
      'Alarm raised' =>
        'The site alarm is active. Passing a stealth check does not switch it off or remove the encounter. Resolve the encounter or use Flee to withdraw.',
      'Suspicion raised' =>
        'Observers are suspicious. Further stealth and disguise checks are harder. Passing one check does not reset suspicion.',
      'Suspicion building' =>
        'Observers are becoming suspicious. Further actions can advance the alarm countdown. Passing a stealth check does not reset it.',
      'No alarm' =>
        'No site alarm is currently raised. This is not a guarantee of concealment: moving, waiting and other actions can trigger detection checks.',
      _ => label,
    },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: JournalPalette.small.copyWith(color: color, fontSize: 11),
        ),
      ],
    ),
  );
}

/// Shared passive tile details for tactical and full-floor maps.
class TacticalTileInspector extends StatelessWidget {
  const TacticalTileInspector({
    super.key,
    required this.snapshot,
    required this.cell,
    required this.art,
    this.inspectionOnly = false,
    this.compact = false,
    this.movementEnabled = true,
    this.inspectMode = false,
    this.minimal = false,
  });
  final TacticalMapSnapshot snapshot;
  final TacticalMapCell? cell;
  final TacticalArt? art;
  final bool inspectionOnly, compact, movementEnabled, inspectMode, minimal;

  @override
  Widget build(BuildContext context) {
    final tile = cell;
    final current = tile?.kind == TacticalTileKind.squad;
    final direction = tile == null ? null : _adjacentDirection(snapshot, tile);
    final known = tile != null && tile.kind != TacticalTileKind.unknown;
    final title = tile == null
        ? inspectionOnly
              ? 'Inspect the explored floor'
              : 'Explore, take action, and leave via an exit'
        : current
        ? 'Current tile · ${tile.featureLabel}'
        : tile.kind == TacticalTileKind.enemy ||
              tile.kind == TacticalTileKind.armoredEnemy ||
              tile.kind == TacticalTileKind.woundedEnemy
        ? '${tile.label} · ${tile.featureLabel}'
        : tile.featureLabel;
    final state = !known
        ? ''
        : [
            if (current) 'Your squad',
            if (tile.visible || current) 'In view' else 'Previously explored',
            if (tile.restricted) 'Restricted area',
            if (tile.lootAvailable) 'Loot available (G)',
            if (tile.hazardLabel != null) tile.hazardLabel!,
          ].join(' · ');
    final advice = tile == null
        ? inspectionOnly
              ? 'Hover, tap or hold a tile to inspect. Zoom in, then drag to pan.'
              : 'Use arrow controls or an outlined tile to move one step.'
        : !known
        ? 'Unexplored. Hidden contents remain concealed.'
        : inspectionOnly
        ? 'Inspection only. Return to the operation to move or act. ${tile.actionHint}'
        : !movementEnabled
        ? 'Map taps inspect only. Resolve the current decision or use an available escape action. ${tile.actionHint}'
        : inspectMode
        ? 'Inspect mode: map taps inspect safely. Arrows still move. ${tile.actionHint}'
        : direction != null && tile.kind == TacticalTileKind.door
        ? 'Tap to try the door ${direction.toLowerCase()}. ${tile.actionHint}'
        : current
        ? tile.actionHint.isEmpty
              ? 'Move one outlined tile at a time. Return to an exit to leave the site.'
              : tile.actionHint.replaceFirst('Stand here, then press', 'Press')
        : '${direction != null ? 'One step ${direction.toLowerCase()}.' : 'Move one outlined tile at a time to reach this tile.'} ${tile.actionHint}';
    final complete = [title, if (state.isNotEmpty) state, advice].join('\n');
    final scaler = MediaQuery.textScalerOf(context);
    if (minimal) {
      final warnings = [
        if (tile?.hazardLabel != null) tile!.hazardLabel!,
        if (tile?.restricted == true) 'Restricted area',
        if (tile?.lootAvailable == true) 'Loot available (G)',
      ].join(' · ');
      return Tooltip(
        message: complete,
        child: Container(
          height: 14 + scaler.scale(10) * (warnings.isEmpty ? 2.3 : 3.45),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: JournalPalette.card,
            border: Border.all(color: JournalPalette.rule),
          ),
          child: Row(
            children: [
              if (tile != null) ...[
                SizedBox.square(
                  dimension: 32,
                  child: TacticalTilePreview(
                    snapshot: snapshot,
                    cell: tile,
                    art: art,
                  ),
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JournalPalette.small.copyWith(
                        fontSize: 10,
                        height: 1.1,
                        fontWeight: FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    if (warnings.isNotEmpty)
                      Text(
                        warnings,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: JournalPalette.small.copyWith(
                          fontSize: 10,
                          height: 1.1,
                          color: tile?.burning == true
                              ? _danger
                              : JournalPalette.brassDark,
                        ),
                      ),
                    Text(
                      advice,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JournalPalette.small.copyWith(
                        fontSize: 10,
                        height: 1.1,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('tactical-tile-details'),
                tooltip: 'Read full tile details',
                icon: const Icon(Icons.info_outline, size: 18),
                onPressed: () => showTacticalTileDetails(
                  context,
                  snapshot: snapshot,
                  cell: tile,
                  art: art,
                  inspectionOnly: inspectionOnly,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final contentHeight = compact
        ? 22 +
              scaler.scale(12) * 1.15 +
              scaler.scale(10) * 1.15 +
              scaler.scale(11) * 3.45
        : 32 +
              scaler.scale(12) * 2.3 +
              scaler.scale(10) * 2.3 +
              scaler.scale(11) * 4.6;
    return Tooltip(
      message: complete,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        child: Container(
          height: contentHeight,
          padding: EdgeInsets.all(compact ? 6 : 10),
          decoration: BoxDecoration(
            color: JournalPalette.card.withValues(alpha: .95),
            border: Border.all(color: JournalPalette.rule),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tile != null) ...[
                SizedBox.square(
                  dimension: compact ? 48 : 64,
                  child: TacticalTilePreview(
                    snapshot: snapshot,
                    cell: tile,
                    art: art,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: JournalPalette.small.copyWith(
                        fontSize: 12,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    if (state.isNotEmpty)
                      Text(
                        state,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: JournalPalette.small.copyWith(
                          fontSize: 10,
                          height: 1.15,
                          color: tile?.burning == true
                              ? _danger
                              : JournalPalette.muted,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      advice,
                      maxLines: compact ? 3 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: JournalPalette.small.copyWith(
                        fontSize: 11,
                        height: 1.15,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey('tactical-tile-details'),
                tooltip: 'Read full tile details',
                icon: const Icon(Icons.info_outline, size: 18),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(title),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tile != null)
                            SizedBox.square(
                              dimension: 96,
                              child: TacticalTilePreview(
                                snapshot: snapshot,
                                cell: tile,
                                art: art,
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            [if (state.isNotEmpty) state, advice].join('\n\n'),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close tile details'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TacticalTilePreview extends StatelessWidget {
  const TacticalTilePreview({
    super.key,
    required this.snapshot,
    required this.cell,
    this.art,
  });
  final TacticalMapSnapshot snapshot;
  final TacticalMapCell cell;
  final TacticalArt? art;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _TilePreviewPainter(snapshot, cell, art));
}

Future<void> showTacticalTileDetails(
  BuildContext context, {
  required TacticalMapSnapshot snapshot,
  required TacticalMapCell? cell,
  TacticalArt? art,
  bool inspectionOnly = false,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(cell?.featureLabel ?? 'Tactical map controls'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cell != null)
            SizedBox.square(
              dimension: 96,
              child: TacticalTilePreview(
                snapshot: snapshot,
                cell: cell,
                art: art,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            cell?.semanticLabel ??
                'Use arrows or outlined tiles to move one step. Hold a tile or enable Inspect to examine it safely.',
          ),
          if (inspectionOnly)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Inspection only. Return to the operation to move or act.',
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close tile details'),
      ),
    ],
  ),
);

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

class _TilePreviewPainter extends CustomPainter {
  _TilePreviewPainter(this.snapshot, this.cell, this.art);
  final TacticalMapSnapshot snapshot;
  final TacticalMapCell cell;
  final TacticalArt? art;
  @override
  void paint(Canvas canvas, Size size) => TacticalMapPainter(
    snapshot,
    art: art,
  )._paintCell(canvas, Offset.zero & size, cell);
  @override
  bool shouldRepaint(covariant _TilePreviewPainter oldDelegate) => true;
}

class TacticalMapPainter extends CustomPainter {
  TacticalMapPainter(this.snapshot, {this.onMove, this.art, this.inspected});
  final TacticalMapSnapshot snapshot;
  final ValueChanged<String>? onMove;
  final TacticalArt? art;
  final TacticalMapCell? inspected;

  @override
  void paint(Canvas canvas, Size size) {
    final cellSize = size.width / snapshot.columnCount;
    if (cellSize <= 0) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = _fog);
    for (int i = 0; i < snapshot.cells.length; i++) {
      final rect = Rect.fromLTWH(
        (i % snapshot.columnCount) * cellSize,
        (i ~/ snapshot.columnCount) * cellSize,
        cellSize,
        cellSize,
      );
      _paintCell(canvas, rect, snapshot.cells[i]);
    }
  }

  void _paintCell(Canvas canvas, Rect rect, TacticalMapCell cell) {
    final step = onMove != null ? _adjacentDirection(snapshot, cell) : null;
    final selected = inspected?.x == cell.x && inspected?.y == cell.y;
    if (cell.kind == TacticalTileKind.unknown) {
      // No terrain, sprite or state from a hidden tile reaches this branch.
      TacticalSymbols.drawFog(canvas, rect);
      if (selected) {
        _outline(canvas, rect, JournalPalette.brassDark);
      }
      return;
    }
    canvas.save();
    canvas.clipRect(rect);
    _terrain(canvas, rect, cell);
    if (cell.graffiti != null) {
      TacticalSymbols.drawGraffiti(canvas, rect, cell.graffiti!);
    }
    if (cell.restricted) {
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
    final hasObject = art != null && cell.objectSprite != null;
    final hasHazard = art != null && cell.hazardSprite != null;
    if (hasObject) {
      // Art does not decide whether a feature is manually usable.
      art!.drawObject(
        canvas,
        cell.objectQuadrant == null ? rect.deflate(rect.width * .04) : rect,
        cell.objectSprite!,
        quadrant: cell.objectQuadrant,
      );
      if (cell.objectSprite == TacticalObjectCell.signboard) {
        TacticalSymbols.drawSignLettering(canvas, rect);
      }
    }
    if (hasHazard) {
      art!.drawHazard(
        canvas,
        rect.deflate(rect.width * .04),
        cell.hazardSprite!,
      );
    }
    if (cell.pointOfInterest && !cell.visited) {
      canvas.drawCircle(
        rect.topRight + Offset(-rect.width * .13, rect.height * .13),
        rect.width * .07,
        Paint()..color = JournalPalette.brassDark,
      );
    }
    if (cell.hazardLabel?.contains('Defensive boobytrap') == true) {
      TacticalSymbols.drawTrapMarker(canvas, rect);
    }
    final occupied =
        cell.kind == TacticalTileKind.squad ||
        cell.kind == TacticalTileKind.enemy ||
        cell.kind == TacticalTileKind.woundedEnemy ||
        cell.kind == TacticalTileKind.armoredEnemy;
    final unitRect =
        occupied &&
            (cell.objectSprite != null ||
                cell.hazardSprite != null ||
                (cell.underlyingKind != null &&
                    cell.underlyingKind != TacticalTileKind.floor))
        ? Rect.fromLTWH(
            rect.left + rect.width * .39,
            rect.top + rect.height * .39,
            rect.width * .6,
            rect.height * .6,
          )
        : rect;
    final feature = cell.underlyingKind;
    if (occupied &&
        (feature == TacticalTileKind.stairsUp ||
            feature == TacticalTileKind.stairsDown)) {
      TacticalSymbols.drawStairs(
        canvas,
        rect,
        up: feature == TacticalTileKind.stairsUp,
      );
    } else if (occupied && feature == TacticalTileKind.exit) {
      TacticalSymbols.drawExit(canvas, rect);
    } else if (occupied && feature == TacticalTileKind.door) {
      TacticalSymbols.drawDoor(
        canvas,
        rect,
        horizontal: cell.horizontalDoor,
        locked: cell.featureLabel.contains('Locked'),
        blocked: cell.featureLabel.contains('cannot unlock'),
        metal: cell.featureLabel == 'Metal door',
        burning: cell.burning,
      );
    }
    switch (cell.kind) {
      case TacticalTileKind.door:
        TacticalSymbols.drawDoor(
          canvas,
          rect,
          horizontal: cell.horizontalDoor,
          locked:
              cell.label.contains('Locked') ||
              cell.label.contains('cannot unlock'),
          blocked: cell.label.contains('cannot unlock'),
          metal: cell.label == 'Metal door',
          burning: cell.burning,
        );
      case TacticalTileKind.squad:
        TacticalSymbols.drawUnit(
          canvas,
          unitRect,
          kind: TacticalUnitSymbol.squad,
        );
      case TacticalTileKind.enemy:
        TacticalSymbols.drawUnit(
          canvas,
          unitRect,
          kind: TacticalUnitSymbol.enemy,
        );
      case TacticalTileKind.woundedEnemy:
        TacticalSymbols.drawUnit(
          canvas,
          unitRect,
          kind: TacticalUnitSymbol.wounded,
        );
      case TacticalTileKind.armoredEnemy:
        TacticalSymbols.drawUnit(
          canvas,
          unitRect,
          kind: TacticalUnitSymbol.armored,
        );
      case TacticalTileKind.exit:
        TacticalSymbols.drawExit(canvas, rect);
      case TacticalTileKind.stairsUp:
        TacticalSymbols.drawStairs(canvas, rect, up: true);
      case TacticalTileKind.stairsDown:
        TacticalSymbols.drawStairs(canvas, rect, up: false);
      case TacticalTileKind.loot:
        if (!hasObject) TacticalSymbols.drawLoot(canvas, rect);
      case TacticalTileKind.trap:
        if (!hasHazard) TacticalSymbols.drawTrap(canvas, rect);
      default:
        if (!hasObject &&
            !hasHazard &&
            cell.graffiti == null &&
            cell.icon != null &&
            !(cell.kind == TacticalTileKind.wall && cell.burning)) {
          _drawIcon(
            canvas,
            rect,
            cell.icon!,
            _iconColor(cell),
            rect.width * .62,
          );
        }
    }
    if (cell.kind == TacticalTileKind.wall &&
        cell.label == 'Bloodstained wall') {
      if (art != null) {
        art!.drawHazard(canvas, rect, TacticalHazardCell.heavyBlood);
      } else {
        canvas.drawCircle(
          rect.center,
          rect.width * .18,
          Paint()..color = _danger.withValues(alpha: .65),
        );
      }
    }
    if (cell.burning && occupied) {
      final badge = Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width * .4,
        rect.height * .4,
      );
      canvas.drawRect(badge, Paint()..color = _paper);
      TacticalSymbols.drawFire(canvas, badge);
    } else if (cell.burning &&
        cell.kind == TacticalTileKind.wall &&
        !hasHazard) {
      TacticalSymbols.drawFire(canvas, rect);
    }
    if (cell.visited) {
      TacticalSymbols.drawVisitedMarker(
        canvas,
        rect,
        alongsideTrap:
            cell.hazardLabel?.contains('Defensive boobytrap') == true,
      );
    }
    // Remembered terrain keeps its shape but loses saturation and contrast.
    if (!cell.visible && cell.kind != TacticalTileKind.squad) {
      canvas.drawRect(rect, Paint()..color = _fog.withValues(alpha: .42));
    }
    _gridRule(canvas, rect);
    if (step != null) {
      _outline(canvas, rect, _teal, width: math.max(1.3, rect.width * .048));
      // Small direction cue, backed in paper, leaves the object centre clear.
      final badge = Rect.fromLTWH(
        rect.left + 2,
        rect.bottom - rect.height * .3,
        rect.width * .28,
        rect.height * .25,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(badge, const Radius.circular(1)),
        Paint()..color = _paper,
      );
      _drawIcon(
        canvas,
        badge,
        switch (step) {
          'Left' => Icons.arrow_back,
          'Right' => Icons.arrow_forward,
          'Up' => Icons.arrow_upward,
          _ => Icons.arrow_downward,
        },
        _teal,
        rect.width * .22,
      );
    }
    if (selected) {
      _outline(
        canvas,
        rect,
        JournalPalette.brassDark,
        width: math.max(2, rect.width * .065),
      );
    }
    canvas.restore();
  }

  void _outline(Canvas canvas, Rect rect, Color color, {double width = 1.8}) {
    canvas.drawRect(
      rect.deflate(width / 2 + .5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = _paper,
    );
    canvas.drawRect(
      rect.deflate(width + 1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = color,
    );
  }

  void _gridRule(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..color = JournalPalette.brassDark.withValues(alpha: .25),
    );
  }

  void _terrain(Canvas canvas, Rect rect, TacticalMapCell cell) {
    final wall = (cell.underlyingKind ?? cell.kind) == TacticalTileKind.wall;
    final surfaces = tacticalSurfacesForSite(snapshot.siteType);
    final terrain = wall ? surfaces.wall : cell.groundSprite ?? surfaces.floor;
    canvas.drawRect(rect, Paint()..color = wall ? _wall : _paper);
    if (art != null) {
      art!.drawTerrain(canvas, rect, terrain, opacity: wall ? .72 : .52);
    } else if (wall) {
      final detail = Paint()
        ..color = JournalPalette.brassDark
        ..strokeWidth = .8;
      canvas.drawLine(rect.centerLeft, rect.centerRight, detail);
      canvas.drawLine(rect.topCenter, rect.center, detail);
    } else if (cell.kind == TacticalTileKind.grass) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFFC7CFAB));
    }
    if (wall) {
      canvas.drawRect(
        rect.deflate(.7),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = JournalPalette.brassDark.withValues(alpha: .65),
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
                  '${snapshot.cells[i].semanticLabel}, '
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
