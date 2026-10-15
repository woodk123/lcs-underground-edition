import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
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
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _zoom(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final scale = (current * factor).clamp(1.0, 5.0);
    final ratio = scale / current;
    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final old = _transform.value;
    final next = Matrix4.diagonal3Values(scale, scale, 1);
    next[12] = center.dx - (center.dx - old[12]) * ratio;
    next[13] = center.dy - (center.dy - old[13]) * ratio;
    _transform.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = TacticalMapSnapshot.capture(fullMap: true);
    return JournalSurface(
      key: const ValueKey('full-floor-field-plan'),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final header = _header(snapshot);
          final footer = _footer();
          if (bounds.hasBoundedHeight) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 9),
                Expanded(child: _grid(snapshot)),
                const SizedBox(height: 9),
                footer,
              ],
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              _grid(snapshot),
              const SizedBox(height: 12),
              footer,
            ],
          );
        },
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

  Widget _grid(TacticalMapSnapshot snapshot) => LayoutBuilder(
    builder: (context, constraints) {
      final size = fittedFieldPlanSize(
        constraints,
        snapshot.columnCount,
        snapshot.rowCount,
      );
      _viewport = size;
      return Center(
        key: const ValueKey('full-map-plan-fit'),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CustomPaint(
                  key: const ValueKey('full-site-map-grid'),
                  painter: TacticalMapPainter(snapshot),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _footer() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldPlanLegend(),
      SizedBox(height: 8),
      Text(
        'Zoom to inspect rooms, then drag to pan. '
        'Return to the operation to move your squad.',
        style: JournalPalette.small,
      ),
    ],
  );
}
