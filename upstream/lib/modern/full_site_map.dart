import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/tactical_art.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';

/// Read-only inspection using exactly the source's full-floor snapshot.
/// Zoom and pan never supply movement input to the engine.
class FullSiteMap extends StatefulWidget {
  const FullSiteMap({super.key, this.showHeading = true});
  final bool showHeading;
  @override
  State<FullSiteMap> createState() => _FullSiteMapState();
}

class _FullSiteMapState extends State<FullSiteMap> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  (int, int)? _hovered, _selected;
  int? _floor;

  TacticalMapCell? _inspected(TacticalMapSnapshot snapshot) {
    final position = _hovered ?? _selected;
    if (position == null) return null;
    return snapshot.cells
        .where((cell) => cell.x == position.$1 && cell.y == position.$2)
        .firstOrNull;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final scale = (current * factor).clamp(1.0, 12.0);
    final ratio = scale / current;
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final old = _transform.value;
    final next = Matrix4.diagonal3Values(scale, scale, 1);
    next[12] = center.dx - (center.dx - old[12]) * ratio;
    next[13] = center.dy - (center.dy - old[13]) * ratio;
    _transform.value = next;
  }

  void _findSquad(TacticalMapSnapshot snapshot) {
    final squad = snapshot.cells
        .where((cell) => cell.kind == TacticalTileKind.squad)
        .firstOrNull;
    if (squad == null || _viewport.width <= 0) return;
    final cellSize = _viewport.width / snapshot.columnCount;
    final scale = (36 / cellSize).clamp(1.0, 12.0);
    final next = Matrix4.diagonal3Values(scale, scale, 1);
    next[12] = _viewport.width / 2 - (squad.x + .5) * cellSize * scale;
    next[13] = _viewport.height / 2 - (squad.y + .5) * cellSize * scale;
    _transform.value = next;
    setState(() => _selected = (squad.x, squad.y));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = TacticalMapSnapshot.capture(fullMap: true);
    if (_floor != snapshot.floor) {
      _floor = snapshot.floor;
      _hovered = _selected = null;
    }
    return TacticalArtwork(
      builder: (context, art) => JournalSurface(
        key: const ValueKey('full-floor-field-plan'),
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, bounds) {
            final header = _header(snapshot);
            final footer = _footer(
              snapshot,
              art,
              compact: bounds.hasBoundedHeight && bounds.maxHeight < 440,
            );
            final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
            final scrollHeight = 280 + (textScale - 1).clamp(0, 2) * 180;
            if (bounds.hasBoundedHeight && bounds.maxHeight >= scrollHeight) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const SizedBox(height: 9),
                  Expanded(child: _grid(snapshot, art)),
                  const SizedBox(height: 9),
                  footer,
                ],
              );
            }
            final content = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 12),
                _grid(snapshot, art),
                const SizedBox(height: 12),
                footer,
              ],
            );
            return bounds.hasBoundedHeight
                ? SingleChildScrollView(
                    key: const ValueKey('full-map-scroll'),
                    child: content,
                  )
                : content;
          },
        ),
      ),
    );
  }

  Widget _header(TacticalMapSnapshot snapshot) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 14,
    runSpacing: 6,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeading)
            Text(
              snapshot.location,
              style: JournalPalette.heading.copyWith(fontSize: 19),
            ),
          Text(
            'Level ${snapshot.floor + 1} · Explored areas',
            style: JournalPalette.small,
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            key: const ValueKey('full-map-zoom-out'),
            tooltip: 'Zoom out',
            onPressed: () => _zoom(1 / 1.5),
            icon: const Icon(Icons.remove, color: JournalPalette.ink),
          ),
          const SizedBox(width: 6),
          IconButton.outlined(
            key: const ValueKey('full-map-zoom-in'),
            tooltip: 'Zoom in',
            onPressed: () => _zoom(1.5),
            icon: const Icon(Icons.add, color: JournalPalette.ink),
          ),
          const SizedBox(width: 6),
          IconButton.outlined(
            key: const ValueKey('full-map-find-squad'),
            tooltip: 'Find squad on full map',
            onPressed: () => _findSquad(snapshot),
            icon: const Icon(Icons.my_location, color: JournalPalette.ink),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            key: const ValueKey('full-map-fit'),
            onPressed: () => _transform.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen, size: 18),
            label: const Text('Fit floor'),
            style: TextButton.styleFrom(foregroundColor: JournalPalette.ink),
          ),
        ],
      ),
    ],
  );

  Widget _grid(TacticalMapSnapshot snapshot, TacticalArt? art) => LayoutBuilder(
    builder: (context, constraints) {
      final size = fittedFieldPlanSize(
        constraints,
        snapshot.columnCount,
        snapshot.rowCount,
      );
      _viewport = size;
      TacticalMapCell? hit(Offset point) {
        if (size.width <= 0) return null;
        final cellSize = size.width / snapshot.columnCount;
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

      void inspect(Offset point) {
        final cell = hit(point);
        if (cell == null) return;
        setState(() => _selected = (cell.x, cell.y));
      }

      return Center(
        key: const ValueKey('full-map-plan-fit'),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (event) {
                  final cell = hit(event.localPosition);
                  final next = cell == null ? null : (cell.x, cell.y);
                  if (_hovered != next) setState(() => _hovered = next);
                },
                onExit: (_) => setState(() => _hovered = null),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => inspect(details.localPosition),
                  onLongPressStart: (details) => inspect(details.localPosition),
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: CustomPaint(
                      key: const ValueKey('full-site-map-grid'),
                      painter: TacticalMapPainter(
                        snapshot,
                        art: art,
                        inspected: _inspected(snapshot),
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
    required bool compact,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      KeyedSubtree(
        key: const ValueKey('full-map-tile-inspector'),
        child: TacticalTileInspector(
          snapshot: snapshot,
          cell: _inspected(snapshot),
          art: art,
          inspectionOnly: true,
          compact: compact,
        ),
      ),
      const SizedBox(height: 8),
      const FieldPlanLegend(),
      const SizedBox(height: 8),
      const Text(
        'Inspection only — return to operation to move',
        style: JournalPalette.small,
      ),
    ],
  );
}
