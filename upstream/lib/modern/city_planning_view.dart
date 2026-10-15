import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/city_scene.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

const _ink = JournalPalette.ink;
const _muted = JournalPalette.muted;
const _teal = JournalPalette.olive;
const _red = JournalPalette.danger;
const _paper = JournalPalette.card;
const _rule = JournalPalette.rule;

/// Browsing cities and districts opens their original destination list directly.
/// Building inspection is local; explicit orders dispatch the engine command.
class CityPlanningView extends StatefulWidget {
  const CityPlanningView({
    super.key,
    required this.console,
    required this.onAction,
    this.viewportHeight,
  });
  final Console console;
  final ValueChanged<String> onAction;

  /// Height available inside the workspace panel, after its padding.
  final double? viewportHeight;
  @override
  State<CityPlanningView> createState() => _CityPlanningViewState();
}

class _CityPlanningViewState extends State<CityPlanningView> {
  bool _list = false;
  String? _selectedId;
  String? _selectedCrewId;
  bool _squadDetails = false;
  final _crewScroll = ScrollController();

  @override
  void dispose() {
    _crewScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: widget.console.revision,
    builder: (context, revision, child) {
      final frame = _PlanningFrame(widget.console);
      final selected = frame.destinations
          .where((d) => d.id == _selectedId)
          .firstOrNull;
      final person = game.activeSquad?.members
          .where(
            (p) =>
                '${p.id}' == _selectedCrewId &&
                frame.crew.any((m) => m.id == _selectedCrewId),
          )
          .firstOrNull;
      return DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: JournalPalette.serif,
          color: _ink,
          fontSize: 14,
          height: 1.4,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height =
                widget.viewportHeight ??
                (MediaQuery.sizeOf(context).height - 80).clamp(460.0, 800.0);
            final wide = constraints.maxWidth >= 640;
            final footer = _footer(frame);
            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _squad(frame),
                const SizedBox(height: 7),
                _heading(frame, wide),
                const SizedBox(height: 7),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, body) =>
                        _body(frame, selected, person, body.maxHeight, wide),
                  ),
                ),
                const SizedBox(height: 6),
                footer,
              ],
            );
            return SizedBox(
              key: const ValueKey('city-viewport'),
              height: height,
              child: content,
            );
          },
        ),
      );
    },
  );

  Widget _heading(_PlanningFrame frame, bool wide) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          frame.area.isEmpty ? 'City operations' : frame.area,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        const Text(
          'Open a district directly. Inspect a building to queue a squad visit.',
          style: TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    );
    final switcher = SegmentedButton<bool>(
      key: const ValueKey('city-view-switch'),
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.location_city, size: 16),
          label: Text('City streets'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.view_list_outlined, size: 16),
          label: Text('Locations list'),
        ),
      ],
      selected: {_list},
      onSelectionChanged: (value) => setState(() => _list = value.single),
      showSelectedIcon: false,
    );
    return wide
        ? Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              switcher,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 8), switcher],
          );
  }

  Widget _body(
    _PlanningFrame frame,
    _Destination? selected,
    Creature? person,
    double height,
    bool wide,
  ) {
    final scene = _list
        ? SingleChildScrollView(child: _locations(frame))
        : CityScene(
            key: ValueKey('city-scene:${frame.area}'),
            viewportHeight: height,
            buildings: frame.destinations.map((d) => d.building).toList(),
            selectedId: selected?.id,
            onInspect: (id) => _inspect(frame, id),
          );
    final inspection = person != null || selected != null || _squadDetails;
    final inspectorHeight = wide ? height : math.min<double>(210, height * .48);
    final inspector = person != null
        ? CrewInspector(
            key: ValueKey('city-crew-inspector:${person.id}'),
            person: person,
            onClose: _closeInspection,
            compact: !wide,
          )
        : _squadDetails
        ? _squadInspector(frame)
        : _inspector(
            frame,
            selected,
            height: inspectorHeight,
            compact: !wide || inspectorHeight < 260,
          );
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: frame.destinations.isEmpty
                ? const Center(child: Text('No destinations are listed here.'))
                : scene,
          ),
          if (inspection) ...[
            const SizedBox(width: 10),
            SizedBox(width: 264, child: inspector),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: scene),
        if (inspection) ...[
          const SizedBox(height: 7),
          SizedBox(height: inspectorHeight, child: inspector),
        ],
      ],
    );
  }

  Widget _footer(_PlanningFrame frame) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    spacing: 8,
    runSpacing: 5,
    children: [
      for (final destination in frame.travel) _travel(frame, destination),
      for (final action in frame.navigation) _navigation(frame, action),
    ],
  );

  Widget _squad(_PlanningFrame frame) {
    final squad = game.activeSquad;
    final members = squad?.members ?? [];
    return Container(
      key: const ValueKey('city-squad-context'),
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: JournalPalette.inset,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _rule),
      ),
      child: Row(
        children: [
          Tooltip(
            message:
                '${squad?.name ?? 'Selected squad'}\nCurrent order: ${squad?.activity.description ?? 'None'}',
            child: SizedBox(
              width: 98,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${squad?.name ?? 'Squad'}\n${squad?.activity.description ?? 'No order'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _crewScroll,
              thumbVisibility: true,
              child: ListView.separated(
                key: const ValueKey('city-crew-strip'),
                controller: _crewScroll,
                scrollDirection: Axis.horizontal,
                itemCount: frame.crew.length,
                separatorBuilder: (context, index) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final member = frame.crew[index];
                  final person = members
                      .where(
                        (p) =>
                            member.id != null && p.id.toString() == member.id,
                      )
                      .firstOrNull;
                  final chip = SizedBox(
                    width: person == null ? 155 : 180,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      child: Row(
                        children: [
                          if (person != null) ...[
                            CrewPortrait(person: person, size: 34),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  [
                                    if (member.health.isNotEmpty)
                                      'Health ${member.health}',
                                    if (member.transport.isNotEmpty)
                                      member.transport,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: _teal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  return Material(
                    color: _selectedCrewId == member.id && member.id != null
                        ? JournalPalette.selected
                        : _paper,
                    borderRadius: BorderRadius.circular(7),
                    child: Tooltip(
                      message: person == null
                          ? member.details.join('\n')
                          : 'Inspect ${member.name} alongside the city',
                      child: person == null
                          ? chip
                          : Semantics(
                              button: true,
                              label:
                                  'Inspect ${person.name} alongside the city',
                              child: InkWell(
                                key: ValueKey('city-crew-dossier:${person.id}'),
                                borderRadius: BorderRadius.circular(7),
                                onTap: () {
                                  if (!_liveFrame(frame)) return;
                                  setState(() {
                                    _selectedCrewId = '${person.id}';
                                    _selectedId = null;
                                    _squadDetails = false;
                                  });
                                },
                                child: ExcludeSemantics(child: chip),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 7),
          IconButton(
            key: const ValueKey('city-squad-details'),
            tooltip: 'Squad equipment & skills',
            isSelected: _squadDetails,
            onPressed: () => setState(() {
              _squadDetails = !_squadDetails;
              _selectedId = null;
              _selectedCrewId = null;
            }),
            icon: const Icon(Icons.info_outline, size: 21, color: _teal),
          ),
        ],
      ),
    );
  }

  Widget _squadInspector(_PlanningFrame frame) => Container(
    key: const ValueKey('city-squad-inspector'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _paper,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _rule),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                game.activeSquad?.name ?? 'Selected squad',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const ValueKey('city-squad-close'),
              tooltip: 'Close squad inspection',
              onPressed: _closeInspection,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 17),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current order: ${game.activeSquad?.activity.description ?? 'None'}',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Orders resolve when you advance the day. Browsing the city or inspecting crew changes no orders.',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
                const SizedBox(height: 10),
                for (final member in frame.crew)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          member.details.join(' · '),
                          style: const TextStyle(fontSize: 13, color: _muted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _inspector(
    _PlanningFrame frame,
    _Destination? destination, {
    required double height,
    bool compact = false,
  }) => Container(
    key: const ValueKey('city-building-inspector'),
    height: height,
    padding: EdgeInsets.all(compact ? 10 : 12),
    decoration: BoxDecoration(
      color: _paper,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _rule),
    ),
    child: destination == null
        ? const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.location_city, size: 30, color: _teal),
                SizedBox(height: 12),
                Text(
                  'On the street',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 8),
                Text(
                  'Select a building to inspect its known conditions and available order.',
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                SizedBox(height: 12),
                Text(
                  'Inspection keeps your current orders and does not advance the day.',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      destination.kindLabel.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: _muted,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('city-close-inspector'),
                    tooltip: 'Close inspection',
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _closeInspection,
                    icon: const Icon(Icons.close, size: 17),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        destination.name,
                        style: TextStyle(
                          fontSize: compact ? 16 : 20,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (destination.tags.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in destination.tags) _badge(tag),
                          ],
                        ),
                      if (destination.queued) ...[
                        const SizedBox(height: 7),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _badge('Visit queued'),
                        ),
                      ],
                      if (destination.note.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Text(
                          destination.note,
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                      for (final explanation in destination.explanations)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Text(
                            explanation,
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                        ),
                      const SizedBox(height: 7),
                      Text(
                        destination.isSite
                            ? 'Queue a visit for the selected squad. The visit starts when you advance the day.'
                            : 'Open this ${destination.kindLabel.toLowerCase()} to inspect its available destinations.',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                key: ValueKey('city-order:${destination.id}'),
                onPressed: _activate(frame, destination.action),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
                icon: Icon(
                  destination.action.enabled
                      ? destination.isSite
                            ? Icons.assignment_turned_in_outlined
                            : Icons.arrow_forward
                      : Icons.lock_outline,
                  size: 17,
                ),
                label: Text(
                  destination.orderLabel,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (!destination.action.enabled && !compact)
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Text(
                    'Order unavailable under the conditions above.',
                    style: TextStyle(fontSize: 10, color: _red),
                  ),
                ),
            ],
          ),
  );

  Widget _locations(_PlanningFrame frame) => Column(
    key: const ValueKey('city-locations-list'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final destination in frame.destinations)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            key: ValueKey(
              'direct-action:${destination.action.y}:${destination.action.x}:${destination.action.key}',
            ),
            label:
                '${destination.isArea && destination.action.enabled ? 'Open' : 'Inspect'} ${destination.name}',
            value: destination.details.join('. '),
            button: true,
            onTap: () {
              _inspect(frame, destination.id);
            },
            excludeSemantics: true,
            child: OutlinedButton(
              onPressed: () {
                _inspect(frame, destination.id);
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: _selectedId == destination.id
                    ? const Color(0xFFE5EEE7)
                    : _paper,
                foregroundColor: _ink,
                padding: const EdgeInsets.all(11),
                alignment: Alignment.centerLeft,
              ),
              child: Row(
                children: [
                  Icon(
                    destination.action.enabled
                        ? Icons.location_city
                        : Icons.lock_outline,
                    color: destination.action.enabled ? _teal : _muted,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          destination.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (destination.details.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(
                              destination.details.join(' · '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: _muted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    destination.isArea && destination.action.enabled
                        ? 'Open'
                        : 'Inspect',
                    style: const TextStyle(color: _teal, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _badge(String tag) {
    final danger = [
      'Closed Down',
      'Under Siege',
      'Need Car',
      'High Security',
    ].any(tag.contains);
    final color = danger ? _red : _teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .085),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _travel(
    _PlanningFrame frame,
    _Destination destination,
  ) => OutlinedButton.icon(
    key: ValueKey(
      'direct-action:${destination.action.y}:${destination.action.x}:${destination.action.key}',
    ),
    onPressed: _activate(frame, destination.action),
    icon: const Icon(Icons.public, size: 19),
    label: Text([destination.name, ...destination.details].join(' · ')),
  );

  Widget _navigation(_PlanningFrame frame, ConsoleAction action) {
    final isBack = action.key == 'Enter' || action.key == 'Escape';
    return Semantics(
      key: ValueKey('direct-action:${action.y}:${action.x}:${action.key}'),
      label: action.label,
      button: true,
      enabled: action.enabled,
      child: OutlinedButton.icon(
        onPressed: _activate(frame, action),
        icon: Icon(
          isBack || action.key == 'PageUp'
              ? Icons.arrow_back_rounded
              : Icons.arrow_forward_rounded,
          size: 17,
        ),
        label: Text(
          action.label.contains('not yet Liberal enough')
              ? 'Cancel this visit'
              : _title(action),
        ),
      ),
    );
  }

  bool _liveFrame(_PlanningFrame frame) =>
      widget.console.revision.value == frame.revision;

  void _inspect(_PlanningFrame frame, String id) {
    if (!_liveFrame(frame)) return;
    final destination = frame.destinations.where((d) => d.id == id).firstOrNull;
    if (destination == null) return;
    // Opening a city or district only changes the destination list. It needs
    // no inspection/confirmation step; sites still require a deliberate order.
    if (destination.isArea && destination.action.enabled) {
      _activate(frame, destination.action)?.call();
      setState(() {
        _selectedId = null;
        _selectedCrewId = null;
        _squadDetails = false;
      });
      return;
    }
    setState(() {
      _selectedId = id;
      _selectedCrewId = null;
      _squadDetails = false;
    });
  }

  void _closeInspection() => setState(() {
    _selectedId = null;
    _selectedCrewId = null;
    _squadDetails = false;
  });

  VoidCallback? _activate(_PlanningFrame frame, ConsoleAction action) {
    if (!action.enabled) return null;
    return () {
      if (_liveFrame(frame) &&
          widget.console.actions.any((live) => identical(live, action))) {
        widget.onAction(action.key);
      }
    };
  }
}

String _title(ConsoleAction action) =>
    action.label.replaceFirst(RegExp(r'^\s*\S+\s+[-–—]\s*'), '').trim();

class _PlanningFrame {
  _PlanningFrame(Console console) : revision = console.revision.value {
    String slice(int y, int start, int end) => console.buffer[y]
        .sublist(start.clamp(0, console.width), end.clamp(0, console.width))
        .map((cell) => cell.glyph)
        .join()
        .trim();
    area = slice(
      8,
      0,
      console.width,
    ).replaceAll(RegExp(r'[—═─━]{2,}'), '').trim();
    final actions = List<ConsoleAction>.of(console.actions);
    for (final action in actions) {
      if (action.y >= 2 && action.y <= 7 && action.x == 0) {
        crew.add(
          _CrewMember(
            id: action.entityType == 'person' ? action.entityId : null,
            name: action.label.replaceFirst(RegExp(r'^\d\s+'), ''),
            skill: slice(action.y, 23, 29),
            weapon: slice(action.y, 29, 44),
            armor: slice(action.y, 44, 59),
            health: slice(action.y, 59, 70),
            transport: slice(action.y, 70, console.width),
          ),
        );
        continue;
      }
      final isTravel = action.label.contains('Travel to a Different City');
      if ((action.y >= 10 && action.y <= 20 && action.x < 50) || isTravel) {
        final start = math.min(console.width, action.x + action.width);
        final end = actions
            .where((other) => other.y == action.y && other.x >= start)
            .fold(console.width, (end, other) => math.min(end, other.x));
        var details = slice(action.y, start, end);
        final tags = RegExp(
          r'\(([^)]+)\)',
        ).allMatches(details).map((match) => match.group(1)!).toList();
        details = details.replaceAll(RegExp(r'\([^)]+\)'), '').trim();
        for (final match in RegExp(
          r'(?:Heat|Secrecy):\s*\S+',
        ).allMatches(details)) {
          tags.add(match.group(0)!);
        }
        details = details
            .replaceAll(RegExp(r'(?:Heat|Secrecy):\s*\S+'), '')
            .replaceAll(RegExp(r'\s{2,}'), ' ')
            .trim();
        final destination = _Destination(action, _title(action), tags, details);
        (isTravel ? travel : destinations).add(destination);
      } else if (action.y >= 22 || action.x >= 50) {
        navigation.add(action);
      }
    }
    destinations.sort((a, b) => a.action.y.compareTo(b.action.y));
  }
  final int revision;
  late final String area;
  final List<_CrewMember> crew = [];
  final List<_Destination> destinations = [], travel = [];
  final List<ConsoleAction> navigation = [];
}

class _Destination {
  const _Destination(this.action, this.name, this.tags, this.note);
  final ConsoleAction action;
  final String name, note;
  final List<String> tags;
  String get id => action.entityId ?? '${action.y}:${action.key}:$name';
  bool get current => tags.contains('Current Location');
  bool get isSite => action.entityType == 'site';
  bool get isArea =>
      action.entityType == 'city' || action.entityType == 'district';
  bool get queued =>
      isSite &&
      game.activeSquad?.activity.type == ActivityType.visit &&
      game.activeSquad?.activity.idString == action.entityId;
  String get kindLabel => switch (action.entityType) {
    'district' => 'District',
    'city' => 'City',
    'site' => 'Building',
    _ => 'Destination',
  };
  String get orderLabel => switch (action.entityType) {
    'district' => 'Enter district',
    'city' => 'Open city',
    'site' => queued ? 'Keep visit queued' : 'Queue squad visit',
    _ => 'Choose destination',
  };
  List<String> get details => [...tags, if (note.isNotEmpty) note];
  List<String> get explanations {
    final heat = tags.where((tag) => tag.startsWith('Heat:')).firstOrNull;
    final secrecy = tags.where((tag) => tag.startsWith('Secrecy:')).firstOrNull;
    return [
      if (tags.contains('Need Car'))
        'A squad member needs a preferred vehicle to reach a different area.',
      if (tags.contains('Closed Down'))
        'This site is closed. The squad cannot queue a visit while it remains closed.',
      if (tags.contains('Under Siege'))
        'This site is under siege and cannot be selected for a visit.',
      if (tags.contains('High Security'))
        'This site has extra security. The visit is available, but you may face stronger protection inside.',
      if (heat != null || secrecy != null)
        'Heat is attention on this safehouse; secrecy is its protection against discovery. Heat above secrecy increases police search pressure during daily updates. These values are not percentages.',
      if (tags.contains('Current Location'))
        'The selected squad is currently based here.',
      if (queued)
        'This is the squad’s current visit order. Choose another building to replace it, or keep this order.',
    ];
  }

  int get spriteIndex =>
      _spriteFor(action.entityCategory ?? name, action.entityType);
  CitySceneBuilding get building => CitySceneBuilding(
    id: id,
    name: name,
    spriteIndex: spriteIndex,
    enabled: action.enabled,
    current: current,
    queued: queued,
    district: isArea,
    details: details,
  );
}

int _spriteFor(String category, String? kind) {
  final name = category.toLowerCase();
  if (RegExp('warehouse|shelter|bunker').hasMatch(name)) return 3;
  if (RegExp('industry|industrial|sweatshop|nuclear|factory').hasMatch(name)) {
    return 4;
  }
  if (RegExp('radio|news|media').hasMatch(name)) return 5;
  if (RegExp('court').hasMatch(name)) return 6;
  if (RegExp('police|fire|intelligence|army').hasMatch(name)) return 7;
  if (RegExp('hospital|clinic|nursing').hasMatch(name)) return 8;
  if (RegExp('university|lab|genetic|cosmetic').hasMatch(name)) return 9;
  if (RegExp('bank').hasMatch(name)) return 10;
  if (RegExp('prison|oubliette').hasMatch(name)) return 11;
  if (RegExp('corporat|insurance|downtown|office').hasMatch(name)) return 12;
  if (RegExp('mansion|ceo|house').hasMatch(name)) return 13;
  if (RegExp('rural|farm|outskirts|out of town').hasMatch(name)) return 14;
  if (RegExp('white house|party hq|civic').hasMatch(name) || kind == 'city') {
    return 15;
  }
  if (RegExp('cafe|latte|juice|bar|grill|vegan').hasMatch(name)) return 2;
  if (RegExp('shop|store|dealer|market|commercial').hasMatch(name)) return 1;
  return 0;
}

class _CrewMember {
  const _CrewMember({
    this.id,
    required this.name,
    required this.skill,
    required this.weapon,
    required this.armor,
    required this.health,
    required this.transport,
  });
  final String name, skill, weapon, armor, health, transport;
  final String? id;
  List<String> get details => [
    if (skill.isNotEmpty) 'Skill: $skill',
    if (weapon.isNotEmpty) 'Weapon: $weapon',
    if (armor.isNotEmpty) 'Armor: $armor',
    if (health.isNotEmpty) 'Health: $health',
    if (transport.isNotEmpty) 'Transport: $transport',
  ];
}
