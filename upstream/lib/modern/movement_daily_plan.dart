import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/injury_status.dart';
import 'package:lcs_new_age/modern/journal_recruitment.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';

enum DailyPlanFilter { all, needsOrder, assigned, unavailable }

String dailyPlanFilterLabel(DailyPlanFilter filter) => switch (filter) {
  DailyPlanFilter.all => 'All',
  DailyPlanFilter.needsOrder => 'Needs order',
  DailyPlanFilter.assigned => 'Assigned',
  DailyPlanFilter.unavailable => 'Unavailable',
};

/// Copied presentation facts. Holding a row never holds a gameplay command or
/// a mutable person, squad or activity across an input revision.
@immutable
class MovementDailyPlanPerson {
  MovementDailyPlanPerson._(
    Creature person, {
    required bool planningContext,
    required List<PendingRecruitmentMeeting> meetings,
  }) : id = person.id,
       name = person.name,
       status = personnelStatus(person),
       location = personnelLocation(person),
       personalOrder = person.activity.description,
       sleeper = person.sleeperAgent,
       squadId = person.squad?.id,
       squadName = person.squad?.name,
       squadOrder =
           planningContext &&
               person.squad != null &&
               person.squad!.activity.type != ActivityType.none
           ? person.squad!.activity.description
           : null,
       queuedVisit =
           planningContext && person.squad?.activity.type == ActivityType.visit,
       availabilityReason = _availabilityReason(person),
       needsOrder =
           !person.sleeperAgent &&
           personnelAvailableForOrders(person) &&
           person.activity.type == ActivityType.none &&
           (!planningContext ||
               person.squad == null ||
               person.squad!.activity.type == ActivityType.none),
       condition = crewInjurySummary(person)?.label ?? 'No recorded injuries',
       medicalDetails =
           crewInjurySummary(person)?.details ??
           '${person.blood}/${person.maxBlood} blood',
       meetings = List.unmodifiable(meetings);

  final int id;
  final String name, status, location, personalOrder;
  final bool sleeper, queuedVisit, needsOrder;
  final int? squadId;
  final String? squadName, squadOrder, availabilityReason;
  final String condition, medicalDetails;
  final List<PendingRecruitmentMeeting> meetings;

  bool get unavailable => availabilityReason != null;
  bool get assigned => !unavailable && !needsOrder;
  String get effectiveOrder => squadOrder == null
      ? sleeper
            ? '$personalOrder · sleeper standing order'
            : personalOrder
      : '${queuedVisit ? 'Queued squad visit' : 'Squad order'} · $squadOrder';

  String? get orderUnavailableReason =>
      availabilityReason ??
      (squadOrder == null
          ? null
          : 'This squad has a joint operation queued. View its squad and cancel departure before assigning individual daily orders.');

  bool matches(DailyPlanFilter filter) => switch (filter) {
    DailyPlanFilter.all => true,
    DailyPlanFilter.needsOrder => needsOrder,
    DailyPlanFilter.assigned => assigned,
    DailyPlanFilter.unavailable => unavailable,
  };

  bool contains(String query) => [
    name,
    status,
    location,
    personalOrder,
    effectiveOrder,
    squadName ?? '',
    for (final meeting in meetings) meeting.prospectName,
  ].any((text) => text.toLowerCase().contains(query));

  static String? _availabilityReason(Creature person) {
    if (person.sleeperAgent) return sleeperOrderUnavailableReason(person);
    if (personnelAvailableForOrders(person)) return null;
    return '${personnelStatus(person)}; daily orders are unavailable.';
  }
}

/// A movement-wide reading of existing orders, including people outside the
/// selected squad. Capture does not allocate work, advance time or run meetings.
@immutable
class MovementDailyPlan {
  factory MovementDailyPlan.capture({
    int? currentPersonId,
    bool planningContext = true,
  }) {
    final meetings = pendingRecruitmentMeetings();
    return MovementDailyPlan._(
      campaignId: game.gameState.uniqueGameId,
      date: game.date,
      currentPersonId: currentPersonId,
      meetingsPaused: game.disbanding,
      meetings: meetings,
      people: [
        for (final person in game.pool)
          if (person.alive && person.isLiberal)
            MovementDailyPlanPerson._(
              person,
              planningContext: planningContext && game.mode == GameMode.base,
              meetings: meetings
                  .where((meeting) => meeting.recruiterId == person.id)
                  .toList(),
            ),
      ],
    );
  }

  MovementDailyPlan._({
    required this.campaignId,
    required this.date,
    required this.currentPersonId,
    required this.meetingsPaused,
    required List<MovementDailyPlanPerson> people,
    required List<PendingRecruitmentMeeting> meetings,
  }) : people = List.unmodifiable(people),
       meetings = List.unmodifiable(meetings);

  final int campaignId;
  final DateTime date;
  final int? currentPersonId;
  final bool meetingsPaused;
  final List<MovementDailyPlanPerson> people;
  final List<PendingRecruitmentMeeting> meetings;

  int count(DailyPlanFilter filter) =>
      people.where((person) => person.matches(filter)).length;
}
