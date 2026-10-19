import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_site_art.dart';

const _street = Color(0xFF32352F);
const _pavement = Color(0xFF777B66);
const _paper = Color(0xFFE5DDBB);
const _ink = Color(0xFF302F23);
const _blue = Color(0xFF76A9C6);
const _red = Color(0xFFAA3025);
const _gold = Color(0xFFC9A849);

/// A known, source-provided destination. Geometry has no gameplay meaning.
@immutable
class JournalMapPlace {
  const JournalMapPlace({
    required this.id,
    required this.name,
    required this.kind,
    required this.enabled,
    this.siteType,
    this.shortcut,
    this.current = false,
    this.queued = false,
    this.details = const [],
  }) : assert(kind == 'city' || kind == 'district' || kind == 'site');

  final String id, name, kind;
  final String? siteType, shortcut;
  final bool enabled, current, queued;
  final List<String> details;
}

/// Top-down notebook cartography with reusable painted district illustrations.
///
/// Every selectable block comes from [places]. The decorative roofs and roads
/// express neither actual geography nor travel distance. Selecting a block only
/// reports its source ID; the caller owns selection and all engine commands.
class JournalCityPlan extends StatefulWidget {
  const JournalCityPlan({
    super.key,
    required this.places,
    required this.onSelect,
    this.selectedId,
    this.title = 'City plan',
    this.showLabels = true,
    this.showLegend = true,
    this.allowUnavailableInspection = false,
  });

  final List<JournalMapPlace> places;
  final ValueChanged<String> onSelect;
  final String? selectedId;
  final String title;
  final bool showLabels;
  final bool showLegend;
  final bool allowUnavailableInspection;

  @override
  State<JournalCityPlan> createState() => _JournalCityPlanState();
}

class _JournalCityPlanState extends State<JournalCityPlan> {
  final _transform = TransformationController();
  Size? _viewport;
  _PlanLayout? _layout;
  double _fitScale = 1;
  bool _index = false;

  @override
  void didUpdateWidget(JournalCityPlan oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ids(oldWidget.places) != _ids(widget.places)) _viewport = null;
  }

  String _ids(List<JournalMapPlace> places) =>
      (places.map((p) => p.id).toList()..sort()).join('\u001f');

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _fit() {
    final viewport = _viewport;
    final layout = _layout;
    if (viewport == null || layout == null) return;
    _fitScale = math.min(
      viewport.width / layout.size.width,
      viewport.height / layout.size.height,
    );
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - layout.size.width * _fitScale) / 2,
        (viewport.height - layout.size.height * _fitScale) / 2,
        0,
        1,
      )
      ..scaleByDouble(_fitScale, _fitScale, 1, 1);
  }

  void _zoom(double factor) {
    final viewport = _viewport;
    if (viewport == null) return;
    final scale = _transform.value.entry(0, 0).abs();
    final next = (scale * factor).clamp(_fitScale * .7, _fitScale * 4);
    final center = viewport.center(Offset.zero);
    _transform.value = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..scaleByDouble(next / scale, next / scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1)
      ..multiply(_transform.value);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : 480.0;
      final width = constraints.hasBoundedWidth ? constraints.maxWidth : 600.0;
      return SizedBox(
        key: const ValueKey('journal-city-plan'),
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _street,
            border: Border.all(color: const Color(0xFF96885B), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(),
              Expanded(child: _index ? _placeIndex() : _map()),
              if (widget.showLegend) _legend(),
            ],
          ),
        ),
      );
    },
  );

  Widget _toolbar() => Container(
    color: _paper,
    padding: const EdgeInsets.only(left: 9, right: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _tool('Zoom out', Icons.remove, _index ? null : () => _zoom(.8)),
        _tool('Zoom in', Icons.add, _index ? null : () => _zoom(1.25)),
        _tool('Fit all locations', Icons.fit_screen, _index ? null : _fit),
        _tool(
          _index ? 'Show city plan' : 'Show location index',
          _index ? Icons.map_outlined : Icons.list_alt,
          () => setState(() => _index = !_index),
        ),
      ],
    ),
  );

  Widget _tool(String tooltip, IconData icon, VoidCallback? callback) =>
      IconButton(
        tooltip: tooltip,
        onPressed: callback,
        icon: Icon(icon, size: 17),
        color: _ink,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 36),
        visualDensity: VisualDensity.compact,
      );

  Widget _map() => LayoutBuilder(
    builder: (context, constraints) {
      final viewport = Size(constraints.maxWidth, constraints.maxHeight);
      final layout = _PlanLayout(widget.places, viewport);
      _layout = layout;
      if (_viewport != viewport) {
        _viewport = viewport;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fit();
        });
      }
      return Stack(
        children: [
          ClipRect(
            child: InteractiveViewer(
              key: const ValueKey('journal-city-pan-zoom'),
              transformationController: _transform,
              constrained: false,
              minScale: .03,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(220),
              child: SizedBox(
                width: layout.size.width,
                height: layout.size.height,
                child: CustomPaint(
                  painter: _PlanPainter(layout),
                  child: ValueListenableBuilder<Matrix4>(
                    valueListenable: _transform,
                    builder: (context, transform, child) {
                      // Keep names legible at the default fitted view. Large
                      // campaigns also have the full-size location index.
                      final labelScale = (1 / transform.entry(0, 0).abs())
                          .clamp(1.0, 1.8);
                      return Stack(
                        children: [
                          for (final place in widget.places)
                            Positioned.fromRect(
                              rect: layout.rects[place.id]!,
                              child: _block(place, labelScale),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          if (widget.places.isEmpty)
            const Center(
              child: ColoredBox(
                color: _paper,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No known locations in this view.',
                    style: TextStyle(color: _ink),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  String _description(JournalMapPlace place) => [
    place.name,
    if (place.shortcut != null) 'Key ${place.shortcut!.toUpperCase()}',
    place.kind,
    if (place.current) 'Current location',
    if (place.queued) 'Queued destination',
    if (place.id == widget.selectedId) 'Selected',
    if (!place.enabled) 'Unavailable',
    ...place.details,
  ].join('. ');

  Widget _block(JournalMapPlace place, double labelScale) {
    final selected = place.id == widget.selectedId;
    final border = selected
        ? _red
        : place.enabled
        ? _blue
        : _pavement;
    return Tooltip(
      message: _description(place),
      child: TextButton(
        key: ValueKey('journal-map-place:${place.id}'),
        onPressed: place.enabled || widget.allowUnavailableInspection
            ? () => widget.onSelect(place.id)
            : null,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? const BorderSide(color: Colors.white, width: 4)
                : BorderSide(
                    color: selected
                        ? _red
                        : place.queued
                        ? _gold
                        : border,
                    width: selected ? 4 : 2,
                  ),
          ),
          backgroundColor: WidgetStatePropertyAll(
            selected
                ? _red.withValues(alpha: .13)
                : place.enabled
                ? _blue.withValues(alpha: .12)
                : Colors.black.withValues(alpha: .12),
          ),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: .15),
          ),
        ),
        child: Semantics(
          label: _description(place),
          selected: selected,
          excludeSemantics: true,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: const EdgeInsets.all(3),
                child: Opacity(
                  opacity: place.enabled ? 1 : .55,
                  child: place.kind == 'site'
                      ? ColoredBox(
                          color: journalSiteArtPaper,
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: widget.showLabels ? 32 : 0,
                            ),
                            child: JournalSiteArtwork(siteType: place.siteType),
                          ),
                        )
                      : _DistrictArtwork(place: place),
                ),
              ),
              if (place.shortcut != null)
                Positioned(
                  top: 3,
                  left: 3,
                  child: Container(
                    color: _paper,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      place.shortcut!.toUpperCase(),
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              if (place.current || place.queued)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: _paper,
                      border: Border.all(color: _ink),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      place.current ? Icons.my_location : Icons.flag,
                      size: 19,
                      color: place.current ? _red : const Color(0xFF785C15),
                    ),
                  ),
                ),
              if (widget.showLabels)
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: 3,
                  child: Container(
                    color: _paper.withValues(alpha: .96),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
                    child: Text(
                      place.name,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12 * labelScale,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        color: place.enabled ? _ink : const Color(0xFF67634E),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeIndex() => Material(
    color: _paper,
    child: SingleChildScrollView(
      key: const ValueKey('journal-location-index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final place in widget.places)
            ListTile(
              key: ValueKey('journal-map-index:${place.id}'),
              enabled: place.enabled || widget.allowUnavailableInspection,
              selected: place.id == widget.selectedId,
              selectedTileColor: _red.withValues(alpha: .12),
              selectedColor: _red,
              textColor: _ink,
              iconColor: _ink,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(place.name),
              trailing: place.shortcut == null
                  ? null
                  : Text(place.shortcut!.toUpperCase()),
              subtitle: Text(
                [
                  place.kind,
                  if (place.current) 'Current location',
                  if (place.queued) 'Queued destination',
                  if (!place.enabled) 'Unavailable',
                  ...place.details,
                ].join(' · '),
              ),
              leading: Icon(
                place.current
                    ? Icons.my_location
                    : place.queued
                    ? Icons.flag
                    : place.kind == 'site'
                    ? Icons.apartment
                    : Icons.location_city,
                size: 20,
              ),
              onTap: place.enabled || widget.allowUnavailableInspection
                  ? () => widget.onSelect(place.id)
                  : null,
            ),
          if (widget.places.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('No known locations in this view.'),
            ),
        ],
      ),
    ),
  );

  Widget _legend() => Container(
    color: _paper,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    child: Wrap(
      spacing: 10,
      runSpacing: 3,
      children: [
        _legendItem(_blue, 'Selectable'),
        _legendItem(_red, 'Selected'),
        _legendItem(_gold, 'Queued'),
        Text(
          '${widget.places.length} known · Drag to pan',
          style: const TextStyle(fontSize: 10, color: _ink),
        ),
      ],
    ),
  );

  Widget _legendItem(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(border: Border.all(color: color, width: 2)),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: _ink)),
    ],
  );
}

// Atlas order: shopping, downtown, industrial / campus, residential, rural.
// These are symbolic illustrations, never a claim about real site geography.
class _DistrictArtwork extends StatelessWidget {
  const _DistrictArtwork({required this.place});
  final JournalMapPlace place;

  int get _cell {
    final name = place.name.toLowerCase();
    if (RegExp(
      r'shopping|store|shop|mall|dealer|cafe|bar\b|cosmetics|co-op',
    ).hasMatch(name)) {
      return 0;
    }
    if (RegExp(
      r'industrial|warehouse|factory|plant|mill|genetics|laboratory',
    ).hasMatch(name)) {
      return 2;
    }
    if (RegExp(r'university|college|campus|school|park\b').hasMatch(name)) {
      return 3;
    }
    if (RegExp(
      r'outskirts|rural|country|eastern|farm|mountain|desert',
    ).hasMatch(name)) {
      return 5;
    }
    if (RegExp(
      r'residen|apartment|house|shelter|suburb|nursing|home\b',
    ).hasMatch(name)) {
      return 4;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => ClipRect(
      child: OverflowBox(
        // Preserve the square atlas's proportions, cropping the middle of
        // each portrait cell to the landscape lot rather than squashing roofs.
        alignment: Alignment(
          (_cell % 3) - 1.0,
          ((_cell ~/ 3) * 2.0 - 1) *
              (bounds.maxWidth * 1.5) /
              (bounds.maxWidth * 3 - bounds.maxHeight),
        ),
        minWidth: bounds.maxWidth * 3,
        maxWidth: bounds.maxWidth * 3,
        minHeight: bounds.maxWidth * 3,
        maxHeight: bounds.maxWidth * 3,
        child: Image.asset(
          'assets/modern/district_atlas_v1.webp',
          width: bounds.maxWidth * 3,
          height: bounds.maxWidth * 3,
          fit: BoxFit.fill,
          excludeFromSemantics: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

class _PlanLayout {
  _PlanLayout(List<JournalMapPlace> places, Size viewport) {
    final count = math.max(12, places.length);
    final aspect = viewport.width / math.max(1, viewport.height);
    columns = math.sqrt(count * aspect).round().clamp(3, 7);
    rows = (count / columns).ceil();
    size = Size(columns * 148.0 + 24, rows * 132.0 + 24);
    final occupied = <int>{};
    final ordered = [...places]..sort((a, b) => a.id.compareTo(b.id));
    for (final place in ordered) {
      var lot = _stableHash(place.id) % (columns * rows);
      while (occupied.contains(lot)) {
        lot = (lot + 1) % (columns * rows);
      }
      occupied.add(lot);
      rects[place.id] = Rect.fromLTWH(
        24 + (lot % columns) * 148.0,
        24 + (lot ~/ columns) * 132.0,
        124,
        108,
      );
    }
  }

  late final int columns, rows;
  late final Size size;
  final Map<String, Rect> rects = {};
}

int _stableHash(String value) {
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0x7fffffff;
  }
  return hash;
}

class _PlanPainter extends CustomPainter {
  _PlanPainter(this.layout);
  final _PlanLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _street);
    for (var row = 0; row < layout.rows; row++) {
      for (var col = 0; col < layout.columns; col++) {
        final block = Rect.fromLTWH(
          24 + col * 148.0,
          24 + row * 132.0,
          124,
          108,
        );
        final seed = _stableHash('$row:$col');
        canvas.drawRect(
          block.inflate(6),
          Paint()..color = const Color(0xFF484D40),
        );
        canvas.drawRect(
          block.inflate(3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF626650),
        );
        canvas.drawRect(block, Paint()..color = const Color(0xFF3C4237));
        // Painted known places provide the detail. Filler blocks stay quiet.
        if (layout.rects.values.contains(block)) continue;
        // Small buildings form an original varied top-down block texture.
        for (var by = 0; by < 2; by++) {
          for (var bx = 0; bx < 2; bx++) {
            final roof = Rect.fromLTWH(
              block.left + 12 + bx * 56.0,
              block.top + 12 + by * 47.0,
              37 + ((seed >> (bx + by)) % 5).toDouble(),
              30 + ((seed >> (bx * 2 + by)) % 4).toDouble(),
            );
            _roof(canvas, roof, (seed + bx * 7 + by * 13) % 6);
          }
        }
      }
    }
    final road = Paint()
      ..color = const Color(0xFF4B4E41)
      ..strokeWidth = 1;
    for (var col = 0; col <= layout.columns; col++) {
      final x = 12 + col * 148.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), road);
    }
    for (var row = 0; row <= layout.rows; row++) {
      final y = 12 + row * 132.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), road);
    }
  }

  void _roof(Canvas canvas, Rect roof, int tone) {
    const shades = [
      Color(0xFF535744),
      Color(0xFF505A48),
      Color(0xFF5D604F),
      Color(0xFF4C5444),
      Color(0xFF545E4E),
      Color(0xFF605E47),
    ];
    canvas.drawRect(
      roof.shift(const Offset(2, 3)),
      Paint()..color = const Color(0xFF22291F),
    );
    canvas.drawRect(roof, Paint()..color = shades[tone]);
    canvas.drawRect(
      roof.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF464B3B),
    );
    canvas.drawLine(
      roof.topLeft,
      roof.topRight,
      Paint()
        ..strokeWidth = 2
        ..color = const Color(0xFF71745E),
    );
    canvas.drawRect(
      Rect.fromLTWH(roof.left + 8, roof.top + 8, 6, 5),
      Paint()..color = const Color(0xFF454B40),
    );
    canvas.drawRect(
      Rect.fromLTWH(roof.right - 9, roof.bottom - 10, 4, 6),
      Paint()..color = const Color(0xFF72745B),
    );
  }

  @override
  bool shouldRepaint(_PlanPainter oldDelegate) =>
      oldDelegate.layout.columns != layout.columns ||
      oldDelegate.layout.rows != layout.rows ||
      !mapEquals(oldDelegate.layout.rects, layout.rects);
}
