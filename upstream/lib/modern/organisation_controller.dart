import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';

/// Coordinates a single organisation journal with the original awaited menus.
///
/// Selection is local presentation state. Every game change goes through the
/// current, engine-authored action and original input reader. In particular no
/// squad, activity, save field, time, money or random state is written here.
class OrganisationController extends ChangeNotifier {
  OrganisationController({required this.console}) {
    console.revision.addListener(_frameChanged);
  }

  final Console console;
  bool _disposed = false;
  bool _busy = false;
  String? _message;
  int? _selectedSquadId;
  int? _selectedPersonId;

  bool get busy => _busy;
  String? get message => _message;
  int? get selectedSquadId =>
      assembly?.squadId ?? _selectedSquadId ?? game.activeSquad?.id;
  int? get selectedPersonId => _selectedPersonId;
  Squad? get selectedSquad =>
      game.squads.where((squad) => squad.id == selectedSquadId).firstOrNull;
  Creature? get selectedPerson =>
      game.pool.where((person) => person.id == _selectedPersonId).firstOrNull;
  SquadAllocationFrame? get assembly => squadAllocationFrame(console);
  int? get assemblySquadId => assembly?.squadId;
  bool get isNewAssembly => assembly?.isNew == true;
  bool get isHeadquarters => console.screen == 'headquarters';
  HeadquartersFrame? get headquarters => headquartersFrame(console);

  /// Actual source-authored W/F/C choice, or null when the current scope needs
  /// a fresh source HQ frame. A missing W must never be presented as Run day.
  ConsoleAction? headquartersAction(String key) =>
      console.eventMessage == null ? headquarters?.action(key) : null;
  bool get canNavigate =>
      console.eventMessage == null &&
      !_busy &&
      !_disposed &&
      game.mode == GameMode.base &&
      console.awaitingInput &&
      !console.textInput &&
      (isHeadquarters ||
          console.navigation != null ||
          assembly?.isNew == false);

  /// The exact allocation pool, including candidates on other original pages.
  List<Creature> get allocationPool {
    final ids = assembly?.personIds;
    if (ids == null) return const [];
    final people = {for (final person in game.pool) person.id: person};
    return List.unmodifiable(ids.map((id) => people[id]).nonNulls);
  }

  List<Creature> get allocationMembers {
    final ids = assembly?.memberIds;
    if (ids == null) return const [];
    final people = {for (final person in game.pool) person.id: person};
    return List.unmodifiable(ids.map((id) => people[id]).nonNulls);
  }

  String? allocationBlockReason(int personId) => assembly == null
      ? 'Open squad allocation to change its members.'
      : assembly!.unavailableReason(personId);

  void inspectPerson(int personId) {
    if (_disposed || !game.pool.any((person) => person.id == personId)) return;
    _selectedPersonId = personId;
    _notify();
  }

  void clearInspection() {
    if (_disposed) return;
    _selectedPersonId = null;
    _notify();
  }

  /// Selecting the already active squad never unexpectedly opens assembly.
  Future<bool> selectSquad(int squadId) => _run(() async {
    if (!_squadExists(squadId)) return _fail('That squad no longer exists.');
    if (!await _openOverview()) return false;
    if (game.activeSquad?.id != squadId) {
      final action = await _findSquad(squadId);
      if (action == null || !await _dispatch(action)) return false;
    }
    _selectedSquadId = squadId;
    return _toHeadquarters();
  });

  /// Null is an intentional request to create a new original-engine squad.
  Future<bool> openAllocation(int? squadId) =>
      _run(() => _openAllocation(squadId));

  Future<bool> _openAllocation(int? squadId) async {
    if (squadId != null && !_squadExists(squadId)) {
      return _fail('That squad no longer exists.');
    }
    final current = assembly;
    if (current != null &&
        ((squadId == null && current.isNew) || current.squadId == squadId)) {
      return true;
    }
    if (!await _openOverview()) return false;
    if (squadId == null) {
      final action = _action('z');
      if (action == null || !await _dispatch(action)) return false;
    } else {
      if (game.activeSquad?.id != squadId) {
        final select = await _findSquad(squadId);
        if (select == null || !await _dispatch(select)) return false;
      }
      final edit = await _findSquad(squadId);
      if (edit == null || !await _dispatch(edit)) return false;
      _selectedSquadId = squadId;
    }
    return assembly != null ||
        _fail('The squad allocation prompt is unavailable.');
  }

  /// Allocates/removes one person through the exact displayed original action.
  /// This can be used by a click, keyboard selection or drag-and-drop target.
  Future<bool> assignPerson(int personId) => _run(() async {
    if (!game.pool.any((person) => person.id == personId)) {
      return _fail('That person is no longer in the organisation.');
    }
    if (assembly == null) {
      final squadId = selectedSquadId;
      if (squadId == null) return _fail('Select a squad first.');
      if (!await _openAllocation(squadId)) return false;
    }
    final frame = assembly!;
    final reason = frame.unavailableReason(personId);
    if (reason != null) return _fail(reason);
    final index = frame.personIds.indexOf(personId);
    if (!await _allocationPage(index ~/ 19)) return false;
    final action = _entityAction('person', personId.toString());
    if (action == null || !action.enabled) {
      return _fail('That person is not available in this allocation prompt.');
    }
    if (!await _dispatch(action)) return false;
    _selectedPersonId = personId;
    return true;
  });

  /// Explicit Done is also allowed for new squads; the original naming prompt
  /// remains visible and is never filled or dismissed by this controller.
  Future<bool> finishAllocation() => _run(() async {
    if (assembly == null) return _fail('No squad allocation is open.');
    final isNew = assembly!.isNew;
    final action = _entityAction('squad-ready', assembly!.squadId.toString());
    if (action == null) return _fail('The allocation prompt has changed.');
    if (!await _dispatch(action)) return false;
    return isNew ? true : _toHeadquarters();
  });

  Future<bool> openOrders(int personId) => _run(() async {
    final person = game.pool.where((p) => p.id == personId).firstOrNull;
    if (person == null) {
      return _fail('That person is no longer in the organisation.');
    }
    if (!person.alive) {
      return _fail('A deceased person cannot take daily orders.');
    }
    if (!person.sleeperAgent && !person.isActiveLiberal) {
      return _fail(
        'Daily orders are available to active crew; this person is away, in care or in custody.',
      );
    }
    // Leave an unconfirmed visit picker even when a queued squad order blocks
    // this request. The journal must show the actual queued order, not a stale
    // destination confirmation screen.
    if (!await _toHeadquarters()) return false;
    if (!person.sleeperAgent &&
        person.squad != null &&
        person.squad!.activity.type != ActivityType.none) {
      return _fail(
        'This squad has a joint operation queued. Cancel its departure before assigning individual daily orders.',
      );
    }
    final action = _action(person.sleeperAgent ? 'b' : 'a');
    if (action == null || !action.enabled || !await _dispatch(action)) {
      return _fail('Daily orders are not available for this person right now.');
    }
    final personAction = await _findPersonInOrderList(personId);
    if (personAction == null || !await _dispatch(personAction)) return false;
    _selectedPersonId = personId;
    return true;
  });

  /// Other journal tabs retain their original HQ command and all source rules.
  Future<bool> openSection(String sourceHeadquartersKey) => _run(() async {
    if (!await _toHeadquarters()) return false;
    final action = _action(sourceHeadquartersKey);
    if (action == null || !action.enabled) {
      return _fail('That section is unavailable in the current game state.');
    }
    return _dispatch(action);
  });

  Future<bool> returnToHeadquarters() => _run(_toHeadquarters);

  /// Opening an order category is presentation-only. Its actual original
  /// letter command is deliberately reserved for explicit legacy input.
  Future<bool> browseCategory(ConsoleAction action, {required int revision}) =>
      _run(() async {
        final frame = activityOrderFrame(console);
        if (game.mode != GameMode.base ||
            frame == null ||
            console.revision.value != revision ||
            !console.actions.contains(action) ||
            !action.enabled ||
            action.entityCategory != frame.actorId.toString() ||
            !const {
              'activity-category',
              'sleeper-category',
              'sleeper-category-selected',
            }.contains(action.entityType)) {
          return _fail(
            'This order category has changed; choose from the current screen.',
          );
        }
        final preview = frame.categoryPreviewCommands[action.key];
        if (preview == null) return _fail('That category cannot be previewed.');
        return _dispatchKey(preview);
      });

  /// Confirm applies exactly one staged source task, then closes only its own
  /// ordinary confirmation menu. Required skill/crafting/prisoner/name choices
  /// remain explicit and are never filled or dismissed automatically.
  Future<bool> commitOrder(ConsoleAction action, {required int revision}) =>
      _run(() async {
        final frame = activityOrderFrame(console);
        if (game.mode != GameMode.base ||
            frame == null ||
            console.revision.value != revision ||
            !console.actions.contains(action) ||
            !action.enabled ||
            action.entityCategory != frame.actorId.toString() ||
            action.entityType !=
                (frame.sleeper ? 'sleeper-activity' : 'activity')) {
          return _fail(
            'This order has changed; choose from the current screen.',
          );
        }
        if (!await _dispatch(action)) return false;
        final next = activityOrderFrame(console);
        if (next?.actorId != frame.actorId || next?.sleeper != frame.sleeper) {
          return true;
        }
        final confirm = console.actions
            .where(
              (candidate) =>
                  candidate.entityType ==
                      (frame.sleeper
                          ? 'sleeper-activity-confirm'
                          : 'activity-confirm') &&
                  candidate.entityCategory == frame.actorId.toString(),
            )
            .firstOrNull;
        if (confirm == null || !confirm.enabled || !await _dispatch(confirm)) {
          return false;
        }
        return _toHeadquarters();
      });

  /// A captured widget callback may never dispatch after its frame is gone.
  Future<bool> sendAction(ConsoleAction action, {required int revision}) =>
      _run(() async {
        if (console.revision.value != revision) {
          return _fail(
            'This choice has changed; choose from the current screen.',
          );
        }
        return _dispatch(action);
      });

  Future<bool> _openOverview() async {
    if (organisationOverviewFrame(console) != null) return true;
    if (!await _toHeadquarters()) return false;
    final review = _action('r');
    if (review == null || !review.enabled || !await _dispatch(review)) {
      return _fail('The organisation is unavailable right now.');
    }
    return organisationOverviewFrame(console) != null ||
        _fail('Finish the current choice before opening the organisation.');
  }

  Future<bool> _toHeadquarters() async {
    if (game.mode != GameMode.base) {
      return _fail(
        'Finish or leave the current site before changing organisation orders.',
      );
    }
    for (var step = 0; step < 40; step++) {
      if (!await _ready()) return false;
      if (console.textInput) {
        return _fail(
          'Complete the current name or entry before changing sections.',
        );
      }
      if (isHeadquarters) return true;
      final allocation = assembly;
      if (allocation != null) {
        if (allocation.isNew) {
          return _fail(
            'Finish this new squad and name it before changing sections.',
          );
        }
        final ready = _entityAction(
          'squad-ready',
          allocation.squadId.toString(),
        );
        if (ready == null || !await _dispatch(ready)) return false;
        continue;
      }
      final navigation = console.navigation;
      if (navigation == null) {
        return _fail('Finish the current choice before changing sections.');
      }
      if (!await _dispatchKey(navigation.backKey)) return false;
    }
    return _fail('The current menu could not be left safely.');
  }

  Future<ConsoleAction?> _findSquad(int squadId) async {
    final frame = organisationOverviewFrame(console);
    if (frame == null) {
      _fail('Open the organisation before selecting a squad.');
      return null;
    }
    final index = frame.squadIds.indexOf(squadId);
    if (index < 0) {
      _fail('That squad no longer exists.');
      return null;
    }
    final targetPage = index ~/ 19;
    for (var step = 0; step < 256; step++) {
      final current = organisationOverviewFrame(console);
      if (current == null) break;
      if (current.page == targetPage) {
        final action = _entityAction('squad', squadId.toString());
        if (action != null) return action;
        break;
      }
      // The original asset-review handler interprets its two printable page
      // keys in reverse. Dispatch the key it actually handles; do not infer a
      // command from the displayed Previous/Next label or rewrite its rules.
      final page = _pageAction(forward: current.page > targetPage);
      if (page == null || !await _dispatch(page)) break;
      if (organisationOverviewFrame(console)?.page == current.page) break;
    }
    _fail('That squad is unavailable on the current organisation page.');
    return null;
  }

  Future<bool> _allocationPage(int targetPage) async {
    for (var step = 0; step < 256; step++) {
      final current = assembly;
      if (current == null) return _fail('The allocation prompt has changed.');
      if (current.page == targetPage) return true;
      final page = _pageAction(forward: current.page < targetPage);
      if (page == null || !await _dispatch(page)) return false;
      if (assembly?.page == current.page) break;
    }
    return _fail('That person is unavailable on the current allocation page.');
  }

  Future<ConsoleAction?> _findPersonInOrderList(int personId) async {
    final visited = <String>{};
    for (var step = 0; step < 256; step++) {
      if (!console.awaitingInput ||
          console.navigation?.section != 'assignments' ||
          console.textInput) {
        break;
      }
      final action = _entityAction('person', personId.toString());
      if (action != null && action.enabled) return action;
      final signature = console.actions
          .where((a) => a.entityType == 'person')
          .map((a) => a.entityId)
          .join(',');
      if (signature.isEmpty || !visited.add(signature)) break;
      final page = _pageAction(forward: true);
      if (page == null || !await _dispatch(page)) break;
    }
    _fail('The original daily-order list does not include this person.');
    return null;
  }

  ConsoleAction? _action(String key) => console.actions
      .where((action) => action.key == normalizeConsoleKey(key))
      .firstOrNull;

  ConsoleAction? _entityAction(String type, String id) => console.actions
      .where((action) => action.entityType == type && action.entityId == id)
      .firstOrNull;

  ConsoleAction? _pageAction({required bool forward}) => console.actions
      .where(
        (action) =>
            (forward
                    ? const {']', '.', 'PageDown'}
                    : const {'[', ';', ',', 'PageUp'})
                .contains(action.key),
      )
      .firstOrNull;

  bool _squadExists(int id) => game.squads.any((squad) => squad.id == id);

  Future<bool> _dispatch(ConsoleAction action) async {
    if (!action.enabled || !console.actions.contains(action)) {
      return _fail('This choice is no longer available.');
    }
    return _dispatchKey(action.key);
  }

  Future<bool> _dispatchKey(String key) async {
    if (_disposed || !console.awaitingInput || console.textInput) {
      return _fail('Wait for the current choice to finish.');
    }
    final revision = console.revision.value;
    if (!console.sendInput(key)) {
      return _fail('The current choice is already being processed.');
    }
    for (var wait = 0; wait < 500; wait++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      if (_disposed) return false;
      if (console.revision.value != revision && console.awaitingInput) {
        return true;
      }
    }
    return _fail('The game is processing this choice.');
  }

  Future<bool> _ready() async {
    for (var wait = 0; wait < 500; wait++) {
      if (_disposed) return false;
      if (console.awaitingInput && console.lastKey == null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    return _fail('The game is processing the current choice.');
  }

  Future<bool> _run(Future<bool> Function() command) async {
    if (_disposed || _busy) return false;
    _busy = true;
    _message = null;
    _notify();
    try {
      return await command();
    } finally {
      _busy = false;
      _notify();
    }
  }

  bool _fail(String message) {
    _message = message;
    return false;
  }

  void _frameChanged() {
    // Keyboard/legacy Next Squad commands use the same source state. A cached
    // tab selection must never point at a different team from the one that
    // will receive the engine's equipment and operation commands.
    if (isHeadquarters || organisationOverviewFrame(console) != null) {
      _selectedSquadId = game.activeSquad?.id;
    }
    if (_selectedSquadId != null && !_squadExists(_selectedSquadId!)) {
      _selectedSquadId = null;
    }
    if (_selectedPersonId != null &&
        !game.pool.any((person) => person.id == _selectedPersonId)) {
      _selectedPersonId = null;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    console.revision.removeListener(_frameChanged);
    _disposed = true;
    super.dispose();
  }
}
