import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/movement_daily_plan.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'support/campaign_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampaignFixture fixture;
  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
  });
  setUp(() => fixture.restoreHeadquarters(console: Console()));

  test('whole movement uses actual availability and squad overrides without changing state or RNG', () {
    final idle = addTestCrewMember(name: 'Idle outside squads')
      ..activity = Activity.none();
    final assigned = addTestCrewMember(name: 'Remote worker')
      ..activity = Activity(ActivityType.donations)
      ..location = game.sites.firstWhere(
        (site) =>
            site != game.activeSafehouse &&
            site.type != SiteType.universityHospital &&
            site.type != SiteType.clinic &&
            !site.isPartOfTheJusticeSystem,
      );
    final hospital = addTestCrewMember(name: 'Hospital patient')
      ..location = game.sites.firstWhere(
        (site) => site.type == SiteType.universityHospital,
      );
    final custody = addTestCrewMember(name: 'In custody')
      ..location = game.sites.firstWhere(
        (site) => site.type == SiteType.policeStation,
      );
    final hiding = addTestCrewMember(name: 'No contact')..hidingDaysLeft = -1;
    final vacation = addTestCrewMember(name: 'On vacation')
      ..vacationDaysLeft = 3;
    final clinic = game.sites.firstWhere(
      (site) => site.type == SiteType.clinic,
    );
    final sleeper = addTestCrewMember(name: 'Clinic sleeper')
      ..sleeperAgent = true
      ..location = clinic
      ..workLocation = clinic
      ..activity = Activity.none();
    final hiddenSleeper = addTestCrewMember(name: 'Hidden sleeper')
      ..sleeperAgent = true
      ..hidingDaysLeft = 2;
    final dead = addTestCrewMember(name: 'Dead')..alive = false;
    final captive = addTestCrewMember(name: 'Captive')
      ..align = Alignment.conservative;
    final team = game.activeSquad!;
    team.activity = Activity(ActivityType.visit, idString: clinic.idString);
    team.members.first.activity = Activity(ActivityType.sellArt);
    final prospect = addTestCrewMember(name: 'Prospect');
    prospect.squad = null;
    game.pool.remove(prospect);
    final session = RecruitmentSession(prospect, idle)..rawEagerness = 4;
    game.recruitmentSessions
      ..clear()
      ..add(session);
    final before = campaignSnapshot();
    reseedRNG(seed: 48293);
    final rolls = List.generate(12, (_) => lcsRandom(100000));
    reseedRNG(seed: 48293);

    final plan = MovementDailyPlan.capture(
      currentPersonId: team.members.first.id,
    );
    MovementDailyPlanPerson row(int id) =>
        plan.people.singleWhere((row) => row.id == id);

    expect(row(idle.id).needsOrder, true);
    expect(row(assigned.id).assigned, true);
    for (final person in [hospital, custody, hiding, vacation, hiddenSleeper]) {
      expect(row(person.id).unavailable, true, reason: person.name);
      expect(row(person.id).orderUnavailableReason, isNotNull);
    }
    expect(sleeperOrderUnavailableReason(sleeper), isNull);
    expect(row(sleeper.id).unavailable, false);
    expect(row(sleeper.id).assigned, true);
    expect(row(sleeper.id).needsOrder, false);
    expect(row(sleeper.id).effectiveOrder, contains('sleeper standing order'));
    expect(row(team.members.first.id).queuedVisit, true);
    expect(
      row(team.members.first.id).personalOrder,
      ActivityType.sellArt.label,
    );
    expect(
      row(team.members.first.id).effectiveOrder,
      contains(team.activity.description),
    );
    expect(
      row(team.members.first.id).orderUnavailableReason,
      contains('joint operation'),
    );
    expect(row(team.members.first.id).assigned, true);
    expect(
      plan.people.any((row) => row.id == dead.id || row.id == captive.id),
      false,
    );
    expect(plan.people.map((row) => row.id).toSet().length, plan.people.length);
    expect(
      plan.count(DailyPlanFilter.all),
      plan.count(DailyPlanFilter.needsOrder) +
          plan.count(DailyPlanFilter.assigned) +
          plan.count(DailyPlanFilter.unavailable),
    );
    expect(row(idle.id).meetings.single.prospectName, prospect.name);
    expect(plan.meetings.single.canOfferJoin, idle.subordinatesLeft > 0);
    expect(campaignSnapshot(), before);
    expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
  });

  test('personal visits and field activity are never described as queued departures', () {
    final person = game.squad.first;
    final destination = game.sites.first;
    person.activity = Activity(
      ActivityType.visit,
      idString: destination.idString,
    );
    game.activeSquad!.activity = Activity.none();
    final personal = MovementDailyPlan.capture().people.singleWhere(
      (row) => row.id == person.id,
    );
    expect(personal.queuedVisit, false);
    expect(personal.squadOrder, isNull);
    expect(personal.effectiveOrder, person.activity.description);
    game.activeSquad!.activity = Activity(
      ActivityType.visit,
      idString: destination.idString,
    );
    game.mode = GameMode.site;
    final field = MovementDailyPlan.capture().people.singleWhere(
      (row) => row.id == person.id,
    );
    expect(field.queuedVisit, false);
    expect(field.squadOrder, isNull);
    game.mode = GameMode.base;
    final noPlanning = MovementDailyPlan.capture(planningContext: false).people
        .singleWhere((row) => row.id == person.id);
    expect(noPlanning.queuedVisit, false);
  });

  test('rows retain detached source facts and immutable collections', () {
    final person = game.squad.first;
    final plan = MovementDailyPlan.capture(currentPersonId: person.id);
    final row = plan.people.singleWhere((row) => row.id == person.id);
    final oldName = row.name;
    final oldOrder = row.personalOrder;
    final oldDate = plan.date;
    person
      ..name = 'Changed after capture'
      ..activity = Activity(ActivityType.donations);
    game.gameState.date = oldDate.add(const Duration(days: 1));
    expect(row.name, oldName);
    expect(row.personalOrder, oldOrder);
    expect(plan.date, oldDate);
    expect(plan.people.clear, throwsUnsupportedError);
    expect(row.meetings.clear, throwsUnsupportedError);
  });

  test('regular and sleeper availability track original predicates', () {
    final people = [
      addTestCrewMember(name: 'Active'),
      addTestCrewMember(name: 'Hiding')..hidingDaysLeft = -1,
      addTestCrewMember(name: 'Sleeper')..sleeperAgent = true,
      addTestCrewMember(name: 'Sleeper on vacation')
        ..sleeperAgent = true
        ..vacationDaysLeft = 1,
    ];
    final plan = MovementDailyPlan.capture();
    for (final person in people) {
      final row = plan.people.singleWhere((row) => row.id == person.id);
      final available = person.sleeperAgent
          ? sleeperOrderUnavailableReason(person) == null
          : personnelAvailableForOrders(person);
      expect(!row.unavailable, available, reason: person.name);
    }
  });
}
