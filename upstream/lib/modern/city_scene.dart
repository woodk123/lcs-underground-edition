import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

const _sceneInk = JournalPalette.ink;
const _sceneTeal = JournalPalette.olive;
const _sceneRed = JournalPalette.danger;
const _worldSize = Size(1320, 910);

// Alpha bounds of the generated sprites plus four pixels of soft-edge padding.
// The atlas has deliberately uneven spacing: uniform cells would clip roofs.
const cityBuildingAsset = 'assets/modern/building_sprites_v2.webp';
const cityPedestrianAsset = 'assets/modern/pedestrian_walk_v2.webp';
const _walkFootAnchors = <Offset>[
  Offset(223, 476),
  Offset(207.5, 466),
  Offset(190.5, 463),
  Offset(192, 431),
  Offset(234.5, 449),
  Offset(205.5, 445),
  Offset(190.5, 439),
  Offset(199.5, 416),
];
const cityBuildingSourceRects = <Rect>[
  Rect.fromLTWH(52, 64, 233, 258),
  Rect.fromLTWH(352, 120, 247, 192),
  Rect.fromLTWH(664, 108, 240, 211),
  Rect.fromLTWH(962, 83, 248, 228),
  Rect.fromLTWH(45, 349, 250, 273),
  Rect.fromLTWH(365, 349, 226, 272),
  Rect.fromLTWH(658, 352, 259, 272),
  Rect.fromLTWH(964, 373, 252, 239),
  Rect.fromLTWH(44, 661, 259, 240),
  Rect.fromLTWH(347, 667, 257, 239),
  Rect.fromLTWH(656, 677, 258, 229),
  Rect.fromLTWH(965, 672, 255, 228),
  Rect.fromLTWH(52, 930, 234, 278),
  Rect.fromLTWH(349, 978, 256, 218),
  Rect.fromLTWH(648, 970, 275, 232),
  Rect.fromLTWH(965, 916, 251, 283),
];

/// An exposed planning destination. The scene never queries the game world.
@immutable
class CitySceneBuilding {
  const CitySceneBuilding({
    required this.id,
    required this.name,
    required this.spriteIndex,
    required this.enabled,
    this.current = false,
    this.queued = false,
    this.district = false,
    this.details = const [],
  });

  final String id;
  final String name;
  final int spriteIndex;
  final bool enabled, current, queued, district;
  final List<String> details;
}

/// A pannable illustration of the visible destination list, not a navigation
/// simulation. Every interactive object corresponds to one exposed destination.
class CityScene extends StatefulWidget {
  const CityScene({
    super.key,
    required this.buildings,
    required this.onInspect,
    this.selectedId,
    this.buildingAsset = cityBuildingAsset,
    this.pedestrianAsset = cityPedestrianAsset,
    this.atlasColumns = 4,
    this.atlasRows = 4,
    this.walkColumns = 4,
    this.walkRows = 2,
    this.viewportHeight = 600,
  });

  final List<CitySceneBuilding> buildings;
  final ValueChanged<String> onInspect;
  final String? selectedId;
  final String buildingAsset, pedestrianAsset;
  final int atlasColumns, atlasRows, walkColumns, walkRows;
  final double viewportHeight;

  @override
  State<CityScene> createState() => _CitySceneState();
}

class _CitySceneState extends State<CityScene> {
  final _transform = TransformationController();
  Size? _viewport;
  String? _hoveredId, _focusedId;
  double _fitScale = 1;

  @override
  void didUpdateWidget(CityScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.buildings.map((b) => b.id).join('|') !=
        widget.buildings.map((b) => b.id).join('|')) {
      _viewport = null;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _fit(Size viewport) {
    final positions = _positions().values;
    // Fit the exposed objects, rather than acres of decorative empty road.
    // This is presentation geometry only and cannot imply a travel distance.
    final bounds = positions.isEmpty
        ? Offset.zero & _worldSize
        : positions
              .map((p) => Rect.fromLTWH(p.dx - 20, p.dy - 160, 220, 230))
              .reduce((a, b) => a.expandToInclude(b))
              .inflate(55);
    _fitScale = math.min(
      viewport.width / bounds.width,
      viewport.height / bounds.height,
    );
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        viewport.width / 2 - bounds.center.dx * _fitScale,
        viewport.height / 2 - bounds.center.dy * _fitScale,
        0,
        1,
      )
      ..scaleByDouble(_fitScale, _fitScale, 1, 1);
  }

  void _zoom(double factor) {
    final current = _transform.value.entry(0, 0).abs();
    final next = (current * factor).clamp(_fitScale * .8, _fitScale * 3.5);
    final actual = next / current;
    final center = _viewport!.center(Offset.zero);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(actual, actual, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_transform.value);
  }

  Map<String, Offset> _positions() {
    // Fixed display lots; they express no real street geography or distance.
    const allLots = [
      Offset(550, 425),
      Offset(790, 310),
      Offset(310, 310),
      Offset(790, 540),
      Offset(310, 540),
      Offset(550, 195),
      Offset(1030, 425),
      Offset(550, 655),
      Offset(1030, 655),
      Offset(70, 425),
      Offset(790, 770),
    ];
    final lots = allLots.take(widget.buildings.length).toList();
    final occupied = <int>{};
    final result = <String, Offset>{};
    final ordered = [...widget.buildings]..sort((a, b) => a.id.compareTo(b.id));
    for (final building in ordered) {
      var hash = 2166136261;
      for (final code in building.id.codeUnits) {
        hash = ((hash ^ code) * 16777619) & 0x7fffffff;
      }
      var index = hash % lots.length;
      while (occupied.contains(index)) {
        index = (index + 1) % lots.length;
      }
      occupied.add(index);
      result[building.id] = lots[index];
    }
    return result;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.viewportHeight,
    child: Container(
      key: const ValueKey('city-planning-board'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFD6D9CB),
        border: Border.all(color: const Color(0xFFB5BDB0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _sceneInk,
            padding: const EdgeInsets.fromLTRB(15, 9, 9, 9),
            child: Row(
              children: [
                const Icon(
                  Icons.location_city,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.buildings.length} places · open districts / inspect buildings',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                IconButton(
                  key: const ValueKey('city-zoom-out'),
                  tooltip: 'Zoom out',
                  color: Colors.white,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => _zoom(1 / 1.25),
                  icon: const Icon(Icons.remove, size: 19),
                ),
                IconButton(
                  key: const ValueKey('city-zoom-in'),
                  tooltip: 'Zoom in',
                  color: Colors.white,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => _zoom(1.25),
                  icon: const Icon(Icons.add, size: 19),
                ),
                IconButton(
                  key: const ValueKey('city-fit'),
                  tooltip: 'Fit city',
                  color: Colors.white,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => _fit(_viewport!),
                  icon: const Icon(Icons.fit_screen, size: 19),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = constraints.biggest;
                if (_viewport != viewport) {
                  _viewport = viewport;
                  _fit(viewport);
                }
                final positions = _positions();
                final ordered = [...widget.buildings]
                  ..sort(
                    (a, b) =>
                        positions[a.id]!.dy.compareTo(positions[b.id]!.dy),
                  );
                return Stack(
                  children: [
                    InteractiveViewer(
                      key: const ValueKey('city-pan-zoom'),
                      transformationController: _transform,
                      constrained: false,
                      minScale: _fitScale * .8,
                      maxScale: _fitScale * 3.5,
                      boundaryMargin: const EdgeInsets.all(340),
                      child: SizedBox(
                        width: _worldSize.width,
                        height: _worldSize.height,
                        child: Stack(
                          children: [
                            const Positioned.fill(
                              child: ExcludeSemantics(
                                child: CustomPaint(painter: _StreetPainter()),
                              ),
                            ),
                            for (final building in ordered)
                              _building(building, positions[building.id]!),
                            Positioned(
                              left: 622,
                              top: 500,
                              child: ExcludeSemantics(
                                child: _WalkingSprite(
                                  asset: widget.pedestrianAsset,
                                  columns: widget.walkColumns,
                                  rows: widget.walkRows,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 385,
                              top: 390,
                              child: ExcludeSemantics(
                                child: _WalkingSprite(
                                  asset: widget.pedestrianAsset,
                                  columns: widget.walkColumns,
                                  rows: widget.walkRows,
                                  reverse: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF7F5EC,
                            ).withValues(alpha: .92),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 6,
                            ),
                            child: Text(
                              'Drag to explore · scroll to zoom',
                              style: TextStyle(fontSize: 11, color: _sceneInk),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Text(
              'Illustrated street plan · only the currently listed places are shown. Positions do not represent travel distance.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                height: 1.2,
                color: Color(0xFF52605B),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _building(CitySceneBuilding building, Offset lot) {
    final selected = widget.selectedId == building.id;
    final reveal =
        selected || _hoveredId == building.id || _focusedId == building.id;
    final opensArea = building.district && building.enabled;
    final verb = opensArea ? 'Open' : 'Inspect';
    final accent = building.queued
        ? const Color(0xFFB37D2E)
        : building.current
        ? _sceneTeal
        : _sceneRed;
    return Positioned(
      left: lot.dx - 20,
      top: lot.dy - 160,
      width: 220,
      height: 230,
      child: Semantics(
        key: ValueKey('city-building:${building.id}'),
        button: true,
        label: '$verb ${building.name}',
        onTap: () => widget.onInspect(building.id),
        value: [
          if (building.current) 'Current location',
          if (building.queued) 'Visit queued',
          if (!building.enabled) 'Order unavailable',
          ...building.details,
        ].join('. '),
        excludeSemantics: true,
        child: Tooltip(
          message: [
            '$verb ${building.name}',
            ...building.details,
            if (opensArea) 'Browse its places without changing orders or time.',
          ].join('\n'),
          child: MouseRegion(
            onEnter: (_) => setState(() => _hoveredId = building.id),
            onExit: (_) => setState(() => _hoveredId = null),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('city-building-button:${building.id}'),
                onTap: () => widget.onInspect(building.id),
                onFocusChange: (focused) =>
                    setState(() => _focusedId = focused ? building.id : null),
                borderRadius: BorderRadius.circular(10),
                focusColor: _sceneTeal.withValues(alpha: .17),
                hoverColor: Colors.transparent,
                splashColor: _sceneTeal.withValues(alpha: .12),
                child: Stack(
                  children: [
                    Positioned(
                      left: 15,
                      top: 133,
                      width: 190,
                      height: 80,
                      child: CustomPaint(
                        painter: _LotPainter(
                          color: accent,
                          selected: selected || _focusedId == building.id,
                          available: building.enabled,
                          marked: building.current || building.queued,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 0,
                      width: 200,
                      height: 200,
                      child: Opacity(
                        opacity: building.enabled ? 1 : .6,
                        child: AtlasSprite(
                          asset: widget.buildingAsset,
                          frame: building.spriteIndex,
                          columns: widget.atlasColumns,
                          rows: widget.atlasRows,
                          fallbackIndex: building.spriteIndex,
                        ),
                      ),
                    ),
                    if (building.current ||
                        building.queued ||
                        !building.enabled)
                      Positioned(
                        right: 27,
                        top: 107,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            !building.enabled
                                ? Icons.lock_outline
                                : building.queued
                                ? Icons.schedule
                                : Icons.home_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: reveal ? _sceneInk : const Color(0xFFF5F3E9),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFFE8C77E)
                                  : const Color(0xFFA7B29F),
                            ),
                          ),
                          child: Text(
                            building.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: reveal ? Colors.white : _sceneInk,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Crops actual frames from a generated raster atlas; the image is shared by
/// Flutter's image cache. A missing development asset has a neutral silhouette.
class AtlasSprite extends StatefulWidget {
  const AtlasSprite({
    super.key,
    required this.asset,
    required this.frame,
    required this.columns,
    required this.rows,
    this.fallbackIndex = 0,
  });

  final String asset;
  final int frame, columns, rows, fallbackIndex;

  @override
  State<AtlasSprite> createState() => _AtlasSpriteState();
}

class _AtlasSpriteState extends State<AtlasSprite> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(AtlasSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) _resolve();
  }

  void _resolve() {
    final stream = AssetImage(
      widget.asset,
    ).resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    if (_listener != null) _stream?.removeListener(_listener!);
    _image = null;
    _stream = stream;
    _listener = ImageStreamListener(
      (info, synchronousCall) {
        if (mounted) setState(() => _image = info.image);
      },
      onError: (error, stack) {
        // The release asset audit verifies these files. The graceful silhouette
        // keeps source-only development and unit tests usable before generation.
      },
    );
    stream.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _AtlasPainter(
      image: _image,
      frame: widget.frame,
      columns: widget.columns,
      rows: widget.rows,
      fallbackIndex: widget.fallbackIndex,
      sourceRects: widget.asset == cityBuildingAsset
          ? cityBuildingSourceRects
          : null,
      footAnchors: widget.asset == cityPedestrianAsset
          ? _walkFootAnchors
          : null,
    ),
  );
}

class _WalkingSprite extends StatefulWidget {
  const _WalkingSprite({
    required this.asset,
    required this.columns,
    required this.rows,
    this.reverse = false,
  });
  final String asset;
  final int columns, rows;
  final bool reverse;
  @override
  State<_WalkingSprite> createState() => _WalkingSpriteState();
}

class _WalkingSpriteState extends State<_WalkingSprite> {
  Timer? _timer;
  int _frame = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled) {
      _timer = Timer.periodic(const Duration(milliseconds: 125), (_) {
        if (mounted && !_isOffstage) {
          setState(
            () => _frame = (_frame + 1) % (widget.columns * widget.rows),
          );
        }
      });
    }
  }

  bool get _isOffstage {
    var offstage = false;
    // Offstage intentionally leaves animations running unless its owner also
    // supplies TickerMode. Check every ancestor so a visible inner Offstage
    // cannot mask a hidden outer one. Keep the timer alive to resume naturally
    // when the same scene becomes visible again.
    context.visitAncestorElements((ancestor) {
      if (ancestor is RenderObjectElement) {
        final renderObject = ancestor.renderObject;
        if (renderObject is RenderOffstage && renderObject.offstage) {
          offstage = true;
          return false;
        }
      }
      return true;
    });
    return offstage;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Transform.flip(
    flipX: widget.reverse,
    child: SizedBox(
      width: 38,
      height: 57,
      child: AtlasSprite(
        asset: widget.asset,
        frame: _frame,
        columns: widget.columns,
        rows: widget.rows,
        fallbackIndex: -1,
      ),
    ),
  );
}

class _AtlasPainter extends CustomPainter {
  const _AtlasPainter({
    required this.image,
    required this.frame,
    required this.columns,
    required this.rows,
    required this.fallbackIndex,
    this.sourceRects,
    this.footAnchors,
  });
  final ui.Image? image;
  final int frame, columns, rows, fallbackIndex;
  final List<Rect>? sourceRects;
  final List<Offset>? footAnchors;

  @override
  void paint(Canvas canvas, Size size) {
    final raster = image;
    if (raster != null) {
      final width = raster.width / columns;
      final height = raster.height / rows;
      final index = frame % (columns * rows);
      final source =
          sourceRects?[frame % sourceRects!.length] ??
          Rect.fromLTWH(
            index % columns * width,
            index ~/ columns * height,
            width,
            height,
          );
      final fitted = applyBoxFit(BoxFit.contain, source.size, size);
      final anchor = footAnchors?[frame % footAnchors!.length];
      final target = anchor == null
          ? Alignment.bottomCenter.inscribe(
              fitted.destination,
              Offset.zero & size,
            )
          : Rect.fromLTWH(
              size.width / 2 -
                  anchor.dx * fitted.destination.width / source.width,
              size.height -
                  anchor.dy * fitted.destination.height / source.height,
              fitted.destination.width,
              fitted.destination.height,
            );
      canvas.drawImageRect(
        raster,
        source,
        target,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }
    if (fallbackIndex < 0) return;
    final sx = size.width / 200;
    final sy = size.height / 200;
    canvas.save();
    canvas.scale(sx, sy);
    final tall = 55.0 + fallbackIndex % 3 * 13;
    final roof = Path()
      ..moveTo(100, 170 - tall)
      ..lineTo(175, 132 - tall)
      ..lineTo(100, 95 - tall)
      ..lineTo(25, 132 - tall)
      ..close();
    final left = Path()
      ..moveTo(25, 132 - tall)
      ..lineTo(100, 170 - tall)
      ..lineTo(100, 170)
      ..lineTo(25, 132)
      ..close();
    final right = Path()
      ..moveTo(100, 170 - tall)
      ..lineTo(175, 132 - tall)
      ..lineTo(175, 132)
      ..lineTo(100, 170)
      ..close();
    canvas.drawPath(left, Paint()..color = const Color(0xFFB4AF9D));
    canvas.drawPath(right, Paint()..color = const Color(0xFF858E83));
    canvas.drawPath(roof, Paint()..color = const Color(0xFF607067));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AtlasPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.frame != frame ||
      oldDelegate.columns != columns ||
      oldDelegate.rows != rows ||
      oldDelegate.fallbackIndex != fallbackIndex;
}

class _LotPainter extends CustomPainter {
  const _LotPainter({
    required this.color,
    required this.selected,
    required this.available,
    required this.marked,
  });
  final Color color;
  final bool selected, available, marked;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = selected
            ? color.withValues(alpha: .22)
            : const Color(0xFFB9C1AE).withValues(alpha: .5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = selected || marked ? color : const Color(0xFFA1AE9B)
        ..strokeWidth = selected ? 4 : 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_LotPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.selected != selected ||
      oldDelegate.marked != marked ||
      oldDelegate.available != available;
}

class _StreetPainter extends CustomPainter {
  const _StreetPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFD6D9CB),
    );
    final roads = Paint()
      ..color = const Color(0xFFB0B8AB)
      ..strokeWidth = 50
      ..strokeCap = StrokeCap.square;
    final curb = Paint()
      ..color = const Color(0xFFEBEBDE)
      ..strokeWidth = 62;
    final paths = <(Offset, Offset)>[
      (const Offset(90, 320), const Offset(1170, 838)),
      (const Offset(330, 205), const Offset(1280, 660)),
      (const Offset(570, 90), const Offset(1290, 435)),
      (const Offset(160, 740), const Offset(1120, 280)),
      (const Offset(400, 855), const Offset(1290, 428)),
      (const Offset(0, 587), const Offset(880, 165)),
    ];
    for (final (from, to) in paths) {
      canvas.drawLine(from, to, curb);
      canvas.drawLine(from, to, roads);
    }
    final lane = Paint()
      ..color = const Color(0xFFE9E8D8).withValues(alpha: .75)
      ..strokeWidth = 2;
    for (final (from, to) in paths) {
      final vector = to - from;
      final count = (vector.distance / 30).floor();
      for (var i = 0; i < count; i += 2) {
        canvas.drawLine(
          from + vector * (i / count),
          from + vector * ((i + 1) / count),
          lane,
        );
      }
    }
    final text = TextPainter(
      text: const TextSpan(
        text: 'CITY OPERATIONS',
        style: TextStyle(
          fontFamily: 'ModernSans',
          color: Color(0xFF8D9C89),
          fontSize: 27,
          fontWeight: FontWeight.w700,
          letterSpacing: 5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, const Offset(62, 805));
  }

  @override
  bool shouldRepaint(_StreetPainter oldDelegate) => false;
}
