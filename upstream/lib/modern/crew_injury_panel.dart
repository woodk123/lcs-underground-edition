import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/injury_anatomy.dart';
import 'package:lcs_new_age/modern/injury_status.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/recovery_help.dart';

const _amber = Color(0xFF956019);

/// A read-only medical plate. Previewing a location never sends engine input.
class CrewInjuryPanel extends StatefulWidget {
  const CrewInjuryPanel({super.key, required this.person});

  final Creature person;

  @override
  State<CrewInjuryPanel> createState() => _CrewInjuryPanelState();
}

class _CrewInjuryPanelState extends State<CrewInjuryPanel> {
  String? _pinned;
  String? _hovered;
  String? _focused;
  bool _showAll = false;

  @override
  void didUpdateWidget(covariant CrewInjuryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.person.id != widget.person.id) {
      _pinned = _hovered = _focused = null;
      _showAll = false;
    }
  }

  void _preview(String id, bool hovering) => setState(() {
    if (hovering) {
      _hovered = id;
    } else if (_hovered == id) {
      _hovered = null;
    }
  });

  void _focus(String id, bool focused) => setState(() {
    if (focused) {
      _focused = id;
    } else if (_focused == id) {
      _focused = null;
    }
  });

  void _pin(String id) => setState(() => _pinned = id);

  @override
  Widget build(BuildContext context) {
    final person = widget.person;
    final locations = injuryLocations(person);
    final affected = locations.where((location) => location.affected).toList()
      ..sort((a, b) => b.severity.index.compareTo(a.severity.index));
    final defaultLocation = affected.isEmpty ? locations.first : affected.first;
    final activeId = _hovered ?? _focused ?? _pinned;
    final active =
        locations.where((location) => location.id == activeId).firstOrNull ??
        defaultLocation;
    final humanoid = person.body.type == BodyType.human;
    return Column(
      key: const ValueKey('crew-injury-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _vitals(person, affected),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, bounds) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            final sideBySide =
                humanoid && bounds.maxWidth >= 610 && textScale < 1.6;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _details(active),
                const SizedBox(height: 16),
                _locations(locations, affected, active),
              ],
            );
            if (!humanoid) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${person.body.typeName} · condition by location',
                    style: JournalPalette.small,
                  ),
                  const SizedBox(height: 12),
                  details,
                ],
              );
            }
            final plate = _plate(locations, active);
            return sideBySide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 260, child: plate),
                      const SizedBox(width: 24),
                      Expanded(child: details),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SizedBox(
                          width: math.min(280, bounds.maxWidth),
                          child: plate,
                        ),
                      ),
                      const SizedBox(height: 18),
                      details,
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _vitals(Creature person, List<InjuryLocation> affected) {
    final fraction = person.maxBlood > 0
        ? (person.blood / person.maxBlood).clamp(0.0, 1.0)
        : 0.0;
    final bleeding = person.body.parts.fold<int>(
      0,
      (sum, part) => sum + part.bleeding,
    );
    final status = !person.alive
        ? 'Deceased'
        : bleeding > 0
        ? 'Active bleeding'
        : fraction < .25
        ? 'Very low blood'
        : fraction < .75
        ? 'Low blood'
        : affected.isNotEmpty
        ? 'Injuries recorded'
        : fraction < 1
        ? 'Recovering blood'
        : 'No recorded injuries';
    final color = !person.alive || bleeding > 0 || fraction < .5
        ? JournalPalette.danger
        : affected.isNotEmpty || fraction < 1
        ? _amber
        : JournalPalette.olive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 8,
          children: [
            const Text(
              'FIELD MEDICAL RECORD',
              style: TextStyle(
                fontFamily: 'ModernSans',
                fontSize: 10,
                letterSpacing: 1.8,
                color: JournalPalette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            _badge(
              status,
              color,
              !person.alive
                  ? Icons.person_off_outlined
                  : Icons.monitor_heart_outlined,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Blood',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${person.blood} / ${person.maxBlood}',
              key: const ValueKey('crew-dossier-blood'),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            color: color,
            backgroundColor: JournalPalette.rule.withValues(alpha: .4),
            semanticsLabel: 'Blood remaining',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            Text('Health ${person.health}', style: JournalPalette.small),
            if (person.permanentHealthDamage > 0)
              Text(
                'Permanent health loss ${person.permanentHealthDamage}',
                style: JournalPalette.small.copyWith(
                  color: JournalPalette.danger,
                ),
              ),
            if (bleeding > 0)
              Text(
                'Bleeding stacks $bleeding',
                style: JournalPalette.small.copyWith(
                  color: JournalPalette.danger,
                ),
              ),
          ],
        ),
        if (person.alive && fraction < 1) ...[
          const SizedBox(height: 9),
          const Text(
            'Blood loss reduces Strength, Agility, Charisma and Intelligence. '
            'Their values scale with blood remaining, with rounding and a minimum of 1.',
            style: JournalPalette.small,
          ),
        ],
        if (person.alive) ...[
          const SizedBox(height: 12),
          Text(
            dailyRecoveryHelp(person).first,
            key: const ValueKey('daily-recovery-rate'),
            style: JournalPalette.small.copyWith(fontWeight: FontWeight.w700),
          ),
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              key: const PageStorageKey('daily-recovery-explanation'),
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'How daily recovery works',
                style: JournalPalette.small,
              ),
              children: [
                for (final paragraph in dailyRecoveryHelp(person).skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(paragraph, style: JournalPalette.small),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (!person.alive) ...[
          const SizedBox(height: 9),
          Text(
            'Historical injury record. This person cannot act or recover.',
            style: JournalPalette.small.copyWith(color: JournalPalette.danger),
          ),
        ],
      ],
    );
  }

  Widget _plate(List<InjuryLocation> locations, InjuryLocation active) =>
      Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: JournalPalette.inset.withValues(alpha: .28),
          border: Border.all(color: JournalPalette.rule.withValues(alpha: .65)),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ANATOMICAL SURVEY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'ModernSans',
                fontSize: 9,
                letterSpacing: 1.7,
                color: JournalPalette.muted,
              ),
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: injuryAnatomyAspectRatio,
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final size = Size(bounds.maxWidth, bounds.maxHeight);
                  final markers = _markerPositions(locations);
                  return Stack(
                    key: const ValueKey('injury-map'),
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(child: CustomPaint(painter: _SurveyGrid())),
                      ExcludeSemantics(
                        child: Image.asset(
                          injuryAnatomyAsset,
                          fit: BoxFit.fill,
                          errorBuilder: (context, error, stack) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _InjuryOverlay(locations, active),
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _InjuryCallouts(markers, active),
                        ),
                      ),
                      for (final location in locations.where(
                        (location) =>
                            !location.internal &&
                            location.region != null &&
                            _partIds.contains(location.id),
                      ))
                        _regionTarget(location, active, size),
                      for (final location in locations.where(
                        (location) => markers.containsKey(location.id),
                      ))
                        Positioned(
                          left: markers[location.id]!.dx * size.width - 15,
                          top: markers[location.id]!.dy * size.height - 15,
                          width: 30,
                          height: 30,
                          child: _target(
                            location,
                            active,
                            'injury-marker:${location.id}',
                            marker: true,
                          ),
                        ),
                      const Positioned(
                        left: 2,
                        top: 72,
                        child: ExcludeSemantics(
                          child: Text('R', style: JournalPalette.small),
                        ),
                      ),
                      const Positioned(
                        right: 2,
                        top: 72,
                        child: ExcludeSemantics(
                          child: Text('L', style: JournalPalette.small),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Front view · sides are the character’s',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: JournalPalette.muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                _legend('Clear', JournalPalette.olive, Icons.circle_outlined),
                _legend('Injured', _amber, Icons.circle),
                _legend(
                  'Severe',
                  JournalPalette.danger,
                  Icons.warning_amber_rounded,
                ),
                _legend('Missing', JournalPalette.ink, Icons.close),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Hover to inspect. Select to keep a location open.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: JournalPalette.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      );

  Widget _target(
    InjuryLocation location,
    InjuryLocation active,
    String key, {
    bool marker = false,
  }) {
    final color = _severityColor(location.severity);
    final selected = active.id == location.id;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Inspect ${location.name}: ${_severityLabel(location.severity)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey(key),
          onTap: () => _pin(location.id),
          onHover: (value) => _preview(location.id, value),
          onFocusChange: (value) => _focus(location.id, value),
          customBorder: marker ? const CircleBorder() : null,
          hoverColor: JournalPalette.brass.withValues(alpha: .12),
          focusColor: JournalPalette.selected.withValues(alpha: .5),
          splashColor: JournalPalette.brass.withValues(alpha: .2),
          child: marker
              ? Center(
                  child: Container(
                    width: selected ? 20 : 16,
                    height: selected ? 20 : 16,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(color: JournalPalette.card, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: .25),
                          blurRadius: 0,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Icon(
                      location.severity == InjurySeverity.missing
                          ? Icons.close
                          : Icons.add,
                      size: selected ? 12 : 10,
                      color: JournalPalette.card,
                    ),
                  ),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _regionTarget(
    InjuryLocation location,
    InjuryLocation active,
    Size plateSize,
  ) {
    final bounds = injuryRegionPath(location.region!, plateSize).getBounds();
    return Positioned.fromRect(
      rect: bounds,
      child: ClipPath(
        clipper: _RegionClipper(location.region!, plateSize, bounds.topLeft),
        child: _target(location, active, 'injury-zone:${location.id}'),
      ),
    );
  }

  Widget _details(InjuryLocation location) {
    final color = _severityColor(location.severity);
    return Container(
      key: ValueKey('injury-detail:${location.id}'),
      constraints: const BoxConstraints(minHeight: 240),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: JournalPalette.card.withValues(alpha: .65),
        border: Border.all(color: JournalPalette.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                location.name,
                style: JournalPalette.heading.copyWith(fontSize: 20),
              ),
              _badge(
                _severityLabel(location.severity),
                color,
                _severityIcon(location.severity),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            location.findings.isEmpty
                ? 'No injury recorded at this location.'
                : location.findings.join(' · '),
            style: JournalPalette.body.copyWith(
              color: location.affected ? color : JournalPalette.muted,
            ),
          ),
          if (location.tissueHealth != null &&
              location.severity != InjurySeverity.missing &&
              !location.findings.any((s) => s.contains('tissue health'))) ...[
            const SizedBox(height: 8),
            Text(
              '${(location.tissueHealth!.clamp(0, 1) * 100).round()}% tissue health',
              style: JournalPalette.small,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: JournalPalette.rule),
          ),
          _detailLabel('GAMEPLAY IMPACT', Icons.sports_martial_arts_outlined),
          const SizedBox(height: 6),
          if (location.effects.isEmpty)
            const Text(
              'No location-specific injury penalty.',
              style: JournalPalette.body,
            ),
          for (final effect in location.effects)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(effect, style: JournalPalette.body),
            ),
          const SizedBox(height: 9),
          _detailLabel(
            widget.person.alive ? 'CARE & RECOVERY' : 'MEDICAL RECORD',
            Icons.medical_services_outlined,
          ),
          const SizedBox(height: 6),
          Text(
            widget.person.alive ? location.care : 'Injuries are retained for the historical record. Treatment is unavailable after death.',
            style: JournalPalette.small,
          ),
        ],
      ),
    );
  }

  Widget _locations(
    List<InjuryLocation> locations,
    List<InjuryLocation> affected,
    InjuryLocation active,
  ) {
    final listed = _showAll || affected.isEmpty ? locations : affected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          affected.isEmpty ? 'Inspect a location' : 'Recorded injuries',
          style: JournalPalette.heading.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 7),
        for (final location in listed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Semantics(
              selected: active.id == location.id,
              child: TextButton(
                key: ValueKey('injury-row:${location.id}'),
                onPressed: () => _pin(location.id),
                onHover: (value) => _preview(location.id, value),
                onFocusChange: (value) => _focus(location.id, value),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  minimumSize: const Size(44, 48),
                  foregroundColor: JournalPalette.ink,
                  backgroundColor: active.id == location.id
                      ? JournalPalette.selected.withValues(alpha: .7)
                      : Colors.transparent,
                  side: BorderSide(
                    color: active.id == location.id
                        ? JournalPalette.brass
                        : JournalPalette.rule.withValues(alpha: .4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        _severityIcon(location.severity),
                        size: 15,
                        color: _severityColor(location.severity),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _locationSummary(location),
                        style: JournalPalette.small.copyWith(
                          color: JournalPalette.ink,
                        ),
                      ),
                    ),
                    if (_pinned == location.id) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.push_pin_outlined,
                        size: 13,
                        color: JournalPalette.muted,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (affected.isNotEmpty && locations.length > affected.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('injury-all-locations'),
              onPressed: () => setState(() => _showAll = !_showAll),
              icon: Icon(_showAll ? Icons.remove : Icons.add, size: 14),
              label: Text(
                _showAll ? 'Show injured locations' : 'Inspect all locations',
                style: JournalPalette.small,
              ),
            ),
          ),
      ],
    );
  }
}

Widget _badge(String label, Color color, IconData icon) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .07),
    border: Border.all(color: color.withValues(alpha: .35)),
    borderRadius: BorderRadius.circular(2),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'ModernSans',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    ],
  ),
);

Widget _detailLabel(String text, IconData icon) => Row(
  children: [
    Icon(icon, size: 13, color: JournalPalette.muted),
    const SizedBox(width: 6),
    Expanded(
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'ModernSans',
          fontSize: 10,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
          color: JournalPalette.muted,
        ),
      ),
    ),
  ],
);

Widget _legend(String label, Color color, IconData icon) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Icon(icon, size: 9, color: color),
    const SizedBox(width: 4),
    Text(
      label,
      style: const TextStyle(fontSize: 9, color: JournalPalette.muted),
    ),
  ],
);

Color _severityColor(InjurySeverity severity) => switch (severity) {
  InjurySeverity.healthy => JournalPalette.olive,
  InjurySeverity.minor => _amber,
  InjurySeverity.serious || InjurySeverity.critical => JournalPalette.danger,
  InjurySeverity.missing => JournalPalette.ink,
};

String _severityLabel(InjurySeverity severity) => switch (severity) {
  InjurySeverity.healthy => 'Clear',
  InjurySeverity.minor => 'Injured',
  InjurySeverity.serious => 'Serious',
  InjurySeverity.critical => 'Critical',
  InjurySeverity.missing => 'Missing',
};

IconData _severityIcon(InjurySeverity severity) => switch (severity) {
  InjurySeverity.healthy => Icons.check_circle_outline,
  InjurySeverity.minor => Icons.circle_outlined,
  InjurySeverity.serious ||
  InjurySeverity.critical => Icons.warning_amber_rounded,
  InjurySeverity.missing => Icons.close,
};

const _partIds = {
  'head',
  'torso',
  'left-arm',
  'right-arm',
  'left-leg',
  'right-leg',
};

String _locationSummary(InjuryLocation location) {
  final findings = location.findings
      .map(
        (finding) => finding == 'Tissue damage' && location.tissueHealth != null
            ? '${(location.tissueHealth!.clamp(0, 1) * 100).round()}% tissue health'
            : finding,
      )
      .join(', ');
  return '${location.name} · ${findings.isEmpty ? 'No recorded injury' : findings}';
}

class _RegionClipper extends CustomClipper<Path> {
  const _RegionClipper(this.region, this.plateSize, this.origin);
  final InjuryRegion region;
  final Size plateSize;
  final Offset origin;
  @override
  Path getClip(Size size) => injuryRegionPath(region, plateSize).shift(-origin);
  @override
  bool shouldReclip(_RegionClipper oldClipper) =>
      oldClipper.region != region ||
      oldClipper.plateSize != plateSize ||
      oldClipper.origin != origin;
}

// Small facial/organ targets would overlap on the figure. Distribute callout
// buttons in two outside columns, connected to their actual anatomical anchor.
// The equivalent full-width rows are the primary touch targets.
Map<String, Offset> _markerPositions(List<InjuryLocation> locations) {
  final specials = locations
      .where(
        (location) =>
            location.affected && injuryOrganAnchors.containsKey(location.id),
      )
      .toList();
  final result = <String, Offset>{};
  final left = <InjuryLocation>[];
  final right = <InjuryLocation>[];
  for (final location in specials) {
    final x = injuryOrganAnchors[location.id]!.dx;
    final central = (x - .5).abs() < .025;
    if (central ? left.length <= right.length : x < .5) {
      left.add(location);
    } else {
      right.add(location);
    }
  }
  for (final (side, x) in [(left, .075), (right, .925)]) {
    side.sort(
      (a, b) =>
          injuryOrganAnchors[a.id]!.dy.compareTo(injuryOrganAnchors[b.id]!.dy),
    );
    final step = math.min(.095, .9 / math.max(1, side.length - 1));
    var previous = -.05;
    for (var index = 0; index < side.length; index++) {
      final id = side[index].id;
      final lower = .045 + index * step;
      final upper = .955 - (side.length - 1 - index) * step;
      final y = math
          .max(injuryOrganAnchors[id]!.dy, previous + step)
          .clamp(lower, upper);
      result[id] = Offset(x, y);
      previous = y;
    }
  }
  return result;
}

class _InjuryCallouts extends CustomPainter {
  const _InjuryCallouts(this.positions, this.active);
  final Map<String, Offset> positions;
  final InjuryLocation active;

  @override
  void paint(Canvas canvas, Size size) {
    Offset scaled(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    for (final entry in positions.entries) {
      final selected = active.id == entry.key;
      final from = scaled(injuryOrganAnchors[entry.key]!);
      final to = scaled(entry.value);
      final color = selected ? JournalPalette.danger : JournalPalette.brassDark;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo((from.dx + to.dx) / 2, to.dy)
        ..lineTo(to.dx, to.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: selected ? .85 : .4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 1.2 : .7,
      );
      canvas.drawCircle(from, selected ? 3 : 2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_InjuryCallouts oldDelegate) => true;
}

class _InjuryOverlay extends CustomPainter {
  const _InjuryOverlay(this.locations, this.active);
  final List<InjuryLocation> locations;
  final InjuryLocation active;

  @override
  void paint(Canvas canvas, Size size) {
    for (final region in InjuryRegion.values) {
      final regional = locations.where((location) => location.region == region);
      var severity = InjurySeverity.healthy;
      for (final location in regional) {
        // A missing eye must not hatch the whole head as if it were missing.
        final regionalSeverity =
            location.severity == InjurySeverity.missing &&
                !_partIds.contains(location.id)
            ? InjurySeverity.serious
            : location.severity;
        if (regionalSeverity.index > severity.index) {
          severity = regionalSeverity;
        }
      }
      final selected = active.region == region;
      if (severity == InjurySeverity.healthy && !selected) continue;
      final path = injuryRegionPath(region, size);
      final color = _severityColor(severity);
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: selected ? .32 : .27),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: selected ? .95 : .85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1.25,
      );
      if (severity == InjurySeverity.missing) {
        canvas.save();
        canvas.clipPath(path);
        for (double x = -size.height; x < size.width; x += 8) {
          canvas.drawLine(
            Offset(x, 0),
            Offset(x + size.height, size.height),
            Paint()
              ..color = color.withValues(alpha: .3)
              ..strokeWidth = .8,
          );
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_InjuryOverlay oldDelegate) => true;
}

class _SurveyGrid extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = JournalPalette.rule.withValues(alpha: .25)
      ..strokeWidth = .6;
    for (final y in [.2, .52, .76, .97]) {
      canvas.drawLine(
        Offset(10, size.height * y),
        Offset(size.width - 10, size.height * y),
        paint,
      );
    }
    for (double y = 0; y < size.height; y += 6) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SurveyGrid oldDelegate) => false;
}
