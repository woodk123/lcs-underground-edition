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
import 'package:lcs_new_age/modern/injury_status.dart';
import 'package:lcs_new_age/modern/journal_bases.dart';
import 'package:lcs_new_age/modern/journal_city_plan.dart';
import 'package:lcs_new_age/modern/journal_navigation_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_network.dart';
import 'package:lcs_new_age/modern/journal_order_icon.dart';
import 'package:lcs_new_age/modern/journal_people.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_indicator.dart';
import 'package:lcs_new_age/modern/location_details.dart';
import 'package:lcs_new_age/modern/location_help.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/order_mechanics_dialog.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/modern/organisation_crew_pool.dart';
import 'package:lcs_new_age/modern/organisation_crew_roster.dart';
import 'package:lcs_new_age/modern/organisation_order_card.dart';
import 'package:lcs_new_age/modern/organisation_order_workspace.dart';
import 'package:lcs_new_age/modern/organisation_reviews.dart';
import 'package:lcs_new_age/modern/organisation_skills_paper.dart';
import 'package:lcs_new_age/modern/organisation_team_header.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/modern/recruitment_target_picker.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/modern/squad_readiness.dart';
import 'package:lcs_new_age/modern/travel_help.dart';

// Existing section IDs remain stable for retained journal routes and shortcuts.
const networkJournalSection = 8;
const peopleJournalSection = 9;
const basesJournalSection = 10;

/// A local pointer draft retains the exact source action and its revision.
typedef _PreparedOrder = ({ConsoleAction action, int revision});

typedef _JournalFooterCommand = ({
  String label,
  String? shortcut,
  bool continuing,
  bool detailOwnsContinue,
  VoidCallback? onPressed,
});

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
    this.peopleToolsBuilder,
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
  final WidgetBuilder? peopleToolsBuilder;

  @override
  State<OrganisationJournal> createState() => OrganisationJournalState();
}

class OrganisationJournalState extends State<OrganisationJournal> {
  final _sectionKeys = <int, GlobalKey>{};
  final _networkKey = GlobalKey<JournalNetworkViewState>();
  final _basesKey = GlobalKey<JournalBasesViewState>();
  JournalPeopleScope _peopleScope = JournalPeopleScope.people;
  bool _managementDialog = false;
  final ScrollController _narrowJournalScroll = ScrollController();
  final ScrollController _sectionScroll = ScrollController();
  final ScrollController _orderTaskScroll = ScrollController();
  final PersonnelDirectoryController _personnel =
      PersonnelDirectoryController();

  @override
  void dispose() {
    _narrowJournalScroll.dispose();
    _sectionScroll.dispose();
    _orderTaskScroll.dispose();
    _personnel.dispose();
    super.dispose();
  }

  bool _orders = false, _skills = false, _pool = false;
  bool _ordersMap = false;
  bool _showReports = false;
  bool _personnelTools = false;
  bool _sourceKeyboardInput = false;
  Skill _poolSort = Skill.firearms;
  int _group = 0;
  int? _poolPerson;
  String? _areaId, _targetId, _categoryId;
  _PreparedOrder? _pendingOrder;
  List<ConsoleAction> _orderBrowseActions = const [];
  String? _orderBrowseTaskStorageId;
  int? _targetSquadId;
  bool _visitRouting = false;
  String? _visitMessage;
  int _visitRequest = 0;
  bool get hasPreparedOrder =>
      _pendingOrder != null &&
      _pendingOrder!.revision == console.revision.value &&
      console.actions.contains(_pendingOrder!.action) &&
      activityFrame;

  bool get _hasUnconfirmedDraft =>
      hasPreparedOrder ||
      (planning && _selectedDestination != null) ||
      (_networkKey.currentState?.hasPreparedOrder ?? false) ||
      (_basesKey.currentState?.hasPreparedPurchase ?? false);

  /// External development actions must respect the same local draft boundary.
  bool get hasUnconfirmedDraft => _hasUnconfirmedDraft;

  void _draftChanged(bool _) {
    if (mounted) setState(() {});
  }

  Console get console => widget.console;
  OrganisationController get controller => widget.controller;
  Squad? get squad => controller.selectedSquad ?? game.activeSquad;
  bool get undercover =>
      confirmation?.entityType == 'sleeper-activity-confirm' ||
      !allocating &&
          _requiredRecruitmentActor == null &&
          controller.selectedPerson?.sleeperAgent == true;
  Creature? get _requiredRecruitmentActor {
    if (!console.awaitingInput ||
        console.lastKey != null ||
        console.textInput ||
        console.eventMessage != null) {
      return null;
    }
    return console.recruitmentTarget?.recruiter ??
        console.recruitment?.recruiter;
  }

  Creature? get _requiredEducationActor {
    if (!console.awaitingInput ||
        console.textInput ||
        console.eventMessage != null) {
      return null;
    }
    final actorIds = console.actions
        .where((action) => action.entityType == 'education-skill')
        .map((action) => action.entityCategory)
        .toSet();
    if (actorIds.length != 1) return null;
    final actorId = int.tryParse(actorIds.single ?? '');
    return game.pool.where((p) => p.id == actorId).firstOrNull;
  }

  Creature? get _individualOrderActor {
    final requiredActor = _requiredRecruitmentActor ?? _requiredEducationActor;
    if ((!activityFrame && requiredActor == null) || undercover || allocating) {
      return null;
    }
    final actorId = int.tryParse(confirmation?.entityCategory ?? '');
    final actor =
        requiredActor ?? game.pool.where((p) => p.id == actorId).firstOrNull;
    return actor != null &&
            !(squad?.members.any((p) => p.id == actor.id) ?? false)
        ? actor
        : null;
  }

  List<Creature> get members => controller.assembly != null
      ? controller.allocationMembers
      : undercover
      ? game.pool.where((p) => p.sleeperAgent && p.alive).toList()
      : _individualOrderActor != null
      ? [_individualOrderActor!]
      : squad?.members ?? const [];
  Creature? get person {
    final recruiter = _requiredRecruitmentActor;
    if (recruiter != null) return recruiter;
    final profile = console.journalProfile;
    if (profile != null) return profile.person;
    final requiredActor = _requiredEducationActor;
    if (requiredActor != null) return requiredActor;
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
  bool get _showPeople =>
      widget.section == peopleJournalSection &&
      !widget.fullSpreadDetail &&
      !activityFrame &&
      !allocating &&
      widget.detail == null;
  bool get _showBases =>
      widget.section == basesJournalSection &&
      !widget.fullSpreadDetail &&
      !allocating &&
      widget.detail == null;
  bool get planning => console.screen == 'planning';
  bool get allocating => controller.assembly != null;
  bool get overview => console.screen == 'organisation';
  bool get _compactMapText =>
      widget.textScale > 1.1 && MediaQuery.sizeOf(context).width < 1000;
  bool get _compact => JournalPreferences.of(context).compact;
  bool get _showGuidance => JournalPreferences.of(context).showGuidance;
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

  /// Presentation dialogs keep their own input. Otherwise the original reader
  /// owns every game key, including category defaults, immediate choices and
  /// Back aliases. Pointer previews must never add keyboard confirmation steps.
  bool handleGameShortcut(String key) {
    if (!_managementDialog) return false;
    if (normalizeConsoleKey(key) == 'Escape') {
      unawaited(Navigator.of(context, rootNavigator: true).maybePop());
    }
    return true;
  }

  /// Drop pointer-only drafts before a source key and expose the current source
  /// roster rather than a differently sorted/searchable presentation directory.
  void prepareForSourceInput() {
    setState(() {
      _pendingOrder = null;
      _targetId = null;
      _ordersMap = false;
      _showReports = false;
      _pool = false;
      _personnelTools = true;
      _orders = activityFrame || planning;
      _sourceKeyboardInput = true;
      _syncSourceCategory();
    });
  }

  void pointerInputStarted() => _sourceKeyboardInput = false;

  void _syncSourceCategory() {
    final frame = activityOrderFrame(console);
    if (frame == null) return;
    _orders = true;
    final category = console.actions
        .where(
          (action) =>
              action.key == frame.selectedCategoryKey &&
              const {
                'activity-category',
                'sleeper-category',
                'sleeper-category-selected',
              }.contains(action.entityType),
        )
        .firstOrNull;
    _categoryId = category?.entityId;
    _group = category == null
        ? 3
        : const {
            'legal',
            'illegal',
            'sleeper-espionage',
          }.contains(category.entityId)
        ? 0
        : const {'activism', 'sleeper-advocacy'}.contains(category.entityId)
        ? 2
        : 1;
  }

  /// Global journal commands use the same live controls as pointer activation.
  /// They never send an HQ key into whichever source reader is open now.
  bool handleGlobalCommand(JournalGlobalCommand command) {
    if (!mounted ||
        _managementDialog ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
        console.textInput ||
        controller.busy) {
      return false;
    }
    final VoidCallback? callback;
    switch (command) {
      case JournalGlobalCommand.saveAndExit:
        callback = _saveExitCommand;
      case JournalGlobalCommand.advanceDay:
        final primary = _footerPrimaryCommand();
        // Required messages retain their own original acknowledgement key.
        if (primary.continuing || primary.detailOwnsContinue) return false;
        callback = primary.onPressed;
    }
    if (callback == null) return false;
    callback();
    return true;
  }

  /// Reveal a routed tab without taking focus away from the game reader.
  void revealSection(int section) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _sectionKeys[section]?.currentContext;
      if (target != null) {
        final scrollable = Scrollable.maybeOf(target, axis: Axis.horizontal);
        final targetBox = target.findRenderObject();
        final scrollBox = scrollable?.context.findRenderObject();
        if (targetBox is RenderBox && scrollBox is RenderBox) {
          final left = targetBox
              .localToGlobal(Offset.zero, ancestor: scrollBox)
              .dx;
          // A visible tab needs no movement. Preserve the player's strip
          // position when a source reader changes within the visible group.
          if (left >= 0 &&
              left + targetBox.size.width <=
                  scrollable!.position.viewportDimension) {
            return;
          }
        }
        unawaited(
          Scrollable.ensureVisible(
            target,
            alignment: .5,
            duration: Duration.zero,
          ),
        );
      }
    });
  }

  @override
  void didUpdateWidget(OrganisationJournal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      revealSection(widget.section);
      _visitRequest++;
      _pendingOrder = null;
      _pool = false;
      _poolPerson = null;
      _orders = false;
      _showReports = widget.section == 5;
    }
    if (_sourceKeyboardInput) _syncSourceCategory();
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
                    child: _showPeople
                        ? JournalSurface(
                            padding: const EdgeInsets.all(12),
                            child: _peopleView(),
                          )
                        : _showBases
                        ? JournalSurface(
                            padding: EdgeInsets.zero,
                            child: JournalBasesView(
                              key: _basesKey,
                              console: console,
                              controller: controller,
                              onDraftChanged: _draftChanged,
                              onInspect: (person) => unawaited(
                                controller.openPersonnelProfile(person.id),
                              ),
                            ),
                          )
                        : widget.section == networkJournalSection &&
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
                            onDraftChanged: _draftChanged,
                          )
                        : (widget.section != 0 &&
                                      widget.section != peopleJournalSection ||
                                  widget.fullSpreadDetail) &&
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

  // Presentation-owned lists keep their local letter meanings. Advertise HQ
  // routes as scoped metadata when those keys do not reach the HQ reader.
  bool get _sourceKeysPassThrough =>
      !_showPeople &&
      !_showBases &&
      widget.section != networkJournalSection &&
      !_managementDialog &&
      !_hasUnconfirmedDraft;

  bool get _headquartersKeysActive =>
      console.screen == 'headquarters' &&
      controller.canNavigate &&
      _sourceKeysPassThrough;

  String _headquartersShortcut(String key) =>
      _headquartersKeysActive ? key : 'HQ: $key';

  String? _originalSectionShortcut(int section) {
    if (console.screen == 'organisation' && _sourceKeysPassThrough) {
      final key = switch (section) {
        1 => 'v',
        2 => '4',
        peopleJournalSection => '0',
        _ => null,
      };
      if (key != null &&
          console.actions.any(
            (action) => action.key == key && action.enabled,
          )) {
        return key;
      }
    }
    final route = journalOriginalSectionRoutes[section];
    return route == null ? null : _headquartersShortcut(route);
  }

  String _sectionShortcutHelp(int section) {
    final route = journalOriginalSectionRoutes[section];
    final current = _originalSectionShortcut(section);
    return '${current == null ? '' : 'Keyboard shortcut: ${journalShortcutSpokenLabel(current)}. '}'
        '${route == null ? '' : 'Original headquarters route: ${journalShortcutLabel(route)}. '}'
        'Optional global shortcut: ${journalSectionShortcuts[section]}.';
  }

  Widget _sectionTabs(bool narrow) {
    const tabs = <(int, String, JournalIcon)>[
      (0, 'Organisation', JournalIcon.crew),
      (peopleJournalSection, 'People', JournalIcon.people),
      (networkJournalSection, 'Network', JournalIcon.network),
      (basesJournalSection, 'Bases', JournalIcon.bases),
      (1, 'Ledger', JournalIcon.accounts),
      (2, 'Justice', JournalIcon.law),
      (3, 'Agenda', JournalIcon.diplomacy),
      (4, 'Newspaper', JournalIcon.newspaper),
      (5, 'Reports', JournalIcon.reports),
      (6, 'City maps', JournalIcon.city),
      (7, 'Options', JournalIcon.options),
    ];
    final reviews = controller.networkReviews.count(game.pool);
    final peopleReviews = controller.organisationReviews.notices.length;
    Widget tab((int, String, JournalIcon) item) => Padding(
      key: _sectionKeys.putIfAbsent(
        item.$1,
        () => GlobalKey(debugLabel: 'Journal section ${item.$1}'),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Tooltip(
        excludeFromSemantics: true,
        message: controller.canNavigate
            ? '${item.$1 == networkJournalSection ? 'Sleeper agents · monthly standing orders' : item.$2}. ${_sectionShortcutHelp(item.$1)}'
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
                enabled: controller.canNavigate,
                excludeSemantics: true,
                selected: widget.section == item.$1,
                label: item.$1 == peopleJournalSection && peopleReviews > 0
                    ? 'People. $peopleReviews changes to review.'
                    : item.$1 == networkJournalSection && reviews > 0
                    ? 'Network. $reviews ${reviews == 1 ? 'role' : 'roles'} to review.'
                    : item.$2,
                hint:
                    '${_sectionShortcutHelp(item.$1)}${item.$1 == networkJournalSection ? ' Sleeper agents · monthly standing orders.' : ''}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          JournalIllustratedIcon(
                            icon: item.$3,
                            size: narrow ? 22 : 28,
                          ),
                          if (_originalSectionShortcut(item.$1)
                              case final shortcut?) ...[
                            const SizedBox(width: 4),
                            JournalShortcutBadge(shortcut: shortcut),
                          ],
                        ],
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
                          if (item.$1 == networkJournalSection && reviews > 0 ||
                              item.$1 == peopleJournalSection &&
                                  peopleReviews > 0)
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
                                    '${item.$1 == peopleJournalSection ? peopleReviews : reviews}',
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
              builder: (context, bounds) {
                // Let the complete tab, including borders and the current
                // font's badge metrics, determine its minimum usable width.
                final minimumTabWidth = (bounds.maxWidth / tabs.length).clamp(
                  widget.textScale > 1.1 ? 120.0 : 100.0,
                  double.infinity,
                );
                return Scrollbar(
                  controller: _sectionScroll,
                  child: SingleChildScrollView(
                    key: const ValueKey('journal-section-scroll'),
                    controller: _sectionScroll,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final item in tabs)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              minWidth: minimumTabWidth,
                            ),
                            child: IntrinsicWidth(child: tab(item)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Tooltip(
            message: 'Field guide',
            excludeFromSemantics: true,
            child: Semantics(
              button: true,
              excludeSemantics: true,
              label: 'Field guide',
              hint: 'Keyboard shortcut: F1',
              onTap: widget.onHelp,
              child: TextButton.icon(
                onPressed: widget.onHelp,
                icon: const Icon(
                  Icons.keyboard_outlined,
                  color: JournalPalette.brassLight,
                ),
                label: Text(
                  'Keys · F1',
                  style: JournalPalette.small.copyWith(
                    color: JournalPalette.brassLight,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _peopleView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('journal-equipment'),
          onPressed: controller.canNavigate
              ? () => _openManagementSection('e')
              : null,
          icon: const JournalIllustratedIcon(
            icon: JournalIcon.stores,
            size: 22,
          ),
          label: const Text('Equipment'),
        ),
      ),
      Expanded(
        child: _personnelTools
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
                        onPressed: () =>
                            setState(() => _personnelTools = false),
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Back to directory'),
                      ),
                    ],
                  ),
                  Expanded(
                    child:
                        widget.peopleToolsBuilder?.call(context) ??
                        const SizedBox.shrink(),
                  ),
                ],
              )
            : _peopleDirectory(),
      ),
    ],
  );

  Widget _peopleDirectory() => JournalPeopleView(
    people: game.pool,
    directoryController: _personnel,
    initialScope: _peopleScope,
    onScopeChanged: (scope) => _peopleScope = scope,
    scopeArtBuilder: (scope) => JournalIllustratedIcon(
      icon: switch (scope) {
        JournalPeopleScope.people => JournalIcon.people,
        JournalPeopleScope.leadership => JournalIcon.leadership,
        JournalPeopleScope.captives => JournalIcon.captives,
      },
      size: 44,
    ),
    reviewPanel: _peopleReviews(),
    onTools: () => setState(() => _personnelTools = true),
    enabled: controller.canNavigate && !controller.busy,
    onOpenProfile: (p) => unawaited(controller.openPersonnelProfile(p.id)),
    onAssignOrder: (p) => unawaited(preparePersonOrder(p)),
    onJoinSquad: (p) => unawaited(_joinSquad(p)),
    onOpenPromotionTools: () => unawaited(controller.openPromotionTools()),
    onPromotePerson: (p) => unawaited(_promotePerson(p)),
    onAssignTender: (p) => unawaited(
      preparePersonOrder(
        p,
        categoryId: 'acquisition',
        activity: ActivityType.interrogation,
      ),
    ),
  );

  Widget _peopleReviews() {
    final notices = controller.organisationReviews.notices;
    if (notices.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      key: const PageStorageKey('people-changes-review'),
      initiallyExpanded: notices.length <= 2,
      title: Text(
        '${notices.length} ${notices.length == 1 ? 'change' : 'changes'} to review',
        style: JournalPalette.heading,
      ),
      leading: const Icon(
        Icons.notifications_active_outlined,
        color: JournalPalette.brassDark,
      ),
      children: [
        SizedBox(
          height: (notices.length * 115.0).clamp(100, 200),
          child: ListView(
            // The tile stores a bool in its PageStorage entry. The nested
            // scroll position needs its own identifier for a double offset.
            key: const PageStorageKey('people-changes-review-list'),
            children: [
              for (final notice in notices)
                if (game.pool.where((p) => p.id == notice.personId).firstOrNull
                    case final p?)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 5, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.name} · ${notice.title}',
                          style: JournalPalette.heading,
                        ),
                        Text(notice.detail, style: JournalPalette.small),
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          children: [
                            if (notice.previousActivity != null)
                              _previousOrderButton(p, notice),
                            TextButton(
                              onPressed:
                                  controller.canNavigate &&
                                      personnelAvailableForOrders(p)
                                  ? () => unawaited(preparePersonOrder(p))
                                  : null,
                              child: const Text('Choose order'),
                            ),
                            if (p.isActiveLiberal && p.squad == null)
                              TextButton(
                                onPressed: controller.canNavigate
                                    ? () => unawaited(_joinSquad(p))
                                    : null,
                                child: const Text('Join squad'),
                              ),
                            TextButton(
                              onPressed: () => unawaited(
                                controller.organisationReviews.acknowledge(
                                  notice.id,
                                ),
                              ),
                              child: const Text('Keep resting'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _previousOrderButton(Creature actor, OrganisationReviewNotice notice) {
    final activity = notice.previousActivity;
    final category = previousOrderCategory(activity);
    return TextButton(
      key: ValueKey('journal-previous-order:${actor.id}'),
      onPressed:
          category != null &&
              controller.canNavigate &&
              !controller.busy &&
              personnelAvailableForOrders(actor)
          ? () {
              // Revalidate a retained callback against the live follow-up.
              if (!controller.canNavigate ||
                  !personnelAvailableForOrders(actor) ||
                  actor.activity.type != ActivityType.none ||
                  actor.squad?.activity.type == ActivityType.visit ||
                  !controller.organisationReviews.notices.contains(notice)) {
                return;
              }
              unawaited(
                preparePersonOrder(
                  actor,
                  categoryId: category,
                  activity: activity,
                ),
              );
            }
          : null,
      child: Text('Prepare previous order: ${activity?.label ?? ''}'),
    );
  }

  /// Prepares the original actor's order reader and category. Selecting a
  /// suggested job is still a local draft; the normal Confirm card commits it.
  Future<void> preparePersonOrder(
    Creature actor, {
    String categoryId = 'legal',
    ActivityType? activity,
  }) async {
    widget.onCloseInspection?.call();
    _pendingOrder = null;
    if (!await controller.openOrders(actor.id) || !mounted) return;
    final group = categoryId == 'activism'
        ? 2
        : const {'legal', 'illegal'}.contains(categoryId)
        ? 0
        : 1;
    setState(() {
      _orders = true;
      _pool = false;
      _showReports = false;
      _group = group;
    });
    await _openGroup(group, categoryId: categoryId);
    if (!mounted || activity == null) return;
    final action = console.actions
        .where(
          (a) =>
              a.entityType == 'activity' &&
              a.entityId == activity.name &&
              a.entityCategory == actor.id.toString(),
        )
        .firstOrNull;
    if (action != null && action.enabled) {
      setState(() {
        _pendingOrder = (action: action, revision: console.revision.value);
      });
    }
  }

  Future<void> _joinSquad(Creature actor) async {
    widget.onCloseInspection?.call();
    if (!await controller.openAllocation(squad?.id) || !mounted) return;
    setState(() {
      _pool = true;
      _orders = false;
      _poolPerson = actor.id;
      _pendingOrder = null;
    });
  }

  Future<void> _promotePerson(Creature actor) async {
    final action = await controller.preparePromotion(actor.id);
    if (action == null || !mounted) return;
    final revision = console.revision.value;
    final next = game.pool
        .where((p) => p.id.toString() == action.entityCategory)
        .firstOrNull;
    _managementDialog = true;
    bool? accepted;
    try {
      accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Promote ${actor.name}?'),
          content: Text(
            'Move their contact to ${next?.name ?? 'the next leader'}. '
            'Recruitment capacity is recalculated. No time passes.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Promote'),
            ),
          ],
        ),
      );
    } finally {
      _managementDialog = false;
    }
    if (!mounted) return;
    if (accepted == true) {
      await controller.sendAction(action, revision: revision);
    }
    if (mounted && controller.canNavigate) {
      await controller.openPersonnelDirectory();
    }
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
      person != null &&
          (person!.activity.type != ActivityType.none ||
              controller.organisationReviews.notices.any(
                (notice) =>
                    notice.personId == person!.id &&
                    notice.previousActivity != null,
              ));

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
                  members.length * (widget.textScale > 1.1 ? 56.0 : 44.0) + 56;
              final preferredJobHeight =
                  (bounds.maxHeight - headerHeight - crewDesired - 12).clamp(
                    widget.textScale > 1.1 ? (planning ? 260.0 : 230.0) : 140.0,
                    widget.textScale > 1.1 ? (planning ? 280.0 : 260.0) : 240.0,
                  );
              // Preserve a usable roster when the phone-width footer wraps.
              // The job's details already have their own scrolling viewport.
              final availableJobHeight =
                  (bounds.maxHeight - headerHeight - 12 - 80).clamp(
                    0.0,
                    double.infinity,
                  );
              final jobHeight = preferredJobHeight > availableJobHeight
                  ? availableJobHeight
                  : preferredJobHeight;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: headerHeight,
                    child: SingleChildScrollView(child: _teamHeader(narrow)),
                  ),
                  const SizedBox(height: 6),
                  if (_hasJob) ...[
                    SizedBox(
                      height: jobHeight,
                      child: _jobCard(
                        scrollHeading: jobHeight < preferredJobHeight,
                      ),
                    ),
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
        : _individualOrderActor != null
        ? 'Individual orders'
        : controller.assembly?.isNew == true
        ? 'New squad'
        : controller.assembly?.squadName ?? squad?.name ?? 'The organisation';
    final location =
        actor?.location?.getName(short: true, includeCity: true) ??
        'Unknown location';
    final wounded = actor?.body.parts.any((part) => part.wounded) == true;
    return OrganisationTeamHeaderView(
      teamName: teamName,
      showingSkills: _skills,
      onToggleSkills: () => setState(() => _skills = !_skills),
      actor: actor == null
          ? null
          : OrganisationTeamActorView(
              personId: actor.id,
              name: actor.name,
              location: location,
              status:
                  'Juice ${actor.juice} · ${actor.blood}/${actor.maxBlood} blood',
              statusTooltip:
                  'Juice ${actor.juice} · ${actor.title} · ${actor.blood}/${actor.maxBlood} blood${wounded ? ' · Injured' : ''}',
              statusWarning: actor.blood < actor.maxBlood || wounded,
              portrait: CrewPortrait(
                person: actor,
                size: _compact
                    ? 36
                    : narrow
                    ? 46
                    : 58,
              ),
              onInspect: () => widget.onInspect(actor),
            ),
      memberCount: undercover
          ? '${members.length} agents'
          : _individualOrderActor != null
          ? '1 person'
          : '${members.length}/6',
      memberCountLabel: undercover
          ? 'Undercover agents'
          : _individualOrderActor != null
          ? 'Individual assignment'
          : 'Squad members',
      armedCount: '${members.where((p) => p.equippedWeapon != null).length}',
      carCount: '${members.map((p) => p.car?.id).nonNulls.toSet().length}',
    );
  }

  Widget _innerRail(bool narrow) => SizedBox(
    width: _compact && widget.textScale > 1.1
        ? 88
        : narrow
        ? 64
        : 72,
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
                          _settleOrderTaskScroll();
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
          'People',
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
                  if (widget.onSection != null) {
                    widget.onSection!(peopleJournalSection);
                  } else {
                    await controller.openPersonnelDirectory();
                  }
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
              child: _compact
                  ? Container(
                      alignment: Alignment.center,
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 8,
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        softWrap: true,
                        style: JournalPalette.small.copyWith(
                          fontSize: 10,
                          height: 1.15,
                          color: onTap == null
                              ? JournalPalette.muted
                              : JournalPalette.ink,
                        ),
                      ),
                    )
                  : SizedBox(
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
    _settleOrderTaskScroll();
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
          _pendingOrder!.action,
          revision: _pendingOrder!.revision,
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

  Widget _crewPaper() => OrganisationCrewRosterView(
    title: undercover
        ? 'Undercover agents · ${members.length}'
        : _individualOrderActor != null
        ? 'Individual assignment'
        : 'Crew · ${members.length}/6',
    rows: [for (final member in members) _memberView(member)],
    showDone: allocating,
    onDone: controller.busy
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
    canAcceptPerson: (personId) =>
        !controller.busy && !members.any((member) => member.id == personId),
    onTransfer: (personId) => unawaited(controller.assignPerson(personId)),
    hint: _hasJob
        ? null
        : allocating
        ? 'Drag crew between these pages, or use Add / Remove.'
        : _showSquadNumberKeys
        ? '1–6: select · repeat: profile · 0: clear'
        : 'Select a name to inspect. Crew pool changes the team.',
  );

  bool get _showSquadNumberKeys =>
      controller.isHeadquarters &&
      controller.canNavigate &&
      widget.section == 0 &&
      widget.inspectedPerson == null &&
      !undercover &&
      !allocating;

  OrganisationCrewMemberView _memberView(Creature member) {
    final squadIndex = game.squad.indexOf(member);
    final numberKey = _showSquadNumberKeys && squadIndex >= 0
        ? '${squadIndex + 1}'
        : null;
    final injury = crewInjurySummary(member);
    final location = member.location?.getName(short: true) ?? 'In hiding';
    final showingOrders = _orders || activityFrame;
    final stacked = _compact && widget.textScale > 1.1;
    final clothing = member.equippedClothing;
    final clothingSummary = clothing == null
        ? 'No equipped clothing'
        : [
            if (clothing.quality > clothing.type.qualityLevels)
              'Tattered Rags'
            else
              clothing.type.name,
            if (clothing.bloody) 'Bloodstained',
            if (clothing.damaged) 'Damaged',
          ].join(' · ');
    final strengths =
        Skill.values.where((skill) => member.skill(skill) > 0).toList()
          ..sort((a, b) {
            final level = member.skill(b).compareTo(member.skill(a));
            return level != 0 ? level : a.displayName.compareTo(b.displayName);
          });
    final skillSummary = strengths.isEmpty
        ? 'No trained skills yet'
        : strengths
              .take(3)
              .map((skill) => '${skill.displayName} ${member.skill(skill)}')
              .join(' · ');
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
      _settleOrderTaskScroll();
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

    return OrganisationCrewMemberView(
      data: OrganisationCrewMemberData(
        personId: member.id,
        name: member.name,
        selected: person?.id == member.id,
        orderDescription: member.activity.description,
        location: location,
        clothingSummary: clothingSummary,
        clothingWarning:
            clothing == null || clothing.bloody || clothing.damaged,
        skillSummary: skillSummary,
        hasAssignment: member.activity.type != ActivityType.none,
        numberKey: numberKey,
        injury: injury,
      ),
      showingOrders: showingOrders,
      stacked: stacked,
      allocating: allocating,
      juiceBadge: JuiceBadge(person: member, compact: true, showHelp: false),
      onSelect: canSelect() ? () => unawaited(select()) : null,
      onInspect: () => widget.onInspect(member),
      onRemove: controller.busy
          ? null
          : () => controller.assignPerson(member.id),
    );
  }

  Widget _skillsPaper(Creature? actor) {
    final skills = Skill.values.toList()
      ..sort((a, b) => (actor?.skill(b) ?? 0).compareTo(actor?.skill(a) ?? 0));
    return OrganisationSkillsPaperView(
      title: actor == null ? 'Skills' : '${actor.name} · Skills',
      skills: [
        for (final skill in skills)
          OrganisationSkillData(
            id: skill.name,
            label: skill.displayName,
            level: actor?.skill(skill) ?? 0,
            help: skillHelp(skill, actor: actor),
          ),
      ],
    );
  }

  Future<void> _showOrderMechanics(ActivityMechanics help) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
        child: OrderMechanicsDialog(
          help: help,
          visitReadiness: help.type == ActivityType.visit
              ? SquadReadiness(members)
              : null,
          visitMemberNames: help.type == ActivityType.visit
              ? members.map((member) => member.name).toList()
              : const [],
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
    if (mounted) _restoreInputFocus();
  }

  Widget _jobCard({bool scrollHeading = false}) {
    if (widget.console.recruitmentTarget case final target?) {
      return JournalSurface(
        lined: true,
        padding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          child: RecruitmentTargetPreview(target: target),
        ),
      );
    }
    if (_requiredEducationActor case final actor?) {
      return _educationChoiceCard(actor);
    }
    final actor = person;
    final prepared = hasPreparedOrder;
    final previousOrder = actor == null
        ? null
        : controller.organisationReviews.notices
              .where(
                (notice) =>
                    notice.personId == actor.id &&
                    notice.previousActivity != null,
              )
              .firstOrNull;
    final actual = squad?.activity.type == ActivityType.visit
        ? squad!.activity
        : actor?.activity;
    final type = prepared
        ? activityTypeForAction(_pendingOrder!.action)!
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
    final hospitalVisit =
        recoveryContext(console)?.scene == RecoveryScene.hospital;
    final atVisitDestination =
        actual?.location != null &&
        actor?.activity.type == ActivityType.visit &&
        actor?.location == actual?.location &&
        console.awaitingInput &&
        console.screen != 'headquarters' &&
        console.screen != 'planning';
    final visitInProgress =
        !prepared &&
        !planning &&
        actual?.type == ActivityType.visit &&
        squad?.id == game.activeSquad?.id &&
        (hospitalVisit || atVisitDestination);
    final calculation = type == ActivityType.visit ? null : help.calculation;
    return OrganisationOrderCard(
      data: OrganisationOrderCardData(
        scope: type == ActivityType.visit
            ? 'Squad order · ${squad?.name ?? 'Squad'}'
            : actor?.name ?? squad?.name ?? 'Squad order',
        title: planning
            ? target == null
                  ? 'Visit a location'
                  : 'Visit ${target.getName()}'
            : !prepared && actual?.type == ActivityType.visit
            ? 'Visit ${actual?.location?.getName() ?? 'a location'}'
            : help.title,
        stateLabel: planning && (target == null || visit?.enabled != true)
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
        prepared: prepared,
        previousOrder:
            !prepared &&
                !activityFrame &&
                !planning &&
                actual?.type == ActivityType.none &&
                actor != null &&
                previousOrder != null
            ? _previousOrderButton(actor, previousOrder)
            : null,
        timing: visitInProgress
            ? hospitalVisit
                  ? 'Choose care or return to headquarters.'
                  : 'Use the location’s services or leave to finish this visit.'
            : help.timing,
        currentAssignment: prepared && actor != null
            ? 'Currently assigned: ${actual?.description ?? ActivityType.none.label}'
            : null,
        showAssignedOrderHint: activityFrame && !prepared && _showGuidance,
        juiceHint: actor != null && _showGuidance
            ? JuiceActivityHint(person: actor, activity: type)
            : null,
        travelNotice:
            !visitInProgress && type == ActivityType.visit && notices.isNotEmpty
            ? travelSuffix(notices).trim()
            : null,
        readinessSummary: type == ActivityType.visit
            ? SquadReadiness(members).summary
            : null,
        calculationResult: calculation == null
            ? null
            : estimatedIncome != null
            ? 'Estimated \$${estimatedIncome.round()}/day'
            : calculation.result,
        factors: type != ActivityType.visit && help.factors.isNotEmpty
            ? help.factors
            : null,
        cost:
            type != ActivityType.visit &&
                help.cost.isNotEmpty &&
                help.cost != 'No activity fee'
            ? help.cost
            : null,
        risk: type != ActivityType.visit && help.risk.isNotEmpty
            ? help.risk
            : null,
        unavailableReason: help.unavailableReason,
        destinationUnavailableReason:
            planning && visit != null && !visit.enabled && notices.isEmpty
            ? _locationDetails(visit).join(' · ')
            : null,
      ),
      scrollHeading: scrollHeading,
      onDetails: () => _showOrderMechanics(help),
      showConfirm: prepared || planning,
      onConfirm:
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
      showFinish: confirmation != null,
      onFinish: controller.busy ? null : () => _dispatch(confirmation!),
      showQueueVisit: !planning && !prepared && _selectedDestination != null,
      onQueueVisit: controller.canNavigate && !undercover && !_visitRouting
          ? _queueSelectedVisit
          : null,
      showCancel: prepared || activityFrame || planning,
      cancelPrepared: prepared || planning,
      onCancel: prepared
          ? () => setState(() => _pendingOrder = null)
          : controller.canNavigate && !_visitRouting
          ? planning
                ? _cancelVisit
                : controller.returnToHeadquarters
          : null,
    );
  }

  Widget _educationChoiceCard(Creature actor) {
    final back = console.actions
        .where((action) => action.key == 'Enter')
        .firstOrNull;
    return JournalSurface(
      key: const ValueKey('journal-job-card'),
      lined: true,
      padding: const EdgeInsets.all(9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            actor.name,
            key: const ValueKey('journal-required-order-actor'),
            style: JournalPalette.heading.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 5),
          const Text('Choose a skill', style: JournalPalette.heading),
          const Text(
            'Awaiting skill choice',
            key: ValueKey('journal-order-state'),
            style: JournalPalette.small,
          ),
          const SizedBox(height: 7),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                'The skill list is for ${actor.name}. Selecting a skill assigns the order. Cancel keeps ${actor.activity.description}. No time passes while choosing.',
                style: JournalPalette.small,
              ),
            ),
          ),
          if (back != null)
            TextButton.icon(
              key: const ValueKey('journal-cancel-skill-choice'),
              onPressed: !controller.busy && back.enabled
                  ? () => _dispatch(back)
                  : null,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Cancel skill choice'),
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

  Widget _poolPage() => OrganisationCrewPoolView(
    allocationPool: controller.allocationPool,
    members: members,
    sortSkill: _poolSort,
    selectedPersonId: _poolPerson,
    busy: controller.busy,
    blockReason: controller.allocationBlockReason,
    canRemoveMember: (personId) =>
        allocating && members.any((member) => member.id == personId),
    onSortChanged: (skill) => setState(() => _poolSort = skill),
    onSelectPerson: (personId) => setState(() => _poolPerson = personId),
    onTransfer: (personId) => unawaited(controller.assignPerson(personId)),
  );

  Widget _orderContext(bool narrow) {
    final showMap = planning || _ordersMap;
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
      _orderBrowseTaskStorageId = 'journal-tasks:$_group:$_categoryId';
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
    final revision = console.revision.value;
    return OrganisationOrderWorkspace(
      heading: planning
          ? 'Choose a destination'
          : _ordersMap
          ? 'Browse destinations'
          : 'Choose a task',
      showMap: showMap,
      onToggleMap: planning
          ? null
          : () {
              _settleOrderTaskScroll();
              setState(() => _ordersMap = !_ordersMap);
            },
      categories: [
        for (final category in visibleCategories)
          OrganisationOrderCategoryView(
            label: _clean(category.label),
            shortcut: category.key,
            selected: _categoryId == category.entityId,
            onSelect: category.enabled && !controller.busy
                ? () => _browseOrderCategory(category, revision: revision)
                : null,
          ),
      ],
      // Cached rows must keep their own storage identity until the new reader
      // arrives. A short cached category must not clamp another category's
      // restored offset, including through native web accessibility scrolling.
      taskStorageId: controller.busy && _orderBrowseTaskStorageId != null
          ? _orderBrowseTaskStorageId!
          : 'journal-tasks:$_group:$_categoryId',
      taskScrollController: _orderTaskScroll,
      tasks: [for (final task in tasks) _taskView(task, revision: revision)],
      leadingTask: _group == 3 ? _visitTaskChoice() : null,
      emptyMessage: controller.busy
          ? 'Opening current orders…'
          : 'Choose an order group to see its tasks.',
      map: _mapContext(),
    );
  }

  void _settleOrderTaskScroll() {
    if (_orderTaskScroll.hasClients) {
      // Ending an in-flight scroll persists its current offset to PageStorage
      // before a category/reader transition can dispose the scroll position.
      _orderTaskScroll.jumpTo(_orderTaskScroll.offset);
    }
  }

  // A rendered or cached choice is never authority for a later reader. Capture
  // its observed revision with the action before passing callbacks to views.
  bool _isCurrentOrderChoice(ConsoleAction action, {required int revision}) =>
      mounted &&
      !controller.busy &&
      activityFrame &&
      console.revision.value == revision &&
      console.actions.contains(action) &&
      action.enabled &&
      action.entityCategory == activityOrderFrame(console)!.actorId.toString();

  void _browseOrderCategory(ConsoleAction category, {required int revision}) {
    if (!_isCurrentOrderChoice(category, revision: revision)) return;
    _settleOrderTaskScroll();
    setState(() {
      _categoryId = category.entityId;
      _pendingOrder = null;
      _ordersMap = false;
    });
    unawaited(controller.browseCategory(category, revision: revision));
  }

  OrganisationOrderTaskView _taskView(
    ConsoleAction action, {
    required int revision,
  }) {
    final type = activityTypeForAction(action)!;
    final help = activityMechanics(type, actor: person);
    final prepared = hasPreparedOrder;
    return OrganisationOrderTaskView(
      taskId: action.entityId,
      type: type,
      label: _clean(action.label),
      shortcut: action.key,
      enabled: action.enabled,
      selected: prepared
          ? activityTypeForAction(_pendingOrder!.action) == type
          : person?.activity.type == type,
      prepared: prepared,
      tooltip:
          '${help.summary}\n${help.factors}\n${help.cost}\n${help.unavailableReason ?? ''}\n${help.calculation?.text ?? ''}',
      summary: help.summary,
      factors: help.factors,
      cost: help.cost,
      unavailableReason: help.unavailableReason,
      compact: _compact,
      showGuidance: _showGuidance,
      onPrepare: action.enabled && !controller.busy
          ? () {
              if (!_isCurrentOrderChoice(action, revision: revision)) return;
              setState(() {
                _pendingOrder = (action: action, revision: revision);
                _ordersMap = false;
              });
            }
          : null,
    );
  }

  Widget _visitTaskChoice() => Padding(
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
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
          minimumSize: const Size(44, 44),
          shape: const RoundedRectangleBorder(),
        ),
        child: const Row(
          children: [
            JournalOrderIcon(type: ActivityType.visit, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text('Visit a location', style: JournalPalette.body),
            ),
          ],
        ),
      ),
    ),
  );

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
        shortcut: planning ? action?.key : null,
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
        if (planning)
          const Text(
            'Letters browse · Enter queues visit · Esc cancels',
            key: ValueKey('journal-visit-keys'),
            style: JournalPalette.small,
          ),
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

  VoidCallback? get _queueSelectedVisit {
    final targetId = _selectedDestination?.idString;
    final squadId = squad?.id;
    final revision = console.revision.value;
    return targetId == null || squadId == null
        ? null
        : () {
            if (console.revision.value == revision &&
                _selectedDestination?.idString == targetId &&
                squad?.id == squadId) {
              unawaited(_queueMapVisit());
            }
          };
  }

  Future<void> _queueMapVisit() async {
    final targetId = _selectedDestination?.idString;
    final squadId = squad?.id;
    if (targetId == null ||
        squadId == null ||
        _visitRouting ||
        !controller.canNavigate) {
      return;
    }
    final request = _visitRequest + 1;
    await _prepareMapVisit();
    if (!mounted ||
        request != _visitRequest ||
        squad?.id != squadId ||
        _selectedDestination?.idString != targetId) {
      return;
    }
    final action = _visitAction;
    if (action?.enabled == true) await _confirmVisit(action!);
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
    final cityMapVisit = widget.section == 6 && !planning;
    final canPrepareVisit =
        controller.canNavigate &&
        !_visitRouting &&
        !undercover &&
        squad?.members.isNotEmpty == true &&
        controller.headquarters?.siege == null &&
        controller.headquartersAction('f')?.enabled == true;
    final queued =
        squad?.activity.type == ActivityType.visit &&
        squad?.activity.idString == target.idString;
    return Padding(
      padding: EdgeInsets.only(top: _compactMapText ? 4 : 7),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: _compactMapText || MediaQuery.sizeOf(context).height < 700
              ? cityMapVisit
                    ? 150
                    : 110
              : cityMapVisit
              ? 260
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
                if (cityMapVisit) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Squad: ${squad?.name ?? 'No squad selected'}',
                          key: const ValueKey('journal-city-map-squad'),
                          style: JournalPalette.small,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const ValueKey('journal-city-map-prepare-visit'),
                        onPressed: canPrepareVisit ? _queueSelectedVisit : null,
                        icon: const Icon(Icons.place_outlined, size: 17),
                        label: const Text('Queue visit · Enter'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
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
    if (_hasUnconfirmedDraft) return;
    if (!await controller.returnToHeadquarters() || !mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _hasUnconfirmedDraft) return;
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
    if (action != null && mounted && !_hasUnconfirmedDraft) {
      await controller.sendAction(action, revision: revision);
    }
  }

  VoidCallback? get _saveExitCommand {
    if (!controller.canNavigate) return null;
    final revision = console.revision.value;
    return () {
      if (mounted &&
          controller.canNavigate &&
          console.revision.value == revision) {
        unawaited(controller.openSection('x'));
      }
    };
  }

  _JournalFooterCommand _footerPrimaryCommand() {
    final unconfirmedDraft = _hasUnconfirmedDraft;
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
    final wait =
        controller.headquartersAction('w') ??
        (directHQ
            ? console.actions.where((action) => action.key == 'w').firstOrNull
            : null);
    final known = controller.headquarters != null || directHQ;
    final label = unconfirmedDraft
        ? 'Confirm or cancel draft'
        : continuing
        ? console.screen == 'full_map'
              ? 'Back to operation'
              : 'Continue'
        : known
        ? wait == null
              ? 'Day advance unavailable'
              : _clean(wait.label)
        : 'Return to planning';
    VoidCallback? onPressed;
    if (!unconfirmedDraft) {
      if (continuing && canContinue) {
        onPressed = () {
          // Retained callbacks must not answer a replacement source reader.
          if (console.revision.value != revision ||
              !console.awaitingInput ||
              console.textInput ||
              controller.busy ||
              _hasUnconfirmedDraft ||
              continueAction != null &&
                  !console.actions.contains(continueAction)) {
            return;
          }
          widget.onAction(continueAction?.key ?? 'Enter');
          _restoreInputFocus();
        };
      } else if (!continuing && controller.canNavigate) {
        if (!known) {
          onPressed = () {
            if (mounted &&
                controller.canNavigate &&
                console.revision.value == revision &&
                !_hasUnconfirmedDraft) {
              unawaited(controller.returnToHeadquarters());
            }
          };
        } else if (wait?.enabled == true) {
          onPressed = () async {
            if (!mounted ||
                !controller.canNavigate ||
                console.revision.value != revision ||
                _hasUnconfirmedDraft) {
              return;
            }
            await controller.openSection(wait!.key);
            _restoreInputFocus();
          };
        }
      }
    }
    return (
      label: label,
      shortcut: unconfirmedDraft
          ? null
          : continuing
          ? continueAction?.key ?? 'Enter'
          : _headquartersShortcut('w'),
      continuing: continuing,
      detailOwnsContinue: detailOwnsContinue,
      onPressed: onPressed,
    );
  }

  Widget _footer(bool narrow) {
    final unconfirmedDraft = _hasUnconfirmedDraft;
    final primary = _footerPrimaryCommand();
    final directHQ = console.screen == 'headquarters';
    final cancel =
        controller.headquartersAction('c') ??
        (directHQ
            ? console.actions.where((action) => action.key == 'c').firstOrNull
            : null);
    final dateFunds =
        '${game.day} ${getMonth(game.month).substring(0, 3)} ${game.year}  ·  \$${game.ledger.funds}';
    final utilities = <Widget>[
      IconButton(
        tooltip: 'More headquarters commands',
        key: const ValueKey('journal-more-commands'),
        onPressed: controller.canNavigate && !unconfirmedDraft
            ? _headquartersCommands
            : null,
        icon: const Icon(
          Icons.menu_book,
          color: JournalPalette.brassLight,
          size: 21,
        ),
      ),
      Expanded(
        child: Text(
          dateFunds,
          key: const ValueKey('journal-date-funds'),
          maxLines: 2,
          style: JournalPalette.small.copyWith(
            color: JournalPalette.card,
            height: widget.textScale > 1.1 ? 1 : 1.4,
          ),
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
      const JournalPreferencesButton(color: JournalPalette.brassLight),
      IconButton(
        tooltip: 'Switch readable / classic view',
        onPressed: widget.onClassic,
        icon: const Icon(
          Icons.terminal,
          color: JournalPalette.brassLight,
          size: 21,
        ),
      ),
    ];
    final commands = <Widget>[
      OutlinedButton.icon(
        key: const ValueKey('journal-save-exit'),
        onPressed: _saveExitCommand,
        style: OutlinedButton.styleFrom(
          backgroundColor: JournalPalette.page,
          minimumSize: const Size(44, 34),
          padding: const EdgeInsets.symmetric(horizontal: 9),
        ),
        icon: const Icon(Icons.save_outlined, size: 17),
        label: Tooltip(
          excludeFromSemantics: true,
          message:
              'At headquarters: X. '
              'Optional global shortcut: $journalSaveShortcut.',
          child: JournalCommandLabel(
            shortcut: _headquartersShortcut('x'),
            label: 'Save & exit',
          ),
        ),
      ),
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
      if (!primary.detailOwnsContinue)
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: narrow ? 230 : 340),
          child: Tooltip(
            message: primary.continuing
                ? primary.label
                : '${primary.label}. At headquarters: W. '
                      'Optional global shortcut: $journalAdvanceShortcut.',
            child: FilledButton.icon(
              key: const ValueKey('journal-advance-day'),
              onPressed: primary.onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: JournalPalette.binding,
                minimumSize: const Size(44, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              icon: Icon(
                primary.continuing ? Icons.arrow_forward : Icons.play_arrow,
                size: 18,
              ),
              label: primary.shortcut == null
                  ? Text(
                      primary.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Semantics(
                      label: primary.label,
                      hint:
                          'Keyboard shortcut: ${journalShortcutSpokenLabel(primary.shortcut!)}',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          JournalShortcutBadge(
                            shortcut: primary.shortcut!,
                            primary: true,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              primary.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
    ];
    return LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
        final theme = Theme.of(context);
        final saveTextStyle =
            OutlinedButtonTheme.of(context).style?.textStyle?.resolve({}) ??
            theme.textTheme.labelLarge!;
        final advanceTextStyle =
            FilledButtonTheme.of(context).style?.textStyle?.resolve({}) ??
            theme.textTheme.labelLarge!;
        final saveWidth =
            18 +
            17 +
            8 +
            _shortcutBadgeWidth(context, _headquartersShortcut('x')) +
            8 +
            _textWidth(context, 'Save & exit', saveTextStyle);
        final advanceWidth = primary.detailOwnsContinue
            ? 0.0
            : (20 +
                      18 +
                      8 +
                      (primary.shortcut == null
                          ? 0
                          : _shortcutBadgeWidth(context, primary.shortcut!) +
                                8) +
                      _textWidth(context, primary.label, advanceTextStyle))
                  .clamp(44.0, narrow ? 230.0 : 340.0);
        // Four utility buttons plus a readable two-line date/funds label.
        // Measure the command labels so wider fonts wrap before they overflow.
        final minimumUtilitiesWidth =
            4 * kMinInteractiveDimension +
            _textWidth(context, dateFunds, JournalPalette.small) / 2;
        final requiredWidth =
            minimumUtilitiesWidth +
            saveWidth +
            advanceWidth +
            (cancel?.enabled == true ? kMinInteractiveDimension : 0) +
            commands.length * 9;
        final stacked =
            bounds.maxWidth < 760 || bounds.maxWidth < requiredWidth;
        if (stacked) {
          final utilitiesHeight = bounds.maxWidth < 550
              ? (scale * 12 * 2.8).clamp(42.0, 70.0)
              : 42.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: utilitiesHeight,
                child: Row(children: utilities),
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: commands,
              ),
            ],
          );
        }
        return SizedBox(
          height: narrow ? 41 : 45,
          child: Row(
            children: [
              ...utilities,
              for (final command in commands) ...[
                const SizedBox(width: 9),
                command,
              ],
            ],
          ),
        );
      },
    );
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  double _shortcutBadgeWidth(BuildContext context, String shortcut) =>
      (_textWidth(
                context,
                journalShortcutLabel(shortcut),
                JournalShortcutBadge.textStyle,
              ) +
              12)
          .clamp(24.0, double.infinity);

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
