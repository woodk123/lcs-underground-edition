import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;

/// The exact pool and team exposed by one original squad-assembly await.
///
/// The source handler supplies this data; presentation code must still dispatch
/// the current action to that handler to change membership. This also retains
/// the handler's fixed pool after the last current member has been removed.
@immutable
class SquadAllocationFrame {
  SquadAllocationFrame({
    required this.squadId,
    required this.squadName,
    required this.isNew,
    required this.page,
    required this.readyAction,
    required List<int> personIds,
    required List<int> memberIds,
    required Map<int, String> unavailableReasons,
  }) : personIds = List.unmodifiable(personIds),
       memberIds = List.unmodifiable(memberIds),
       unavailableReasons = Map.unmodifiable(unavailableReasons);

  final int squadId;
  final String squadName;
  final bool isNew;
  final int page;
  final ConsoleAction readyAction;
  final List<int> personIds;
  final List<int> memberIds;
  final Map<int, String> unavailableReasons;

  bool canToggle(int personId) =>
      personIds.contains(personId) && !unavailableReasons.containsKey(personId);

  String? unavailableReason(int personId) => personIds.contains(personId)
      ? unavailableReasons[personId]
      : 'This person is not in the squad’s available pool at this location.';
}

@immutable
class OrganisationOverviewFrame {
  OrganisationOverviewFrame({required this.page, required List<int> squadIds})
    : squadIds = List.unmodifiable(squadIds);

  final int page;
  final List<int> squadIds;
}

/// A task's display facts, authored by the original order reader.
@immutable
class ActivityOrderTask {
  const ActivityOrderTask(this.typeId, this.label, {this.enabled = true});

  final String typeId, label;
  final bool enabled;
}

@immutable
class ActivityOrderCategory {
  ActivityOrderCategory(
    this.id,
    this.key,
    this.label,
    Iterable<ActivityOrderTask> tasks,
  ) : tasks = List.unmodifiable(tasks);

  final String id, key, label;
  final List<ActivityOrderTask> tasks;
}

/// One actor's original daily-order menu and its read-only category previews.
///
/// Original letter keys retain their original immediate assignment behavior.
/// The private preview commands are handled only by this exact source await;
/// they change its local display category and never execute an activity.
@immutable
class ActivityOrderFrame {
  ActivityOrderFrame({
    required this.actorId,
    required this.sleeper,
    required this.confirmation,
    required this.navigation,
    required Iterable<String> categoryKeys,
    this.selectedCategoryKey,
    Iterable<ActivityOrderCategory> catalog = const [],
  }) : catalog = List.unmodifiable(catalog),
       categoryPreviewCommands = Map.unmodifiable({
         for (final key in categoryKeys)
           key: String.fromCharCode(0xE100 + key.codeUnitAt(0)),
       });

  final int actorId;
  final bool sleeper;
  final ConsoleAction confirmation;
  final ConsoleNavigation navigation;
  final String? selectedCategoryKey;
  final Map<String, String> categoryPreviewCommands;

  /// Source-authored display facts only; search must resolve a fresh action
  /// through the matching category before preparing or executing a task.
  final List<ActivityOrderCategory> catalog;

  int? categoryCodeForPreview(int command) {
    for (final entry in categoryPreviewCommands.entries) {
      if (entry.value.codeUnitAt(0) == command) return entry.key.codeUnitAt(0);
    }
    return null;
  }
}

typedef _HeadquartersScope = ({
  Object campaign,
  int? squadId,
  int? safehouseId,
  String? locationId,
  DateTime date,
  String memberIds,
  String selectedOrder,
  String queuedOrders,
  String locationSiege,
  String attacks,
});

_HeadquartersScope _currentHeadquartersScope() {
  final squad = game.activeSquad;
  final location = squad?.site ?? game.activeSafehouse;
  return (
    campaign: game.gameState,
    squadId: squad?.id,
    safehouseId: game.activeSafehouse?.id,
    locationId: location?.idString,
    date: game.date,
    memberIds: squad?.members.map((person) => person.id).join(',') ?? '',
    selectedOrder: jsonEncode(squad?.activity.toJson()),
    queuedOrders: game.squads
        .map((team) => '${team.id}:${team.activity.type.name}')
        .join(','),
    locationSiege: location == null
        ? ''
        : '${location.siege.activeSiegeType.name}:${location.siege.underAttack}',
    attacks: game.pool
        .where((person) => person.site?.siege.underAttack == true)
        .map((person) => '${person.id}:${person.locationId}')
        .join(','),
  );
}

/// Read-only siege information authored alongside one original HQ reader.
@immutable
class SiegeBriefing {
  SiegeBriefing({
    required this.location,
    required this.title,
    required this.note,
    required Iterable<String> statusLines,
  }) : statusLines = List.unmodifiable(statusLines);

  final String location, title, note;
  final List<String> statusLines;
}

/// The exact W/F/G/C capabilities authored by the last matching HQ frame.
///
/// Its scope is a fingerprint, never an eligibility calculation. A changed
/// team, site, date, roster, queued order or siege invalidates the snapshot; UI
/// must return to the source HQ to refresh rather than guess a new command.
@immutable
class HeadquartersFrame {
  HeadquartersFrame.capture(Iterable<ConsoleAction> actions, {this.siege})
    : _scope = _currentHeadquartersScope(),
      actions = List.unmodifiable(
        actions.where(
          (action) => const {'w', 'f', 'g', 'c'}.contains(action.key),
        ),
      );

  final _HeadquartersScope _scope;
  final List<ConsoleAction> actions;
  final SiegeBriefing? siege;
  int? get squadId => _scope.squadId;
  String? get locationId => _scope.locationId;
  DateTime get date => _scope.date;

  bool get matchesCurrentGame =>
      game.mode == GameMode.base && _scope == _currentHeadquartersScope();

  ConsoleAction? action(String key) => actions
      .where((action) => action.key == normalizeConsoleKey(key))
      .firstOrNull;
}

final _allocationFrames = Expando<SquadAllocationFrame>();
final _overviewFrames = Expando<OrganisationOverviewFrame>();
final _activityFrames = Expando<ActivityOrderFrame>();
final _headquartersFrames = Expando<HeadquartersFrame>();

void describeSquadAllocation(Console console, SquadAllocationFrame frame) =>
    _allocationFrames[console] = frame;

void describeOrganisationOverview(
  Console console,
  OrganisationOverviewFrame frame,
) => _overviewFrames[console] = frame;

void describeActivityOrders(Console console, ActivityOrderFrame frame) =>
    _activityFrames[console] = frame;

void describeHeadquarters(Console console, HeadquartersFrame frame) =>
    _headquartersFrames[console] = frame;

HeadquartersFrame? headquartersFrame(Console console) {
  final frame = _headquartersFrames[console];
  return frame?.matchesCurrentGame == true ? frame : null;
}

/// Consumed, nested and text-entry awaits never inherit a management frame.
SquadAllocationFrame? squadAllocationFrame(Console console) {
  final frame = _allocationFrames[console];
  return game.mode == GameMode.base &&
          console.awaitingInput &&
          !console.textInput &&
          console.screen == 'squad-assembly' &&
          frame != null &&
          console.actions.contains(frame.readyAction) &&
          frame.readyAction.entityType == 'squad-ready' &&
          frame.readyAction.entityId == frame.squadId.toString()
      ? frame
      : null;
}

OrganisationOverviewFrame? organisationOverviewFrame(Console console) =>
    console.awaitingInput &&
        !console.textInput &&
        console.screen == 'organisation'
    ? _overviewFrames[console]
    : null;

ActivityOrderFrame? activityOrderFrame(Console console) {
  final frame = _activityFrames[console];
  return game.mode == GameMode.base &&
          console.awaitingInput &&
          !console.textInput &&
          console.screen == 'activity-orders' &&
          frame != null &&
          identical(console.navigation, frame.navigation) &&
          console.actions.contains(frame.confirmation) &&
          frame.confirmation.entityCategory == frame.actorId.toString() &&
          frame.confirmation.entityType ==
              (frame.sleeper ? 'sleeper-activity-confirm' : 'activity-confirm')
      ? frame
      : null;
}
