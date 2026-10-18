import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/engine/recovery_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/district.dart';
import 'package:lcs_new_age/location/location.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_city_plan.dart';
import 'package:lcs_new_age/modern/journal_network.dart';
import 'package:lcs_new_age/modern/journal_order_icon.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_indicator.dart';
import 'package:lcs_new_age/modern/location_details.dart';
import 'package:lcs_new_age/modern/location_help.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/modern/recruitment_target_picker.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/modern/travel_help.dart';

// Existing section IDs remain stable for retained journal routes and shortcuts.
const networkJournalSection = 8;

/// The organiser is one open journal: team and job card on the left, the
/// selected report, pool, or target map on the right. Changing a portrait or a
/// page is local; only the controller dispatches original engine commands.
class OrganisationJournal extends StatefulWidget {
  const OrganisationJournal({
    super.key,
    required this.console,
    required this.controller,
    required this.onAction,
    required this.onInspect,
    required this.onHelp,
    required this.onClassic,
    required this.onTextScale,
    this.section = 0,
    this.onSection,
    this.textScale = 1,
    this.detail,
    this.fullSpreadDetail = false,
    this.inspectedPerson,
    this.onCloseInspection,
    this.inspectorActions = const [],
  });

  final Console console;
  final OrganisationController controller;
  final ValueChanged<String> onAction;
  final ValueChanged<Creature> onInspect;
  final VoidCallback onHelp, onClassic;
  final ValueChanged<double> onTextScale;
  final int section;
  final ValueChanged<int>? onSection;
  final double textScale;
  final Widget? detail;
  final bool fullSpreadDetail;
  final Creature? inspectedPerson;
  final VoidCallback? onCloseInspection;
  final List<CrewDossierAction> inspectorActions;

  @override
  State<OrganisationJournal> createState() => OrganisationJournalState();
}

class OrganisationJournalState extends State<OrganisationJournal> {
  final _networkKey = GlobalKey<JournalNetworkViewState>();
  final ScrollController _narrowJournalScroll = ScrollController();
  final PersonnelDirectoryController _personnel =
      PersonnelDirectoryController();

  @override
  void dispose() {
    _narrowJournalScroll.dispose();
    _personnel.dispose();
    super.dispose();
  }

  bool _orders = false, _skills = false, _pool = false;
  bool _showReports = false;
  bool _personnelTools = false;
  Skill _poolSort = Skill.firearms;
  int _group = 0;
  int? _poolPerson;
  String? _areaId, _targetId, _categoryId;
  ConsoleAction? _pendingOrder;
  List<ConsoleAction> _orderBrowseActions = const [];
  int? _pendingRevision;
  int? _targetSquadId;
  bool _visitRouting = false;
  String? _visitMessage;
  int _visitRequest = 0;
  bool get hasPreparedOrder =>
      _pendingOrder != null &&
      _pendingRevision == console.revision.value &&
      console.actions.contains(_pendingOrder) &&
      activityFrame;

  Console get console => widget.console;
  OrganisationController get controller => widget.controller;
  Squad? get squad => controller.selectedSquad ?? game.activeSquad;
  bool get undercover =>
      confirmation?.entityType == 'sleeper-activity-confirm' ||
      !allocating && controller.selectedPerson?.sleeperAgent == true;
  List<Creature> get members => controller.assembly != null
      ? controller.allocationMembers
      : undercover
      ? game.pool.where((p) => p.sleeperAgent && p.alive).toList()
      : squad?.members ?? const [];
  Creature? get person {
    final profile = console.journalProfile;
    if (profile != null) return profile.person;
    final actorId = int.tryParse(confirmation?.entityCategory ?? '');
    if (actorId != null) {
      return game.pool.where((p) => p.id == actorId).firstOrNull;
    }
    final inspected = controller.selectedPerson;
    if (!members.any((p) => p.id == inspected?.id)) {
      return members.firstOrNull;
    }
    return inspected ?? members.firstOrNull;
  }

  ConsoleAction? get confirmation => console.actions
      .where(
        (action) =>
            action.entityType == 'activity-confirm' ||
            action.entityType == 'sleeper-activity-confirm',
      )
      .firstOrNull;
  bool get activityFrame => activityOrderFrame(console) != null;
  bool get planning => console.screen == 'planning';
  bool get allocating => controller.assembly != null;
  bool get overview => console.screen == 'organisation';
  bool get _compactMapText =>
      widget.textScale > 1.1 && MediaQuery.sizeOf(context).width < 1000;
  Site? get _selectedDestination => _targetSquadId == squad?.id
      ? game.sites
            .where((site) => site.idString == _targetId && !site.hidden)
            .firstOrNull
      : null;
  ConsoleAction? get _visitAction => planning
      ? console.actions
            .where(
              (action) =>
                  action.entityType == 'site' &&
                  action.entityId == _selectedDestination?.idString,
            )
            .firstOrNull
      : null;

  /// Journal shortcuts use the same prepare/confirm path as pointer controls.
  /// The original immediate keyboard handlers remain available in Classic view.
  bool handleGameShortcut(String key) {
    if (widget.section == networkJournalSection &&
        _networkKey.currentState != null) {
      return _networkKey.currentState!.handleGameShortcut(key);
    }
    if (controller.busy || _visitRouting) return false;
    if (console.screen == 'personnel-directory' &&
        normalizeConsoleKey(key) == 'Escape') {
      unawaited(controller.returnToHeadquarters());
      return true;
    }
    if (planning) {
      final normalized = normalizeConsoleKey(key);
      if (const {'Escape', 'x', 'Space'}.contains(normalized)) {
        unawaited(_cancelVisit());
        return true;
      }
      if (normalized == 'Enter') {
        final action = _visitAction;
        if (action?.enabled == true) unawaited(_confirmVisit(action!));
        return true;
      }
      // Destination keys must prepare a card, never commit behind the journal.
      final action = console.actions
          .where((a) => a.key == normalized)
          .firstOrNull;
      if (action?.entityType == 'site') {
        setState(() {
          _targetId = action!.entityId;
          _targetSquadId = squad?.id;
        });
        return true;
      }
    }
    if (!activityFrame) return false;
    final normalized = normalizeConsoleKey(key);
    if (normalized == 'Escape' && hasPreparedOrder) {
      setState(() => _pendingOrder = null);
      return true;
    }
    if (normalized == 'Enter' && hasPreparedOrder) {
      unawaited(_commitPreparedOrder());
      return true;
    }
    final action = console.actions
        .where((a) => a.key == normalized && a.enabled)
        .firstOrNull;
    if (action == null) return false;
    if (const {
      'activity-category',
      'sleeper-category',
      'sleeper-category-selected',
    }.contains(action.entityType)) {
      setState(() {
        _orders = true;
        _pendingOrder = null;
        _categoryId = action.entityId;
        _group =
            const {
              'legal',
              'illegal',
              'sleeper-espionage',
            }.contains(action.entityId)
            ? 0
            : const {'activism', 'sleeper-advocacy'}.contains(action.entityId)
            ? 2
            : 1;
      });
      unawaited(
        controller.browseCategory(action, revision: console.revision.value),
      );
      return true;
    }
    if (activityTypeForAction(action) != null &&
        !action.entityType!.endsWith('-confirm')) {
      setState(() {
        _pendingOrder = action;
        _pendingRevision = console.revision.value;
      });
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(OrganisationJournal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _visitRequest++;
      _pendingOrder = null;
      _pool = false;
      _poolPerson = null;
      _orders = false;
      _showReports = widget.section == 5;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      if (bounds.maxWidth >= 650 || widget.fullSpreadDetail) {
        return _journal(context);
      }
      // Keep the two-page journal readable on narrow browser windows. A
      // visible horizontal scrollbar also exposes the map and day controls.
      return Scrollbar(
        controller: _narrowJournalScroll,
        thumbVisibility: true,
        trackVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          key: const ValueKey('journal-narrow-scroll'),
          controller: _narrowJournalScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 800,
            height: bounds.maxHeight,
            child: _journal(context),
          ),
        ),
      );
    },
  );

  Widget _journal(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final narrow = bounds.maxWidth < 1000;
        final inset = bounds.maxWidth < 650 ? 5.0 : 12.0;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: JournalPalette.leather,
            image: DecorationImage(
              image: AssetImage(JournalPalette.leatherAsset),
              fit: BoxFit.cover,
              opacity: .7,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 6, inset, 7),
            child: DefaultTextStyle(
              style: JournalPalette.body,
              child: Column(
                children: [
                  _sectionTabs(narrow),
                  Expanded(
                    child:
                        widget.section == networkJournalSection &&
                            !widget.fullSpreadDetail &&
                            !allocating &&
                            widget.detail == null
                        ? JournalNetworkView(
                            key: _networkKey,
                            console: console,
                            controller: controller,
                            onInspect: widget.onInspect,
                            onCloseInspection:
                                widget.onCloseInspection ?? () {},
                            inspectedPerson: widget.inspectedPerson,
                          )
                        : (widget.section != 0 || widget.fullSpreadDetail) &&
                              !activityFrame &&
                              !allocating
                        ? JournalSurface(
                            padding: const EdgeInsets.all(12),
                            child:
                                widget.detail ??
                                (widget.section == 5
                                    ? _reportsContext(narrow)
                                    : planning
                                    ? Row(
                                        children: [
                                          Expanded(child: _mapContext()),
                                          if (console.actions.any(
                                            (a) =>
                                                a.entityType == 'site' &&
                                                a.entityId == _targetId,
                                          ))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 10,
                                              ),
                                              child: SizedBox(
                                                width: narrow ? 230 : 300,
                                                child: _jobCard(),
                                              ),
                                            ),
                                        ],
                                      )
                                    : _mapContext()),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _squadTabs(narrow),
                              Expanded(
                                flex: narrow ? 43 : 44,
                                child: _teamPage(narrow),
                              ),
                              JournalBinding(width: narrow ? 22 : 30),
                              Expanded(
                                flex: narrow ? 51 : 50,
                                child: _contextPage(narrow),
                              ),
                            ],
                          ),
                  ),
                  _footer(narrow),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _sectionTabs(bool narrow) {
    const tabs = <(int, String, JournalIcon)>[
      (0, 'Organisation', JournalIcon.crew),
      (networkJournalSection, 'Network', JournalIcon.network),
      (1, 'Ledger', JournalIcon.accounts),
      (2, 'Justice', JournalIcon.law),
      (3, 'Agenda', JournalIcon.diplomacy),
      (4, 'Newspaper', JournalIcon.newspaper),
      (5, 'Reports', JournalIcon.reports),
      (6, 'City maps', JournalIcon.city),
      (7, 'Options', JournalIcon.options),
    ];
    final reviews = controller.networkReviews.count(game.pool);
    Widget tab((int, String, JournalIcon) item) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        message: controller.canNavigate
            ? item.$1 == networkJournalSection
                  ? 'Sleeper agents · monthly standing orders'
                  : item.$2
            : '${item.$2}: finish the current decision first.',
        child: Material(
          color: Colors.transparent,
          child: Ink(
            key: ValueKey('journal-section:${item.$1}'),
            decoration: journalTabDecoration(
              selected: widget.section == item.$1,
              enabled: controller.canNavigate,
            ),
            child: InkWell(
              onTap: controller.canNavigate
                  ? () => widget.onSection?.call(item.$1)
                  : null,
              child: Semantics(
                button: true,
                excludeSemantics: true,
                selected: widget.section == item.$1,
                label: item.$1 == networkJournalSection && reviews > 0
                    ? 'Network. $reviews ${reviews == 1 ? 'role' : 'roles'} to review.'
                    : item.$2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      JournalIllustratedIcon(
                        icon: item.$3,
                        size: narrow ? 30 : 40,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              item.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JournalPalette.small.copyWith(
                                fontSize: narrow ? 10 : 12,
                                fontWeight: FontWeight.w700,
                                color: JournalPalette.ink,
                              ),
                            ),
                          ),
                          if (item.$1 == networkJournalSection && reviews > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: JournalPalette.selected,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Text(
                                    '$reviews',
                                    style: JournalPalette.small.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return SizedBox(
      height: narrow ? 72 : 80,
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, bounds) =>
                  bounds.maxWidth < 950 && widget.textScale > 1.1
                  ? Scrollbar(
                      child: SingleChildScrollView(
                        key: const ValueKey('journal-section-scroll'),
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final item in tabs)
                              SizedBox(width: 130, child: tab(item)),
                          ],
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        for (final item in tabs) Expanded(child: tab(item)),
                      ],
                    ),
            ),
          ),
          IconButton(
            tooltip: 'Field guide',
            onPressed: widget.onHelp,
            icon: const Icon(
              Icons.help_outline,
              color: JournalPalette.brassLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _squadTabs(bool narrow) => SizedBox(
    width: narrow ? 43 : 57,
    child: Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              for (final team in game.squads)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 3),
                  child: Tooltip(
                    message:
                        '${team.name}\n${team.members.length}/6 crew · ${team.activity.description}',
                    child: Material(
                      color: Colors.transparent,
                      child: Ink(
                        decoration: journalTabDecoration(
                          selected: team.id == squad?.id,
                        ),
                        child: InkWell(
                          key: ValueKey('journal-squad:${team.id}'),
                          onTap: controller.canNavigate
                              ? () async {
                                  widget.onCloseInspection?.call();
                                  if (await controller.selectSquad(team.id)) {
                                    controller.clearInspection();
                                    if (mounted) {
                                      setState(() {
                                        _pool = false;
                                        _poolPerson = null;
                                      });
                                    }
                                  }
                                }
                              : null,
                          child: Semantics(
                            button: true,
                            selected: team.id == squad?.id,
                            label: 'Select squad ${team.name}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 7,
                                horizontal: 3,
                              ),
                              child: Column(
                                children: [
                                  if (team.members.isNotEmpty)
                                    CrewPortrait(
                                      person: team.members.first,
                                      size: narrow ? 30 : 42,
                                    )
                                  else
                                    const Icon(Icons.group_outlined, size: 28),
                                  Text(
                                    '${team.members.length}/6',
                                    style: JournalPalette.small,
                                  ),
                                  if (team.activity.type != ActivityType.none)
                                    const Icon(
                                      Icons.assignment_turned_in,
                                      size: 12,
                                      color: JournalPalette.binding,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('journal-new-squad'),
          tooltip: 'Assemble a new squad',
          onPressed: controller.canNavigate
              ? () {
                  widget.onCloseInspection?.call();
                  unawaited(controller.openAllocation(null));
                }
              : null,
          icon: const Icon(Icons.group_add, color: JournalPalette.brassLight),
        ),
      ],
    ),
  );

  bool get _hasJob =>
      _selectedDestination != null ||
      activityFrame ||
      planning ||
      squad?.activity.type == ActivityType.visit ||
      person != null && person!.activity.type != ActivityType.none;

  Widget _teamPage(bool narrow) => JournalSurface(
    padding: const EdgeInsets.all(8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final headerHeight = widget.textScale > 1.1
                  ? (narrow ? 130.0 : 140.0)
                  : (bounds.maxHeight * .25).clamp(
                      108.0,
                      narrow ? 108.0 : 120.0,
                    );
              final crewDesired =
                  members.length * (widget.textScale > 1.1 ? 34.0 : 30.0) + 56;
              final jobHeight =
                  (bounds.maxHeight - headerHeight - crewDesired - 12).clamp(
                    widget.textScale > 1.1 ? (planning ? 260.0 : 230.0) : 140.0,
                    widget.textScale > 1.1 ? (planning ? 280.0 : 260.0) : 240.0,
                  );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: SingleChildScrollView(child: _teamHeader(narrow)),
                  ),
                  const SizedBox(height: 6),
                  if (_hasJob) ...[
                    SizedBox(height: jobHeight, child: _jobCard()),
                    const SizedBox(height: 6),
                  ],
                  Expanded(
                    child: _skills ? _skillsPaper(person) : _crewPaper(),
                  ),
                  if (controller.message != null)
                    Text(
                      controller.message!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        _innerRail(narrow),
      ],
    ),
  );

  Widget _teamHeader(bool narrow) {
    final actor = person;
    final teamName = undercover
        ? 'Undercover network'
        : controller.assembly?.isNew == true
        ? 'New squad'
        : controller.assembly?.squadName ?? squad?.name ?? 'The organisation';
    final location =
        actor?.location?.getName(short: true, includeCity: true) ??
        'Unknown location';
    final wounded = actor?.body.parts.any((part) => part.wounded) == true;
    return JournalSurface(
      inset: true,
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: teamName,
                  child: Text(
                    teamName,
                    key: const ValueKey('journal-team-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JournalPalette.heading.copyWith(
                      fontSize: 14,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  key: const ValueKey('journal-skills'),
                  tooltip: 'Toggle crew and skills',
                  onPressed: () => setState(() => _skills = !_skills),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(24, 24),
                  ),
                  icon: Icon(
                    _skills ? Icons.groups : Icons.auto_graph,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (actor != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  button: true,
                  label: 'Inspect ${actor.name}',
                  child: InkWell(
                    key: ValueKey('hq-portrait:${actor.id}'),
                    onTap: () => widget.onInspect(actor),
                    child: CrewPortrait(person: actor, size: narrow ? 46 : 58),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: actor.name,
                        child: Text(
                          actor.name,
                          key: const ValueKey('journal-selected-person'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JournalPalette.heading.copyWith(
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: location,
                        child: Text(
                          location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JournalPalette.small.copyWith(
                            fontSize: 10.5,
                            height: 1.15,
                          ),
                        ),
                      ),
                      Tooltip(
                        message:
                            'Juice ${actor.juice} · ${actor.title} · ${actor.blood}/${actor.maxBlood} blood${wounded ? ' · Injured' : ''}',
                        child: Text(
                          'Juice ${actor.juice} · ${actor.blood}/${actor.maxBlood} blood',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: JournalPalette.small.copyWith(
                            fontSize: 10.5,
                            height: 1.15,
                            color: actor.blood < actor.maxBlood || wounded
                                ? JournalPalette.danger
                                : JournalPalette.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            const Text('No active crew selected.', style: JournalPalette.small),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              _fact(
                Icons.people,
                undercover ? '${members.length} agents' : '${members.length}/6',
                undercover ? 'Undercover agents' : 'Squad members',
              ),
              _fact(
                Icons.shield_outlined,
                '${members.where((p) => p.equippedWeapon != null).length}',
                'Armed members',
              ),
              _fact(
                Icons.directions_car,
                '${members.map((p) => p.car?.id).nonNulls.toSet().length}',
                'Assigned cars',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fact(IconData icon, String value, String name) => Tooltip(
    message: name,
    child: Semantics(
      label: '$name: $value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: JournalPalette.brassDark),
          const SizedBox(width: 4),
          Text(value, style: JournalPalette.body),
        ],
      ),
    ),
  );

  Widget _innerRail(bool narrow) => SizedBox(
    width: narrow ? 64 : 72,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _railButton(
                  Icons.receipt_long,
                  'Reports',
                  _showReports && !_orders && widget.detail == null,
                  controller.canNavigate
                      ? () async {
                          if (await controller.returnToHeadquarters() &&
                              mounted) {
                            widget.onCloseInspection?.call();
                            setState(() {
                              _orders = false;
                              _pool = false;
                              _pendingOrder = null;
                              _showReports = true;
                            });
                          }
                        }
                      : null,
                  key: 'journal-reports',
                  semanticLabel: 'Crew reports',
                ),
                _railButton(
                  Icons.assignment,
                  'Orders',
                  _orders || activityFrame || planning,
                  person == null || !controller.canNavigate
                      ? null
                      : () async {
                          widget.onCloseInspection?.call();
                          setState(() {
                            _orders = true;
                            _pool = false;
                            _showReports = false;
                          });
                          await _openGroup(_group, categoryId: _categoryId);
                        },
                  key: 'journal-orders',
                ),
                const SizedBox(height: 7),
                if (_orders || activityFrame || planning) ...[
                  for (final (index, icon, label) in <(int, IconData, String)>[
                    (0, Icons.account_balance, 'Business'),
                    (1, Icons.people, 'Personnel'),
                    (2, Icons.campaign, 'Activism'),
                    (3, Icons.security, 'Operations'),
                  ])
                    _railButton(
                      icon,
                      label,
                      _group == index,
                      controller.canNavigate ? () => _openGroup(index) : null,
                      key: 'journal-order-group:$index',
                    ),
                ],
              ],
            ),
          ),
        ),
        _railButton(
          Icons.manage_accounts,
          'Crew pool',
          _pool || allocating,
          controller.canNavigate
              ? () async {
                  widget.onCloseInspection?.call();
                  if (await controller.openAllocation(squad?.id)) {
                    if (mounted) {
                      setState(() {
                        _pool = true;
                        _orders = false;
                      });
                    }
                  }
                }
              : null,
          key: 'journal-pool',
        ),
        _railButton(
          Icons.assignment_ind,
          'Clipboard',
          console.navigation?.section == 'people' ||
              console.journalProfile != null,
          controller.canNavigate
              ? () async {
                  widget.onCloseInspection?.call();
                  setState(() {
                    _orders = false;
                    _pool = false;
                    _showReports = false;
                    _personnelTools = false;
                    _pendingOrder = null;
                  });
                  await controller.openPersonnelDirectory();
                }
              : null,
          key: 'journal-clipboard',
        ),
        _railButton(
          Icons.directions_car,
          'Vehicles',
          console.navigation?.section == 'vehicles',
          controller.canNavigate && !undercover
              ? () => _openManagementSection('v')
              : null,
          key: 'journal-vehicles',
        ),
        _railButton(
          Icons.inventory_2,
          'Weapons',
          console.navigation?.section == 'equipment',
          controller.canNavigate ? () => _openManagementSection('e') : null,
          key: 'journal-equipment',
        ),
      ],
    ),
  );

  Future<bool> _openManagementSection(String key) async {
    widget.onCloseInspection?.call();
    setState(() {
      _orders = false;
      _pool = false;
      _showReports = false;
      _pendingOrder = null;
    });
    return controller.openSection(key);
  }

  Widget _railButton(
    IconData icon,
    String label,
    bool selected,
    VoidCallback? onTap, {
    required String key,
    String? semanticLabel,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Tooltip(
      message: semanticLabel ?? label,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: journalTabDecoration(
            selected: selected,
            enabled: onTap != null,
          ),
          child: InkWell(
            key: ValueKey(key),
            onTap: onTap,
            child: Semantics(
              button: true,
              selected: selected,
              excludeSemantics: true,
              label: semanticLabel ?? label,
              child: SizedBox(
                height: 32 + MediaQuery.textScalerOf(context).scale(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  child: Column(
                    children: [
                      SizedBox.square(
                        dimension: 24,
                        child: Center(
                          child: key.startsWith('journal-order-group:')
                              ? JournalIllustratedIcon(
                                  icon:
                                      JournalIcon.values[8 +
                                          int.parse(key.split(':').last)],
                                  size: 24,
                                )
                              : Icon(
                                  icon,
                                  size: 24,
                                  color: onTap == null
                                      ? JournalPalette.muted
                                      : JournalPalette.brassDark,
                                ),
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: JournalPalette.small.copyWith(
                          fontSize: 10,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _openGroup(int group, {String? categoryId}) async {
    widget.onCloseInspection?.call();
    setState(() {
      _orders = true;
      _pool = false;
      _group = group;
    });
    _pendingOrder = null;
    final selected = person;
    if (group == 3 && !undercover) return;
    if (selected == null) return;
    if (!activityFrame && !await controller.openOrders(selected.id)) return;
    if (!mounted || group == 3 && !undercover) return;
    final id = undercover
        ? (group == 0 || group == 3 ? 'sleeper-espionage' : 'sleeper-advocacy')
        : switch (group) {
            0 => 'legal',
            1 => 'acquisition',
            _ => 'activism',
          };
    final categories = console.actions.where(
      (a) =>
          const {
            'activity-category',
            'sleeper-category',
            'sleeper-category-selected',
          }.contains(a.entityType) &&
          a.enabled,
    );
    final category =
        categories.where((a) => a.entityId == categoryId).firstOrNull ??
        categories.where((a) => a.entityId == id).firstOrNull;
    if (category != null) {
      _categoryId = category.entityId;
      await controller.browseCategory(
        category,
        revision: console.revision.value,
      );
    }
  }

  Future<void> _commitPreparedOrder() async {
    if (!hasPreparedOrder) return;
    final actorId = activityOrderFrame(console)!.actorId;
    final group = _group;
    final categoryId = _categoryId;
    final section = widget.section;
    controller.inspectPerson(actorId);
    if (!await controller.commitOrder(
          _pendingOrder!,
          revision: _pendingRevision!,
        ) ||
        !mounted) {
      return;
    }
    setState(() => _pendingOrder = null);
    // Only ordinary completion returns to HQ. Required follow-up choices
    // stay with the original skill, crafting, prisoner or other reader.
    if (controller.isHeadquarters &&
        widget.section == section &&
        controller.selectedPerson?.id == actorId &&
        await controller.openOrders(actorId) &&
        mounted) {
      await _openGroup(group, categoryId: categoryId);
    }
  }

  Widget _crewPaper() => DragTarget<int>(
    onWillAcceptWithDetails: (details) =>
        !controller.busy && !members.any((member) => member.id == details.data),
    onAcceptWithDetails: (details) =>
        unawaited(controller.assignPerson(details.data)),
    builder: (context, candidates, rejected) => JournalSurface(
      lined: true,
      inset: true,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.attach_file,
                size: 19,
                color: JournalPalette.brassDark,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  undercover
                      ? 'Undercover agents · ${members.length}'
                      : 'Crew · ${members.length}/6',
                  style: JournalPalette.heading.copyWith(fontSize: 14),
                ),
              ),
              if (allocating)
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () async {
                          if (await controller.finishAllocation() && mounted) {
                            controller.clearInspection();
                            setState(() {
                              _pool = false;
                              _poolPerson = null;
                            });
                          }
                        },
                  child: const Text('Done'),
                ),
            ],
          ),
          if (candidates.isNotEmpty)
            const Text(
              'Drop to add to this squad',
              style: JournalPalette.small,
            ),
          Expanded(
            child: members.isEmpty
                ? const Center(child: Text('Choose crew from the pool.'))
                : ListView(
                    key: const ValueKey('journal-crew-list'),
                    children: [
                      for (final member in members) _memberRow(member),
                    ],
                  ),
          ),
          if (!_hasJob)
            Text(
              allocating
                  ? 'Drag crew between these pages, or use Add / Remove.'
                  : 'Select a name to inspect. Crew pool changes the team.',
              style: JournalPalette.small,
            ),
        ],
      ),
    ),
  );

  Widget _memberRow(Creature member) {
    bool canSelect() =>
        !controller.busy &&
        !_visitRouting &&
        (console.journalProfile == null ||
            controller.canSelectProfilePerson(member.id)) &&
        (!(_orders || activityFrame) || controller.canNavigate);
    Future<void> select() async {
      if (!canSelect()) return;
      if (person?.id == member.id &&
          (console.journalProfile != null ||
              activityFrame ||
              controller.selectedPersonId == member.id)) {
        return;
      }
      setState(() => _pendingOrder = null);
      final wasOrders = _orders || activityFrame;
      final categoryId = _categoryId;
      if (widget.inspectedPerson != null &&
          console.journalProfile == null &&
          !wasOrders) {
        controller.inspectPerson(member.id);
        widget.onInspect(member);
        return;
      }
      widget.onCloseInspection?.call();
      if (console.journalProfile != null) {
        await controller.selectProfilePerson(member.id);
        return;
      }
      controller.inspectPerson(member.id);
      if (wasOrders && await controller.openOrders(member.id)) {
        await _openGroup(_group, categoryId: categoryId);
      }
    }

    final row = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: person?.id == member.id ? JournalPalette.selected : null,
          border: Border(
            bottom: BorderSide(
              color: JournalPalette.rule.withValues(alpha: .4),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                key: ValueKey('journal-member:${member.id}'),
                onPressed: canSelect() ? select : null,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  minimumSize: const Size(24, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Semantics(
                  label: 'Select crew ${member.name}',
                  excludeSemantics: true,
                  child: Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: JournalPalette.body.copyWith(
                      fontSize: 13,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
            JuiceBadge(person: member, compact: true, showHelp: false),
            if (member.activity.type != ActivityType.none)
              Tooltip(
                message: member.activity.description,
                child: const Icon(
                  Icons.assignment,
                  size: 13,
                  color: JournalPalette.olive,
                ),
              ),
            SizedBox(
              width: 26,
              height: 26,
              child: IconButton(
                key: ValueKey('hq-dossier:${member.id}'),
                tooltip: 'Dossier: ${member.name}',
                onPressed: () => widget.onInspect(member),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(24, 24),
                ),
                icon: const Icon(Icons.person_search, size: 16),
              ),
            ),
            if (allocating)
              SizedBox(
                width: 26,
                height: 26,
                child: IconButton(
                  key: ValueKey('journal-remove-member:${member.id}'),
                  tooltip: 'Remove ${member.name} from this squad',
                  onPressed: controller.busy
                      ? null
                      : () => controller.assignPerson(member.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(24, 24),
                  ),
                  icon: const Icon(Icons.remove_circle_outline, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
    return allocating
        ? Draggable<int>(
            data: member.id,
            feedback: Material(
              color: JournalPalette.selected,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(member.name, style: JournalPalette.body),
              ),
            ),
            childWhenDragging: Opacity(opacity: .4, child: row),
            child: row,
          )
        : row;
  }

  Widget _skillsPaper(Creature? actor) {
    final skills = Skill.values.toList()
      ..sort((a, b) => (actor?.skill(b) ?? 0).compareTo(actor?.skill(a) ?? 0));
    return JournalSurface(
      lined: true,
      inset: true,
      padding: const EdgeInsets.all(9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            actor == null ? 'Skills' : '${actor.name} · Skills',
            style: JournalPalette.heading.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 5),
          Expanded(
            child: ListView(
              children: [
                for (final skill in skills)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: SkillTooltip(
                      key: ValueKey('journal-skill:${skill.name}'),
                      skill: skill,
                      actor: actor,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              skill.displayName,
                              style: JournalPalette.small,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${actor?.skill(skill) ?? 0}',
                            style: JournalPalette.body,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showOrderMechanics(ActivityMechanics help) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: AlertDialog(
          key: const ValueKey('journal-order-details-dialog'),
          title: Text(help.title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(help.summary),
                  const SizedBox(height: 8),
                  Text(help.timing),
                  if (help.factors.isNotEmpty) Text('Uses: ${help.factors}'),
                  if (help.cost.isNotEmpty) Text('Cost: ${help.cost}'),
                  if (help.requirements.isNotEmpty)
                    Text('Needs: ${help.requirements}'),
                  if (help.risk.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(help.risk),
                  ],
                  if (help.type == ActivityType.visit) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Members: ${members.map((member) => member.name).join(', ')}',
                      key: const ValueKey('journal-visit-members'),
                    ),
                    const Text(
                      'Travel to another area needs a car; intercity travel also needs enough cash. '
                      'The site must be open and free of siege.',
                    ),
                  ],
                  if (help.calculation case final calculation?) ...[
                    const SizedBox(height: 12),
                    ActivityCalculationView(calculation: calculation),
                  ],
                  if (help.details.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(help.details),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
    if (mounted) _restoreInputFocus();
  }

  Widget _jobCard() {
    if (widget.console.recruitmentTarget case final target?) {
      return JournalSurface(
        lined: true,
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          child: RecruitmentTargetPreview(target: target),
        ),
      );
    }
    final actor = person;
    final prepared = hasPreparedOrder;
    final actual = squad?.activity.type == ActivityType.visit
        ? squad!.activity
        : actor?.activity;
    final type = prepared
        ? activityTypeForAction(_pendingOrder!)!
        : planning
        ? ActivityType.visit
        : actual?.type ?? ActivityType.none;
    final target = _selectedDestination;
    final help = activityMechanics(
      type,
      actor: type == ActivityType.visit ? null : actor,
      activity: planning
          ? Activity(ActivityType.visit, idString: target?.idString)
          : prepared
          ? null
          : actual,
    );
    final visit = _visitAction;
    final travel = type == ActivityType.visit
        ? (planning ? target : actual?.location)
        : null;
    final notices = travel == null
        ? const <String>[]
        : travelNotices(travel, squad);
    final estimatedIncome = help.calculation?.quantities['estimatedIncome'];
    final visitInProgress =
        !prepared &&
        !planning &&
        actual?.type == ActivityType.visit &&
        squad?.id == game.activeSquad?.id &&
        recoveryContext(console)?.scene == RecoveryScene.hospital;
    return JournalSurface(
      key: const ValueKey('journal-job-card'),
      lined: true,
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.push_pin,
                size: 18,
                color: JournalPalette.brassDark,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  type == ActivityType.visit
                      ? 'Squad order · ${squad?.name ?? 'Squad'}'
                      : actor?.name ?? squad?.name ?? 'Squad order',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JournalPalette.heading.copyWith(fontSize: 11),
                ),
              ),
              IconButton(
                key: const ValueKey('journal-order-details'),
                tooltip: 'Order mechanics',
                onPressed: () => _showOrderMechanics(help),
                icon: const Icon(Icons.info_outline, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            planning
                ? target == null
                      ? 'Visit a location'
                      : 'Visit ${target.getName()}'
                : !prepared && actual?.type == ActivityType.visit
                ? 'Visit ${actual?.location?.getName() ?? 'a location'}'
                : help.title,
            key: const ValueKey('journal-current-order'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: JournalPalette.heading.copyWith(fontSize: 14),
          ),
          Text(
            planning && (target == null || visit?.enabled != true)
                ? target == null
                      ? 'Choose a building on the map'
                      : 'Destination unavailable'
                : prepared || planning
                ? 'Prepared · awaiting confirmation'
                : actual?.type == ActivityType.visit
                ? visitInProgress
                      ? 'Visit in progress'
                      : 'Visit queued · advance the day to travel'
                : 'Assigned order',
            key: const ValueKey('journal-order-state'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: JournalPalette.small.copyWith(
              fontSize: 9.5,
              height: 1.1,
              color: prepared ? JournalPalette.binding : JournalPalette.olive,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: SingleChildScrollView(
              key: const ValueKey('journal-order-mechanics'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    visitInProgress
                        ? 'Choose care or return to headquarters.'
                        : help.timing,
                    style: JournalPalette.small,
                  ),
                  if (actor != null)
                    JuiceActivityHint(person: actor, activity: type),
                  if (!visitInProgress &&
                      type == ActivityType.visit &&
                      notices.isNotEmpty)
                    Text(
                      travelSuffix(notices).trim(),
                      key: const ValueKey('journal-travel-notices'),
                      style: JournalPalette.small,
                    ),
                  if (help.calculation case final calculation?
                      when type != ActivityType.visit)
                    Text(
                      estimatedIncome != null
                          ? 'Estimated \$${estimatedIncome.round()}/day'
                          : calculation.result,
                      key: const ValueKey('journal-calculation-result'),
                      style: JournalPalette.small.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (type != ActivityType.visit && help.factors.isNotEmpty)
                    Text('Uses: ${help.factors}', style: JournalPalette.small),
                  if (type != ActivityType.visit &&
                      help.cost.isNotEmpty &&
                      help.cost != 'No activity fee')
                    Text('Cost: ${help.cost}', style: JournalPalette.small),
                  if (type != ActivityType.visit && help.risk.isNotEmpty)
                    Text(
                      help.risk,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                  if (help.unavailableReason case final reason?)
                    Text(
                      reason,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                  if (planning &&
                      visit != null &&
                      !visit.enabled &&
                      notices.isEmpty)
                    Text(
                      _locationDetails(visit).join(' · '),
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.danger,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              if (prepared || planning)
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('journal-confirm-order'),
                    onPressed:
                        controller.busy ||
                            _visitRouting ||
                            (planning && visit?.enabled != true)
                        ? null
                        : () async {
                            if (planning) {
                              await _confirmVisit(visit!);
                              return;
                            }
                            await _commitPreparedOrder();
                          },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      textStyle: JournalPalette.small.copyWith(
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Confirm order'),
                  ),
                )
              else if (confirmation != null)
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('journal-finish-orders'),
                    onPressed: controller.busy
                        ? null
                        : () => _dispatch(confirmation!),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      textStyle: JournalPalette.small.copyWith(
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Finish orders'),
                  ),
                ),
              if (!planning && !prepared && _selectedDestination != null)
                Expanded(
                  child: TextButton.icon(
                    key: const ValueKey('journal-prepare-map-visit'),
                    onPressed:
                        controller.canNavigate && !undercover && !_visitRouting
                        ? _prepareMapVisit
                        : null,
                    icon: const Icon(Icons.place, size: 16),
                    label: const Text('Prepare visit'),
                  ),
                ),
              if (prepared)
                IconButton(
                  tooltip: 'Cancel prepared order',
                  key: const ValueKey('journal-cancel-order'),
                  onPressed: () => setState(() => _pendingOrder = null),
                  icon: const Icon(Icons.close, size: 18),
                )
              else if (activityFrame || planning)
                IconButton(
                  key: planning ? const ValueKey('journal-cancel-order') : null,
                  tooltip: planning
                      ? 'Cancel prepared order'
                      : 'Return to planning; keep assigned orders',
                  onPressed: controller.canNavigate && !_visitRouting
                      ? planning
                            ? _cancelVisit
                            : controller.returnToHeadquarters
                      : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _contextPage(bool narrow) => JournalSurface(
    padding: const EdgeInsets.all(9),
    child:
        console.screen == 'personnel-directory' &&
            console.journalProfile == null &&
            !console.textInput &&
            widget.inspectedPerson == null
        ? _personnelTools
              ? Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Roster tools',
                            style: JournalPalette.heading,
                          ),
                        ),
                        TextButton.icon(
                          key: const ValueKey('personnel-back-directory'),
                          onPressed: controller.busy
                              ? null
                              : () => setState(() => _personnelTools = false),
                          icon: const Icon(Icons.arrow_back, size: 16),
                          label: const Text('Back to directory'),
                        ),
                      ],
                    ),
                    Expanded(child: widget.detail ?? const SizedBox.shrink()),
                  ],
                )
              : PersonnelDirectory(
                  people: game.pool,
                  controller: _personnel,
                  enabled: !controller.busy && console.awaitingInput,
                  onClose: () => unawaited(controller.returnToHeadquarters()),
                  onTools: () => setState(() => _personnelTools = true),
                  onOpen: (person) {
                    FocusScope.of(context).unfocus();
                    unawaited(controller.openPersonnelProfile(person.id));
                  },
                )
        : _orders && controller.busy && console.journalProfile == null
        ? _orderContext(narrow)
        : widget.detail != null &&
              console.awaitingInput &&
              (console.textInput || console.navigation == null)
        ? widget.detail!
        : widget.inspectedPerson != null
        ? CrewInspector(
            person: widget.inspectedPerson!,
            onClose: widget.onCloseInspection ?? () {},
            actions: widget.inspectorActions,
            compact: true,
          )
        : widget.detail != null
        ? widget.detail!
        : allocating || _pool
        ? _poolPage()
        : console.screen == 'headquarters' &&
              controller.headquarters?.siege != null
        ? _siegeResponse()
        : _orders || activityFrame || planning
        ? _orderContext(narrow)
        : _showReports || widget.section == 5
        ? _reportsContext(narrow)
        : _mapContext(),
  );

  Widget _siegeResponse() {
    final frame = controller.headquarters!;
    final briefing = frame.siege!;
    final revision = console.revision.value;
    return ListView(
      key: const ValueKey('journal-siege-response'),
      children: [
        Text(briefing.title, style: JournalPalette.heading),
        const SizedBox(height: 5),
        Text(briefing.location, style: JournalPalette.small),
        const Divider(height: 20),
        if (briefing.statusLines.isNotEmpty)
          Text(briefing.statusLines.first, style: JournalPalette.body),
        const SizedBox(height: 12),
        for (final key in const ['f', 'g', 'w'])
          if (frame.action(key) case final action?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                key: ValueKey('journal-siege-action:$key'),
                onPressed: action.enabled && !controller.busy
                    ? () {
                        if (widget.inspectedPerson == null &&
                            identical(controller.headquarters, frame) &&
                            console.screen == 'headquarters') {
                          unawaited(
                            controller.sendAction(action, revision: revision),
                          );
                        }
                      }
                    : null,
                child: Text(action.intentLabel ?? _clean(action.label)),
              ),
            ),
        const SizedBox(height: 5),
        Text(briefing.note, style: JournalPalette.small),
        if (briefing.statusLines.length > 1)
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              key: const PageStorageKey('journal-siege-details'),
              tilePadding: EdgeInsets.zero,
              title: const Text('Siege details', style: JournalPalette.body),
              children: [
                for (final line in briefing.statusLines.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(line, style: JournalPalette.body),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _poolPage() {
    final memberIds = members.map((member) => member.id).toSet();
    final candidates =
        controller.allocationPool
            .where((p) => !memberIds.contains(p.id))
            .toList()
          ..sort((a, b) {
            final rating = b.skill(_poolSort).compareTo(a.skill(_poolSort));
            return rating != 0 ? rating : a.name.compareTo(b.name);
          });
    final preview = candidates.where((p) => p.id == _poolPerson).firstOrNull;
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) =>
          allocating && members.any((p) => p.id == d.data),
      onAcceptWithDetails: (d) => unawaited(controller.assignPerson(d.data)),
      builder: (context, incoming, rejected) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Available crew', style: JournalPalette.heading),
          DropdownButton<Skill>(
            value: _poolSort,
            isExpanded: true,
            items: [
              for (final skill in Skill.values)
                DropdownMenuItem(
                  value: skill,
                  child: SkillTooltip(
                    skill: skill,
                    actor: preview,
                    child: Text(
                      'Sort: ${skill.displayName}',
                      style: JournalPalette.small,
                    ),
                  ),
                ),
            ],
            onChanged: (skill) {
              if (skill != null) setState(() => _poolSort = skill);
            },
          ),
          Text(
            incoming.isNotEmpty
                ? 'Drop to remove from this squad'
                : 'Select a portrait to inspect; add with the arrow or drag onto the left page.',
            style: JournalPalette.small,
          ),
          const SizedBox(height: 7),
          Expanded(
            child: candidates.isEmpty
                ? const Center(
                    child: Text(
                      'All eligible crew are already in this squad.\nRemove a name on the left to return them to the pool.',
                      textAlign: TextAlign.center,
                      style: JournalPalette.body,
                    ),
                  )
                : ListView(
                    children: [
                      for (final candidate in candidates) _poolRow(candidate),
                    ],
                  ),
          ),
          if (preview != null)
            SizedBox(
              height: 165,
              child: JournalSurface(
                inset: true,
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      preview.name,
                      style: JournalPalette.heading.copyWith(fontSize: 15),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final skill in _bestSkills(preview))
                              SkillTooltip(
                                skill: skill,
                                actor: preview,
                                child: Text(
                                  '${skill.displayName}  ${preview.skill(skill)}',
                                  style: JournalPalette.small,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (controller.allocationBlockReason(preview.id)
                        case final reason?)
                      Text(
                        reason,
                        style: JournalPalette.small.copyWith(
                          color: JournalPalette.danger,
                        ),
                      ),
                    FilledButton.icon(
                      onPressed:
                          controller.busy ||
                              controller.allocationBlockReason(preview.id) !=
                                  null
                          ? null
                          : () => controller.assignPerson(preview.id),
                      icon: Icon(
                        members.any((p) => p.id == preview.id)
                            ? Icons.arrow_forward
                            : Icons.arrow_back,
                        size: 17,
                      ),
                      label: Text(
                        members.any((p) => p.id == preview.id)
                            ? 'Return to pool'
                            : 'Add to this squad',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _poolRow(Creature candidate) {
    final inSquad = members.any((p) => p.id == candidate.id);
    final reason = controller.allocationBlockReason(candidate.id);
    void select() => setState(() => _poolPerson = candidate.id);
    final row = Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.all(5),
        decoration: journalTabDecoration(selected: _poolPerson == candidate.id),
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                key: ValueKey('journal-pool-person:${candidate.id}'),
                onPressed: select,
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const RoundedRectangleBorder(),
                ),
                child: Semantics(
                  label: 'Inspect pool member ${candidate.name}',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      CrewPortrait(person: candidate, size: 46),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              candidate.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JournalPalette.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              candidate.squad?.name ?? 'Unassigned',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JournalPalette.small,
                            ),
                            Text(
                              '${_poolSort.displayName} ${candidate.skill(_poolSort)} · ${candidate.blood}/${candidate.maxBlood} blood',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: JournalPalette.small,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Tooltip(
              message:
                  reason ??
                  (inSquad ? 'Remove from this squad' : 'Add to this squad'),
              child: IconButton(
                key: ValueKey('journal-transfer:${candidate.id}'),
                tooltip: inSquad
                    ? 'Remove ${candidate.name} from this squad'
                    : 'Add ${candidate.name} to this squad',
                onPressed: reason == null && !controller.busy
                    ? () => controller.assignPerson(candidate.id)
                    : null,
                icon: Icon(
                  inSquad ? Icons.arrow_forward : Icons.arrow_back,
                  color: reason == null
                      ? JournalPalette.olive
                      : JournalPalette.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return reason == null
        ? Draggable<int>(
            data: candidate.id,
            feedback: Material(
              color: JournalPalette.selected,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(candidate.name, style: JournalPalette.body),
              ),
            ),
            childWhenDragging: Opacity(opacity: .4, child: row),
            child: row,
          )
        : row;
  }

  Iterable<Skill> _bestSkills(Creature actor) {
    final values = Skill.values.toList()
      ..sort((a, b) => actor.skill(b).compareTo(actor.skill(a)));
    return values.take(8);
  }

  Widget _orderContext(bool narrow) {
    final queued = person?.squad?.activity;
    if (!undercover &&
        !planning &&
        !activityFrame &&
        _group != 3 &&
        queued != null &&
        queued.type != ActivityType.none) {
      return ListView(
        children: [
          const Text('Daily orders', style: JournalPalette.heading),
          const SizedBox(height: 12),
          Text(
            queued.location == null
                ? 'This crew member has a joint squad operation queued.'
                : 'This crew member’s squad has a visit to ${queued.location!.getName()} queued.',
            style: JournalPalette.body,
          ),
          const SizedBox(height: 8),
          const Text(
            'Cancel the squad’s departure to assign individual daily orders. Keeping the departure carries out the squad visit when you advance the day.',
            style: JournalPalette.small,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('journal-cancel-departure-edit-orders'),
            onPressed:
                controller.canNavigate &&
                    person?.squadId == game.activeSquad?.id
                ? () async {
                    if (await controller.openSection('c') && mounted) {
                      await _openGroup(_group);
                    }
                  }
                : null,
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel departure and edit daily orders'),
          ),
        ],
      );
    }
    // Keep presentation stable through HQ/person-list awaits while changing
    // actor or reopening a confirmed order. These cached actions are displayed
    // only while controls are disabled; dispatch always uses the fresh frame.
    if (activityFrame && !controller.busy) {
      _orderBrowseActions = List.of(console.actions);
    }
    final browsingActions = controller.busy
        ? _orderBrowseActions
        : console.actions;
    final categories = browsingActions
        .where(
          (a) =>
              a.entityType == 'activity-category' ||
              a.entityType == 'sleeper-category' ||
              a.entityType == 'sleeper-category-selected',
        )
        .toList();
    final categoryIds = undercover
        ? const {'sleeper-advocacy', 'sleeper-espionage'}
        : switch (_group) {
            0 => const {'legal', 'illegal'},
            1 => const {'acquisition', 'education', 'teaching', 'medical'},
            2 => const {'activism'},
            _ => const <String>{},
          };
    final visibleCategories = categories
        .where((a) => categoryIds.contains(a.entityId))
        .toList();
    final tasks = browsingActions
        .where(
          (a) =>
              activityTypeForAction(a) != null &&
              !a.entityType!.endsWith('-confirm') &&
              (_group == 3 ? a.x < 40 : a.x >= 40),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (visibleCategories.length > 1)
          Wrap(
            spacing: 4,
            runSpacing: 3,
            children: [
              for (final category in visibleCategories)
                OutlinedButton(
                  onPressed: category.enabled && !controller.busy
                      ? () {
                          setState(() => _categoryId = category.entityId);
                          _pendingOrder = null;
                          unawaited(
                            controller.browseCategory(
                              category,
                              revision: console.revision.value,
                            ),
                          );
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    minimumSize: const Size(44, 32),
                    backgroundColor: _categoryId == category.entityId
                        ? JournalPalette.selected
                        : null,
                  ),
                  child: Text(
                    _clean(category.label),
                    style: JournalPalette.small,
                  ),
                ),
            ],
          ),
        if (visibleCategories.length > 1) const SizedBox(height: 6),
        Expanded(
          key: const ValueKey('journal-order-workspace'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!planning && (_group == 3 || tasks.isNotEmpty))
                SizedBox(
                  width: narrow ? 96 : 130,
                  child: ListView(
                    key: PageStorageKey('journal-tasks:$_group:$_categoryId'),
                    children: [
                      if (_group == 3)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: DecoratedBox(
                            decoration: journalTabDecoration(
                              selected: false,
                              enabled: controller.canNavigate && !undercover,
                            ),
                            child: TextButton(
                              key: const ValueKey('journal-plan-visit'),
                              onPressed: controller.canNavigate && !undercover
                                  ? () {
                                      setState(() {
                                        _targetId = null;
                                        _targetSquadId = null;
                                      });
                                      unawaited(_prepareMapVisit());
                                    }
                                  : null,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 7,
                                ),
                                minimumSize: const Size(44, 44),
                                shape: const RoundedRectangleBorder(),
                              ),
                              child: Column(
                                children: [
                                  const JournalOrderIcon(
                                    type: ActivityType.visit,
                                    size: 34,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Visit a location',
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: JournalPalette.small.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      for (final task in tasks) _taskButton(task),
                    ],
                  ),
                ),
              if (!planning && (_group == 3 || tasks.isNotEmpty))
                const SizedBox(width: 7),
              Expanded(
                key: const ValueKey('journal-order-map'),
                child: _mapContext(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _taskButton(ConsoleAction action) {
    final type = activityTypeForAction(action)!;
    final help = activityMechanics(type, actor: person);
    final selected = hasPreparedOrder
        ? activityTypeForAction(_pendingOrder!) == type
        : person?.activity.type == type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: MechanicsTooltip(
        message:
            '${help.summary}\n${help.factors}\n${help.cost}\n${help.unavailableReason ?? ''}\n${help.calculation?.text ?? ''}',
        maxWidth: 520,
        child: DecoratedBox(
          decoration: journalTabDecoration(
            selected: selected,
            enabled: action.enabled,
          ),
          child: TextButton(
            key: ValueKey('journal-activity:${action.entityId}'),
            onPressed: action.enabled && !controller.busy
                ? () => setState(() {
                    _pendingOrder = action;
                    _pendingRevision = console.revision.value;
                  })
                : null,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              minimumSize: const Size(44, 44),
              shape: const RoundedRectangleBorder(),
            ),
            child: Semantics(
              label: 'Prepare ${_clean(action.label)}',
              selected: selected,
              excludeSemantics: true,
              child: Column(
                children: [
                  JournalOrderIcon(type: type, size: 34),
                  const SizedBox(height: 3),
                  Text(
                    _clean(action.label),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: JournalPalette.small.copyWith(
                      fontSize: 11,
                      color: action.enabled
                          ? JournalPalette.ink
                          : JournalPalette.muted,
                    ),
                  ),
                  if (selected)
                    Icon(
                      hasPreparedOrder
                          ? Icons.hourglass_top
                          : Icons.check_circle,
                      size: 14,
                      color: hasPreparedOrder
                          ? JournalPalette.binding
                          : JournalPalette.olive,
                    ),
                  if (!action.enabled && help.unavailableReason != null)
                    Text(
                      help.unavailableReason!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: JournalPalette.small.copyWith(
                        fontSize: 9,
                        color: JournalPalette.danger,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reportsContext(bool narrow) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Current orders · ${squad?.name ?? 'Organisation'}',
        style: JournalPalette.heading,
      ),
      const SizedBox(height: 6),
      if (squad?.activity.type == ActivityType.visit)
        Text(squad!.activity.description, style: JournalPalette.body),
      SizedBox(
        height: members.length > 3 ? 144 : 95,
        child: ListView(
          children: [
            for (final member in members)
              InkWell(
                onTap: () async {
                  controller.inspectPerson(member.id);
                  setState(() => _orders = true);
                  await controller.openOrders(member.id);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(member.name, style: JournalPalette.small),
                      ),
                      Expanded(
                        child: Text(
                          member.activity.description,
                          style: JournalPalette.small,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      const Divider(height: 12),
      Expanded(child: _mapContext()),
    ],
  );

  List<Location> _locations() {
    if (planning) {
      return console.actions
          .where(
            (a) => const {'site', 'district', 'city'}.contains(a.entityType),
          )
          .map(
            (a) => <Location>[
              ...game.cities,
              ...game.cities.expand((c) => c.districts),
              ...game.sites,
            ].where((l) => l.idString == a.entityId).firstOrNull,
          )
          .nonNulls
          .toList();
    }
    final city =
        squad?.site?.city ??
        game.activeSafehouse?.city ??
        game.cities.firstOrNull;
    final district = city?.districts
        .where((d) => d.idString == _areaId)
        .firstOrNull;
    if (district != null) {
      return district.sites.where((site) => !site.hidden).toList();
    }
    return city?.districts ?? const [];
  }

  List<String> _locationDetails(ConsoleAction action) {
    if (action.y < 0 || action.y >= console.height) return const [];
    return [
      console.buffer[action.y]
          .skip((action.x + action.width).clamp(0, console.width))
          .map((c) => c.glyph)
          .join()
          .trim(),
    ];
  }

  Widget _mapContext() {
    final locations = _locations();
    final city = squad?.site?.city ?? game.activeSafehouse?.city;
    final places = locations.map((location) {
      final action = console.actions
          .where(
            (a) =>
                a.entityId == location.idString &&
                const {'site', 'district', 'city'}.contains(a.entityType),
          )
          .firstOrNull;
      return JournalMapPlace(
        id: location.idString,
        name:
            '${location.getName()}${travelSuffix(travelNotices(location, squad))}',
        // SiteType.name is a display title; EnumName is the stable enum key.
        siteType: location is Site ? EnumName(location.type).name : null,
        kind: location is Site
            ? 'site'
            : location is District
            ? 'district'
            : 'city',
        enabled: !planning || action?.enabled == true,
        current: location == squad?.site || location == squad?.site?.district,
        queued: location.idString == squad?.activity.idString,
        details: [
          if (location is Site) locationPurpose(location.type),
          if (action != null) ..._locationDetails(action),
        ],
      );
    }).toList();
    void select(String id) {
      if (_visitRouting || controller.busy) return;
      final location = locations.where((l) => l.idString == id).firstOrNull;
      if (location == null) return;
      _visitRequest++;
      setState(() {
        _visitMessage = null;
        _targetId = location is Site ? id : null;
        _targetSquadId = location is Site ? squad?.id : null;
      });
      if (location is District || location is City) {
        if (planning) {
          final action = console.actions
              .where((a) => a.entityId == id)
              .firstOrNull;
          if (action?.enabled == true) {
            unawaited(_dispatch(action!));
          } else if (action != null) {
            setState(() => _visitMessage = _unavailableVisit(action));
          }
        } else {
          setState(() => _areaId = id);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: JournalCityPlan(
            places: places,
            onSelect: select,
            selectedId: _targetId,
            allowUnavailableInspection: true,
            showLegend: !_compactMapText,
            title: planning ? 'Select a destination' : city?.name ?? 'City map',
          ),
        ),
        if (_selectedDestination != null) _destinationCard(),
        if (_visitMessage != null)
          Text(
            _visitMessage!,
            key: const ValueKey('journal-visit-message'),
            style: JournalPalette.small.copyWith(color: JournalPalette.danger),
          ),
        if (planning)
          Wrap(
            spacing: 4,
            children: [
              for (final action in console.actions.where(
                (a) =>
                    !const {
                      'site',
                      'district',
                      'city',
                      'person',
                    }.contains(a.entityType) &&
                    (a.key != 'Enter' || a.label.contains('Back one step')),
              ))
                TextButton(
                  onPressed: action.enabled && !controller.busy
                      ? () => _dispatch(action)
                      : null,
                  child: Text(
                    action.key == 'Enter'
                        ? 'Back one step'
                        : action.entityType == 'intercity-travel'
                        ? 'Other cities${travelSuffix(intercityTravelNotices(squad))}'
                        : _clean(action.label),
                    style: JournalPalette.small,
                  ),
                ),
            ],
          )
        else if (_areaId != null)
          TextButton.icon(
            style: _compactMapText
                ? TextButton.styleFrom(
                    minimumSize: const Size(44, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
                  )
                : null,
            onPressed: () => setState(() {
              _areaId = null;
              _targetId = null;
            }),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: Text(
              'City overview',
              style: _compactMapText ? JournalPalette.small : null,
            ),
          ),
      ],
    );
  }

  Future<void> _prepareMapVisit() async {
    if (_visitRouting || !controller.canNavigate || undercover) return;
    final selected = _selectedDestination;
    final squadId = squad?.id;
    final request = ++_visitRequest;
    setState(() {
      _visitRouting = true;
      _visitMessage = null;
      _pendingOrder = null;
      _pendingRevision = null;
      _pool = false;
      _orders = false;
      _showReports = false;
      if (selected != null) _areaId = selected.district.idString;
    });
    bool current() =>
        mounted &&
        request == _visitRequest &&
        squad?.id == squadId &&
        game.activeSquad?.id == squadId &&
        (selected == null || _targetId == selected.idString);
    try {
      if (!await controller.openSection('f') || !current() || !planning) {
        if (current()) {
          setState(
            () => _visitMessage =
                controller.message ??
                'Visit planning is unavailable for the selected squad.',
          );
        }
        return;
      }
      if (selected == null) return;
      final district = await _findVisitAction(
        'district',
        selected.district.idString,
        current,
      );
      if (!current() || district == null) {
        if (current()) {
          setState(
            () => _visitMessage =
                'The original planner does not offer this district to the selected squad.',
          );
        }
        return;
      }
      if (!district.enabled) {
        setState(() => _visitMessage = _unavailableVisit(district));
        return;
      }
      if (!await controller.sendAction(
            district,
            revision: console.revision.value,
          ) ||
          !current()) {
        return;
      }
      final destination = await _findVisitAction(
        'site',
        selected.idString,
        current,
      );
      if (!current()) return;
      setState(
        () => _visitMessage = destination == null
            ? 'The original planner does not offer this building.'
            : destination.enabled
            ? null
            : _unavailableVisit(destination),
      );
    } finally {
      if (mounted) setState(() => _visitRouting = false);
      _restoreInputFocus();
    }
  }

  Future<ConsoleAction?> _findVisitAction(
    String type,
    String id,
    bool Function() current,
  ) async {
    // The original planner retains its page when entering a district. Use its
    // actual page controls to start at the first page, then locate the entity.
    final rewind = <String>{};
    while (current() && planning) {
      final previous = console.actions
          .where((a) => a.key == 'PageUp' && a.enabled)
          .firstOrNull;
      if (previous == null) break;
      final signature = console.actions
          .map((a) => '${a.entityType}:${a.entityId}:${a.key}')
          .join('|');
      if (!rewind.add(signature) ||
          !await controller.sendAction(
            previous,
            revision: console.revision.value,
          )) {
        return null;
      }
    }
    final visited = <String>{};
    for (var page = 0; page < 256 && current() && planning; page++) {
      final action = console.actions
          .where((a) => a.entityType == type && a.entityId == id)
          .firstOrNull;
      if (action != null) return action;
      final signature = console.actions
          .map((a) => '${a.entityType}:${a.entityId}:${a.key}')
          .join('|');
      if (!visited.add(signature)) break;
      final next = console.actions
          .where((a) => a.key == 'PageDown' && a.enabled)
          .firstOrNull;
      if (next == null ||
          !await controller.sendAction(
            next,
            revision: console.revision.value,
          )) {
        break;
      }
    }
    return null;
  }

  String _unavailableVisit(ConsoleAction action) {
    final reason = _locationDetails(
      action,
    ).where((text) => text.isNotEmpty).join(' · ');
    return reason.isEmpty
        ? 'Unavailable for this squad in the current visit planner.'
        : reason;
  }

  Future<void> _confirmVisit(ConsoleAction action) async {
    final target = _selectedDestination;
    if (_visitRouting ||
        target == null ||
        !identical(action, _visitAction) ||
        !action.enabled) {
      return;
    }
    if (await controller.sendAction(action, revision: console.revision.value) &&
        mounted) {
      setState(() {
        _orders = false;
        _visitMessage = null;
      });
      _restoreInputFocus();
    }
  }

  Future<void> _cancelVisit() async {
    if (_visitRouting) return;
    _visitRequest++;
    if (await controller.returnToHeadquarters() && mounted) {
      setState(() {
        _orders = false;
        _visitMessage = null;
      });
      _restoreInputFocus();
    }
  }

  Widget _destinationCard() {
    final target = _selectedDestination!;
    final queued =
        squad?.activity.type == ActivityType.visit &&
        squad?.activity.idString == target.idString;
    return Padding(
      padding: EdgeInsets.only(top: _compactMapText ? 4 : 7),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: _compactMapText || MediaQuery.sizeOf(context).height < 700
              ? 110
              : 220,
        ),
        child: SingleChildScrollView(
          child: JournalSurface(
            key: const ValueKey('journal-selected-destination'),
            inset: true,
            padding: EdgeInsets.all(_compactMapText ? 4 : 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        target.getName(),
                        key: const ValueKey('journal-destination-name'),
                        style: JournalPalette.heading.copyWith(fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      key: const ValueKey('journal-location-details'),
                      onPressed: () => showLocationDetails(context, target),
                      icon: const JournalLocationGuideIcon(size: 22),
                      label: const Text('Location guide'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                      ),
                    ),
                  ],
                ),
                MechanicsTooltip(
                  message:
                      '${locationPurpose(target.type)}\n\n${locationAccess(target)}',
                  child: Text(
                    locationPurpose(target.type),
                    key: const ValueKey('journal-destination-purpose'),
                    maxLines: _compactMapText ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: JournalPalette.small,
                  ),
                ),
                Text(
                  locationAccess(target),
                  key: const ValueKey('journal-destination-access'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JournalPalette.small,
                ),
                Text(
                  locationPeopleSummary(target),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: JournalPalette.small,
                ),
                if (queued && !planning)
                  const Text(
                    'Visit queued',
                    key: ValueKey('journal-queued-visit'),
                    style: JournalPalette.small,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _dispatch(ConsoleAction action) async {
    final revision = console.revision.value;
    if (widget.onCloseInspection != null) widget.onCloseInspection!();
    await controller.sendAction(action, revision: revision);
  }

  Future<void> _headquartersCommands() async {
    if (!await controller.returnToHeadquarters() || !mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final revision = console.revision.value;
    final choices = List<ConsoleAction>.of(console.actions);
    final action = await showMenu<ConsoleAction>(
      context: context,
      position: const RelativeRect.fromLTRB(25, 80, 25, 45),
      items: [
        for (final choice in choices)
          PopupMenuItem(
            value: choice,
            enabled: choice.enabled,
            child: Text(_clean(choice.label), style: JournalPalette.body),
          ),
      ],
    );
    if (action != null && mounted) {
      await controller.sendAction(action, revision: revision);
    }
  }

  Widget _footer(bool narrow) {
    final revision = console.revision.value;
    final ledger = ledgerReportFrame(console);
    final detailOwnsContinue =
        console.eventMessage == null &&
        (console.legislation != null || ledger != null && !ledger.management);
    final continueAction = ledger != null && !ledger.management
        ? ledger.closeAction
        : console.actions
              .where(
                (action) => RegExp(
                  r'^(continue\b|press .+ to continue\b)',
                  caseSensitive: false,
                ).hasMatch(_clean(action.label)),
              )
              .firstOrNull;
    final acknowledgement =
        console.eventMessage != null ||
        console.screen == 'article' && console.article != null ||
        console.screen == 'full_map' ||
        console.actions.isEmpty &&
            console.awaitingInput &&
            !controller.canNavigate;
    final continuing =
        !console.textInput && (acknowledgement || continueAction != null);
    final canContinue =
        continuing &&
        console.awaitingInput &&
        !controller.busy &&
        (continueAction?.enabled ?? true);
    final directHQ = console.screen == 'headquarters';
    ConsoleAction? current(String key) =>
        console.actions.where((a) => a.key == key).firstOrNull;
    final wait =
        controller.headquartersAction('w') ?? (directHQ ? current('w') : null);
    final known = controller.headquarters != null || directHQ;
    final label = continuing
        ? console.screen == 'full_map'
              ? 'Back to operation'
              : 'Continue'
        : known
        ? wait == null
              ? 'Day advance unavailable'
              : _clean(wait.label)
        : 'Return to planning';
    final cancel =
        controller.headquartersAction('c') ?? (directHQ ? current('c') : null);
    return SizedBox(
      height: narrow ? 41 : 45,
      child: Row(
        children: [
          IconButton(
            tooltip: 'More headquarters commands',
            key: const ValueKey('journal-more-commands'),
            onPressed: controller.canNavigate ? _headquartersCommands : null,
            icon: const Icon(
              Icons.menu_book,
              color: JournalPalette.brassLight,
              size: 21,
            ),
          ),
          Expanded(
            child: Text(
              '${game.day} ${getMonth(game.month).substring(0, 3)} ${game.year}  ·  \$${game.ledger.funds}',
              key: const ValueKey('journal-date-funds'),
              style: JournalPalette.small.copyWith(color: JournalPalette.card),
            ),
          ),
          PopupMenuButton<double>(
            tooltip: 'Reading size',
            initialValue: widget.textScale,
            onSelected: widget.onTextScale,
            icon: const Icon(
              Icons.text_fields,
              color: JournalPalette.brassLight,
              size: 22,
            ),
            itemBuilder: (_) => [
              for (final scale in [1.0, 1.25, 1.5])
                PopupMenuItem(
                  value: scale,
                  child: Text('${(scale * 100).round()}%'),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Switch readable / classic view',
            onPressed: widget.onClassic,
            icon: const Icon(
              Icons.terminal,
              color: JournalPalette.brassLight,
              size: 21,
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('journal-save-exit'),
            onPressed: controller.canNavigate
                ? () => controller.openSection('x')
                : null,
            style: OutlinedButton.styleFrom(
              backgroundColor: JournalPalette.page,
              minimumSize: const Size(44, 34),
              padding: const EdgeInsets.symmetric(horizontal: 9),
            ),
            icon: const Icon(Icons.save_outlined, size: 17),
            label: const Text('Save & exit'),
          ),
          const SizedBox(width: 9),
          if (cancel?.enabled == true)
            IconButton(
              tooltip: _clean(cancel!.label),
              key: const ValueKey('journal-cancel-departure'),
              onPressed: controller.canNavigate
                  ? () => controller.openSection(cancel.key)
                  : null,
              icon: const Icon(
                Icons.cancel_outlined,
                color: JournalPalette.brassLight,
              ),
            ),
          if (!detailOwnsContinue)
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: narrow ? 200 : 340),
              child: Tooltip(
                message: label,
                child: FilledButton.icon(
                  key: const ValueKey('journal-advance-day'),
                  onPressed: continuing
                      ? canContinue
                            ? () {
                                // A retained callback must not advance a later
                                // report or answer a newly opened decision.
                                if (console.revision.value != revision ||
                                    !console.awaitingInput ||
                                    console.textInput ||
                                    controller.busy) {
                                  return;
                                }
                                widget.onAction(continueAction?.key ?? 'Enter');
                                _restoreInputFocus();
                              }
                            : null
                      : !controller.canNavigate
                      ? null
                      : !known
                      ? controller.returnToHeadquarters
                      : wait?.enabled == true
                      ? () async {
                          await controller.openSection(wait!.key);
                          _restoreInputFocus();
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: JournalPalette.binding,
                    minimumSize: const Size(44, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: Icon(
                    continuing ? Icons.arrow_forward : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _clean(String label) => stripConsoleColors(
    label,
  ).replaceFirst(RegExp(r'^\(?[A-Za-z0-9?]+\s*[-–:]\s*'), '').trim();

  void _restoreInputFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          console.awaitingInput &&
          !console.textInput &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        Focus.maybeOf(context)?.requestFocus();
      }
    });
  }
}
